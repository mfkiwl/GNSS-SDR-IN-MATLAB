function results = verifyPlutoStream(varargin)
%VERIFYPLUTOSTREAM M1 验证：PlutoSDR 连续采集链路完整性
%   用法：
%     verifyPlutoStream                              % 默认参数
%     verifyPlutoStream('Fs',4e6,'DurationSec',10)   % 自定义
%     verifyPlutoStream('UseTone',false)             % 无回环线时关闭测试音
%
%   验证内容（详见 README_M1.md）：
%     A. GPS L1 前端健康：RMS / 削波比例 / DC 偏移 / 噪声底
%     B. 流模式逐帧采集：帧数、样本数、帧间隔、处理耗时、吞吐率
%     C. 回环测试音连续性：帧间相位跳变检测（丢帧 -> 相位突变）
%     D. 突发模式整块捕获：样本数、相位线性度
%
%   输出：
%     results                 - 指标与判定结构体
%     data\verify_<时间戳>.mat - 完整结果
%     data\verify_<时间戳>.png - 图形化结果

%% ---- 参数 ----
p = struct( ...
    'fs',          4e6, ...         % 目标采样率 (Hz)
    'centerFreq',  1575.42e6, ...   % GPS L1 中心频率
    'durationSec', 15, ...          % 流模式测试时长 (s)
    'frameMs',     10, ...          % 帧长 (ms)
    'useTone',     true, ...        % 是否发射回环测试音
    'toneFreq',    97.333e3, ...    % 测试音偏移 (Hz)；需满足 缓冲3ms×f = 整数周期
    'toneAmp',     0.15, ...        % 测试音幅度
    'rxGain',      20, ...          % 回环测试时 RX 手动增益 (dB)
    'burstSec',    2, ...           % 突发模式测试时长 (s)
    'plot',        true);           % 是否输出图形

for k = 1:2:numel(varargin)
    key = lower(varargin{k});
    val = varargin{k+1};
    switch key
        case 'fs',           p.fs = val;
        case 'centerfreq',   p.centerFreq = val;
        case 'durationsec',  p.durationSec = val;
        case 'framems',      p.frameMs = val;
        case 'usetone',      p.useTone = val;
        case 'tonefreq',     p.toneFreq = val;
        case 'toneamp',      p.toneAmp = val;
        case 'rxgain',       p.rxGain = val;
        case 'burstsec',     p.burstSec = val;
        case 'plot',         p.plot = val;
        otherwise, error('未知参数: %s', key);
    end
end

results = struct();
results.params = p;
results.checks = struct();
results.pass = false;

tx = [];
rx = [];

