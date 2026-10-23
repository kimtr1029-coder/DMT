onerror {quit -code 1}
if {[file exists work]} {vdel -lib work -all}
vlib work
vmap work work

vlog -sv +incdir+rtl rtl/piecewise_cheb_coeff_rom_q30.v
vlog -sv +incdir+rtl rtl/cheb_poly_degree4_q30_pipe.v
vlog -sv +incdir+rtl rtl/per_qam_datapath_chebyshev_q24.v
vlog -sv +incdir+rtl rtl/per_qam_margin_ctrl_direct_erfc.v
vlog -sv +incdir+rtl rtl/per_qam_bitloading_pipeline_top_chebyshev_q24.v
vlog -sv +incdir+rtl latency/channel_latency_chebyshev_top.v
vlog -sv +incdir+rtl latency/tb_channel_latency_chebyshev.sv

vsim -c work.tb_channel_latency_chebyshev \
    +PROFILE=channel25 \
    +DB_FILE=latency/channel25_snr_db_q16.mem \
    +LINEAR_FILE=latency/channel25_snr_linear_q16.mem
run -all
quit -sim

vsim -c work.tb_channel_latency_chebyshev \
    +PROFILE=two_null \
    +DB_FILE=latency/two_null_snr_db_q16.mem \
    +LINEAR_FILE=latency/two_null_snr_linear_q16.mem
run -all
quit -sim
quit -f
