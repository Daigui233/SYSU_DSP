function test_fft8
%TEST_FFT8 运行 8 点底层验证，保存最终误差数据；不调用内置 FFT/IFFT。
%   仓库根目录运行：addpath('basic/tests'); test_fft8

    % 从测试文件自身定位 basic/，不将机器相关的绝对路径写入仓库。
    module_directory = fileparts(fileparts(mfilename('fullpath')));
    original_path = path;
    % 测试结束或中途报错时恢复搜索路径，不影响用户后续 MATLAB 会话。
    restore_path = onCleanup(@() path(original_path));
    addpath(fullfile(module_directory, 'src'));

    point_count = 8;
    % 当前固定输入规模较小，以最大绝对误差判断是否通过。
    tolerance = 1e-12;
    % 8 点配置只初始化一次，后面的所有用例共用；另测较大配置的复用。
    plan = fft_plan(point_count);

    % 独立核对倒位序与分层系数，避免两个 FFT 共用错误底层却相互吻合。
    expected_order = [1; 5; 3; 7; 2; 6; 4; 8];
    assert(isequal(plan.input_orders{3}, expected_order), '8 点倒位序不正确。');
    % 8 点仅需 W2、W4、W8 三行；不应生成更高层或全局基准表。
    assert(isequal(plan.stage_points, [2; 4; 8]), '8 点配置的层数不正确。');
    twiddle_error = 0;
    % 按定义独立计算每层因子，不复用被测的象限对称生成过程。
    for stage = 1:numel(plan.stage_weights)
        block_length = 2^stage;
        reference_stage = exp(-2i * pi * (0:block_length / 2 - 1).' / block_length);
        stage_error = max(abs(plan.stage_weights{stage} - reference_stage));
        twiddle_error = max(twiddle_error, stage_error);
        assert(stage_error < tolerance, '初始化生成的层系数不正确。');
    end

    % 保存初始化结果后重新载入；下面两种 FFT 只使用此配置，不再计算因子。
    plan_file = fullfile(module_directory, 'results', 'fft8_plan.mat');
    save(plan_file, 'plan');
    % load 返回含 plan 字段的结构体；取出配置后直接传入两个实现。
    saved = load(plan_file, 'plan');
    plan = saved.plan;

    % 另准备一次最大 128 点的共享配置，仍只用 8 点输入验证选择逻辑。
    % 直接检查第 3 行的排列，防止误用或截取 128 点倒位序。
    shared_plan = fft_plan(128);
    assert(isequal(shared_plan.input_orders{3}, expected_order), ...
           '共享配置未保存正确的 8 点倒位序。');

    % 用可手算的 1 和 -j 检查蝶形乘法及上下路的加减符号。
    [upper, lower] = fft_butterfly([1; 1], [2; 2], [1; -1i]);
    assert(isequal(upper, [3; 1 - 2i]) && ...
           isequal(lower, [-1; 1 + 2i]), '蝶形基本运算不正确。');

    sample_index = (0:point_count - 1).';
    % 每列是一组输入，依次覆盖：零位冲激、移位冲激、直流、斜坡、
    % 第 3 个频点的复指数，以及非对称的一般复数序列。
    signals = [ ...
        [1; zeros(7, 1)], ...
        [0; 1; zeros(6, 1)], ...
        ones(point_count, 1), ...
        sample_index, ...
        exp(2i * pi * 3 * sample_index / point_count), ...
        [1 + 2i; -3 + 0.5i; 2 - 1i; 0; -0.5 - 2i; 4 + 3i; 1i; -2]];
    case_names = {'impulse'; 'shifted_impulse'; 'constant'; ...
                  'ramp'; 'complex_tone'; 'complex_mixed'};
    % 前五列保留 DFT 对照、方法间差异及往返误差；最后两列检查
    % 使用 128 点共享配置时，8 点计算是否仍与独立 DFT 一致。
    errors = zeros(numel(case_names), 7);

    % 仅验证逆变换复用方案，当前阶段不额外添加 IFFT 封装。
    inverse_plan = plan;
    % 每层系数取共轭，将 FFT 的负指数变为 IFFT 的正指数。
    for stage = 1:numel(plan.stage_weights)
        inverse_plan.stage_weights{stage} = conj(plan.stage_weights{stage});
    end

    for case_index = 1:numel(case_names)
        signal = signals(:, case_index);
        % 独立 DFT 作正确性基准，不能只靠两种 FFT 相等来判断正确。
        reference = dft_reference(signal);
        recursive = fft_recursive(signal, plan);
        iterative = fft_iterative(signal, plan);
        shared_recursive = fft_recursive(signal, shared_plan);
        shared_iterative = fft_iterative(signal, shared_plan);
        % 逆变换复用原核心，仅在最外层除以 N 一次，恢复原输入。
        restored_recursive = fft_recursive(recursive, inverse_plan) / point_count;
        restored_iterative = fft_iterative(iterative, inverse_plan) / point_count;
        % abs 对复数差求模，max 取所有频点或采样点中的最坏误差。
        errors(case_index, :) = [ ...
            max(abs(recursive - reference)), ...
            max(abs(iterative - reference)), ...
            max(abs(recursive - iterative)), ...
            max(abs(restored_recursive - signal)), ...
            max(abs(restored_iterative - signal)), ...
            max(abs(shared_recursive - reference)), ...
            max(abs(shared_iterative - reference))];
    end

    % 数值检查全部通过后才导出最终误差，避免将失败结果作为验收数据。
    assert(all(errors(:) < tolerance), '8 点 FFT 或逆变换误差超过阈值。');
    summary = array2table(errors, 'VariableNames', { ...
        'recursive_dft_error', 'iterative_dft_error', 'methods_difference', ...
        'recursive_roundtrip_error', 'iterative_roundtrip_error', ...
        'shared_recursive_dft_error', 'shared_iterative_dft_error'});
    % 给数值附上用例名和指标名，便于人工直接审查 CSV。
    summary = addvars(summary, case_names, 'Before', 1, 'NewVariableNames', 'case_name');
    writetable(summary, fullfile(module_directory, 'results', 'fft8_errors.csv'));
    disp(summary);
    fprintf('PASS: 8-point FFT; tolerance %.1e; twiddle error %.3e\n', ...
            tolerance, twiddle_error);
    fprintf('MATLAB %s\n', version);
end
