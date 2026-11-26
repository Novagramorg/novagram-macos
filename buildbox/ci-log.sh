#!/bin/bash
set +x
set -o pipefail

if [ "$#" -eq 0 ]; then
    exit 64
fi
export CI_BUILD_LOG_DIR="${CI_PROJECT_DIR:-$PWD}/.ci-build-logs/${CI_JOB_ID:-manual}"
mkdir -p "$CI_BUILD_LOG_DIR" || exit 1
"$@" 2>&1 | tee -a "$CI_BUILD_LOG_DIR/job.log"
results=("${PIPESTATUS[@]}")
if [ "${results[0]}" -ne 0 ]; then
    exit "${results[0]}"
fi
exit "${results[1]}"
