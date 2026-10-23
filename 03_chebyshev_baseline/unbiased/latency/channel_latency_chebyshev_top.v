`timescale 1ns / 1ps

// Verification wrapper.  The external table interface models the same
// one-cycle synchronous SNR response used in the proposed-engine measurement.
module channel_latency_chebyshev_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        i_start,
    input  wire [31:0] i_snr_linear,
    input  wire [31:0] i_snr_db,
    output wire [7:0]  o_carrier_idx,
    output wire        o_done,
    output wire [15:0] o_updates,
    output wire [15:0] o_refinement_accepts,
    output wire [15:0] o_refinement_scans,
    output wire [11:0] o_total_bits,
    output wire [63:0] o_weighted_err_q24,
    output wire [7:0]  o_final_carrier_idx,
    output wire [2:0]  o_final_m_tier,
    output wire        o_final_valid,
    output wire        o_final_done
);
    wire addr_valid;
    wire [31:0] margin_256, margin_64, margin_16, margin_4;
    wire margin_done, margin_converged, margin_timeout;

    per_qam_bitloading_pipeline_top_chebyshev_q24 u_engine (
        .clk(clk), .rst_n(rst_n), .i_start(i_start),
        .i_snr_linear(i_snr_linear), .i_snr_db(i_snr_db),
        .o_carrier_idx(o_carrier_idx), .o_addr_valid(addr_valid),
        .o_margin_256(margin_256), .o_margin_64(margin_64),
        .o_margin_16(margin_16), .o_margin_4(margin_4),
        .o_margin_done(margin_done), .o_margin_converged(margin_converged),
        .o_margin_timeout(margin_timeout), .o_margin_updates(o_updates),
        .o_refinement_accepts(o_refinement_accepts),
        .o_refinement_scans(o_refinement_scans),
        .o_selected_weighted_err_q24(o_weighted_err_q24),
        .o_selected_total_bits(o_total_bits),
        .o_final_carrier_idx(o_final_carrier_idx),
        .o_final_m_tier(o_final_m_tier),
        .o_final_valid(o_final_valid), .o_final_done(o_final_done),
        .o_done(o_done)
    );
endmodule
