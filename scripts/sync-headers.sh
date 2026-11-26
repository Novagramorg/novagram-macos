#!/bin/sh
set -e

SOURCE_DIR="$1"
DEST_DIR="$2"

[ -d "$SOURCE_DIR" ] || { echo "Missing header source: $SOURCE_DIR" >&2; exit 1; }
mkdir -p "$DEST_DIR"
rsync -rlc --delete --delete-excluded \
    --include='*/' --include='*.h' --exclude='*' "$SOURCE_DIR/" "$DEST_DIR/"
