# ECE284: runtime channel enable masking

## Scope

This is a minimal **8 x 8** masking extension of the supplied Part 3/4 baseline, not a physically smaller array or a parallel-subarray implementation. All 64 PEs, 8 L0 FIFOs, 8 OFIFOs, 8 SFP lanes, memory interfaces, instruction encoding, and the original controller schedule remain in place. The original archive is untouched. The modified project is a separate copy.

## Mask interface and data mapping

`row_enable[7:0]` and `col_enable[7:0]` are active-high runtime inputs to both `core` and `corelet`. A one enables the original channel index; bit 0 corresponds to channel 0 (the least significant packed nibble/partial-sum lane). `row_enable` selects input channels and `col_enable` selects output channels. Noncontiguous channel selections are supported. The masks must be known and stable before reset/weight loading and remain unchanged for the entire convolution, including SFP accumulation and ReLU. Reset/reload before changing the masks. Tie both to `8'hFF` for ordinary unpruned operation. Existing external wrappers or Quartus pin assignments must connect the new ports; leaving them floating is invalid.

Examples (hex):

| Input | Output | Enabled PEs | Description |
|---|---|---:|---|
| FF | FF | 64 | All enabled |
| 55 | FF | 32 | Input channels 0,2,4,6 |
| FF | AA | 32 | Output channels 1,3,5,7 |
| 55 | AA | 16 | Both noncontiguous masks |
| 80 | 01 | 1 | Input channel 7, output channel 0 |
| 00 | FF | 0 | All input channels disabled |
| FF | 00 | 0 | All output channels disabled |

Any pair of 8-bit masks is legal, including zero. The number of enabled PEs is `popcount(row_enable) * popcount(col_enable)`.

## RTL changes

| File | Change and rationale |
|---|---|
| `netlists/core.v` | Add row/column enable ports and forward them to `corelet_instance`. The SRAM widths and 34-bit instruction word do not change. |
| `netlists/corelet.v` | Add the same ports and forward them to `mac_array_instance`. No changes to L0, OFIFO, or SFP interfaces. |
| `netlists/mac_array.v` | Add masks; each generated `mac_row` gets its own `row_enable[i-1]` and the full column mask. Preserve all vertical instructions/psum timing. |
| `netlists/mac_row.v` | Pass `row_enable & col_enable[i-1]` to each `mac_tile`. Preserve all activation and instruction forwarding. |
| `netlists/mac_tile.v` | Add `pe_enable`. Isolate both multiplier inputs to zero when disabled. Inhibit stationary-weight register writes when disabled, while still advancing `load_ready_q`. Preserve `a_q`, `c_q`, `inst_q`, east/south outputs and the loading sequence. |

The arithmetic in `mac.v` is unchanged (unsigned 4-bit activations, signed 4-bit weights). A disabled PE computes `out_s = c_q + 0*0 = c_q`, rather than forcing its output to zero. This is necessary because a disabled row can lie between active rows and must carry the accumulated result south. A disabled output column receives zero at its top from `corelet` and accumulates zero all the way down. Inactive columns still write zero-valued FIFO words with normal valid timing. This preserves the existing all-column `o_valid` behavior and prevents deadlock. The weight-load state machine must advance even for disabled PEs so load instructions reach active columns farther east. No fabric clock gating is introduced.

Not changed: `mac.v`, `l0.v`, `ofifo.v`, `fifo_depth64.v`, `sfp.v`, SRAM modules, stimulus notebooks, and original stimulus files. Existing single-row/single-column parameterization limitations are deliberately not addressed in this masking-only change.

## Testbench changes (`part3/core_tb.v`)

- Default masks are FF/FF, preserving the original convolution. Override with `+INPUT_MASK=<hex>` and `+OUTPUT_MASK=<hex>`.
- Connect both new runtime mask ports; report active and enabled PE counts.
- Preserve the original SRAM, L0, loading, execution, OFIFO, SFP and ReLU sequence. No cycle-skipping changes.
- Capture original activation and weight words. Decode accumulation addresses into kernel index and spatial input index. Compute an independent signed integer dot product over the selected input/output channels. Compare every packed 128-bit output both before and after ReLU; disabled output lanes must be zero. Case inequality/equality catches unknown values. Check the raw reference fits the 16-bit signed psum range.
- In FF/FF mode, also check the computed reference against the existing `out.txt`. For a separately exported pruned golden, use `+CHECK_OUT_FILE` to require that comparison in masked mode as well.
- Skip the three header lines using `$fgets`, validate opens and binary scans, close weight files, check OFIFO validity before read, report error count and cycles, and fail with `$fatal` on error. Testbench uses SystemVerilog-compatible simulation mode (`-g2012`); synthesizable RTL remains Verilog-style.
- `+PAD_PRUNED` zeros inactive input activation lanes and weights to/from pruned channels before writing SRAM. `+MASK_BYPASS` (requires `+PAD_PRUNED`) drives hardware masks FF/FF while retaining the selected model masks for padding and reference. This provides an equivalent-output, same-stimulus control within the masked RTL.
- `+NO_VCD` disables dumping; `+VCD_FILE=<path>` chooses a distinct VCD name. Default remains `core_tb.vcd`.

