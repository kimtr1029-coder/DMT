`timescale 1ns / 1ps

// Degree-4 piecewise polynomial evaluated in the local Chebyshev coordinate.
// The unbiased chebfit coefficients are converted offline to the power basis;
// no upward-envelope correction is applied.  Latency: 4 clocks, II: 1 clock.
module cheb_poly_degree4_q30_pipe #(
    parameter integer TAG_WIDTH = 5
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         i_valid,
    input  wire [5:0]                   i_segment,
    input  wire signed [31:0]           i_u_q30,
    input  wire [TAG_WIDTH-1:0]         i_tag,
    output wire                         o_valid,
    output wire signed [31:0]           o_h_q30,
    output wire [TAG_WIDTH-1:0]         o_tag
);

    wire signed [31:0] rom_c0, rom_c1, rom_c2, rom_c3, rom_c4;
    piecewise_cheb_coeff_rom_q30 u_coefficients (
        .i_segment(i_segment), .o_c0(rom_c0), .o_c1(rom_c1),
        .o_c2(rom_c2), .o_c3(rom_c3), .o_c4(rom_c4)
    );

    function signed [31:0] mul_q30;
        input signed [31:0] a_q30;
        input signed [31:0] b_q30;
        reg signed [63:0] product;
        reg signed [63:0] magnitude;
        begin
            product = a_q30 * b_q30;
            if (product >= 0)
                mul_q30 = (product + 64'sd536870912) >>> 30;
            else begin
                magnitude = -product;
                mul_q30 = -((magnitude + 64'sd536870912) >>> 30);
            end
        end
    endfunction

    reg valid_0, valid_1, valid_2, valid_3, valid_4;
    reg signed [31:0] p_0, p_1, p_2, p_3, p_4;
    reg signed [31:0] u_0, u_1, u_2, u_3;
    reg signed [31:0] c3_0, c2_0, c1_0, c0_0;
    reg signed [31:0] c2_1, c1_1, c0_1;
    reg signed [31:0] c1_2, c0_2, c0_3;
    reg [TAG_WIDTH-1:0] tag_0, tag_1, tag_2, tag_3, tag_4;

    wire signed [31:0] p_w1 = c3_0 + mul_q30(p_0, u_0);
    wire signed [31:0] p_w2 = c2_1 + mul_q30(p_1, u_1);
    wire signed [31:0] p_w3 = c1_2 + mul_q30(p_2, u_2);
    wire signed [31:0] p_w4 = c0_3 + mul_q30(p_3, u_3);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_0 <= 1'b0; valid_1 <= 1'b0; valid_2 <= 1'b0;
            valid_3 <= 1'b0; valid_4 <= 1'b0;
        end else begin
            valid_0 <= i_valid; valid_1 <= valid_0; valid_2 <= valid_1;
            valid_3 <= valid_2; valid_4 <= valid_3;
        end
    end

    always @(posedge clk) begin
        p_0 <= rom_c4; u_0 <= i_u_q30;
        c3_0 <= rom_c3; c2_0 <= rom_c2; c1_0 <= rom_c1; c0_0 <= rom_c0;
        tag_0 <= i_tag;

        p_1 <= p_w1; u_1 <= u_0;
        c2_1 <= c2_0; c1_1 <= c1_0; c0_1 <= c0_0; tag_1 <= tag_0;

        p_2 <= p_w2; u_2 <= u_1;
        c1_2 <= c1_1; c0_2 <= c0_1; tag_2 <= tag_1;

        p_3 <= p_w3; u_3 <= u_2;
        c0_3 <= c0_2; tag_3 <= tag_2;

        p_4 <= p_w4; tag_4 <= tag_3;
    end

    assign o_valid = valid_4;
    assign o_h_q30 = p_4;
    assign o_tag = tag_4;

endmodule
