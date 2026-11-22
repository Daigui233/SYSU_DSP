# 250 MHz clock required by the assignment.
create_clock -name clk -period 4.000 [get_ports clk]
set_clock_uncertainty 0.100 [get_clocks clk]

# RTL samples reset synchronously. External rst/status paths are excluded
# for this virtual wrapper. check_timing does not validate those interfaces.
set_input_delay -clock clk -min 0.000 [get_ports rst]
set_input_delay -clock clk -max 0.000 [get_ports rst]
set_false_path -from [get_ports rst]
set_output_delay -clock clk -min 0.000 [get_ports status]
set_output_delay -clock clk -max 0.000 [get_ports status]
# status is a virtual checksum pin; core frame timing is checked at the
# internal full-width capture registers, while this debug pin is exempted
# from board-level output timing until real package constraints are supplied.
set_false_path -to [get_ports status]
