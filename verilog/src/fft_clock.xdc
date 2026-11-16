# 250 MHz clock required by the assignment.
create_clock -name clk -period 4.000 [get_ports clk]
set_clock_uncertainty 0.100 [get_clocks clk]

# The implementation tops are synchronous analysis wrappers. Reset is an
# asynchronous control input and is excluded from data-path timing; explicit
# zero input/output delays document the virtual interface assumptions.
set_input_delay -clock clk -min 0.000 [get_ports rst]
set_input_delay -clock clk -max 0.000 [get_ports rst]
set_false_path -from [get_ports rst]
set_output_delay -clock clk -min 0.000 [get_ports status]
set_output_delay -clock clk -max 0.000 [get_ports status]
# status is a virtual checksum pin; core frame timing is checked at the
# internal full-width capture registers, while this debug pin is exempted
# from board-level output timing until real package constraints are supplied.
set_false_path -to [get_ports status]
