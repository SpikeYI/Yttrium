#!/usr/bin/env bash
set -euo pipefail

: "${UGC_WORK:=/mnt/ugc}"
_arch="${ARCH:-arm64}"
_tar="${GITHUB_WORKSPACE}/build-tree-${_arch}.tar.zst"

if [ ! -f "$_tar" ]; then
    _candidate=$(find "${GITHUB_WORKSPACE}" -maxdepth 2 \( -name "build-tree-${_arch}.tar.zst" -o -name "build-tree.tar.zst" \) -type f | head -n 1)
    if [ -n "$_candidate" ] && [ -f "$_candidate" ]; then
        _tar="$_candidate"
    else
        echo "FATAL: build tree archive not found for architecture ${_arch}"
        exit 1
    fi
fi

echo "::group::unpacking $(du -h "$_tar" | cut -f1)"
mkdir -p "${UGC_WORK}"
zstd -dc -T0 "$_tar" | tar -xf - -C "${UGC_WORK}"
rm -f "$_tar"
echo "::endgroup::"

df -h / /mnt
