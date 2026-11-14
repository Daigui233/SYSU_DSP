function result = cma_reference_oracle(input, tap_count)
%CMA_REFERENCE_ORACLE 执行教师脚本的原始计算段，不复制或改写更新算法。
%   唯一参数替换为 tap_len，便于验证另外两种抽头；源文件保持不变。
    root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    source = fileread(fullfile(root, 'reference', '大作业matlab', 'CMA_reference.m'));
    first = strfind(source, '%% Parameters');
    last = strfind(source, '%% Figure and Results');
    calculation = source(first(1):last(1) - 1);
    calculation = strrep(calculation, 'tap_len     = 33;', sprintf('tap_len     = %d;', tap_count));
    % 只跳过 load/绘图，输入原样传给原脚本的同名变量。
    SigX_in = input(:, 1); %#ok<NASGU> 由下方原脚本计算段读取
    SigY_in = input(:, 2); %#ok<NASGU>
    timer = tic;
    eval(calculation);
    result.seconds = toc(timer);
    result.output = [SigX_out, SigY_out];
    result.errors = [errx_vec, erry_vec];
    result.tap_history = permute(cat(3, xx, xy, yx, yy), [1, 3, 2]);
    result.last_used_taps = [final_xx, final_xy, final_yx, final_yy];
end
