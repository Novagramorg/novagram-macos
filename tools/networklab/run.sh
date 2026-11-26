#!/bin/bash
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$DIR/../.." && pwd)
LABEL=$1; ACCOUNT=$2; ENGINE=$3; PROFILE=$4; shift 4 || true
if [ -z "$LABEL" ] || [ -z "$ACCOUNT" ] || [ -z "$ENGINE" ] || [ -z "$PROFILE" ]; then
    echo "usage: tools/networklab/run.sh <label> <test|main> <rust|mtProtoKit> <direct|netsim-profile> [-PerfLabScenarios a,b ...]"
    exit 1
fi
if [ -z "$NETWORKLAB_APP" ]; then
    for data in ~/Library/Developer/Xcode/DerivedData/Telegram-Mac-*; do
        if /usr/libexec/PlistBuddy -c "Print :WorkspacePath" "$data/info.plist" 2>/dev/null | grep -q "$ROOT/"; then
            NETWORKLAB_APP="$data/Build/Products/Debug/Telegram.app"
        fi
    done
fi
APP=$NETWORKLAB_APP
OUT="$HOME/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/debug/perf-lab"
RESULTS=${NETWORKLAB_RESULTS:-$DIR/results}
BENCH="$ROOT/submodules/telegram-ios/third-party/mtproto-engine/target/release/mtproto-bench"
mkdir -p "$RESULTS" "$OUT"
if pgrep -f "Debug/Telegram.app/Contents/MacOS/Telegram" >/dev/null; then
    echo "a Debug Telegram is already running; quit it first"
    exit 1
fi
PROXY_ARGS=()
PROXY_LOG="$RESULTS/network-$LABEL-proxy.log"
rm -f "$PROXY_LOG"
if [ "$PROFILE" != "direct" ]; then
    "$BENCH" proxy --profile "$PROFILE" --bind 127.0.0.1:1081 ${NETWORKLAB_OUTAGES:+--outage-every $NETWORKLAB_OUTAGES} 2> "$PROXY_LOG" &
    PROXY=$!
    trap 'kill $PROXY 2>/dev/null' EXIT
    sleep 1
    PROXY_ARGS=(-PerfLabProxy 127.0.0.1:1081)
fi
run_app() {
    open -n "$APP" --args -PerfLab network -PerfLabLabel "$LABEL" -PerfLabQuit -PerfLabAccount "$ACCOUNT" -PerfLabNetworkEngine "$ENGINE" "${PROXY_ARGS[@]}" "$@"
    sleep 3
    local pid
    pid=$(pgrep -f "Debug/Telegram.app/Contents/MacOS/Telegram" | head -1)
    while [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; do sleep 1; done
}
BEFORE=$(ls "$OUT" 2>/dev/null | sort)
rm -f "$OUT/network-lab-engine-switched"
run_app "$@"
if [ -f "$OUT/network-lab-engine-switched" ]; then
    rm -f "$OUT/network-lab-engine-switched"
    echo "engine switched to $ENGINE, relaunching"
    run_app "$@"
fi
AFTER=$(ls "$OUT" | sort)
REPORT=$(comm -13 <(echo "$BEFORE") <(echo "$AFTER") | grep "^network-$LABEL-.*\.json$" | tail -1)
if [ -z "$REPORT" ]; then
    echo "no report written"
    exit 1
fi
cp "$OUT/$REPORT" "$RESULTS/"
echo "$RESULTS/$REPORT"
cat "$RESULTS/$REPORT"
[ -f "$PROXY_LOG" ] && tail -2 "$PROXY_LOG"
