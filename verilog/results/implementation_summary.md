# Implementation summary

Device: `xcvu13p-flga2577-2-i`  
Tool: Vivado 2019.1  
Clock: 250 MHz, 4.000 ns period  
RTL: `src/fft_parallel.sv` using explicit `DSP48E2` multipliers; no Vivado FFT IP
DSP pipeline: AREG/BREG + MREG + PREG, three multiplier cycles
Core latency: FFT32 16 cycles; FFT64 19 cycles
Internal format: 26-bit data with six guard bits; final symmetric rounding and signed 8-bit saturation

| Top | CLB LUT | CLB FF | DSP48E2 | BRAM | URAM | WNS | TNS | WHS | THS |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `fft32_impl_top` | 20,557 | 12,955 | 320 | 0 | 0 | 0.571 ns | 0.000 ns | 0.000 ns | 0.000 ns |
| `fft64_impl_top` | 47,048 | 30,880 | 768 | 0 | 0 | 0.137 ns | 0.000 ns | 0.000 ns | 0.000 ns |

Both routed min/max timing reports say all user timing constraints are met. `check_timing -verbose` reports zero no-clock, no-delay, unconstrained-endpoint, loop, and latch-loop findings. The routed DRC reports have no Error severity entries and no `DSPS-2` or `RTSTAT-10` findings. The remaining critical-warning/advisory entries are the virtual wrapper's unassigned package pins/I/O standards (`NSTD-1`, `UCIO-1`) and the expected unused-D-port advisory (`AVAL-155`); board-specific pin constraints are intentionally omitted because these tops are core implementation analysis wrappers.

Behavioral simulation results: all 8 original vectors passed, four consecutive frames for each FFT size passed, and the fixed-point precision checks passed for +1, +8, -8, +127, and -128 DC inputs. Full reports are in this directory.
