#!/usr/bin/env bash
set -euo pipefail

: "${UGC_WORK:=/mnt/ugc}"
: "${ARCH:?ARCH must be set}"
: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE must be set}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"
: "${GH_TOKEN:?GH_TOKEN must be set}"

RUN="${SOURCE_RUN_ID:-${GITHUB_RUN_ID:?GITHUB_RUN_ID must be set}}"
API="https://api.github.com/repos/${GITHUB_REPOSITORY}"
AUTH=(-H "Authorization: Bearer ${GH_TOKEN}" -H "Accept: application/vnd.github+json")
ARTIFACT="build-tree-${ARCH}.tar.zst"

meta=$(curl -fsSL "${AUTH[@]}" "${API}/actions/runs/${RUN}/artifacts?name=${ARTIFACT}")
read -r AID ASIZE <<< "$(python3 -c '
import json, sys

name = sys.argv[2]
artifacts = json.loads(sys.argv[1])["artifacts"]
matches = [a for a in artifacts if a["name"] == name and not a["expired"]]
if matches:
    artifact = max(matches, key=lambda a: a["created_at"])
    print(artifact["id"], artifact["size_in_bytes"])
' "$meta" "$ARTIFACT")"
if [ -z "${AID:-}" ] || [ -z "${ASIZE:-}" ]; then
    echo "FATAL: run ${RUN} has no ${ARTIFACT} artifact to resume from"
    exit 1
fi
echo "artifact ${AID}: ${ASIZE} bytes from run ${RUN}"

dl=$(mktemp -d "${RUNNER_TEMP:-${GITHUB_WORKSPACE}}/build-tree-download.XXXXXX")
trap 'rm -rf "$dl"' EXIT
_tar="${dl}/${ARTIFACT}"

# Probe the redirected blob with a one-byte range; never expose its signed URL in logs.
if ! probe=$(curl -fsSL --range 0-0 --max-filesize 1 "${AUTH[@]}" -o /dev/null \
    -w '%{http_code}\n%{url_effective}\n%{size_download}' \
    "${API}/actions/artifacts/${AID}/zip"); then
    echo "FATAL: could not probe the artifact with a byte-range request"
    exit 1
fi
mapfile -t PROBE <<< "$probe"
if [ "${PROBE[0]:-}" != "206" ] || [ -z "${PROBE[1]:-}" ] || [ "${PROBE[2]:-}" != "1" ]; then
    echo "FATAL: artifact download endpoint does not support byte-range requests"
    exit 1
fi
if [[ ! "$ASIZE" =~ ^[0-9]+$ ]] || (( ASIZE <= 0 )); then
    echo "FATAL: invalid artifact size: ${ASIZE}"
    exit 1
fi

chunk_size=$((128 * 1024 * 1024))
workers=$(((ASIZE + chunk_size - 1) / chunk_size))
if (( workers > 8 )); then
    workers=8
fi
part_dir="${dl}/parts"
mkdir -p "$part_dir"

curl_args=(--parallel --parallel-immediate --parallel-max "$workers")
part_count=$(((ASIZE + chunk_size - 1) / chunk_size))
for ((index = 0, start = 0; start < ASIZE; index++, start += chunk_size)); do
    end=$((start + chunk_size - 1))
    (( end >= ASIZE )) && end=$((ASIZE - 1))
    part=$(printf '%s/part.%06d' "$part_dir" "$index")
    headers="${part}.headers"
    if (( index > 0 )); then
        curl_args+=(--next)
    fi
    curl_args+=(
        --fail --silent --show-error --retry 5 --retry-all-errors --retry-delay 2
        --connect-timeout 30
        --range "${start}-${end}"
        --dump-header "$headers"
        --output "$part"
        "${PROBE[1]}"
    )
done

echo "downloading ${ASIZE} bytes in ${part_count} ranges (${workers} parallel)"
curl "${curl_args[@]}"

for ((index = 0, start = 0; start < ASIZE; index++, start += chunk_size)); do
    end=$((start + chunk_size - 1))
    (( end >= ASIZE )) && end=$((ASIZE - 1))
    part=$(printf '%s/part.%06d' "$part_dir" "$index")
    headers="${part}.headers"
    expected=$((end - start + 1))
    if ! grep -Eq '^HTTP/[0-9.]+ 206([[:space:]]|$)' "$headers" ||
        ! grep -Fqi "content-range: bytes ${start}-${end}/${ASIZE}" "$headers" ||
        [ "$(stat -c%s "$part")" -ne "$expected" ]; then
        echo "FATAL: invalid response for byte range ${start}-${end}"
        exit 1
    fi
done

cat "$part_dir"/part.[0-9][0-9][0-9][0-9][0-9][0-9] > "$_tar"
if [ "$(stat -c%s "$_tar")" -ne "$ASIZE" ]; then
    echo "FATAL: downloaded file size does not match artifact metadata"
    exit 1
fi
rm -rf "$part_dir"

echo "::group::verifying and unpacking $(du -h "$_tar" | cut -f1)"
zstd -t "$_tar"
mkdir -p "${UGC_WORK}"
zstd -dc -T0 "$_tar" | tar -xf - -C "${UGC_WORK}"
rm -rf "$dl"
trap - EXIT
echo "::endgroup::"

df -h / /mnt
