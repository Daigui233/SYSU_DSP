`timescale 1ns/1ps
// Parallel fixed-point FFT for xcvu13p.
// Inputs and outputs are signed 8-bit complex samples packed with sample 0 at bit 0.
// Every radix-2 butterfly divides by two, so the transform is normalized by N.
// Twiddles are signed Q1.15 constants. Every real multiplication uses one DSP48E2
// primitive with a three-register multiplier pipeline; no Verilog multiply operator
// is used in the RTL datapath.

module dsp48_mult3 #(
    parameter integer A_W = 20,
    parameter integer B_W = 16
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire signed [A_W-1:0]        a,
    input  wire signed [B_W-1:0]        b,
    output wire signed [47:0]           p
);
    wire [29:0] a_ext;
    wire [17:0] b_ext;
    wire [47:0] p_int;

    assign a_ext = {{(30-A_W){a[A_W-1]}}, a};
    assign b_ext = {{(18-B_W){b[B_W-1]}}, b};

    DSP48E2 #(
        .ACASCREG(1), .ADREG(0), .ALUMODEREG(0),
        .AMULTSEL("A"), .AREG(1), .AUTORESET_PATDET("NO_RESET"),
        .BCASCREG(1), .BREG(1), .BMULTSEL("B"),
        .CARRYINREG(0), .CARRYINSELREG(0), .CREG(0), .DREG(0),
        .INMODEREG(0), .MREG(1), .OPMODEREG(0), .PREG(0),
        .PREADDINSEL("A"), .USE_MULT("MULTIPLY"), .USE_SIMD("ONE48"),
        .A_INPUT("DIRECT"), .B_INPUT("DIRECT")
    ) u_dsp48e2 (
        .ACOUT(), .BCOUT(), .CARRYCASCOUT(), .CARRYOUT(),
        .MULTSIGNOUT(), .OVERFLOW(), .P(p_int),
        .PATTERNBDETECT(), .PATTERNDETECT(), .PCOUT(), .UNDERFLOW(), .XOROUT(),
        .A(a_ext), .ACIN(30'b0), .ALUMODE(4'b0000), .B(b_ext), .BCIN(18'b0),
        .C(48'b0), .CARRYCASCIN(1'b0), .CARRYIN(1'b0), .CARRYINSEL(3'b000),
        .CEA1(1'b1), .CEA2(1'b1), .CEAD(1'b0), .CEALUMODE(1'b1),
        .CEB1(1'b1), .CEB2(1'b1), .CEC(1'b0), .CECARRYIN(1'b0),
        .CECTRL(1'b1), .CED(1'b0), .CEINMODE(1'b1), .CEM(1'b1), .CEP(1'b1),
        .CLK(clk), .D(27'b0), .INMODE(5'b00000), .MULTSIGNIN(1'b0),
        // Z=0, Y=V_DATA, X=U_DATA: pure A*B multiplication without PCIN.
        .OPMODE(9'b000000101), .PCIN(48'b0),
        .RSTA(rst), .RSTALLCARRYIN(rst), .RSTALUMODE(rst), .RSTB(rst),
        .RSTC(rst), .RSTCTRL(rst), .RSTD(rst), .RSTINMODE(rst), .RSTM(rst), .RSTP(rst)
    );

    assign p = $signed(p_int);
endmodule

module complex_butterfly_pipe #(
    parameter integer DATA_W = 20,
    parameter integer TW_RE  = 0,
    parameter integer TW_IM  = 0
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         valid_i,
    input  wire signed [DATA_W-1:0]     a_re,
    input  wire signed [DATA_W-1:0]     a_im,
    input  wire signed [DATA_W-1:0]     b_re,
    input  wire signed [DATA_W-1:0]     b_im,
    output wire                         valid_o,
    output wire signed [DATA_W-1:0]     y0_re,
    output wire signed [DATA_W-1:0]     y0_im,
    output wire signed [DATA_W-1:0]     y1_re,
    output wire signed [DATA_W-1:0]     y1_im
);
    localparam integer Q_SHIFT = 15;
    localparam signed [15:0] TW_RE_S = TW_RE;
    localparam signed [15:0] TW_IM_S = TW_IM;

    wire signed [47:0] p_rr;
    wire signed [47:0] p_ii;
    wire signed [47:0] p_ri;
    wire signed [47:0] p_ir;
    wire signed [47:0] mult_re_full;
    wire signed [47:0] mult_im_full;
    wire signed [DATA_W-1:0] mult_re_q15;
    wire signed [DATA_W-1:0] mult_im_q15;

    // DSP48E2 uses one A/B input register and one multiplier register
    // (PREG is disabled), so the multiplier result is aligned after two
    // clock edges.  The bypass A path and valid marker must use the same
    // two-edge delay for back-to-back frames.
    reg signed [DATA_W-1:0] a_re_d0, a_re_d1;
    reg signed [DATA_W-1:0] a_im_d0, a_im_d1;
    reg [1:0] valid_d;

    wire signed [DATA_W:0] sum_re;
    wire signed [DATA_W:0] sum_im;
    wire signed [DATA_W:0] dif_re;
    wire signed [DATA_W:0] dif_im;

    dsp48_mult3 #(.A_W(DATA_W), .B_W(16)) u_rr (
        .clk(clk), .rst(rst), .a(b_re), .b(TW_RE_S), .p(p_rr)
    );
    dsp48_mult3 #(.A_W(DATA_W), .B_W(16)) u_ii (
        .clk(clk), .rst(rst), .a(b_im), .b(TW_IM_S), .p(p_ii)
    );
    dsp48_mult3 #(.A_W(DATA_W), .B_W(16)) u_ri (
        .clk(clk), .rst(rst), .a(b_re), .b(TW_IM_S), .p(p_ri)
    );
    dsp48_mult3 #(.A_W(DATA_W), .B_W(16)) u_ir (
        .clk(clk), .rst(rst), .a(b_im), .b(TW_RE_S), .p(p_ir)
    );

    assign mult_re_full = $signed(p_rr) - $signed(p_ii);
    assign mult_im_full = $signed(p_ri) + $signed(p_ir);
    assign mult_re_q15 = mult_re_full >>> Q_SHIFT;
    assign mult_im_q15 = mult_im_full >>> Q_SHIFT;

    assign sum_re = $signed(a_re_d1) + $signed(mult_re_q15);
    assign sum_im = $signed(a_im_d1) + $signed(mult_im_q15);
    assign dif_re = $signed(a_re_d1) - $signed(mult_re_q15);
    assign dif_im = $signed(a_im_d1) - $signed(mult_im_q15);

    assign y0_re = sum_re >>> 1;
    assign y0_im = sum_im >>> 1;
    assign y1_re = dif_re >>> 1;
    assign y1_im = dif_im >>> 1;
    assign valid_o = valid_d[1];

    always @(posedge clk) begin
        if (rst) begin
            a_re_d0 <= '0;
            a_re_d1 <= '0;
            a_im_d0 <= '0;
            a_im_d1 <= '0;
            valid_d <= 2'b00;
        end else begin
            a_re_d0 <= a_re;
            a_re_d1 <= a_re_d0;
            a_im_d0 <= a_im;
            a_im_d1 <= a_im_d0;
            valid_d <= {valid_d[0], valid_i};
        end
    end
endmodule

module fft32_parallel (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         in_valid,
    input  wire signed [255:0] in_re,
    input  wire signed [255:0] in_im,
    output wire                         out_valid,
    output reg  signed [255:0] out_re,
    output reg  signed [255:0] out_im
);
    wire signed [19:0] stage_re [0:5][0:31];
    wire signed [19:0] stage_im [0:5][0:31];
    wire stage_valid [0:5];
    assign stage_valid[0] = in_valid;
    assign stage_re[0][0] = {{12{in_re[7]}}, in_re[0 +: 8]};
    assign stage_im[0][0] = {{12{in_im[7]}}, in_im[0 +: 8]};
    assign stage_re[0][1] = {{12{in_re[135]}}, in_re[128 +: 8]};
    assign stage_im[0][1] = {{12{in_im[135]}}, in_im[128 +: 8]};
    assign stage_re[0][2] = {{12{in_re[71]}}, in_re[64 +: 8]};
    assign stage_im[0][2] = {{12{in_im[71]}}, in_im[64 +: 8]};
    assign stage_re[0][3] = {{12{in_re[199]}}, in_re[192 +: 8]};
    assign stage_im[0][3] = {{12{in_im[199]}}, in_im[192 +: 8]};
    assign stage_re[0][4] = {{12{in_re[39]}}, in_re[32 +: 8]};
    assign stage_im[0][4] = {{12{in_im[39]}}, in_im[32 +: 8]};
    assign stage_re[0][5] = {{12{in_re[167]}}, in_re[160 +: 8]};
    assign stage_im[0][5] = {{12{in_im[167]}}, in_im[160 +: 8]};
    assign stage_re[0][6] = {{12{in_re[103]}}, in_re[96 +: 8]};
    assign stage_im[0][6] = {{12{in_im[103]}}, in_im[96 +: 8]};
    assign stage_re[0][7] = {{12{in_re[231]}}, in_re[224 +: 8]};
    assign stage_im[0][7] = {{12{in_im[231]}}, in_im[224 +: 8]};
    assign stage_re[0][8] = {{12{in_re[23]}}, in_re[16 +: 8]};
    assign stage_im[0][8] = {{12{in_im[23]}}, in_im[16 +: 8]};
    assign stage_re[0][9] = {{12{in_re[151]}}, in_re[144 +: 8]};
    assign stage_im[0][9] = {{12{in_im[151]}}, in_im[144 +: 8]};
    assign stage_re[0][10] = {{12{in_re[87]}}, in_re[80 +: 8]};
    assign stage_im[0][10] = {{12{in_im[87]}}, in_im[80 +: 8]};
    assign stage_re[0][11] = {{12{in_re[215]}}, in_re[208 +: 8]};
    assign stage_im[0][11] = {{12{in_im[215]}}, in_im[208 +: 8]};
    assign stage_re[0][12] = {{12{in_re[55]}}, in_re[48 +: 8]};
    assign stage_im[0][12] = {{12{in_im[55]}}, in_im[48 +: 8]};
    assign stage_re[0][13] = {{12{in_re[183]}}, in_re[176 +: 8]};
    assign stage_im[0][13] = {{12{in_im[183]}}, in_im[176 +: 8]};
    assign stage_re[0][14] = {{12{in_re[119]}}, in_re[112 +: 8]};
    assign stage_im[0][14] = {{12{in_im[119]}}, in_im[112 +: 8]};
    assign stage_re[0][15] = {{12{in_re[247]}}, in_re[240 +: 8]};
    assign stage_im[0][15] = {{12{in_im[247]}}, in_im[240 +: 8]};
    assign stage_re[0][16] = {{12{in_re[15]}}, in_re[8 +: 8]};
    assign stage_im[0][16] = {{12{in_im[15]}}, in_im[8 +: 8]};
    assign stage_re[0][17] = {{12{in_re[143]}}, in_re[136 +: 8]};
    assign stage_im[0][17] = {{12{in_im[143]}}, in_im[136 +: 8]};
    assign stage_re[0][18] = {{12{in_re[79]}}, in_re[72 +: 8]};
    assign stage_im[0][18] = {{12{in_im[79]}}, in_im[72 +: 8]};
    assign stage_re[0][19] = {{12{in_re[207]}}, in_re[200 +: 8]};
    assign stage_im[0][19] = {{12{in_im[207]}}, in_im[200 +: 8]};
    assign stage_re[0][20] = {{12{in_re[47]}}, in_re[40 +: 8]};
    assign stage_im[0][20] = {{12{in_im[47]}}, in_im[40 +: 8]};
    assign stage_re[0][21] = {{12{in_re[175]}}, in_re[168 +: 8]};
    assign stage_im[0][21] = {{12{in_im[175]}}, in_im[168 +: 8]};
    assign stage_re[0][22] = {{12{in_re[111]}}, in_re[104 +: 8]};
    assign stage_im[0][22] = {{12{in_im[111]}}, in_im[104 +: 8]};
    assign stage_re[0][23] = {{12{in_re[239]}}, in_re[232 +: 8]};
    assign stage_im[0][23] = {{12{in_im[239]}}, in_im[232 +: 8]};
    assign stage_re[0][24] = {{12{in_re[31]}}, in_re[24 +: 8]};
    assign stage_im[0][24] = {{12{in_im[31]}}, in_im[24 +: 8]};
    assign stage_re[0][25] = {{12{in_re[159]}}, in_re[152 +: 8]};
    assign stage_im[0][25] = {{12{in_im[159]}}, in_im[152 +: 8]};
    assign stage_re[0][26] = {{12{in_re[95]}}, in_re[88 +: 8]};
    assign stage_im[0][26] = {{12{in_im[95]}}, in_im[88 +: 8]};
    assign stage_re[0][27] = {{12{in_re[223]}}, in_re[216 +: 8]};
    assign stage_im[0][27] = {{12{in_im[223]}}, in_im[216 +: 8]};
    assign stage_re[0][28] = {{12{in_re[63]}}, in_re[56 +: 8]};
    assign stage_im[0][28] = {{12{in_im[63]}}, in_im[56 +: 8]};
    assign stage_re[0][29] = {{12{in_re[191]}}, in_re[184 +: 8]};
    assign stage_im[0][29] = {{12{in_im[191]}}, in_im[184 +: 8]};
    assign stage_re[0][30] = {{12{in_re[127]}}, in_re[120 +: 8]};
    assign stage_im[0][30] = {{12{in_im[127]}}, in_im[120 +: 8]};
    assign stage_re[0][31] = {{12{in_re[255]}}, in_re[248 +: 8]};
    assign stage_im[0][31] = {{12{in_im[255]}}, in_im[248 +: 8]};
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b0_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][0]), .a_im(stage_im[0][0]),
        .b_re(stage_re[0][1]), .b_im(stage_im[0][1]),
        .valid_o(stage_valid[1]),
        .y0_re(stage_re[1][0]), .y0_im(stage_im[1][0]),
        .y1_re(stage_re[1][1]), .y1_im(stage_im[1][1])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b2_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][2]), .a_im(stage_im[0][2]),
        .b_re(stage_re[0][3]), .b_im(stage_im[0][3]),
        .valid_o(),
        .y0_re(stage_re[1][2]), .y0_im(stage_im[1][2]),
        .y1_re(stage_re[1][3]), .y1_im(stage_im[1][3])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b4_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][4]), .a_im(stage_im[0][4]),
        .b_re(stage_re[0][5]), .b_im(stage_im[0][5]),
        .valid_o(),
        .y0_re(stage_re[1][4]), .y0_im(stage_im[1][4]),
        .y1_re(stage_re[1][5]), .y1_im(stage_im[1][5])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b6_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][6]), .a_im(stage_im[0][6]),
        .b_re(stage_re[0][7]), .b_im(stage_im[0][7]),
        .valid_o(),
        .y0_re(stage_re[1][6]), .y0_im(stage_im[1][6]),
        .y1_re(stage_re[1][7]), .y1_im(stage_im[1][7])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b8_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][8]), .a_im(stage_im[0][8]),
        .b_re(stage_re[0][9]), .b_im(stage_im[0][9]),
        .valid_o(),
        .y0_re(stage_re[1][8]), .y0_im(stage_im[1][8]),
        .y1_re(stage_re[1][9]), .y1_im(stage_im[1][9])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b10_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][10]), .a_im(stage_im[0][10]),
        .b_re(stage_re[0][11]), .b_im(stage_im[0][11]),
        .valid_o(),
        .y0_re(stage_re[1][10]), .y0_im(stage_im[1][10]),
        .y1_re(stage_re[1][11]), .y1_im(stage_im[1][11])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b12_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][12]), .a_im(stage_im[0][12]),
        .b_re(stage_re[0][13]), .b_im(stage_im[0][13]),
        .valid_o(),
        .y0_re(stage_re[1][12]), .y0_im(stage_im[1][12]),
        .y1_re(stage_re[1][13]), .y1_im(stage_im[1][13])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b14_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][14]), .a_im(stage_im[0][14]),
        .b_re(stage_re[0][15]), .b_im(stage_im[0][15]),
        .valid_o(),
        .y0_re(stage_re[1][14]), .y0_im(stage_im[1][14]),
        .y1_re(stage_re[1][15]), .y1_im(stage_im[1][15])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b16_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][16]), .a_im(stage_im[0][16]),
        .b_re(stage_re[0][17]), .b_im(stage_im[0][17]),
        .valid_o(),
        .y0_re(stage_re[1][16]), .y0_im(stage_im[1][16]),
        .y1_re(stage_re[1][17]), .y1_im(stage_im[1][17])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b18_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][18]), .a_im(stage_im[0][18]),
        .b_re(stage_re[0][19]), .b_im(stage_im[0][19]),
        .valid_o(),
        .y0_re(stage_re[1][18]), .y0_im(stage_im[1][18]),
        .y1_re(stage_re[1][19]), .y1_im(stage_im[1][19])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b20_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][20]), .a_im(stage_im[0][20]),
        .b_re(stage_re[0][21]), .b_im(stage_im[0][21]),
        .valid_o(),
        .y0_re(stage_re[1][20]), .y0_im(stage_im[1][20]),
        .y1_re(stage_re[1][21]), .y1_im(stage_im[1][21])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b22_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][22]), .a_im(stage_im[0][22]),
        .b_re(stage_re[0][23]), .b_im(stage_im[0][23]),
        .valid_o(),
        .y0_re(stage_re[1][22]), .y0_im(stage_im[1][22]),
        .y1_re(stage_re[1][23]), .y1_im(stage_im[1][23])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b24_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][24]), .a_im(stage_im[0][24]),
        .b_re(stage_re[0][25]), .b_im(stage_im[0][25]),
        .valid_o(),
        .y0_re(stage_re[1][24]), .y0_im(stage_im[1][24]),
        .y1_re(stage_re[1][25]), .y1_im(stage_im[1][25])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b26_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][26]), .a_im(stage_im[0][26]),
        .b_re(stage_re[0][27]), .b_im(stage_im[0][27]),
        .valid_o(),
        .y0_re(stage_re[1][26]), .y0_im(stage_im[1][26]),
        .y1_re(stage_re[1][27]), .y1_im(stage_im[1][27])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b28_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][28]), .a_im(stage_im[0][28]),
        .b_re(stage_re[0][29]), .b_im(stage_im[0][29]),
        .valid_o(),
        .y0_re(stage_re[1][28]), .y0_im(stage_im[1][28]),
        .y1_re(stage_re[1][29]), .y1_im(stage_im[1][29])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b30_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][30]), .a_im(stage_im[0][30]),
        .b_re(stage_re[0][31]), .b_im(stage_im[0][31]),
        .valid_o(),
        .y0_re(stage_re[1][30]), .y0_im(stage_im[1][30]),
        .y1_re(stage_re[1][31]), .y1_im(stage_im[1][31])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s1_b0_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][0]), .a_im(stage_im[1][0]),
        .b_re(stage_re[1][2]), .b_im(stage_im[1][2]),
        .valid_o(stage_valid[2]),
        .y0_re(stage_re[2][0]), .y0_im(stage_im[2][0]),
        .y1_re(stage_re[2][2]), .y1_im(stage_im[2][2])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s1_b0_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][1]), .a_im(stage_im[1][1]),
        .b_re(stage_re[1][3]), .b_im(stage_im[1][3]),
        .valid_o(),
        .y0_re(stage_re[2][1]), .y0_im(stage_im[2][1]),
        .y1_re(stage_re[2][3]), .y1_im(stage_im[2][3])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s1_b4_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][4]), .a_im(stage_im[1][4]),
        .b_re(stage_re[1][6]), .b_im(stage_im[1][6]),
        .valid_o(),
        .y0_re(stage_re[2][4]), .y0_im(stage_im[2][4]),
        .y1_re(stage_re[2][6]), .y1_im(stage_im[2][6])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s1_b4_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][5]), .a_im(stage_im[1][5]),
        .b_re(stage_re[1][7]), .b_im(stage_im[1][7]),
        .valid_o(),
        .y0_re(stage_re[2][5]), .y0_im(stage_im[2][5]),
        .y1_re(stage_re[2][7]), .y1_im(stage_im[2][7])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s1_b8_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][8]), .a_im(stage_im[1][8]),
        .b_re(stage_re[1][10]), .b_im(stage_im[1][10]),
        .valid_o(),
        .y0_re(stage_re[2][8]), .y0_im(stage_im[2][8]),
        .y1_re(stage_re[2][10]), .y1_im(stage_im[2][10])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s1_b8_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][9]), .a_im(stage_im[1][9]),
        .b_re(stage_re[1][11]), .b_im(stage_im[1][11]),
        .valid_o(),
        .y0_re(stage_re[2][9]), .y0_im(stage_im[2][9]),
        .y1_re(stage_re[2][11]), .y1_im(stage_im[2][11])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s1_b12_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][12]), .a_im(stage_im[1][12]),
        .b_re(stage_re[1][14]), .b_im(stage_im[1][14]),
        .valid_o(),
        .y0_re(stage_re[2][12]), .y0_im(stage_im[2][12]),
        .y1_re(stage_re[2][14]), .y1_im(stage_im[2][14])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s1_b12_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][13]), .a_im(stage_im[1][13]),
        .b_re(stage_re[1][15]), .b_im(stage_im[1][15]),
        .valid_o(),
        .y0_re(stage_re[2][13]), .y0_im(stage_im[2][13]),
        .y1_re(stage_re[2][15]), .y1_im(stage_im[2][15])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s1_b16_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][16]), .a_im(stage_im[1][16]),
        .b_re(stage_re[1][18]), .b_im(stage_im[1][18]),
        .valid_o(),
        .y0_re(stage_re[2][16]), .y0_im(stage_im[2][16]),
        .y1_re(stage_re[2][18]), .y1_im(stage_im[2][18])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s1_b16_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][17]), .a_im(stage_im[1][17]),
        .b_re(stage_re[1][19]), .b_im(stage_im[1][19]),
        .valid_o(),
        .y0_re(stage_re[2][17]), .y0_im(stage_im[2][17]),
        .y1_re(stage_re[2][19]), .y1_im(stage_im[2][19])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s1_b20_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][20]), .a_im(stage_im[1][20]),
        .b_re(stage_re[1][22]), .b_im(stage_im[1][22]),
        .valid_o(),
        .y0_re(stage_re[2][20]), .y0_im(stage_im[2][20]),
        .y1_re(stage_re[2][22]), .y1_im(stage_im[2][22])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s1_b20_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][21]), .a_im(stage_im[1][21]),
        .b_re(stage_re[1][23]), .b_im(stage_im[1][23]),
        .valid_o(),
        .y0_re(stage_re[2][21]), .y0_im(stage_im[2][21]),
        .y1_re(stage_re[2][23]), .y1_im(stage_im[2][23])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s1_b24_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][24]), .a_im(stage_im[1][24]),
        .b_re(stage_re[1][26]), .b_im(stage_im[1][26]),
        .valid_o(),
        .y0_re(stage_re[2][24]), .y0_im(stage_im[2][24]),
        .y1_re(stage_re[2][26]), .y1_im(stage_im[2][26])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s1_b24_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][25]), .a_im(stage_im[1][25]),
        .b_re(stage_re[1][27]), .b_im(stage_im[1][27]),
        .valid_o(),
        .y0_re(stage_re[2][25]), .y0_im(stage_im[2][25]),
        .y1_re(stage_re[2][27]), .y1_im(stage_im[2][27])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s1_b28_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][28]), .a_im(stage_im[1][28]),
        .b_re(stage_re[1][30]), .b_im(stage_im[1][30]),
        .valid_o(),
        .y0_re(stage_re[2][28]), .y0_im(stage_im[2][28]),
        .y1_re(stage_re[2][30]), .y1_im(stage_im[2][30])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s1_b28_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][29]), .a_im(stage_im[1][29]),
        .b_re(stage_re[1][31]), .b_im(stage_im[1][31]),
        .valid_o(),
        .y0_re(stage_re[2][29]), .y0_im(stage_im[2][29]),
        .y1_re(stage_re[2][31]), .y1_im(stage_im[2][31])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s2_b0_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][0]), .a_im(stage_im[2][0]),
        .b_re(stage_re[2][4]), .b_im(stage_im[2][4]),
        .valid_o(stage_valid[3]),
        .y0_re(stage_re[3][0]), .y0_im(stage_im[3][0]),
        .y1_re(stage_re[3][4]), .y1_im(stage_im[3][4])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(23170), .TW_IM(-23170)) u_s2_b0_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][1]), .a_im(stage_im[2][1]),
        .b_re(stage_re[2][5]), .b_im(stage_im[2][5]),
        .valid_o(),
        .y0_re(stage_re[3][1]), .y0_im(stage_im[3][1]),
        .y1_re(stage_re[3][5]), .y1_im(stage_im[3][5])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s2_b0_2 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][2]), .a_im(stage_im[2][2]),
        .b_re(stage_re[2][6]), .b_im(stage_im[2][6]),
        .valid_o(),
        .y0_re(stage_re[3][2]), .y0_im(stage_im[3][2]),
        .y1_re(stage_re[3][6]), .y1_im(stage_im[3][6])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-23170), .TW_IM(-23170)) u_s2_b0_3 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][3]), .a_im(stage_im[2][3]),
        .b_re(stage_re[2][7]), .b_im(stage_im[2][7]),
        .valid_o(),
        .y0_re(stage_re[3][3]), .y0_im(stage_im[3][3]),
        .y1_re(stage_re[3][7]), .y1_im(stage_im[3][7])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s2_b8_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][8]), .a_im(stage_im[2][8]),
        .b_re(stage_re[2][12]), .b_im(stage_im[2][12]),
        .valid_o(),
        .y0_re(stage_re[3][8]), .y0_im(stage_im[3][8]),
        .y1_re(stage_re[3][12]), .y1_im(stage_im[3][12])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(23170), .TW_IM(-23170)) u_s2_b8_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][9]), .a_im(stage_im[2][9]),
        .b_re(stage_re[2][13]), .b_im(stage_im[2][13]),
        .valid_o(),
        .y0_re(stage_re[3][9]), .y0_im(stage_im[3][9]),
        .y1_re(stage_re[3][13]), .y1_im(stage_im[3][13])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s2_b8_2 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][10]), .a_im(stage_im[2][10]),
        .b_re(stage_re[2][14]), .b_im(stage_im[2][14]),
        .valid_o(),
        .y0_re(stage_re[3][10]), .y0_im(stage_im[3][10]),
        .y1_re(stage_re[3][14]), .y1_im(stage_im[3][14])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-23170), .TW_IM(-23170)) u_s2_b8_3 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][11]), .a_im(stage_im[2][11]),
        .b_re(stage_re[2][15]), .b_im(stage_im[2][15]),
        .valid_o(),
        .y0_re(stage_re[3][11]), .y0_im(stage_im[3][11]),
        .y1_re(stage_re[3][15]), .y1_im(stage_im[3][15])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s2_b16_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][16]), .a_im(stage_im[2][16]),
        .b_re(stage_re[2][20]), .b_im(stage_im[2][20]),
        .valid_o(),
        .y0_re(stage_re[3][16]), .y0_im(stage_im[3][16]),
        .y1_re(stage_re[3][20]), .y1_im(stage_im[3][20])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(23170), .TW_IM(-23170)) u_s2_b16_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][17]), .a_im(stage_im[2][17]),
        .b_re(stage_re[2][21]), .b_im(stage_im[2][21]),
        .valid_o(),
        .y0_re(stage_re[3][17]), .y0_im(stage_im[3][17]),
        .y1_re(stage_re[3][21]), .y1_im(stage_im[3][21])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s2_b16_2 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][18]), .a_im(stage_im[2][18]),
        .b_re(stage_re[2][22]), .b_im(stage_im[2][22]),
        .valid_o(),
        .y0_re(stage_re[3][18]), .y0_im(stage_im[3][18]),
        .y1_re(stage_re[3][22]), .y1_im(stage_im[3][22])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-23170), .TW_IM(-23170)) u_s2_b16_3 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][19]), .a_im(stage_im[2][19]),
        .b_re(stage_re[2][23]), .b_im(stage_im[2][23]),
        .valid_o(),
        .y0_re(stage_re[3][19]), .y0_im(stage_im[3][19]),
        .y1_re(stage_re[3][23]), .y1_im(stage_im[3][23])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s2_b24_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][24]), .a_im(stage_im[2][24]),
        .b_re(stage_re[2][28]), .b_im(stage_im[2][28]),
        .valid_o(),
        .y0_re(stage_re[3][24]), .y0_im(stage_im[3][24]),
        .y1_re(stage_re[3][28]), .y1_im(stage_im[3][28])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(23170), .TW_IM(-23170)) u_s2_b24_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][25]), .a_im(stage_im[2][25]),
        .b_re(stage_re[2][29]), .b_im(stage_im[2][29]),
        .valid_o(),
        .y0_re(stage_re[3][25]), .y0_im(stage_im[3][25]),
        .y1_re(stage_re[3][29]), .y1_im(stage_im[3][29])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s2_b24_2 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][26]), .a_im(stage_im[2][26]),
        .b_re(stage_re[2][30]), .b_im(stage_im[2][30]),
        .valid_o(),
        .y0_re(stage_re[3][26]), .y0_im(stage_im[3][26]),
        .y1_re(stage_re[3][30]), .y1_im(stage_im[3][30])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-23170), .TW_IM(-23170)) u_s2_b24_3 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][27]), .a_im(stage_im[2][27]),
        .b_re(stage_re[2][31]), .b_im(stage_im[2][31]),
        .valid_o(),
        .y0_re(stage_re[3][27]), .y0_im(stage_im[3][27]),
        .y1_re(stage_re[3][31]), .y1_im(stage_im[3][31])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s3_b0_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][0]), .a_im(stage_im[3][0]),
        .b_re(stage_re[3][8]), .b_im(stage_im[3][8]),
        .valid_o(stage_valid[4]),
        .y0_re(stage_re[4][0]), .y0_im(stage_im[4][0]),
        .y1_re(stage_re[4][8]), .y1_im(stage_im[4][8])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(30273), .TW_IM(-12539)) u_s3_b0_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][1]), .a_im(stage_im[3][1]),
        .b_re(stage_re[3][9]), .b_im(stage_im[3][9]),
        .valid_o(),
        .y0_re(stage_re[4][1]), .y0_im(stage_im[4][1]),
        .y1_re(stage_re[4][9]), .y1_im(stage_im[4][9])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(23170), .TW_IM(-23170)) u_s3_b0_2 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][2]), .a_im(stage_im[3][2]),
        .b_re(stage_re[3][10]), .b_im(stage_im[3][10]),
        .valid_o(),
        .y0_re(stage_re[4][2]), .y0_im(stage_im[4][2]),
        .y1_re(stage_re[4][10]), .y1_im(stage_im[4][10])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(12539), .TW_IM(-30273)) u_s3_b0_3 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][3]), .a_im(stage_im[3][3]),
        .b_re(stage_re[3][11]), .b_im(stage_im[3][11]),
        .valid_o(),
        .y0_re(stage_re[4][3]), .y0_im(stage_im[4][3]),
        .y1_re(stage_re[4][11]), .y1_im(stage_im[4][11])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s3_b0_4 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][4]), .a_im(stage_im[3][4]),
        .b_re(stage_re[3][12]), .b_im(stage_im[3][12]),
        .valid_o(),
        .y0_re(stage_re[4][4]), .y0_im(stage_im[4][4]),
        .y1_re(stage_re[4][12]), .y1_im(stage_im[4][12])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-12539), .TW_IM(-30273)) u_s3_b0_5 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][5]), .a_im(stage_im[3][5]),
        .b_re(stage_re[3][13]), .b_im(stage_im[3][13]),
        .valid_o(),
        .y0_re(stage_re[4][5]), .y0_im(stage_im[4][5]),
        .y1_re(stage_re[4][13]), .y1_im(stage_im[4][13])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-23170), .TW_IM(-23170)) u_s3_b0_6 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][6]), .a_im(stage_im[3][6]),
        .b_re(stage_re[3][14]), .b_im(stage_im[3][14]),
        .valid_o(),
        .y0_re(stage_re[4][6]), .y0_im(stage_im[4][6]),
        .y1_re(stage_re[4][14]), .y1_im(stage_im[4][14])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-30273), .TW_IM(-12539)) u_s3_b0_7 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][7]), .a_im(stage_im[3][7]),
        .b_re(stage_re[3][15]), .b_im(stage_im[3][15]),
        .valid_o(),
        .y0_re(stage_re[4][7]), .y0_im(stage_im[4][7]),
        .y1_re(stage_re[4][15]), .y1_im(stage_im[4][15])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s3_b16_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][16]), .a_im(stage_im[3][16]),
        .b_re(stage_re[3][24]), .b_im(stage_im[3][24]),
        .valid_o(),
        .y0_re(stage_re[4][16]), .y0_im(stage_im[4][16]),
        .y1_re(stage_re[4][24]), .y1_im(stage_im[4][24])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(30273), .TW_IM(-12539)) u_s3_b16_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][17]), .a_im(stage_im[3][17]),
        .b_re(stage_re[3][25]), .b_im(stage_im[3][25]),
        .valid_o(),
        .y0_re(stage_re[4][17]), .y0_im(stage_im[4][17]),
        .y1_re(stage_re[4][25]), .y1_im(stage_im[4][25])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(23170), .TW_IM(-23170)) u_s3_b16_2 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][18]), .a_im(stage_im[3][18]),
        .b_re(stage_re[3][26]), .b_im(stage_im[3][26]),
        .valid_o(),
        .y0_re(stage_re[4][18]), .y0_im(stage_im[4][18]),
        .y1_re(stage_re[4][26]), .y1_im(stage_im[4][26])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(12539), .TW_IM(-30273)) u_s3_b16_3 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][19]), .a_im(stage_im[3][19]),
        .b_re(stage_re[3][27]), .b_im(stage_im[3][27]),
        .valid_o(),
        .y0_re(stage_re[4][19]), .y0_im(stage_im[4][19]),
        .y1_re(stage_re[4][27]), .y1_im(stage_im[4][27])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s3_b16_4 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][20]), .a_im(stage_im[3][20]),
        .b_re(stage_re[3][28]), .b_im(stage_im[3][28]),
        .valid_o(),
        .y0_re(stage_re[4][20]), .y0_im(stage_im[4][20]),
        .y1_re(stage_re[4][28]), .y1_im(stage_im[4][28])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-12539), .TW_IM(-30273)) u_s3_b16_5 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][21]), .a_im(stage_im[3][21]),
        .b_re(stage_re[3][29]), .b_im(stage_im[3][29]),
        .valid_o(),
        .y0_re(stage_re[4][21]), .y0_im(stage_im[4][21]),
        .y1_re(stage_re[4][29]), .y1_im(stage_im[4][29])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-23170), .TW_IM(-23170)) u_s3_b16_6 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][22]), .a_im(stage_im[3][22]),
        .b_re(stage_re[3][30]), .b_im(stage_im[3][30]),
        .valid_o(),
        .y0_re(stage_re[4][22]), .y0_im(stage_im[4][22]),
        .y1_re(stage_re[4][30]), .y1_im(stage_im[4][30])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-30273), .TW_IM(-12539)) u_s3_b16_7 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][23]), .a_im(stage_im[3][23]),
        .b_re(stage_re[3][31]), .b_im(stage_im[3][31]),
        .valid_o(),
        .y0_re(stage_re[4][23]), .y0_im(stage_im[4][23]),
        .y1_re(stage_re[4][31]), .y1_im(stage_im[4][31])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s4_b0_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][0]), .a_im(stage_im[4][0]),
        .b_re(stage_re[4][16]), .b_im(stage_im[4][16]),
        .valid_o(stage_valid[5]),
        .y0_re(stage_re[5][0]), .y0_im(stage_im[5][0]),
        .y1_re(stage_re[5][16]), .y1_im(stage_im[5][16])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32137), .TW_IM(-6393)) u_s4_b0_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][1]), .a_im(stage_im[4][1]),
        .b_re(stage_re[4][17]), .b_im(stage_im[4][17]),
        .valid_o(),
        .y0_re(stage_re[5][1]), .y0_im(stage_im[5][1]),
        .y1_re(stage_re[5][17]), .y1_im(stage_im[5][17])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(30273), .TW_IM(-12539)) u_s4_b0_2 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][2]), .a_im(stage_im[4][2]),
        .b_re(stage_re[4][18]), .b_im(stage_im[4][18]),
        .valid_o(),
        .y0_re(stage_re[5][2]), .y0_im(stage_im[5][2]),
        .y1_re(stage_re[5][18]), .y1_im(stage_im[5][18])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(27245), .TW_IM(-18204)) u_s4_b0_3 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][3]), .a_im(stage_im[4][3]),
        .b_re(stage_re[4][19]), .b_im(stage_im[4][19]),
        .valid_o(),
        .y0_re(stage_re[5][3]), .y0_im(stage_im[5][3]),
        .y1_re(stage_re[5][19]), .y1_im(stage_im[5][19])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(23170), .TW_IM(-23170)) u_s4_b0_4 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][4]), .a_im(stage_im[4][4]),
        .b_re(stage_re[4][20]), .b_im(stage_im[4][20]),
        .valid_o(),
        .y0_re(stage_re[5][4]), .y0_im(stage_im[5][4]),
        .y1_re(stage_re[5][20]), .y1_im(stage_im[5][20])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(18204), .TW_IM(-27245)) u_s4_b0_5 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][5]), .a_im(stage_im[4][5]),
        .b_re(stage_re[4][21]), .b_im(stage_im[4][21]),
        .valid_o(),
        .y0_re(stage_re[5][5]), .y0_im(stage_im[5][5]),
        .y1_re(stage_re[5][21]), .y1_im(stage_im[5][21])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(12539), .TW_IM(-30273)) u_s4_b0_6 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][6]), .a_im(stage_im[4][6]),
        .b_re(stage_re[4][22]), .b_im(stage_im[4][22]),
        .valid_o(),
        .y0_re(stage_re[5][6]), .y0_im(stage_im[5][6]),
        .y1_re(stage_re[5][22]), .y1_im(stage_im[5][22])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(6393), .TW_IM(-32137)) u_s4_b0_7 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][7]), .a_im(stage_im[4][7]),
        .b_re(stage_re[4][23]), .b_im(stage_im[4][23]),
        .valid_o(),
        .y0_re(stage_re[5][7]), .y0_im(stage_im[5][7]),
        .y1_re(stage_re[5][23]), .y1_im(stage_im[5][23])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s4_b0_8 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][8]), .a_im(stage_im[4][8]),
        .b_re(stage_re[4][24]), .b_im(stage_im[4][24]),
        .valid_o(),
        .y0_re(stage_re[5][8]), .y0_im(stage_im[5][8]),
        .y1_re(stage_re[5][24]), .y1_im(stage_im[5][24])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-6393), .TW_IM(-32137)) u_s4_b0_9 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][9]), .a_im(stage_im[4][9]),
        .b_re(stage_re[4][25]), .b_im(stage_im[4][25]),
        .valid_o(),
        .y0_re(stage_re[5][9]), .y0_im(stage_im[5][9]),
        .y1_re(stage_re[5][25]), .y1_im(stage_im[5][25])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-12539), .TW_IM(-30273)) u_s4_b0_10 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][10]), .a_im(stage_im[4][10]),
        .b_re(stage_re[4][26]), .b_im(stage_im[4][26]),
        .valid_o(),
        .y0_re(stage_re[5][10]), .y0_im(stage_im[5][10]),
        .y1_re(stage_re[5][26]), .y1_im(stage_im[5][26])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-18204), .TW_IM(-27245)) u_s4_b0_11 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][11]), .a_im(stage_im[4][11]),
        .b_re(stage_re[4][27]), .b_im(stage_im[4][27]),
        .valid_o(),
        .y0_re(stage_re[5][11]), .y0_im(stage_im[5][11]),
        .y1_re(stage_re[5][27]), .y1_im(stage_im[5][27])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-23170), .TW_IM(-23170)) u_s4_b0_12 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][12]), .a_im(stage_im[4][12]),
        .b_re(stage_re[4][28]), .b_im(stage_im[4][28]),
        .valid_o(),
        .y0_re(stage_re[5][12]), .y0_im(stage_im[5][12]),
        .y1_re(stage_re[5][28]), .y1_im(stage_im[5][28])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-27245), .TW_IM(-18204)) u_s4_b0_13 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][13]), .a_im(stage_im[4][13]),
        .b_re(stage_re[4][29]), .b_im(stage_im[4][29]),
        .valid_o(),
        .y0_re(stage_re[5][13]), .y0_im(stage_im[5][13]),
        .y1_re(stage_re[5][29]), .y1_im(stage_im[5][29])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-30273), .TW_IM(-12539)) u_s4_b0_14 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][14]), .a_im(stage_im[4][14]),
        .b_re(stage_re[4][30]), .b_im(stage_im[4][30]),
        .valid_o(),
        .y0_re(stage_re[5][14]), .y0_im(stage_im[5][14]),
        .y1_re(stage_re[5][30]), .y1_im(stage_im[5][30])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-32137), .TW_IM(-6393)) u_s4_b0_15 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][15]), .a_im(stage_im[4][15]),
        .b_re(stage_re[4][31]), .b_im(stage_im[4][31]),
        .valid_o(),
        .y0_re(stage_re[5][15]), .y0_im(stage_im[5][15]),
        .y1_re(stage_re[5][31]), .y1_im(stage_im[5][31])
    );
    assign out_valid = stage_valid[5];
    function [7:0] sat8;
        input signed [19:0] value;
        begin
            if (value > 20'sd127) sat8 = 8'h7f;
            else if (value < -20'sd128) sat8 = 8'h80;
            else sat8 = value[7:0];
        end
    endfunction
    always @* begin
        out_re = '0;
        out_im = '0;
        out_re[0 +: 8] = sat8(stage_re[5][0]);
        out_im[0 +: 8] = sat8(stage_im[5][0]);
        out_re[8 +: 8] = sat8(stage_re[5][1]);
        out_im[8 +: 8] = sat8(stage_im[5][1]);
        out_re[16 +: 8] = sat8(stage_re[5][2]);
        out_im[16 +: 8] = sat8(stage_im[5][2]);
        out_re[24 +: 8] = sat8(stage_re[5][3]);
        out_im[24 +: 8] = sat8(stage_im[5][3]);
        out_re[32 +: 8] = sat8(stage_re[5][4]);
        out_im[32 +: 8] = sat8(stage_im[5][4]);
        out_re[40 +: 8] = sat8(stage_re[5][5]);
        out_im[40 +: 8] = sat8(stage_im[5][5]);
        out_re[48 +: 8] = sat8(stage_re[5][6]);
        out_im[48 +: 8] = sat8(stage_im[5][6]);
        out_re[56 +: 8] = sat8(stage_re[5][7]);
        out_im[56 +: 8] = sat8(stage_im[5][7]);
        out_re[64 +: 8] = sat8(stage_re[5][8]);
        out_im[64 +: 8] = sat8(stage_im[5][8]);
        out_re[72 +: 8] = sat8(stage_re[5][9]);
        out_im[72 +: 8] = sat8(stage_im[5][9]);
        out_re[80 +: 8] = sat8(stage_re[5][10]);
        out_im[80 +: 8] = sat8(stage_im[5][10]);
        out_re[88 +: 8] = sat8(stage_re[5][11]);
        out_im[88 +: 8] = sat8(stage_im[5][11]);
        out_re[96 +: 8] = sat8(stage_re[5][12]);
        out_im[96 +: 8] = sat8(stage_im[5][12]);
        out_re[104 +: 8] = sat8(stage_re[5][13]);
        out_im[104 +: 8] = sat8(stage_im[5][13]);
        out_re[112 +: 8] = sat8(stage_re[5][14]);
        out_im[112 +: 8] = sat8(stage_im[5][14]);
        out_re[120 +: 8] = sat8(stage_re[5][15]);
        out_im[120 +: 8] = sat8(stage_im[5][15]);
        out_re[128 +: 8] = sat8(stage_re[5][16]);
        out_im[128 +: 8] = sat8(stage_im[5][16]);
        out_re[136 +: 8] = sat8(stage_re[5][17]);
        out_im[136 +: 8] = sat8(stage_im[5][17]);
        out_re[144 +: 8] = sat8(stage_re[5][18]);
        out_im[144 +: 8] = sat8(stage_im[5][18]);
        out_re[152 +: 8] = sat8(stage_re[5][19]);
        out_im[152 +: 8] = sat8(stage_im[5][19]);
        out_re[160 +: 8] = sat8(stage_re[5][20]);
        out_im[160 +: 8] = sat8(stage_im[5][20]);
        out_re[168 +: 8] = sat8(stage_re[5][21]);
        out_im[168 +: 8] = sat8(stage_im[5][21]);
        out_re[176 +: 8] = sat8(stage_re[5][22]);
        out_im[176 +: 8] = sat8(stage_im[5][22]);
        out_re[184 +: 8] = sat8(stage_re[5][23]);
        out_im[184 +: 8] = sat8(stage_im[5][23]);
        out_re[192 +: 8] = sat8(stage_re[5][24]);
        out_im[192 +: 8] = sat8(stage_im[5][24]);
        out_re[200 +: 8] = sat8(stage_re[5][25]);
        out_im[200 +: 8] = sat8(stage_im[5][25]);
        out_re[208 +: 8] = sat8(stage_re[5][26]);
        out_im[208 +: 8] = sat8(stage_im[5][26]);
        out_re[216 +: 8] = sat8(stage_re[5][27]);
        out_im[216 +: 8] = sat8(stage_im[5][27]);
        out_re[224 +: 8] = sat8(stage_re[5][28]);
        out_im[224 +: 8] = sat8(stage_im[5][28]);
        out_re[232 +: 8] = sat8(stage_re[5][29]);
        out_im[232 +: 8] = sat8(stage_im[5][29]);
        out_re[240 +: 8] = sat8(stage_re[5][30]);
        out_im[240 +: 8] = sat8(stage_im[5][30]);
        out_re[248 +: 8] = sat8(stage_re[5][31]);
        out_im[248 +: 8] = sat8(stage_im[5][31]);
    end
endmodule
module fft64_parallel (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         in_valid,
    input  wire signed [511:0] in_re,
    input  wire signed [511:0] in_im,
    output wire                         out_valid,
    output reg  signed [511:0] out_re,
    output reg  signed [511:0] out_im
);
    wire signed [19:0] stage_re [0:6][0:63];
    wire signed [19:0] stage_im [0:6][0:63];
    wire stage_valid [0:6];
    assign stage_valid[0] = in_valid;
    assign stage_re[0][0] = {{12{in_re[7]}}, in_re[0 +: 8]};
    assign stage_im[0][0] = {{12{in_im[7]}}, in_im[0 +: 8]};
    assign stage_re[0][1] = {{12{in_re[263]}}, in_re[256 +: 8]};
    assign stage_im[0][1] = {{12{in_im[263]}}, in_im[256 +: 8]};
    assign stage_re[0][2] = {{12{in_re[135]}}, in_re[128 +: 8]};
    assign stage_im[0][2] = {{12{in_im[135]}}, in_im[128 +: 8]};
    assign stage_re[0][3] = {{12{in_re[391]}}, in_re[384 +: 8]};
    assign stage_im[0][3] = {{12{in_im[391]}}, in_im[384 +: 8]};
    assign stage_re[0][4] = {{12{in_re[71]}}, in_re[64 +: 8]};
    assign stage_im[0][4] = {{12{in_im[71]}}, in_im[64 +: 8]};
    assign stage_re[0][5] = {{12{in_re[327]}}, in_re[320 +: 8]};
    assign stage_im[0][5] = {{12{in_im[327]}}, in_im[320 +: 8]};
    assign stage_re[0][6] = {{12{in_re[199]}}, in_re[192 +: 8]};
    assign stage_im[0][6] = {{12{in_im[199]}}, in_im[192 +: 8]};
    assign stage_re[0][7] = {{12{in_re[455]}}, in_re[448 +: 8]};
    assign stage_im[0][7] = {{12{in_im[455]}}, in_im[448 +: 8]};
    assign stage_re[0][8] = {{12{in_re[39]}}, in_re[32 +: 8]};
    assign stage_im[0][8] = {{12{in_im[39]}}, in_im[32 +: 8]};
    assign stage_re[0][9] = {{12{in_re[295]}}, in_re[288 +: 8]};
    assign stage_im[0][9] = {{12{in_im[295]}}, in_im[288 +: 8]};
    assign stage_re[0][10] = {{12{in_re[167]}}, in_re[160 +: 8]};
    assign stage_im[0][10] = {{12{in_im[167]}}, in_im[160 +: 8]};
    assign stage_re[0][11] = {{12{in_re[423]}}, in_re[416 +: 8]};
    assign stage_im[0][11] = {{12{in_im[423]}}, in_im[416 +: 8]};
    assign stage_re[0][12] = {{12{in_re[103]}}, in_re[96 +: 8]};
    assign stage_im[0][12] = {{12{in_im[103]}}, in_im[96 +: 8]};
    assign stage_re[0][13] = {{12{in_re[359]}}, in_re[352 +: 8]};
    assign stage_im[0][13] = {{12{in_im[359]}}, in_im[352 +: 8]};
    assign stage_re[0][14] = {{12{in_re[231]}}, in_re[224 +: 8]};
    assign stage_im[0][14] = {{12{in_im[231]}}, in_im[224 +: 8]};
    assign stage_re[0][15] = {{12{in_re[487]}}, in_re[480 +: 8]};
    assign stage_im[0][15] = {{12{in_im[487]}}, in_im[480 +: 8]};
    assign stage_re[0][16] = {{12{in_re[23]}}, in_re[16 +: 8]};
    assign stage_im[0][16] = {{12{in_im[23]}}, in_im[16 +: 8]};
    assign stage_re[0][17] = {{12{in_re[279]}}, in_re[272 +: 8]};
    assign stage_im[0][17] = {{12{in_im[279]}}, in_im[272 +: 8]};
    assign stage_re[0][18] = {{12{in_re[151]}}, in_re[144 +: 8]};
    assign stage_im[0][18] = {{12{in_im[151]}}, in_im[144 +: 8]};
    assign stage_re[0][19] = {{12{in_re[407]}}, in_re[400 +: 8]};
    assign stage_im[0][19] = {{12{in_im[407]}}, in_im[400 +: 8]};
    assign stage_re[0][20] = {{12{in_re[87]}}, in_re[80 +: 8]};
    assign stage_im[0][20] = {{12{in_im[87]}}, in_im[80 +: 8]};
    assign stage_re[0][21] = {{12{in_re[343]}}, in_re[336 +: 8]};
    assign stage_im[0][21] = {{12{in_im[343]}}, in_im[336 +: 8]};
    assign stage_re[0][22] = {{12{in_re[215]}}, in_re[208 +: 8]};
    assign stage_im[0][22] = {{12{in_im[215]}}, in_im[208 +: 8]};
    assign stage_re[0][23] = {{12{in_re[471]}}, in_re[464 +: 8]};
    assign stage_im[0][23] = {{12{in_im[471]}}, in_im[464 +: 8]};
    assign stage_re[0][24] = {{12{in_re[55]}}, in_re[48 +: 8]};
    assign stage_im[0][24] = {{12{in_im[55]}}, in_im[48 +: 8]};
    assign stage_re[0][25] = {{12{in_re[311]}}, in_re[304 +: 8]};
    assign stage_im[0][25] = {{12{in_im[311]}}, in_im[304 +: 8]};
    assign stage_re[0][26] = {{12{in_re[183]}}, in_re[176 +: 8]};
    assign stage_im[0][26] = {{12{in_im[183]}}, in_im[176 +: 8]};
    assign stage_re[0][27] = {{12{in_re[439]}}, in_re[432 +: 8]};
    assign stage_im[0][27] = {{12{in_im[439]}}, in_im[432 +: 8]};
    assign stage_re[0][28] = {{12{in_re[119]}}, in_re[112 +: 8]};
    assign stage_im[0][28] = {{12{in_im[119]}}, in_im[112 +: 8]};
    assign stage_re[0][29] = {{12{in_re[375]}}, in_re[368 +: 8]};
    assign stage_im[0][29] = {{12{in_im[375]}}, in_im[368 +: 8]};
    assign stage_re[0][30] = {{12{in_re[247]}}, in_re[240 +: 8]};
    assign stage_im[0][30] = {{12{in_im[247]}}, in_im[240 +: 8]};
    assign stage_re[0][31] = {{12{in_re[503]}}, in_re[496 +: 8]};
    assign stage_im[0][31] = {{12{in_im[503]}}, in_im[496 +: 8]};
    assign stage_re[0][32] = {{12{in_re[15]}}, in_re[8 +: 8]};
    assign stage_im[0][32] = {{12{in_im[15]}}, in_im[8 +: 8]};
    assign stage_re[0][33] = {{12{in_re[271]}}, in_re[264 +: 8]};
    assign stage_im[0][33] = {{12{in_im[271]}}, in_im[264 +: 8]};
    assign stage_re[0][34] = {{12{in_re[143]}}, in_re[136 +: 8]};
    assign stage_im[0][34] = {{12{in_im[143]}}, in_im[136 +: 8]};
    assign stage_re[0][35] = {{12{in_re[399]}}, in_re[392 +: 8]};
    assign stage_im[0][35] = {{12{in_im[399]}}, in_im[392 +: 8]};
    assign stage_re[0][36] = {{12{in_re[79]}}, in_re[72 +: 8]};
    assign stage_im[0][36] = {{12{in_im[79]}}, in_im[72 +: 8]};
    assign stage_re[0][37] = {{12{in_re[335]}}, in_re[328 +: 8]};
    assign stage_im[0][37] = {{12{in_im[335]}}, in_im[328 +: 8]};
    assign stage_re[0][38] = {{12{in_re[207]}}, in_re[200 +: 8]};
    assign stage_im[0][38] = {{12{in_im[207]}}, in_im[200 +: 8]};
    assign stage_re[0][39] = {{12{in_re[463]}}, in_re[456 +: 8]};
    assign stage_im[0][39] = {{12{in_im[463]}}, in_im[456 +: 8]};
    assign stage_re[0][40] = {{12{in_re[47]}}, in_re[40 +: 8]};
    assign stage_im[0][40] = {{12{in_im[47]}}, in_im[40 +: 8]};
    assign stage_re[0][41] = {{12{in_re[303]}}, in_re[296 +: 8]};
    assign stage_im[0][41] = {{12{in_im[303]}}, in_im[296 +: 8]};
    assign stage_re[0][42] = {{12{in_re[175]}}, in_re[168 +: 8]};
    assign stage_im[0][42] = {{12{in_im[175]}}, in_im[168 +: 8]};
    assign stage_re[0][43] = {{12{in_re[431]}}, in_re[424 +: 8]};
    assign stage_im[0][43] = {{12{in_im[431]}}, in_im[424 +: 8]};
    assign stage_re[0][44] = {{12{in_re[111]}}, in_re[104 +: 8]};
    assign stage_im[0][44] = {{12{in_im[111]}}, in_im[104 +: 8]};
    assign stage_re[0][45] = {{12{in_re[367]}}, in_re[360 +: 8]};
    assign stage_im[0][45] = {{12{in_im[367]}}, in_im[360 +: 8]};
    assign stage_re[0][46] = {{12{in_re[239]}}, in_re[232 +: 8]};
    assign stage_im[0][46] = {{12{in_im[239]}}, in_im[232 +: 8]};
    assign stage_re[0][47] = {{12{in_re[495]}}, in_re[488 +: 8]};
    assign stage_im[0][47] = {{12{in_im[495]}}, in_im[488 +: 8]};
    assign stage_re[0][48] = {{12{in_re[31]}}, in_re[24 +: 8]};
    assign stage_im[0][48] = {{12{in_im[31]}}, in_im[24 +: 8]};
    assign stage_re[0][49] = {{12{in_re[287]}}, in_re[280 +: 8]};
    assign stage_im[0][49] = {{12{in_im[287]}}, in_im[280 +: 8]};
    assign stage_re[0][50] = {{12{in_re[159]}}, in_re[152 +: 8]};
    assign stage_im[0][50] = {{12{in_im[159]}}, in_im[152 +: 8]};
    assign stage_re[0][51] = {{12{in_re[415]}}, in_re[408 +: 8]};
    assign stage_im[0][51] = {{12{in_im[415]}}, in_im[408 +: 8]};
    assign stage_re[0][52] = {{12{in_re[95]}}, in_re[88 +: 8]};
    assign stage_im[0][52] = {{12{in_im[95]}}, in_im[88 +: 8]};
    assign stage_re[0][53] = {{12{in_re[351]}}, in_re[344 +: 8]};
    assign stage_im[0][53] = {{12{in_im[351]}}, in_im[344 +: 8]};
    assign stage_re[0][54] = {{12{in_re[223]}}, in_re[216 +: 8]};
    assign stage_im[0][54] = {{12{in_im[223]}}, in_im[216 +: 8]};
    assign stage_re[0][55] = {{12{in_re[479]}}, in_re[472 +: 8]};
    assign stage_im[0][55] = {{12{in_im[479]}}, in_im[472 +: 8]};
    assign stage_re[0][56] = {{12{in_re[63]}}, in_re[56 +: 8]};
    assign stage_im[0][56] = {{12{in_im[63]}}, in_im[56 +: 8]};
    assign stage_re[0][57] = {{12{in_re[319]}}, in_re[312 +: 8]};
    assign stage_im[0][57] = {{12{in_im[319]}}, in_im[312 +: 8]};
    assign stage_re[0][58] = {{12{in_re[191]}}, in_re[184 +: 8]};
    assign stage_im[0][58] = {{12{in_im[191]}}, in_im[184 +: 8]};
    assign stage_re[0][59] = {{12{in_re[447]}}, in_re[440 +: 8]};
    assign stage_im[0][59] = {{12{in_im[447]}}, in_im[440 +: 8]};
    assign stage_re[0][60] = {{12{in_re[127]}}, in_re[120 +: 8]};
    assign stage_im[0][60] = {{12{in_im[127]}}, in_im[120 +: 8]};
    assign stage_re[0][61] = {{12{in_re[383]}}, in_re[376 +: 8]};
    assign stage_im[0][61] = {{12{in_im[383]}}, in_im[376 +: 8]};
    assign stage_re[0][62] = {{12{in_re[255]}}, in_re[248 +: 8]};
    assign stage_im[0][62] = {{12{in_im[255]}}, in_im[248 +: 8]};
    assign stage_re[0][63] = {{12{in_re[511]}}, in_re[504 +: 8]};
    assign stage_im[0][63] = {{12{in_im[511]}}, in_im[504 +: 8]};
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b0_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][0]), .a_im(stage_im[0][0]),
        .b_re(stage_re[0][1]), .b_im(stage_im[0][1]),
        .valid_o(stage_valid[1]),
        .y0_re(stage_re[1][0]), .y0_im(stage_im[1][0]),
        .y1_re(stage_re[1][1]), .y1_im(stage_im[1][1])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b2_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][2]), .a_im(stage_im[0][2]),
        .b_re(stage_re[0][3]), .b_im(stage_im[0][3]),
        .valid_o(),
        .y0_re(stage_re[1][2]), .y0_im(stage_im[1][2]),
        .y1_re(stage_re[1][3]), .y1_im(stage_im[1][3])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b4_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][4]), .a_im(stage_im[0][4]),
        .b_re(stage_re[0][5]), .b_im(stage_im[0][5]),
        .valid_o(),
        .y0_re(stage_re[1][4]), .y0_im(stage_im[1][4]),
        .y1_re(stage_re[1][5]), .y1_im(stage_im[1][5])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b6_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][6]), .a_im(stage_im[0][6]),
        .b_re(stage_re[0][7]), .b_im(stage_im[0][7]),
        .valid_o(),
        .y0_re(stage_re[1][6]), .y0_im(stage_im[1][6]),
        .y1_re(stage_re[1][7]), .y1_im(stage_im[1][7])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b8_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][8]), .a_im(stage_im[0][8]),
        .b_re(stage_re[0][9]), .b_im(stage_im[0][9]),
        .valid_o(),
        .y0_re(stage_re[1][8]), .y0_im(stage_im[1][8]),
        .y1_re(stage_re[1][9]), .y1_im(stage_im[1][9])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b10_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][10]), .a_im(stage_im[0][10]),
        .b_re(stage_re[0][11]), .b_im(stage_im[0][11]),
        .valid_o(),
        .y0_re(stage_re[1][10]), .y0_im(stage_im[1][10]),
        .y1_re(stage_re[1][11]), .y1_im(stage_im[1][11])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b12_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][12]), .a_im(stage_im[0][12]),
        .b_re(stage_re[0][13]), .b_im(stage_im[0][13]),
        .valid_o(),
        .y0_re(stage_re[1][12]), .y0_im(stage_im[1][12]),
        .y1_re(stage_re[1][13]), .y1_im(stage_im[1][13])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b14_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][14]), .a_im(stage_im[0][14]),
        .b_re(stage_re[0][15]), .b_im(stage_im[0][15]),
        .valid_o(),
        .y0_re(stage_re[1][14]), .y0_im(stage_im[1][14]),
        .y1_re(stage_re[1][15]), .y1_im(stage_im[1][15])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b16_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][16]), .a_im(stage_im[0][16]),
        .b_re(stage_re[0][17]), .b_im(stage_im[0][17]),
        .valid_o(),
        .y0_re(stage_re[1][16]), .y0_im(stage_im[1][16]),
        .y1_re(stage_re[1][17]), .y1_im(stage_im[1][17])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b18_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][18]), .a_im(stage_im[0][18]),
        .b_re(stage_re[0][19]), .b_im(stage_im[0][19]),
        .valid_o(),
        .y0_re(stage_re[1][18]), .y0_im(stage_im[1][18]),
        .y1_re(stage_re[1][19]), .y1_im(stage_im[1][19])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b20_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][20]), .a_im(stage_im[0][20]),
        .b_re(stage_re[0][21]), .b_im(stage_im[0][21]),
        .valid_o(),
        .y0_re(stage_re[1][20]), .y0_im(stage_im[1][20]),
        .y1_re(stage_re[1][21]), .y1_im(stage_im[1][21])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b22_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][22]), .a_im(stage_im[0][22]),
        .b_re(stage_re[0][23]), .b_im(stage_im[0][23]),
        .valid_o(),
        .y0_re(stage_re[1][22]), .y0_im(stage_im[1][22]),
        .y1_re(stage_re[1][23]), .y1_im(stage_im[1][23])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b24_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][24]), .a_im(stage_im[0][24]),
        .b_re(stage_re[0][25]), .b_im(stage_im[0][25]),
        .valid_o(),
        .y0_re(stage_re[1][24]), .y0_im(stage_im[1][24]),
        .y1_re(stage_re[1][25]), .y1_im(stage_im[1][25])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b26_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][26]), .a_im(stage_im[0][26]),
        .b_re(stage_re[0][27]), .b_im(stage_im[0][27]),
        .valid_o(),
        .y0_re(stage_re[1][26]), .y0_im(stage_im[1][26]),
        .y1_re(stage_re[1][27]), .y1_im(stage_im[1][27])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b28_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][28]), .a_im(stage_im[0][28]),
        .b_re(stage_re[0][29]), .b_im(stage_im[0][29]),
        .valid_o(),
        .y0_re(stage_re[1][28]), .y0_im(stage_im[1][28]),
        .y1_re(stage_re[1][29]), .y1_im(stage_im[1][29])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b30_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][30]), .a_im(stage_im[0][30]),
        .b_re(stage_re[0][31]), .b_im(stage_im[0][31]),
        .valid_o(),
        .y0_re(stage_re[1][30]), .y0_im(stage_im[1][30]),
        .y1_re(stage_re[1][31]), .y1_im(stage_im[1][31])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b32_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][32]), .a_im(stage_im[0][32]),
        .b_re(stage_re[0][33]), .b_im(stage_im[0][33]),
        .valid_o(),
        .y0_re(stage_re[1][32]), .y0_im(stage_im[1][32]),
        .y1_re(stage_re[1][33]), .y1_im(stage_im[1][33])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b34_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][34]), .a_im(stage_im[0][34]),
        .b_re(stage_re[0][35]), .b_im(stage_im[0][35]),
        .valid_o(),
        .y0_re(stage_re[1][34]), .y0_im(stage_im[1][34]),
        .y1_re(stage_re[1][35]), .y1_im(stage_im[1][35])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b36_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][36]), .a_im(stage_im[0][36]),
        .b_re(stage_re[0][37]), .b_im(stage_im[0][37]),
        .valid_o(),
        .y0_re(stage_re[1][36]), .y0_im(stage_im[1][36]),
        .y1_re(stage_re[1][37]), .y1_im(stage_im[1][37])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b38_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][38]), .a_im(stage_im[0][38]),
        .b_re(stage_re[0][39]), .b_im(stage_im[0][39]),
        .valid_o(),
        .y0_re(stage_re[1][38]), .y0_im(stage_im[1][38]),
        .y1_re(stage_re[1][39]), .y1_im(stage_im[1][39])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b40_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][40]), .a_im(stage_im[0][40]),
        .b_re(stage_re[0][41]), .b_im(stage_im[0][41]),
        .valid_o(),
        .y0_re(stage_re[1][40]), .y0_im(stage_im[1][40]),
        .y1_re(stage_re[1][41]), .y1_im(stage_im[1][41])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b42_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][42]), .a_im(stage_im[0][42]),
        .b_re(stage_re[0][43]), .b_im(stage_im[0][43]),
        .valid_o(),
        .y0_re(stage_re[1][42]), .y0_im(stage_im[1][42]),
        .y1_re(stage_re[1][43]), .y1_im(stage_im[1][43])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b44_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][44]), .a_im(stage_im[0][44]),
        .b_re(stage_re[0][45]), .b_im(stage_im[0][45]),
        .valid_o(),
        .y0_re(stage_re[1][44]), .y0_im(stage_im[1][44]),
        .y1_re(stage_re[1][45]), .y1_im(stage_im[1][45])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b46_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][46]), .a_im(stage_im[0][46]),
        .b_re(stage_re[0][47]), .b_im(stage_im[0][47]),
        .valid_o(),
        .y0_re(stage_re[1][46]), .y0_im(stage_im[1][46]),
        .y1_re(stage_re[1][47]), .y1_im(stage_im[1][47])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b48_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][48]), .a_im(stage_im[0][48]),
        .b_re(stage_re[0][49]), .b_im(stage_im[0][49]),
        .valid_o(),
        .y0_re(stage_re[1][48]), .y0_im(stage_im[1][48]),
        .y1_re(stage_re[1][49]), .y1_im(stage_im[1][49])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b50_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][50]), .a_im(stage_im[0][50]),
        .b_re(stage_re[0][51]), .b_im(stage_im[0][51]),
        .valid_o(),
        .y0_re(stage_re[1][50]), .y0_im(stage_im[1][50]),
        .y1_re(stage_re[1][51]), .y1_im(stage_im[1][51])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b52_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][52]), .a_im(stage_im[0][52]),
        .b_re(stage_re[0][53]), .b_im(stage_im[0][53]),
        .valid_o(),
        .y0_re(stage_re[1][52]), .y0_im(stage_im[1][52]),
        .y1_re(stage_re[1][53]), .y1_im(stage_im[1][53])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b54_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][54]), .a_im(stage_im[0][54]),
        .b_re(stage_re[0][55]), .b_im(stage_im[0][55]),
        .valid_o(),
        .y0_re(stage_re[1][54]), .y0_im(stage_im[1][54]),
        .y1_re(stage_re[1][55]), .y1_im(stage_im[1][55])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b56_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][56]), .a_im(stage_im[0][56]),
        .b_re(stage_re[0][57]), .b_im(stage_im[0][57]),
        .valid_o(),
        .y0_re(stage_re[1][56]), .y0_im(stage_im[1][56]),
        .y1_re(stage_re[1][57]), .y1_im(stage_im[1][57])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b58_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][58]), .a_im(stage_im[0][58]),
        .b_re(stage_re[0][59]), .b_im(stage_im[0][59]),
        .valid_o(),
        .y0_re(stage_re[1][58]), .y0_im(stage_im[1][58]),
        .y1_re(stage_re[1][59]), .y1_im(stage_im[1][59])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b60_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][60]), .a_im(stage_im[0][60]),
        .b_re(stage_re[0][61]), .b_im(stage_im[0][61]),
        .valid_o(),
        .y0_re(stage_re[1][60]), .y0_im(stage_im[1][60]),
        .y1_re(stage_re[1][61]), .y1_im(stage_im[1][61])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s0_b62_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[0]),
        .a_re(stage_re[0][62]), .a_im(stage_im[0][62]),
        .b_re(stage_re[0][63]), .b_im(stage_im[0][63]),
        .valid_o(),
        .y0_re(stage_re[1][62]), .y0_im(stage_im[1][62]),
        .y1_re(stage_re[1][63]), .y1_im(stage_im[1][63])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s1_b0_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][0]), .a_im(stage_im[1][0]),
        .b_re(stage_re[1][2]), .b_im(stage_im[1][2]),
        .valid_o(stage_valid[2]),
        .y0_re(stage_re[2][0]), .y0_im(stage_im[2][0]),
        .y1_re(stage_re[2][2]), .y1_im(stage_im[2][2])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s1_b0_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][1]), .a_im(stage_im[1][1]),
        .b_re(stage_re[1][3]), .b_im(stage_im[1][3]),
        .valid_o(),
        .y0_re(stage_re[2][1]), .y0_im(stage_im[2][1]),
        .y1_re(stage_re[2][3]), .y1_im(stage_im[2][3])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s1_b4_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][4]), .a_im(stage_im[1][4]),
        .b_re(stage_re[1][6]), .b_im(stage_im[1][6]),
        .valid_o(),
        .y0_re(stage_re[2][4]), .y0_im(stage_im[2][4]),
        .y1_re(stage_re[2][6]), .y1_im(stage_im[2][6])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s1_b4_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][5]), .a_im(stage_im[1][5]),
        .b_re(stage_re[1][7]), .b_im(stage_im[1][7]),
        .valid_o(),
        .y0_re(stage_re[2][5]), .y0_im(stage_im[2][5]),
        .y1_re(stage_re[2][7]), .y1_im(stage_im[2][7])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s1_b8_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][8]), .a_im(stage_im[1][8]),
        .b_re(stage_re[1][10]), .b_im(stage_im[1][10]),
        .valid_o(),
        .y0_re(stage_re[2][8]), .y0_im(stage_im[2][8]),
        .y1_re(stage_re[2][10]), .y1_im(stage_im[2][10])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s1_b8_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][9]), .a_im(stage_im[1][9]),
        .b_re(stage_re[1][11]), .b_im(stage_im[1][11]),
        .valid_o(),
        .y0_re(stage_re[2][9]), .y0_im(stage_im[2][9]),
        .y1_re(stage_re[2][11]), .y1_im(stage_im[2][11])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s1_b12_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][12]), .a_im(stage_im[1][12]),
        .b_re(stage_re[1][14]), .b_im(stage_im[1][14]),
        .valid_o(),
        .y0_re(stage_re[2][12]), .y0_im(stage_im[2][12]),
        .y1_re(stage_re[2][14]), .y1_im(stage_im[2][14])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s1_b12_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][13]), .a_im(stage_im[1][13]),
        .b_re(stage_re[1][15]), .b_im(stage_im[1][15]),
        .valid_o(),
        .y0_re(stage_re[2][13]), .y0_im(stage_im[2][13]),
        .y1_re(stage_re[2][15]), .y1_im(stage_im[2][15])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s1_b16_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][16]), .a_im(stage_im[1][16]),
        .b_re(stage_re[1][18]), .b_im(stage_im[1][18]),
        .valid_o(),
        .y0_re(stage_re[2][16]), .y0_im(stage_im[2][16]),
        .y1_re(stage_re[2][18]), .y1_im(stage_im[2][18])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s1_b16_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][17]), .a_im(stage_im[1][17]),
        .b_re(stage_re[1][19]), .b_im(stage_im[1][19]),
        .valid_o(),
        .y0_re(stage_re[2][17]), .y0_im(stage_im[2][17]),
        .y1_re(stage_re[2][19]), .y1_im(stage_im[2][19])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s1_b20_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][20]), .a_im(stage_im[1][20]),
        .b_re(stage_re[1][22]), .b_im(stage_im[1][22]),
        .valid_o(),
        .y0_re(stage_re[2][20]), .y0_im(stage_im[2][20]),
        .y1_re(stage_re[2][22]), .y1_im(stage_im[2][22])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s1_b20_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][21]), .a_im(stage_im[1][21]),
        .b_re(stage_re[1][23]), .b_im(stage_im[1][23]),
        .valid_o(),
        .y0_re(stage_re[2][21]), .y0_im(stage_im[2][21]),
        .y1_re(stage_re[2][23]), .y1_im(stage_im[2][23])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s1_b24_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][24]), .a_im(stage_im[1][24]),
        .b_re(stage_re[1][26]), .b_im(stage_im[1][26]),
        .valid_o(),
        .y0_re(stage_re[2][24]), .y0_im(stage_im[2][24]),
        .y1_re(stage_re[2][26]), .y1_im(stage_im[2][26])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s1_b24_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][25]), .a_im(stage_im[1][25]),
        .b_re(stage_re[1][27]), .b_im(stage_im[1][27]),
        .valid_o(),
        .y0_re(stage_re[2][25]), .y0_im(stage_im[2][25]),
        .y1_re(stage_re[2][27]), .y1_im(stage_im[2][27])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s1_b28_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][28]), .a_im(stage_im[1][28]),
        .b_re(stage_re[1][30]), .b_im(stage_im[1][30]),
        .valid_o(),
        .y0_re(stage_re[2][28]), .y0_im(stage_im[2][28]),
        .y1_re(stage_re[2][30]), .y1_im(stage_im[2][30])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s1_b28_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][29]), .a_im(stage_im[1][29]),
        .b_re(stage_re[1][31]), .b_im(stage_im[1][31]),
        .valid_o(),
        .y0_re(stage_re[2][29]), .y0_im(stage_im[2][29]),
        .y1_re(stage_re[2][31]), .y1_im(stage_im[2][31])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s1_b32_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][32]), .a_im(stage_im[1][32]),
        .b_re(stage_re[1][34]), .b_im(stage_im[1][34]),
        .valid_o(),
        .y0_re(stage_re[2][32]), .y0_im(stage_im[2][32]),
        .y1_re(stage_re[2][34]), .y1_im(stage_im[2][34])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s1_b32_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][33]), .a_im(stage_im[1][33]),
        .b_re(stage_re[1][35]), .b_im(stage_im[1][35]),
        .valid_o(),
        .y0_re(stage_re[2][33]), .y0_im(stage_im[2][33]),
        .y1_re(stage_re[2][35]), .y1_im(stage_im[2][35])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s1_b36_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][36]), .a_im(stage_im[1][36]),
        .b_re(stage_re[1][38]), .b_im(stage_im[1][38]),
        .valid_o(),
        .y0_re(stage_re[2][36]), .y0_im(stage_im[2][36]),
        .y1_re(stage_re[2][38]), .y1_im(stage_im[2][38])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s1_b36_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][37]), .a_im(stage_im[1][37]),
        .b_re(stage_re[1][39]), .b_im(stage_im[1][39]),
        .valid_o(),
        .y0_re(stage_re[2][37]), .y0_im(stage_im[2][37]),
        .y1_re(stage_re[2][39]), .y1_im(stage_im[2][39])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s1_b40_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][40]), .a_im(stage_im[1][40]),
        .b_re(stage_re[1][42]), .b_im(stage_im[1][42]),
        .valid_o(),
        .y0_re(stage_re[2][40]), .y0_im(stage_im[2][40]),
        .y1_re(stage_re[2][42]), .y1_im(stage_im[2][42])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s1_b40_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][41]), .a_im(stage_im[1][41]),
        .b_re(stage_re[1][43]), .b_im(stage_im[1][43]),
        .valid_o(),
        .y0_re(stage_re[2][41]), .y0_im(stage_im[2][41]),
        .y1_re(stage_re[2][43]), .y1_im(stage_im[2][43])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s1_b44_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][44]), .a_im(stage_im[1][44]),
        .b_re(stage_re[1][46]), .b_im(stage_im[1][46]),
        .valid_o(),
        .y0_re(stage_re[2][44]), .y0_im(stage_im[2][44]),
        .y1_re(stage_re[2][46]), .y1_im(stage_im[2][46])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s1_b44_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][45]), .a_im(stage_im[1][45]),
        .b_re(stage_re[1][47]), .b_im(stage_im[1][47]),
        .valid_o(),
        .y0_re(stage_re[2][45]), .y0_im(stage_im[2][45]),
        .y1_re(stage_re[2][47]), .y1_im(stage_im[2][47])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s1_b48_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][48]), .a_im(stage_im[1][48]),
        .b_re(stage_re[1][50]), .b_im(stage_im[1][50]),
        .valid_o(),
        .y0_re(stage_re[2][48]), .y0_im(stage_im[2][48]),
        .y1_re(stage_re[2][50]), .y1_im(stage_im[2][50])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s1_b48_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][49]), .a_im(stage_im[1][49]),
        .b_re(stage_re[1][51]), .b_im(stage_im[1][51]),
        .valid_o(),
        .y0_re(stage_re[2][49]), .y0_im(stage_im[2][49]),
        .y1_re(stage_re[2][51]), .y1_im(stage_im[2][51])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s1_b52_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][52]), .a_im(stage_im[1][52]),
        .b_re(stage_re[1][54]), .b_im(stage_im[1][54]),
        .valid_o(),
        .y0_re(stage_re[2][52]), .y0_im(stage_im[2][52]),
        .y1_re(stage_re[2][54]), .y1_im(stage_im[2][54])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s1_b52_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][53]), .a_im(stage_im[1][53]),
        .b_re(stage_re[1][55]), .b_im(stage_im[1][55]),
        .valid_o(),
        .y0_re(stage_re[2][53]), .y0_im(stage_im[2][53]),
        .y1_re(stage_re[2][55]), .y1_im(stage_im[2][55])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s1_b56_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][56]), .a_im(stage_im[1][56]),
        .b_re(stage_re[1][58]), .b_im(stage_im[1][58]),
        .valid_o(),
        .y0_re(stage_re[2][56]), .y0_im(stage_im[2][56]),
        .y1_re(stage_re[2][58]), .y1_im(stage_im[2][58])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s1_b56_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][57]), .a_im(stage_im[1][57]),
        .b_re(stage_re[1][59]), .b_im(stage_im[1][59]),
        .valid_o(),
        .y0_re(stage_re[2][57]), .y0_im(stage_im[2][57]),
        .y1_re(stage_re[2][59]), .y1_im(stage_im[2][59])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s1_b60_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][60]), .a_im(stage_im[1][60]),
        .b_re(stage_re[1][62]), .b_im(stage_im[1][62]),
        .valid_o(),
        .y0_re(stage_re[2][60]), .y0_im(stage_im[2][60]),
        .y1_re(stage_re[2][62]), .y1_im(stage_im[2][62])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s1_b60_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[1]),
        .a_re(stage_re[1][61]), .a_im(stage_im[1][61]),
        .b_re(stage_re[1][63]), .b_im(stage_im[1][63]),
        .valid_o(),
        .y0_re(stage_re[2][61]), .y0_im(stage_im[2][61]),
        .y1_re(stage_re[2][63]), .y1_im(stage_im[2][63])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s2_b0_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][0]), .a_im(stage_im[2][0]),
        .b_re(stage_re[2][4]), .b_im(stage_im[2][4]),
        .valid_o(stage_valid[3]),
        .y0_re(stage_re[3][0]), .y0_im(stage_im[3][0]),
        .y1_re(stage_re[3][4]), .y1_im(stage_im[3][4])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(23170), .TW_IM(-23170)) u_s2_b0_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][1]), .a_im(stage_im[2][1]),
        .b_re(stage_re[2][5]), .b_im(stage_im[2][5]),
        .valid_o(),
        .y0_re(stage_re[3][1]), .y0_im(stage_im[3][1]),
        .y1_re(stage_re[3][5]), .y1_im(stage_im[3][5])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s2_b0_2 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][2]), .a_im(stage_im[2][2]),
        .b_re(stage_re[2][6]), .b_im(stage_im[2][6]),
        .valid_o(),
        .y0_re(stage_re[3][2]), .y0_im(stage_im[3][2]),
        .y1_re(stage_re[3][6]), .y1_im(stage_im[3][6])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-23170), .TW_IM(-23170)) u_s2_b0_3 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][3]), .a_im(stage_im[2][3]),
        .b_re(stage_re[2][7]), .b_im(stage_im[2][7]),
        .valid_o(),
        .y0_re(stage_re[3][3]), .y0_im(stage_im[3][3]),
        .y1_re(stage_re[3][7]), .y1_im(stage_im[3][7])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s2_b8_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][8]), .a_im(stage_im[2][8]),
        .b_re(stage_re[2][12]), .b_im(stage_im[2][12]),
        .valid_o(),
        .y0_re(stage_re[3][8]), .y0_im(stage_im[3][8]),
        .y1_re(stage_re[3][12]), .y1_im(stage_im[3][12])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(23170), .TW_IM(-23170)) u_s2_b8_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][9]), .a_im(stage_im[2][9]),
        .b_re(stage_re[2][13]), .b_im(stage_im[2][13]),
        .valid_o(),
        .y0_re(stage_re[3][9]), .y0_im(stage_im[3][9]),
        .y1_re(stage_re[3][13]), .y1_im(stage_im[3][13])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s2_b8_2 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][10]), .a_im(stage_im[2][10]),
        .b_re(stage_re[2][14]), .b_im(stage_im[2][14]),
        .valid_o(),
        .y0_re(stage_re[3][10]), .y0_im(stage_im[3][10]),
        .y1_re(stage_re[3][14]), .y1_im(stage_im[3][14])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-23170), .TW_IM(-23170)) u_s2_b8_3 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][11]), .a_im(stage_im[2][11]),
        .b_re(stage_re[2][15]), .b_im(stage_im[2][15]),
        .valid_o(),
        .y0_re(stage_re[3][11]), .y0_im(stage_im[3][11]),
        .y1_re(stage_re[3][15]), .y1_im(stage_im[3][15])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s2_b16_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][16]), .a_im(stage_im[2][16]),
        .b_re(stage_re[2][20]), .b_im(stage_im[2][20]),
        .valid_o(),
        .y0_re(stage_re[3][16]), .y0_im(stage_im[3][16]),
        .y1_re(stage_re[3][20]), .y1_im(stage_im[3][20])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(23170), .TW_IM(-23170)) u_s2_b16_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][17]), .a_im(stage_im[2][17]),
        .b_re(stage_re[2][21]), .b_im(stage_im[2][21]),
        .valid_o(),
        .y0_re(stage_re[3][17]), .y0_im(stage_im[3][17]),
        .y1_re(stage_re[3][21]), .y1_im(stage_im[3][21])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s2_b16_2 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][18]), .a_im(stage_im[2][18]),
        .b_re(stage_re[2][22]), .b_im(stage_im[2][22]),
        .valid_o(),
        .y0_re(stage_re[3][18]), .y0_im(stage_im[3][18]),
        .y1_re(stage_re[3][22]), .y1_im(stage_im[3][22])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-23170), .TW_IM(-23170)) u_s2_b16_3 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][19]), .a_im(stage_im[2][19]),
        .b_re(stage_re[2][23]), .b_im(stage_im[2][23]),
        .valid_o(),
        .y0_re(stage_re[3][19]), .y0_im(stage_im[3][19]),
        .y1_re(stage_re[3][23]), .y1_im(stage_im[3][23])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s2_b24_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][24]), .a_im(stage_im[2][24]),
        .b_re(stage_re[2][28]), .b_im(stage_im[2][28]),
        .valid_o(),
        .y0_re(stage_re[3][24]), .y0_im(stage_im[3][24]),
        .y1_re(stage_re[3][28]), .y1_im(stage_im[3][28])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(23170), .TW_IM(-23170)) u_s2_b24_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][25]), .a_im(stage_im[2][25]),
        .b_re(stage_re[2][29]), .b_im(stage_im[2][29]),
        .valid_o(),
        .y0_re(stage_re[3][25]), .y0_im(stage_im[3][25]),
        .y1_re(stage_re[3][29]), .y1_im(stage_im[3][29])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s2_b24_2 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][26]), .a_im(stage_im[2][26]),
        .b_re(stage_re[2][30]), .b_im(stage_im[2][30]),
        .valid_o(),
        .y0_re(stage_re[3][26]), .y0_im(stage_im[3][26]),
        .y1_re(stage_re[3][30]), .y1_im(stage_im[3][30])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-23170), .TW_IM(-23170)) u_s2_b24_3 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][27]), .a_im(stage_im[2][27]),
        .b_re(stage_re[2][31]), .b_im(stage_im[2][31]),
        .valid_o(),
        .y0_re(stage_re[3][27]), .y0_im(stage_im[3][27]),
        .y1_re(stage_re[3][31]), .y1_im(stage_im[3][31])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s2_b32_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][32]), .a_im(stage_im[2][32]),
        .b_re(stage_re[2][36]), .b_im(stage_im[2][36]),
        .valid_o(),
        .y0_re(stage_re[3][32]), .y0_im(stage_im[3][32]),
        .y1_re(stage_re[3][36]), .y1_im(stage_im[3][36])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(23170), .TW_IM(-23170)) u_s2_b32_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][33]), .a_im(stage_im[2][33]),
        .b_re(stage_re[2][37]), .b_im(stage_im[2][37]),
        .valid_o(),
        .y0_re(stage_re[3][33]), .y0_im(stage_im[3][33]),
        .y1_re(stage_re[3][37]), .y1_im(stage_im[3][37])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s2_b32_2 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][34]), .a_im(stage_im[2][34]),
        .b_re(stage_re[2][38]), .b_im(stage_im[2][38]),
        .valid_o(),
        .y0_re(stage_re[3][34]), .y0_im(stage_im[3][34]),
        .y1_re(stage_re[3][38]), .y1_im(stage_im[3][38])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-23170), .TW_IM(-23170)) u_s2_b32_3 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][35]), .a_im(stage_im[2][35]),
        .b_re(stage_re[2][39]), .b_im(stage_im[2][39]),
        .valid_o(),
        .y0_re(stage_re[3][35]), .y0_im(stage_im[3][35]),
        .y1_re(stage_re[3][39]), .y1_im(stage_im[3][39])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s2_b40_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][40]), .a_im(stage_im[2][40]),
        .b_re(stage_re[2][44]), .b_im(stage_im[2][44]),
        .valid_o(),
        .y0_re(stage_re[3][40]), .y0_im(stage_im[3][40]),
        .y1_re(stage_re[3][44]), .y1_im(stage_im[3][44])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(23170), .TW_IM(-23170)) u_s2_b40_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][41]), .a_im(stage_im[2][41]),
        .b_re(stage_re[2][45]), .b_im(stage_im[2][45]),
        .valid_o(),
        .y0_re(stage_re[3][41]), .y0_im(stage_im[3][41]),
        .y1_re(stage_re[3][45]), .y1_im(stage_im[3][45])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s2_b40_2 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][42]), .a_im(stage_im[2][42]),
        .b_re(stage_re[2][46]), .b_im(stage_im[2][46]),
        .valid_o(),
        .y0_re(stage_re[3][42]), .y0_im(stage_im[3][42]),
        .y1_re(stage_re[3][46]), .y1_im(stage_im[3][46])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-23170), .TW_IM(-23170)) u_s2_b40_3 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][43]), .a_im(stage_im[2][43]),
        .b_re(stage_re[2][47]), .b_im(stage_im[2][47]),
        .valid_o(),
        .y0_re(stage_re[3][43]), .y0_im(stage_im[3][43]),
        .y1_re(stage_re[3][47]), .y1_im(stage_im[3][47])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s2_b48_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][48]), .a_im(stage_im[2][48]),
        .b_re(stage_re[2][52]), .b_im(stage_im[2][52]),
        .valid_o(),
        .y0_re(stage_re[3][48]), .y0_im(stage_im[3][48]),
        .y1_re(stage_re[3][52]), .y1_im(stage_im[3][52])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(23170), .TW_IM(-23170)) u_s2_b48_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][49]), .a_im(stage_im[2][49]),
        .b_re(stage_re[2][53]), .b_im(stage_im[2][53]),
        .valid_o(),
        .y0_re(stage_re[3][49]), .y0_im(stage_im[3][49]),
        .y1_re(stage_re[3][53]), .y1_im(stage_im[3][53])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s2_b48_2 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][50]), .a_im(stage_im[2][50]),
        .b_re(stage_re[2][54]), .b_im(stage_im[2][54]),
        .valid_o(),
        .y0_re(stage_re[3][50]), .y0_im(stage_im[3][50]),
        .y1_re(stage_re[3][54]), .y1_im(stage_im[3][54])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-23170), .TW_IM(-23170)) u_s2_b48_3 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][51]), .a_im(stage_im[2][51]),
        .b_re(stage_re[2][55]), .b_im(stage_im[2][55]),
        .valid_o(),
        .y0_re(stage_re[3][51]), .y0_im(stage_im[3][51]),
        .y1_re(stage_re[3][55]), .y1_im(stage_im[3][55])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s2_b56_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][56]), .a_im(stage_im[2][56]),
        .b_re(stage_re[2][60]), .b_im(stage_im[2][60]),
        .valid_o(),
        .y0_re(stage_re[3][56]), .y0_im(stage_im[3][56]),
        .y1_re(stage_re[3][60]), .y1_im(stage_im[3][60])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(23170), .TW_IM(-23170)) u_s2_b56_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][57]), .a_im(stage_im[2][57]),
        .b_re(stage_re[2][61]), .b_im(stage_im[2][61]),
        .valid_o(),
        .y0_re(stage_re[3][57]), .y0_im(stage_im[3][57]),
        .y1_re(stage_re[3][61]), .y1_im(stage_im[3][61])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s2_b56_2 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][58]), .a_im(stage_im[2][58]),
        .b_re(stage_re[2][62]), .b_im(stage_im[2][62]),
        .valid_o(),
        .y0_re(stage_re[3][58]), .y0_im(stage_im[3][58]),
        .y1_re(stage_re[3][62]), .y1_im(stage_im[3][62])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-23170), .TW_IM(-23170)) u_s2_b56_3 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[2]),
        .a_re(stage_re[2][59]), .a_im(stage_im[2][59]),
        .b_re(stage_re[2][63]), .b_im(stage_im[2][63]),
        .valid_o(),
        .y0_re(stage_re[3][59]), .y0_im(stage_im[3][59]),
        .y1_re(stage_re[3][63]), .y1_im(stage_im[3][63])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s3_b0_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][0]), .a_im(stage_im[3][0]),
        .b_re(stage_re[3][8]), .b_im(stage_im[3][8]),
        .valid_o(stage_valid[4]),
        .y0_re(stage_re[4][0]), .y0_im(stage_im[4][0]),
        .y1_re(stage_re[4][8]), .y1_im(stage_im[4][8])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(30273), .TW_IM(-12539)) u_s3_b0_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][1]), .a_im(stage_im[3][1]),
        .b_re(stage_re[3][9]), .b_im(stage_im[3][9]),
        .valid_o(),
        .y0_re(stage_re[4][1]), .y0_im(stage_im[4][1]),
        .y1_re(stage_re[4][9]), .y1_im(stage_im[4][9])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(23170), .TW_IM(-23170)) u_s3_b0_2 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][2]), .a_im(stage_im[3][2]),
        .b_re(stage_re[3][10]), .b_im(stage_im[3][10]),
        .valid_o(),
        .y0_re(stage_re[4][2]), .y0_im(stage_im[4][2]),
        .y1_re(stage_re[4][10]), .y1_im(stage_im[4][10])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(12539), .TW_IM(-30273)) u_s3_b0_3 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][3]), .a_im(stage_im[3][3]),
        .b_re(stage_re[3][11]), .b_im(stage_im[3][11]),
        .valid_o(),
        .y0_re(stage_re[4][3]), .y0_im(stage_im[4][3]),
        .y1_re(stage_re[4][11]), .y1_im(stage_im[4][11])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s3_b0_4 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][4]), .a_im(stage_im[3][4]),
        .b_re(stage_re[3][12]), .b_im(stage_im[3][12]),
        .valid_o(),
        .y0_re(stage_re[4][4]), .y0_im(stage_im[4][4]),
        .y1_re(stage_re[4][12]), .y1_im(stage_im[4][12])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-12539), .TW_IM(-30273)) u_s3_b0_5 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][5]), .a_im(stage_im[3][5]),
        .b_re(stage_re[3][13]), .b_im(stage_im[3][13]),
        .valid_o(),
        .y0_re(stage_re[4][5]), .y0_im(stage_im[4][5]),
        .y1_re(stage_re[4][13]), .y1_im(stage_im[4][13])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-23170), .TW_IM(-23170)) u_s3_b0_6 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][6]), .a_im(stage_im[3][6]),
        .b_re(stage_re[3][14]), .b_im(stage_im[3][14]),
        .valid_o(),
        .y0_re(stage_re[4][6]), .y0_im(stage_im[4][6]),
        .y1_re(stage_re[4][14]), .y1_im(stage_im[4][14])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-30273), .TW_IM(-12539)) u_s3_b0_7 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][7]), .a_im(stage_im[3][7]),
        .b_re(stage_re[3][15]), .b_im(stage_im[3][15]),
        .valid_o(),
        .y0_re(stage_re[4][7]), .y0_im(stage_im[4][7]),
        .y1_re(stage_re[4][15]), .y1_im(stage_im[4][15])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s3_b16_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][16]), .a_im(stage_im[3][16]),
        .b_re(stage_re[3][24]), .b_im(stage_im[3][24]),
        .valid_o(),
        .y0_re(stage_re[4][16]), .y0_im(stage_im[4][16]),
        .y1_re(stage_re[4][24]), .y1_im(stage_im[4][24])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(30273), .TW_IM(-12539)) u_s3_b16_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][17]), .a_im(stage_im[3][17]),
        .b_re(stage_re[3][25]), .b_im(stage_im[3][25]),
        .valid_o(),
        .y0_re(stage_re[4][17]), .y0_im(stage_im[4][17]),
        .y1_re(stage_re[4][25]), .y1_im(stage_im[4][25])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(23170), .TW_IM(-23170)) u_s3_b16_2 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][18]), .a_im(stage_im[3][18]),
        .b_re(stage_re[3][26]), .b_im(stage_im[3][26]),
        .valid_o(),
        .y0_re(stage_re[4][18]), .y0_im(stage_im[4][18]),
        .y1_re(stage_re[4][26]), .y1_im(stage_im[4][26])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(12539), .TW_IM(-30273)) u_s3_b16_3 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][19]), .a_im(stage_im[3][19]),
        .b_re(stage_re[3][27]), .b_im(stage_im[3][27]),
        .valid_o(),
        .y0_re(stage_re[4][19]), .y0_im(stage_im[4][19]),
        .y1_re(stage_re[4][27]), .y1_im(stage_im[4][27])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s3_b16_4 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][20]), .a_im(stage_im[3][20]),
        .b_re(stage_re[3][28]), .b_im(stage_im[3][28]),
        .valid_o(),
        .y0_re(stage_re[4][20]), .y0_im(stage_im[4][20]),
        .y1_re(stage_re[4][28]), .y1_im(stage_im[4][28])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-12539), .TW_IM(-30273)) u_s3_b16_5 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][21]), .a_im(stage_im[3][21]),
        .b_re(stage_re[3][29]), .b_im(stage_im[3][29]),
        .valid_o(),
        .y0_re(stage_re[4][21]), .y0_im(stage_im[4][21]),
        .y1_re(stage_re[4][29]), .y1_im(stage_im[4][29])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-23170), .TW_IM(-23170)) u_s3_b16_6 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][22]), .a_im(stage_im[3][22]),
        .b_re(stage_re[3][30]), .b_im(stage_im[3][30]),
        .valid_o(),
        .y0_re(stage_re[4][22]), .y0_im(stage_im[4][22]),
        .y1_re(stage_re[4][30]), .y1_im(stage_im[4][30])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-30273), .TW_IM(-12539)) u_s3_b16_7 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][23]), .a_im(stage_im[3][23]),
        .b_re(stage_re[3][31]), .b_im(stage_im[3][31]),
        .valid_o(),
        .y0_re(stage_re[4][23]), .y0_im(stage_im[4][23]),
        .y1_re(stage_re[4][31]), .y1_im(stage_im[4][31])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s3_b32_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][32]), .a_im(stage_im[3][32]),
        .b_re(stage_re[3][40]), .b_im(stage_im[3][40]),
        .valid_o(),
        .y0_re(stage_re[4][32]), .y0_im(stage_im[4][32]),
        .y1_re(stage_re[4][40]), .y1_im(stage_im[4][40])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(30273), .TW_IM(-12539)) u_s3_b32_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][33]), .a_im(stage_im[3][33]),
        .b_re(stage_re[3][41]), .b_im(stage_im[3][41]),
        .valid_o(),
        .y0_re(stage_re[4][33]), .y0_im(stage_im[4][33]),
        .y1_re(stage_re[4][41]), .y1_im(stage_im[4][41])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(23170), .TW_IM(-23170)) u_s3_b32_2 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][34]), .a_im(stage_im[3][34]),
        .b_re(stage_re[3][42]), .b_im(stage_im[3][42]),
        .valid_o(),
        .y0_re(stage_re[4][34]), .y0_im(stage_im[4][34]),
        .y1_re(stage_re[4][42]), .y1_im(stage_im[4][42])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(12539), .TW_IM(-30273)) u_s3_b32_3 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][35]), .a_im(stage_im[3][35]),
        .b_re(stage_re[3][43]), .b_im(stage_im[3][43]),
        .valid_o(),
        .y0_re(stage_re[4][35]), .y0_im(stage_im[4][35]),
        .y1_re(stage_re[4][43]), .y1_im(stage_im[4][43])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s3_b32_4 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][36]), .a_im(stage_im[3][36]),
        .b_re(stage_re[3][44]), .b_im(stage_im[3][44]),
        .valid_o(),
        .y0_re(stage_re[4][36]), .y0_im(stage_im[4][36]),
        .y1_re(stage_re[4][44]), .y1_im(stage_im[4][44])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-12539), .TW_IM(-30273)) u_s3_b32_5 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][37]), .a_im(stage_im[3][37]),
        .b_re(stage_re[3][45]), .b_im(stage_im[3][45]),
        .valid_o(),
        .y0_re(stage_re[4][37]), .y0_im(stage_im[4][37]),
        .y1_re(stage_re[4][45]), .y1_im(stage_im[4][45])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-23170), .TW_IM(-23170)) u_s3_b32_6 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][38]), .a_im(stage_im[3][38]),
        .b_re(stage_re[3][46]), .b_im(stage_im[3][46]),
        .valid_o(),
        .y0_re(stage_re[4][38]), .y0_im(stage_im[4][38]),
        .y1_re(stage_re[4][46]), .y1_im(stage_im[4][46])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-30273), .TW_IM(-12539)) u_s3_b32_7 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][39]), .a_im(stage_im[3][39]),
        .b_re(stage_re[3][47]), .b_im(stage_im[3][47]),
        .valid_o(),
        .y0_re(stage_re[4][39]), .y0_im(stage_im[4][39]),
        .y1_re(stage_re[4][47]), .y1_im(stage_im[4][47])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s3_b48_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][48]), .a_im(stage_im[3][48]),
        .b_re(stage_re[3][56]), .b_im(stage_im[3][56]),
        .valid_o(),
        .y0_re(stage_re[4][48]), .y0_im(stage_im[4][48]),
        .y1_re(stage_re[4][56]), .y1_im(stage_im[4][56])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(30273), .TW_IM(-12539)) u_s3_b48_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][49]), .a_im(stage_im[3][49]),
        .b_re(stage_re[3][57]), .b_im(stage_im[3][57]),
        .valid_o(),
        .y0_re(stage_re[4][49]), .y0_im(stage_im[4][49]),
        .y1_re(stage_re[4][57]), .y1_im(stage_im[4][57])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(23170), .TW_IM(-23170)) u_s3_b48_2 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][50]), .a_im(stage_im[3][50]),
        .b_re(stage_re[3][58]), .b_im(stage_im[3][58]),
        .valid_o(),
        .y0_re(stage_re[4][50]), .y0_im(stage_im[4][50]),
        .y1_re(stage_re[4][58]), .y1_im(stage_im[4][58])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(12539), .TW_IM(-30273)) u_s3_b48_3 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][51]), .a_im(stage_im[3][51]),
        .b_re(stage_re[3][59]), .b_im(stage_im[3][59]),
        .valid_o(),
        .y0_re(stage_re[4][51]), .y0_im(stage_im[4][51]),
        .y1_re(stage_re[4][59]), .y1_im(stage_im[4][59])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s3_b48_4 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][52]), .a_im(stage_im[3][52]),
        .b_re(stage_re[3][60]), .b_im(stage_im[3][60]),
        .valid_o(),
        .y0_re(stage_re[4][52]), .y0_im(stage_im[4][52]),
        .y1_re(stage_re[4][60]), .y1_im(stage_im[4][60])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-12539), .TW_IM(-30273)) u_s3_b48_5 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][53]), .a_im(stage_im[3][53]),
        .b_re(stage_re[3][61]), .b_im(stage_im[3][61]),
        .valid_o(),
        .y0_re(stage_re[4][53]), .y0_im(stage_im[4][53]),
        .y1_re(stage_re[4][61]), .y1_im(stage_im[4][61])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-23170), .TW_IM(-23170)) u_s3_b48_6 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][54]), .a_im(stage_im[3][54]),
        .b_re(stage_re[3][62]), .b_im(stage_im[3][62]),
        .valid_o(),
        .y0_re(stage_re[4][54]), .y0_im(stage_im[4][54]),
        .y1_re(stage_re[4][62]), .y1_im(stage_im[4][62])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-30273), .TW_IM(-12539)) u_s3_b48_7 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[3]),
        .a_re(stage_re[3][55]), .a_im(stage_im[3][55]),
        .b_re(stage_re[3][63]), .b_im(stage_im[3][63]),
        .valid_o(),
        .y0_re(stage_re[4][55]), .y0_im(stage_im[4][55]),
        .y1_re(stage_re[4][63]), .y1_im(stage_im[4][63])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s4_b0_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][0]), .a_im(stage_im[4][0]),
        .b_re(stage_re[4][16]), .b_im(stage_im[4][16]),
        .valid_o(stage_valid[5]),
        .y0_re(stage_re[5][0]), .y0_im(stage_im[5][0]),
        .y1_re(stage_re[5][16]), .y1_im(stage_im[5][16])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32137), .TW_IM(-6393)) u_s4_b0_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][1]), .a_im(stage_im[4][1]),
        .b_re(stage_re[4][17]), .b_im(stage_im[4][17]),
        .valid_o(),
        .y0_re(stage_re[5][1]), .y0_im(stage_im[5][1]),
        .y1_re(stage_re[5][17]), .y1_im(stage_im[5][17])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(30273), .TW_IM(-12539)) u_s4_b0_2 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][2]), .a_im(stage_im[4][2]),
        .b_re(stage_re[4][18]), .b_im(stage_im[4][18]),
        .valid_o(),
        .y0_re(stage_re[5][2]), .y0_im(stage_im[5][2]),
        .y1_re(stage_re[5][18]), .y1_im(stage_im[5][18])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(27245), .TW_IM(-18204)) u_s4_b0_3 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][3]), .a_im(stage_im[4][3]),
        .b_re(stage_re[4][19]), .b_im(stage_im[4][19]),
        .valid_o(),
        .y0_re(stage_re[5][3]), .y0_im(stage_im[5][3]),
        .y1_re(stage_re[5][19]), .y1_im(stage_im[5][19])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(23170), .TW_IM(-23170)) u_s4_b0_4 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][4]), .a_im(stage_im[4][4]),
        .b_re(stage_re[4][20]), .b_im(stage_im[4][20]),
        .valid_o(),
        .y0_re(stage_re[5][4]), .y0_im(stage_im[5][4]),
        .y1_re(stage_re[5][20]), .y1_im(stage_im[5][20])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(18204), .TW_IM(-27245)) u_s4_b0_5 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][5]), .a_im(stage_im[4][5]),
        .b_re(stage_re[4][21]), .b_im(stage_im[4][21]),
        .valid_o(),
        .y0_re(stage_re[5][5]), .y0_im(stage_im[5][5]),
        .y1_re(stage_re[5][21]), .y1_im(stage_im[5][21])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(12539), .TW_IM(-30273)) u_s4_b0_6 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][6]), .a_im(stage_im[4][6]),
        .b_re(stage_re[4][22]), .b_im(stage_im[4][22]),
        .valid_o(),
        .y0_re(stage_re[5][6]), .y0_im(stage_im[5][6]),
        .y1_re(stage_re[5][22]), .y1_im(stage_im[5][22])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(6393), .TW_IM(-32137)) u_s4_b0_7 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][7]), .a_im(stage_im[4][7]),
        .b_re(stage_re[4][23]), .b_im(stage_im[4][23]),
        .valid_o(),
        .y0_re(stage_re[5][7]), .y0_im(stage_im[5][7]),
        .y1_re(stage_re[5][23]), .y1_im(stage_im[5][23])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s4_b0_8 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][8]), .a_im(stage_im[4][8]),
        .b_re(stage_re[4][24]), .b_im(stage_im[4][24]),
        .valid_o(),
        .y0_re(stage_re[5][8]), .y0_im(stage_im[5][8]),
        .y1_re(stage_re[5][24]), .y1_im(stage_im[5][24])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-6393), .TW_IM(-32137)) u_s4_b0_9 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][9]), .a_im(stage_im[4][9]),
        .b_re(stage_re[4][25]), .b_im(stage_im[4][25]),
        .valid_o(),
        .y0_re(stage_re[5][9]), .y0_im(stage_im[5][9]),
        .y1_re(stage_re[5][25]), .y1_im(stage_im[5][25])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-12539), .TW_IM(-30273)) u_s4_b0_10 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][10]), .a_im(stage_im[4][10]),
        .b_re(stage_re[4][26]), .b_im(stage_im[4][26]),
        .valid_o(),
        .y0_re(stage_re[5][10]), .y0_im(stage_im[5][10]),
        .y1_re(stage_re[5][26]), .y1_im(stage_im[5][26])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-18204), .TW_IM(-27245)) u_s4_b0_11 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][11]), .a_im(stage_im[4][11]),
        .b_re(stage_re[4][27]), .b_im(stage_im[4][27]),
        .valid_o(),
        .y0_re(stage_re[5][11]), .y0_im(stage_im[5][11]),
        .y1_re(stage_re[5][27]), .y1_im(stage_im[5][27])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-23170), .TW_IM(-23170)) u_s4_b0_12 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][12]), .a_im(stage_im[4][12]),
        .b_re(stage_re[4][28]), .b_im(stage_im[4][28]),
        .valid_o(),
        .y0_re(stage_re[5][12]), .y0_im(stage_im[5][12]),
        .y1_re(stage_re[5][28]), .y1_im(stage_im[5][28])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-27245), .TW_IM(-18204)) u_s4_b0_13 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][13]), .a_im(stage_im[4][13]),
        .b_re(stage_re[4][29]), .b_im(stage_im[4][29]),
        .valid_o(),
        .y0_re(stage_re[5][13]), .y0_im(stage_im[5][13]),
        .y1_re(stage_re[5][29]), .y1_im(stage_im[5][29])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-30273), .TW_IM(-12539)) u_s4_b0_14 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][14]), .a_im(stage_im[4][14]),
        .b_re(stage_re[4][30]), .b_im(stage_im[4][30]),
        .valid_o(),
        .y0_re(stage_re[5][14]), .y0_im(stage_im[5][14]),
        .y1_re(stage_re[5][30]), .y1_im(stage_im[5][30])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-32137), .TW_IM(-6393)) u_s4_b0_15 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][15]), .a_im(stage_im[4][15]),
        .b_re(stage_re[4][31]), .b_im(stage_im[4][31]),
        .valid_o(),
        .y0_re(stage_re[5][15]), .y0_im(stage_im[5][15]),
        .y1_re(stage_re[5][31]), .y1_im(stage_im[5][31])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s4_b32_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][32]), .a_im(stage_im[4][32]),
        .b_re(stage_re[4][48]), .b_im(stage_im[4][48]),
        .valid_o(),
        .y0_re(stage_re[5][32]), .y0_im(stage_im[5][32]),
        .y1_re(stage_re[5][48]), .y1_im(stage_im[5][48])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32137), .TW_IM(-6393)) u_s4_b32_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][33]), .a_im(stage_im[4][33]),
        .b_re(stage_re[4][49]), .b_im(stage_im[4][49]),
        .valid_o(),
        .y0_re(stage_re[5][33]), .y0_im(stage_im[5][33]),
        .y1_re(stage_re[5][49]), .y1_im(stage_im[5][49])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(30273), .TW_IM(-12539)) u_s4_b32_2 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][34]), .a_im(stage_im[4][34]),
        .b_re(stage_re[4][50]), .b_im(stage_im[4][50]),
        .valid_o(),
        .y0_re(stage_re[5][34]), .y0_im(stage_im[5][34]),
        .y1_re(stage_re[5][50]), .y1_im(stage_im[5][50])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(27245), .TW_IM(-18204)) u_s4_b32_3 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][35]), .a_im(stage_im[4][35]),
        .b_re(stage_re[4][51]), .b_im(stage_im[4][51]),
        .valid_o(),
        .y0_re(stage_re[5][35]), .y0_im(stage_im[5][35]),
        .y1_re(stage_re[5][51]), .y1_im(stage_im[5][51])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(23170), .TW_IM(-23170)) u_s4_b32_4 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][36]), .a_im(stage_im[4][36]),
        .b_re(stage_re[4][52]), .b_im(stage_im[4][52]),
        .valid_o(),
        .y0_re(stage_re[5][36]), .y0_im(stage_im[5][36]),
        .y1_re(stage_re[5][52]), .y1_im(stage_im[5][52])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(18204), .TW_IM(-27245)) u_s4_b32_5 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][37]), .a_im(stage_im[4][37]),
        .b_re(stage_re[4][53]), .b_im(stage_im[4][53]),
        .valid_o(),
        .y0_re(stage_re[5][37]), .y0_im(stage_im[5][37]),
        .y1_re(stage_re[5][53]), .y1_im(stage_im[5][53])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(12539), .TW_IM(-30273)) u_s4_b32_6 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][38]), .a_im(stage_im[4][38]),
        .b_re(stage_re[4][54]), .b_im(stage_im[4][54]),
        .valid_o(),
        .y0_re(stage_re[5][38]), .y0_im(stage_im[5][38]),
        .y1_re(stage_re[5][54]), .y1_im(stage_im[5][54])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(6393), .TW_IM(-32137)) u_s4_b32_7 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][39]), .a_im(stage_im[4][39]),
        .b_re(stage_re[4][55]), .b_im(stage_im[4][55]),
        .valid_o(),
        .y0_re(stage_re[5][39]), .y0_im(stage_im[5][39]),
        .y1_re(stage_re[5][55]), .y1_im(stage_im[5][55])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s4_b32_8 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][40]), .a_im(stage_im[4][40]),
        .b_re(stage_re[4][56]), .b_im(stage_im[4][56]),
        .valid_o(),
        .y0_re(stage_re[5][40]), .y0_im(stage_im[5][40]),
        .y1_re(stage_re[5][56]), .y1_im(stage_im[5][56])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-6393), .TW_IM(-32137)) u_s4_b32_9 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][41]), .a_im(stage_im[4][41]),
        .b_re(stage_re[4][57]), .b_im(stage_im[4][57]),
        .valid_o(),
        .y0_re(stage_re[5][41]), .y0_im(stage_im[5][41]),
        .y1_re(stage_re[5][57]), .y1_im(stage_im[5][57])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-12539), .TW_IM(-30273)) u_s4_b32_10 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][42]), .a_im(stage_im[4][42]),
        .b_re(stage_re[4][58]), .b_im(stage_im[4][58]),
        .valid_o(),
        .y0_re(stage_re[5][42]), .y0_im(stage_im[5][42]),
        .y1_re(stage_re[5][58]), .y1_im(stage_im[5][58])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-18204), .TW_IM(-27245)) u_s4_b32_11 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][43]), .a_im(stage_im[4][43]),
        .b_re(stage_re[4][59]), .b_im(stage_im[4][59]),
        .valid_o(),
        .y0_re(stage_re[5][43]), .y0_im(stage_im[5][43]),
        .y1_re(stage_re[5][59]), .y1_im(stage_im[5][59])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-23170), .TW_IM(-23170)) u_s4_b32_12 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][44]), .a_im(stage_im[4][44]),
        .b_re(stage_re[4][60]), .b_im(stage_im[4][60]),
        .valid_o(),
        .y0_re(stage_re[5][44]), .y0_im(stage_im[5][44]),
        .y1_re(stage_re[5][60]), .y1_im(stage_im[5][60])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-27245), .TW_IM(-18204)) u_s4_b32_13 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][45]), .a_im(stage_im[4][45]),
        .b_re(stage_re[4][61]), .b_im(stage_im[4][61]),
        .valid_o(),
        .y0_re(stage_re[5][45]), .y0_im(stage_im[5][45]),
        .y1_re(stage_re[5][61]), .y1_im(stage_im[5][61])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-30273), .TW_IM(-12539)) u_s4_b32_14 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][46]), .a_im(stage_im[4][46]),
        .b_re(stage_re[4][62]), .b_im(stage_im[4][62]),
        .valid_o(),
        .y0_re(stage_re[5][46]), .y0_im(stage_im[5][46]),
        .y1_re(stage_re[5][62]), .y1_im(stage_im[5][62])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-32137), .TW_IM(-6393)) u_s4_b32_15 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[4]),
        .a_re(stage_re[4][47]), .a_im(stage_im[4][47]),
        .b_re(stage_re[4][63]), .b_im(stage_im[4][63]),
        .valid_o(),
        .y0_re(stage_re[5][47]), .y0_im(stage_im[5][47]),
        .y1_re(stage_re[5][63]), .y1_im(stage_im[5][63])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32767), .TW_IM(0)) u_s5_b0_0 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][0]), .a_im(stage_im[5][0]),
        .b_re(stage_re[5][32]), .b_im(stage_im[5][32]),
        .valid_o(stage_valid[6]),
        .y0_re(stage_re[6][0]), .y0_im(stage_im[6][0]),
        .y1_re(stage_re[6][32]), .y1_im(stage_im[6][32])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32609), .TW_IM(-3212)) u_s5_b0_1 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][1]), .a_im(stage_im[5][1]),
        .b_re(stage_re[5][33]), .b_im(stage_im[5][33]),
        .valid_o(),
        .y0_re(stage_re[6][1]), .y0_im(stage_im[6][1]),
        .y1_re(stage_re[6][33]), .y1_im(stage_im[6][33])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(32137), .TW_IM(-6393)) u_s5_b0_2 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][2]), .a_im(stage_im[5][2]),
        .b_re(stage_re[5][34]), .b_im(stage_im[5][34]),
        .valid_o(),
        .y0_re(stage_re[6][2]), .y0_im(stage_im[6][2]),
        .y1_re(stage_re[6][34]), .y1_im(stage_im[6][34])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(31356), .TW_IM(-9512)) u_s5_b0_3 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][3]), .a_im(stage_im[5][3]),
        .b_re(stage_re[5][35]), .b_im(stage_im[5][35]),
        .valid_o(),
        .y0_re(stage_re[6][3]), .y0_im(stage_im[6][3]),
        .y1_re(stage_re[6][35]), .y1_im(stage_im[6][35])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(30273), .TW_IM(-12539)) u_s5_b0_4 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][4]), .a_im(stage_im[5][4]),
        .b_re(stage_re[5][36]), .b_im(stage_im[5][36]),
        .valid_o(),
        .y0_re(stage_re[6][4]), .y0_im(stage_im[6][4]),
        .y1_re(stage_re[6][36]), .y1_im(stage_im[6][36])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(28898), .TW_IM(-15446)) u_s5_b0_5 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][5]), .a_im(stage_im[5][5]),
        .b_re(stage_re[5][37]), .b_im(stage_im[5][37]),
        .valid_o(),
        .y0_re(stage_re[6][5]), .y0_im(stage_im[6][5]),
        .y1_re(stage_re[6][37]), .y1_im(stage_im[6][37])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(27245), .TW_IM(-18204)) u_s5_b0_6 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][6]), .a_im(stage_im[5][6]),
        .b_re(stage_re[5][38]), .b_im(stage_im[5][38]),
        .valid_o(),
        .y0_re(stage_re[6][6]), .y0_im(stage_im[6][6]),
        .y1_re(stage_re[6][38]), .y1_im(stage_im[6][38])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(25329), .TW_IM(-20787)) u_s5_b0_7 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][7]), .a_im(stage_im[5][7]),
        .b_re(stage_re[5][39]), .b_im(stage_im[5][39]),
        .valid_o(),
        .y0_re(stage_re[6][7]), .y0_im(stage_im[6][7]),
        .y1_re(stage_re[6][39]), .y1_im(stage_im[6][39])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(23170), .TW_IM(-23170)) u_s5_b0_8 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][8]), .a_im(stage_im[5][8]),
        .b_re(stage_re[5][40]), .b_im(stage_im[5][40]),
        .valid_o(),
        .y0_re(stage_re[6][8]), .y0_im(stage_im[6][8]),
        .y1_re(stage_re[6][40]), .y1_im(stage_im[6][40])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(20787), .TW_IM(-25329)) u_s5_b0_9 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][9]), .a_im(stage_im[5][9]),
        .b_re(stage_re[5][41]), .b_im(stage_im[5][41]),
        .valid_o(),
        .y0_re(stage_re[6][9]), .y0_im(stage_im[6][9]),
        .y1_re(stage_re[6][41]), .y1_im(stage_im[6][41])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(18204), .TW_IM(-27245)) u_s5_b0_10 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][10]), .a_im(stage_im[5][10]),
        .b_re(stage_re[5][42]), .b_im(stage_im[5][42]),
        .valid_o(),
        .y0_re(stage_re[6][10]), .y0_im(stage_im[6][10]),
        .y1_re(stage_re[6][42]), .y1_im(stage_im[6][42])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(15446), .TW_IM(-28898)) u_s5_b0_11 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][11]), .a_im(stage_im[5][11]),
        .b_re(stage_re[5][43]), .b_im(stage_im[5][43]),
        .valid_o(),
        .y0_re(stage_re[6][11]), .y0_im(stage_im[6][11]),
        .y1_re(stage_re[6][43]), .y1_im(stage_im[6][43])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(12539), .TW_IM(-30273)) u_s5_b0_12 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][12]), .a_im(stage_im[5][12]),
        .b_re(stage_re[5][44]), .b_im(stage_im[5][44]),
        .valid_o(),
        .y0_re(stage_re[6][12]), .y0_im(stage_im[6][12]),
        .y1_re(stage_re[6][44]), .y1_im(stage_im[6][44])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(9512), .TW_IM(-31356)) u_s5_b0_13 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][13]), .a_im(stage_im[5][13]),
        .b_re(stage_re[5][45]), .b_im(stage_im[5][45]),
        .valid_o(),
        .y0_re(stage_re[6][13]), .y0_im(stage_im[6][13]),
        .y1_re(stage_re[6][45]), .y1_im(stage_im[6][45])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(6393), .TW_IM(-32137)) u_s5_b0_14 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][14]), .a_im(stage_im[5][14]),
        .b_re(stage_re[5][46]), .b_im(stage_im[5][46]),
        .valid_o(),
        .y0_re(stage_re[6][14]), .y0_im(stage_im[6][14]),
        .y1_re(stage_re[6][46]), .y1_im(stage_im[6][46])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(3212), .TW_IM(-32609)) u_s5_b0_15 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][15]), .a_im(stage_im[5][15]),
        .b_re(stage_re[5][47]), .b_im(stage_im[5][47]),
        .valid_o(),
        .y0_re(stage_re[6][15]), .y0_im(stage_im[6][15]),
        .y1_re(stage_re[6][47]), .y1_im(stage_im[6][47])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(0), .TW_IM(-32767)) u_s5_b0_16 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][16]), .a_im(stage_im[5][16]),
        .b_re(stage_re[5][48]), .b_im(stage_im[5][48]),
        .valid_o(),
        .y0_re(stage_re[6][16]), .y0_im(stage_im[6][16]),
        .y1_re(stage_re[6][48]), .y1_im(stage_im[6][48])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-3212), .TW_IM(-32609)) u_s5_b0_17 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][17]), .a_im(stage_im[5][17]),
        .b_re(stage_re[5][49]), .b_im(stage_im[5][49]),
        .valid_o(),
        .y0_re(stage_re[6][17]), .y0_im(stage_im[6][17]),
        .y1_re(stage_re[6][49]), .y1_im(stage_im[6][49])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-6393), .TW_IM(-32137)) u_s5_b0_18 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][18]), .a_im(stage_im[5][18]),
        .b_re(stage_re[5][50]), .b_im(stage_im[5][50]),
        .valid_o(),
        .y0_re(stage_re[6][18]), .y0_im(stage_im[6][18]),
        .y1_re(stage_re[6][50]), .y1_im(stage_im[6][50])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-9512), .TW_IM(-31356)) u_s5_b0_19 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][19]), .a_im(stage_im[5][19]),
        .b_re(stage_re[5][51]), .b_im(stage_im[5][51]),
        .valid_o(),
        .y0_re(stage_re[6][19]), .y0_im(stage_im[6][19]),
        .y1_re(stage_re[6][51]), .y1_im(stage_im[6][51])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-12539), .TW_IM(-30273)) u_s5_b0_20 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][20]), .a_im(stage_im[5][20]),
        .b_re(stage_re[5][52]), .b_im(stage_im[5][52]),
        .valid_o(),
        .y0_re(stage_re[6][20]), .y0_im(stage_im[6][20]),
        .y1_re(stage_re[6][52]), .y1_im(stage_im[6][52])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-15446), .TW_IM(-28898)) u_s5_b0_21 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][21]), .a_im(stage_im[5][21]),
        .b_re(stage_re[5][53]), .b_im(stage_im[5][53]),
        .valid_o(),
        .y0_re(stage_re[6][21]), .y0_im(stage_im[6][21]),
        .y1_re(stage_re[6][53]), .y1_im(stage_im[6][53])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-18204), .TW_IM(-27245)) u_s5_b0_22 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][22]), .a_im(stage_im[5][22]),
        .b_re(stage_re[5][54]), .b_im(stage_im[5][54]),
        .valid_o(),
        .y0_re(stage_re[6][22]), .y0_im(stage_im[6][22]),
        .y1_re(stage_re[6][54]), .y1_im(stage_im[6][54])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-20787), .TW_IM(-25329)) u_s5_b0_23 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][23]), .a_im(stage_im[5][23]),
        .b_re(stage_re[5][55]), .b_im(stage_im[5][55]),
        .valid_o(),
        .y0_re(stage_re[6][23]), .y0_im(stage_im[6][23]),
        .y1_re(stage_re[6][55]), .y1_im(stage_im[6][55])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-23170), .TW_IM(-23170)) u_s5_b0_24 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][24]), .a_im(stage_im[5][24]),
        .b_re(stage_re[5][56]), .b_im(stage_im[5][56]),
        .valid_o(),
        .y0_re(stage_re[6][24]), .y0_im(stage_im[6][24]),
        .y1_re(stage_re[6][56]), .y1_im(stage_im[6][56])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-25329), .TW_IM(-20787)) u_s5_b0_25 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][25]), .a_im(stage_im[5][25]),
        .b_re(stage_re[5][57]), .b_im(stage_im[5][57]),
        .valid_o(),
        .y0_re(stage_re[6][25]), .y0_im(stage_im[6][25]),
        .y1_re(stage_re[6][57]), .y1_im(stage_im[6][57])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-27245), .TW_IM(-18204)) u_s5_b0_26 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][26]), .a_im(stage_im[5][26]),
        .b_re(stage_re[5][58]), .b_im(stage_im[5][58]),
        .valid_o(),
        .y0_re(stage_re[6][26]), .y0_im(stage_im[6][26]),
        .y1_re(stage_re[6][58]), .y1_im(stage_im[6][58])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-28898), .TW_IM(-15446)) u_s5_b0_27 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][27]), .a_im(stage_im[5][27]),
        .b_re(stage_re[5][59]), .b_im(stage_im[5][59]),
        .valid_o(),
        .y0_re(stage_re[6][27]), .y0_im(stage_im[6][27]),
        .y1_re(stage_re[6][59]), .y1_im(stage_im[6][59])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-30273), .TW_IM(-12539)) u_s5_b0_28 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][28]), .a_im(stage_im[5][28]),
        .b_re(stage_re[5][60]), .b_im(stage_im[5][60]),
        .valid_o(),
        .y0_re(stage_re[6][28]), .y0_im(stage_im[6][28]),
        .y1_re(stage_re[6][60]), .y1_im(stage_im[6][60])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-31356), .TW_IM(-9512)) u_s5_b0_29 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][29]), .a_im(stage_im[5][29]),
        .b_re(stage_re[5][61]), .b_im(stage_im[5][61]),
        .valid_o(),
        .y0_re(stage_re[6][29]), .y0_im(stage_im[6][29]),
        .y1_re(stage_re[6][61]), .y1_im(stage_im[6][61])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-32137), .TW_IM(-6393)) u_s5_b0_30 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][30]), .a_im(stage_im[5][30]),
        .b_re(stage_re[5][62]), .b_im(stage_im[5][62]),
        .valid_o(),
        .y0_re(stage_re[6][30]), .y0_im(stage_im[6][30]),
        .y1_re(stage_re[6][62]), .y1_im(stage_im[6][62])
    );
    complex_butterfly_pipe #(.DATA_W(20), .TW_RE(-32609), .TW_IM(-3212)) u_s5_b0_31 (
        .clk(clk), .rst(rst), .valid_i(stage_valid[5]),
        .a_re(stage_re[5][31]), .a_im(stage_im[5][31]),
        .b_re(stage_re[5][63]), .b_im(stage_im[5][63]),
        .valid_o(),
        .y0_re(stage_re[6][31]), .y0_im(stage_im[6][31]),
        .y1_re(stage_re[6][63]), .y1_im(stage_im[6][63])
    );
    assign out_valid = stage_valid[6];
    function [7:0] sat8;
        input signed [19:0] value;
        begin
            if (value > 20'sd127) sat8 = 8'h7f;
            else if (value < -20'sd128) sat8 = 8'h80;
            else sat8 = value[7:0];
        end
    endfunction
    always @* begin
        out_re = '0;
        out_im = '0;
        out_re[0 +: 8] = sat8(stage_re[6][0]);
        out_im[0 +: 8] = sat8(stage_im[6][0]);
        out_re[8 +: 8] = sat8(stage_re[6][1]);
        out_im[8 +: 8] = sat8(stage_im[6][1]);
        out_re[16 +: 8] = sat8(stage_re[6][2]);
        out_im[16 +: 8] = sat8(stage_im[6][2]);
        out_re[24 +: 8] = sat8(stage_re[6][3]);
        out_im[24 +: 8] = sat8(stage_im[6][3]);
        out_re[32 +: 8] = sat8(stage_re[6][4]);
        out_im[32 +: 8] = sat8(stage_im[6][4]);
        out_re[40 +: 8] = sat8(stage_re[6][5]);
        out_im[40 +: 8] = sat8(stage_im[6][5]);
        out_re[48 +: 8] = sat8(stage_re[6][6]);
        out_im[48 +: 8] = sat8(stage_im[6][6]);
        out_re[56 +: 8] = sat8(stage_re[6][7]);
        out_im[56 +: 8] = sat8(stage_im[6][7]);
        out_re[64 +: 8] = sat8(stage_re[6][8]);
        out_im[64 +: 8] = sat8(stage_im[6][8]);
        out_re[72 +: 8] = sat8(stage_re[6][9]);
        out_im[72 +: 8] = sat8(stage_im[6][9]);
        out_re[80 +: 8] = sat8(stage_re[6][10]);
        out_im[80 +: 8] = sat8(stage_im[6][10]);
        out_re[88 +: 8] = sat8(stage_re[6][11]);
        out_im[88 +: 8] = sat8(stage_im[6][11]);
        out_re[96 +: 8] = sat8(stage_re[6][12]);
        out_im[96 +: 8] = sat8(stage_im[6][12]);
        out_re[104 +: 8] = sat8(stage_re[6][13]);
        out_im[104 +: 8] = sat8(stage_im[6][13]);
        out_re[112 +: 8] = sat8(stage_re[6][14]);
        out_im[112 +: 8] = sat8(stage_im[6][14]);
        out_re[120 +: 8] = sat8(stage_re[6][15]);
        out_im[120 +: 8] = sat8(stage_im[6][15]);
        out_re[128 +: 8] = sat8(stage_re[6][16]);
        out_im[128 +: 8] = sat8(stage_im[6][16]);
        out_re[136 +: 8] = sat8(stage_re[6][17]);
        out_im[136 +: 8] = sat8(stage_im[6][17]);
        out_re[144 +: 8] = sat8(stage_re[6][18]);
        out_im[144 +: 8] = sat8(stage_im[6][18]);
        out_re[152 +: 8] = sat8(stage_re[6][19]);
        out_im[152 +: 8] = sat8(stage_im[6][19]);
        out_re[160 +: 8] = sat8(stage_re[6][20]);
        out_im[160 +: 8] = sat8(stage_im[6][20]);
        out_re[168 +: 8] = sat8(stage_re[6][21]);
        out_im[168 +: 8] = sat8(stage_im[6][21]);
        out_re[176 +: 8] = sat8(stage_re[6][22]);
        out_im[176 +: 8] = sat8(stage_im[6][22]);
        out_re[184 +: 8] = sat8(stage_re[6][23]);
        out_im[184 +: 8] = sat8(stage_im[6][23]);
        out_re[192 +: 8] = sat8(stage_re[6][24]);
        out_im[192 +: 8] = sat8(stage_im[6][24]);
        out_re[200 +: 8] = sat8(stage_re[6][25]);
        out_im[200 +: 8] = sat8(stage_im[6][25]);
        out_re[208 +: 8] = sat8(stage_re[6][26]);
        out_im[208 +: 8] = sat8(stage_im[6][26]);
        out_re[216 +: 8] = sat8(stage_re[6][27]);
        out_im[216 +: 8] = sat8(stage_im[6][27]);
        out_re[224 +: 8] = sat8(stage_re[6][28]);
        out_im[224 +: 8] = sat8(stage_im[6][28]);
        out_re[232 +: 8] = sat8(stage_re[6][29]);
        out_im[232 +: 8] = sat8(stage_im[6][29]);
        out_re[240 +: 8] = sat8(stage_re[6][30]);
        out_im[240 +: 8] = sat8(stage_im[6][30]);
        out_re[248 +: 8] = sat8(stage_re[6][31]);
        out_im[248 +: 8] = sat8(stage_im[6][31]);
        out_re[256 +: 8] = sat8(stage_re[6][32]);
        out_im[256 +: 8] = sat8(stage_im[6][32]);
        out_re[264 +: 8] = sat8(stage_re[6][33]);
        out_im[264 +: 8] = sat8(stage_im[6][33]);
        out_re[272 +: 8] = sat8(stage_re[6][34]);
        out_im[272 +: 8] = sat8(stage_im[6][34]);
        out_re[280 +: 8] = sat8(stage_re[6][35]);
        out_im[280 +: 8] = sat8(stage_im[6][35]);
        out_re[288 +: 8] = sat8(stage_re[6][36]);
        out_im[288 +: 8] = sat8(stage_im[6][36]);
        out_re[296 +: 8] = sat8(stage_re[6][37]);
        out_im[296 +: 8] = sat8(stage_im[6][37]);
        out_re[304 +: 8] = sat8(stage_re[6][38]);
        out_im[304 +: 8] = sat8(stage_im[6][38]);
        out_re[312 +: 8] = sat8(stage_re[6][39]);
        out_im[312 +: 8] = sat8(stage_im[6][39]);
        out_re[320 +: 8] = sat8(stage_re[6][40]);
        out_im[320 +: 8] = sat8(stage_im[6][40]);
        out_re[328 +: 8] = sat8(stage_re[6][41]);
        out_im[328 +: 8] = sat8(stage_im[6][41]);
        out_re[336 +: 8] = sat8(stage_re[6][42]);
        out_im[336 +: 8] = sat8(stage_im[6][42]);
        out_re[344 +: 8] = sat8(stage_re[6][43]);
        out_im[344 +: 8] = sat8(stage_im[6][43]);
        out_re[352 +: 8] = sat8(stage_re[6][44]);
        out_im[352 +: 8] = sat8(stage_im[6][44]);
        out_re[360 +: 8] = sat8(stage_re[6][45]);
        out_im[360 +: 8] = sat8(stage_im[6][45]);
        out_re[368 +: 8] = sat8(stage_re[6][46]);
        out_im[368 +: 8] = sat8(stage_im[6][46]);
        out_re[376 +: 8] = sat8(stage_re[6][47]);
        out_im[376 +: 8] = sat8(stage_im[6][47]);
        out_re[384 +: 8] = sat8(stage_re[6][48]);
        out_im[384 +: 8] = sat8(stage_im[6][48]);
        out_re[392 +: 8] = sat8(stage_re[6][49]);
        out_im[392 +: 8] = sat8(stage_im[6][49]);
        out_re[400 +: 8] = sat8(stage_re[6][50]);
        out_im[400 +: 8] = sat8(stage_im[6][50]);
        out_re[408 +: 8] = sat8(stage_re[6][51]);
        out_im[408 +: 8] = sat8(stage_im[6][51]);
        out_re[416 +: 8] = sat8(stage_re[6][52]);
        out_im[416 +: 8] = sat8(stage_im[6][52]);
        out_re[424 +: 8] = sat8(stage_re[6][53]);
        out_im[424 +: 8] = sat8(stage_im[6][53]);
        out_re[432 +: 8] = sat8(stage_re[6][54]);
        out_im[432 +: 8] = sat8(stage_im[6][54]);
        out_re[440 +: 8] = sat8(stage_re[6][55]);
        out_im[440 +: 8] = sat8(stage_im[6][55]);
        out_re[448 +: 8] = sat8(stage_re[6][56]);
        out_im[448 +: 8] = sat8(stage_im[6][56]);
        out_re[456 +: 8] = sat8(stage_re[6][57]);
        out_im[456 +: 8] = sat8(stage_im[6][57]);
        out_re[464 +: 8] = sat8(stage_re[6][58]);
        out_im[464 +: 8] = sat8(stage_im[6][58]);
        out_re[472 +: 8] = sat8(stage_re[6][59]);
        out_im[472 +: 8] = sat8(stage_im[6][59]);
        out_re[480 +: 8] = sat8(stage_re[6][60]);
        out_im[480 +: 8] = sat8(stage_im[6][60]);
        out_re[488 +: 8] = sat8(stage_re[6][61]);
        out_im[488 +: 8] = sat8(stage_im[6][61]);
        out_re[496 +: 8] = sat8(stage_re[6][62]);
        out_im[496 +: 8] = sat8(stage_im[6][62]);
        out_re[504 +: 8] = sat8(stage_re[6][63]);
        out_im[504 +: 8] = sat8(stage_im[6][63]);
    end
endmodule
