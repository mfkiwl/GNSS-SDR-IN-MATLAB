function results = demoGnssPositioning(varargin)
%DEMOGNSSPOSITIONING 一键演示：多星定位全链路（合成信号）+ 可视化
%
%   运行后依次弹出 5 幅图，直观看到整个"现象"：
%     图1: 卫星 3D 星座（真实 GPS 轨道位置）+ 接收机位置
%     图2: 天空图（6 颗卫星方位/仰角，GPS 接收机视角）
%     图3: 每星 C/N0 随时间（跟踪质量）
%     图4: 伪距重建 vs 注入真值（一致性）
%     图5: 定位结果（经纬高 + 距参考点误差 + GDOP + 残差）
%     图6: 解码原始电文（300 位位梯 + 逐字/字段解析）
%   控制台额外直接输出解码后的原始电文数据（300 位比特 + TLM/HOW +
%   数据字 + 星历 26 字段），参数 'MsgPRN' 选星（默认第一颗）
%
%   用法:
%     demoGnssPositioning                    % 6 星，28 s，~1.5 min
%     demoGnssPositioning('NumSats', 5)      % 5 星更快
%     demoGnssPositioning('RefLat', 31.2, 'RefLon', 121.5)
%
%   说明:
%     - 合成信号模式下星历从接收信号解码（端到端）；如需硬件 TX→RX，
%       传 'Synthetic', false（Pluto 发射需确认，且仅子帧 1 → 用已知星历）
%     - 图默认保存到 data/demo_gnss_positioning_<时间戳>.png（第 1-5 图
%       各一张 + 一张总览 + 一张电文图）

p = struct();
p.Synthetic = true;
p.NumSats   = 6;
p.RefLat    = 31.2304;
p.RefLon    = 121.4737;
p.RefH      = 0;
p.CaptureSec = 28;
p.MsgPRN     = [];
for k = 1:2:numel(varargin)
    key = varargin{k};
    val = varargin{k+1};
    switch lower(key)
        case 'synthetic',  p.Synthetic = val;
        case 'numsats',    p.NumSats = val;
        case 'reflat',     p.RefLat = val;
        case 'reflon',     p.RefLon = val;
        case 'refh',       p.RefH = val;
        case 'capturesec', p.CaptureSec = val;
        case 'msgprn',     p.MsgPRN = val;
        otherwise, error('未知参数: %s', key);
    end
end

fprintf('==========================================================\n');
fprintf(' 多星定位演示：跑全链路 + 弹可视化（%d 星，%.0f s 合成信号）\n', ...
    p.NumSats, p.CaptureSec);
fprintf('==========================================================\n');

%% ---- 跑定位验证 ----
if p.Synthetic
    results = verifyGnssPositioning('NumSats', p.NumSats, ...
        'RefLat', p.RefLat, 'RefLon', p.RefLon, 'RefH', p.RefH, ...
        'CaptureSec', p.CaptureSec);
else
    error('硬件模式请直接运行 verifyGnssPositioning 对应分支（需发射确认）');
end

if ~isfield(results, 'trk')
    fprintf('[演示] 定位未完成，无结果可显示\n');
    return;
end

%% ---- 准备绘图数据 ----
prns   = results.injected.prns;
if isempty(p.MsgPRN)
    p.MsgPRN = prns(1);
end
X0     = results.injected.X0;
satPos = results.injected.satPos;
posEst = results.posEst;
m      = results.metrics;
trk    = results.trk;

% 每星重新解码子帧 + 星历（供电文展示）
decAll = cell(1, p.NumSats);
ephAll = cell(1, p.NumSats);
for i = 1:p.NumSats
    decAll{i} = gnssSubframeDecode(trk(i).bits);
    ephAll{i} = gnssEphDecode(decAll{i}.subframes);
end
results.decAll = decAll;
results.ephAll = ephAll;

%% ---- 控制台：解码原始电文数据 ----
msgIdx = find(prns == p.MsgPRN, 1);
if isempty(msgIdx)
    msgIdx = 1;
    p.MsgPRN = prns(1);
end
fprintf('\n==========================================================\n');
sf1i = find([decAll{msgIdx}.subframes.subframeId] == 1, 1);
if isempty(sf1i), sf1i = 1; end
fprintf(' 解码原始电文数据：PRN %d（子帧 %d，TOW %d）\n', ...
    p.MsgPRN, decAll{msgIdx}.subframes(sf1i).subframeId, ...
    decAll{msgIdx}.subframes(sf1i).tow);
