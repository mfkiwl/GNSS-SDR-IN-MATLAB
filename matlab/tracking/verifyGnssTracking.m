function results = verifyGnssTracking(varargin)
%VERIFYGNSSTRACKING M3 跟踪验证：TX 合成 GPS + RX 采集 + 捕获 + DLL/PLL 跟踪
%
%   流程：
%     1. 生成 1 个完整子帧电文（300 位，含 ICD-GPS-200 奇偶校验）
%     2. TX transmitRepeat 持续发射（或 Synthetic 离线合成，含注入多普勒/码延迟）
%     3. RX step() 连续流采集
%     4. acquisition 捕获 -> 码相位/多普勒
%     5. tracking DLL+PLL 跟踪 -> C/N0 / 环路残差 / 位同步 / 解调比特
%     6. gnssSubframeDecode 端到端对比（前导码+奇偶校验，0 比特错误）
%     7. 判定：捕获命中 && 环路锁定 && C/N0 达标 && 有效子帧全对
%
%   用法：
%     verifyGnssTracking                                  % 硬件（天线场景默认）
%     verifyGnssTracking('Synthetic', true)               % 离线合成信号模拟
%     verifyGnssTracking('TxGain', -89.75, 'TxAmplitude', 0.034, 'RxGain', 10)
%
%   参数 (Name-Value)：
%     'Synthetic'   - true 离线模拟（不加硬件），默认 false
%     'PRN', 'Fs', 'CenterFreq', 'TxGain', 'TxAmplitude', 'RxGain'
%     'CaptureSec'  - 采集时长（默认 12.5：保证任意位对齐下跟踪段
%                     都含至少 1 个完整 300 位子帧，可做端到端对比）
%     'SyntheticDopplerHz' - 合成模式注入多普勒（默认 +1200）
%     'SyntheticCodePhase' - 合成模式注入码相位（0-based，默认 777）
%     'SyntheticCN0'       - 合成模式 C/N0（默认 45 dB-Hz）
%     'PllBandwidth', 'DllBandwidth', 'CorrSpacing' - 跟踪环路参数

%% ---- 参数 ----
p = struct();
p.Synthetic   = false;
p.PRN         = 5;
p.Fs          = 2.5e6;
p.CenterFreq  = 1575.42e6;
p.TxGain      = -65;
p.TxAmplitude = 0.1;
p.RxGain      = 20;
p.CaptureSec  = 12.5;
p.SyntheticDopplerHz = 1200;
p.SyntheticCodePhase = 777;
p.SyntheticCN0       = 45;
p.PllBandwidth = 18;
p.DllBandwidth = 2;
p.CorrSpacing  = 0.5;

for k = 1:2:numel(varargin)
    key = varargin{k};
    val = varargin{k+1};
    switch lower(key)
        case 'synthetic',        p.Synthetic = val;
        case 'prn',              p.PRN = val;
        case 'fs',               p.Fs = val;
        case 'centerfreq',       p.CenterFreq = val;
        case 'txgain',           p.TxGain = val;
        case 'txamplitude',      p.TxAmplitude = val;
        case 'rxgain',           p.RxGain = val;
        case 'capturesec',       p.CaptureSec = val;
        case 'syntheticdopplerhz', p.SyntheticDopplerHz = val;
        case 'syntheticcodephase', p.SyntheticCodePhase = val;
        case 'syntheticcn0',     p.SyntheticCN0 = val;
        case 'pllbandwidth',     p.PllBandwidth = val;
        case 'dllbandwidth',     p.DllBandwidth = val;
        case 'corrspacing',      p.CorrSpacing = val;
        otherwise, error('未知参数: %s', key);
    end
end

results = struct();
results.params = p;
results.pass = false;
tx = []; rx = []; data = []; buf = [];

