# Usage: vivado -mode batch -source scripts/vivado_build.tcl
# RTL and constraints never include the baseline source tree.
set project_root [file normalize [file join [file dirname [info script]] ..]]
cd $project_root
set output_dir [file join $project_root build vivado]
file mkdir $output_dir
set_param general.maxThreads 4
create_project -in_memory -part xc7a35tcpg236-1
set_property target_language Verilog [current_project]
foreach dir {cpu game input video platform} {
    foreach source [glob -nocomplain [file join rtl $dir *.v]] {read_verilog $source}
}
read_xdc constrs/Basys3_Puyo.xdc
synth_design -top TD8_RISCV_PUYO_TOP -part xc7a35tcpg236-1
report_utilization -hierarchical -file [file join $output_dir utilization_synth.rpt]
report_ram_utilization -file [file join $output_dir ram_synth.rpt]
write_checkpoint -force [file join $output_dir post_synth.dcp]
opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $output_dir post_route.dcp]
report_utilization -hierarchical -file [file join $output_dir utilization_route.rpt]
report_utilization -file [file join $output_dir utilization_summary.rpt]
report_ram_utilization -file [file join $output_dir ram_route.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -file [file join $output_dir timing_summary.rpt]
report_timing -max_paths 20 -input_pins -file [file join $output_dir timing_worst20.rpt]
report_clock_utilization -file [file join $output_dir clocks.rpt]
report_cdc -file [file join $output_dir cdc.rpt]
report_methodology -file [file join $output_dir methodology.rpt]
report_drc -file [file join $output_dir drc.rpt]
report_power -file [file join $output_dir power_estimate.rpt]
# Gate bitstream on setup/hold checks. Do not waive unconstrained CPU paths.
set setup_paths [get_timing_paths -delay_type max -max_paths 1]
set hold_paths [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup_paths] == 0 || [llength $hold_paths] == 0} {error "Missing timing paths"}
if {[get_property SLACK $setup_paths] < 0 || [get_property SLACK $hold_paths] < 0} {
    error "Timing not closed; reports saved, no bitstream issued"
}
write_bitstream -force [file join $output_dir TD8_RISCV_PUYO_TOP.bit]
puts "PASS: synthesis, place/route, setup/hold, bitstream generation"
