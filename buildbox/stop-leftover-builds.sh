#!/bin/sh
set -e

leftovers=""
for pid in $(pgrep -x xcodebuild || true); do
    cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
    case "$cwd" in
        "${TELEGRAM_BUILD_ROOT:-$HOME}"/build-*)
            echo "Stopping xcodebuild $pid left running in $cwd by an earlier job"
            kill "$pid" || true
            leftovers="$leftovers $pid"
            ;;
    esac
done

for pid in $leftovers; do
    waited=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$waited" -ge 60 ]; then
            kill -9 "$pid" || true
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done
done
