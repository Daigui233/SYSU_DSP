function test_ifft_sizes
%TEST_IFFT_SIZES 验证 32/64/128 点 IFFT 封装及复数 FFT 的线性分解。
    module_directory = fileparts(fileparts(mfilename('fullpath')));
    original_path = path;
    restore_path = onCleanup(@() path(original_path));
    addpath(fullfile(module_directory, 'src'));

    plan = fft_plan(128);
    points = [32, 64, 128];
    forward = {@fft32, @fft64, @fft128};
    inverse = {@ifft32, @ifft64, @ifft128};
    names = {'zero'; 'dc_bin'; 'last_bin'; 'constant'; 'real_random'; 'complex_random'};
    stream = RandStream('mt19937ar', 'Seed', 20261115);
    tolerance = 1e-12;
    errors = zeros(18, 7);
    tested_points = zeros(18, 1);
    tested_cases = cell(18, 1);
    row = 0;

    for size_index = 1:numel(points)
        n = points(size_index);
        fft_function = forward{size_index};
        ifft_function = inverse{size_index};
        inputs = [zeros(n, 1), [1; zeros(n - 1, 1)], [zeros(n - 1, 1); 1], ...
                  ones(n, 1), randn(stream, n, 1), ...
                  randn(stream, n, 1) + 1i * randn(stream, n, 1)];
        for case_index = 1:numel(names)
            spectrum = inputs(:, case_index);
            % 正指数矩阵直接表达 IDFT 定义，不复用被测的共轭 FFT 公式。
            sample = (0:n - 1).';
            reference = exp(2i * pi * (sample * sample.') / n) * spectrum / n;
            signal = ifft_function(spectrum, plan);
            row_signal = ifft_function(spectrum.', plan);
            forward_roundtrip = fft_function(signal, plan);
            inverse_roundtrip = ifft_function(fft_function(spectrum, plan), plan);
            % 检查复数 FFT 等于两路实数 FFT 的线性组合，不另建复数核心。
            split = fft_function(real(spectrum), plan) ...
                    + 1i * fft_function(imag(spectrum), plan);
            assert(isequal(size(signal), [n, 1]) && ...
                   isequal(size(row_signal), [n, 1]), 'IFFT 输出形状不正确。');

            row = row + 1;
            tested_points(row) = n;
            tested_cases{row} = names{case_index};
            absolute_error = max(abs(signal - reference));
            errors(row, :) = [absolute_error, ...
                absolute_error / max(1, max(abs(reference))), ...
                max(abs(signal - row_signal)), ...
                max(abs(forward_roundtrip - spectrum)) / max(1, max(abs(spectrum))), ...
                max(abs(inverse_roundtrip - spectrum)) / max(1, max(abs(spectrum))), ...
                max(abs(split - fft_function(spectrum, plan))) / max(1, max(abs(split))), ...
                max(abs(inverse_roundtrip - spectrum))];
        end
    end
    % 同时验证独立 IDFT、两种往返方向和复数分解，避免错误相互抵消。
    checked = errors(:, [2, 4, 5, 6]);
    assert(all(checked(:) < tolerance) && all(errors(:, 3) == 0), 'IFFT 验证失败。');
    summary = array2table(errors, 'VariableNames', {'idft_absolute_error', ...
        'idft_scaled_error', 'row_column_difference', 'fft_ifft_scaled_error', ...
        'ifft_fft_scaled_error', 'complex_split_scaled_error', 'roundtrip_absolute_error'});
    summary = addvars(summary, tested_points, tested_cases, 'Before', 1, ...
        'NewVariableNames', {'point_count', 'case_name'});
    writetable(summary, fullfile(module_directory, 'results', 'ifft_sizes_errors.csv'));
    fprintf('PASS: IFFT 18 cases; max IDFT scaled error %.3e; max roundtrip %.3e\n', ...
            max(errors(:, 2)), max(errors(:, 7)));
end
