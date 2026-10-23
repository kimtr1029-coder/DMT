`timescale 1ns / 1ps

module tb_channel_latency_chebyshev;
    localparam integer N = 255;
    localparam integer TIMEOUT_CYCLES = 1000000;
    reg clk = 1'b0, rst_n = 1'b0, start = 1'b0;
    reg [31:0] snr_db_mem [0:N-1];
    reg [31:0] snr_linear_mem [0:N-1];
    string profile, db_file, linear_file;
    wire [7:0] carrier_idx, final_idx;
    wire [2:0] final_tier;
    wire done, final_valid, final_done;
    reg [31:0] snr_db, snr_linear;
    wire [15:0] updates, accepts, scans;
    wire [11:0] total_bits;
    wire [63:0] weighted_err;
    integer global_cycles, elapsed, done_cycles, final_count;
    reg active, seen_done;

    always #5 clk = ~clk;
    always @(posedge clk) begin
        snr_db <= snr_db_mem[carrier_idx];
        snr_linear <= snr_linear_mem[carrier_idx];
        if (start) begin elapsed = 0; active = 1'b1; end
        else if (active && !seen_done) elapsed = elapsed + 1;
        if (final_valid) final_count = final_count + 1;
        global_cycles = global_cycles + 1;
        if (global_cycles > TIMEOUT_CYCLES) $fatal(1, "latency timeout");
    end

    always @(negedge clk) begin
        if (done && !seen_done) begin
            seen_done = 1'b1;
            done_cycles = elapsed;
        end
    end

    channel_latency_chebyshev_top dut (
        .clk(clk), .rst_n(rst_n), .i_start(start),
        .i_snr_linear(snr_linear), .i_snr_db(snr_db),
        .o_carrier_idx(carrier_idx), .o_done(done),
        .o_updates(updates), .o_refinement_accepts(accepts),
        .o_refinement_scans(scans), .o_total_bits(total_bits),
        .o_weighted_err_q24(weighted_err),
        .o_final_carrier_idx(final_idx), .o_final_m_tier(final_tier),
        .o_final_valid(final_valid), .o_final_done(final_done)
    );

    initial begin
        if (!$value$plusargs("PROFILE=%s", profile)) profile = "channel25";
        if (!$value$plusargs("DB_FILE=%s", db_file))
            db_file = "latency/channel25_snr_db_q16.mem";
        if (!$value$plusargs("LINEAR_FILE=%s", linear_file))
            linear_file = "latency/channel25_snr_linear_q16.mem";
        global_cycles = 0; elapsed = 0; done_cycles = -1; final_count = 0;
        active = 1'b0; seen_done = 1'b0; snr_db = 0; snr_linear = 0;
        $readmemh(db_file, snr_db_mem);
        $readmemh(linear_file, snr_linear_mem);
        repeat (5) @(negedge clk); rst_n = 1'b1;
        repeat (3) @(negedge clk); start = 1'b1; @(negedge clk); start = 1'b0;
        wait (seen_done); repeat (2) @(negedge clk);
        if (final_count != N) $fatal(1, "final stream count %0d != %0d", final_count, N);
        $display("PROFILE=%s", profile);
        $display("CHEBYSHEV cycles=%0d us@100MHz=%0f updates=%0d accepts=%0d scans=%0d bits=%0d weighted=%0d final=%0d",
            done_cycles, done_cycles/100.0, updates, accepts, scans,
            total_bits, weighted_err, final_count);
        $finish;
    end
endmodule
