set script_dir [file normalize [file dirname [info script]]]
set verilog_dir [file normalize [file join $script_dir ..]]
set build_dir [file normalize [file join $verilog_dir build_impl2]]
set result_dir [file normalize [file join $verilog_dir results]]
file mkdir $build_dir
file mkdir $result_dir
foreach top {fft32_impl_top fft64_impl_top} {
    set pdir [file join $build_dir $top]
    create_project -force $top $pdir -part xcvu13p-flga2577-2-i
    add_files [file join $verilog_dir src fft_parallel.sv]
    add_files [file join $verilog_dir src fft_impl_top.sv]
    add_files -fileset constrs_1 [file join $verilog_dir src fft_clock.xdc]
    set_property file_type SystemVerilog [get_files [file join $verilog_dir src fft_parallel.sv]]
    set_property top $top [get_filesets sources_1]
    update_compile_order -fileset sources_1
    launch_runs impl_1 -to_step route_design -jobs 2
    wait_on_run impl_1
    open_run impl_1
    report_utilization -file [file join $result_dir ${top}_utilization.rpt]
    report_timing_summary -delay_type min_max -max_paths 20 -warn_on_violation -file [file join $result_dir ${top}_timing.rpt]
    check_timing -verbose -file [file join $result_dir ${top}_check_timing.rpt]
    report_drc -file [file join $result_dir ${top}_drc.rpt]
    close_project
}
