function output = conv_ola(signal, kernel, plan, fft_points)
%CONV_OLA 重叠相加法，输入不重叠，输出的重叠区累加。
%   输入为非空实数或复数向量，返回长度 Lx+M-1 的完整卷积。
%   fft_points 是 plan 支持的 FFT 长度，且不小于核长 M。
%   本次调用使用固定 kernel；CMA 抽头更新后不能继续复用旧频谱。

    signal = signal(:);
    kernel = kernel(:);
    block_length = fft_points - numel(kernel) + 1; % 每块最多 B=N-M+1 个新点
    output = complex(zeros(numel(signal) + numel(kernel) - 1, 1));
    % 固定核只变换一次，在本次调用的所有数据块间复用。
    kernel_spectrum = fft_iterative([kernel; zeros(fft_points - numel(kernel), 1)], plan);

    for first = 1:block_length:numel(signal)
        % 最后一块允许不足 B 点，用实际长度确定有效输出区间。
        last = min(first + block_length - 1, numel(signal));
        block = [signal(first:last); zeros(fft_points - (last - first + 1), 1)];
        filtered = ifft_iterative(fft_iterative(block, plan) .* kernel_spectrum, plan);
        % b 个输入产生 b+M-1 个输出；按该块起点对齐并累加，而非覆盖。
        indices = first:last + numel(kernel) - 1;
        output(indices) = output(indices) + filtered(1:numel(indices));
    end
end
