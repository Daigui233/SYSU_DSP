function output = conv_ols(signal, kernel, plan, fft_points)
%CONV_OLS 重叠保留法，保留输入历史，丢弃每块输出的循环混叠区。
%   输入为非空实数或复数向量，返回长度 Lx+M-1 的完整卷积。
%   fft_points 是 plan 支持的 FFT 长度，且不小于核长 M。
%   本次调用使用固定 kernel；不在此模块内执行 CMA 抽头更新。

    signal = signal(:);
    kernel = kernel(:);
    history_length = numel(kernel) - 1;
    block_length = fft_points - history_length; % 每块保留 B=N-M+1 个有效输出
    output_length = numel(signal) + history_length;
    output = complex(zeros(output_length, 1));
    kernel_spectrum = fft_iterative([kernel; zeros(fft_points - numel(kernel), 1)], plan);

    % 起始历史为零；尾部继续送零以输出完整卷积尾部，并补齐最后一个块。
    block_count = ceil(output_length / block_length);
    padded = [zeros(history_length, 1); signal; ...
              zeros(block_count * block_length - numel(signal), 1)];
    for first = 1:block_length:output_length
        % 每次前进 B 点，连续 N 点窗口自然保留上一块末尾的 M-1 个输入。
        block = padded(first:first + fft_points - 1);
        filtered = ifft_iterative(fft_iterative(block, plan) .* kernel_spectrum, plan);
        % 丢弃前 M-1 个污染输出；最后一块只写入尚需的有效点，不进行相加。
        count = min(block_length, output_length - first + 1);
        output(first:first + count - 1) = filtered(history_length + (1:count));
    end
end
