#!/bin/bash
set -euo pipefail
lab_dir="$(cd "$(dirname "$0")" && pwd)"
lab_work="${TEXT_LAYOUT_LAB_WORK:-${TMPDIR:-/tmp}/telegram-text-layout-lab}"
export CLANG_MODULE_CACHE_PATH="$lab_work/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$lab_work/swift-cache"
python3 "$lab_dir/prepare.py" "$lab_work/package"
mode="${1:-test}"
shift "$(( $# > 0 ? 1 : 0 ))"
common=(--disable-sandbox --package-path "$lab_work/package" --cache-path "$lab_work/cache" --config-path "$lab_work/config" --security-path "$lab_work/security")
case "$mode" in
    test) swift test "${common[@]}" --scratch-path "$lab_work/build" "$@" ;;
    release-test) swift test "${common[@]}" --scratch-path "$lab_work/build" -c release "$@" ;;
    bench) swift run "${common[@]}" --scratch-path "$lab_work/build" -c release LabRunner "$@" ;;
    tsan) swift test "${common[@]}" --scratch-path "$lab_work/tsan" --sanitize=thread "$@" ;;
    asan) swift test "${common[@]}" --scratch-path "$lab_work/asan" --sanitize=address "$@" ;;
    *) echo "Usage: $0 test|release-test|bench [--memory baseline|candidate]|tsan|asan" >&2; exit 2 ;;
esac
