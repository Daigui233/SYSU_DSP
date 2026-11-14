function signal = ifft64(spectrum, plan)
%IFFT64 64 点 IFFT；plan 至少初始化到 64 点，输出为 64×1 列向量。
    % 固定长度并统一形状，逆变换及归一化均交给公共核心。
    signal = ifft_iterative(reshape(spectrum, 64, 1), plan);
end
