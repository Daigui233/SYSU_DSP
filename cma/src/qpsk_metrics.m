function [metrics, aligned] = qpsk_metrics(signal)
%QPSK_METRICS 判决辅助 EVM：无发送符号参考，不代表真实 BER 或参考符号 EVM。
%   仅在评价时按均方功率归一化和四阶矩估计常相位，不反馈给 CMA。
    signal = signal(:);
    metrics.power = mean(abs(signal).^2);
    normalized = signal * sqrt(2 / metrics.power);
    % 理想角点 (±1±j)^4=-4；取 -E[z^4] 的相角后除以4，存在90度模糊。
    % 最近点 EVM 不受这一90度星座对称影响，但不能据此恢复比特映射。
    metrics.phase = angle(-mean(normalized.^4)) / 4;
    aligned = normalized * exp(-1i * metrics.phase);
    decision = (2 * (real(aligned) >= 0) - 1) + 1i * (2 * (imag(aligned) >= 0) - 1);
    metrics.evm_percent = 100 * sqrt(mean(abs(aligned - decision).^2) / 2);
    metrics.modulus_cost = mean((2 - abs(signal).^2).^2); % 使用未处理的原输出
end
