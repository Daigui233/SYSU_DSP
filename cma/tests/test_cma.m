function result33 = test_cma(tap_counts)
%TEST_CMA 固定核、短段逐次更新及全量 33 抽头与教师脚本对照。
    if nargin == 0
        tap_counts = [5, 9, 17, 33];
    end
    module = fileparts(fileparts(mfilename('fullpath')));
    root = fileparts(module);
    original_path = path;
    restore_path = onCleanup(@() path(original_path));
    addpath(fullfile(module, 'src'), fullfile(root, 'basic', 'src'));
    data = load(fullfile(root, 'reference', '大作业matlab', 'TD_TRdata.mat'));
    input = [data.RTdataX(:), data.RTdataY(:)];
    plan = fft_plan(2^ceil(log2(max(tap_counts) + 31)));
    stream = RandStream('mt19937ar', 'Seed', 20261117);
    % 在运行前固定容差：固定核 1e-12；自适应对照 1e-9（各量分别归一化）。
    rows = cell(0, 5);
    for tap_count = tap_counts
        config = cma_config(tap_count);
        taps = (randn(stream, tap_count, 4) + 1i * randn(stream, tap_count, 4)) / tap_count;
        spectra = complex(zeros(config.fft_points, 4));
        for channel = 1:4
            spectra(:, channel) = fft_iterative([taps(:, channel); zeros(config.fft_points - tap_count, 1)], plan);
        end
        padded = [zeros(tap_count - 1, 2); input(1:128, :)];
        worst = 0;
        for block = 1:4
            first = (block - 1) * 32 + 1;
            window = padded(first:first + tap_count + 30, :);
            actual = cma_filter_block(window, spectra, plan, config);
            expected = complex(zeros(32, 2));
            for sample = 1:32
                indices = sample + tap_count - 1:-1:sample;
                expected(sample, 1) = taps(:, 1).' * window(indices, 1) + taps(:, 2).' * window(indices, 2);
                expected(sample, 2) = taps(:, 3).' * window(indices, 1) + taps(:, 4).' * window(indices, 2);
            end
            worst = max(worst, scaled_error(actual, expected));
        end
        assert(worst < 1e-12, '固定核滤波对照失败。');
        rows(end + 1, :) = {tap_count, 'fixed_four_blocks', worst, 0, 0}; %#ok<AGROW>
        % 167 点包含完整四块更新、下一块的新抽头，以及不足32点的截断。
        for count = [167, 4096]
            actual = cma_equalize(input(1:count, :), config, plan);
            expected = cma_reference_oracle(input(1:count, :), tap_count);
            differences = compare_results(actual, expected);
            assert(all(differences < 1e-9), '短段自适应对照失败。');
            rows(end + 1, :) = [{tap_count, sprintf('adaptive_%d', count)}, num2cell(differences)]; %#ok<AGROW>
        end
    end
    fprintf('Short tests passed. Running full 33-tap reference comparison...\n');
    expected = cma_reference_oracle(input, 33);
    result33 = cma_equalize(input, cma_config(33), plan);
    differences = compare_results(result33, expected);
    assert(all(differences < 1e-9), '全量33抽头参考对照失败。');
    assert(scaled_error(result33.last_used_taps, expected.last_used_taps) < 1e-9, ...
           '最终参考抽头位置不一致。');
    rows(end + 1, :) = [{33, 'full_reference'}, num2cell(differences)];
    summary = cell2table(rows, 'VariableNames', {'tap_count', 'test', ...
        'output_scaled_error', 'error_scaled_error', 'tap_history_scaled_error'});
    writetable(summary, fullfile(module, 'results', 'validation.csv'));
    disp(summary);
    fprintf('PASS: CMA reference checks; full output %.3e, taps %.3e\n', differences(1), differences(3));
end

function differences = compare_results(actual, expected)
    differences = [scaled_error(actual.output, expected.output), ...
        scaled_error(actual.errors, expected.errors), ...
        scaled_error(actual.tap_history, expected.tap_history)];
end

function value = scaled_error(actual, expected)
    assert(isequal(size(actual), size(expected)), '参考数据尺寸不一致。');
    value = max(abs(actual(:) - expected(:))) / max(1, max(abs(expected(:))));
    assert(isfinite(value), '出现非有限结果。');
end
