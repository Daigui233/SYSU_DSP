set script_dir [file normalize [file dirname [info script]]]
set verilog_dir [file normalize [file join $script_dir ..]]
set build_dir [file normalize [file join $verilog_dir build_precision_sim]]
file mkdir $build_dir
create_project -force sysu_dsp_fft_precision [file join $build_dir project] -part xcvu13p-flga2577-2-i
add_files [file join $verilog_dir src fft_parallel.sv]
add_files -fileset sim_1 [file join $verilog_dir tests tb_fft_precision.sv]
set_property file_type SystemVerilog [get_files [file join $verilog_dir src fft_parallel.sv]]
set_property file_type SystemVerilog [get_files [file join $verilog_dir tests tb_fft_precision.sv]]
set_property top tb_fft_precision [get_filesets sim_1]
set_property top fft32_parallel [get_filesets sources_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
source [file join $script_dir finish_sim.tcl]
