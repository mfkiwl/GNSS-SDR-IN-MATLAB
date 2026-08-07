function out = gnssBitEdgeDetect(msValues)
%GNSSBITEDGEDETECT GPS 比特边缘检测（位同步，无参考序列）
%
%   out = gnssBitEdgeDetect(msValues)
%
%   输入:
%     msValues - 每 1 ms 相关复数（去载波去码后），列向量
%   输出:
%     out.bitOffsetMs  - 最优位同步偏移 (0~19 ms)
%     out.energy       - 20 个候选偏移的平均比特相干能量
%     out.flipRate     - 20 个候选偏移的边界翻转率（翻转直方图法）
%     out.peakToSecond - 最优/次优能量比（越大越可信）
%
%   原理：
%     - 能量法：正确对齐时每个 20 ms 窗口内的 20 个 1 ms 值同相叠加，
%       |20 ms 和| 最大；错位时窗口跨两个比特，能量被抵消。
%     - 翻转法（直方图）：正确对齐时候选边界位置恰为真实比特边缘，
%       相邻 1 ms 符号翻转率高（约 50%）；错位时边界落在比特内部，
%       相邻同相，翻转率低。用 real(c(i)*conj(c(i+1))) < 0 判翻转，
%       无需绝对载波相位。

msValues = msValues(:);
nMs = numel(msValues);
energy = zeros(20, 1);
flipRate = zeros(20, 1);

for b = 0:19
    nB = floor((nMs - b) / 20);
    e = zeros(nB, 1);
    for j = 1:nB
        e(j) = abs(sum(msValues(b + (j-1)*20 + (1:20))));
    end
    energy(b+1) = mean(e);

    flips = 0; cnt = 0;
    for t = b+20 : 20 : nMs-1
        flips = flips + (real(msValues(t) * conj(msValues(t+1))) < 0);
        cnt = cnt + 1;
    end
    flipRate(b+1) = flips / max(cnt, 1);
end

% 综合：翻转率归一化 + 能量归一化（各占一半权重）
energyN = energy / max(energy);
flipN   = flipRate / max(flipRate);
[~, best] = max(energyN + flipN);
out.bitOffsetMs = best - 1;
out.energy = energy;
out.flipRate = flipRate;
sorted = sort(energy, 'descend');
out.peakToSecond = sorted(1) / max(sorted(2), eps);
end
