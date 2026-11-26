#!/bin/bash
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$DIR/../../.." && pwd)
REV=${1:-HEAD}
rm -rf "$DIR/LegacyGraphUI"
mkdir -p "$DIR/LegacyGraphUI"
git -C "$ROOT" archive "$REV" packages/GraphUI/Sources | tar -x -C "$DIR/LegacyGraphUI" --strip-components=2
echo "LegacyGraphUI = packages/GraphUI/Sources at $(git -C "$ROOT" rev-parse --short "$REV")"
