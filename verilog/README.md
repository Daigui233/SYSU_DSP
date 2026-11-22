# Verilog FFT implementation

This directory contains the assignment's 32-point and 64-point fully parallel radix-2 FFT.

- `src/fft_parallel.sv`: synthesizable RTL. Samples are signed 8-bit complex values packed with sample 0 at the least-significant byte. Each butterfly divides by two, so the transform is normalized by N. The internal datapath is 26 bits wide with six guard bits; the final result uses symmetric rounding and saturation to signed 8 bits.
- `src/fft_clock.xdc`: 250 MHz clock constraint plus explicit virtual-wrapper input/output assumptions.
- `src/fft_impl_top.sv`: implementation-only wrappers. They generate an internal frame and capture every real and imaginary FFT output bit in clocked registers before generating the narrow status checksum.
- `tests/tb_fft.sv`: Vivado behavioral testbench for impulse, constant, random, and signed-complex-ramp vectors, with timeout failure checks.
- `tests/tb_fft_cont.sv`: 400-cycle scoreboard for exact valid timing and frame data, including bubbles, continuous traffic, pipeline reset and drain.
- `tests/tb_fft_precision.sv`: DC/full-scale fixed-point boundary checks.
- `tests/fft_fixed_reference.m`: MATLAB fixed-point reference model used to generate/check the expected values.
- `scripts/create_project.tcl`: reconstructs the Vivado project.
- `scripts/run_sim.tcl`: runs the basic behavioral simulation.
- `scripts/run_sim_cont.tcl`: runs the contiguous-frame behavioral simulation.
- `scripts/run_sim_precision.tcl`: runs the fixed-point boundary simulation.
- `scripts/run_impl.tcl`: synthesizes, places and routes both tops and writes utilization, min/max timing, check_timing, and DRC reports to `results/`.

## Verified implementation

The implementation was run with Vivado 2019.1 for `xcvu13p-flga2577-2-i` using the supplied 250 MHz constraint (4.000 ns period). The FFT cores are fully parallel and do not use the Vivado FFT IP. Unit rotations use three registered sign/swap stages. Every other butterfly uses four explicit DSP48E2 multipliers. Each multiplier has AREG/BREG, MREG, and PREG enabled, so the multiplier result takes three clock cycles; the bypass path and valid marker use the same three-cycle alignment. Counting the input capture as edge 1, the result is valid after edge 16 for FFT32 and edge 19 for FFT64. Each core can accept one frame per clock. The implementation-only tops in `src/fft_impl_top.sv` generate a small internal frame so the wide functional buses do not become package pins; the complete FFT core remains inside each top and every output bit is captured at the valid boundary.

| Core | RTL | CLB LUT | CLB FF | DSP48E2 | BRAM/URAM | WNS (ns) | TNS (ns) | WHS (ns) | THS (ns) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| FFT32 | Baseline | 20,557 | 12,955 | 320 | 0/0 | 0.571 | 0.000 | 0.000 | 0.000 |
| FFT32 | Unit rotation | 16,465 | 16,924 | 136 | 0/0 | 0.646 | 0.000 | 0.000 | 0.000 |
| FFT64 | Baseline | 47,048 | 30,880 | 768 | 0/0 | 0.137 | 0.000 | 0.000 | 0.000 |
| FFT64 | Unit rotation | 38,762 | 39,281 | 392 | 0/0 | 0.196 | 0.000 | 0.000 | 0.000 |

The [implementation comparison](results/implementation_summary.md) records the routed critical paths and the resource trade-off. External reset and status paths are excluded by the virtual wrapper constraints.

Both min/max timing reports state that all user timing constraints are met, and `check_timing -verbose` reports zero no-clock, no-delay, unconstrained-endpoint, loop, and latch-loop findings. The routed DRC reports contain no Error severity violations and no DSPS-2 or RTSTAT-10 findings. They retain the expected virtual-wrapper `NSTD-1`/`UCIO-1` critical warnings for unspecified package pins and the AVAL-155 advisory for unused DSP D ports; these wrappers are for core implementation analysis and are not intended to generate a board bitstream without board-specific pin constraints.

The baseline and unit-rotation RTL both passed all three Vivado 2019.1 behavioral tests. The stream scoreboard checked 220 FFT32 and 217 FFT64 outputs in 400 cycles. It checks every valid bit after the rising edge and compares every valid real and imaginary output byte. The directed tests include +1, +8, -8, +127 and -128 DC inputs. The stream includes all 48 seeded complex vectors per size. An independent recursive integer reference matched all 104 size/vector cases in the two vector files bit for bit.

In MATLAB, run `addpath('verilog/tests'); make_stream_vectors` from the repository root to regenerate the stream vectors. For seed 7214 the largest component differences from a direct floating-point DFT/N were 0.52223607 LSB (FFT32) and 0.54594578 LSB (FFT64) over those 48 frames per size. The XSim scripts run to completion with a 10 us simulation watchdog and check an explicit pass flag. A one-edge latency fault in a temporary copy triggered the scoreboard and returned batch exit code 1.

Run each flow as a separate batch process so one script cannot terminate the Vivado process needed by the next flow:

```powershell
cd <repository>\verilog\scripts
& <Vivado>\bin\vivado.bat -mode batch -source run_sim.tcl
& <Vivado>\bin\vivado.bat -mode batch -source run_sim_cont.tcl
& <Vivado>\bin\vivado.bat -mode batch -source run_sim_precision.tcl
& <Vivado>\bin\vivado.bat -mode batch -source run_impl.tcl
```

The simulation scripts wait past Vivado's global-set/reset interval before sending the first frame. This is required for the behavioral DSP48E2 model; it does not add a functional protocol requirement to the synthesized core.