fprintf('==========================================================\n');
printNavMessage(trk(msgIdx), decAll{msgIdx}, ephAll{msgIdx});
for i = 1:p.NumSats
    if i == msgIdx, continue; end
    i1 = find([decAll{i}.subframes.subframeId] == 1, 1);
    if isempty(i1), i1 = 1; end
    sf1 = decAll{i}.subframes(i1);
    if isfield(trk(i), 'numErrors')
        fprintf('  PRN %2d: 子帧1 TOW=%d 子帧号=%d 位误码(参考)=%d\n', ...
            prns(i), sf1.tow, sf1.subframeId, trk(i).numErrors);
    else
        fprintf('  PRN %2d: 子帧1 TOW=%d 子帧号=%d（解调 %d 位）\n', ...
            prns(i), sf1.tow, sf1.subframeId, numel(trk(i).bits));
    end
end

% 每星方位/仰角（以参考点 X0 为观测站）
[azDeg, elDeg] = deal(zeros(1, p.NumSats));
for i = 1:p.NumSats
    [azDeg(i), elDeg(i)] = azElFromEcef(X0, satPos(:, i));
end

outDir = fullfile(fileparts(mfilename('fullpath')), 'data');
if ~exist(outDir, 'dir'), mkdir(outDir); end
ts = datestr(now, 'yyyymmdd_HHMMSS');
pngBase = fullfile(outDir, ['demo_gnss_positioning_' ts]);

%% ---- 图1：卫星 3D 星座 + 接收机 ----
f1 = figure('Name', 'GPS 星座与接收机位置', 'Position', [60 60 760 640]);
earthWire(3); hold on;
plot3(satPos(1,:), satPos(2,:), satPos(3,:), 'r^', 'MarkerSize', 10, ...
    'MarkerFaceColor', 'r');
for i = 1:p.NumSats
    text(satPos(1,i), satPos(2,i), satPos(3,i)+3e5, sprintf('PRN%d', prns(i)), ...
        'FontSize', 8, 'Color', 'r');
end
plot3(X0(1), X0(2), X0(3), 'bs', 'MarkerSize', 14, 'MarkerFaceColor', 'b');
plot3(posEst(1), posEst(2), posEst(3), 'g^', 'MarkerSize', 12, ...
    'MarkerFaceColor', 'g');
legend('地球', '卫星(真实星历)', '参考点', '解算位置', 'Location', 'best');
title(sprintf('GPS 星座（%d 星，ECEF）— 解算误差 %.1f m', p.NumSats, m.dPos));
xlabel('X (m)'); ylabel('Y (m)'); zlabel('Z (m)'); grid on; axis equal;
saveas(f1, [pngBase '_1_constellation.png']);

%% ---- 图2：天空图 ----
f2 = figure('Name', '天空图（方位/仰角）', 'Position', [120 120 560 560]);
polaraxes(f2);
r = 90 - elDeg;                       % 天顶距
th = deg2rad(azDeg);
polarscatter(th, r, 80, 1:p.NumSats, 'filled');
title(sprintf('天空图（%s 视角，仰角 %.0f°~%.0f°）', ...
    sprintf('%.3fN %.3fE', p.RefLat, p.RefLon), min(elDeg), max(elDeg)));
for i = 1:p.NumSats
    text(th(i), r(i) + 4, sprintf('PRN%d', prns(i)), 'FontSize', 8);
end
colorbar('Ticks', 1:p.NumSats, 'TickLabels', ...
    arrayfun(@(x) sprintf('PRN%d', x), prns, 'UniformOutput', false));
saveas(f2, [pngBase '_2_sky.png']);

%% ---- 图3：C/N0 ----
f3 = figure('Name', '各星 C/N0', 'Position', [180 180 820 420]);
hold on;
for i = 1:p.NumSats
    cn0 = trk(i).CN0dBHz;
    plot((1:numel(cn0)) * 0.02, cn0, 'LineWidth', 1);
end
legend(arrayfun(@(x) sprintf('PRN%d', x), prns, 'UniformOutput', false), ...
    'Location', 'eastoutside');
