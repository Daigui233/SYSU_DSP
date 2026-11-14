# 基础模块

## For Human

已完成 32/64/128 点 FFT、IFFT 独立封装，以及直接线性卷积、短序列快速卷积、重叠相加（OLA）、重叠保留（OLS）。支持实数和复数，统一输出列向量；尚未进行性能评测或接入自适应 CMA。

在仓库根目录调用，`x32` 为 32 点向量；`x`、`h` 为非空输入及卷积核：

```matlab
addpath('basic/src');
plan = fft_plan(128);       % 初始化一次，各模块共用
X = fft32(x32, plan);       % 另有 fft64、fft128
restored = ifft32(X, plan); % 另有 ifft64、ifft128

y_linear = conv_linear(x, h);
y_fft = conv_fft(x, h, plan, 64); % 要求 length(x)+length(h)-1 <= 64
y_ola = conv_ola(x, h, plan, 64); % 要求 length(h) <= 64，输入可更长
y_ols = conv_ols(x, h, plan, 64);
```

固定点数封装不自动补零或截断。卷积模块负责补零，返回完整的 `length(x)+length(h)-1` 点结果，保留复数值；固定核频谱在每次 OLA/OLS 调用内复用。

运行全部测试：

```matlab
addpath('basic/tests');
test_fft8;
test_fft_sizes;
test_ifft_sizes;
test_convolution;
```

MATLAB R2025a Update 1 验证结果如下，阈值为 `1e-12`：

| 验证范围 | 数量 | 最大误差 |
| --- | --- | --- |
| 8 点 FFT | 6 组输入 | DFT 绝对误差 `2.54e-14` |
| 32/64/128 点 FFT | 18 组输入 | DFT 归一化误差 `1.37e-13` |
| 32/64/128 点 IFFT | 18 组输入 | IDFT 归一化误差 `5.67e-15` |
| 四种卷积方法 | 156 项检查 | 归一化误差 `6.06e-16` |

测试覆盖行列输入、正逆往返、复数 FFT 的实虚部分解，以及卷积的首尾边界、整块/末块不足、单点核、核长等于 FFT 长度和两路 CMA 数据片段。卷积核固定；CMA 自适应更新尚未验证。

最终数据：[8 点 FFT](results/fft8_errors.csv)、[FFT 封装](results/fft_sizes_errors.csv)、[IFFT 封装](results/ifft_sizes_errors.csv)、[卷积](results/convolution_errors.csv)。复用配置：`results/fft8_plan.mat`、`results/fft128_plan.mat`。

## For Agent

- 遵循根目录 README；各级 README 保持 `For Human`、`For Agent` 两部分，内容简洁。
- 保持分层：`fft_plan` 初始化，`fft_butterfly` 共用蝶形，`fft_iterative` / `fft_recursive` 为核心；`ifft_iterative` 用 `conj(FFT(conj(X)))/N` 复用迭代 FFT。固定点数入口只负责形状约定，不重复实现算法。
- `plan` 按最大点数初始化一次，按层保存 `stage_points`、`stage_weights`、`input_orders`；只计算第四象限，用对称性补齐。实际输入决定使用的层数和排列，计算时不重新生成配置。
- 通用 FFT/IFFT 输入长度为配置支持的 2 的幂且至少为 2；IFFT 仅归一化一次。卷积的 `fft_points` 同样需受配置支持；短卷积要求 N≥Lx+M−1，OLA/OLS 要求 N≥M，并以 B=N−M+1 分块。
- `conv_linear` 按反折、移位、相乘求和计算，不取共轭；`conv_fft` 补零后频域相乘。OLA 累加重叠输出，OLS 丢弃前 M−1 点并拼接有效输出，末尾补零输出完整卷积尾部。
- 参考 CMA 输入为复数，抽头也可为复数；不要取实部或误用共轭转置。当前卷积模块采用固定核，接入 CMA 时须按抽头更新时机重算频谱并保持原更新节奏。
- 代码和具体操作均需注释，避免重复变量与重复实现；新增参数校验先与用户讨论，不额外添加保护逻辑。
- 禁用内置 `fft/ifft/conv`。测试用直接 DFT、正指数 IDFT 和移位累加基准独立验证；除 8 点绝对误差外，按 `最大绝对误差 / max(1, 基准最大幅度)` 判定，往返以原输入作基准。
- 修改后运行相关测试；`results/` 只保留最终数据和复用配置，临时日志和缓存不纳入提交。
