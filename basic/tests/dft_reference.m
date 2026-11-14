function spectrum = dft_reference(signal)
%DFT_REFERENCE 按 DFT 定义直接求和，供各点数测试作独立基准。
%   不使用被测 FFT 的旋转因子表、蝶形或倒位序，不调用内置 FFT。

    signal = signal(:);
    point_count = numel(signal);
    % 每个频点分别累加全部输入样本的贡献，复杂度为 O(N^2)。
    spectrum = complex(zeros(point_count, 1));
    for frequency = 0:point_count - 1
        for sample = 0:point_count - 1
            % 数学下标从 0 起；仅在访问 MATLAB 数组时加 1。
            weight = exp(-2i * pi * frequency * sample / point_count);
            spectrum(frequency + 1) = spectrum(frequency + 1) ...
                + signal(sample + 1) * weight;
        end
    end
end
