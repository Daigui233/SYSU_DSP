`timescale 1ns/1ps
module tb_fft;
    `include "vectors.svh"
    reg clk = 1'b0;
    always #2 clk = ~clk; // 250 MHz
    reg rst = 1'b1;
    reg valid32 = 1'b0;
    reg valid64 = 1'b0;
    reg signed [255:0] in32_re, in32_im;
    reg signed [511:0] in64_re, in64_im;
    wire valid32_o, valid64_o;
    wire signed [255:0] out32_re, out32_im;
    wire signed [511:0] out64_re, out64_im;
    integer i;
    integer errors;

    fft32_parallel dut32 (
        .clk(clk), .rst(rst), .in_valid(valid32), .in_re(in32_re), .in_im(in32_im),
        .out_valid(valid32_o), .out_re(out32_re), .out_im(out32_im)
    );
    fft64_parallel dut64 (
        .clk(clk), .rst(rst), .in_valid(valid64), .in_re(in64_re), .in_im(in64_im),
        .out_valid(valid64_o), .out_re(out64_re), .out_im(out64_im)
    );

    task automatic send32(input integer index);
        begin
            @(negedge clk);
            in32_re = FFT32_IN_RE[index]; in32_im = FFT32_IN_IM[index]; valid32 = 1'b1;
            @(negedge clk); valid32 = 1'b0;
            wait (valid32_o === 1'b1); #1;
            if (out32_re !== FFT32_OUT_RE[index] || out32_im !== FFT32_OUT_IM[index]) begin
                $display("FFT32 mismatch vector %0d: got re=%h im=%h expected re=%h im=%h", index, out32_re, out32_im, FFT32_OUT_RE[index], FFT32_OUT_IM[index]);
                errors = errors + 1;
            end else $display("FFT32 vector %0d PASS", index);
            @(negedge clk);
        end
    endtask

    task automatic send64(input integer index);
        begin
            @(negedge clk);
            in64_re = FFT64_IN_RE[index]; in64_im = FFT64_IN_IM[index]; valid64 = 1'b1;
            @(negedge clk); valid64 = 1'b0;
            wait (valid64_o === 1'b1); #1;
            if (out64_re !== FFT64_OUT_RE[index] || out64_im !== FFT64_OUT_IM[index]) begin
                $display("FFT64 mismatch vector %0d: got re=%h im=%h expected re=%h im=%h", index, out64_re, out64_im, FFT64_OUT_RE[index], FFT64_OUT_IM[index]);
                errors = errors + 1;
            end else $display("FFT64 vector %0d PASS", index);
            @(negedge clk);
        end
    endtask

    initial begin
        errors = 0; in32_re = '0; in32_im = '0; in64_re = '0; in64_im = '0;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        for (i = 0; i < VECTOR_COUNT; i = i + 1) begin
            send32(i);
            send64(i);
        end
        if (errors == 0) $display("ALL FFT TESTS PASS");
        else $display("FFT TESTS FAILED: %0d errors", errors);
        $finish;
    end
endmodule
