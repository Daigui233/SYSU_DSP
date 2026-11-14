function signal = ifft32(spectrum, plan)
%IFFT32 32 点 IFFT；plan 至少初始化到 32 点，输出为 32×1 列向量。
    % 固定长度并统一形状，逆变换及归一化均交给公共核心。
    signal = ifft_iterative(reshape(spectrum, 32, 1), plan);
end
