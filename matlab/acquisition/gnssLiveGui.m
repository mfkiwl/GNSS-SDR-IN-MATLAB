function app = gnssLiveGui(varargin)
%GNSSLIVEGUI M4 多星定位实时显示 GUI（uifigure）
%
%   面板:
%     - 左：各星 C/N0 实时曲线（随时间增长，播放控制）
%     - 右：天空图（方位/仰角）
%     - 左下：解码电文（子帧比特 + TLM/HOW + 星历字段）
%     - 右下：定位结果（经纬高/误差/GDOP/残差）
%     - 控制：播放/暂停、时间滑杆、速度、选星
%
%   用法:
%     gnssLiveGui                        % 跑合成定位后打开（约 1.5 min）
%     gnssLiveGui('Synthetic', false)    % 硬件多星（需发射确认）
%     gnssLiveGui('LoadFile', 'D:\13_MCP\GNSS\data\gnss_positioning_20260810_105452.mat')
%     gnssLiveGui('SnapshotFile', 'gui.png')   % 无头模式：播完截图退出
%
%   说明:
%     - 播放按接收机处理节奏回放：C/N0 曲线增长、子帧解码、定位结果
%       按时间点依次出现
%     - 合成模式星历来自信号解码；硬件模式仅子帧 1（星历用 RINEX 已知）

p = struct();
p.Synthetic = true;
p.NumSats   = 6;
p.MsgPRN    = [];
p.LoadFile  = '';
p.SnapshotFile = '';

for k = 1:2:numel(varargin)
    key = varargin{k};
    val = varargin{k+1};
    switch lower(key)
        case 'synthetic',    p.Synthetic = val;
        case 'numsats',      p.NumSats = val;
        case 'msgprn',       p.MsgPRN = val;
        case 'loadfile',     p.LoadFile = val;
        case 'snapshotfile', p.SnapshotFile = val;
        otherwise, error('未知参数: %s', key);
    end
end

%% ---- 1. 获取定位结果 ----
if ~isempty(p.LoadFile)
    s = load(p.LoadFile);
    results = s.results;
else
    fprintf('[GUI] 先跑定位 ...\n');
    results = verifyGnssPositioning('Synthetic', p.Synthetic, ...
        'NumSats', p.NumSats);
end
if ~isfield(results, 'trk')
    error('无跟踪结果（定位未完成）');
end

%% ---- 2. 准备数据 ----
prns   = results.injected.prns;
X0     = results.injected.X0;
satPos = results.injected.satPos;
m      = results.metrics;
trk    = results.trk;
nSat   = numel(prns);

% 每星 C/N0 时间序列（20 ms 间隔）
cn0All = cell(1, nSat);
for i = 1:nSat
    cn0All{i} = trk(i).CN0dBHz;
end
nPts = max(cellfun(@numel, cn0All));
tSec = (0:nPts-1) * 0.02;

% 天空图数据（方位/仰角）
azDeg = zeros(1, nSat);
elDeg = zeros(1, nSat);
for i = 1:nSat
    [azDeg(i), elDeg(i)] = azElFromEcef(X0, satPos(:, i));
end

% 每星解码（子帧 1）+ 电文文本
decAll = cell(1, nSat);
msgText = cell(1, nSat);
decTime = zeros(1, nSat);     % 解码出现的播放时刻（近似：跟踪后段）
for i = 1:nSat
    decAll{i} = gnssSubframeDecode(trk(i).bits);
    msgText{i} = navMessageText(trk(i), decAll{i});
    if ~isempty(decAll{i}.syncIndex)
        decTime(i) = tSec(end) * 0.75;   % 近似：解码在跟踪后段完成
    else
        decTime(i) = inf;
    end
end

%% ---- 3. 构建 UI ----
fig = uifigure('Name', 'GNSS 多星定位实时显示', ...
    'Position', [80 80 1180 760]);
g = uigridlayout(fig, [4 2]);
g.RowHeight = {220, 220, 180, 40};
g.ColumnWidth = {600, 560};

% (1,1) C/N0 实时曲线
axC = uiaxes(g);
axC.Layout.Row = 1; axC.Layout.Column = 1;
title(axC, 'C/N0 实时（各星）'); xlabel(axC, '时间 (s)');
ylabel(axC, 'dB-Hz'); grid(axC, 'on'); hold(axC, 'on');
colors = lines(nSat);
ln = gobjects(1, nSat);
for i = 1:nSat
    ln(i) = plot(axC, NaN, NaN, 'LineWidth', 1.2, 'Color', colors(i, :));
