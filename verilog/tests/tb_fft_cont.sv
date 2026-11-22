`timescale 1ns/1ps
module tb_fft_cont;
    `include "stream_vectors.svh"
    reg passed = 0;
    initial #10000 $fatal(1, "Testbench watchdog expired");
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
    integer cycle, i, frame32, frame64, count32, count64;
    // A negative ID represents a bubble. Slot zero is the capture edge.
    integer expected32 [0:FFT32_LATENCY-1];
    integer expected64 [0:FFT64_LATENCY-1];
    reg [31:0] random_state = 32'h7214d024;

    fft32_parallel dut32 (.clk(clk), .rst(rst), .in_valid(valid32),
        .in_re(in32_re), .in_im(in32_im), .out_valid(valid32_o),
        .out_re(out32_re), .out_im(out32_im));
    fft64_parallel dut64 (.clk(clk), .rst(rst), .in_valid(valid64),
        .in_re(in64_re), .in_im(in64_im), .out_valid(valid64_o),
        .out_re(out64_re), .out_im(out64_im));

    initial begin
        count32 = 0; count64 = 0;
        repeat (30) @(posedge clk);
        for (cycle = 0; cycle < 400; cycle = cycle + 1) begin
            @(negedge clk);
            random_state = {random_state[30:0], ^(random_state & 32'h80200003)};
            frame32 = (cycle + random_state[7:0]) % STREAM_COUNT;
            frame64 = (cycle + random_state[15:8]) % STREAM_COUNT;
            if (cycle >= 208 && cycle < 208 + STREAM_COUNT) begin
                frame32 = cycle - 208;
                frame64 = cycle - 208;
            end
            rst = cycle == 0 || cycle == 44 || cycle == 207;
            valid32 = cycle < 375 && (cycle < 65 || (cycle >= 208 && cycle < 208 + STREAM_COUNT) || random_state[0]);
            valid64 = cycle < 375 && (cycle < 65 || (cycle >= 208 && cycle < 208 + STREAM_COUNT) || random_state[1]);
            in32_re = F32_IN_RE[frame32]; in32_im = F32_IN_IM[frame32];
            in64_re = F64_IN_RE[frame64]; in64_im = F64_IN_IM[frame64];
            @(posedge clk);
            for (i = FFT32_LATENCY-1; i > 0; i = i - 1)
                expected32[i] = rst ? -1 : expected32[i-1];
            expected32[0] = !rst && valid32 ? frame32 : -1;
            for (i = FFT64_LATENCY-1; i > 0; i = i - 1)
                expected64[i] = rst ? -1 : expected64[i-1];
            expected64[0] = !rst && valid64 ? frame64 : -1;
            #1; // Sample after nonblocking updates.
            frame32 = expected32[FFT32_LATENCY-1];
            if (valid32_o !== (frame32 >= 0))
                $fatal(1, "FFT32 cycle %0d expected frame %0d valid=%b", cycle, frame32, valid32_o);
            if (frame32 >= 0) begin
                if (out32_re !== F32_OUT_RE[frame32] || out32_im !== F32_OUT_IM[frame32])
                    $fatal(1, "FFT32 cycle %0d frame %0d data mismatch", cycle, frame32);
                count32 = count32 + 1;
            end
            frame64 = expected64[FFT64_LATENCY-1];
            if (valid64_o !== (frame64 >= 0))
                $fatal(1, "FFT64 cycle %0d expected frame %0d valid=%b", cycle, frame64, valid64_o);
            if (frame64 >= 0) begin
                if (out64_re !== F64_OUT_RE[frame64] || out64_im !== F64_OUT_IM[frame64])
                    $fatal(1, "FFT64 cycle %0d frame %0d data mismatch", cycle, frame64);
                count64 = count64 + 1;
            end
        end
        $display("STREAM PASS FFT32=%0d FFT64=%0d", count32, count64);
        passed = 1;
        $finish;
    end
endmodule
