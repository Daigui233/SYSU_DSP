function spectrum = fft_recursive(signal, plan)
%FFT_RECURSIVE 倒位序输入、自然顺序输出的递归基 2 FFT。
%   signal 的长度为不超过 plan.max_points 的 2 的幂（至少为 2）。
%   按实际输入长度选择层数，输出统一为列向量。
%   只在入口倒位序一次；递归内部按连续前后两半拆分。
%   核心不做归一化，逆变换可使用共轭因子并在外部除以总点数。

    % 只统一行列形状，不改变元素次序或复数值。
    signal = signal(:);
    % 输入有多少点，就使用多少层；不使用初始化配置的最大层数。
    stage_count = log2(numel(signal));
    % 顶层倒位序后，连续前后两半已对应 DIT 所需的两个子问题。
    reordered = signal(plan.input_orders{stage_count});
    % 8 点配置有 3 层，从第 3 层向下递归，返回时依次完成各层合并。
    spectrum = transform_block(reordered, plan.stage_weights, stage_count);
end

function output = transform_block(input, stage_weights, stage)
% 当前输入长度为 2^stage；子结果返回时已按其自身频点自然排序。
    % stage=0 时只剩一个点，1 点 DFT 就是输入自身，终止递归。
    if stage == 0
        output = input;
        return;
    end

    % 每次处理连续两半，不再次倒位序，也不再按奇偶下标抽取。
    half_length = numel(input) / 2;
    left = transform_block(input(1:half_length), stage_weights, stage - 1);
    right = transform_block(input(half_length + 1:end), stage_weights, stage - 1);

    % 子变换已完成；用当前层的旋转因子将两份结果合并。
    [upper, lower] = fft_butterfly(left, right, stage_weights{stage});
    % 上路放频点 0:M/2-1，下路放 M/2:M-1，组成自然顺序的当前结果。
    output = [upper; lower];
end