try
    %% ---- 1. 生成连续子帧电文 ----
    [sfBits, metas] = generateGpsSubframe(1, 80000, ...
        'TlmMsg', de2bi(21, 6, 'left-msb'));
    results.txBits  = sfBits;
    results.txMetas = metas;
    fprintf('============================================\n');
    fprintf(' M3 跟踪验证：DLL/PLL 实时跟踪（TX 合成 GPS）\n');
    fprintf('============================================\n');
    fprintf('电文   : 1 个子帧（%d 位 = %.1f s），TOW 80000\n', ...
        numel(sfBits), numel(sfBits)/50);

    %% ---- 2. 发射/合成 ----
    buf = generateGnssTxBuffer(p.PRN, p.Fs, ...
        'Amplitude', p.TxAmplitude, 'NavBits', sfBits);
    if numel(buf) > 2^24
        error('TX 缓冲 %d 采样超过 Pluto 上限 2^24', numel(buf));
    end

    nSamp = round(p.Fs * p.CaptureSec);
    if p.Synthetic
        % 离线：重复子帧缓冲到采集长度 + 注入码延迟/多普勒 + 高斯噪声
        nRep = ceil(nSamp / numel(buf));
        data0 = repmat(buf, nRep, 1);
        data0 = data0(1:nSamp);
        data0 = circshift(data0, mod(p.SyntheticCodePhase, numel(data0)));
        tAll = (0:nSamp-1).';
        data0 = data0 .* exp(1j*2*pi*p.SyntheticDopplerHz*tAll/p.Fs);
        sigma = p.TxAmplitude * sqrt(p.Fs / 10^(p.SyntheticCN0/10));
        rng(20260807);
        noise = (randn(nSamp,1) + 1j*randn(nSamp,1)) * sigma/sqrt(2);
        data = data0 + noise;
        truth = struct('codePhase', mod(p.SyntheticCodePhase, ...
            round(p.Fs*1e-3)), 'dopplerHz', p.SyntheticDopplerHz, ...
            'cn0dBHz', p.SyntheticCN0);
        fprintf('[SYN] 合成信号 %d 采样（%.1f s），注入多普勒 %+d Hz，码相位 %d，C/N0=%d dB-Hz\n', ...
            nSamp, nSamp/p.Fs, p.SyntheticDopplerHz, ...
            truth.codePhase, p.SyntheticCN0);
        clear buf;
    else
        r = findPlutoRadio();
        if isempty(r), error('未找到 PlutoSDR'); end
        radioID = r(1).RadioID;
        results.device = r(1);
        fprintf('设备   : %s\n', radioID);
        tx = sdrtx('Pluto', 'RadioID', radioID, ...
            'CenterFrequency', p.CenterFreq, 'BasebandSampleRate', p.Fs, ...
            'Gain', p.TxGain);
        tx.transmitRepeat(buf);
        fprintf('[TX] 已发射 1 子帧合成 GPS（缓冲 %.1f s，增益 %.1f dB）\n', ...
            numel(buf)/p.Fs, p.TxGain);
        pause(0.5);

        fprintf('[RX] step 连续流采集 %.1f s ...\n', p.CaptureSec);
        frameSamples = round(p.Fs * 0.01);        % 10 ms 帧
        rx = sdrrx('Pluto', 'RadioID', radioID, ...
            'CenterFrequency', p.CenterFreq, 'BasebandSampleRate', p.Fs, ...
            'GainSource', 'Manual', 'Gain', p.RxGain, 'OutputDataType', 'double', ...
            'SamplesPerFrame', frameSamples);
        try
            rx.kernelBuffersCount = 32;
        catch
        end
        nFrames = round(nSamp / frameSamples);
        data = zeros(nFrames * frameSamples, 1);
        tCap = tic;
        for k = 1:nFrames
            data((k-1)*frameSamples + (1:frameSamples)) = step(rx);
        end
        fprintf('  连续流采集 %d 帧（%.1f s），耗时 %.1f s，RMS=%.5f 削波=%.2f%%\n', ...
            nFrames, nFrames*frameSamples/p.Fs, toc(tCap), ...
            rms(data), mean(abs(data) > 0.999)*100);
        release(rx); delete(rx); rx = [];
        release(tx); delete(tx); tx = [];
        truth = struct('codePhase', NaN, 'dopplerHz', 0, 'cn0dBHz', NaN);
        clear buf;
    end

    %% ---- 3. 捕获 ----
    fprintf('[ACQ] 捕获 ...\n');
    acq = acquisition(data, p.Fs, 'Verbose', false, ...
        'IntegrationMs', 5, 'NonCoherentN', 10, 'DopplerStep', 100);
    r1 = acq.results([acq.results.PRN] == p.PRN);
    others = [acq.results.metric];
    others([acq.results.PRN] == p.PRN) = -inf;
    dominance = r1.metric / max(max(others), eps);
    fprintf('  PRN %2d: metric=%.1f doppler=%+7.1f Hz codePhase=%5d 检测=%d 领先度=%.1f\n', ...
        p.PRN, r1.metric, r1.dopplerHz, r1.codePhase, r1.detected, dominance);
    results.acq = acq;

    %% ---- 4. DLL/PLL 跟踪 ----
    fprintf('[TRK] DLL+PLL 跟踪（PLL BW=%.0f Hz, DLL BW=%.0f Hz, 间距 %.1f chip）...\n', ...
        p.PllBandwidth, p.DllBandwidth, p.CorrSpacing);
    trk = tracking(data, p.Fs, acq, 'PRNList', p.PRN, ...
        'PllBandwidth', p.PllBandwidth, 'DllBandwidth', p.DllBandwidth, ...
        'CorrSpacing', p.CorrSpacing, 'ReferenceBits', sfBits);
    t1 = trk(1);
    results.trk = t1;

    % 指标（取锁定后段：末尾 1 s）
    nMs  = numel(t1.carrierFreq);
    n1s  = min(1000, nMs);
    fEst = median(t1.carrierFreq(end-n1s+1 : end));
    cn0w = t1.CN0dBHz;
    nW1s = min(50, numel(cn0w));
    cn0Med = median(cn0w(end-nW1s+1 : end));
    dMean = mean(t1.codePhase(end-n1s+1 : end));
    dRes  = mod(t1.codePhase(end-n1s+1 : end) - dMean + ...
                round(p.Fs*1e-3)/2, round(p.Fs*1e-3)) - round(p.Fs*1e-3)/2;
    dStd  = std(dRes);
    fprintf('  CN0=%.1f dB-Hz  f_est=%+8.2f Hz  codePhase std=%.3f samp  lock=%d\n', ...
        cn0Med, fEst, dStd, t1.lock);
    if isfield(t1, 'numErrors')
        fprintf('  比特 vs 参考（双极性）: 误码 %d/%d 匹配率 %.4f 极性=%s\n', ...
            t1.numErrors, numel(t1.bits), t1.matchRate, ...
            ternaryStr(t1.polarity == 1));
    end

    % 与真值/捕获初值对比
    msLen = round(p.Fs*1e-3);
    if p.Synthetic
        fErr = abs(fEst - truth.dopplerHz);
        dErr = abs(mod(dMean - truth.codePhase + msLen/2, msLen) - msLen/2);
        cn0OK = cn0Med >= truth.cn0dBHz - 5 && cn0Med <= truth.cn0dBHz + 5;
        fprintf('  真值对比: f 误差 %.2f Hz（门限 5），码相位误差 %.2f samp（门限 2），C/N0 %s\n', ...
            fErr, dErr, passStr(cn0OK));
    else
        fErr = abs(fEst - 0);
        cn0OK = cn0Med >= 35;
        fprintf('  期望对比: f 误差 %.2f Hz（门限 3），C/N0 达标 %s（门限 35）\n', ...
            fErr, passStr(cn0OK));
        dErr = NaN;
    end
    results.metrics = struct('cn0Median', cn0Med, 'fEst', fEst, ...
        'dStd', dStd, 'fErr', fErr, 'dErr', dErr, 'cn0OK', cn0OK);

    %% ---- 5. 子帧同步 + 解码 + 对比 ----
    fprintf('[SYNC] 子帧同步（前导码 + 奇偶校验）...\n');
    ref = struct('bits', sfBits, 'metas', metas);
    dec = gnssSubframeDecode(t1.bits, 'Reference', ref);
    results.dec = dec;
    fprintf('  有效子帧 %d 个，位同步偏移 %d ms，解调比特 %d 个\n', ...
        numel(dec.syncIndex), t1.bitOffsetMs, numel(t1.bits));
    nOK = 0;
    if isfield(dec, 'compare') && ~isempty(dec.compare)
        for k = 1:numel(dec.compare)
            c = dec.compare(k);
            if c.matched
                fprintf('    子帧 %d: TOW=%d 子帧号=%d 比特错误=%d 匹配=%s\n', ...
                    k, dec.subframes(k).tow, dec.subframes(k).subframeId, ...
                    c.bitErrors, passStr(c.bitErrors == 0));
                if c.tlmMsgOK && c.towOK && c.sfidOK && c.dataOK && c.bitErrors == 0
                    nOK = nOK + 1;
                end
            end
        end
    end

    %% ---- 6. 判定 ----
    acqOK = r1.detected && dominance >= 3;
    if p.Synthetic
        estOK = fErr <= 5 && dErr <= 2;
    else
        estOK = fErr <= 3;
    end
    results.pass = acqOK && t1.lock && cn0OK && estOK && nOK >= 1;
    fprintf('\n============================================\n');
    fprintf(' M3 跟踪验证结论: %s（捕获=%d 锁定=%d C/N0=%d 参数=%d 子帧=%d/%d）\n', ...
        passStr(results.pass), acqOK, t1.lock, cn0OK, estOK, nOK, numel(dec.syncIndex));
    fprintf('============================================\n');

