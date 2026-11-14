function spectrum = fft64(signal, plan)
%FFT64 64 点 FFT 封装，共用逐层迭代核心。
%   signal 含 64 个元素，plan 至少初始化到 64 点；输出为 64×1 列向量。
%   不在封装内初始化，不自动补零或截断，不调用 MATLAB 内置 FFT。

    % 固定点数并统一行列形状；长度不符时由 reshape 自身报错。
    spectrum = fft_iterative(reshape(signal, 64, 1), plan);
end
