function [out_re, out_im] = fft_fixed_reference(in_re, in_im)
% Normalized radix-2 fixed-point reference used by the Verilog testbench.
% Inputs and outputs are signed 8-bit integer samples. Six fractional guard
% bits are retained through the normalized FFT and rounded at the 8-bit output.
    n = numel(in_re);
    stages = log2(n);
    guard_bits = 6;
    twiddle_scale = 32768; % 17-bit coefficients represent +/-1 exactly.
    order = zeros(1,n);
    for k = 0:n-1
        x = k; y = 0;
        for b = 1:stages
            y = 2*y + bitand(bitshift(x, -(b-1)), 1);
        end
        order(k+1) = y + 1;
    end
    out_re = bitshift(int64(in_re(order)), guard_bits);
    out_im = bitshift(int64(in_im(order)), guard_bits);
    for stage = 1:stages
        m = 2^stage;
        half = m/2;
        stride = n/m;
        for base = 1:m:n
            for j = 0:half-1
                i0 = base+j; i1 = i0+half;
                theta = -2*pi*j*stride/n;
                wr = round(twiddle_scale*cos(theta));
                wi = round(twiddle_scale*sin(theta));
                pr = bitshift(out_re(i1)*wr - out_im(i1)*wi, -15);
                prod_im = bitshift(out_re(i1)*wi + out_im(i1)*wr, -15);
                ar = out_re(i0); ai = out_im(i0);
                out_re(i0) = bitshift(ar+pr, -1);
                out_im(i0) = bitshift(ai+prod_im, -1);
                out_re(i1) = bitshift(ar-pr, -1);
                out_im(i1) = bitshift(ai-prod_im, -1);
            end
        end
    end
    out_re = round_shift_guard(out_re, guard_bits);
    out_im = round_shift_guard(out_im, guard_bits);
    out_re = max(-128,min(127,out_re));
    out_im = max(-128,min(127,out_im));
end

function result = round_shift_guard(value, shift)
% Symmetric round-to-nearest, away from zero at exact half-way values.
    offset = int64(2^(shift-1));
    result = zeros(size(value), 'int64');
    positive = value >= 0;
    result(positive) = bitshift(value(positive) + offset, -shift);
    result(~positive) = -bitshift(-value(~positive) + offset, -shift);
end