end
legend(axC, arrayfun(@(x) sprintf('PRN%d', x), prns, ...
    'UniformOutput', false), 'Location', 'northeastoutside');
ylim(axC, [25 50]); xlim(axC, [0 max(tSec(end), 1)]);

% (1,2) 天空图
axS = uiaxes(g);
axS.Layout.Row = 1; axS.Layout.Column = 2;
axis(axS, 'equal'); grid(axS, 'on'); hold(axS, 'on');
th = deg2rad(azDeg);
rr = 90 - elDeg;
% 极坐标转直角绘制
scatter(axS, rr.*cos(th), rr.*sin(th), 70, 1:nSat, 'filled');
for i = 1:nSat
    text(axS, rr(i).*cos(th(i)), rr(i).*sin(th(i)) + 4, ...
        sprintf('PRN%d', prns(i)), 'FontSize', 9);
end
for rk = [45 75]
    viscircles(axS, [0 0], rk, 'Color', [0.7 0.7 0.7]);
end
title(axS, '天空图（方位/仰角）'); xlim(axS, [-100 100]); ylim(axS, [-100 100]);
text(axS, 0, 100, '天顶', 'HorizontalAlignment', 'center');

% (2,1) 解码电文
txMsg = uitextarea(g);
txMsg.Layout.Row = 2; txMsg.Layout.Column = 1;
txMsg.Value = '等待子帧解码 ...';
txMsg.FontName = 'Consolas'; txMsg.FontSize = 11;

% (2,2) 定位结果
txPos = uitextarea(g);
txPos.Layout.Row = 2; txPos.Layout.Column = 2;
txPos.Value = '等待定位解算 ...';
txPos.FontName = 'Consolas'; txPos.FontSize = 11;

% (3,1) 卫星选择
selSat = uidropdown(g, 'Items', arrayfun(@(x) sprintf('PRN%d', x), ...
    prns, 'UniformOutput', false), 'ValueChangedFcn', @(s, e) showMsg());
selSat.Layout.Row = 3; selSat.Layout.Column = 1;
txSel = uilabel(g, 'Text', '选择卫星查看解码电文');
txSel.Layout.Row = 3; txSel.Layout.Column = 1;
txSel.HorizontalAlignment = 'right';

% (3,2) 状态
st = uilabel(g, 'Text', sprintf('状态: 6 星已跟踪，等待播放'), ...
    'FontSize', 13, 'FontWeight', 'bold');
st.Layout.Row = 3; st.Layout.Column = 2;

% (4,*) 控制
btnPlay = uibutton(g, 'Text', '播放', 'ButtonPushedFcn', @(s, e) playBack());
btnPlay.Layout.Row = 4; btnPlay.Layout.Column = 1;
slTime = uislider(g, 'Limits', [0 tSec(end)], 'Value', 0, ...
    'ValueChangedFcn', @(s, e) seek());
slTime.Layout.Row = 4; slTime.Layout.Column = 2;

%% ---- 4. 播放状态 ----
app = struct('fig', fig, 'results', results, 't', 0, 'playing', false, ...
    'tSec', tSec, 'cn0All', {cn0All}, 'ln', ln, 'prns', prns, ...
    'txMsg', txMsg, 'txPos', txPos, 'st', st, 'slTime', slTime, ...
    'decTime', decTime, 'msgText', {msgText}, 'decAll', {decAll}, ...
    'm', m, 'nSat', nSat, 'selSat', selSat);

updateDisplay(app, 0);

%% ---- 5. 播放（交互：timer；无头：快进到结束）----
if ~isempty(p.SnapshotFile)
    % 无头模式：分 40 步播完并截图
    for k = 1:40
        app.t = tSec(end) * k / 40;
        updateDisplay(app, app.t);
        drawnow;
    end
    exportapp(fig, p.SnapshotFile);
    fprintf('[GUI] 截图已保存: %s\n', p.SnapshotFile);
    close(fig);
else
    tmr = timer('TimerFcn', @(s, e) tick(), 'Period', 0.1, ...
        'ExecutionMode', 'fixedSpacing');
    app.timer = tmr;
    app.btnPlay = btnPlay;
    start(tmr);
    fprintf('[GUI] 已打开实时显示（播放中），关闭窗口即停止\n');
