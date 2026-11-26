#!/bin/sh

LABEL="$1"
shift
STARTED=$(date +%s)
"$@"
RESULT=$?
ELAPSED=$(($(date +%s) - STARTED))
echo "build-timing: $LABEL ${ELAPSED}s (exit $RESULT)"
if [ -n "${BUILD_TIMING_LOG:-}" ]; then
    printf '%s\t%s\t%s\n' "$LABEL" "$ELAPSED" "$RESULT" >> "$BUILD_TIMING_LOG"
fi
exit "$RESULT"
