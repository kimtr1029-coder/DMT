create_clock -name clk -period 10.000 [get_ports {clk}]
set_clock_uncertainty 0.100 [get_clocks {clk}]
set_input_delay 0.0 -clock clk [all_inputs]
set_output_delay 0.0 -clock clk [all_outputs]
