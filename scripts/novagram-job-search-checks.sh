#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/packages/NovagramSearchKit"

if [ ! -f "$PACKAGE/Package.swift" ]; then
    echo "packages/NovagramSearchKit is missing: git submodule update --init -- packages/NovagramSearchKit" >&2
    exit 1
fi

cd "$PACKAGE"
swift test
