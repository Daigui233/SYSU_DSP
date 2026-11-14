function signal = ifft128(spectrum, plan)
%IFFT128 128 点 IFFT；plan 至少初始化到 128 点，输出为 128×1 列向量。
    % 固定长度并统一形状，逆变换及归一化均交给公共核心。
    signal = ifft_iterative(reshape(spectrum, 128, 1), plan);
end
