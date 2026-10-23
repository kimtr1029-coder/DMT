`timescale 1ns / 1ps

// ============================================================================
// per_qam_datapath_balanced
//
// Final single-bank BER/allocation datapath.
//
//   allocation : Q16 SNR_dB compared with base threshold + per-QAM margin
//   estimator  : BER ~= C * 2^(-K*SNR_linear)
//   K/C        : one conservative Q16 coefficient pair per QAM order
//   LUT        : shared 32-entry Q16 table for 2^(-fraction)
//   BER output : Q24 (the multipliers remain 16x32 and 16x17)
//
// The Q24 BER path avoids the large 1-LSB penalty of a Q16 BER result while
// keeping the expensive arithmetic unchanged. There is no original/validator
// bank, alpha correction, or coefficient-selection MUX in this datapath.
// It accepts one tone per clock.
// ============================================================================
module per_qam_datapath_balanced #(
    parameter [15:0] K_256 = 16'd602,
    parameter [15:0] C_256 = 16'd6506,
    parameter [15:0] K_64  = 16'd2436,
    parameter [15:0] C_64  = 16'd8057,
    parameter [15:0] K_16  = 16'd10213,
    parameter [15:0] C_16  = 16'd10206,
    parameter [15:0] K_4   = 16'd50734,
    parameter [15:0] C_4   = 16'd12756
)(
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

    localparam [31:0] TH_256 = 32'd1572864; // 24 dB, Q16
    localparam [31:0] TH_64  = 32'd1179648; // 18 dB, Q16
    localparam [31:0] TH_16  = 32'd786432;  // 12 dB, Q16
    localparam [31:0] TH_4   = 32'd393216;  //  6 dB, Q16

    // The 33rd bit prevents a wrapped threshold if a large margin is supplied.
    wire [32:0] req_256 = {1'b0, i_margin_256} + {1'b0, TH_256};
    wire [32:0] req_64  = {1'b0, i_margin_64}  + {1'b0, TH_64};
    wire [32:0] req_16  = {1'b0, i_margin_16}  + {1'b0, TH_16};
    wire [32:0] req_4   = {1'b0, i_margin_4}   + {1'b0, TH_4};

    wire qual_256 = ({1'b0, i_snr_db} >= req_256);
    wire qual_64  = ({1'b0, i_snr_db} >= req_64);
    wire qual_16  = ({1'b0, i_snr_db} >= req_16);
    wire qual_4   = ({1'b0, i_snr_db} >= req_4);

    reg [2:0] next_m_tier;

    always @(*) begin
        if (qual_256)
            next_m_tier = 3'd4;
        else if (qual_64)
            next_m_tier = 3'd3;
        else if (qual_16)
            next_m_tier = 3'd2;
        else if (qual_4)
            next_m_tier = 3'd1;
        else
            next_m_tier = 3'd0;
    end

    function [15:0] k_from_tier;
        input [2:0] tier;
        begin
            case (tier)
                3'd4: k_from_tier = K_256;
                3'd3: k_from_tier = K_64;
                3'd2: k_from_tier = K_16;
                3'd1: k_from_tier = K_4;
                default: k_from_tier = 16'd0;
            endcase
        end
    endfunction

    function [15:0] c_from_tier;
        input [2:0] tier;
        begin
            case (tier)
                3'd4: c_from_tier = C_256;
                3'd3: c_from_tier = C_64;
                3'd2: c_from_tier = C_16;
                3'd1: c_from_tier = C_4;
                default: c_from_tier = 16'd0;
            endcase
        end
    endfunction

    function [16:0] exp_lut;
        input [4:0] addr;
        begin
            case (addr)
                5'd0:  exp_lut = 17'd65536;
                5'd1:  exp_lut = 17'd64131;
                5'd2:  exp_lut = 17'd62757;
                5'd3:  exp_lut = 17'd61412;
                5'd4:  exp_lut = 17'd60096;
                5'd5:  exp_lut = 17'd58809;
                5'd6:  exp_lut = 17'd57548;
                5'd7:  exp_lut = 17'd56315;
                5'd8:  exp_lut = 17'd55108;
                5'd9:  exp_lut = 17'd53928;
                5'd10: exp_lut = 17'd52772;
                5'd11: exp_lut = 17'd51641;
                5'd12: exp_lut = 17'd50535;
                5'd13: exp_lut = 17'd49452;
                5'd14: exp_lut = 17'd48392;
                5'd15: exp_lut = 17'd47355;
                5'd16: exp_lut = 17'd46340;
                5'd17: exp_lut = 17'd45347;
                5'd18: exp_lut = 17'd44376;
                5'd19: exp_lut = 17'd43425;
                5'd20: exp_lut = 17'd42494;
                5'd21: exp_lut = 17'd41584;
                5'd22: exp_lut = 17'd40693;
                5'd23: exp_lut = 17'd39821;
                5'd24: exp_lut = 17'd38967;
                5'd25: exp_lut = 17'd38132;
                5'd26: exp_lut = 17'd37315;
                5'd27: exp_lut = 17'd36516;
                5'd28: exp_lut = 17'd35733;
                5'd29: exp_lut = 17'd34968;
                5'd30: exp_lut = 17'd34218;
                5'd31: exp_lut = 17'd33485;
            endcase
        end
    endfunction

    // Stage 1: allocation and SNR capture.
    reg        valid_st1;
    reg [2:0]  tier_st1;
    reg [31:0] snr_linear_st1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_st1      <= 1'b0;
            tier_st1       <= 3'd0;
            snr_linear_st1 <= 32'd0;
        end else begin
            valid_st1      <= i_valid;
            tier_st1       <= next_m_tier;
            snr_linear_st1 <= i_snr_linear;
        end
    end

    // Stage 2: Y(Q32) = K(Q16) * SNR_linear(Q16).
    wire [15:0] k_st1 = k_from_tier(tier_st1);
    wire [47:0] y_mult_wire = snr_linear_st1 * k_st1;

    reg        valid_st2;
    reg [2:0]  tier_st2;
    reg [4:0]  y_frac_st2;
    reg [4:0]  y_shift_st2;
    reg        y_ge24_st2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_st2   <= 1'b0;
            tier_st2    <= 3'd0;
            y_frac_st2  <= 5'd0;
            y_shift_st2 <= 5'd0;
            y_ge24_st2  <= 1'b0;
        end else begin
            valid_st2   <= valid_st1;
            tier_st2    <= tier_st1;
            y_frac_st2  <= y_mult_wire[31:27];
            y_shift_st2 <= y_mult_wire[36:32];
            y_ge24_st2  <= (|y_mult_wire[47:37]) ||
                           (y_mult_wire[36:32] >= 5'd24);
        end
    end

    // Stage 3: C(Q16) * LUT(Q16), then integer power-of-two shift.
    // Product Q32 -> Q24 requires an 8-bit right shift.
    wire [15:0] c_st2 = c_from_tier(tier_st2);
    wire [16:0] lut_st2 = exp_lut(y_frac_st2);
    wire [32:0] c_lut_mult = c_st2 * lut_st2;
    wire [23:0] base_q24 = c_lut_mult[31:8];
    wire [23:0] shifted_q24 = base_q24 >> y_shift_st2;
    wire [23:0] err_q24 = y_ge24_st2 ? 24'd0 : shifted_q24;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_valid          <= 1'b0;
            o_subcarrier_err <= 24'd0;
            o_m_tier         <= 3'd0;
        end else begin
            o_valid  <= valid_st2;
            o_m_tier <= tier_st2;
            if (tier_st2 == 3'd0)
                o_subcarrier_err <= 24'd0;
            else
                o_subcarrier_err <= err_q24;
        end
    end

endmodule
