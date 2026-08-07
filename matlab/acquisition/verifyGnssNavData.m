function results = verifyGnssNavData(varargin)
%VERIFYGNSSNAVDATA M2.5 验证：TX 发射带 50 bps 导航电文的合成 GPS + RX 解调
%
%   用法：
%     verifyGnssNavData                                % 默认（天线场景）
%     verifyGnssNavData('TxGain', -89.75, 'TxAmplitude', 0.034, 'RxGain', 10)  % 回环线
%     verifyGnssNavData('NavBits', [1 0 0 0 1 0 1 1 1 0 1 0 0 1 0 1])
%
%   流程：
%     1. 构造已知 NavBits（默认 40 位，GPS TLM 前导码 10001011 开头）
%     2. TX transmitRepeat 发射（缓冲 = 20*N ms，整数码周期/电文比特）
%     3. RX capture 采集
%     4. acquisition 捕获 → 码相位/多普勒
%     5. demodulateNavBits 解调 → 与参考对比
%     6. 画图 + 存数据 + 判定（捕获命中 且 0 比特错误）
%
%   输出：
%     results                      - 指标与判定
%     data\gnss_navdata_<时间戳>.mat - 采集数据 + 解调结果
%     data\gnss_navdata_<时间戳>.png - 图形

%% ---- 参数 ----
p = struct();
p.PRN         = 5;
p.NavBits     = [];
p.Fs          = 2.5e6;
p.CenterFreq  = 1575.42e6;
p.TxGain      = -65;        % 拉杆天线场景实测推荐；回环线用 -89.75
p.TxAmplitude = 0.1;
p.RxGain      = 20;
p.CaptureSec  = 2;
p.IntegrationMs = 5;
p.NonCoherentN  = 10;
p.DopplerStep   = 100;

for k = 1:2:numel(varargin)
    key = varargin{k};
    val = varargin{k+1};
    switch lower(key)
        case 'prn',           p.PRN = val;
        case 'navbits',       p.NavBits = val(:).';
        case 'fs',            p.Fs = val;
        case 'centerfreq',    p.CenterFreq = val;
        case 'txgain',        p.TxGain = val;
        case 'txamplitude',   p.TxAmplitude = val;
        case 'rxgain',        p.RxGain = val;
        case 'capturesec',    p.CaptureSec = val;
        case 'integrationms', p.IntegrationMs = val;
        case 'noncoherentn',  p.NonCoherentN = val;
        case 'dopplerstep',   p.DopplerStep = val;
        otherwise, error('未知参数: %s', key);
    end
end

%% ---- 默认导航电文（40 位：GPS TLM 前导码 + 固定测试序列，可复现）----
if isempty(p.NavBits)
    rng(20260807);
    p.NavBits = [1 0 0 0 1 0 1 1, randi([0 1], 1, 32)];
end

results = struct();
results.params = p;
results.pass = false;
tx = []; rx = []; data = []; buf = [];

try
    %% ---- 设备检测 ----
    r = findPlutoRadio();
    if isempty(r), error('未找到 PlutoSDR'); end
    radioID = r(1).RadioID;
    results.device = r(1);

    fprintf('============================================\n');
    fprintf(' M2.5 导航电文验证：TX 合成 GPS(50 bps) -> RX 解调\n');
    fprintf('============================================\n');
    fprintf('设备   : %s (序列号 %s)\n', radioID, r(1).SerialNum);
    fprintf('PRN %d, 电文 %d 位, TX %.1f dB, RX %d dB\n', ...
        p.PRN, numel(p.NavBits), p.TxGain, p.RxGain);
    fprintf('前导码: %s（GPS TLM 10001011）\n', mat2str(p.NavBits(1:8)));

    %% ---- 1. TX 发射（缓冲 = 20*N ms，整数码周期与电文比特）----
    buf = generateGnssTxBuffer(p.PRN, p.Fs, ...
        'Amplitude', p.TxAmplitude, 'NavBits', p.NavBits);
    tx = sdrtx('Pluto', 'RadioID', radioID, ...
        'CenterFrequency', p.CenterFreq, 'BasebandSampleRate', p.Fs, ...
        'Gain', p.TxGain);
    tx.transmitRepeat(buf);
    fprintf('\n[TX] 已发射 PRN %d 合成 GPS（缓冲 %d ms = %d 位 x 20 ms）\n', ...
        p.PRN, numel(buf)/p.Fs*1000, numel(p.NavBits));
    pause(0.5);

    %% ---- 2. RX 采集 ----
    fprintf('[RX] capture 采集 %d s ...\n', p.CaptureSec);
    rx = sdrrx('Pluto', 'RadioID', radioID, ...
        'CenterFrequency', p.CenterFreq, 'BasebandSampleRate', p.Fs, ...
        'GainSource', 'Manual', 'Gain', p.RxGain, 'OutputDataType', 'double');
    data = capture(rx, round(p.Fs * p.CaptureSec));
    release(rx); delete(rx); rx = [];
    release(tx); delete(tx); tx = [];
    fprintf('  采集 %d 采样（%.2f s），RMS=%.5f 削波=%.2f%%\n', ...
        numel(data), numel(data)/p.Fs, rms(data), mean(abs(data)>0.999)*100);

    %% ---- 3. 捕获 ----
    fprintf('[ACQ] 捕获（%d ms 相干 x %d 块）...\n', p.IntegrationMs, p.NonCoherentN);
    acq = acquisition(data, p.Fs, 'Verbose', false, ...
        'IntegrationMs', p.IntegrationMs, ...
        'NonCoherentN',  p.NonCoherentN, ...
        'DopplerStep',   p.DopplerStep);
    r1 = acq.results([acq.results.PRN] == p.PRN);
    fprintf('  PRN %2d: metric=%.1f doppler=%+7.1f Hz codePhase=%5d 检测=%d\n', ...
        p.PRN, r1.metric, r1.dopplerHz, r1.codePhase, r1.detected);
    results.acq = acq;

    %% ---- 4. 解调 50 bps 电文 ----
    fprintf('[DEMOD] 解调 50 bps 导航电文（%d 位 x 20 ms）...\n', numel(p.NavBits));
    out = demodulateNavBits(data, p.Fs, acq, p.PRN, ...
        'ReferenceBits', p.NavBits);
    results.demod = out;
    fprintf('  位同步偏移: %d ms\n', out.bitOffsetMs);
    fprintf('  解调位数: %d, 参考 %d 位循环对齐\n', numel(out.bits), numel(p.NavBits));
    fprintf('  比特错误: %d/%d（匹配率 %.3f）\n', ...
        out.numErrors, numel(out.bits), out.matchRate);

    %% ---- 5. 判定 ----
    results.pass = r1.detected && out.numErrors == 0;
    fprintf('\n============================================\n');
    fprintf(' M2.5 导航电文验证结论: %s\n', passStr(results.pass));
    fprintf('============================================\n');

