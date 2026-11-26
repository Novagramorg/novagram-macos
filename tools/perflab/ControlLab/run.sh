#!/bin/bash
set -euo pipefail
lab_dir="$(cd "$(dirname "$0")" && pwd)"
variant="${1:-candidate}"
shift "$(( $# > 0 ? 1 : 0 ))"
lab_work="${CONTROL_LAB_WORK:-${TMPDIR:-/tmp}/telegram-control-lab}"
python3 "$lab_dir/prepare.py" "$variant" "$lab_work/$variant"
cp "$lab_work/$variant/provenance.json" "$lab_dir/Evidence/$variant-provenance.json"
swift run --package-path "$lab_work/$variant/ControlLab" -c release ControlLab "$@"
