function runAcquisitionTests()
%RUNACQUISITIONTESTS M2 捕获模块离线测试（合成信号验证）
%
%   测试项:
%     T1 强信号捕获（PRN5，码相位 876，多普勒 +2300 Hz，CN0=45）
%     T2 弱信号捕获（PRN12，码相位 1987，多普勒 -4200 Hz，CN0=35，
%         5 ms 相干 x 10 块，DopplerStep=100）
%     T3 纯噪声虚警检查（32 PRN 全扫描，默认门限）
%     T4 多星同时捕获（PRN3 + PRN17，不同延迟/多普勒）
%     T5 码相位回绕（延迟接近码周期末尾）
%     T6 相干积分路径（IntegrationMs=5，DopplerStep=100）
%
%   全部 PASS 时打印汇总；任一 FAIL 则抛错（matlab -batch 返回非零）。

fs    = 2.5e6;
msLen = round(fs * 1e-3);

testNames = {'T1 强信号捕获', 'T2 弱信号捕获', 'T3 纯噪声虚警', ...
             'T4 多星同时捕获', 'T5 码相位回绕', 'T6 相干积分路径'};
passFlags = false(1, numel(testNames));
details   = cell(1, numel(testNames));

tTotal = tic;

%% T1: 强信号捕获（默认参数）
[sig, truth] = generateSyntheticGpsSignal('PRN', 5, 'Fs', fs, ...
    'DurationMs', 30, 'CodePhase', 876, 'DopplerHz', 2300, 'CN0dBHz', 45);
acq = acquisition(sig, fs, 'Verbose', false);
r1 = acq.results([acq.results.PRN] == 5);
passFlags(1) = r1.detected && abs(r1.dopplerHz - 2300) <= 250 ...
    && abs(r1.codePhase - 1 - 876) <= 2;
details{1} = sprintf('metric=%.1f doppler=%+d Hz (真值 +2300) codePhase=%d (真值 877 1-based)', ...
                     r1.metric, r1.dopplerHz, r1.codePhase);

%% T2: 弱信号捕获（5 ms 相干 x 10 块，弱信号须靠相干积分提升指标）
[sig, truth] = generateSyntheticGpsSignal('PRN', 12, 'Fs', fs, ...
    'DurationMs', 60, 'CodePhase', 1987, 'DopplerHz', -4200, 'CN0dBHz', 35);
acq = acquisition(sig, fs, 'Verbose', false, ...
    'IntegrationMs', 5, 'NonCoherentN', 10, 'DopplerStep', 100);
r2 = acq.results([acq.results.PRN] == 12);
passFlags(2) = r2.detected && abs(r2.dopplerHz - (-4200)) <= 50 ...
    && abs(r2.codePhase - 1 - 1987) <= 2;
details{2} = sprintf('metric=%.1f doppler=%+d Hz (真值 -4200) codePhase=%d (真值 1988 1-based)', ...
                     r2.metric, r2.dopplerHz, r2.codePhase);

%% T3: 纯噪声虚警检查（32 PRN x 41 多普勒 x 10 ms，默认门限 6）
sigma = sqrt(fs / 10^(45/10));
rng(7);
noise = (randn(50*msLen, 1) + 1j*randn(50*msLen, 1)) * sigma/sqrt(2);
acq = acquisition(noise, fs, 'Verbose', false);
allMetric = max([acq.results.metric]);
passFlags(3) = isempty(acq.detectedPRN);
details{3} = sprintf('无虚警，噪声最大 metric=%.2f（门限 %d）', ...
                     allMetric, acq.settings.Threshold);

%% T4: 多星同时捕获（两路无噪声合成后叠加，等效每颗 CN0~42 dB-Hz）
s1 = generateSyntheticGpsSignal('PRN', 3, 'Fs', fs, 'DurationMs', 40, ...
    'CodePhase', 321, 'DopplerHz', 1500, 'CN0dBHz', Inf);
s2 = generateSyntheticGpsSignal('PRN', 17, 'Fs', fs, 'DurationMs', 40, ...
    'CodePhase', 1555, 'DopplerHz', -2800, 'CN0dBHz', Inf);
rng(11);
sigma = sqrt(fs / 10^(45/10));
sig = s1 + s2 + (randn(size(s1)) + 1j*randn(size(s1))) * sigma/sqrt(2);
acq = acquisition(sig, fs, 'Verbose', false);
r3 = acq.results([acq.results.PRN] == 3);
r17 = acq.results([acq.results.PRN] == 17);
ok3  = r3.detected  && abs(r3.dopplerHz - 1500)  <= 250 && abs(r3.codePhase - 1 - 321)  <= 2;
ok17 = r17.detected && abs(r17.dopplerHz - (-2800)) <= 250 && abs(r17.codePhase - 1 - 1555) <= 2;
passFlags(4) = ok3 && ok17;
details{4} = sprintf('PRN3 metric=%.1f phase=%d doppler=%+d; PRN17 metric=%.1f phase=%d doppler=%+d', ...
                     r3.metric, r3.codePhase, r3.dopplerHz, ...
                     r17.metric, r17.codePhase, r17.dopplerHz);

%% T5: 码相位回绕（延迟接近码周期末尾）
phaseNearEnd = msLen - 5;
[sig, truth] = generateSyntheticGpsSignal('PRN', 9, 'Fs', fs, ...
    'DurationMs', 30, 'CodePhase', phaseNearEnd, 'DopplerHz', 1200, 'CN0dBHz', 40);
acq = acquisition(sig, fs, 'Verbose', false);
r9 = acq.results([acq.results.PRN] == 9);
passFlags(5) = r9.detected && abs(r9.dopplerHz - 1200) <= 250 ...
    && abs(r9.codePhase - 1 - phaseNearEnd) <= 2;
details{5} = sprintf('metric=%.1f codePhase=%d (真值 %d, 1-based)', ...
                     r9.metric, r9.codePhase, phaseNearEnd + 1);

%% T6: 相干积分路径（5 ms 相干 x 4 块，DopplerStep=100）
[sig, truth] = generateSyntheticGpsSignal('PRN', 7, 'Fs', fs, ...
    'DurationMs', 40, 'CodePhase', 543, 'DopplerHz', 1800, 'CN0dBHz', 35);
acq = acquisition(sig, fs, 'Verbose', false, ...
    'IntegrationMs', 5, 'NonCoherentN', 4, 'DopplerStep', 100);
r7 = acq.results([acq.results.PRN] == 7);
passFlags(6) = r7.detected && abs(r7.dopplerHz - 1800) <= 50 ...
    && abs(r7.codePhase - 1 - 543) <= 2;
details{6} = sprintf('metric=%.1f doppler=%+d Hz codePhase=%d', ...
                     r7.metric, r7.dopplerHz, r7.codePhase);

%% ---- 汇总 ----
fprintf('\n===== M2 捕获模块离线测试 =====\n');
nPass = 0; nFail = 0;
for k = 1:numel(testNames)
    if passFlags(k)
        nPass = nPass + 1;
        fprintf('PASS  %-14s %s\n', testNames{k}, details{k});
    else
        nFail = nFail + 1;
        fprintf('FAIL  %-14s %s\n', testNames{k}, details{k});
    end
end
fprintf('结果: %d/%d PASS，总用时 %.1f s\n', nPass, nPass+nFail, toc(tTotal));

if nFail > 0
    error('M2 离线测试失败: %d 项未通过', nFail);
end
end
