#!/usr/bin/env bash
# Compile once and run the full 8x8 channel-mask regression.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
command -v iverilog >/dev/null || { echo 'Install Icarus Verilog (sudo apt install iverilog)' >&2; exit 127; }
command -v vvp >/dev/null || { echo 'vvp not found' >&2; exit 127; }
mkdir -p "$root/mask_results"
# filelist paths are relative to the project root.
iverilog -g2012 -s core_tb -o "$root/mask_results/core_tb.vvp" -f filelist part3/core_tb.v
run_case() {
    local dataset=$1 name=$2
    shift 2
    local dest="$root/mask_results/$dataset/$name"
    mkdir -p "$dest"
    echo "=== $dataset / $name ==="
    local dump_arg=+NO_VCD
    if [[ ${DUMP_VCD:-0} == 1 ]]; then dump_arg="+VCD_FILE=$dest/core_tb.vcd"; fi
    (cd "$root/$dataset" && vvp "$root/mask_results/core_tb.vvp" "$dump_arg" "$@") | tee "$dest/run.log"
    grep -q 'errors=0;' "$dest/run.log"
}
for dataset in part4 part4_actual; do
    run_case "$dataset" all_enabled
    run_case "$dataset" input_only +INPUT_MASK=55
    run_case "$dataset" output_only +OUTPUT_MASK=AA
    run_case "$dataset" combined_4x4 +INPUT_MASK=55 +OUTPUT_MASK=AA
    run_case "$dataset" singleton +INPUT_MASK=80 +OUTPUT_MASK=01
    run_case "$dataset" no_inputs +INPUT_MASK=00
    run_case "$dataset" no_outputs +OUTPUT_MASK=00
    run_case "$dataset" masked_padded +INPUT_MASK=55 +OUTPUT_MASK=AA +PAD_PRUNED
    run_case "$dataset" bypass_padded +INPUT_MASK=55 +OUTPUT_MASK=AA +PAD_PRUNED +MASK_BYPASS
 done
echo 'All mask regression cases passed.'
