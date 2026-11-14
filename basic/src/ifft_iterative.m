function signal = ifft_iterative(spectrum, plan)
%IFFT_ITERATIVE 复用迭代 FFT，实现相同点数的 IFFT，输出为列向量。
%   输入长度为 plan 支持的 2 的幂（至少 2）；不补零、不截断。

    % IFFT(X) = conj(FFT(conj(X)))/N，无需生成另一份旋转因子表。
    % 对一般复数频谱保留完整复数输出，只在此处归一化一次。
    signal = conj(fft_iterative(conj(spectrum), plan)) / numel(spectrum);
end
