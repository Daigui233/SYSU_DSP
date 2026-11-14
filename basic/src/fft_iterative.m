function spectrum = fft_iterative(signal, plan)
%FFT_ITERATIVE 按 2、4、8、... 点分组逐层计算的基 2 FFT。
%   输入约定与 fft_recursive 一致，输出为自然顺序的列向量。
%   与递归版共用倒位序、旋转因子表和蝶形，不做归一化。

    % 统一为列向量，并在所有蝶形层开始前完成一次输入重排。
    signal = signal(:);
    % 依据实际输入长度选择排列和层数，允许复用更大点数的初始化配置。
    point_count = numel(signal);
    stage_count = log2(point_count);
    spectrum = signal(plan.input_orders{stage_count});

    % 从小组到大组逐层计算；每层全部完成后，才能进入下一层。
    for stage = 1:stage_count
        block_length = plan.stage_points(stage);
        half_length = block_length / 2;
        % 同一层所有分组共用同一份预计算系数。
        weights = plan.stage_weights{stage};

        % first 每次跨过一个完整分组，各组在本层处理互不重叠的数据。
        for first = 1:block_length:point_count
            left_indices = first:first + half_length - 1;
            % 前后半组一一配对，蝶形两输入的距离恰好是 M/2。
            right_indices = left_indices + half_length;
            % 先完整读取两路并算出结果，再写回，避免覆盖仍需使用的输入。
            [upper, lower] = fft_butterfly( ...
                spectrum(left_indices), spectrum(right_indices), weights);
            % 原位写回当前组，上下两路保持该组频点的自然顺序。
            spectrum(left_indices) = upper;
            spectrum(right_indices) = lower;
        end
    end
end