The regression testbench intentionally supports the original 8x8, 4-bit, 9-offset convolution only. The parameters for spatial lengths retain the original values (36 input positions, 16 output positions). A shared zeroed spatial kernel position is still loaded and executed; kernel skipping belongs to a separate experiment.

## Run from the project root (WSL/Linux)

```bash
sudo apt install iverilog
iverilog -g2012 -s core_tb -o core_tb.vvp -f filelist part3/core_tb.v
cd part4_actual
vvp ../core_tb.vvp                                     # all enabled
vvp ../core_tb.vvp +INPUT_MASK=55 +OUTPUT_MASK=AA       # arbitrary 4x4
vvp ../core_tb.vvp +INPUT_MASK=80 +OUTPUT_MASK=01       # single active PE
vvp ../core_tb.vvp +INPUT_MASK=55 +OUTPUT_MASK=AA +PAD_PRUNED +VCD_FILE=masked.vcd
vvp ../core_tb.vvp +INPUT_MASK=55 +OUTPUT_MASK=AA +PAD_PRUNED +MASK_BYPASS +VCD_FILE=bypass.vcd
```

Or, from the root, run `bash part3/run_mask_tests.sh`. It compiles once and runs nine cases on each of `part4` and `part4_actual` (18 total). `DUMP_VCD=1 bash part3/run_mask_tests.sh` saves separate VCDs and logs in `mask_results/`. The script returns a nonzero exit code on a simulation error. A successful simulation should report `errors=0`; this is an acceptance criterion, not an already observed RTL result.

## Independent reference and original baseline control

`part3/mask_reference.py` uses Python integer arithmetic to verify the supplied baseline data and zero-padding equivalence. It can export stimulus files for a separate, untouched baseline build:

```bash
python3 part3/mask_reference.py part4_actual --input-mask 55 --output-mask AA --write-padded padded_4x4
```

The destination must not already exist. Copy/use this fixture directory with the original baseline simulation, then use the same padded data with the masked implementation. This is stronger than comparing only to `+MASK_BYPASS`, because the bypass still contains synthesized masking logic. The script assumes source `out.txt`, if present, is the full-channel golden for that source data. Output includes pre- and post-ReLU packed golden files.

## Using your actual pruned/fine-tuned model

The included datasets are the original layer fixtures, not your new fine-tuned checkpoints. Masking the old weights demonstrates functional masking, not your pruned model's accuracy. For hardware benchmarking, export the fine-tuned integer weights and matching activations. If the model stores channels compactly, scatter them back into the original 8-channel lane positions (or pack into the first N lanes and choose the matching contiguous masks). Maintain exactly the same channel mapping for weight columns, activation rows, and output verification. Fill removed lanes with zero for the padded control. Use the same fine-tuned tensor values in both masked and unmasked runs. Export the corresponding zero-padded 128-bit output words if using `+CHECK_OUT_FILE`. The quantizer normalizes weights before quantization, so ensure final exported integers in intended zero positions really are zero. For the 4x4 eight-offset model, export the ninth offset as all zeros; keep nine rounds for this masking experiment.

## Benchmarking and limitations

- The design targets local multiplier switching and weight-register updates, not area or cycle reduction. `a_q`/`c_q`, FIFO transfers, SFP operations and forwarding remain active. A disabled PE can still switch outside its multiplier. Clock enables do not stop the global FPGA clock. The reduction in enabled MAC count is not the reduction in total dynamic power.
- Compare the original unmasked 8x8 RTL with a zero-padded pruned model to the masked RTL with the same zero-padded model and masks. Also compare FF/FF to the untouched baseline to quantify mask logic overhead. `MASK_BYPASS` is a useful within-design toggle, not the original physical baseline.
- Keep mask ports runtime inputs at the synthesized `corelet` top; do not tie masks to constants during synthesis, as Quartus may remove disabled logic. Keep identical target FPGA, constraints, voltage, temperature and clock frequency for like-for-like power measurements. Use the project's required 20% input activity and simulation-derived activity where possible; real activity is particularly important because the unmasked zero-padded baseline may already have low multiplier switching. Include mask routing/mux overhead and check Fmax.
- Report post-fit logic/register/DSP utilization, static/dynamic power, total cycles, latency at a common clock (and optionally each design's Fmax), and estimated energy per layer. The testbench clock is 1 ns for functional simulation; it is not a measured FPGA operating frequency. SRAM is outside `corelet`, so report corelet-only power/area consistently.
- Part 2 signed activation support, reference-frame nibble reconstruction, wider accumulation, reduced physical arrays and parallel subarrays are not implemented here. Keep masks constant across differential passes once those features are integrated.

## Verification status

The independent Python reference matched the supplied `out.txt` at 16/16 positions for each original dataset. Seven mask cases on each dataset (14 software checks) also passed zero-padding equivalence, including noncontiguous masks, one active PE, and zero-active cases. An exported padded fixture was re-read and its golden matched 16/16 positions. The shell regression script passed `bash -n`. The RTL changes were statically inspected. Icarus Verilog and Verilator were not installed in the execution environment; an attempted package installation timed out. **RTL compilation, simulation, Quartus synthesis, timing, and power have not been verified.** Run the supplied regression before using the design for hardware measurements.
