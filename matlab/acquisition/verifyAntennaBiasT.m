function results = verifyAntennaBiasT(varargin)
%VERIFYANTENNABIAST 有源 GPS 天线：直连 vs Bias-T 增益对比测量
%   用法（配合硬件接线切换）：
%     verifyAntennaBiasT('Case','Cal')      % 先接好 Bias-T（天线->BiasT->RX1A，DC 供电），自动定 TX 增益
%     verifyAntennaBiasT('Case','BiasT')    % Bias-T 情况全测（6 频点单音 + 1500~1600 频谱 + 噪声底）
%     verifyAntennaBiasT('Case','Direct')   % 直连情况全测（与 BiasT 同 TX 增益）
%     verifyAntennaBiasT('Case','Compare')  % 载入两次结果，输出对比表 + 叠加频谱图
%   参数：'Case','TxGain','TxFreqsMHz','FsTone','FsSpec','RxGain',
%         'ToneOffsetHz','ToneAmp','SpecCentersMHz','TargetPeakDbF',
%         'CaptureSecTone','SpecSec','DataDir'
%   说明：
%     - RX 增益固定手动（默认 40 dB），两种情况保持一致，AGC 关闭；
%     - 全景频谱受 AD9361 瞬时带宽 / USB 限制，分段拼接（默认 20 MSPS x 5 段）；
%     - TX 单音为基带 +100 kHz 偏移的 CW，缓冲 3 ms（整数周期，相位连续）；
%     - 结果保存 data\antenna_<case>_<时间戳>.mat，Compare 输出 PNG。

p = struct();
p.Case             = 'BiasT';
p.TxGain           = nan;              % NaN=从 Cal 文件读取
p.TxFreqsMHz       = 1555:5:1580;      % 单音频点 (MHz)
p.FsTone           = 2.5e6;            % 单音测量采样率
p.FsSpec           = 20e6;             % 频谱拼接采样率
p.RxGain           = 40;               % RX 手动增益 (dB)，两情况必须一致
p.ToneOffsetHz     = 100e3;            % 单音基带偏移（避开 DC/本振泄漏）
p.ToneAmp          = 0.1;              % 单音幅度
p.SpecCentersMHz   = [1500 1520 1540 1560 1580];  % 频谱分段中心 (MHz)
p.TargetPeakDbF    = -6;               % Cal 目标峰值（BiasT 下）
p.ClipGuardDbF     = -2;               % 削波警戒线
p.CaptureSecTone   = 0.5;              % 单音捕获时长 (s)
p.SpecSec          = 0.3;              % 每段频谱捕获时长 (s)
p.SweepGains       = [-89.75 -80 -70 -60 -50 -40 -30 -20];  % Cal 扫描 TX 增益
p.SpecFreqRangeMHz = [1500 1600];      % 频谱图显示范围 (MHz)
p.NumAverages      = 1;                % 每频点捕获次数（取中值平滑多径）
p.DataDir          = fullfile(fileparts(mfilename('fullpath')), 'data');

for k = 1:2:numel(varargin)
    key = lower(varargin{k});
    val = varargin{k+1};
    switch key
        case 'case',              p.Case = val;
        case 'txgain',            p.TxGain = val;
        case 'txfreqsmhz',        p.TxFreqsMHz = val;
        case 'fstone',            p.FsTone = val;
        case 'fsspec',            p.FsSpec = val;
        case 'rxgain',            p.RxGain = val;
        case 'toneoffsethz',      p.ToneOffsetHz = val;
        case 'toneamp',           p.ToneAmp = val;
        case 'speccentersmhz',    p.SpecCentersMHz = val;
        case 'targetpeakdbf',     p.TargetPeakDbF = val;
        case 'capturesectone',    p.CaptureSecTone = val;
        case 'specsec',           p.SpecSec = val;
        case 'specfreqrangemhz',  p.SpecFreqRangeMHz = val;
        case 'numaverages',       p.NumAverages = val;
        case 'datadir',           p.DataDir = val;
        otherwise, error('Unknown param: %s', key);
    end
end

if ~exist(p.DataDir, 'dir'), mkdir(p.DataDir); end

switch lower(p.Case)
    case 'cal'
        results = runCal(p);
    case {'biast', 'direct'}
        results = runCase(p, lower(p.Case));
    case 'compare'
        results = runCompare(p);
    case 'specplot'
        results = runSpecPlot(p);
    otherwise
        error('Unknown Case: %s', p.Case);
end
end

