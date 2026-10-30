#!/usr/bin/env bash
set -eu -o pipefail

chrome_modern_target=chrome_public_bundle
webview_target=system_webview_apk
all=all

if [[ -f src/chrome/VERSION ]]; then
    chromium_version=$(paste -sd. <(cut -d= -f2 src/chrome/VERSION))
else
    chromium_version=$(grep -m1 -o '[0-9]\+\(\.[0-9]\+\)\{3\}' Vanadium/args.gn)
fi
chromium_revision=1
chromium_android_revision=1

# Show env
pwd
whoami
echo $PATH
echo $HOME

# Argument parser from https://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash/29754866#29754866
! getopt --test > /dev/null
if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
    echo 'I’m sorry, `getopt --test` failed in this environment.'
    exit 1
fi

OPTIONS=dlipra:t:
LONGOPTS=debug,local-sdk,install-deps,prepare-only,resume,arch:,target:

! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    exit 2
fi
eval set -- "$PARSED"

ARCH=- TARGET=- DEBUG=n LOCAL_SDK=n INSTALL_DEPS=n PREPARE_ONLY=n RESUME=n

while true; do
    case "$1" in
        -d|--debug)
            DEBUG=y
            shift
            ;;
        -l|--local-sdk)
            LOCAL_SDK=y
            shift
            ;;
        -i|--install-deps)
            INSTALL_DEPS=y
            shift
            ;;
        -p|--prepare-only)
            PREPARE_ONLY=y
            shift
            ;;
        -r|--resume)
            RESUME=y
            shift
            ;;
        -a|--arch)
            ARCH="$2"
            shift 2
            ;;
        -t|--target)
            TARGET="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Programming error"
            exit 3
            ;;
    esac
done

if [[ "$ARCH" != "arm64" ]] && [[ "$ARCH" != "arm" ]] && [[ "$ARCH" != "x86" ]]; then
    echo "Wrong architecture"
    exit 4
fi

if [[ "$TARGET" != "chrome_modern_target" ]] && [[ "$TARGET" != "webview_target" ]] && [[ "$TARGET" != "all" ]]; then
    echo "Wrong target"
    exit 5
fi

echo "arch: $ARCH, target: $TARGET, debug: $DEBUG, local sdk: $LOCAL_SDK"

path_modified=false

function prepare_repos {
  git config --global http.lowSpeedLimit 1000
  git config --global http.lowSpeedTime 900

  declare -a arr=("depot_tools" "src" ".cipd")
  for dname in "${arr[@]}"
  do
    if [[ -d "$dname" ]]
    then
      echo "Removing $dname"
      rm -rf "$dname"
    fi
  done

  path_modified=false

  CHROMIUM_SOURCE="${CHROMIUM_SOURCE:-https://chromium.googlesource.com/chromium/src.git}"
  mkdir -p src
  pushd src
  git init -q
  git remote add origin "${CHROMIUM_SOURCE}" 2>/dev/null || git remote set-url origin "${CHROMIUM_SOURCE}"
  case "${CHROMIUM_SOURCE}" in
    *github.com*) _alt="https://chromium.googlesource.com/chromium/src.git" ;;
    *)            _alt="https://github.com/chromium/chromium.git" ;;
  esac
  git fetch --depth 1 --no-tags "${CHROMIUM_SOURCE}" \
      "+refs/tags/${chromium_version}:refs/tags/${chromium_version}" \
    || { echo "primary source failed, falling back to ${_alt}"
         git remote set-url origin "${_alt}"
         git fetch --depth 1 --no-tags "${_alt}" \
             "+refs/tags/${chromium_version}:refs/tags/${chromium_version}"; } \
    || { popd; return 1; }
  git checkout -q "${chromium_version}" || { popd; return 1; }
  popd

  ## Fetch depot-tools
  depot_tools_commit=$(grep 'depot_tools.git' src/DEPS | cut -d\' -f8)
  mkdir -p depot_tools
  pushd depot_tools
  git init
  git remote add origin https://chromium.googlesource.com/chromium/tools/depot_tools.git
  git fetch --depth 1 --no-tags origin "${depot_tools_commit}" || return $?
  git reset --hard FETCH_HEAD
  popd

  OLD_PATH=$PATH
  export PATH="$(pwd -P)/depot_tools:$PATH"
  export PYTHONPATH="$(pwd -P)/depot_tools${PYTHONPATH:+:$PYTHONPATH}"
  ensure_bootstrap # need to initialize depot_tools
  path_modified=true
  rm -rf src/third_party/depot_tools
  ln -s "$(pwd -P)/depot_tools" src/third_party/depot_tools

  git config --global http.lowSpeedTime 120
  DEPOT_TOOLS_UPDATE=0 gclient sync -D --no-history --nohooks --shallow
  _sync_rc=$?
  git config --global http.lowSpeedTime 900
  [ $_sync_rc -eq 0 ] || return $_sync_rc
}

