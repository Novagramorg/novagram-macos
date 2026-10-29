#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/packages/NovagramJobSearch"
SOURCES="$PACKAGE/Sources/NovagramJobSearch"
PURE_FILES=(
    NovagramJobText.swift
    NovagramJobQuery.swift
    NovagramJobPostParser.swift
    NovagramJobPresets.swift
    NovagramJobStore.swift
    NovagramJobModel.swift
    NovagramJobRegex.swift
    NovagramJobSalaryParser.swift
    NovagramJobContactParser.swift
    NovagramSearchLanguage.swift
    NovagramSearchConversion.swift
)

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

INPUTS=()
for file in "${PURE_FILES[@]}"; do
    INPUTS+=("$SOURCES/$file")
done
INPUTS+=("$PACKAGE/Checks/main.swift")

swiftc -module-name NovagramJobChecks -o "$WORK/novagram-job-checks" "${INPUTS[@]}"
"$WORK/novagram-job-checks"
