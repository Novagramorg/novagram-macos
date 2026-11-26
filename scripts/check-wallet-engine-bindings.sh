#!/bin/sh

ROOT_DIR="$(cd "${1:-$(dirname "$0")/..}" && pwd)"
REPORT="${2:-}"
BUILT_BINDINGS="$ROOT_DIR/core-xprojects/wallet-engine/build/WalletEngineFFI.swift"
PACKAGE_BINDINGS="$ROOT_DIR/packages/WalletEngine/Sources/WalletEngineFFI/WalletEngineFFI.swift"
REBUILD="git -C submodules/telegram-ios submodule update --init third-party/wallet-engine/wallet-engine && sh core-xprojects/wallet-engine/wallet-engine/build.sh \"\$PWD/submodules/telegram-ios/third-party/wallet-engine/wallet-engine\" \"\$PWD/core-xprojects/wallet-engine/build\" \"\$PWD/packages/WalletEngine\""

if [ ! -f "$BUILT_BINDINGS" ]; then
    if [ "$REPORT" = "xcode" ]; then
        echo "warning: the wallet engine library has no record of the bindings it was built with, so WalletEngineFFI.swift cannot be checked against it. Rebuild it once from the repository root: $REBUILD"
        exit 0
    fi
    exit 2
fi

if cmp -s "$BUILT_BINDINGS" "$PACKAGE_BINDINGS"; then
    exit 0
fi

if [ "$REPORT" = "xcode" ]; then
    echo "error: packages/WalletEngine/Sources/WalletEngineFFI/WalletEngineFFI.swift does not match the wallet engine library in packages/WalletEngine/wallet_engineFFI.xcframework, so the app would abort at launch with a UniFFI checksum mismatch. Rebuild the library from the repository root: $REBUILD"
fi
exit 1
