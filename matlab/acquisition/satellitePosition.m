function [posEcef, satClk, r, E] = satellitePosition(eph, tSow)
%SATELLITEPOSITION 由 GPS 广播星历计算卫星 ECEF 位置（IS-GPS-200 §20.3.3.4）
%
%   [posEcef, satClk, r, E] = satellitePosition(eph, tSow)
%
%   输入:
%     eph  - gnssEphDecode 输出的星历结构（角度为半周）
%     tSow - 计算时刻的 GPS 秒周（0..604799）
%   输出:
%     posEcef - 3x1 ECEF 位置 (m)
%     satClk  - 卫星钟差修正 Δtsv (s)：af0+af1·dt+af2·dt²+相对论项
%     r       - 地心距 (m)
%     E       - 偏近点角 (rad)
%
%   参考: IS-GPS-200L §20.3.3.4 开普勒传播 + 轨道摄动修正；
%         常量 mu=3.986005e14, WE=7.2921151467e-5 rad/s

mu = 3.986005e14;
WE = 7.2921151467e-5;
F  = -4.442807633e-10;   % 相对论修正系数 2*sqrt(mu)/c^2

A    = eph.SqrtA^2;
n0   = sqrt(mu / A^3);
n    = n0 + eph.DeltaN * pi;               % Δn 半周/s → rad/s

tk = tSow - eph.Toe;
if tk > 302400,  tk = tk - 604800; end
if tk < -302400, tk = tk + 604800; end

% 平近点角
M = (eph.M0 * pi) + n * tk;

% 开普勒方程迭代解偏近点角 E = M + e·sin(E)
e = eph.Ecc;
E = M;
for it = 1:10
    dE = (M - (E - e*sin(E))) / (1 - e*cos(E));
    E = E + dE;
    if abs(dE) < 1e-12, break; end
end

% 真近点角 + 纬度辐角
v    = atan2(sqrt(1 - e^2)*sin(E), cos(E) - e);
phi  = v + eph.omega * pi;

% 摄动修正
u = phi + eph.Cuc*cos(2*phi) + eph.Cus*sin(2*phi);
r = A*(1 - e*cos(E)) + eph.Crc*cos(2*phi) + eph.Crs*sin(2*phi);
i = (eph.i0 * pi) + eph.IDOT*tk*pi + ...
    eph.Cic*cos(2*phi) + eph.Cis*sin(2*phi);

% 升交点经度（含地球自转；OmegaDot 半周/s → rad/s）
Omega = (eph.Omega0 * pi) + (eph.OmegaDot*pi - WE)*tk - WE*eph.Toe;

% 轨道平面内 → ECEF
xp = r*cos(u);
yp = r*sin(u);
posEcef = [xp*cos(Omega) - yp*cos(i)*sin(Omega); ...
           xp*sin(Omega) + yp*cos(i)*cos(Omega); ...
           yp*sin(i)];

% 卫星钟差（含相对论项；TGD 由接收机单频用户另行扣除）
dt = tSow - eph.Toc;
if dt > 302400,  dt = dt - 604800; end
if dt < -302400, dt = dt + 604800; end
satClk = eph.Af0 + eph.Af1*dt + eph.Af2*dt^2 + F*e*eph.SqrtA*sin(E);
end
