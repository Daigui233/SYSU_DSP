# 250 MHz clock required by the assignment.
create_clock -name clk -period 4.000 [get_ports clk]
set_clock_uncertainty 0.100 [get_clocks clk]