catch err
    fprintf('\n[M3 跟踪验证中断]: %s\n', err.message);
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
pngFile = '';
if isfield(results, 'trk')
    try
        outDir = fullfile(fileparts(mfilename('fullpath')), 'data');
        if ~exist(outDir, 'dir'), mkdir(outDir); end
        ts = datestr(now, 'yyyymmdd_HHMMSS');
        pngFile = fullfile(outDir, ['gnss_tracking_' ts '.png']);
        plotTracking(results, p, truth, pngFile);
        fprintf('图形已保存: %s\n', pngFile);
    catch e
        fprintf('绘图跳过: %s\n', e.message);
    end
end

%% ---- 保存结果 ----
outDir = fullfile(fileparts(mfilename('fullpath')), 'data');
if ~exist(outDir, 'dir'), mkdir(outDir); end
ts = datestr(now, 'yyyymmdd_HHMMSS');
matFile = fullfile(outDir, ['gnss_tracking_' ts '.mat']);
save(matFile, 'results', 'p', 'truth');
fprintf('结果已保存: %s\n', matFile);
end

%% ---- 绘图 ----
function plotTracking(results, p, truth, pngFile)
t1 = results.trk;
msLen = round(p.Fs*1e-3);
nMs = numel(t1.carrierFreq);
tms = (1:nMs)/1000;
fig = figure('Visible', 'off', 'Position', [100 100 1200 800]);

