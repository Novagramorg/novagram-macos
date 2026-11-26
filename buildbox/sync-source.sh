#!/bin/sh
set -e

SOURCE_DIR="$1"
DEST_DIR="$2"

mkdir -p "$DEST_DIR"
rsync -a --delete \
    --exclude='/core-xprojects/*/build/' \
    --exclude='/Telegram-Mac/Release.xcconfig' \
    --exclude='/packages/WalletEngine/wallet_engineFFI.xcframework/' \
    --exclude='/submodules/telegram-ios/submodules/MTProtoRustEngine/MTProtoEngineFFI.xcframework/' \
    --exclude='/submodules/**/SharedHeaders/' \
    --exclude='/.build/telegram-api-generation/' \
    --exclude='/submodules/telegram-ios/build-system/SwiftTL/.build/' \
    --exclude='/submodules/telegram-ios/submodules/TelegramApi/Sources/SwiftPMGenerated/' \
    --exclude='/submodules/telegram-ios/submodules/TelegramApi/ObjC/SwiftPMGenerated/' \
    --exclude='/submodules/telegram-ios/submodules/TelegramApi/Tests/SwiftPMGenerated/' \
    --exclude='/submodules/telegram-ios/submodules/TelegramCore/FlatSerialization/Sources/' \
    --exclude='/.ci-build-logs/' \
    "$SOURCE_DIR/" "$DEST_DIR/"
