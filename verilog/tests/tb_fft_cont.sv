`timescale 1ns/1ps
module tb_fft_cont;
    `include "vectors.svh"
    reg clk = 1'b0;
    always #2 clk = ~clk;
    reg rst = 1'b1;
    reg valid32 = 1'b0;
    reg valid64 = 1'b0;
    reg signed [255:0] in32_re, in32_im;
    reg signed [511:0] in64_re, in64_im;
    wire valid32_o, valid64_o;
    wire signed [255:0] out32_re, out32_im;
    wire signed [511:0] out64_re, out64_im;
    localparam integer FFT32_LATENCY = 5 * 3 + 1;
    localparam integer FFT64_LATENCY = 6 * 3 + 1;
    integer cycle, idx32, idx64, errors;

    fft32_parallel dut32 (.clk(clk), .rst(rst), .in_valid(valid32),
        .in_re(in32_re), .in_im(in32_im), .out_valid(valid32_o),
        .out_re(out32_re), .out_im(out32_im));
    fft64_parallel dut64 (.clk(clk), .rst(rst), .in_valid(valid64),
        .in_re(in64_re), .in_im(in64_im), .out_valid(valid64_o),
        .out_re(out64_re), .out_im(out64_im));

    initial begin
        in32_re='0; in32_im='0; in64_re='0; in64_im='0;
        idx32=0; idx64=0; errors=0;
        // Wait beyond Vivado glbl's 100 ns GSR interval.
        repeat (30) @(posedge clk);
        rst=1'b0;
        // Four different frames are accepted on four consecutive cycles.
        for (cycle=0; cycle<45; cycle=cycle+1) begin
            @(negedge clk);
            if (cycle < VECTOR_COUNT) begin
                in32_re=FFT32_IN_RE[cycle]; in32_im=FFT32_IN_IM[cycle]; valid32=1'b1;
                in64_re=FFT64_IN_RE[cycle]; in64_im=FFT64_IN_IM[cycle]; valid64=1'b1;
            end else begin
                valid32=1'b0; valid64=1'b0;
            end
            @(posedge clk); #1;
            if (valid32_o) begin
                if (idx32 >= VECTOR_COUNT || out32_re !== FFT32_OUT_RE[idx32] || out32_im !== FFT32_OUT_IM[idx32]) begin
                    $display("CONT FFT32 mismatch frame %0d: got %h/%h", idx32, out32_re, out32_im);
                    errors=errors+1;
                end
                idx32=idx32+1;
            end
            if (valid64_o) begin
                if (idx64 >= VECTOR_COUNT || out64_re !== FFT64_OUT_RE[idx64] || out64_im !== FFT64_OUT_IM[idx64]) begin
                    $display("CONT FFT64 mismatch frame %0d: got %h/%h", idx64, out64_re, out64_im);
                    errors=errors+1;
                end
                idx64=idx64+1;
            end
        end
        if (idx32 != VECTOR_COUNT || idx64 != VECTOR_COUNT) begin
            $display("CONT valid count mismatch: 32=%0d 64=%0d", idx32, idx64);
            errors=errors+1;
        end
        if (errors == 0) $display("CONTIGUOUS FRAME TEST PASS (latencies %0d/%0d cycles)", FFT32_LATENCY, FFT64_LATENCY);
        else $fatal(1, "CONTIGUOUS FRAME TEST FAILED: %0d errors", errors);
        $finish;
    end
endmodule
