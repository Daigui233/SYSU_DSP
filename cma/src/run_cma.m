function summary = run_cma(tap_counts)
%RUN_CMA 以33抽头为参考，向下比较5/9/17/33抽头，验证后绘图。
%   仓库根目录：addpath('cma/src'); run_cma
%   可用 run_cma([5, 9, 17, 33]) 指定对比组；其中应包含参考的33抽头。
    if nargin == 0
        tap_counts = [5, 9, 17, 33];
    end
    module = fileparts(fileparts(mfilename('fullpath')));
    root = fileparts(module);
    original_path = path;
    restore_path = onCleanup(@() path(original_path));
    addpath(fullfile(root, 'basic', 'src'), fullfile(module, 'tests'));
    test_qpsk_metrics;
    result33 = test_cma(tap_counts);
    data = load(fullfile(root, 'reference', '大作业matlab', 'TD_TRdata.mat'));
    input = [data.RTdataX(:), data.RTdataY(:)];
    plan = fft_plan(2^ceil(log2(max(tap_counts) + 31)));
    results = cell(numel(tap_counts), 1);
    results{tap_counts == 33} = result33;
    directory = fullfile(module, 'results');
    validation = readtable(fullfile(directory, 'validation.csv'));
    for experiment = find(tap_counts ~= 33)
        fprintf('Full experiment: %d taps\n', tap_counts(experiment));
        results{experiment} = cma_equalize(input, cma_config(tap_counts(experiment)), plan);
        assert(all(isfinite(results{experiment}.output(:))), '实验输出出现非有限值。');
        % 其他抽头也执行同一教师计算段，只替换 tap_len，完成全量对照。
        reference = cma_reference_oracle(input, tap_counts(experiment));
        fields = {'output', 'errors', 'tap_history'};
        differences = zeros(1, 3);
        for field = 1:3
            actual = results{experiment}.(fields{field});
            expected = reference.(fields{field});
            differences(field) = max(abs(actual(:) - expected(:))) / max(1, max(abs(expected(:))));
        end
        assert(all(differences < 1e-9), '全量抽头对比未通过参考验证。');
        % 对照实验控制样本数及更新次数，FFT长度变化不能改变更新节奏。
        assert(isequal(size(results{experiment}.output), size(result33.output)) && ...
               isequal(size(results{experiment}.cost), size(result33.cost)), ...
               '不同抽头实验的样本数或更新次数不一致。');
        validation(end + 1, :) = [{tap_counts(experiment), 'full_reference'}, num2cell(differences)]; %#ok<AGROW>
        fprintf('PASS full %d-tap reference: output %.3e, taps %.3e\n', ...
                tap_counts(experiment), differences(1), differences(3));
    end
    writetable(validation, fullfile(directory, 'validation.csv'));
    for experiment = 1:numel(tap_counts)
        % 最终结果保留完整输出、误差、统计及最终抽头；逐时钟抽头只用于验证。
        result = rmfield(results{experiment}, 'tap_history');
        result.matlab_version = version;
        save(fullfile(directory, sprintf('cma_%d.mat', result.config.tap_len)), 'result', '-v7');
    end
    summary = analyze_cma(input, results, directory);
end
