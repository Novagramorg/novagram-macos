#!/bin/bash
# tc.sh <Module> <srcDir> : type-check a package module against Xcode DerivedData (read-only)
set -e
# Usage: tc.sh <Module> <srcDir>          type-check a package module (macOS 10.13 target)
#        EMIT=1 tc.sh <Module> <srcDir>   emit its .swiftmodule into $WORK/mods for modules missing from DerivedData
# Uses the app's Xcode DerivedData read-only. Needed extras: WidgetSandbox must be emitted first (EMIT=1),
# and CQuickJS comes from its package include dir.
MOD="$1"; SRC="$2"
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
WORK="${TMPDIR:-/tmp}/tg-typecheck"
mkdir -p "$WORK/mods"
D=$(ls -dt ~/Library/Developer/Xcode/DerivedData/Telegram*/Build | head -1)
SDK=$(xcrun --show-sdk-path --sdk macosx)
ARGS=()
HDRS=()
for mm in "$D"/Intermediates.noindex/GeneratedModuleMaps/*.modulemap; do
  ARGS+=(-Xcc "-fmodule-map-file=$mm")
  while IFS= read -r line; do
    if [[ "$line" =~ (umbrella\ header|header)\ \"([^\"]+)\" ]]; then p="${BASH_REMATCH[2]}"; d=$(dirname "$p"); HDRS+=("$d" "$(dirname "$d")");
    elif [[ "$line" =~ umbrella\ \"([^\"]+)\" ]]; then HDRS+=("${BASH_REMATCH[1]}"); fi
  done < "$mm"
done
for h in $(printf "%s\n" "${HDRS[@]}" | sort -u); do ARGS+=(-Xcc "-I$h"); done
STUB="$WORK/BundleStub.swift"
echo 'import Foundation
extension Bundle { static var module: Bundle { .main } }' > $STUB
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "$SRC" -name '*.swift')
MODE=(-typecheck)
[ -n "$EMIT" ] && MODE=(-emit-module -emit-module-path "$WORK/mods/$MOD.swiftmodule")
swiftc "${MODE[@]}" -module-name "$MOD" -parse-as-library -target arm64-apple-macos10.13 -sdk "$SDK" \
  -I "$WORK/mods" -I "$D/Products/Debug" -F "$D/Products/Debug" -I "$D/Products/Debug/include" \
  "${ARGS[@]}" -Xcc -I"$REPO/packages"/WidgetSandbox/Sources/CQuickJS/include -Xcc -I"$REPO/third-party"/widget-sandbox/packages/ios/Sources/CQuickJS/include "${FILES[@]}" $STUB 2>&1 | grep -E "error:" | head -20
echo "exit ${PIPESTATUS[0]}"
