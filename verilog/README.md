# Verilog FFT implementation

This directory contains the assignment's 32-point and 64-point fully parallel radix-2 FFT.

- `src/fft_parallel.sv`: synthesizable RTL. Samples are signed 8-bit complex values packed with sample 0 at the least-significant byte. Each butterfly divides by two, so the transform is normalized by N. The internal datapath is 26 bits wide with six guard bits; the final result uses symmetric rounding and saturation to signed 8 bits.
- `src/fft_clock.xdc`: 250 MHz clock constraint plus explicit virtual-wrapper input/output assumptions.
- `src/fft_impl_top.sv`: implementation-only wrappers. They generate an internal frame and capture every real and imaginary FFT output bit in clocked registers before generating the narrow status checksum.
- `tests/tb_fft.sv`: Vivado behavioral testbench for impulse, constant, random, and signed-complex-ramp vectors, with timeout failure checks.
- `tests/tb_fft_cont.sv`: back-to-back four-frame test for checking pipeline alignment across consecutive valid cycles.
- `tests/tb_fft_precision.sv`: DC/full-scale fixed-point boundary checks.
- `tests/fft_fixed_reference.m`: MATLAB fixed-point reference model used to generate/check the expected values.
- `scripts/create_project.tcl`: reconstructs the Vivado project.
- `scripts/run_sim.tcl`: runs the basic behavioral simulation.
- `scripts/run_sim_cont.tcl`: runs the contiguous-frame behavioral simulation.
- `scripts/run_sim_precision.tcl`: runs the fixed-point boundary simulation.
- `scripts/run_impl.tcl`: synthesizes, places and routes both tops and writes utilization, min/max timing, check_timing, and DRC reports to `results/`.

## Verified implementation

The implementation was run with Vivado 2019.1 for `xcvu13p-flga2577-2-i` using the supplied 250 MHz constraint (4.000 ns period). The FFT cores are fully parallel and do not use the Vivado FFT IP. Every butterfly uses four explicit DSP48E2 multipliers. Each multiplier has AREG/BREG, MREG, and PREG enabled, so the multiplier result takes three clock cycles; the bypass path and valid marker use the same three-cycle alignment. The total core latency is 16 cycles for FFT32 and 19 cycles for FFT64. The implementation-only tops in `src/fft_impl_top.sv` generate a small internal frame so the wide functional buses do not become package pins; the complete FFT core remains inside each top and every output bit is captured at the valid boundary.

| Top | CLB LUT | CLB FF | DSP48E2 | BRAM/URAM | WNS | TNS | WHS | THS |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `fft32_impl_top` | 20,557 | 12,955 | 320 | 0 / 0 | 0.571 ns | 0.000 ns | 0.000 ns | 0.000 ns |
| `fft64_impl_top` | 47,048 | 30,880 | 768 | 0 / 0 | 0.137 ns | 0.000 ns | 0.000 ns | 0.000 ns |

Both min/max timing reports state that all user timing constraints are met, and `check_timing -verbose` reports zero no-clock, no-delay, unconstrained-endpoint, loop, and latch-loop findings. The routed DRC reports contain no Error severity violations and no DSPS-2 or RTSTAT-10 findings. They retain the expected virtual-wrapper `NSTD-1`/`UCIO-1` critical warnings for unspecified package pins and the AVAL-155 advisory for unused DSP D ports; these wrappers are for core implementation analysis and are not intended to generate a board bitstream without board-specific pin constraints.

The Vivado behavioral simulation passes all eight original 32-point and 64-point test cases. The contiguous-frame simulation passes four frames for each FFT size at consecutive valid cycles, and the precision simulation passes +1, +8, -8, +127, and -128 DC/full-scale checks for both sizes. The output is the normalized fixed-point FFT described above, with one divide-by-two scaling operation per radix-2 stage and final six-bit symmetric rounding.

Run each flow as a separate batch process so one script cannot terminate the Vivado process needed by the next flow:

```powershell
cd <repository>\verilog\scripts
& <Vivado>\bin\vivado.bat -mode batch -source run_sim.tcl
& <Vivado>\bin\vivado.bat -mode batch -source run_sim_cont.tcl
& <Vivado>\bin\vivado.bat -mode batch -source run_sim_precision.tcl
& <Vivado>\bin\vivado.bat -mode batch -source run_impl.tcl
```

The simulation scripts wait past Vivado's global-set/reset interval before sending the first frame. This is required for the behavioral DSP48E2 model; it does not add a functional protocol requirement to the synthesized core.