catch err
    fprintf('\n[M2.5 验证中断]: %s\n', err.message);
    results.error = err.message;
    results.pass = false;
end

%% ---- 清理设备 ----
for obj = {rx, tx}
    o = obj{1};
    if ~isempty(o) && isvalid(o)
        try, release(o); catch, end
        try, delete(o); catch, end
    end
end

%% ---- 画图 ----
ts = datestr(now, 'yyyymmdd_HHMMSS');
pngFile = '';
if results.pass || isfield(results, 'demod')
    try
        outDir = fullfile(fileparts(mfilename('fullpath')), 'data');
        if ~exist(outDir, 'dir'), mkdir(outDir); end
        pngFile = fullfile(outDir, ['gnss_navdata_' ts '.png']);
        plotNavData(results, p, pngFile);
        fprintf('图形已保存: %s\n', pngFile);
    catch e
        fprintf('绘图跳过: %s\n', e.message);
    end
end

%% ---- 保存结果 ----
outDir = fullfile(fileparts(mfilename('fullpath')), 'data');
if ~exist(outDir, 'dir'), mkdir(outDir); end
matFile = fullfile(outDir, ['gnss_navdata_' ts '.mat']);
if ~exist('out', 'var'), out = []; end
save(matFile, 'data', 'buf', 'results', 'p', 'out');
fprintf('结果已保存: %s\n', matFile);
end

%% ---- 绘图 ----
function plotNavData(results, p, pngFile)
acq = results.acq;
out = results.demod;
fig = figure('Visible', 'off', 'Position', [100 100 1100 760]);

% (1) 捕获指标
subplot(2,2,1);
mets = [acq.results.metric];
bar(1:32, mets, 'FaceColor', [0.6 0.6 0.6]);
hold on;
bar(p.PRN, mets(p.PRN), 'FaceColor', [0.85 0.33 0.10]);
hold off;
xlabel('PRN'); ylabel('metric');
title(sprintf('Acquisition metrics (PRN %d = %.1f)', p.PRN, mets(p.PRN)));
grid on;

% (2) 解调软值 + 参考比特
subplot(2,2,2);
stem(1:numel(out.soft), out.soft, 'MarkerSize', 3);
hold on;
if isfield(out, 'refBits') && ~isempty(out.refBits)
    rb = out.refBits(:)';
    plot(find(rb==1), out.soft(rb==1), 'ro', 'MarkerSize', 6, 'LineStyle', 'none');
    plot(find(rb==0), out.soft(rb==0), 'bo', 'MarkerSize', 6, 'LineStyle', 'none');
end
if isfield(out, 'numErrors') && out.numErrors > 0 && isfield(out, 'refBits')
    errIdx = find(out.bits ~= out.refBits);
    plot(errIdx, out.soft(errIdx), 'kx', 'MarkerSize', 10, 'LineWidth', 2);
end
hold off;
xlabel('bit index'); ylabel('soft value');
title(sprintf('Demod soft values (errors=%d)', out.numErrors));
legend({'soft', 'ref=1', 'ref=0'}, 'Location', 'best');
grid on;

% (3) 每比特能量
subplot(2,2,3);
plot(abs(out.acc), '.-');
xlabel('bit index'); ylabel('|20ms corr|');
title('Per-bit coherent energy');
grid on;

% (4) 位同步偏移候选得分
subplot(2,2,4);
stem(0:19, out.bitScores, 'MarkerSize', 4);
hold on;
stem(out.bitOffsetMs, out.bitScores(out.bitOffsetMs+1), 'r', 'LineWidth', 2);
hold off;
xlabel('bit sync offset (ms)'); ylabel('match count');
title(sprintf('Bit sync search (best = %d ms)', out.bitOffsetMs));
grid on;

exportgraphics(fig, pngFile, 'Resolution', 110);
close(fig);
end

%% ---- 工具函数 ----
function s = passStr(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end