%% ---- 设备 ----
function [radioID, dev] = getRadio()
r = findPlutoRadio();
if isempty(r)
    error('No Pluto radio found. Check USB and power.');
end
radioID = r(1).RadioID;
dev = r(1);
fprintf('Device: %s serial=%s\n', radioID, dev.SerialNum);
end

%% ---- Cal：自动定 TX 增益（需 BiasT 接好并供电）----
function results = runCal(p)
fprintf('===== CAL: find TX gain (Bias-T connected) =====\n');
[radioID, dev] = getRadio();
ng = numel(p.SweepGains);
peaks = nan(ng,1);
txGain = p.SweepGains(1);
fprintf('%-9s %-10s %-9s %-6s\n', 'TxGain', 'Peak_dB', 'RMS_dB', 'Clip');
for i = 1:ng
    g = p.SweepGains(i);
    m = measureToneAt(radioID, p, 1575.42e6, g);
    peaks(i) = m.peakDbF;
    fprintf('%-9.2f %-10.1f %-9.1f %-6d\n', g, m.peakDbF, m.rmsDbF, m.clip);
    txGain = g;
    if m.peakDbF >= p.TargetPeakDbF || m.clip > 0 || m.peakDbF > p.ClipGuardDbF
        break;
    end
end
if peaks(end) < p.TargetPeakDbF
    fprintf('WARN: target not reached within sweep; using last gain %.2f dB.\n', txGain);
end
results = struct('case','Cal','txGain',txGain,'sweepGains',p.SweepGains, ...
                 'peaks',peaks,'device',dev,'params',p);
ts = datestr(now,'yyyymmdd_HHMMSS');
fn = fullfile(p.DataDir, ['antenna_cal_' ts '.mat']);
save(fn, 'results');
fprintf('CAL DONE: TxGain = %.2f dB -> %s\n', txGain, fn);
end

%% ---- 单情况全测 ----
function results = runCase(p, caseName)
cal = loadLatestCal(p.DataDir);
if isnan(p.TxGain)
    if isempty(cal)
        error('No cal file found and TxGain not given. Run CAL first.');
    end
    txGain = cal.txGain;
else
    txGain = p.TxGain;
end
fprintf('===== CASE %s (TxGain=%.2f dB, RxGain=%.0f dB) =====\n', ...
        upper(caseName), txGain, p.RxGain);
[radioID, dev] = getRadio();

nf = numel(p.TxFreqsMHz);
tone = repmat(struct('freqMHz',nan,'offsetHz',nan,'ampLin',nan, ...
                     'ampDbF',nan,'snrDb',nan,'clip',nan,'rmsDbF',nan), nf, 1);
fprintf('%-9s %-11s %-11s %-9s %-6s\n', 'f_MHz', 'Peak_dB', 'Offset_Hz', 'SNR_dB', 'Clip');
for i = 1:nf
    cf = p.TxFreqsMHz(i)*1e6;
    if p.NumAverages > 1
        m = measureToneAvg(radioID, p, cf, txGain, p.NumAverages);
    else
        m = measureToneAt(radioID, p, cf, txGain);
    end
    tone(i).freqMHz = (cf + m.offsetHz)/1e6;
    tone(i).offsetHz = m.offsetHz;
    tone(i).ampLin   = m.ampLin;
    tone(i).ampDbF   = m.peakDbF;
    tone(i).snrDb    = m.snrDb;
    tone(i).clip     = m.clip;
    tone(i).rmsDbF   = m.rmsDbF;
    tone(i).nAvg     = m.nAvg;
    fprintf('%-9.1f %-11.1f %-11.1f %-9.1f %-6d\n', ...
            p.TxFreqsMHz(i), m.peakDbF, m.offsetHz, m.snrDb, m.clip);
end

noise = measureNoise(radioID, p);
fprintf('Noise floor @1575.42 MHz: RMS=%.1f dBFS\n', noise.rmsDbF);

spec = runSpec(radioID, p);

results = struct('case',caseName,'txGain',txGain,'tone',tone, ...
                 'noiseRmsDbF',noise.rmsDbF,'spec',spec, ...
                 'device',dev,'params',p);
ts = datestr(now,'yyyymmdd_HHMMSS');
fn = fullfile(p.DataDir, ['antenna_' caseName '_' ts '.mat']);
save(fn, 'results');
fprintf('CASE %s DONE -> %s\n', upper(caseName), fn);
end

