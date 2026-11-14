function [accumulator, errors] = cma_update(window, output, accumulator, config)
%CMA_UPDATE 按参考逐样本顺序累积梯度，不在块内修改抽头。
    errors = [config.Rx - abs(output(:, 1)).^2, config.Ry - abs(output(:, 2)).^2];
    for sample = 1:config.seg_len
        % 当前到过去的 M 点窗口，与参考 padded_idx:-1:... 完全相同。
        indices = sample + config.tap_len - 1:-1:sample;
        input_x = window(indices, 1);
        input_y = window(indices, 2);
        % 列顺序 xx、xy、yx、yy；step 的位置与参考一致，避免额外平均。
        accumulator(:, 1) = accumulator(:, 1) + config.step * errors(sample, 1) * output(sample, 1) * conj(input_x);
        accumulator(:, 4) = accumulator(:, 4) + config.step * errors(sample, 2) * output(sample, 2) * conj(input_y);
        accumulator(:, 2) = accumulator(:, 2) + config.step * errors(sample, 1) * output(sample, 1) * conj(input_y);
        accumulator(:, 3) = accumulator(:, 3) + config.step * errors(sample, 2) * output(sample, 2) * conj(input_x);
    end
end
