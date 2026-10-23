`timescale 1ns / 1ps

// Same-algorithm, pre-optimization arithmetic baseline.
// The external interface and final QAM allocation semantics match
// per_qam_bitloading_pipeline_top_balanced exactly.
module per_qam_bitloading_pipeline_top_unoptimized_baseline #(
    parameter integer N_SUBCARRIERS          = 255,
    parameter integer MAX_MARGIN_UPDATES     = 1000,
    parameter integer MAX_REFINEMENT_ACCEPTS = 1000,

    parameter [31:0] K_256 = 32'd602,
    parameter [31:0] C_256 = 32'd6506,
    parameter [31:0] K_64  = 32'd2436,
    parameter [31:0] C_64  = 32'd8057,
    parameter [31:0] K_16  = 32'd10213,
    parameter [31:0] C_16  = 32'd10206,
    parameter [31:0] K_4   = 32'd50734,
    parameter [31:0] C_4   = 32'd12756
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         i_start,

    // The external SNR table must present the entry selected by
    // o_carrier_idx. o_addr_valid qualifies the corresponding input pair.
    input  wire [31:0]  i_snr_linear,
    input  wire [31:0]  i_snr_db,

    output wire [7:0]   o_carrier_idx,
    output wire         o_addr_valid,

    output wire [31:0]  o_margin_256,
    output wire [31:0]  o_margin_64,
    output wire [31:0]  o_margin_16,
    output wire [31:0]  o_margin_4,

    output wire         o_margin_done,
    output wire         o_margin_converged,
    output wire         o_margin_timeout,
    output wire [15:0]  o_margin_updates,
    output wire [15:0]  o_refinement_accepts,
    output wire [15:0]  o_refinement_scans,

    output wire [63:0]  o_selected_weighted_err_q24,
    output wire [11:0]  o_selected_total_bits,

    output wire [7:0]   o_final_carrier_idx,
    output wire [2:0]   o_final_m_tier,
    output wire         o_final_valid,
    output wire         o_final_done,
    output wire         o_done
);

    wire [23:0] w_subcarrier_err;
    wire [2:0]  w_m_tier;
    wire        w_err_valid;

    per_qam_margin_ctrl_unoptimized_baseline #(
        .N_SUBCARRIERS(N_SUBCARRIERS),
        .MAX_MARGIN_UPDATES(MAX_MARGIN_UPDATES),
        .MAX_REFINEMENT_ACCEPTS(MAX_REFINEMENT_ACCEPTS),
        .MARGIN_STEP_Q16(32'd6554)
    ) u_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .i_start(i_start),
        .i_subcarrier_err(w_subcarrier_err),
        .i_m_tier(w_m_tier),
        .i_err_valid(w_err_valid),
        .o_carrier_idx(o_carrier_idx),
        .o_addr_valid(o_addr_valid),
        .o_margin_256(o_margin_256),
        .o_margin_64(o_margin_64),
        .o_margin_16(o_margin_16),
        .o_margin_4(o_margin_4),
        .o_margin_done(o_margin_done),
        .o_margin_converged(o_margin_converged),
        .o_margin_timeout(o_margin_timeout),
        .o_margin_updates(o_margin_updates),
        .o_refinement_accepts(o_refinement_accepts),
        .o_refinement_scans(o_refinement_scans),
        .o_selected_weighted_err_q24(o_selected_weighted_err_q24),
        .o_selected_total_bits(o_selected_total_bits),
        .o_final_carrier_idx(o_final_carrier_idx),
        .o_final_m_tier(o_final_m_tier),
        .o_final_valid(o_final_valid),
        .o_final_done(o_final_done),
        .o_done(o_done)
    );

    per_qam_datapath_unoptimized_baseline #(
        .K_256(K_256), .C_256(C_256),
        .K_64(K_64),   .C_64(C_64),
        .K_16(K_16),   .C_16(C_16),
        .K_4(K_4),     .C_4(C_4)
    ) u_datapath (
        .clk(clk),
        .rst_n(rst_n),
        .i_valid(o_addr_valid),
        .o_valid(w_err_valid),
        .i_snr_linear(i_snr_linear),
        .i_snr_db(i_snr_db),
        .i_margin_256(o_margin_256),
        .i_margin_64(o_margin_64),
        .i_margin_16(o_margin_16),
        .i_margin_4(o_margin_4),
        .o_subcarrier_err(w_subcarrier_err),
        .o_m_tier(w_m_tier)
    );

endmodule
