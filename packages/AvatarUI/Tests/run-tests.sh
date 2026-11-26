#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../../.." && pwd)"
args=(swift test --package-path "$repo_root/packages/AvatarUI" -Xlinker -lbz2 -Xlinker -liconv)
for directory in \
    libvpx/build/libvpx/lib ffmpeg/build/ffmpeg/lib libopus/build/libopus/lib \
    libwebp/build/libwebp/lib Mozjpeg/build openssl/build/openssl/lib \
    webrtc/build/webrtc OpenH264/build/output/lib dav1d/build/dav1d/lib tde2e/build/tde2e/lib
do
    for library in "$repo_root/core-xprojects/$directory"/*.a; do
        [[ -f "$library" ]] || { echo "Missing native libraries: $directory" >&2; exit 1; }
        args+=(-Xlinker "$library")
    done
done
exec "${args[@]}" "$@"
