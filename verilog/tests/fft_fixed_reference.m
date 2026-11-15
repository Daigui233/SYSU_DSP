function [out_re, out_im] = fft_fixed_reference(in_re, in_im)
% Normalized radix-2 fixed-point reference used by the Verilog testbench.
% Inputs and outputs are signed integer samples; every stage divides by two.
    n = numel(in_re);
    stages = log2(n);
    order = zeros(1,n);
    for k = 0:n-1
        x = k; y = 0;
        for b = 1:stages
            y = 2*y + bitand(bitshift(x, -(b-1)), 1);
        end
        order(k+1) = y + 1;
    end
    out_re = int64(in_re(order));
    out_im = int64(in_im(order));
    for stage = 1:stages
        m = 2^stage;
        half = m/2;
        stride = n/m;
        for base = 1:m:n
            for j = 0:half-1
                i0 = base+j; i1 = i0+half;
                theta = -2*pi*j*stride/n;
                wr = round(32767*cos(theta));
                wi = round(32767*sin(theta));
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
    out_re = max(-128,min(127,out_re));
    out_im = max(-128,min(127,out_im));
end
