`timescale 1ns / 1ps

module per_qam_bitloading_pipeline_top_chebyshev_q24 #(
    parameter integer N_SUBCARRIERS          = 255,
    parameter integer MAX_MARGIN_UPDATES     = 1000,
    parameter integer MAX_REFINEMENT_ACCEPTS = 1000,
    parameter [24:0] TARGET_RHS_PER_BIT_Q24  = 25'd16617216
)(
    input wire clk, input wire rst_n, input wire i_start,
    input wire [31:0] i_snr_linear, input wire [31:0] i_snr_db,
    output wire [7:0] o_carrier_idx, output wire o_addr_valid,
    output wire [31:0] o_margin_256, o_margin_64, o_margin_16, o_margin_4,
    output wire o_margin_done, o_margin_converged, o_margin_timeout,
    output wire [15:0] o_margin_updates, o_refinement_accepts, o_refinement_scans,
    output wire [63:0] o_selected_weighted_err_q24,
    output wire [11:0] o_selected_total_bits,
    output wire [7:0] o_final_carrier_idx,
    output wire [2:0] o_final_m_tier,
    output wire o_final_valid, o_final_done, o_done
);
    wire [23:0] error_q24;
    wire [2:0] tier;
    wire error_valid;

    per_qam_margin_ctrl_direct_erfc #(
        .N_SUBCARRIERS(N_SUBCARRIERS),
        .MAX_MARGIN_UPDATES(MAX_MARGIN_UPDATES),
        .MAX_REFINEMENT_ACCEPTS(MAX_REFINEMENT_ACCEPTS),
        .MARGIN_STEP_Q16(32'd6554),
        .TARGET_RHS_PER_BIT_Q24(TARGET_RHS_PER_BIT_Q24)
    ) u_ctrl (
        .clk(clk), .rst_n(rst_n), .i_start(i_start),
        .i_subcarrier_err(error_q24), .i_m_tier(tier), .i_err_valid(error_valid),
        .o_carrier_idx(o_carrier_idx), .o_addr_valid(o_addr_valid),
        .o_margin_256(o_margin_256), .o_margin_64(o_margin_64),
        .o_margin_16(o_margin_16), .o_margin_4(o_margin_4),
        .o_margin_done(o_margin_done), .o_margin_converged(o_margin_converged),
        .o_margin_timeout(o_margin_timeout), .o_margin_updates(o_margin_updates),
        .o_refinement_accepts(o_refinement_accepts),
        .o_refinement_scans(o_refinement_scans),
        .o_selected_weighted_err_q24(o_selected_weighted_err_q24),
        .o_selected_total_bits(o_selected_total_bits),
        .o_final_carrier_idx(o_final_carrier_idx), .o_final_m_tier(o_final_m_tier),
        .o_final_valid(o_final_valid), .o_final_done(o_final_done), .o_done(o_done)
    );

    per_qam_datapath_chebyshev_q24 u_datapath (
        .clk(clk), .rst_n(rst_n), .i_valid(o_addr_valid), .o_valid(error_valid),
        .i_snr_linear(i_snr_linear), .i_snr_db(i_snr_db),
        .i_margin_256(o_margin_256), .i_margin_64(o_margin_64),
        .i_margin_16(o_margin_16), .i_margin_4(o_margin_4),
        .o_subcarrier_err(error_q24), .o_m_tier(tier)
    );
endmodule
