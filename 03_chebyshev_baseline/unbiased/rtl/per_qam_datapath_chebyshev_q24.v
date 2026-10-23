`timescale 1ns / 1ps

// Unbiased 44-segment, degree-4 piecewise-Chebyshev approximation of
// erfc(sqrt(z)).  Segment width is 0.25 in z, so segment selection and local
// coordinate normalization require only subtraction, slicing and shifting.
// This baseline is two-sided: no upward correction is applied.  II: 1 tone/clk.
module per_qam_datapath_chebyshev_q24 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         i_valid,
    output reg          o_valid,
    input  wire [31:0]  i_snr_linear,
    input  wire [31:0]  i_snr_db,
    input  wire [31:0]  i_margin_256,
    input  wire [31:0]  i_margin_64,
    input  wire [31:0]  i_margin_16,
    input  wire [31:0]  i_margin_4,
    output reg  [23:0]  o_subcarrier_err,
    output reg  [2:0]   o_m_tier
);

    localparam [31:0] TH_256 = 32'd1572864;
    localparam [31:0] TH_64  = 32'd1179648;
    localparam [31:0] TH_16  = 32'd786432;
    localparam [31:0] TH_4   = 32'd393216;
    localparam [31:0] Z_LO_Q16 = 32'd81920;
    localparam [31:0] Z_HI_Q16 = 32'd802816;

    wire [32:0] req_256 = {1'b0, i_margin_256} + {1'b0, TH_256};
    wire [32:0] req_64  = {1'b0, i_margin_64}  + {1'b0, TH_64};
    wire [32:0] req_16  = {1'b0, i_margin_16}  + {1'b0, TH_16};
    wire [32:0] req_4   = {1'b0, i_margin_4}   + {1'b0, TH_4};

    reg [2:0] next_m_tier;
    always @(*) begin
        if ({1'b0, i_snr_db} >= req_256) next_m_tier = 3'd4;
        else if ({1'b0, i_snr_db} >= req_64) next_m_tier = 3'd3;
        else if ({1'b0, i_snr_db} >= req_16) next_m_tier = 3'd2;
        else if ({1'b0, i_snr_db} >= req_4) next_m_tier = 3'd1;
        else next_m_tier = 3'd0;
    end

    function [23:0] z_factor_from_tier;
        input [2:0] tier;
        begin
            case (tier)
                3'd4: z_factor_from_tier = 24'd98690;
                3'd3: z_factor_from_tier = 24'd399458;
                3'd2: z_factor_from_tier = 24'd1677722;
                3'd1: z_factor_from_tier = 24'd8388608;
                default: z_factor_from_tier = 24'd0;
            endcase
        end
    endfunction

    function [23:0] ber_scale_from_tier;
        input [2:0] tier;
        begin
            case (tier)
                3'd4: ber_scale_from_tier = 24'd3932160;
                3'd3: ber_scale_from_tier = 24'd4893355;
                3'd2: ber_scale_from_tier = 24'd6291456;
                3'd1: ber_scale_from_tier = 24'd8388608;
                default: ber_scale_from_tier = 24'd0;
            endcase
        end
    endfunction

    reg valid_st1;
    reg [2:0] tier_st1;
    reg [31:0] snr_linear_st1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) valid_st1 <= 1'b0;
        else valid_st1 <= i_valid;
    end
    always @(posedge clk) begin
        tier_st1 <= next_m_tier;
        snr_linear_st1 <= i_snr_linear;
    end

    wire [23:0] factor_st1 = z_factor_from_tier(tier_st1);
    wire [55:0] z_product = snr_linear_st1 * factor_st1;
    wire [56:0] z_rounded = {1'b0, z_product} + 57'd8388608;
    wire [31:0] z_comb = z_rounded[56] ? 32'hffffffff : z_rounded[55:24];
    reg valid_st2;
    reg [2:0] tier_st2;
    reg [31:0] z_q16_st2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) valid_st2 <= 1'b0;
        else valid_st2 <= valid_st1;
    end
    always @(posedge clk) begin
        tier_st2 <= tier_st1;
        z_q16_st2 <= z_comb;
    end

    wire z_low = z_q16_st2 < Z_LO_Q16;
    wire z_high = z_q16_st2 >= Z_HI_Q16;
    wire [31:0] z_clamped = z_low ? Z_LO_Q16 : (z_high ? Z_HI_Q16-1 : z_q16_st2);
    wire [31:0] relative_z = z_clamped - Z_LO_Q16;
    wire [5:0] segment = relative_z[19:14];
    wire [13:0] offset_in_segment = relative_z[13:0];
    wire signed [31:0] local_u_q30 = $signed({1'b0, offset_in_segment, 17'd0})
                                           - 32'sd1073741824;
    wire [4:0] cheb_tag_in = {z_low, z_high, tier_st2};

    wire cheb_valid;
    wire signed [31:0] h_q30_signed;
    wire [4:0] cheb_tag;
    cheb_poly_degree4_q30_pipe #(.TAG_WIDTH(5)) u_cheb (
        .clk(clk), .rst_n(rst_n), .i_valid(valid_st2),
        .i_segment(segment), .i_u_q30(local_u_q30), .i_tag(cheb_tag_in),
        .o_valid(cheb_valid), .o_h_q30(h_q30_signed), .o_tag(cheb_tag)
    );

    wire cheb_low = cheb_tag[4];
    wire cheb_high = cheb_tag[3];
    wire [2:0] cheb_tier = cheb_tag[2:0];
    wire [31:0] h_q30 = h_q30_signed[31] ? 32'd0 : h_q30_signed;
    wire [23:0] scale = ber_scale_from_tier(cheb_tier);
    wire [55:0] ber_product = h_q30 * scale;
    wire [56:0] ber_rounded = {1'b0, ber_product} + 57'd536870912;
    wire ber_overflow = |ber_rounded[56:54];
    wire [23:0] active_ber_q24 = ber_overflow ? 24'hffffff : ber_rounded[53:30];
    wire [23:0] selected_ber_q24 = cheb_low ? 24'hffffff
                                           : (cheb_high ? 24'd0 : active_ber_q24);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_valid <= 1'b0;
            o_subcarrier_err <= 24'd0;
            o_m_tier <= 3'd0;
        end else begin
            o_valid <= cheb_valid;
            o_m_tier <= cheb_tier;
            o_subcarrier_err <= (cheb_tier == 3'd0) ? 24'd0 : selected_ber_q24;
        end
    end

endmodule
