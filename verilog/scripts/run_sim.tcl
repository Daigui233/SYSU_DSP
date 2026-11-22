set script_dir [file normalize [file dirname [info script]]]
source [file join $script_dir create_project.tcl]
source [file join $script_dir finish_sim.tcl]