function reverse_change {
  if [ "$path_modified" = true ] ; then
    export PATH=$OLD_PATH
    path_modified=false
  fi
}

output_folder="out/Default"
uc_keystore="$PWD/../uc_keystore/uc-release-key.keystore"
stamp_file="src/${output_folder}/.build-stamp"

build_fingerprint() {
  printf '%s\n' "${chromium_version}-${chromium_android_revision}"
  # ( find Vanadium/patches -name '*.patch' -type f | sort | xargs cat ) | sha256sum | cut -d' ' -f1
  cat build.sh patch.sh .gclient args.gn 2>/dev/null | sha256sum | cut -d' ' -f1
}

if [ "$RESUME" = y ]; then
    if [ ! -f "$stamp_file" ] || [ ! -f "src/out/Default/args.gn" ] || [ ! -d "src/third_party" ]; then
        echo "FATAL: --resume but the build tree is incomplete."
        echo "  stamp:      $([ -f "$stamp_file" ] && echo present || echo MISSING)"
        echo "  args.gn:    $([ -f src/out/Default/args.gn ] && echo present || echo MISSING)"
        echo "  src tree:   $([ -d src/third_party ] && echo present || echo MISSING)"
        echo "  If these vanished between runs, actions/checkout wiped them: its default"
        echo "  clean:true runs 'git clean -ffdx', and -x deletes gitignored paths like /src/."
        echo "  The workflow sets clean: false to prevent this. Start a clean build (resume: no)."
        exit 7
    fi
    want=$(build_fingerprint | sha256sum | cut -d' ' -f1)
    have=$(grep -m1 '^fingerprint ' "$stamp_file" | awk '{print $2}')
    if [ "$want" != "$have" ]; then
        echo "FATAL: inputs changed since this build was stamped - resuming would mix old and new objects."
        echo "  stamped:  $have"
        echo "  current:  $want"
        echo "  Start a clean build instead (resume: no)."
        exit 8
    fi
    echo "=== resuming verified build ==="
    cat "$stamp_file"
    printf 'session    %s  run %s  resumed at %s objects\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${GITHUB_RUN_NUMBER:-local}" \
        "$(find src/out/Default -name '*.o' 2>/dev/null | wc -l)" >> "$stamp_file"
else
    # Run preparation
    for i in $(seq 1 10); do prepare_repos && s=0 && break || s=$? && reverse_change && sleep 120; done; (exit $s)
fi

if [ "$INSTALL_DEPS" = y ]; then
    export DEBIAN_FRONTEND=noninteractive
    if ! command -v apt-get >/dev/null 2>&1; then
        echo "FATAL: --install-deps needs apt. Chromium's own build/install-build-deps.py"
        echo "  installs via apt-get and supports Debian/Ubuntu only, so there is nothing"
        echo "  to call on this system."
        echo "  Install the packages listed in README.md by hand (dnf/pacman lists are there),"
        echo "  then run again without --install-deps. Everything after this step is distro-agnostic."
        exit 9
    fi
    if [ "$(id -u)" -ne 0 ] && ! sudo -n true 2>/dev/null; then
        echo "FATAL: --install-deps needs root or passwordless sudo, or it will hang on a password prompt."
        echo "  run it by hand:  ( cd src && ./build/install-build-deps.sh --no-prompt --android --unsupported )"
        echo "  or allow apt:    echo 'USER ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/dpkg' | sudo tee /etc/sudoers.d/chromium-deps"
        exit 6
    fi
    apt-get -qq install -y lsb-release file 2>/dev/null \
        || sudo -n apt-get -qq install -y lsb-release file
    ( cd src && ./build/install-build-deps.sh --no-prompt --android --unsupported ) || exit $?
