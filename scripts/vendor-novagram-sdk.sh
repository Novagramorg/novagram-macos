#!/bin/bash
# Copies the NovagramAds SDK dynamic xcframeworks into packages/NovagramAdsBinary/.
#
# Usage:
#   ./scripts/vendor-novagram-sdk.sh <sdk build dir>
#
# The build dir holds NovagramAds.xcframework, NovagramInsights.xcframework and
# NovagramInsightsUI.xcframework (all three must come from the same SDK build).
# Only the macos-arm64_x86_64 slice is kept and each Info.plist is rewritten to list only it.
# The old copies are moved to a backup folder first (default: a new folder under $TMPDIR, or $BACKUP_DIR).
# Package.swift in the destination is not touched. Nothing here reads or writes keys or URLs.

set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${1:-}"
DEST="packages/NovagramAdsBinary"
SLICE="macos-arm64_x86_64"
NAMES=(NovagramAds NovagramInsights NovagramInsightsUI)

if [ -z "$SRC" ] || [ ! -d "$SRC" ]; then
    echo "Usage: $0 <sdk build dir>" >&2
    exit 1
fi

# Check everything before touching the destination.
for name in "${NAMES[@]}"; do
    framework="$SRC/$name.xcframework/$SLICE/$name.framework"
    if [ ! -d "$framework" ]; then
        echo "Missing $framework" >&2
        exit 1
    fi
    if ! lipo -archs "$framework/Versions/A/$name" 2>/dev/null | grep -q arm64; then
        echo "$name has no arm64 binary (is it a dynamic framework build?)" >&2
        exit 1
    fi
done

BACKUP="${BACKUP_DIR:-${TMPDIR:-/tmp}/novagram-sdk-prev-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$BACKUP"

for name in "${NAMES[@]}"; do
    target="$DEST/$name.xcframework"
    if [ -d "$target" ]; then
        mv "$target" "$BACKUP/"
    fi
    mkdir -p "$target"
    # ditto keeps the Versions/Current symlinks of the framework bundle.
    ditto "$SRC/$name.xcframework/$SLICE" "$target/$SLICE"
    python3 -I - "$SRC/$name.xcframework/Info.plist" "$target/Info.plist" "$SLICE" <<'PY'
import plistlib
import sys

source, destination, slice_id = sys.argv[1:4]
with open(source, "rb") as handle:
    info = plistlib.load(handle)
info["AvailableLibraries"] = [lib for lib in info["AvailableLibraries"] if lib["LibraryIdentifier"] == slice_id]
if len(info["AvailableLibraries"]) != 1:
    sys.exit("slice " + slice_id + " not found in " + source)
with open(destination, "wb") as handle:
    plistlib.dump(info, handle)
PY
    echo "Vendored $name ($(lipo -archs "$target/$SLICE/$name.framework/Versions/A/$name"))."
done

echo "Previous copies moved to $BACKUP"
echo "Next: ./fenix-build.sh (Xcode embeds and signs the frameworks)."
