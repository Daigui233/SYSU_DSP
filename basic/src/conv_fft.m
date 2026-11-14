function output = conv_fft(signal, kernel, plan, fft_points)
%CONV_FFT 用一次 FFT 相乘实现短序列的完整线性卷积。
%   输入为非空实数或复数向量；fft_points 是 plan 支持的 FFT 长度。
%   使用约定：fft_points >= length(signal)+length(kernel)-1。

    signal = signal(:);
    kernel = kernel(:);
    output_length = numel(signal) + numel(kernel) - 1;

    % 两序列补零到同一长度，保证循环卷积的回绕部分不会污染有效结果。
    signal_spectrum = fft_iterative([signal; zeros(fft_points - numel(signal), 1)], plan);
    kernel_spectrum = fft_iterative([kernel; zeros(fft_points - numel(kernel), 1)], plan);
    output = ifft_iterative(signal_spectrum .* kernel_spectrum, plan);
    % 丢弃补零产生的额外位置，保留完整的线性卷积长度，不丢弃虚部。
    output = output(1:output_length);
end