%% ---- 对比 ----
function results = runCompare(p)
bt = loadLatest(p.DataDir, 'antenna_BiasT_*.mat');
dr = loadLatest(p.DataDir, 'antenna_Direct_*.mat');
if isempty(bt) || isempty(dr)
    error('Need both BiasT and Direct result files.');
end
fprintf('===== COMPARE =====\n');
fprintf('BiasT : %s\n', bt.src);
fprintf('Direct: %s\n', dr.src);
fprintf('TxGain: BiasT %.2f / Direct %.2f dB | RxGain %.0f dB\n', ...
        bt.r.txGain, dr.r.txGain, bt.r.params.RxGain);

n = numel(bt.r.tone);
delta = nan(n,1);
fprintf('%-9s %-11s %-11s %-9s\n', 'f_MHz', 'Direct_dB', 'BiasT_dB', 'Delta_dB');
for i = 1:n
    delta(i) = bt.r.tone(i).ampDbF - dr.r.tone(i).ampDbF;
    fprintf('%-9.1f %-11.1f %-11.1f %-9.2f\n', ...
            bt.r.tone(i).freqMHz, dr.r.tone(i).ampDbF, bt.r.tone(i).ampDbF, delta(i));
end
fprintf('Delta: mean=%.2f dB  std=%.2f dB  min=%.2f  max=%.2f\n', ...
        mean(delta), std(delta), min(delta), max(delta));

fig = figure('Visible','off','Position',[100 100 1100 780]);
subplot(2,2,1);
yyaxis left;
plot(dr.r.spec.freqMHz, dr.r.spec.psdDb, 'b', 'LineWidth', 1); hold on;
plot(bt.r.spec.freqMHz, bt.r.spec.psdDb, 'r', 'LineWidth', 1);
ylabel('PSD (dBFS/Hz)');
yyaxis right;
plot([dr.r.tone.freqMHz], [dr.r.tone.ampDbF], 'bo', 'MarkerSize', 7);
plot([bt.r.tone.freqMHz], [bt.r.tone.ampDbF], 'ro', 'MarkerSize', 7);
ylabel('Tone amplitude (dBFS)');
xlim([1500 1600]); grid on;
xlabel('Frequency (MHz)');
title('RX spectrum 1500-1600 MHz (stitched)');
legend('Direct PSD','Bias-T PSD','Direct tone','Bias-T tone','Location','best');
subplot(2,2,2);
plot([dr.r.tone.freqMHz], [dr.r.tone.ampDbF], 'b-o'); hold on;
plot([bt.r.tone.freqMHz], [bt.r.tone.ampDbF], 'r-o');
grid on; xlabel('Frequency (MHz)'); ylabel('Tone amplitude (dBFS)');
title('Tone amplitude vs frequency'); legend('Direct','Bias-T');
subplot(2,2,3);
plot([bt.r.tone.freqMHz], delta, 'k-o', 'LineWidth', 1.5);
grid on; xlabel('Frequency (MHz)'); ylabel('Delta (dB)');
title('Gain difference: BiasT - Direct');
subplot(2,2,4); axis off;
txt = sprintf(['Compare summary\n' ...
    'Delta mean=%.2f dB (std %.2f)\n' ...
    'RxGain=%.0f dB  TxGain=%.2f dB\n' ...
    'Noise floor: Direct %.1f / BiasT %.1f dBFS\n' ...
    'TX-RX: whip -> active antenna, 1.2 m'], ...
    mean(delta), std(delta), bt.r.params.RxGain, bt.r.txGain, ...
    dr.r.noiseRmsDbF, bt.r.noiseRmsDbF);
text(0.05, 0.5, txt, 'Units','normalized', 'FontSize', 11);
ts = datestr(now,'yyyymmdd_HHMMSS');
png = fullfile(p.DataDir, ['antenna_compare_' ts '.png']);
exportgraphics(fig, png, 'Resolution', 130);
close(fig);
fprintf('Figure saved: %s\n', png);
results = struct('case','Compare','deltaDb',delta,'biasT',bt.r,'direct',dr.r, ...
                 'biasTFile',bt.src,'directFile',dr.src);
end

%% ---- 单独输出频谱图 ----
function results = runSpecPlot(p)
bt = loadLatest(p.DataDir, 'antenna_BiasT_*.mat');
dr = loadLatest(p.DataDir, 'antenna_Direct_*.mat');
if isempty(bt) || isempty(dr)
    error('Need both BiasT and Direct result files.');
