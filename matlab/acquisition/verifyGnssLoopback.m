function results = verifyGnssLoopback(varargin)
%VERIFYGNSSLOOPBACK M2 回环验证：PlutoSDR TX 发射合成 GPS + RX 捕获 + 捕获算法
%
%   用法：
%     verifyGnssLoopback                          % 默认参数
%     verifyGnssLoopback('PRN', 8, 'CaptureSec', 2)
%     verifyGnssLoopback('TxGain', -89.75, 'TxAmplitude', 0.034, 'RxGain', 10)  % 回环线
%     verifyGnssLoopback('TxGain', -65)                % 拉杆天线发射（实测推荐）
%
%   流程：
%     1. TX 用 transmitRepeat 发射合成 C/A 码（低功率起步，相位连续）
%     2. RX capture 采集 N 秒
%     3. 停止 TX
%     4. acquisition 捕获，验证命中对应 PRN、多普勒≈0（TX/RX 共时钟）
%
%   输出：
%     results                 - 指标与判定结构体
%     data\gnss_loopback_<时间戳>.mat - 采集数据 + 结果

%% ---- 参数 ----
p = struct();
p.PRN         = 5;
p.Fs          = 2.5e6;
p.CenterFreq  = 1575.42e6;
p.TxGain      = -65;        % Pluto TX Gain: 0=最大输出，负值=衰减（拉杆天线实测推荐）
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

results = struct();
results.params = p;
results.pass = false;
tx = []; rx = []; data = []; buf = [];

try
    %% ---- 设备检测 ----
    r = findPlutoRadio();
    if isempty(r)
        error('未找到 PlutoSDR：请检查 USB 连接。');
    end
    radioID = r(1).RadioID;
    results.device = r(1);

    fprintf('============================================\n');
    fprintf(' M2 回环验证：TX 合成 GPS -> RX 捕获\n');
    fprintf('============================================\n');
    fprintf('设备   : %s (序列号 %s)\n', radioID, r(1).SerialNum);
    fprintf('参数   : PRN %d, %.3f MSPS, %.3f MHz\n', ...
        p.PRN, p.Fs/1e6, p.CenterFreq/1e6);
    fprintf('TX     : 增益 %.1f dB, 幅度 %.2f\n', p.TxGain, p.TxAmplitude);
    fprintf('RX     : 手动增益 %d dB, 采集 %d s\n', p.RxGain, p.CaptureSec);

    %% ---- 1. 启动 TX ----
    buf = generateGnssTxBuffer(p.PRN, p.Fs, 'Amplitude', p.TxAmplitude);
    tx = sdrtx('Pluto', 'RadioID', radioID, ...
        'CenterFrequency', p.CenterFreq, 'BasebandSampleRate', p.Fs, ...
        'Gain', p.TxGain);
    tx.transmitRepeat(buf);
    fprintf('\n[TX] 已发射 PRN %d 合成 C/A 码（缓冲 %d ms，相位连续）\n', ...
        p.PRN, numel(buf)/p.Fs*1000);
    pause(0.5);   % 等发射稳定

    %% ---- 2. RX 采集 ----
    fprintf('[RX] capture 采集 %d s ...\n', p.CaptureSec);
    rx = sdrrx('Pluto', 'RadioID', radioID, ...
        'CenterFrequency', p.CenterFreq, 'BasebandSampleRate', p.Fs, ...
        'GainSource', 'Manual', 'Gain', p.RxGain, 'OutputDataType', 'double');
    nSamp = round(p.Fs * p.CaptureSec);
    tCap = tic;
    data = capture(rx, nSamp);
    capTime = toc(tCap);
    release(rx); delete(rx); rx = [];
    fprintf('  采集 %d 采样（%.1f s @ %.2f MSPS），耗时 %.1f s\n', ...
        numel(data), numel(data)/p.Fs, p.Fs/1e6, capTime);

    % 停止 TX
    release(tx); delete(tx); tx = [];
    fprintf('[TX] 已停止发射\n');

    %% ---- 3. 信号质量检查 ----
    rmsV = rms(data);
    pk   = max(abs(data));
    clip = mean(abs(data) > 0.999);
    results.rx.rms = rmsV;
    results.rx.peak = pk;
    results.rx.clipRatio = clip;
    fprintf('  信号校验: RMS=%.4f 峰值=%.4f 削波=%.2f%%\n', rmsV, pk, clip*100);
    if clip > 0.01
        warning('削波 %.1f%%：信号过强，建议降低 TxGain/TxAmplitude 或 RxGain。', clip*100);
    end

    %% ---- 4. 捕获 ----
    fprintf('[ACQ] 捕获（%d ms 相干 x %d 块，DopplerStep=%d）...\n', ...
        p.IntegrationMs, p.NonCoherentN, p.DopplerStep);
    acq = acquisition(data, p.Fs, 'Verbose', false, ...
        'IntegrationMs', p.IntegrationMs, ...
        'NonCoherentN',  p.NonCoherentN, ...
        'DopplerStep',   p.DopplerStep);

    r1 = acq.results([acq.results.PRN] == p.PRN);
    results.acq = acq;
    fprintf('  PRN %2d: metric=%.1f doppler=%+7.1f Hz codePhase=%5d 检测=%d\n', ...
        p.PRN, r1.metric, r1.dopplerHz, r1.codePhase, r1.detected);

    % 排序展示前 8 名
    [~, idx] = sort([acq.results.metric], 'descend');
    fprintf('  指标前 8 名: ');
    for k = idx(1:min(8, numel(idx)))
        fprintf('PRN%d(%.1f) ', acq.results(k).PRN, acq.results(k).metric);
    end
    fprintf('\n');

    %% ---- 5. 判定 ----
    dopOK = abs(r1.dopplerHz) <= 150;   % 共时钟，预期≈0 Hz，允许 ±1 个格点
    % 目标星指标须显著领先其他 PRN（强信号 C/A 码互相关会产生伪峰，
    % 真实 GPS 信号电平下互相关低于门限；回环强信号下靠领先度判定）
    others = [acq.results.metric];
    others([acq.results.PRN] == p.PRN) = -inf;
    secondMetric = max(others);
    dominance = r1.metric / max(secondMetric, eps);
    domOK = dominance >= 3;
    results.rx.dopplerOK = dopOK;
    results.rx.secondMetric = secondMetric;
    results.rx.dominance = dominance;
    results.pass = r1.detected && dopOK && domOK;
    fprintf('  领先度: 目标 %.1f vs 次高 %.1f（比值 %.1f）-> %s\n', ...
        r1.metric, secondMetric, dominance, passStr(domOK));
    fprintf('\n============================================\n');
    fprintf(' M2 回环验证结论: %s（命中 PRN %d，多普勒 %+.1f Hz）\n', ...
        passStr(results.pass), p.PRN, r1.dopplerHz);
    fprintf('============================================\n');

catch err
    fprintf('\n[M2 回环验证中断]: %s\n', err.message);
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

%% ---- 保存结果 ----
outDir = fullfile(fileparts(mfilename('fullpath')), 'data');
if ~exist(outDir, 'dir'), mkdir(outDir); end
ts = datestr(now, 'yyyymmdd_HHMMSS');
matFile = fullfile(outDir, ['gnss_loopback_' ts '.mat']);
save(matFile, 'data', 'buf', 'results', 'p');
fprintf('结果已保存: %s\n', matFile);
end

%% ---- 工具函数 ----
function s = passStr(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end
