function test_convolution
%TEST_CONVOLUTION 验证完整卷积、分块边界及 CMA 复数数据片段。
%   不调用内置 fft/ifft/conv；所有算法应输出 Lx+M-1 个复数兼容的点。
    module_directory = fileparts(fileparts(mfilename('fullpath')));
    original_path = path;
    restore_path = onCleanup(@() path(original_path));
    addpath(fullfile(module_directory, 'src'));
    plan = fft_plan(128);
    tolerance = 1e-12;
    stream = RandStream('mt19937ar', 'Seed', 20261116);
    data = load(fullfile(fileparts(module_directory), 'reference', ...
                '大作业matlab', 'TD_TRdata.mat'), 'RTdataX', 'RTdataY');

    % 手算结果先确认直接卷积的反折/移位方向，以及复数运算不取共轭。
    assert(isequal(conv_linear([1, 2, 3], [1, 1]), [1; 3; 5; 3]), '实数手算例失败。');
    assert(isequal(conv_linear([1 + 1i, 2 - 1i], [2, -1i]), ...
                   [2 + 2i; 5 - 3i; -1 - 2i]), '复数手算例失败。');
    methods = {@conv_linear, @conv_fft, @conv_ola, @conv_ols};
    method_names = {'linear', 'fft', 'ola', 'ols'};
    % 用例数量随 FFT 长度及短卷积适用条件变化，逐行记录最终指标。
    records = cell(0, 8);
    for n = [32, 64, 128]
        m = min(33, n / 2 + 1);
        b = n - m + 1;
        kernel = randn(stream, m, 1) + 1i * randn(stream, m, 1);
        cases = { ...
            'hand_real', [1, 2, 3], [1, 1]; ...
            'hand_complex', [1 + 1i, 2 - 1i], [2, -1i]; ...
            'real_complex', 1:7, [1 + 1i, -2i, 3]; ...
            'complex_real', [1i, 2 - 1i, -3], [1, -2, 0.5]; ...
            'zero_input', zeros(1, 2 * b + 1), kernel; ...
            'zero_kernel', randn(stream, n + 3, 1), zeros(m, 1); ...
            'scalar_kernel', randn(stream, 2 * n + 3, 1), 2 - 1i; ...
            'scalar_input', 1 + 2i, kernel; ...
            'short_exact', randn(stream, n - 4, 1), [1i; 2; -1; 0.5i; 3]; ...
            'kernel_equals_fft', [1 + 1i; 2; -1i], randn(stream, n, 1); ...
            'kernel_near_fft', randn(stream, 7, 1), randn(stream, n - 1, 1); ...
            'whole_blocks', randn(stream, 3 * b, 1) + 1i * randn(stream, 3 * b, 1), kernel; ...
            'partial_block', randn(stream, 3 * b + 1, 1) + 1i * randn(stream, 3 * b + 1, 1), kernel; ...
            'last_impulse', [zeros(2 * b, 1); 1], kernel};
        if n >= 64
            % 实际 CMA 输入为复数行向量，核长取参考代码中的 33 点。
            % 这里只验证固定核滤波，不把它当作自适应 CMA 的端到端验证。
            cases(end + 1, :) = {'cma_x', data.RTdataX(1:257), kernel}; %#ok<AGROW>
            cases(end + 1, :) = {'cma_y', data.RTdataY(1:193), kernel}; %#ok<AGROW>
        end

        for case_index = 1:size(cases, 1)
            signal = cases{case_index, 2};
            kernel = cases{case_index, 3};
            % 独立基准按每个核抽头累加移位输入，与生产代码的输出逐点求和不同。
            reference = shifted_sum_reference(signal, kernel);
            for method = 1:numel(methods)
                % 单次快速卷积只有补零长度足够时才适用；长输入交给 OLA/OLS。
                if method == 2 && numel(reference) > n
                    continue;
                end
                if method == 1
                    output = methods{method}(signal, kernel);
                    row_output = methods{method}(signal(:).', kernel(:).');
                else
                    output = methods{method}(signal, kernel, plan, n);
                    row_output = methods{method}(signal(:).', kernel(:).', plan, n);
                end
                assert(isequal(size(output), size(reference)) && ...
                       isequal(size(row_output), size(reference)), '卷积输出长度或形状错误。');
                absolute_error = max(abs(output - reference));
                scaled_error = absolute_error / max(1, max(abs(reference)));
                shape_difference = max(abs(output - row_output));
                assert(scaled_error < tolerance && shape_difference == 0, '卷积结果不正确。');
                records(end + 1, :) = {n, cases{case_index, 1}, method_names{method}, ...
                    numel(signal), numel(kernel), absolute_error, scaled_error, shape_difference}; %#ok<AGROW>
            end
        end
    end
    summary = cell2table(records, 'VariableNames', {'fft_points', 'case_name', 'method', ...
        'input_length', 'kernel_length', 'absolute_error', 'scaled_error', 'row_column_difference'});
    writetable(summary, fullfile(module_directory, 'results', 'convolution_errors.csv'));
    fprintf('PASS: convolution %d checks; max scaled error %.3e\n', ...
            height(summary), max(summary.scaled_error));
end

function output = shifted_sum_reference(signal, kernel)
% h[k] 乘整段 x 后移位累加，不复用被测直接卷积的反折索引。
    signal = signal(:);
    kernel = kernel(:);
    output = complex(zeros(numel(signal) + numel(kernel) - 1, 1));
    for tap = 1:numel(kernel)
        indices = tap:tap + numel(signal) - 1;
        output(indices) = output(indices) + kernel(tap) * signal;
    end
end
