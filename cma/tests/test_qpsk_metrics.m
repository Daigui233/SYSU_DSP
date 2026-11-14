function test_qpsk_metrics
%TEST_QPSK_METRICS 已知理想星座在任意固定增益/相位下应给出近零 EVM。
    symbols = repmat([1+1i; 1-1i; -1+1i; -1-1i], 1024, 1);
    metrics = qpsk_metrics(3 * symbols * exp(0.31i));
    assert(metrics.evm_percent < 1e-10, '理想星座相位/增益校正失败。');
    stream = RandStream('mt19937ar', 'Seed', 20261118);
    noisy = symbols + 0.1 * (randn(stream, size(symbols)) + 1i * randn(stream, size(symbols)));
    metrics = qpsk_metrics(noisy);
    assert(metrics.evm_percent > 0 && metrics.evm_percent < 20, '加噪星座评价异常。');
    fprintf('PASS: QPSK evaluation; noisy sanity EVM %.3f%%\n', metrics.evm_percent);
end
