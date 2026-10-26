#!/bin/bash
# novagram-build.sh - Debug build with the real pass/fail result.
# A plain `xcodebuild ...; echo $?` reports the echo's exit code, so this script
# greps the log for "BUILD SUCCEEDED" and prints the Swift errors on failure.
#
# Usage:
#   ./novagram-build.sh            build only
#   ./novagram-build.sh run        build, then launch Novagram.app on success
#   ./novagram-build.sh appstore   build with APP_STORE also set inside the packages
#                               (Xcode passes it to the app target only; packages get it from the command line)
#   NOVAGRAM_DD=/tmp/other-dd NOVAGRAM_LOG=/tmp/other.log ./novagram-build.sh   separate DerivedData (parallel builds)

set -o pipefail
cd "$(dirname "$0")"

LOG="${NOVAGRAM_LOG:-/tmp/novagram13-build.log}"
DD="${NOVAGRAM_DD:-/tmp/tgmac13-dd}"
APP="$DD/Build/Products/Debug/Novagram.app"
MODE="${1:-}"

EXTRA=()
if [ "$MODE" = "appstore" ]; then
  EXTRA+=( 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) APP_STORE' )
fi

echo "Building Novagram (Debug${MODE:+, $MODE}) $(date +%H:%M:%S)"
xcodebuild -workspace Telegram-Mac.xcworkspace -scheme Telegram \
  -configuration Debug -derivedDataPath "$DD" \
  "${EXTRA[@]}" build CODE_SIGN_STYLE=Automatic > "$LOG" 2>&1

if grep -q "BUILD SUCCEEDED" "$LOG"; then
  echo "BUILD SUCCEEDED ($(date +%H:%M:%S))"
  if [ "$MODE" = "run" ]; then
    echo "Launching $APP"
    open -n "$APP"
  fi
  exit 0
else
  echo "BUILD FAILED - errors:"
  grep -E "error:" "$LOG" | grep -E "\.(swift|m|h|plist|xcconfig):" | sort -u | head -30
  grep -E "^error:|xcodebuild: error" "$LOG" | sort -u | head -10
  echo "(full log: $LOG)"
  exit 1
fi
