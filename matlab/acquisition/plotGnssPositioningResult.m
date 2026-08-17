function results = plotGnssPositioningResult(matFile)
%PLOTGNSSPOSITIONINGRESULT M4.2 多星定位结果可视化
%   用法：
%     plotGnssPositioningResult                       % 默认取 data 下最新 gnss_positioning_*.mat
%     plotGnssPositioningResult('D:\13_MCP\GNSS\data\gnss_positioning_20260817_172353.mat')
%   输出：data\gnss_positioning_plot_<时间戳>.png
%   面板：捕获指标 / 跟踪 CN0 / ENU 定位误差 / 伪距一致性

dataDir = fullfile(fileparts(mfilename('fullpath')), 'data');
if nargin < 1 || isempty(matFile)
    f = dir(fullfile(dataDir, 'gnss_positioning_*.mat'));
    if isempty(f), error('No gnss_positioning_*.mat found in %s', dataDir); end
    [~, idx] = sort([f.datenum]);
    matFile = fullfile(dataDir, f(idx(end)).name);
end

d = load(matFile);
r = d.results;

% ---- 参数与坐标 ----
prnsInj = r.injected.prns(:)';
fs = r.params.Fs;
c = 299792458;
X0 = r.injected.X0(:);
posEst = r.posEst(:);
dPos = posEst - X0;
errM = norm(dPos);
latR = r.params.RefLat*pi/180;
lonR = r.params.RefLon*pi/180;
Renu = [-sin(lonR) cos(lonR) 0; ...
        -sin(latR)*cos(lonR) -sin(latR)*sin(lonR) cos(latR); ...
         cos(latR)*cos(lonR)  cos(latR)*sin(lonR) sin(latR)];
enu = Renu*dPos;

% ---- 捕获指标 ----
acqPRN = [r.acq.results.PRN];
acqMet = [r.acq.results.metric];

% ---- 跟踪 CN0（末 50 个 20 ms 窗口的中值）----
cn0s = nan(1, numel(r.trk));
for k = 1:numel(r.trk)
    cn0v = r.trk(k).CN0dBHz(:);
    nw = min(50, numel(cn0v));
    cn0s(k) = median(cn0v(end-nw+1:end));
end

% ---- 伪距偏差 ----
dRho = r.metrics.dRho;
if numel(dRho) == numel(prnsInj)
    dRhoVec = dRho(:)';
else
    relMeas = (r.rho(:) - r.rho(1));
    relInj  = (r.injected.delays(:) - r.injected.delays(1))/fs*c;
    dRhoVec = abs(relMeas - relInj);
end

% ---- 绘图 ----
fig = figure('Visible','off','Position',[80 80 1280 880]);

% 面板 1：捕获指标
subplot(2,2,1);
yAll = zeros(32,1);
yAll(acqPRN) = acqMet;
b = bar(1:32, yAll, 'FaceColor', [0.75 0.75 0.75], 'EdgeColor', 'none');
hold on;
yInj = zeros(32,1);
yInj(prnsInj) = yAll(prnsInj);
bar(prnsInj, yInj(prnsInj), 'FaceColor', [0.85 0.33 0.10], 'EdgeColor', 'none');
yline(6, 'k--', 'LineWidth', 1.2);
ylabel('metric'); xlabel('PRN'); xlim([0 33]);
title(sprintf('Acquisition metrics (6 injected in orange, %d above thr)', sum(acqMet>6)));
grid on;

% 面板 2：跟踪 CN0
subplot(2,2,2);
b2 = bar(1:numel(prnsInj), cn0s, 'FaceColor', [0.10 0.45 0.80], 'EdgeColor', 'none');
hold on;
for k = 1:numel(prnsInj)
    text(k, cn0s(k)+0.6, sprintf('PRN%d\n%.1f', prnsInj(k), cn0s(k)), ...
        'HorizontalAlignment','center', 'FontSize', 9);
end
ylim([min(cn0s)-3 max(cn0s)+5]);
ylabel('CN0 (dB-Hz)'); xlabel('Satellite');
set(gca,'XTick',1:numel(prnsInj),'XTickLabel',arrayfun(@(x)sprintf('%d',x),prnsInj,'UniformOutput',false));
title('Tracking CN0 (median of last 50 x 20 ms)');
grid on;

% 面板 3：ENU 定位误差
subplot(2,2,3);
plot(0, 0, 'g+', 'MarkerSize', 14, 'LineWidth', 2); hold on;
plot(enu(1), enu(2), 'ro', 'MarkerSize', 10, 'LineWidth', 2);
th = linspace(0, 2*pi, 200);
plot(errM*cos(th), errM*sin(th), 'r--', 'LineWidth', 1);
lim = max(errM*1.4, 50);
xlim([-lim lim]); ylim([-lim lim]);
axis equal; grid on;
xlabel('East (m)'); ylabel('North (m)');
legend('Reference', 'Estimate', 'Error circle', 'Location','best');
title(sprintf('Position error %.1f m (ENU: E %.1f, N %.1f, U %.1f)', ...
              errM, enu(1), enu(2), enu(3)));

% 面板 4：伪距一致性
subplot(2,2,4);
bar(1:numel(prnsInj), dRhoVec, 'FaceColor', [0.35 0.60 0.25], 'EdgeColor', 'none');
hold on;
for k = 1:numel(prnsInj)
    text(k, dRhoVec(k)+max(dRhoVec)*0.05, sprintf('%.1f', dRhoVec(k)), ...
        'HorizontalAlignment','center', 'FontSize', 9);
end
ylabel('deviation (m)'); xlabel('Satellite');
set(gca,'XTick',1:numel(prnsInj),'XTickLabel',arrayfun(@(x)sprintf('%d',x),prnsInj,'UniformOutput',false));
title(sprintf('Pseudo-range deviation vs injected (max %.1f m)', max(dRhoVec)));
grid on;

sgtitle(sprintf('M4.2 hardware multi-sat positioning %s | error %.1f m | GDOP %.2f | CN0 %.1f dB-Hz | %s', ...
    passStr(r.pass), errM, r.metrics.gdop, mean(cn0s), datestr(now,'yyyy-mm-dd HH:MM')));

ts = datestr(now,'yyyymmdd_HHMMSS');
png = fullfile(dataDir, ['gnss_positioning_plot_' ts '.png']);
exportgraphics(fig, png, 'Resolution', 150);
close(fig);
fprintf('Figure saved: %s\n', png);
results = struct('file',png,'matFile',matFile,'posErrM',errM,'gdop',r.metrics.gdop, ...
                 'cn0Mean',mean(cn0s),'cn0PerSat',cn0s);
end

function s = passStr(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end
