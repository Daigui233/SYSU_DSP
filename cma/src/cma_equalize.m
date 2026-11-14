function result = cma_equalize(input, config, plan)
%CMA_EQUALIZE 双路频域 CMA；input 每列一路，使用参考的 clk_dly=1 规则。
%   输出与截断到完整 32 点块的输入等长，不额外输出卷积尾部。
    timer = tic;
    blocks = floor(size(input, 1) / config.seg_len);
    clocks = ceil(blocks / config.par_num);
    total = blocks * config.seg_len;
    padded = [zeros(config.tap_len - 1, 2); input(1:total, :)];
    result.output = complex(zeros(total, 2));
    result.errors = zeros(total, 2);
    % 保留各时钟抽头以便与教师参考逐列核对，列顺序为 xx、xy、yx、yy。
    history = complex(zeros(config.tap_len, 4, clocks + config.clk_dly));
    history((config.tap_len + 1) / 2, [1, 4], :) = 1;
    accumulator = complex(zeros(config.tap_len, 4));
    update_norm = nan(clocks, 1); % 最后不足四块时，参考也不会执行更新
    spectra = complex(zeros(config.fft_points, 4));

    for block = 1:blocks
        clock = ceil(block / config.par_num);
        if mod(block - 1, config.par_num) == 0
            % 同一时钟的四块复用当前抽头；仅进入下一组时刷新频谱。
            taps = history(:, :, clock);
            for channel = 1:4
                spectra(:, channel) = fft_iterative( ...
                    [taps(:, channel); zeros(config.fft_points - config.tap_len, 1)], plan);
            end
        end
        first = (block - 1) * config.seg_len + 1;
        indices = first:first + config.seg_len - 1;
        window = padded(first:first + config.tap_len + config.seg_len - 2, :);
        output = cma_filter_block(window, spectra, plan, config);
        [accumulator, errors] = cma_update(window, output, accumulator, config);
        result.output(indices, :) = output;
        result.errors(indices, :) = errors;

        if mod(block, config.par_num) == 0
            % 参考除以并行块数 4，不是除以样本数 128；下一组才使用新抽头。
            next = clock + config.clk_dly;
            increment = accumulator / config.par_num;
            history(:, :, next) = history(:, :, next - 1) + increment;
            update_norm(clock) = norm(increment, 'fro');
            accumulator(:) = 0;
            if mod(clock, 1000) == 0
                fprintf('CMA M=%d: %d/%d groups\n', config.tap_len, clock, clocks);
            end
        end
    end
    % 统计只用于分析，不反馈到抽头更新。最后不足四块则按实际样本数平均。
    cost = zeros(clocks, 2);
    for clock = 1:clocks
        first = (clock - 1) * config.par_num * config.seg_len + 1;
        last = min(clock * config.par_num * config.seg_len, total);
        cost(clock, :) = mean(result.errors(first:last, :).^2, 1);
    end
    result.config = config;
    result.cost = cost;
    result.update_norm = update_norm;
    result.tap_history = history;
    result.last_used_taps = history(:, :, clocks); % 对应参考的 final_xx 等变量
    result.last_updated_taps = history(:, :, floor(blocks / config.par_num) + 1);
    result.seconds = toc(timer);
end
