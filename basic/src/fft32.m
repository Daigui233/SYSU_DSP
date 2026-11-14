function spectrum = fft32(signal, plan)
%FFT32 32 点 FFT 封装，共用逐层迭代核心。
%   signal 含 32 个元素，plan 至少初始化到 32 点；输出为 32×1 列向量。
%   不在封装内初始化，不自动补零或截断，不调用 MATLAB 内置 FFT。

    % 固定点数并统一行列形状；长度不符时由 reshape 自身报错。
    spectrum = fft_iterative(reshape(signal, 32, 1), plan);
end