fi

dependencies=(patch ccache zip python3)
missing=()
for dependency in "${dependencies[@]}"; do
    command -v "$dependency" >/dev/null 2>&1 || missing+=("$dependency")
done
if [ ${#missing[@]} -ne 0 ]; then
    echo "FATAL: missing required tools: ${missing[*]}"
    echo "  Install them with your package manager (per-distro lists are in README.md)."
    exit 10
fi

if [ "$RESUME" != y ]; then
  git config --global user.name 'github-actions[bot]'
  git config --global user.email 'github-actions[bot]@users.noreply.github.com'
  # https://grapheneos.org/build#browser-and-webview
  rm -rf Vanadium/patches/*trichrome-{apk-build-targets,browser-apk-targets}.patch
  rm -rf Vanadium/patches/*{detailed,supported}-language*.patch
  rm -rf Vanadium/patches/*javascript-optimizer-{site-setting,settings-UI}.patch
  rm -rf Vanadium/patches/*component-updates.patch
  rm -rf Vanadium/patches/*{pdf,PDF,for-content-public,toolbar-button,configs-from-config-app,config-app-parsing,new-tab-card,predictive-back}*.patch

  pushd src
  git am --whitespace=nowarn --keep-non-patch ../Vanadium/patches/*.patch
  source ../patch.sh

  gclient runhooks

  mkdir -p "${output_folder}"
  cp ../args.gn "${output_folder}"/args.gn
  sed -i '/^[[:space:]]*target_cpu/d' "${output_folder}"/args.gn
  printf '\ntarget_cpu="'"$ARCH"'"\n' >> "${output_folder}"/args.gn

  gn gen "${output_folder}"
  popd

  { echo "build      $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "version    ${chromium_version}-${chromium_android_revision}"
    echo "commit     $(git rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "fingerprint $(build_fingerprint | sha256sum | cut -d' ' -f1)"
    echo "session    $(date -u +%Y-%m-%dT%H:%M:%SZ)  run ${GITHUB_RUN_NUMBER:-local}  clean start"
  } > "$stamp_file"
fi

if [ "$PREPARE_ONLY" = y ]; then
    cat "$stamp_file"
    echo "prepare complete, stopping before ninja"
    exit 0
fi

## Build
export PATH="$(pwd -P)/depot_tools:$PATH"

autoninja_build() {
  local dir="$1"
  shift

  # autoninja 会自动探测 args.gn 并动态计算最合理的并发数与后端调度 Siso/Ninja; 仅在显式设置 NINJA_JOBS 时手动指定 -j
  local cmd=(autoninja -C "$dir")
  if [ -n "${NINJA_JOBS:-}" ]; then
    cmd+=(-j "$NINJA_JOBS")
  fi
  cmd+=("$@")

  # 无超时限制直接前台执行
  if [ -z "${NINJA_TIMEOUT:-}" ]; then
    "${cmd[@]}"
    return $?
  fi

  local rc=0
  # 发送 SIGINT 触发 Siso/Ninja 优雅退出，确保 build graph、.ninja_log 与缓存完整落盘
  timeout -k 5m -s INT "$NINJA_TIMEOUT" "${cmd[@]}" || rc=$?

  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    echo "autoninja reached the ${NINJA_TIMEOUT} budget with work remaining."
    echo "status=running" >> "${GITHUB_OUTPUT:-/dev/null}"
    exit 0
  fi

  return "$rc"
}

pushd src
# 执行构建，自动适配 Android Build Server 与 Siso/Ninja 调度
autoninja_build "${output_folder}" chrome_public_apk

popd


printf 'session    %s  run %s  BUILD COMPLETE\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${GITHUB_RUN_NUMBER:-local}" >> "$stamp_file"
echo "status=completed" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "=== build provenance ==="
cat "$stamp_file"
