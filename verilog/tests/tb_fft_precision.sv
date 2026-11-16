`timescale 1ns/1ps
// DC and full-scale fixed-point checks. These vectors expose per-stage
// truncation and +/-1 twiddle coefficient errors that ordinary random frames
// can miss.
module tb_fft_precision;
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
    integer errors;
    integer wait_cycles;
    integer k;
    integer value;

    fft32_parallel dut32 (.clk(clk), .rst(rst), .in_valid(valid32),
        .in_re(in32_re), .in_im(in32_im), .out_valid(valid32_o),
        .out_re(out32_re), .out_im(out32_im));
    fft64_parallel dut64 (.clk(clk), .rst(rst), .in_valid(valid64),
        .in_re(in64_re), .in_im(in64_im), .out_valid(valid64_o),
        .out_re(out64_re), .out_im(out64_im));

    task automatic test32(input integer sample);
        begin
            @(negedge clk);
            in32_re = '0; in32_im = '0;
            for (k = 0; k < 32; k = k + 1) in32_re[k*8 +: 8] = sample[7:0];
            valid32 = 1'b1;
            @(negedge clk); valid32 = 1'b0;
            wait_cycles = 0;
            while (valid32_o !== 1'b1 && wait_cycles < FFT32_LATENCY + 8) begin
                @(posedge clk); wait_cycles = wait_cycles + 1;
            end
            if (valid32_o !== 1'b1) $fatal(1, "FFT32 precision timeout for %0d", sample);
            #1;
            if ($signed(out32_re[0 +: 8]) !== sample || out32_im[0 +: 8] !== 8'h00) begin
                $display("FFT32 DC mismatch sample=%0d got=%0d/%0d", sample,
                    $signed(out32_re[0 +: 8]), $signed(out32_im[0 +: 8]));
                errors = errors + 1;
            end
            for (k = 1; k < 32; k = k + 1)
                if (out32_re[k*8 +: 8] !== 8'h00 || out32_im[k*8 +: 8] !== 8'h00) errors = errors + 1;
        end
    endtask

    task automatic test64(input integer sample);
        begin
            @(negedge clk);
            in64_re = '0; in64_im = '0;
            for (k = 0; k < 64; k = k + 1) in64_re[k*8 +: 8] = sample[7:0];
            valid64 = 1'b1;
            @(negedge clk); valid64 = 1'b0;
            wait_cycles = 0;
            while (valid64_o !== 1'b1 && wait_cycles < FFT64_LATENCY + 8) begin
                @(posedge clk); wait_cycles = wait_cycles + 1;
            end
            if (valid64_o !== 1'b1) $fatal(1, "FFT64 precision timeout for %0d", sample);
            #1;
            if ($signed(out64_re[0 +: 8]) !== sample || out64_im[0 +: 8] !== 8'h00) begin
                $display("FFT64 DC mismatch sample=%0d got=%0d/%0d", sample,
                    $signed(out64_re[0 +: 8]), $signed(out64_im[0 +: 8]));
                errors = errors + 1;
            end
            for (k = 1; k < 64; k = k + 1)
                if (out64_re[k*8 +: 8] !== 8'h00 || out64_im[k*8 +: 8] !== 8'h00) errors = errors + 1;
        end
    endtask

    initial begin
        errors = 0; in32_re = '0; in32_im = '0; in64_re = '0; in64_im = '0;
        repeat (30) @(posedge clk);
        rst = 1'b0;
        for (value = -128; value <= 127; value = value + 1) begin
            if (value == -128 || value == -8 || value == 1 || value == 8 || value == 127) begin
                test32(value);
                test64(value);
            end
        end
        if (errors == 0) $display("FIXED-POINT PRECISION TEST PASS");
        else $fatal(1, "FIXED-POINT PRECISION TEST FAILED: %0d errors", errors);
        $finish;
    end
endmodule
