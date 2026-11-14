function config = cma_config(tap_len)
%CMA_CONFIG 保留教师参考参数，只允许实验改变奇数抽头长度。
    config.tap_len = tap_len;
    config.seg_len = 32;
    config.par_num = 4;
    config.clk_dly = 1;  % 本版仅实现参考默认的一个时钟延迟
    config.step = 2^-8;
    config.Rx = 2;
    config.Ry = 2;
    % 32 个新点加 M-1 个历史点；选择现有模块支持的 FFT 长度。
    config.fft_points = 2^ceil(log2(config.seg_len + tap_len - 1));
end