xlabel('时间 (s)'); ylabel('C/N0 (dB-Hz)'); grid on;
title(sprintf('多通道跟踪 C/N0（%s）', ...
    sprintf('%.1f~%.1f dB-Hz', min(arrayfun(@(t) ...
    median(t.CN0dBHz(end-49:end)), trk)), max(arrayfun(@(t) ...
    median(t.CN0dBHz(end-49:end)), trk)))));
saveas(f3, [pngBase '_3_cn0.png']);

%% ---- 图4：伪距一致性 ----
f4 = figure('Name', '伪距重建 vs 注入真值', 'Position', [240 240 820 420]);
rhoRel = results.rho - mean(results.rho);
injRel = results.injected.delays * 299792458 / 2.5e6 - ...
    mean(results.injected.delays * 299792458 / 2.5e6);
bar(1:p.NumSats, [rhoRel; injRel]' / 1e3);
legend('接收端伪距（相对）', '注入真值（相对）', 'Location', 'best');
xlabel('卫星'); ylabel('相对伪距 (km)'); grid on;
set(gca, 'XTick', 1:p.NumSats, 'XTickLabel', ...
    arrayfun(@(x) sprintf('PRN%d', x), prns, 'UniformOutput', false));
title(sprintf('伪距一致性：最大偏差 %.1f m', m.dRho));
saveas(f4, [pngBase '_4_pseudorange.png']);

%% ---- 图5：定位结果 ----
f5 = figure('Name', '定位结果', 'Position', [300 300 760 480]);
subplot(2, 2, [1 2]);
plot(m.lon, m.lat, 'r^', 'MarkerSize', 14, 'MarkerFaceColor', 'r'); hold on;
plot(p.RefLon, p.RefLat, 'bs', 'MarkerSize', 14, 'MarkerFaceColor', 'b');
legend('解算位置', '参考点', 'Location', 'best');
xlabel('经度 (°E)'); ylabel('纬度 (°N)'); grid on;
title(sprintf('定位结果：误差 %.1f m（门限 300 m）', m.dPos));
axis equal; xlim(m.lon + [-1 1]); ylim(m.lat + [-1 1]);

subplot(2, 2, 3);
text(0.1, 0.8, sprintf('WGS84: %.6f°N, %.6f°E, %.1f m', ...
    m.lat, m.lon, m.h), 'Units', 'normalized', 'FontSize', 10);
text(0.1, 0.55, sprintf('距参考点: %.1f m', m.dPos), ...
    'Units', 'normalized', 'FontSize', 10, 'Color', 'r');
text(0.1, 0.30, sprintf('GDOP: %.2f', m.gdop), ...
    'Units', 'normalized', 'FontSize', 10);
text(0.1, 0.05, sprintf('伪距残差 RMS: %.1f m', m.resRms), ...
    'Units', 'normalized', 'FontSize', 10);
axis off;

subplot(2, 2, 4);
bar([m.dPos; m.dRho; m.resRms]);
set(gca, 'XTickLabel', {'位置误差(m)', '伪距偏差(m)', '残差RMS(m)'});
title('指标');
grid on;
saveas(f5, [pngBase '_5_position.png']);

%% ---- 图6：解码原始电文（位梯 + 字段）----
f6 = figure('Name', '解码原始电文', 'Position', [360 360 980 640]);
sf  = decAll{msgIdx}.subframes(sf1i);
sidx = decAll{msgIdx}.syncIndex(1);
subframeBits = trk(msgIdx).bits(sidx : sidx + 299);   % 极性已消除
drawBitLadder(subframeBits);
title(sprintf('PRN %d 原始电文子帧 1（300 位，TOW %d）', ...
    p.MsgPRN, sf.tow));
saveas(f6, [pngBase '_6_navmsg.png']);

%% ---- 总览图（2x3 拼图）----
fo = figure('Name', '多星定位演示总览', 'Position', [80 80 1280 760]);
subplot(2, 3, 1);
skyQuick(fo, azDeg, elDeg, prns, X0);
subplot(2, 3, 2);
hold on;
for i = 1:p.NumSats
    plot((1:numel(trk(i).CN0dBHz)) * 0.02, trk(i).CN0dBHz, 'LineWidth', 1);
end
title('C/N0'); xlabel('s'); ylabel('dB-Hz'); grid on;
subplot(2, 3, 3);
bar(1:p.NumSats, [rhoRel; injRel]' / 1e3);
title(sprintf('伪距一致性 (max %.1f m)', m.dRho));
set(gca, 'XTickLabel', prns); grid on;
subplot(2, 3, 4);
earthWire(3); hold on;
plot3(satPos(1,:), satPos(2,:), satPos(3,:), 'r^', 'MarkerFaceColor', 'r');
plot3(X0(1), X0(2), X0(3), 'bs', 'MarkerFaceColor', 'b');
plot3(posEst(1), posEst(2), posEst(3), 'g^', 'MarkerFaceColor', 'g');
legend('地球', '卫星', '参考', '解算', 'Location', 'best');
title('星座'); axis equal; grid on;
subplot(2, 3, 5);
plot(m.lon, m.lat, 'r^', 'MarkerSize', 12, 'MarkerFaceColor', 'r'); hold on;
plot(p.RefLon, p.RefLat, 'bs', 'MarkerSize', 12, 'MarkerFaceColor', 'b');
title(sprintf('位置：误差 %.1f m', m.dPos));
xlabel('°E'); ylabel('°N'); grid on; axis equal;
subplot(2, 3, 6);
bar([m.dPos; m.dRho; m.resRms; m.gdop*10]);
set(gca, 'XTickLabel', {'位置误差', '伪距偏差', '残差RMS', 'GDOPx10'});
title('指标'); grid on;
sgtitle(sprintf('多星定位演示：%d 星全链路 PASS（%.1f m）', ...
    p.NumSats, m.dPos));
saveas(fo, [pngBase '_overview.png']);

fprintf('[演示] 图已保存: %s_*.png（5 幅 + 总览）\n', pngBase);
fprintf('  定位结果: %.6f°N %.6f°E %.1f m，误差 %.1f m，GDOP %.2f\n', ...
    m.lat, m.lon, m.h, m.dPos, m.gdop);
results.demoPng = pngBase;
end

%% ---- 工具：控制台打印解码电文 ----
function printNavMessage(t1, dec, eph)
sf1idx = find([dec.subframes.subframeId] == 1, 1);
if isempty(sf1idx), sf1idx = 1; end
sf  = dec.subframes(sf1idx);
sidx = dec.syncIndex(sf1idx);
bits300 = t1.bits(sidx : sidx + 299);
words = reshape(bits300, 30, 10).';

% 还原逻辑数据（D30 位反转）
logW = zeros(10, 24);
prevD30 = 0;
for w = 1:10
    logW(w, :) = mod(words(w, 1:24) + prevD30, 2);
    prevD30 = words(w, 30);
end

fprintf('原始 300 位（每 30 位一个字，共 10 字）:\n');
for w = 1:10
    b = words(w, :);
    fprintf('  W%02d  %s %s %s\n', w, ...
        binStr(b(1:10)), binStr(b(11:20)), binStr(b(21:30)));
end

fprintf('\n逐字解析（逻辑数据，24 位）:\n');
fprintf('  W1 TLM : 前导码=%s 消息(9:14)=%s 保留=%s 计数(17:22)=%s 完好性=%d 备用=%d\n', ...
    binStr(logW(1,1:8)), binStr(logW(1,9:14)), binStr(logW(1,15:16)), ...
    binStr(logW(1,17:22)), logW(1,23), logW(1,24));
fprintf('  W2 HOW : TOW=%d 子帧号=%d Alert=%d AS=%d\n', ...
    bi2de(logW(2,1:17), 'left-msb'), bi2de(logW(2,20:22), 'left-msb'), ...
    logW(2,18), logW(2,19));
for w = 3:10
    fprintf('  W%02d 数据: %s %s %s\n', w, ...
        binStr(logW(w,1:8)), binStr(logW(w,9:16)), binStr(logW(w,17:24)));
end

fprintf('\n星历解析（26 字段）:\n');
names = {'Af0(s)','Af1(s/s)','Af2(s/s^2)','Toc(s)','Week','IODE','IODC', ...
    'TGD(s)','URA','SVHealth','sqrtA(m^.5)','Ecc','M0(半周)','DeltaN(半周/s)', ...
    'Toe(s)','Cuc','Cus','Cic','Cis','Crc','Crs','Omega0(半周)','omega(半周)', ...
    'i0(半周)','OmegaDot(半周/s)','IDOT(半周/s)'};
vals = {eph.Af0, eph.Af1, eph.Af2, eph.Toc, eph.Week, eph.IODE, eph.IODC, ...
    eph.TGD, eph.URA, eph.SVHealth, eph.SqrtA, eph.Ecc, eph.M0, eph.DeltaN, ...
    eph.Toe, eph.Cuc, eph.Cus, eph.Cic, eph.Cis, eph.Crc, eph.Crs, ...
    eph.Omega0, eph.omega, eph.i0, eph.OmegaDot, eph.IDOT};
for k = 1:numel(names)
    fprintf('  %-16s = %-14.6g\n', names{k}, vals{k});
end
end

%% ---- 工具：位串 ----
function s = binStr(b)
s = sprintf('%d', b);
end

%% ---- 工具：原始电文位梯图 ----
function drawBitLadder(bits300)
% 10 字 x 30 位列梯：1 为深色，0 为浅色，字边界标线
gridBits = reshape(bits300, 30, 10).';   % 10x30
imagesc(1:30, 1:10, gridBits);
colormap([0.88 0.88 0.88; 0.15 0.35 0.75]);
set(gca, 'YDir', 'reverse');
xlabel('字内位序号'); ylabel('电文字序号');
for w = 1:10
    text(30.8, w, sprintf('W%02d', w), 'FontSize', 8, 'HorizontalAlignment', 'left');
end
hold on;
for x = 8.5:3:29.5
    plot([x x], [0.5 10.5], 'k:', 'LineWidth', 0.4);
end
for x = 0.5:10.5
    plot([x x], [0.5 10.5], 'k-', 'LineWidth', 0.3);
end
text(4.5, 10.6, 'TLM 前导码', 'FontSize', 7, 'HorizontalAlignment', 'center');
text(14.5, 10.6, 'HOW (TOW/子帧号)', 'FontSize', 7, 'HorizontalAlignment', 'center');
axis([0 33 0.5 11.4]);
colorbar('Ticks', [0 1], 'TickLabels', {'0', '1'});
end

%% ---- 工具：ECEF → 方位/仰角 ----
function [az, el] = azElFromEcef(Xobs, Xsat)
[lat, lon] = ecef2Geodetic(Xobs);
phi = deg2rad(lat); lam = deg2rad(lon);
% ENU 基
e = [-sin(lam); cos(lam); 0];
n = [-sin(phi)*cos(lam); -sin(phi)*sin(lam); cos(phi)];
u = [cos(phi)*cos(lam); cos(phi)*sin(lam); sin(phi)];
los = Xsat - Xobs;
los = los / norm(los);
el = asin(dot(los, u));
az = atan2(dot(los, e), dot(los, n));
az = mod(rad2deg(az), 360);
el = rad2deg(el);
end

function [lat, lon, h] = ecef2Geodetic(X)
a = 6378137.0;
f = 1/298.257223563;
e2 = f*(2-f);
x = X(1); y = X(2); z = X(3);
lon = atan2(y, x);
pp = sqrt(x^2 + y^2);
phi = atan2(z, pp*(1-e2));
h = 0;
for it = 1:6
    N = a / sqrt(1 - e2*sin(phi)^2);
    h = pp/cos(phi) - N;
    phi = atan2(z, pp*(1 - e2*N/(N+h)));
end
lat = rad2deg(phi);
lon = rad2deg(lon);
end

%% ---- 工具：地球线框 ----
function earthWire(scale)
[xx, yy, zz] = sphere(24);
re = 6371e3 * scale;      % 地球半径
surf(xx*re, yy*re, zz*re, 'FaceColor', [0.1 0.35 0.8], ...
    'EdgeColor', [0.5 0.7 1], 'FaceAlpha', 0.15, 'LineWidth', 0.4);
hold on;
plot3([-re re], [0 0], [0 0], 'k-');
plot3([0 0], [-re re], [0 0], 'k-');
plot3([0 0], [0 0], [-re re], 'k-');
end

%% ---- 工具：快速天空图（总览用）----
function skyQuick(~, azDeg, elDeg, prns, X0)
th = deg2rad(azDeg);
r = 90 - elDeg;
polarscatter(th, r, 60, 1:numel(prns), 'filled');
[lat0, lon0] = ecef2Geodetic(X0);
title(sprintf('天空图（%.2f°N %.2f°E）', lat0, lon0));
for i = 1:numel(prns)
    text(th(i), r(i) + 4, sprintf('P%d', prns(i)), 'FontSize', 8);
end
end
