#!/bin/bash
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
ROUNDS=${ROUNDS:-3}
OUT=${OUT:-$DIR/results/$(date +%Y%m%d-%H%M%S)}
mkdir -p "$OUT"
[ -d "$DIR/LegacyGraphUI/Sources" ] || "$DIR/prepare-legacy.sh"
(cd "$DIR/Legacy" && swift build -c release)
(cd "$DIR/Current" && swift build -c release)
for r in $(seq 1 "$ROUNDS"); do
    if (( r % 2 )); then ORDER="Legacy Current"; else ORDER="Current Legacy"; fi
    for v in $ORDER; do
        echo "round $r $v"
        CHARTLAB_OUTPUT="$OUT/$v-r$r.jsonl" "$DIR/$v/.build/release/ChartLab" --label "$v" "$@" > /dev/null
    done
done
python3 "$DIR/compare.py" "$OUT"
