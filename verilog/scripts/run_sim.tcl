set script_dir [file normalize [file dirname [info script]]]
source [file join $script_dir create_project.tcl]
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim -force
close_project
exit
