# Verilog FFT implementation

This directory contains the assignment's 32-point and 64-point fully parallel radix-2 FFT.

- `src/fft_parallel.sv`: synthesizable RTL. Samples are signed 8-bit complex values packed with sample 0 at the least-significant byte. Each butterfly divides by two, so the output is a normalized fixed-point FFT.
- `src/fft_clock.xdc`: 250 MHz clock constraint.
- `tests/tb_fft.sv`: Vivado behavioral testbench for impulse, constant, random, and signed-complex-ramp vectors.
- `tests/tb_fft_cont.sv`: back-to-back four-frame test for checking pipeline alignment across consecutive valid cycles.
- `tests/fft_fixed_reference.m`: MATLAB fixed-point reference model used to generate/check the expected values.
- `scripts/create_project.tcl`: reconstructs the Vivado project.
- `scripts/run_sim.tcl`: runs the behavioral simulation.
- `scripts/run_sim_cont.tcl`: runs the contiguous-frame behavioral simulation.
- `scripts/run_impl.tcl`: synthesizes, places and routes both tops and writes utilization/timing/DRC reports to `results/`.

## Verified implementation

The implementation was run with Vivado 2019.1 for `xcvu13p-flga2577-2-i` using the supplied 250 MHz constraint (4.000 ns period). The FFT cores are fully parallel and do not use the Vivado FFT IP. The implementation-only tops in `src/fft_impl_top.sv` generate a small internal frame so the wide functional buses do not become package pins; the complete FFT core remains inside each top and is protected from removal.

| Top | LUT | FF | DSP48E2 | BRAM/URAM | WNS | TNS | WPWS/TPWS |
|---|---:|---:|---:|---:|---:|---:|---:|
| `fft32_impl_top` | 13,255 | 8,472 | 320 | 0 / 0 | 0.034 ns | 0.000 ns | 1.725 / 0.000 ns |
| `fft64_impl_top` | 31,293 | 21,425 | 768 | 0 / 0 | 0.138 ns | 0.000 ns | 1.725 / 0.000 ns |

Both timing reports state that all user timing constraints are met. The routed DRC reports contain no `Error` severity violations. They retain expected wrapper warnings for unspecified package I/O standards and pins, because these implementation tops are virtual analysis wrappers and are not intended to generate a board bitstream. Full reports are in `results/`.

The Vivado behavioral simulation passes all eight 32-point and 64-point test cases. A separate contiguous-frame simulation passes four 32-point and four 64-point frames presented on consecutive cycles, verifying that the valid marker and bypass path remain aligned with the DSP48E2 multiplier pipeline. The output is the normalized fixed-point FFT described above, with one divide-by-two scaling operation per radix-2 stage.

Open Vivado 2019.1 with the license environment configured, then run:

```tcl
cd <repository>/verilog/scripts
source run_sim.tcl
source run_sim_cont.tcl
source run_impl.tcl
```

The simulation scripts wait past Vivado's global-set/reset interval before sending the first frame. This is required for the behavioral DSP48E2 model; it does not add a functional protocol requirement to the synthesized core.

The RTL uses four DSP48E2 multipliers per butterfly. Each DSP wrapper has registered A/B and multiplier stages; the butterfly datapath aligns the add/subtract path and valid marker with the multiplier pipeline. The DSP48E2 OPMODE selects the direct multiplier path without PCIN. The design does not instantiate the vendor FFT IP.
