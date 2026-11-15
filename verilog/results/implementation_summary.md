# Implementation summary

Device: `xcvu13p-flga2577-2-i`  
Tool: Vivado 2019.1  
Clock: 250 MHz, 4.000 ns period  
RTL: `src/fft_parallel.sv` using explicit `DSP48E2` multipliers; no Vivado FFT IP

| Top | LUT | FF | DSP48E2 | BRAM | URAM | WNS | TNS | WPWS | TPWS |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `fft32_impl_top` | 13,255 | 8,472 | 320 | 0 | 0 | 0.052 ns | 0.000 ns | 1.725 ns | 0.000 ns |
| `fft64_impl_top` | 31,293 | 21,425 | 768 | 0 | 0 | 0.121 ns | 0.000 ns | 1.725 ns | 0.000 ns |

Both routed timing reports say all user timing constraints are met. The routed DRC reports have no `Error` severity entries. The remaining critical-warning/advisory entries concern the virtual wrapper's unassigned package pins and I/O standards, which are intentionally omitted because the wrapper is used only for core implementation analysis.

Behavioral simulation result: all 8 vectors passed (`FFT32 vector 0..3`, `FFT64 vector 0..3`).
