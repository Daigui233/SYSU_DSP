function output = cma_filter_block(window, spectra, plan, config)
%CMA_FILTER_BLOCK 两路重叠保留滤波；spectra 四列依次为 xx、xy、yx、yy。
%   window 按时间正序存放 M-1 个历史点和 B 个新点，每列一路。
    padded = [window; zeros(config.fft_points - size(window, 1), 2)];
    input_x = fft_iterative(padded(:, 1), plan);
    input_y = fft_iterative(padded(:, 2), plan);
    % 滤波为普通复数卷积，不对输入或抽头取共轭。
    output_x = ifft_iterative(spectra(:, 1) .* input_x + spectra(:, 2) .* input_y, plan);
    output_y = ifft_iterative(spectra(:, 3) .* input_x + spectra(:, 4) .* input_y, plan);
    % 丢弃 M-1 个混叠点，固定取 B=32 点；额外 FFT 补零不改变更新节奏。
    valid = config.tap_len:config.tap_len + config.seg_len - 1;
    output = [output_x(valid), output_y(valid)];
end