end
fig = figure('Visible','off','Position',[100 100 1280 620]);
yyaxis left;
plot(dr.r.spec.freqMHz, dr.r.spec.psdDb, 'b', 'LineWidth', 1.2); hold on;
plot(bt.r.spec.freqMHz, bt.r.spec.psdDb, 'r', 'LineWidth', 1.2);
ylabel('PSD (dBFS/Hz)');
yyaxis right;
plot([dr.r.tone.freqMHz], [dr.r.tone.ampDbF], 'bo', 'MarkerSize', 8, 'LineWidth', 1.2);
plot([bt.r.tone.freqMHz], [bt.r.tone.ampDbF], 'ro', 'MarkerSize', 8, 'LineWidth', 1.2);
ylabel('Tone amplitude (dBFS)');
xlim(p.SpecFreqRangeMHz);
xline(1555, 'k:', 'LineWidth', 1);
xline(1580, 'k:', 'LineWidth', 1);
grid on;
xlabel('Frequency (MHz)');
title(sprintf('RX spectrum 1500-1600 MHz (TxGain %.0f dB, RxGain %.0f dB)', ...
              bt.r.txGain, bt.r.params.RxGain));
legend('Direct PSD','Bias-T PSD','Direct tone','Bias-T tone','Location','best');
ts = datestr(now,'yyyymmdd_HHMMSS');
png = fullfile(p.DataDir, ['antenna_spectrum_' ts '.png']);
exportgraphics(fig, png, 'Resolution', 150);
close(fig);
fprintf('Spectrum figure saved: %s\n', png);
results = struct('case','SpecPlot','file',png, ...
                 'biasTFile',bt.src,'directFile',dr.src);
end

%% ---- 单音测量 ----
function m = measureToneAt(radioID, p, centerFreq, txGain)
m = measureToneN(radioID, p, centerFreq, txGain, 1);
end

%% ---- 单音测量（多次采集中值）----
function m = measureToneAvg(radioID, p, centerFreq, txGain, nAvg)
m = measureToneN(radioID, p, centerFreq, txGain, nAvg);
end

