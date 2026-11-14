function output = conv_linear(signal, kernel)
%CONV_LINEAR 用反折、移位、相乘求和实现完整线性卷积。
%   输入为非空实数或复数向量，输出列向量长度为 length(signal)+length(kernel)-1。

    signal = signal(:);
    kernel = kernel(:);
    output = complex(zeros(numel(signal) + numel(kernel) - 1, 1));

    for position = 1:numel(output)
        % 只遍历两序列重叠的区间，相当于区间外的输入全部为零。
        first = max(1, position - numel(kernel) + 1);
        last = min(numel(signal), position);
        for sample = first:last
            % sample 增大时，kernel 下标减小，表示反折后的核移到 position。
            % 数学公式 y[n]=sum_m x[m]h[n-m]；1-based 下标需额外加 1。
            % 普通复数卷积不取共轭，避免混淆为相关运算。
            output(position) = output(position) ...
                + signal(sample) * kernel(position - sample + 1);
        end
    end
end