try
    %% ---- 设备检测 ----
    r = findPlutoRadio();
    if isempty(r)
        error(['未找到 PlutoSDR：请检查 USB 连接后重试。' ...
               '正常时系统应出现 "PlutoSDR Serial Console (COMx)" 和 ' ...
               '"PlutoSDR USB Ethernet/RNDIS Gadget"。']);
    end
    radioID = r(1).RadioID;
    results.device = r(1);

    fprintf('============================================\n');
    fprintf(' M1 验证：PlutoSDR 连续采集链路\n');
    fprintf('============================================\n');
    fprintf('设备    : %s (序列号 %s)\n', radioID, r(1).SerialNum);
    fprintf('参数    : fs=%.3f MSPS, 中心=%.3f MHz\n', p.fs/1e6, p.centerFreq/1e6);
    fprintf('流模式  : %d s（帧 %d ms）\n', p.durationSec, p.frameMs);
    fprintf('突发模式: %d s\n', p.burstSec);
    fprintf('测试音  : %s（+%.3f kHz）\n', string(p.useTone), p.toneFreq/1e3);

    %% ---- A. GPS L1 前端健康检查（AGC，无测试音）----
    fprintf('\n[A] GPS L1 前端健康检查 ...\n');
    rxHealth = sdrrx('Pluto', 'RadioID', radioID, ...
        'CenterFrequency', p.centerFreq, 'BasebandSampleRate', p.fs, ...
        'GainSource', 'AGC Slow Attack', 'OutputDataType', 'double');
    hFrame = round(p.fs*p.frameMs/1000);
    rmsSum = 0; clipSum = 0; dcSum = 0; nH = 0;
    for k = 1:10
        d = capture(rxHealth, hFrame);
        a = abs(d);
        rmsSum = rmsSum + rms(d);
        clipSum = clipSum + sum(a > 0.999);
        dcSum = dcSum + abs(mean(d));
        nH = nH + 1;
    end
    release(rxHealth); delete(rxHealth);
    A = struct();
    A.rmsMean   = rmsSum/nH;
    A.clipRatio = clipSum/(nH*hFrame);
    A.dcOffset  = dcSum/nH;
    % 阈值较宽松：AGC 无信号源时可能推高增益导致轻微削波，属正常；
    % 该检查只判断"链路未死/未严重饱和"。
    A.rfHealthOK = A.rmsMean > 1e-4 && A.rmsMean < 0.7 && ...
                   A.clipRatio < 0.05 && A.dcOffset < 0.3;
    fprintf('  RMS=%.4f  削波=%.4f%%  DC=%.4f  -> %s\n', ...
        A.rmsMean, A.clipRatio*100, A.dcOffset, passStr(A.rfHealthOK));
    results.checks.A = A;

    %% ---- B+C. 回环测试音 + step() 连续流采集 ----
    fprintf('\n[B/C] step() 连续流采集（%d 帧 × %d 采样）...\n', ...
        round(p.durationSec*1000/p.frameMs), round(p.fs*p.frameMs/1000));

    if p.useTone
        try
            tx = sdrtx('Pluto', 'RadioID', radioID, ...
                'CenterFrequency', p.centerFreq, 'BasebandSampleRate', p.fs, ...
                'Gain', 0);
            % 相位连续测试音：缓冲 3 ms，且 f×3ms 为整数周期（97.333k×3ms=292）
            toneLen = round(p.fs*0.003);
            tone = p.toneAmp*exp(1j*2*pi*p.toneFreq*(0:toneLen-1)'/p.fs);
            tx.transmitRepeat(tone);
            fprintf('  已发射相位连续回环测试音（+%.3f kHz, 幅度 %.2f）\n', ...
                p.toneFreq/1e3, p.toneAmp);
        catch e
            warning('测试音发射失败，降级为无音模式: %s', e.message);
            p.useTone = false;
        end
    end

    rx = sdrrx('Pluto', 'RadioID', radioID, ...
        'CenterFrequency', p.centerFreq, 'BasebandSampleRate', p.fs, ...
        'GainSource', 'Manual', 'Gain', p.rxGain, 'OutputDataType', 'double', ...
        'SamplesPerFrame', round(p.fs*p.frameMs/1000));
    try
        rx.kernelBuffersCount = 32;   % 加大内核缓冲，吸收偶发调度延迟
    catch
    end
    frameSamples = round(p.fs*p.frameMs/1000);
    nFrames = round(p.durationSec*1000/p.frameMs);

    tWall = zeros(nFrames,1);
    procT = zeros(nFrames,1);
    phase = zeros(nFrames,1);
    toneRef = exp(-1j*2*pi*p.toneFreq*(0:frameSamples-1)'/p.fs);

    tStart = tic;
    for k = 1:nFrames
        t0 = tic;
        data = step(rx);   % 连续流接口；capture() 循环每次重同步，帧间不连续，不可用
        procT(k) = toc(t0);
        tWall(k) = toc(tStart);
        if numel(data) ~= frameSamples
            error('帧 %d 样本数异常: %d（预期 %d）', k, numel(data), frameSamples);
        end
        if p.useTone
            phase(k) = angle(sum(data .* toneRef)/frameSamples);
        end
    end
    totalTime = toc(tStart);

    B = struct();
    B.nFrames = nFrames;
    B.samplesPerFrame = frameSamples;
    B.totalSamples = nFrames*frameSamples;
    B.expectedSamples = round(p.fs*p.durationSec);
    B.sampleCountOK = B.totalSamples == B.expectedSamples;
    B.frameInterval = diff(tWall);
    B.frameIntervalMean = mean(B.frameInterval);
    B.frameIntervalMax = max(B.frameInterval);
    B.frameIntervalP95 = prctile(B.frameInterval, 95);
    if numel(B.frameInterval) > 3
        B.steadyMean = mean(B.frameInterval(3:end));   % 跳过前 2 帧初始化延迟
    else
        B.steadyMean = B.frameIntervalMean;
    end
    B.procTimeMean = mean(procT);
    B.procTimeMax = max(procT(min(3,numel(procT)):end));
    B.frameIntervalOK = B.steadyMean <= 1.2*(p.frameMs/1000) && ...
                        B.frameIntervalP95 <= 1.5*(p.frameMs/1000);
    B.procTimeOK = B.procTimeMax < 0.5;   % 最大单帧处理 < 500 ms（缓冲可吸收）
    B.throughput = B.totalSamples/totalTime;
    B.throughputOK = B.throughput >= 0.9*p.fs;
    fprintf('  帧间隔 稳态mean=%.2f ms  p95=%.2f ms  max=%.2f ms -> %s\n', ...
        B.steadyMean*1000, B.frameIntervalP95*1000, B.frameIntervalMax*1000, ...
        passStr(B.frameIntervalOK));
    fprintf('  处理耗时 mean=%.3f ms max=%.3f ms -> %s\n', ...
        B.procTimeMean*1000, B.procTimeMax*1000, passStr(B.procTimeOK));
    fprintf('  有效吞吐 %.3f MSPS（目标 %.3f）-> %s\n', ...
        B.throughput/1e6, p.fs/1e6, passStr(B.throughputOK));
    results.checks.B = B;

    %% ---- C. 测试音检测 + 帧间相位连续性 ----
    C = struct();
    if p.useTone
        d = step(rx);
        P = abs(fft(d)).^2;
        freqs = (0:frameSamples/2)'/frameSamples*p.fs;
        P1 = P(1:frameSamples/2+1);
        [pkP, pkIdx] = max(P1);
        C.toneDetectedFreq = freqs(pkIdx);
        C.toneFreqErr = abs(C.toneDetectedFreq - p.toneFreq);
        mask = abs(freqs - p.toneFreq) > 1e3;
        C.toneSNRdB = 10*log10(pkP/max(median(P1(mask)), eps));
        C.toneOK = C.toneFreqErr < 1e3 && C.toneSNRdB > 10;

        % 帧间相位步进
        dphase = wrapToPi(diff(phase));
        expStep = wrapToPi(2*pi*p.toneFreq*(p.frameMs/1000));
        dev = abs(wrapToPi(dphase - expStep));
        C.phaseJumps = sum(dev > 0.5);
        C.phaseDevMax = max(dev);
        C.phaseContinuityOK = C.phaseJumps == 0;

        fprintf('  测试音频率 %.3f kHz（误差 %.1f Hz）, SNR %.1f dB -> %s\n', ...
            C.toneDetectedFreq/1e3, C.toneFreqErr, C.toneSNRdB, passStr(C.toneOK));
        fprintf('  帧间相位跳变 %d 次, 最大偏差 %.3f rad -> %s\n', ...
            C.phaseJumps, C.phaseDevMax, passStr(C.phaseContinuityOK));
    else
        C.toneOK = true;
        C.phaseContinuityOK = true;
        C.phaseJumps = nan;
        fprintf('  （无测试音，跳过连续性检测）\n');
    end
    results.checks.C = C;
    results.phase = phase;
    results.frameInterval = diff(tWall);
    results.procTime = procT;

    % 释放流对象，让出射频给 D 对照使用
    release(rx); delete(rx); rx = [];

    %% ---- D. 大块 capture 对照（信息项，不参与 PASS 判定）----
    fprintf('\n[D] 大块 capture 对照（%d s，一次性捕获）...\n', p.burstSec);
    D = doCaptureCheck(radioID, p);
    if D.done
        fprintf('  样本 %d/%d, 耗时 %.2f s（注意：capture 为一次性捕获，跨调用不连续）\n', ...
            D.samples, D.expected, D.captureTime);
    else
        fprintf('  跳过: %s\n', D.msg);
    end
    results.checks.D = D;

    %% ---- 汇总 ----
    allOK = [results.checks.A.rfHealthOK, ...
             results.checks.B.sampleCountOK, ...
             results.checks.B.frameIntervalOK, ...
             results.checks.B.procTimeOK, ...
             results.checks.B.throughputOK, ...
             results.checks.C.toneOK, ...
             results.checks.C.phaseContinuityOK];
    results.pass = all(allOK);
    fprintf('\n============================================\n');
    fprintf(' M1 验证结论: %s\n', passStr(results.pass));
    fprintf('============================================\n');

catch err
    fprintf('\n[M1 验证中断]: %s\n', err.message);
    results.error = err.message;
    results.pass = false;
end

% 无论如何都清理设备
cleanupDevices(rx, tx);

%% ---- 保存结果 ----
outDir = fullfile(fileparts(mfilename('fullpath')), 'data');
if ~exist(outDir, 'dir'), mkdir(outDir); end
ts = datestr(now, 'yyyymmdd_HHMMSS');
matFile = fullfile(outDir, ['verify_' ts '.mat']);
save(matFile, 'results');
fprintf('结果已保存: %s\n', matFile);

if p.plot && isfield(results, 'checks')
    try
        pngFile = fullfile(outDir, ['verify_' ts '.png']);
        plotResults(results, pngFile);
        fprintf('图形已保存: %s\n', pngFile);
    catch e
        fprintf('绘图跳过: %s\n', e.message);
    end
end
end

%% ---- 大块 capture 对照 ----
function D = doCaptureCheck(radioID, p)
D = struct('done', false, 'ok', false, 'msg', '');
try
    rx2 = sdrrx('Pluto', 'RadioID', radioID, ...
        'CenterFrequency', p.centerFreq, 'BasebandSampleRate', p.fs, ...
        'GainSource', 'Manual', 'Gain', p.rxGain, 'OutputDataType', 'double');
    nBurst = round(p.fs*p.burstSec);
    tb = tic;
    [bdata, ~] = capture(rx2, nBurst);
    D.captureTime = toc(tb);
    D.samples = numel(bdata);
    D.expected = nBurst;
    D.countOK = D.samples == D.expected;
    D.phaseOK = true;
    if p.useTone && D.countOK
        tvec = (0:D.samples-1)'/p.fs;
        ph = unwrap(angle(bdata .* exp(-1j*2*pi*p.toneFreq*tvec)));
        fitc = polyfit(tvec, ph, 1);
        resid = ph - polyval(fitc, tvec);
        D.phaseResidStd = std(resid);
        D.phaseOK = D.phaseResidStd < 0.2;
    end
    D.ok = D.countOK && D.phaseOK;
    D.done = true;
    release(rx2); delete(rx2);
catch e
    D.msg = e.message;
    D.ok = false;
end
end

%% ---- 绘图 ----
function plotResults(results, pngFile)
ch = results.checks;
fig = figure('Visible', 'off', 'Position', [100 100 1000 720]);

if isfield(results, 'frameInterval')
    fi = results.frameInterval*1000;
    subplot(2,2,1);
    plot(fi, '.-');
    hold on;
    yline(mean(fi), '--r');
    grid on;
    title('帧间隔 (ms)');
    xlabel('帧序号'); ylabel('ms');
    subplot(2,2,2);
    histogram(fi, 30);
    grid on;
    title('帧间隔直方图');
    xlabel('ms');
else
    subplot(2,2,1);
    text(0.5, 0.5, '无流模式数据', 'HorizontalAlignment', 'center', 'Units', 'normalized');
    axis off;
    subplot(2,2,2);
    axis off;
end

subplot(2,2,3);
if isfield(results, 'phase') && numel(results.phase) > 1
    plot(wrapToPi(diff(results.phase)), '.-');
    grid on;
    title('帧间相位步进 (rad)');
    xlabel('帧序号');
else
    text(0.5, 0.5, '无测试音', 'HorizontalAlignment', 'center', 'Units', 'normalized');
    axis off;
end

subplot(2,2,4);
if isfield(ch, 'A') && isfield(ch, 'B') && isfield(ch, 'C')
    txt = sprintf(['M1 验证: %s\n' ...
        'RMS=%.4f  削波=%.2f%%  DC=%.4f\n' ...
        '帧间隔max=%.2fms  处理max=%.3fms\n' ...
        '吞吐=%.3fMSPS  相位跳变=%d'], ...
        passStr(results.pass), ...
        ch.A.rmsMean, ch.A.clipRatio*100, ch.A.dcOffset, ...
        ch.B.frameIntervalMax*1000, ch.B.procTimeMax*1000, ...
        ch.B.throughput/1e6, ch.C.phaseJumps);
else
    txt = sprintf('M1 验证: %s\n（设备未连接或验证中断）', passStr(results.pass));
end
text(0.05, 0.5, txt, 'Units', 'normalized', 'FontSize', 11, 'VerticalAlignment', 'middle');
axis off;
title('汇总');

exportgraphics(fig, pngFile, 'Resolution', 110);
close(fig);
end

%% ---- 工具函数 ----
function s = passStr(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end

function cleanupDevices(rx, tx)
for obj = {rx, tx}
    o = obj{1};
    if ~isempty(o) && isvalid(o)
        try, release(o); catch, end
        try, delete(o); catch, end
    end
end
end
