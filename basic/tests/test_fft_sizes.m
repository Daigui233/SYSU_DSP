function test_fft_sizes
%TEST_FFT_SIZES 验证 32/64/128 点迭代封装，共用一次 128 点初始化。
%   仓库根目录运行：addpath('basic/tests'); test_fft_sizes

    % 通过文件位置找到源码，测试退出后恢复用户原有搜索路径。
    module_directory = fileparts(fileparts(mfilename('fullpath')));
    original_path = path;
    restore_path = onCleanup(@() path(original_path));
    addpath(fullfile(module_directory, 'src'));

    point_counts = [32, 64, 128];
    transforms = {@fft32, @fft64, @fft128};
    case_names = {'zero'; 'impulse'; 'last_impulse'; 'constant'; ...
                  'complex_tone'; 'complex_random'};
    % 容差在运行前固定：以 max(1, 基准最大幅度) 归一化误差。
    % 同时保留原始绝对误差，便于人工判断尺度和浮点精度。
    tolerance = 1e-12;
    plan = fft_plan(128);
    inverse_plan = plan;
    for stage = 1:numel(plan.stage_weights)
        % 逆变换仍使用相同核心，仅变换系数符号并在输出处除以 N。
        inverse_plan.stage_weights{stage} = conj(plan.stage_weights{stage});
    end

    % 局部随机流保证数据可复现，同时不改变用户的全局随机状态。
    stream = RandStream('mt19937ar', 'Seed', 20261114);
    rows = numel(point_counts) * numel(case_names);
    tested_points = zeros(rows, 1);
    tested_cases = cell(rows, 1);
    errors = zeros(rows, 6);
    row = 0;

    for size_index = 1:numel(point_counts)
        point_count = point_counts(size_index);
        transform = transforms{size_index};
        sample = (0:point_count - 1).';
        % 每列一个用例：零、首尾冲激、直流、靠近末端频点的复指数、
        % 一般复数随机序列，覆盖幅值、相位及频点顺序。
        signals = [zeros(point_count, 1), ...
                   [1; zeros(point_count - 1, 1)], ...
                   [zeros(point_count - 1, 1); 1], ...
                   ones(point_count, 1), ...
                   exp(2i * pi * (point_count - 3) * sample / point_count), ...
                   randn(stream, point_count, 1) + 1i * randn(stream, point_count, 1)];

        for case_index = 1:numel(case_names)
            signal = signals(:, case_index);
            reference = dft_reference(signal);
            spectrum = transform(signal, plan);
            recursive = fft_recursive(signal, plan);
            % .' 不取共轭，只改变形状，验证行向量输入不会改变复数值。
            row_spectrum = transform(signal.', plan);
            restored = transform(spectrum, inverse_plan) / point_count;
            assert(isequal(size(spectrum), [point_count, 1]) && ...
                   isequal(size(row_spectrum), [point_count, 1]), '输出形状不正确。');

            row = row + 1;
            tested_points(row) = point_count;
            tested_cases{row} = case_names{case_index};
            absolute_error = max(abs(spectrum - reference));
            % 各指标分别对照独立 DFT、另一种算法、不同输入形状及原信号。
            errors(row, :) = [absolute_error, ...
                absolute_error / max(1, max(abs(reference))), ...
                max(abs(spectrum - recursive)), ...
                max(abs(spectrum - row_spectrum)), ...
                max(abs(restored - signal)), ...
                max(abs(restored - signal)) / max(1, max(abs(signal)))];
        end
    end

    % 正确性以归一化 DFT 误差和往返误差判定；同一蝶形的两种调度
    % 及行列输入转换应给出完全一致的结果。
    assert(all(errors(:, 2) < tolerance) && all(errors(:, 6) < tolerance), ...
           'DFT 对照或逆变换误差超过阈值。');
    assert(all(errors(:, 3) == 0) && all(errors(:, 4) == 0), ...
           '递归/迭代结果或行列向量结果不一致。');

    summary = array2table(errors, 'VariableNames', {'dft_absolute_error', ...
        'dft_scaled_error', 'recursive_difference', 'row_column_difference', ...
        'roundtrip_absolute_error', 'roundtrip_scaled_error'});
    summary = addvars(summary, tested_points, tested_cases, 'Before', 1, ...
        'NewVariableNames', {'point_count', 'case_name'});
    % 只导出通过验证的最终数据，以及可直接载入复用的共享初始化配置。
    writetable(summary, fullfile(module_directory, 'results', 'fft_sizes_errors.csv'));
    save(fullfile(module_directory, 'results', 'fft128_plan.mat'), 'plan');
    disp(summary);
    fprintf('PASS: 32/64/128-point wrappers; scaled tolerance %.1e\n', tolerance);
    fprintf('MATLAB %s\n', version);
end
