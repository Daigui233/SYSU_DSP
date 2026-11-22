# FFT implementation comparison

Both revisions were synthesized, placed and routed on 2026-11-22 using Vivado 2019.1, `xcvu13p-flga2577-2-i`, a 4.000 ns clock and 0.100 ns clock uncertainty. The baseline is `7214d02`. Verification-only checkpoint `1db56ca` has identical RTL. Unit-rotation RTL is `9477d8b`. These wrapper-level totals include the internal source, the full-width capture registers and the narrow checksum. The four reports for each size in this directory are from the unit-rotation run.

| Core | RTL | CLB LUT | CLB FF | DSP48E2 | BRAM/URAM | WNS (ns) | TNS (ns) | WHS (ns) | THS (ns) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| FFT32 | Baseline | 20,557 | 12,955 | 320 | 0/0 | 0.571 | 0.000 | 0.000 | 0.000 |
| FFT32 | Unit rotation | 16,465 | 16,924 | 136 | 0/0 | 0.646 | 0.000 | 0.000 | 0.000 |
| FFT64 | Baseline | 47,048 | 30,880 | 768 | 0/0 | 0.137 | 0.000 | 0.000 | 0.000 |
| FFT64 | Unit rotation | 38,762 | 39,281 | 392 | 0/0 | 0.196 | 0.000 | 0.000 | 0.000 |

The FFT32 network includes 31 identity and 15 negative-quarter-turn butterflies among 80. FFT64 includes 63 identity and 31 negative-quarter-turn butterflies among 192. Identity forwards the input. The negative quarter turn maps (re, im) to (im, -re). Three registered stages align each result with the bypass and valid paths. Each general rotation still uses four three-cycle DSP48E2 multipliers. The reduction in DSPs and LUTs comes with an increase in fabric FFs for pipeline storage.

The normalized output is FFT/N with six internal fractional bits and final symmetric rounding and saturation. Counting input capture as edge 1, a valid result appears after edge 16 (FFT32) or 19 (FFT64) in both revisions. Corresponding capture-to-result edge separations are 60 and 72 ns. The initiation interval is one clock (4 ns) for either size. The virtual wrapper captures the complete result on the following edge.

Both designs met setup and hold. The external reset and status paths are false paths in this virtual wrapper. The all-zero check_timing counts apply within those constraints. The routed DRC reports list NSTD-1 and UCIO-1 for the virtual pins and AVAL-155 for unused DSP D ports. RTSTAT-10 is absent.

## Worst setup paths in the unit-rotation design

- FFT32 runs from `core/u_s4_b0_12/gen_registered_output.y0_im_reg[0]/C` to `captured_im_reg[100]/D` with a data path delay of 3.170ns  (logic 1.142ns (36.025%)  route 2.028ns (63.975%)).
- FFT64 runs from `core/u_s5_b0_0/gen_registered_output.valid_o_reg/C` to `captured_re_reg[212]/CE` with a data path delay of 3.667ns  (logic 0.079ns (2.154%)  route 3.588ns (97.846%)).

## Functional verification

Both RTL versions passed all three XSim scripts. The stream scoreboard matched 220 FFT32 and 217 FFT64 valid frames, checked bubbles and reset flushing, and required the exact output cycle. MATLAB generated 48 full-range complex random vectors per size with seed 7214. The maximum component errors against direct floating-point DFT/N in that set were 0.52223607 and 0.54594578 LSB. An independent recursive integer model matched those vectors and the four original vectors per size. Reproduction commands are in the [Verilog README](../README.md).
