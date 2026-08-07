function [pos, bias, gdop, res, nIter] = leastSquaresPosition(rho, satPos, pos0)
%LEASTSQUARESPOSITION 伪距最小二乘定位解算（4 未知数：位置 + 接收机钟差）
%
%   [pos, bias, gdop, res] = leastSquaresPosition(rho, satPos, pos0)
%
%   输入:
%     rho    - Nx1 伪距 (m)
%     satPos - 3xN 卫星 ECEF 位置 (m)，计算时刻为信号发射时刻
%     pos0   - 3x1 初始位置估计 (m)；默认地心 [0;0;0]
%   输出:
%     pos   - 3x1 接收机 ECEF 位置 (m)
%     bias  - 接收机钟差等效距离 (m)（含公共时标误差）
%     gdop  - 几何精度因子
%     res   - Nx1 最终伪距残差 (m)
%
%   模型: rho_i = ||pos - sat_i|| + bias + eps_i
%   方法: 高斯-牛顿迭代（线性化 H = [-(sat_i-pos)^T/||..||, 1]）

rho = rho(:);
if size(satPos, 1) ~= 3
    satPos = satPos.';
end
n = numel(rho);
if n < 4
    error('至少需要 4 颗卫星的伪距（当前 %d）', n);
end
if nargin < 3 || isempty(pos0)
    pos0 = [0; 0; 0];
end

x = pos0(:);
b = median(rho) - median(vecnorm(satPos - x));   % 粗初始钟差

for it = 1:8
    dr = satPos - x;               % 3xN
    rngDist = vecnorm(dr);         % 1xN
    H = [-(dr ./ rngDist).', ones(n, 1)];
    delta = rho - (rngDist.' + b);
    if it < 8
        upd = (H.' * H) \ (H.' * delta);
        x = x + upd(1:3);
        b = b + upd(4);
    end
end

pos = x;
bias = b;
dr = satPos - x;
rngDist = vecnorm(dr);
res = rho - (rngDist.' + b);

% GDOP
Q = inv(H.' * H);
gdop = sqrt(trace(Q));
end
