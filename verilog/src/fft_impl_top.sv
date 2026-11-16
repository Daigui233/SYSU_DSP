`timescale 1ns/1ps
// Small implementation wrapper used to run placement and timing analysis.
// The FFT cores keep their wide frame interface for functional simulation.
// This wrapper supplies frames internally so the physical top has only clock,
// reset, and one status output instead of hundreds of package pins.

module fft32_impl_top (
    input  wire clk,
    input  wire rst,
    output wire status
);
    reg [7:0] counter;
    reg frame_valid;
    reg signed [255:0] frame_re;
    reg signed [255:0] frame_im;
    wire core_valid;
    wire signed [255:0] core_re;
    wire signed [255:0] core_im;

    always @(posedge clk) begin
        if (rst) begin
            counter <= 8'h00;
            frame_valid <= 1'b0;
        end else begin
            counter <= counter + 8'h01;
            frame_valid <= (counter == 8'h00);
        end
    end

    always @* begin
        frame_re = '0;
        frame_im = '0;
        frame_re[0 +: 8] = counter;
        frame_re[8 +: 8] = counter + 8'h01;
        frame_re[16 +: 8] = counter + 8'h02;
        frame_re[24 +: 8] = counter + 8'h03;
        frame_re[32 +: 8] = counter + 8'h04;
        frame_re[40 +: 8] = counter + 8'h05;
        frame_re[48 +: 8] = counter + 8'h06;
        frame_re[56 +: 8] = counter + 8'h07;
        frame_re[64 +: 8] = counter + 8'h08;
        frame_re[72 +: 8] = counter + 8'h09;
        frame_re[80 +: 8] = counter + 8'h0a;
        frame_re[88 +: 8] = counter + 8'h0b;
        frame_re[96 +: 8] = counter + 8'h0c;
        frame_re[104 +: 8] = counter + 8'h0d;
        frame_re[112 +: 8] = counter + 8'h0e;
        frame_re[120 +: 8] = counter + 8'h0f;
        frame_re[128 +: 8] = counter + 8'h10;
        frame_re[136 +: 8] = counter + 8'h11;
        frame_re[144 +: 8] = counter + 8'h12;
        frame_re[152 +: 8] = counter + 8'h13;
        frame_re[160 +: 8] = counter + 8'h14;
        frame_re[168 +: 8] = counter + 8'h15;
        frame_re[176 +: 8] = counter + 8'h16;
        frame_re[184 +: 8] = counter + 8'h17;
        frame_re[192 +: 8] = counter + 8'h18;
        frame_re[200 +: 8] = counter + 8'h19;
        frame_re[208 +: 8] = counter + 8'h1a;
        frame_re[216 +: 8] = counter + 8'h1b;
        frame_re[224 +: 8] = counter + 8'h1c;
        frame_re[232 +: 8] = counter + 8'h1d;
        frame_re[240 +: 8] = counter + 8'h1e;
        frame_re[248 +: 8] = counter + 8'h1f;
    end

    (* DONT_TOUCH = "TRUE", KEEP_HIERARCHY = "TRUE" *)
    fft32_parallel core (
        .clk(clk), .rst(rst), .in_valid(frame_valid),
        .in_re(frame_re), .in_im(frame_im),
        .out_valid(core_valid), .out_re(core_re), .out_im(core_im)
    );

    // Capture every FFT output bit at the valid boundary. This makes the
    // implementation wrapper a real synchronous sink for the full frame,
    // while status is a registered reduction checksum for observability.
    (* DONT_TOUCH = "TRUE" *) reg signed [255:0] captured_re;
    (* DONT_TOUCH = "TRUE" *) reg signed [255:0] captured_im;
    (* DONT_TOUCH = "TRUE" *) reg captured_valid;
    reg status_reg;
    always @(posedge clk) begin
        if (rst) begin
            captured_re <= '0;
            captured_im <= '0;
            captured_valid <= 1'b0;
            status_reg <= 1'b0;
        end else begin
            captured_valid <= core_valid;
            if (core_valid) begin
                captured_re <= core_re;
                captured_im <= core_im;
            end
            status_reg <= captured_valid ^ (^captured_re) ^ (^captured_im);
        end
    end
    assign status = status_reg;
endmodule

module fft64_impl_top (
    input  wire clk,
    input  wire rst,
    output wire status
);
    reg [7:0] counter;
    reg frame_valid;
    reg signed [511:0] frame_re;
    reg signed [511:0] frame_im;
    wire core_valid;
    wire signed [511:0] core_re;
    wire signed [511:0] core_im;

    always @(posedge clk) begin
        if (rst) begin
            counter <= 8'h00;
            frame_valid <= 1'b0;
        end else begin
            counter <= counter + 8'h01;
            frame_valid <= (counter == 8'h00);
        end
    end

    always @* begin
        frame_re = '0;
        frame_im = '0;
        frame_re[0 +: 8] = counter;
        frame_re[8 +: 8] = counter + 8'h01;
        frame_re[16 +: 8] = counter + 8'h02;
        frame_re[24 +: 8] = counter + 8'h03;
        frame_re[32 +: 8] = counter + 8'h04;
        frame_re[40 +: 8] = counter + 8'h05;
        frame_re[48 +: 8] = counter + 8'h06;
        frame_re[56 +: 8] = counter + 8'h07;
        frame_re[64 +: 8] = counter + 8'h08;
        frame_re[72 +: 8] = counter + 8'h09;
        frame_re[80 +: 8] = counter + 8'h0a;
        frame_re[88 +: 8] = counter + 8'h0b;
        frame_re[96 +: 8] = counter + 8'h0c;
        frame_re[104 +: 8] = counter + 8'h0d;
        frame_re[112 +: 8] = counter + 8'h0e;
        frame_re[120 +: 8] = counter + 8'h0f;
        frame_re[128 +: 8] = counter + 8'h10;
        frame_re[136 +: 8] = counter + 8'h11;
        frame_re[144 +: 8] = counter + 8'h12;
        frame_re[152 +: 8] = counter + 8'h13;
        frame_re[160 +: 8] = counter + 8'h14;
        frame_re[168 +: 8] = counter + 8'h15;
        frame_re[176 +: 8] = counter + 8'h16;
        frame_re[184 +: 8] = counter + 8'h17;
        frame_re[192 +: 8] = counter + 8'h18;
        frame_re[200 +: 8] = counter + 8'h19;
        frame_re[208 +: 8] = counter + 8'h1a;
        frame_re[216 +: 8] = counter + 8'h1b;
        frame_re[224 +: 8] = counter + 8'h1c;
        frame_re[232 +: 8] = counter + 8'h1d;
        frame_re[240 +: 8] = counter + 8'h1e;
        frame_re[248 +: 8] = counter + 8'h1f;
        frame_re[256 +: 8] = counter + 8'h20;
        frame_re[264 +: 8] = counter + 8'h21;
        frame_re[272 +: 8] = counter + 8'h22;
        frame_re[280 +: 8] = counter + 8'h23;
        frame_re[288 +: 8] = counter + 8'h24;
        frame_re[296 +: 8] = counter + 8'h25;
        frame_re[304 +: 8] = counter + 8'h26;
        frame_re[312 +: 8] = counter + 8'h27;
        frame_re[320 +: 8] = counter + 8'h28;
        frame_re[328 +: 8] = counter + 8'h29;
        frame_re[336 +: 8] = counter + 8'h2a;
        frame_re[344 +: 8] = counter + 8'h2b;
        frame_re[352 +: 8] = counter + 8'h2c;
        frame_re[360 +: 8] = counter + 8'h2d;
        frame_re[368 +: 8] = counter + 8'h2e;
        frame_re[376 +: 8] = counter + 8'h2f;
        frame_re[384 +: 8] = counter + 8'h30;
        frame_re[392 +: 8] = counter + 8'h31;
        frame_re[400 +: 8] = counter + 8'h32;
        frame_re[408 +: 8] = counter + 8'h33;
        frame_re[416 +: 8] = counter + 8'h34;
        frame_re[424 +: 8] = counter + 8'h35;
        frame_re[432 +: 8] = counter + 8'h36;
        frame_re[440 +: 8] = counter + 8'h37;
        frame_re[448 +: 8] = counter + 8'h38;
        frame_re[456 +: 8] = counter + 8'h39;
        frame_re[464 +: 8] = counter + 8'h3a;
        frame_re[472 +: 8] = counter + 8'h3b;
        frame_re[480 +: 8] = counter + 8'h3c;
        frame_re[488 +: 8] = counter + 8'h3d;
        frame_re[496 +: 8] = counter + 8'h3e;
        frame_re[504 +: 8] = counter + 8'h3f;
    end

    (* DONT_TOUCH = "TRUE", KEEP_HIERARCHY = "TRUE" *)
    fft64_parallel core (
        .clk(clk), .rst(rst), .in_valid(frame_valid),
        .in_re(frame_re), .in_im(frame_im),
        .out_valid(core_valid), .out_re(core_re), .out_im(core_im)
    );

    // Capture every FFT output bit at the valid boundary. This makes the
    // implementation wrapper a real synchronous sink for the full frame,
    // while status is a registered reduction checksum for observability.
    (* DONT_TOUCH = "TRUE" *) reg signed [511:0] captured_re;
    (* DONT_TOUCH = "TRUE" *) reg signed [511:0] captured_im;
    (* DONT_TOUCH = "TRUE" *) reg captured_valid;
    reg status_reg;
    always @(posedge clk) begin
        if (rst) begin
            captured_re <= '0;
            captured_im <= '0;
            captured_valid <= 1'b0;
            status_reg <= 1'b0;
        end else begin
            captured_valid <= core_valid;
            if (core_valid) begin
                captured_re <= core_re;
                captured_im <= core_im;
            end
            status_reg <= captured_valid ^ (^captured_re) ^ (^captured_im);
        end
    end
    assign status = status_reg;
endmodule
