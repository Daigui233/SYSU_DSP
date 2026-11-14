function summary = analyze_cma(input, results, directory)
%ANALYZE_CMA 统一末尾统计区间，输出判决辅助 EVM、恒模代价和实际曲线。
%   results 按实验顺序存放；图中平滑仅用于展示，不改变训练。
    experiments = numel(results);
    labels = cell(experiments + 1, 1);
    labels{1} = 'Before';
    for experiment = 1:experiments
        labels{experiment + 1} = sprintf('%d taps', results{experiment}.config.tap_len);
    end
    count = 131072;
    tail = size(input, 1) - count + 1:size(input, 1);
    before = zeros(1, 2);
    before_cost = zeros(1, 2);
    raw = cell(experiments + 1, 1);
    aligned = cell(experiments + 1, 1);
    raw{1} = input(tail, :);
    aligned{1} = complex(zeros(count, 2));
    for polarization = 1:2
        [metric, aligned{1}(:, polarization)] = qpsk_metrics(raw{1}(:, polarization));
        before(polarization) = metric.evm_percent;
        before_cost(polarization) = metric.modulus_cost;
    end
    values = zeros(experiments, 13);
    phase_statistics = zeros(experiments * 2, 5);
    phase_tracks = cell(experiments, 1);
    for experiment = 1:experiments
        result = results{experiment};
        raw{experiment + 1} = result.output(tail, :);
        aligned{experiment + 1} = complex(zeros(count, 2));
        phase_tracks{experiment} = zeros(count, 2);
        evm = zeros(1, 2);
        cost = zeros(1, 2);
        for polarization = 1:2
            [metric, aligned{experiment + 1}(:, polarization)] = qpsk_metrics(raw{experiment + 1}(:, polarization));
            evm(polarization) = metric.evm_percent;
            cost(polarization) = metric.modulus_cost;
            % 离线诊断环状星座：四次方消除理想QPSK的90度跳变，再观察相位走势。
            % 此估计不用于修正输出或EVM，不把它当作已知频偏真值。
            signal = raw{experiment + 1}(:, polarization);
            phase_trace = unwrap(angle(-signal.^4)) / 4;
            sample = (0:count - 1).';
            fit = polyfit(sample, phase_trace, 1);
            coherence = abs(mean((signal ./ abs(signal)).^4));
            phase_statistics((experiment - 1) * 2 + polarization, :) = ...
                [result.config.tap_len, polarization, fit(1) / (2 * pi), ...
                 std(phase_trace - polyval(fit, sample)), coherence];
            phase_tracks{experiment}(:, polarization) = phase_trace;
        end
        % 统一速度指标：50组后向均值，两路代价均低于0.1并连续维持50组。
        % 阈值事先固定；未达到时记录 NaN，不把末端位置当作收敛时间。
        smoothed = movmean(result.cost, [49, 0], 1);
        below = all(smoothed < 0.1, 2);
        convergence = NaN;
        for clock = 99:numel(below)
            if all(below(clock - 49:clock))
                convergence = clock * 128;
                break;
            end
        end
        % 高相关可能提示两路恢复了重复分量；它只是诊断，不能代替已知发送符号。
        cross_correlation = max_lag_correlation(raw{experiment + 1}, 64);
        taps = result.last_used_taps;
        % 短抽头的两侧不能重叠计数；每侧最多4点，保留中心点不计入边缘。
        edge = min(4, floor(size(taps, 1) / 2));
        edge_energy = sum(abs(taps([1:edge, end-edge+1:end], :)).^2, 'all') / sum(abs(taps).^2, 'all');
        values(experiment, :) = [result.config.tap_len, result.config.fft_points, ...
            evm, cost, convergence, median(result.update_norm(end-1023:end)), ...
            cross_correlation, edge_energy, result.seconds, size(result.output, 1), ...
            sum(isfinite(result.update_norm))];
        curve = table((1:size(result.cost, 1)).', (1:size(result.cost, 1)).' * 128, ...
            result.cost(:, 1), result.cost(:, 2), result.update_norm, ...
            'VariableNames', {'update_index', 'processed_samples', 'cost_x', 'cost_y', 'update_norm'});
        writetable(curve, fullfile(directory, sprintf('convergence_%d.csv', result.config.tap_len)));
    end
    summary = array2table(values, 'VariableNames', {'tap_count', 'fft_points', ...
        'evm_x_percent', 'evm_y_percent', 'steady_cost_x', 'steady_cost_y', ...
        'threshold_samples', 'steady_update_norm', 'max_xy_correlation_lag64', ...
        'edge_energy_fraction', 'seconds', 'processed_samples', 'update_count'});
    writetable(summary, fullfile(directory, 'comparison.csv'));
    writetable(table(before(1), before(2), before_cost(1), before_cost(2), count, 'VariableNames', ...
        {'evm_x_percent', 'evm_y_percent', 'cost_x', 'cost_y', 'evaluation_samples'}), ...
        fullfile(directory, 'input_metrics.csv'));
    phase_table = array2table(phase_statistics, 'VariableNames', ...
        {'tap_count', 'polarization_1x_2y', 'estimated_cycles_per_sample', ...
         'linear_fit_residual_rad', 'fourth_moment_coherence'});
    writetable(phase_table, fullfile(directory, 'phase_diagnostics.csv'));

    % 所有星座图使用同样数量的确定性抽样点、坐标范围与比例。
    selected = round(linspace(1, count, 6000));
    for view = 1:2
        figure_handle = figure('Visible', 'off', 'Position', [100, 100, 1000, 250 * (experiments + 1)]);
        for row = 1:experiments + 1
            for polarization = 1:2
                subplot(experiments + 1, 2, (row - 1) * 2 + polarization);
                if view == 1
                    points = raw{row}(selected, polarization);
                else
                    points = aligned{row}(selected, polarization);
                end
                plot(real(points), imag(points), '.', 'MarkerSize', 2);
                axis equal; xlim([-2.5, 2.5]); ylim([-2.5, 2.5]); grid on;
                title(sprintf('%s / %s', labels{row}, char('X' + polarization - 1)));
                xlabel('In-phase'); ylabel('Quadrature');
            end
        end
        if view == 1
            sgtitle('Raw constellations: last 131072 samples, 6000 displayed');
            filename = 'constellations_raw.png';
        else
            sgtitle('Evaluation-only RMS normalization and constant-phase alignment');
            filename = 'constellations_aligned.png';
        end
        exportgraphics(figure_handle, fullfile(directory, filename), 'Resolution', 140);
        close(figure_handle);
    end

    figure_handle = figure('Visible', 'off', 'Position', [100, 100, 1150, 450]);
    for polarization = 1:2
        subplot(1, 2, polarization); hold on;
        for experiment = 1:experiments
            curve = movmean(results{experiment}.cost(:, polarization), [49, 0]);
            semilogy((1:numel(curve)) * 128, curve, 'LineWidth', 1);
        end
        yline(0.1, '--k', 'Common threshold', 'HandleVisibility', 'off'); grid on;
        set(gca, 'YScale', 'log');
        xlabel('Processed sample pairs'); ylabel('Mean squared modulus error');
        title(sprintf('%s polarization / trailing 50-group mean', char('X' + polarization - 1)));
        legend(labels(2:end), 'Location', 'best');
    end
    exportgraphics(figure_handle, fullfile(directory, 'convergence.png'), 'Resolution', 150);
    % 同一数据增加起始区间视图，避免全长横轴压缩早期下降过程。
    for polarization = 1:2
        subplot(1, 2, polarization); xlim([0, 64000]);
    end
    exportgraphics(figure_handle, fullfile(directory, 'convergence_start.png'), 'Resolution', 150);
    close(figure_handle);

    figure_handle = figure('Visible', 'off', 'Position', [100, 100, 850, 450]);
    bar([before; values(:, 3:4)]); grid on;
    xticks(1:experiments + 1); xticklabels(labels); ylabel('Decision-directed RMS EVM (%)');
    legend('X', 'Y'); title('Same evaluation: last 131072 samples, normalized and phase-aligned');
    exportgraphics(figure_handle, fullfile(directory, 'evm_comparison.png'), 'Resolution', 150);
    close(figure_handle);

    figure_handle = figure('Visible', 'off', 'Position', [100, 100, 1050, 700]);
    names = {'xx', 'xy', 'yx', 'yy'};
    for channel = 1:4
        subplot(2, 2, channel); hold on;
        for experiment = 1:experiments
            taps = results{experiment}.last_used_taps;
            position = (1:size(taps, 1)) - (size(taps, 1) + 1) / 2;
            plot(position, abs(taps(:, channel)), '-o', 'MarkerSize', 2);
        end
        grid on; title(names{channel}); xlabel('Tap index relative to initial center'); ylabel('Magnitude');
        legend(labels(2:end));
    end
    exportgraphics(figure_handle, fullfile(directory, 'tap_magnitudes.png'), 'Resolution', 150);
    close(figure_handle);

    figure_handle = figure('Visible', 'off', 'Position', [100, 100, 1100, 450]);
    for polarization = 1:2
        subplot(1, 2, polarization); hold on;
        for experiment = 1:experiments
            phase = phase_tracks{experiment}(1:4096, polarization);
            plot(0:4095, phase - phase(1), 'LineWidth', 1);
        end
        grid on; xlabel('Sample offset within evaluation tail'); ylabel('Unwrapped fourth-power phase / 4 (rad)');
        title(sprintf('%s: phase diagnostic only, no compensation applied', char('X' + polarization - 1)));
        legend(labels(2:end));
    end
    exportgraphics(figure_handle, fullfile(directory, 'phase_evolution.png'), 'Resolution', 150);
    close(figure_handle);
    disp(summary);
    fprintf('Before: decision-directed EVM X=%.3f%%, Y=%.3f%%\n', before);
end

function value = max_lag_correlation(signal, max_lag)
    signal = signal - mean(signal, 1);
    value = 0;
    for lag = -max_lag:max_lag
        first = max(1, 1 - lag);
        last = min(size(signal, 1), size(signal, 1) - lag);
        x = signal(first:last, 1);
        y = signal(first + lag:last + lag, 2);
        correlation = abs(x' * y) / sqrt(real(x' * x) * real(y' * y));
        value = max(value, correlation);
    end
end