function m = measureToneN(radioID, p, centerFreq, txGain, nAvg)
tx = [];
rx = [];
try
    nT = round(p.FsTone*0.003);
    tone = p.ToneAmp*exp(1j*2*pi*p.ToneOffsetHz*(0:nT-1)'/p.FsTone);
    tx = sdrtx('Pluto','RadioID',radioID,'CenterFrequency',centerFreq, ...
               'BasebandSampleRate',p.FsTone,'Gain',txGain);
    tx.transmitRepeat(tone);
    rx = sdrrx('Pluto','RadioID',radioID,'CenterFrequency',centerFreq, ...
               'BasebandSampleRate',p.FsTone,'GainSource','Manual', ...
               'Gain',p.RxGain,'OutputDataType','double');
    n = round(p.FsTone*p.CaptureSecTone);
    ampArr = nan(nAvg,1);
    offArr = nan(nAvg,1);
    snrArr = nan(nAvg,1);
    rmsArr = nan(nAvg,1);
    clipMax = 0;
    for k = 1:nAvg
        d = capture(rx, n);
        [ampLin, offsetHz, snrDb, rmsDbF, clip] = analyzeTone(d, p);
        ampArr(k) = 20*log10(max(ampLin,eps));
        offArr(k) = offsetHz;
        snrArr(k) = snrDb;
        rmsArr(k) = rmsDbF;
        clipMax = max(clipMax, clip);
    end
    m = struct('ampLin',10^(median(ampArr)/20), ...
               'peakDbF',median(ampArr), 'offsetHz',median(offArr), ...
               'snrDb',median(snrArr), 'clip',clipMax, ...
               'rmsDbF',median(rmsArr), 'nAvg',nAvg);
catch e
    m = struct('ampLin',nan,'peakDbF',nan,'offsetHz',nan,'snrDb',nan, ...
               'clip',nan,'rmsDbF',nan,'nAvg',nAvg);
    warning('measureToneN(%d MHz, g=%.2f) failed: %s', centerFreq/1e6, txGain, e.message);
end
cleanupObj(tx); cleanupObj(rx);
end

%% ---- 单帧 FFT 分析 ----
function [ampLin, offsetHz, snrDb, rmsDbF, clip] = analyzeTone(x, p)
x = x(:);
nn = numel(x);
X = fft(x);
P = abs(X);
w = round(5e3*nn/p.FsTone);
k0 = round(p.ToneOffsetHz*nn/p.FsTone)+1;
lo = max(1,k0-w);
hi = min(nn,k0+w);
[pp,kp] = max(P(lo:hi));
kp = kp+lo-1;
offsetHz = (kp-1)/nn*p.FsTone;
ampLin = 2*pp/nn;
nlo = max(1,kp-round(10e3*nn/p.FsTone));
nhi = min(nn,kp+round(10e3*nn/p.FsTone));
mask = true(nn,1);
mask(nlo:nhi) = false;
noiseMed = median(P(mask));
snrDb = 10*log10(pp^2/max(noiseMed^2,eps));
rmsDbF = 20*log10(max(rms(x),eps));
clip = max(abs(x)) > 0.95;
end

%% ---- 噪声底 ----
function nz = measureNoise(radioID, p)
rx = [];
try
    rx = sdrrx('Pluto','RadioID',radioID,'CenterFrequency',1575.42e6, ...
               'BasebandSampleRate',p.FsTone,'GainSource','Manual', ...
               'Gain',p.RxGain,'OutputDataType','double');
    d = capture(rx, round(p.FsTone*0.25));
    nz.rmsDbF = 20*log10(max(rms(d),eps));
catch e
    nz.rmsDbF = nan;
    warning('measureNoise failed: %s', e.message);
end
cleanupObj(rx);
end

%% ---- 分段频谱拼接 ----
function spec = runSpec(radioID, p)
fs = p.FsSpec;
centers = p.SpecCentersMHz(:)';
segs = struct('freqMHz',{},'psdDb',{});
ok = false;
for attempt = 1:2
    if attempt == 2
        fs = 10e6;
        centers = 1500:10:1590;
        fprintf('  Spec fallback: Fs=10 MSPS, centers 1500:10:1590 MHz\n');
    end
    segs = struct('freqMHz',{},'psdDb',{});
    ok = true;
    for c = centers
        s = captureSpec(radioID, p, c*1e6, fs);
        if isempty(s)
            ok = false;
            break;
        end
        segs(end+1) = s;
    end
    if ok, break; end
end
if ~ok || isempty(segs)
    error('Spectrum capture failed at all settings.');
end
gridMHz = (1500:0.05:1600)';
psdGrid = nan(numel(gridMHz),1);
for i = 1:numel(gridMHz)
    fm = gridMHz(i);
    acc = [];
    for s = 1:numel(segs)
        m = abs(segs(s).freqMHz - fm) <= 0.025;
        if any(m), acc = [acc; segs(s).psdDb(m)]; end
    end
    if ~isempty(acc), psdGrid(i) = mean(acc); end
end
spec = struct('freqMHz',gridMHz,'psdDb',psdGrid,'fsUsed',fs);
end

function s = captureSpec(radioID, p, centerFreq, fs)
s = [];
rx = [];
try
    rx = sdrrx('Pluto','RadioID',radioID,'CenterFrequency',centerFreq, ...
               'BasebandSampleRate',fs,'GainSource','Manual', ...
               'Gain',p.RxGain,'OutputDataType','double');
    n = round(fs*p.SpecSec);
    d = capture(rx, n);
    x = d(:);
    nfft = 4096;
    hop = nfft/2;
    nw = floor((numel(x)-nfft)/hop)+1;
    win = hann(nfft,'periodic');
    acc = zeros(nfft,1);
    for j = 1:nw
        seg = x((j-1)*hop+1:(j-1)*hop+nfft);
        X = fft(seg.*win);
        acc = acc + abs(X).^2;
    end
    psd = acc/nw/(sum(win.^2)*fs);
    psd = fftshift(psd);
    freq = (-nfft/2:nfft/2-1)'/nfft*fs + centerFreq;
    s = struct('freqMHz',freq/1e6,'psdDb',10*log10(psd+eps));
catch e
    warning('captureSpec(%d MHz, fs=%.0f) failed: %s', centerFreq/1e6, fs, e.message);
end
cleanupObj(rx);
end

%% ---- 工具 ----
function r = loadLatestCal(dataDir)
r = loadLatest(dataDir, 'antenna_cal_*.mat');
if ~isempty(r), r = r.r; end
end

function out = loadLatest(dataDir, pattern)
out = [];
f = dir(fullfile(dataDir, pattern));
if isempty(f), return; end
[~, idx] = sort([f.datenum]);
fn = fullfile(dataDir, f(idx(end)).name);
tmp = load(fn, 'results');
out.r = tmp.results;
out.src = fn;
end

function cleanupObj(o)
if ~isempty(o) && isvalid(o)
    try, release(o); catch, end
    try, delete(o); catch, end
end
end
