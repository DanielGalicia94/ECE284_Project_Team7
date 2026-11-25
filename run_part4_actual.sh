#!/usr/bin/env bash
# Usage: bash run_part4_actual.sh /path/to/ECE284_Project_Team7-struct_pruning
set -euo pipefail
REPO="$(cd "${1:-.}" && pwd)"
TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STIM="$REPO/part4_actual"

python3 "$TOOLS/verify_part4_actual.py" "$REPO"

for cmd in iverilog vvp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: $cmd is not installed; RTL simulation was not run." >&2
        echo "Install Icarus Verilog, then rerun this script." >&2
        exit 2
    fi
done

iverilog -g2012 -s core_tb -o "$STIM/core_sim" "$REPO/part3/core_tb.v" "$REPO"/netlists/*.v
(cd "$STIM" && vvp ./core_sim | tee simulation.log)

log="$STIM/simulation.log"
matched=$(grep -c 'output featuremap Data matched!' "$log" || true)
errors=$(grep -c 'Data ERROR!!' "$log" || true)
if [[ "$matched" -eq 16 && "$errors" -eq 0 ]] && grep -q 'No error detected' "$log"; then
    echo 'PASS: RTL produced all 16 expected output words (128 output values).'
    echo "Waveform: $STIM/core_tb.vcd"
    echo "Log: $log"
else
    echo "FAIL: Found $matched/16 matches, $errors data error(s)." >&2
    exit 1
fi
