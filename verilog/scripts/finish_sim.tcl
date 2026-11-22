set sim_top [get_property top [get_filesets sim_1]]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
run all
set passed [get_value -radix bin /${sim_top}/passed]
close_sim -force
close_project
if {$passed ne "1"} {error "$sim_top terminated without passing"}