% (1) C/N0
subplot(2,3,1);
nW = numel(t1.CN0dBHz);
plot((1:nW)*0.02, t1.CN0dBHz, 'b', 'LineWidth', 1);
hold on;
if isfinite(truth.cn0dBHz)
    yline(truth.cn0dBHz, 'r--', sprintf('truth %.0f', truth.cn0dBHz));
end
hold off;
xlabel('time (s)'); ylabel('C/N0 (dB-Hz)');
title(sprintf('C/N0 (median %.1f dB-Hz)', median(t1.CN0dBHz)));
grid on;

% (2) 载波频率
subplot(2,3,2);
plot(tms, t1.carrierFreq, 'b', 'LineWidth', 1);
hold on;
if isfinite(truth.dopplerHz)
    yline(truth.dopplerHz, 'r--', sprintf('truth %d', truth.dopplerHz));
end
hold off;
xlabel('time (s)'); ylabel('carrier freq (Hz)');
title(sprintf('PLL carrier freq (last median %+.1f Hz)', ...
    median(t1.carrierFreq(max(1,end-1000):end))));
grid on;

% (3) 码相位残差（相对末段均值/真值）
subplot(2,3,3);
refD = truth.codePhase;
if ~isfinite(refD)
    refD = mean(t1.codePhase(max(1,end-1000):end));
