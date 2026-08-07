function [rho, eSf] = gnssPseudorange(t1, sf, syncIndex, fs)
%GNSSPSEUDORANGE 由跟踪输出 + 解码子帧计算伪距（含未知接收机钟差）
%
%   rho = gnssPseudorange(t1, sf, syncIndex, fs)
%
%   输入:
%     t1        - tracking 单通道输出（须含 codePhase / msValues / bits /
%                 bitOffsetMs）
%     sf        - 该通道解出的子帧结构（gnssSubframeDecode 输出项，
%                 须含 .tow）
%     syncIndex - 该子帧在 t1.bits 中的起点位索引（dec.syncIndex 对应项）
%     fs        - 采样率 (Hz)
%   输出:
%     rho - 伪距 (m)。锚定在子帧起点码相位零点（GPS 时间 T_sf =
%           (tow-1)*6 s），含未知接收机钟差，由定位最小二乘吸收
%     eSf - 锚定码相位零点的接收机采样索引（供多星时标一致性检查）
%
%   说明（亚毫秒比特边界解析）:
%     子帧起点 = 比特边界 = 码相位零点，位于毫秒网格的分数位置。
%     1) 对 20 个整数比特相位求 20 ms 累加能量曲线，抛物线插值得
%        亚毫秒相位 b_true；
%     2) 子帧起点分数毫秒 P = skipMs + b_true + (syncIndex-1)*20；
%     3) 码相位零点采样 e_sf = floor(P)*msLen + codePhase(floor(P)+1)；
%     4) rho = c*(e_sf/fs - T_sf)。
%     实测（CN0 41，6 星）：伪距重建误差 1~6 m（注入真值比对）

c = 299792458;
msLen = round(fs * 1e-3);
nMs = numel(t1.codePhase);
skipMs = min(300, max(50, floor(nMs*0.05)));

%% ---- 1. 亚毫秒比特相位（能量曲线 + 抛物线插值）----
msUse = t1.msValues(skipMs+1 : end);
nUse = numel(msUse);
E = zeros(20, 1);
for b = 0:19
    nB = floor((nUse - b) / 20);
    if nB < 1, E(b+1) = 0; continue; end
    e = zeros(nB, 1);
    for j = 1:nB
        e(j) = abs(sum(msUse(b + (j-1)*20 + (1:20))));
    end
    E(b+1) = mean(e);
end
[~, bp] = max(E);
if bp == 1
    bTrue = bp - 1 + 0.5*(E(20) - E(2)) / (E(20) - 2*E(1) + E(2) + eps);
elseif bp == 20
    bTrue = bp - 1 + 0.5*(E(19) - E(1)) / (E(19) - 2*E(20) + E(1) + eps);
else
    bTrue = bp - 1 + 0.5*(E(bp-1) - E(bp+1)) / ...
        (E(bp-1) - 2*E(bp) + E(bp+1) + eps);
end

%% ---- 2. 子帧起点分数毫秒 + 码相位零点采样 ----
P   = skipMs + bTrue + (syncIndex - 1)*20;
k   = floor(P) + 1;
k   = min(max(k, 2), nMs);
d   = t1.codePhase(k);
eSf = floor(P)*msLen + d;

%% ---- 3. 伪距 ----
Tsf = (sf.tow - 1) * 6;          % 子帧起点 GPS 秒周
rho = c * (eSf / fs - Tsf);
end