end

    function playBack()
        if app.playing
            stop(app.timer); app.playing = false;
            btnPlay.Text = '播放';
        else
            start(app.timer); app.playing = true;
            btnPlay.Text = '暂停';
        end
    end

    function tick()
        app.t = app.t + 0.2;
        if app.t > app.tSec(end)
            app.t = app.tSec(end);
            stop(app.timer); app.playing = false;
            app.btnPlay.Text = '播放';
        end
        updateDisplay(app, app.t);
    end

    function seek()
        app.t = slTime.Value;
        updateDisplay(app, app.t);
    end

    function showMsg()
        idx = app.selSat.Value;
        k = find(strcmp(arrayfun(@(x) sprintf('PRN%d', x), app.prns, ...
            'UniformOutput', false), idx), 1);
        if ~isempty(k)
            app.txMsg.Value = app.msgText{k};
        end
    end
end

%% ---- 工具：刷新显示 ----
function updateDisplay(app, t)
% C/N0 曲线
n = sum(app.tSec <= t);
for i = 1:app.nSat
    c = app.cn0All{i};
    nn = min(n, numel(c));
    set(app.ln(i), 'XData', app.tSec(1:nn), 'YData', c(1:nn));
end
app.slTime.Value = t;

% 状态
app.st.Text = sprintf('状态: %.1f / %.1f s，%d 星跟踪', ...
    t, app.tSec(end), app.nSat);

% 解码电文（选星）
selIdx = 1;
if isvalid(app.selSat)
    v = app.selSat.Value;
    if ~isempty(v)
        selIdx = find(strcmp(arrayfun(@(x) sprintf('PRN%d', x), app.prns, ...
            'UniformOutput', false), v), 1);
        if isempty(selIdx), selIdx = 1; end
    end
end
if t >= app.decTime(selIdx)
    app.txMsg.Value = app.msgText{selIdx};
end

% 定位结果
if t >= app.tSec(end) * 0.9
    app.txPos.Value = sprintf(['定位结果（PASS）\n' ...
        'WGS84: %.6f°N, %.6f°E, %.1f m\n距参考点: %.1f m\n' ...
        'GDOP: %.2f\n伪距残差 RMS: %.1f m\n伪距偏差: %.1f m'], ...
        app.m.lat, app.m.lon, app.m.h, app.m.dPos, app.m.gdop, ...
        app.m.resRms, app.m.dRho);
end
end

%% ---- 工具：电文文本 ----
function txt = navMessageText(t1, dec)
if isempty(dec.syncIndex)
    txt = '未解出子帧';
    return;
end
sf1idx = find([dec.subframes.subframeId] == 1, 1);
if isempty(sf1idx), sf1idx = 1; end
sf  = dec.subframes(sf1idx);
sidx = dec.syncIndex(sf1idx);
bits300 = t1.bits(sidx : sidx + 299);
if dec.polarity(sf1idx) == 0
    bits300 = 1 - bits300;
end
w = reshape(bits300, 30, 10).';
logW = zeros(10, 24);
prevD30 = 0;
for k = 1:10
    logW(k, :) = mod(w(k, 1:24) + prevD30, 2);
    prevD30 = w(k, 30);
end
tow = bi2de(logW(2, 1:17), 'left-msb');
sfid = bi2de(logW(2, 20:22), 'left-msb');
lines = {sprintf('PRN%d 子帧%d TOW=%d', t1.PRN, sfid, tow)};
lines{end+1} = sprintf('TLM 前导码 %s | 消息 %s', ...
    sprintf('%d', logW(1,1:8)), sprintf('%d', logW(1,9:14)));
for k = 3:10
    lines{end+1} = sprintf('W%02d %s %s %s', k, ...
        sprintf('%d', logW(k,1:8)), sprintf('%d', logW(k,9:16)), ...
        sprintf('%d', logW(k,17:24)));
end
txt = strjoin(lines, newline);
end

%% ---- 工具：ECEF → 方位/仰角 ----
function [az, el] = azElFromEcef(Xobs, Xsat)
[lat, lon] = ecef2Geodetic(Xobs);
phi = deg2rad(lat); lam = deg2rad(lon);
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
