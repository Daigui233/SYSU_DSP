function plan = fft_plan(max_points)
%FFT_PLAN 按 W2、W4、...、WN 分层准备旋转因子和倒位序索引。
%   max_points 为最大支持点数，取不超过 128 的 2 的幂（至少为 2）。
%   每层同时保存旋转因子与对应点数的倒位序排列，供较小点数共用。

    plan.max_points = max_points;   % 初始化的最大点数，不是每次输入的长度
    stage_count = log2(max_points); % 需要准备的总层数

    % 三列按层对应：点数、旋转因子、该点数的倒位序排列。
    % 例如 8 点只有三行：W2、W4、W8，不生成 W16 及更高层。
    plan.stage_points = 2.^(1:stage_count).';
    % 每层系数数量不同，用 cell 分行存放
    plan.stage_weights = cell(stage_count, 1);
    plan.input_orders = cell(stage_count, 1);
    for stage = 1:stage_count
        block_length = plan.stage_points(stage);
        % 例如 W8 这一行同时保存 3 位倒位序，W16 保存 4 位倒位序。
        % 每种排列只在初始化时计算；不能用较大点数排列直接截取代替。
        plan.input_orders{stage} = bit_reverse_indices(block_length);

        % W2 只需 W2^0=1；这是最底层蝶形，无需三角函数计算。
        if block_length == 2
            plan.stage_weights{stage} = 1;
            continue;
        end

        % 欧拉公式 exp(-j*theta)=cos(theta)-j*sin(theta)，直接计算第四象限。
        % 实部为 cos(theta)，虚部为 -sin(theta)；轴上直接赋值 1、-j。
        % 例如 W8 只需计算 theta=pi/4；W4 没有象限内部的点。
        angle = 2 * pi * (1:block_length / 4 - 1).' / block_length;
        fourth_quadrant = [1; cos(angle) - 1i * sin(angle); -1i];

        % 前一段直接使用第四象限及轴上系数，覆盖 k=0:M/4。
        % 后一段将内部点倒序，再镜像到第三象限，覆盖 k=M/4+1:M/2-1。
        % -conj(a+jb)=-a+jb：只取反实部，虚部不变；不能把两者同时取反。
        % end-1:-1:2 排除轴上端点，避免重复；对应 W_M^(M/2-k)=-conj(W_M^k)。
        plan.stage_weights{stage} = [fourth_quadrant; ...
                                    -conj(fourth_quadrant(end - 1:-1:2))];
        % 每层仅存 k=0:M/2-1；另一半由蝶形减法利用 W^(k+M/2)=-W^k 得到。
    end
end

function order = bit_reverse_indices(point_count)
% 逐次取最低位并追加到反转下标，最后转换成 MATLAB 的 1-based 下标。
    % 固定反转 log2(N) 位，包含前导零；例如 8 点的 001 反转为 100。
    bit_count = log2(point_count);
    order = zeros(point_count, 1);
    for index = 0:point_count - 1
        % remaining 保存尚未处理的位，reversed 累积已反转的位。
        remaining = index;
        reversed = 0;
        for bit = 1:bit_count
            % 将结果左移一位，并把原下标的最低位追加到末尾。
            reversed = 2 * reversed + mod(remaining, 2);
            % 去掉已读取的最低位，下一轮继续处理更高位。
            remaining = floor(remaining / 2);
        end
        % 数学下标均从 0 开始；数组位置与存储的排列值都需加 1。
        order(index + 1) = reversed + 1;
    end
end