end
resC = mod(t1.codePhase - refD + msLen/2, msLen) - msLen/2;
resChips = resC * 1.023e6 / p.Fs;
plot(tms, resChips, 'b', 'LineWidth', 1);
yline(0, 'r--');
xlabel('time (s)'); ylabel('code phase err (chips)');
title(sprintf('DLL code phase error (std %.3f chip)', ...
    std(resChips(max(1,end-1000):end))));
grid on;

% (4) 鉴别器
subplot(2,3,4);
plot(tms, abs(t1.discrPll), 'b', 'LineWidth', 0.6); hold on;
plot(tms, abs(t1.discrDll), 'r', 'LineWidth', 0.6); hold off;
xlabel('time (s)'); ylabel('discriminator');
legend({'|PLL err| (rad)', '|DLL err| (chip)'}, 'Location', 'northeast');
title(sprintf('Loop discriminators (PLL mean %.3f, DLL mean %.3f)', ...
    mean(abs(t1.discrPll(end-500:end))), mean(abs(t1.discrDll(end-500:end)))));
grid on;

% (5) 锁定后 Prompt 星座
subplot(2,3,5);
n = max(1, nMs-2000);
scatter(t1.I_P(n:end), t1.Q_P(n:end), 4, 'b', 'filled');
hold on;
plot([-max(abs(t1.I_P(n:end)))*1.2 max(abs(t1.I_P(n:end)))*1.2], [0 0], 'k--');
plot([0 0], [-max(abs(t1.Q_P(n:end)))*1.2 max(abs(t1.Q_P(n:end)))*1.2], 'k--');
hold off;
axis equal; grid on;
xlabel('I_P'); ylabel('Q_P');
title('Prompt constellation (last 2 s)');

% (6) 子帧对比
subplot(2,3,6);
if isfield(results.dec, 'compare') && ~isempty(results.dec.compare)
    c = results.dec.compare;
    names = {'TLM','TOW','SFID','DATA','BITS'};
    vals = zeros(numel(c), 5);
    for k = 1:numel(c)
        vals(k, :) = [c(k).tlmMsgOK, c(k).towOK, c(k).sfidOK, c(k).dataOK, ...
                      c(k).bitErrors == 0];
    end
    imagesc(vals);
    colormap(gca, [0.85 0.33 0.10; 0.30 0.65 0.30]);
    set(gca, 'XTick', 1:5, 'XTickLabel', names, 'YTick', 1:numel(c));
    colorbar('Ticks', [0.25 0.75], 'TickLabels', {'FAIL','OK'});
    title('Subframe compare (tracking bits)');
else
    text(0.5, 0.5, 'no valid subframe', 'HorizontalAlignment', 'center', ...
        'Units', 'normalized');
    axis off;
end

exportgraphics(fig, pngFile, 'Resolution', 110);
close(fig);
end

%% ---- 工具函数 ----
function s = passStr(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end

function s = ternaryStr(ok)
if ok, s = 'orig'; else, s = 'INV'; end
end
