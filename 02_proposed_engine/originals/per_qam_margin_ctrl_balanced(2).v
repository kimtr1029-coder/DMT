`timescale 1ns / 1ps

// ============================================================================
// per_qam_margin_ctrl_balanced
//
// Final controller for the single conservative fitted-LUT engine.
//
// Phase 1 - upward search
//   Scan all tones, test the bit-weighted BER target, and increase the margin
//   of the QAM tier with the largest average estimated BER.
//
// Phase 2 - downward local refinement
//   Test each eligible one-step margin decrement.  Among all candidates that
//   still meet the target, accept the candidate with the largest loaded-bit
//   count (fixed tie priority: 4, 16, 64, 256-QAM).  Repeat until no one-step
//   decrement passes.  The final point is therefore coordinate-wise local for
//   the implemented 0.1-dB grid.
//
// BER arithmetic is Q24.  Conservative coefficients cover exact BER down to
// 2^-20.  The divider-free target reserves that residual explicitly:
//
//   estimated_BER <= 1/10000 - 2^-20
//   weighted_err_q24*10000 <= total_bits*(2^24 - 10000*2^4)
//
// There is no alpha scan, correction factor, or validator/fallback path.
// ============================================================================
module per_qam_margin_ctrl_balanced #(
    parameter integer N_SUBCARRIERS          = 255,
    parameter integer MAX_MARGIN_UPDATES     = 1000,
    parameter integer MAX_REFINEMENT_ACCEPTS = 1000,
    parameter [31:0] MARGIN_STEP_Q16         = 32'd6554
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         i_start,

    input  wire [23:0]  i_subcarrier_err,
    input  wire [2:0]   i_m_tier,
    input  wire         i_err_valid,

    output reg  [7:0]   o_carrier_idx,
    output reg          o_addr_valid,

    output reg  [31:0]  o_margin_256,
    output reg  [31:0]  o_margin_64,
    output reg  [31:0]  o_margin_16,
    output reg  [31:0]  o_margin_4,

    output reg          o_margin_done,
    output reg          o_margin_converged,
    output reg          o_margin_timeout,
    output reg  [15:0]  o_margin_updates,
    output reg  [15:0]  o_refinement_accepts,
    output reg  [15:0]  o_refinement_scans,

    output reg  [63:0]  o_selected_weighted_err_q24,
    output reg  [11:0]  o_selected_total_bits,

    output reg  [7:0]   o_final_carrier_idx,
    output reg  [2:0]   o_final_m_tier,
    output reg          o_final_valid,
    output reg          o_final_done,
    output reg          o_done
);

    localparam [4:0] S_IDLE            = 5'd0;
    localparam [4:0] S_UP_INIT         = 5'd1;
    localparam [4:0] S_UP_SCAN         = 5'd2;
    localparam [4:0] S_UP_DECIDE       = 5'd3;
    localparam [4:0] S_XA              = 5'd4;
    localparam [4:0] S_XB              = 5'd5;
    localparam [4:0] S_XC              = 5'd6;
    localparam [4:0] S_XD              = 5'd7;
    localparam [4:0] S_CMP_1           = 5'd8;
    localparam [4:0] S_XFA             = 5'd9;
    localparam [4:0] S_XFB             = 5'd10;
    localparam [4:0] S_UP_UPDATE       = 5'd11;
    localparam [4:0] S_REF_ROUND_BEGIN = 5'd12;
    localparam [4:0] S_REF_PREP        = 5'd13;
    localparam [4:0] S_REF_SCAN_INIT   = 5'd14;
    localparam [4:0] S_REF_SCAN        = 5'd15;
    localparam [4:0] S_REF_DECIDE      = 5'd16;
    localparam [4:0] S_REF_APPLY       = 5'd17;
    localparam [4:0] S_OUTPUT_INIT     = 5'd18;
    localparam [4:0] S_OUTPUT_STREAM   = 5'd19;
    localparam [4:0] S_DONE            = 5'd20;

    // 2^24 - 10000*(2^24/2^20) = 16,617,216.
    localparam [23:0] TARGET_RHS_PER_BIT_Q24 = 24'd16617216;

    reg [4:0] state;
    reg [8:0] req_cnt;
    reg [8:0] rsp_cnt;
    reg       delay_valid;

    // Maximum generic bounds: 255 tones, 8 bits/tone, 24-bit BER/tone.
    reg [34:0] weighted_err_sum;
    reg [11:0] total_bits_sum;

    reg [31:0] err_sum_256, err_sum_64, err_sum_16, err_sum_4;
    reg [8:0]  cnt_256, cnt_64, cnt_16, cnt_4;

    reg [40:0] cross_A, cross_B, cross_C, cross_D;
    reg [40:0] cross_final_A, cross_final_B;

    reg [2:0]  win12_id, win34_id;
    reg [31:0] win12_err, win34_err;
    reg [8:0]  win12_cnt, win34_cnt;

    // Accepted allocation statistics are retained while candidates are tested.
    reg [34:0] accepted_weighted_err;
    reg [11:0] accepted_total_bits;

    reg [1:0] ref_candidate_idx;
    reg       ref_best_found;
    reg [11:0] ref_best_total_bits;
    reg [34:0] ref_best_weighted_err;

    reg [31:0] ref_base_margin_256, ref_base_margin_64;
    reg [31:0] ref_base_margin_16,  ref_base_margin_4;
    reg [31:0] ref_best_margin_256, ref_best_margin_64;
    reg [31:0] ref_best_margin_16,  ref_best_margin_4;

    function [3:0] bits_from_tier;
        input [2:0] tier;
        begin
            case (tier)
                3'd4: bits_from_tier = 4'd8;
                3'd3: bits_from_tier = 4'd6;
                3'd2: bits_from_tier = 4'd4;
                3'd1: bits_from_tier = 4'd2;
                default: bits_from_tier = 4'd0;
            endcase
        end
    endfunction

    function [34:0] weighted_error_term;
        input [23:0] err_q24;
        input [2:0]  tier;
        reg [34:0] ext;
        begin
            ext = {11'd0, err_q24};
            case (tier)
                3'd4: weighted_error_term = ext << 3;
                3'd3: weighted_error_term = (ext << 2) + (ext << 1);
                3'd2: weighted_error_term = ext << 2;
                3'd1: weighted_error_term = ext << 1;
                default: weighted_error_term = 35'd0;
            endcase
        end
    endfunction

    function [48:0] times_10000;
        input [34:0] value;
        reg [48:0] ext;
        begin
            ext = {14'd0, value};
            times_10000 = (ext << 13) + (ext << 10) + (ext << 9) +
                          (ext << 8)  + (ext << 4);
        end
    endfunction

    wire [35:0] target_rhs_small = total_bits_sum * TARGET_RHS_PER_BIT_Q24;
    wire [48:0] target_rhs = {13'd0, target_rhs_small};
    wire target_met = (total_bits_sum == 12'd0) ||
                      (times_10000(weighted_err_sum) <= target_rhs);

    // One shared 32x9 multiplier is reused during six non-streaming cycles.
    reg [31:0] mul_err;
    reg [8:0]  mul_cnt;
    wire [40:0] mul_product = mul_err * mul_cnt;

    always @(*) begin
        mul_err = 32'd0;
        mul_cnt = 9'd0;
        case (state)
            S_XA:  begin mul_err = err_sum_256; mul_cnt = cnt_64;    end
            S_XB:  begin mul_err = err_sum_64;  mul_cnt = cnt_256;   end
            S_XC:  begin mul_err = err_sum_16;  mul_cnt = cnt_4;     end
            S_XD:  begin mul_err = err_sum_4;   mul_cnt = cnt_16;    end
            S_XFA: begin mul_err = win12_err;   mul_cnt = win34_cnt; end
            S_XFB: begin mul_err = win34_err;   mul_cnt = win12_cnt; end
            default: begin end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            req_cnt <= 9'd0;
            rsp_cnt <= 9'd0;
            delay_valid <= 1'b0;

            o_carrier_idx <= 8'd0;
            o_addr_valid <= 1'b0;

            o_margin_256 <= 32'd0;
            o_margin_64  <= 32'd0;
            o_margin_16  <= 32'd0;
            o_margin_4   <= 32'd0;

            o_margin_done <= 1'b0;
            o_margin_converged <= 1'b0;
            o_margin_timeout <= 1'b0;
            o_margin_updates <= 16'd0;
            o_refinement_accepts <= 16'd0;
            o_refinement_scans <= 16'd0;

            o_selected_weighted_err_q24 <= 64'd0;
            o_selected_total_bits <= 12'd0;

            o_final_carrier_idx <= 8'd0;
            o_final_m_tier <= 3'd0;
            o_final_valid <= 1'b0;
            o_final_done <= 1'b0;
            o_done <= 1'b0;

            weighted_err_sum <= 35'd0;
            total_bits_sum <= 12'd0;
            err_sum_256 <= 32'd0; err_sum_64 <= 32'd0;
            err_sum_16 <= 32'd0;  err_sum_4 <= 32'd0;
            cnt_256 <= 9'd0; cnt_64 <= 9'd0;
            cnt_16 <= 9'd0; cnt_4 <= 9'd0;

            cross_A <= 41'd0; cross_B <= 41'd0;
            cross_C <= 41'd0; cross_D <= 41'd0;
            cross_final_A <= 41'd0; cross_final_B <= 41'd0;
            win12_id <= 3'd0; win34_id <= 3'd0;
            win12_err <= 32'd0; win34_err <= 32'd0;
            win12_cnt <= 9'd0; win34_cnt <= 9'd0;

            accepted_weighted_err <= 35'd0;
            accepted_total_bits <= 12'd0;

            ref_candidate_idx <= 2'd0;
            ref_best_found <= 1'b0;
            ref_best_total_bits <= 12'd0;
            ref_best_weighted_err <= 35'd0;
            ref_base_margin_256 <= 32'd0; ref_base_margin_64 <= 32'd0;
            ref_base_margin_16 <= 32'd0;  ref_base_margin_4 <= 32'd0;
            ref_best_margin_256 <= 32'd0; ref_best_margin_64 <= 32'd0;
            ref_best_margin_16 <= 32'd0;  ref_best_margin_4 <= 32'd0;
        end else begin
            // Request valid follows the registered address by one clock.
            o_addr_valid <= delay_valid;
            o_margin_done <= 1'b0;
            o_final_valid <= 1'b0;
            o_final_done <= 1'b0;
            o_done <= 1'b0;

            case (state)
                S_IDLE: begin
                    delay_valid <= 1'b0;
                    if (i_start) begin
                        o_margin_256 <= 32'd0;
                        o_margin_64  <= 32'd0;
                        o_margin_16  <= 32'd0;
                        o_margin_4   <= 32'd0;
                        o_margin_converged <= 1'b0;
                        o_margin_timeout <= 1'b0;
                        o_margin_updates <= 16'd0;
                        o_refinement_accepts <= 16'd0;
                        o_refinement_scans <= 16'd0;
                        o_selected_weighted_err_q24 <= 64'd0;
                        o_selected_total_bits <= 12'd0;
                        state <= S_UP_INIT;
                    end
                end

                S_UP_INIT: begin
                    req_cnt <= 9'd0;
                    rsp_cnt <= 9'd0;
                    delay_valid <= 1'b0;
                    weighted_err_sum <= 35'd0;
                    total_bits_sum <= 12'd0;
                    err_sum_256 <= 32'd0; err_sum_64 <= 32'd0;
                    err_sum_16 <= 32'd0;  err_sum_4 <= 32'd0;
                    cnt_256 <= 9'd0; cnt_64 <= 9'd0;
                    cnt_16 <= 9'd0; cnt_4 <= 9'd0;
                    state <= S_UP_SCAN;
                end

                S_UP_SCAN: begin
                    if (req_cnt < N_SUBCARRIERS) begin
                        o_carrier_idx <= req_cnt[7:0];
                        delay_valid <= 1'b1;
                        req_cnt <= req_cnt + 1'b1;
                    end else begin
                        delay_valid <= 1'b0;
                    end

                    if (i_err_valid) begin
                        weighted_err_sum <= weighted_err_sum +
                            weighted_error_term(i_subcarrier_err, i_m_tier);
                        total_bits_sum <= total_bits_sum + bits_from_tier(i_m_tier);

                        case (i_m_tier)
                            3'd4: begin
                                err_sum_256 <= err_sum_256 + i_subcarrier_err;
                                cnt_256 <= cnt_256 + 1'b1;
                            end
                            3'd3: begin
                                err_sum_64 <= err_sum_64 + i_subcarrier_err;
                                cnt_64 <= cnt_64 + 1'b1;
                            end
                            3'd2: begin
                                err_sum_16 <= err_sum_16 + i_subcarrier_err;
                                cnt_16 <= cnt_16 + 1'b1;
                            end
                            3'd1: begin
                                err_sum_4 <= err_sum_4 + i_subcarrier_err;
                                cnt_4 <= cnt_4 + 1'b1;
                            end
                            default: begin end
                        endcase

                        if (rsp_cnt == N_SUBCARRIERS-1) begin
                            rsp_cnt <= N_SUBCARRIERS;
                            state <= S_UP_DECIDE;
                        end else begin
                            rsp_cnt <= rsp_cnt + 1'b1;
                        end
                    end
                end

                S_UP_DECIDE: begin
                    if (target_met) begin
                        o_margin_converged <= 1'b1;
                        accepted_weighted_err <= weighted_err_sum;
                        accepted_total_bits <= total_bits_sum;
                        state <= S_REF_ROUND_BEGIN;
                    end else if (o_margin_updates >= MAX_MARGIN_UPDATES) begin
                        o_margin_timeout <= 1'b1;
                        accepted_weighted_err <= weighted_err_sum;
                        accepted_total_bits <= total_bits_sum;
                        o_selected_weighted_err_q24 <= {29'd0, weighted_err_sum};
                        o_selected_total_bits <= total_bits_sum;
                        o_margin_done <= 1'b1;
                        state <= S_OUTPUT_INIT;
                    end else begin
                        state <= S_XA;
                    end
                end

                S_XA: begin cross_A <= mul_product; state <= S_XB; end
                S_XB: begin cross_B <= mul_product; state <= S_XC; end
                S_XC: begin cross_C <= mul_product; state <= S_XD; end
                S_XD: begin cross_D <= mul_product; state <= S_CMP_1; end

                S_CMP_1: begin
                    if ((cnt_256 > 0 && cnt_64 == 0) ||
                        (cnt_256 > 0 && cnt_64 > 0 && cross_A >= cross_B)) begin
                        win12_id <= 3'd4;
                        win12_err <= err_sum_256;
                        win12_cnt <= cnt_256;
                    end else begin
                        win12_id <= 3'd3;
                        win12_err <= err_sum_64;
                        win12_cnt <= cnt_64;
                    end

                    if ((cnt_16 > 0 && cnt_4 == 0) ||
                        (cnt_16 > 0 && cnt_4 > 0 && cross_C >= cross_D)) begin
                        win34_id <= 3'd2;
                        win34_err <= err_sum_16;
                        win34_cnt <= cnt_16;
                    end else begin
                        win34_id <= 3'd1;
                        win34_err <= err_sum_4;
                        win34_cnt <= cnt_4;
                    end
                    state <= S_XFA;
                end

                S_XFA: begin cross_final_A <= mul_product; state <= S_XFB; end
                S_XFB: begin cross_final_B <= mul_product; state <= S_UP_UPDATE; end

                S_UP_UPDATE: begin
                    if ((win12_cnt > 0 && win34_cnt == 0) ||
                        (win12_cnt > 0 && win34_cnt > 0 &&
                         cross_final_A >= cross_final_B)) begin
                        case (win12_id)
                            3'd4: o_margin_256 <= o_margin_256 + MARGIN_STEP_Q16;
                            3'd3: o_margin_64  <= o_margin_64  + MARGIN_STEP_Q16;
                            3'd2: o_margin_16  <= o_margin_16  + MARGIN_STEP_Q16;
                            3'd1: o_margin_4   <= o_margin_4   + MARGIN_STEP_Q16;
                            default: begin end
                        endcase
                    end else begin
                        case (win34_id)
                            3'd4: o_margin_256 <= o_margin_256 + MARGIN_STEP_Q16;
                            3'd3: o_margin_64  <= o_margin_64  + MARGIN_STEP_Q16;
                            3'd2: o_margin_16  <= o_margin_16  + MARGIN_STEP_Q16;
                            3'd1: o_margin_4   <= o_margin_4   + MARGIN_STEP_Q16;
                            default: begin end
                        endcase
                    end
                    o_margin_updates <= o_margin_updates + 1'b1;
                    state <= S_UP_INIT;
                end

                // Capture the accepted point before evaluating four decrements.
                S_REF_ROUND_BEGIN: begin
                    delay_valid <= 1'b0;
                    ref_base_margin_256 <= o_margin_256;
                    ref_base_margin_64  <= o_margin_64;
                    ref_base_margin_16  <= o_margin_16;
                    ref_base_margin_4   <= o_margin_4;
                    ref_candidate_idx <= 2'd0;
                    ref_best_found <= 1'b0;
                    ref_best_total_bits <= 12'd0;
                    ref_best_weighted_err <= 35'd0;
                    state <= S_REF_PREP;
                end

                // Candidate order fixes tie behavior: 4, 16, 64, 256-QAM.
                S_REF_PREP: begin
                    o_margin_256 <= ref_base_margin_256;
                    o_margin_64  <= ref_base_margin_64;
                    o_margin_16  <= ref_base_margin_16;
                    o_margin_4   <= ref_base_margin_4;

                    case (ref_candidate_idx)
                        2'd0: begin
                            if (ref_base_margin_4 >= MARGIN_STEP_Q16) begin
                                o_margin_4 <= ref_base_margin_4 - MARGIN_STEP_Q16;
                                state <= S_REF_SCAN_INIT;
                            end else begin
                                ref_candidate_idx <= 2'd1;
                            end
                        end
                        2'd1: begin
                            if (ref_base_margin_16 >= MARGIN_STEP_Q16) begin
                                o_margin_16 <= ref_base_margin_16 - MARGIN_STEP_Q16;
                                state <= S_REF_SCAN_INIT;
                            end else begin
                                ref_candidate_idx <= 2'd2;
                            end
                        end
                        2'd2: begin
                            if (ref_base_margin_64 >= MARGIN_STEP_Q16) begin
                                o_margin_64 <= ref_base_margin_64 - MARGIN_STEP_Q16;
                                state <= S_REF_SCAN_INIT;
                            end else begin
                                ref_candidate_idx <= 2'd3;
                            end
                        end
                        default: begin
                            if (ref_base_margin_256 >= MARGIN_STEP_Q16) begin
                                o_margin_256 <= ref_base_margin_256 - MARGIN_STEP_Q16;
                                state <= S_REF_SCAN_INIT;
                            end else begin
                                state <= S_REF_APPLY;
                            end
                        end
                    endcase
                end

                S_REF_SCAN_INIT: begin
                    req_cnt <= 9'd0;
                    rsp_cnt <= 9'd0;
                    delay_valid <= 1'b0;
                    weighted_err_sum <= 35'd0;
                    total_bits_sum <= 12'd0;
                    state <= S_REF_SCAN;
                end

                S_REF_SCAN: begin
                    if (req_cnt < N_SUBCARRIERS) begin
                        o_carrier_idx <= req_cnt[7:0];
                        delay_valid <= 1'b1;
                        req_cnt <= req_cnt + 1'b1;
                    end else begin
                        delay_valid <= 1'b0;
                    end

                    if (i_err_valid) begin
                        weighted_err_sum <= weighted_err_sum +
                            weighted_error_term(i_subcarrier_err, i_m_tier);
                        total_bits_sum <= total_bits_sum + bits_from_tier(i_m_tier);

                        if (rsp_cnt == N_SUBCARRIERS-1) begin
                            rsp_cnt <= N_SUBCARRIERS;
                            state <= S_REF_DECIDE;
                        end else begin
                            rsp_cnt <= rsp_cnt + 1'b1;
                        end
                    end
                end

                S_REF_DECIDE: begin
                    o_refinement_scans <= o_refinement_scans + 1'b1;

                    // Strictly larger bits wins; equality retains the earlier
                    // candidate and therefore implements the documented tie order.
                    if (target_met &&
                        (!ref_best_found || total_bits_sum > ref_best_total_bits)) begin
                        ref_best_found <= 1'b1;
                        ref_best_total_bits <= total_bits_sum;
                        ref_best_weighted_err <= weighted_err_sum;
                        ref_best_margin_256 <= o_margin_256;
                        ref_best_margin_64  <= o_margin_64;
                        ref_best_margin_16  <= o_margin_16;
                        ref_best_margin_4   <= o_margin_4;
                    end

                    // Restore the accepted point before preparing the next trial.
                    o_margin_256 <= ref_base_margin_256;
                    o_margin_64  <= ref_base_margin_64;
                    o_margin_16  <= ref_base_margin_16;
                    o_margin_4   <= ref_base_margin_4;

                    if (ref_candidate_idx == 2'd3) begin
                        state <= S_REF_APPLY;
                    end else begin
                        ref_candidate_idx <= ref_candidate_idx + 1'b1;
                        state <= S_REF_PREP;
                    end
                end

                S_REF_APPLY: begin
                    if (ref_best_found) begin
                        o_margin_256 <= ref_best_margin_256;
                        o_margin_64  <= ref_best_margin_64;
                        o_margin_16  <= ref_best_margin_16;
                        o_margin_4   <= ref_best_margin_4;
                        accepted_weighted_err <= ref_best_weighted_err;
                        accepted_total_bits <= ref_best_total_bits;
                        o_refinement_accepts <= o_refinement_accepts + 1'b1;

                        if ((o_refinement_accepts + 1'b1) >=
                            MAX_REFINEMENT_ACCEPTS) begin
                            o_margin_timeout <= 1'b1;
                            o_selected_weighted_err_q24 <=
                                {29'd0, ref_best_weighted_err};
                            o_selected_total_bits <= ref_best_total_bits;
                            o_margin_done <= 1'b1;
                            state <= S_OUTPUT_INIT;
                        end else begin
                            state <= S_REF_ROUND_BEGIN;
                        end
                    end else begin
                        o_selected_weighted_err_q24 <=
                            {29'd0, accepted_weighted_err};
                        o_selected_total_bits <= accepted_total_bits;
                        o_margin_done <= 1'b1;
                        state <= S_OUTPUT_INIT;
                    end
                end

                S_OUTPUT_INIT: begin
                    req_cnt <= 9'd0;
                    rsp_cnt <= 9'd0;
                    delay_valid <= 1'b0;
                    state <= S_OUTPUT_STREAM;
                end

                S_OUTPUT_STREAM: begin
                    if (req_cnt < N_SUBCARRIERS) begin
                        o_carrier_idx <= req_cnt[7:0];
                        delay_valid <= 1'b1;
                        req_cnt <= req_cnt + 1'b1;
                    end else begin
                        delay_valid <= 1'b0;
                    end

                    if (i_err_valid) begin
                        o_final_valid <= 1'b1;
                        o_final_carrier_idx <= rsp_cnt[7:0];
                        o_final_m_tier <= i_m_tier;

                        if (rsp_cnt == N_SUBCARRIERS-1) begin
                            rsp_cnt <= N_SUBCARRIERS;
                            state <= S_DONE;
                        end else begin
                            rsp_cnt <= rsp_cnt + 1'b1;
                        end
                    end
                end

                S_DONE: begin
                    o_final_done <= 1'b1;
                    o_done <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
