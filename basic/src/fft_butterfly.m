function [upper, lower] = fft_butterfly(left, right, weights)
%FFT_BUTTERFLY 批量计算一组基 2 DIT 蝶形。
%   三个输入是等长复数列向量；乘积只计算一次，供两路输出共用。

    % 每个右路数据乘对应因子，.* 表示逐元素乘法，而非矩阵乘法。
    product = weights .* right;
    % 两路输出分别对应当前分组的频点 k 与 k+M/2，复用同一个乘积。
    upper = left + product;
    lower = left - product;
end
