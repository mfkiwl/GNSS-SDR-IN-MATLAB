function results = verifyGnssContinuousNav(varargin)
%VERIFYGNSSCONTINUOUSNAV 连续 GPS 子帧电文收发验证（真实环境模拟）
%
%   流程：
%     1. 生成 2 个连续子帧（TOW 递增，含奇偶校验），合并 600 位
%     2. TX transmitRepeat 持续发射（12 s 缓冲）
%     3. RX capture 12 s
%     4. acquisition 捕获 → 码相位/多普勒
%     5. 解调 1 ms 相关 → 比特边缘检测（能量法，无参考）→ 按最优偏移解调比特流
%     6. 子帧同步（前导码 + 奇偶校验验证）→ 解码 TLM/HOW/数据字 → 与发送端对比
%     7. 判定：捕获命中 && >=1 有效子帧 && 对比 0 错误
%
%   用法：
%     verifyGnssContinuousNav                            % 硬件（天线场景默认）
%     verifyGnssContinuousNav('Synthetic', true)         % 离线合成信号模拟
%     verifyGnssContinuousNav('TxGain', -89.75, 'TxAmplitude', 0.034, 'RxGain', 10)
%
%   参数 (Name-Value)：
%     'Synthetic'  - true 离线模拟（不加硬件），默认 false
%     'PRN', 'Fs', 'CenterFreq', 'TxGain', 'TxAmplitude', 'RxGain'
%     'CaptureSec' - 采集时长（默认 12，保证至少 1 个完整 6 s 子帧）
%     'NFrames'    - 发射子帧数（默认 1；TX 缓冲上限 2^24 采样，
%                    2.5 MSPS 下最多 1 个子帧），'TOW0' - 起始 TOW 计数

%% ---- 参数 ----
p = struct();
p.Synthetic   = false;
p.PRN         = 5;
p.Fs          = 2.5e6;
p.CenterFreq  = 1575.42e6;
p.TxGain      = -65;
p.TxAmplitude = 0.1;
p.RxGain      = 20;
p.CaptureSec  = 12;
p.NFrames     = 1;
p.TOW0        = 80000;      % 真实 GPS TOW 范围 0..100799（一周 6 秒计数）

for k = 1:2:numel(varargin)
    key = varargin{k};
    val = varargin{k+1};
    switch lower(key)
        case 'synthetic',   p.Synthetic = val;
        case 'prn',         p.PRN = val;
        case 'fs',          p.Fs = val;
        case 'centerfreq',  p.CenterFreq = val;
        case 'txgain',      p.TxGain = val;
        case 'txamplitude', p.TxAmplitude = val;
        case 'rxgain',      p.RxGain = val;
        case 'capturesec',  p.CaptureSec = val;
        case 'nframes',     p.NFrames = val;
        case 'tow0',        p.TOW0 = val;
        otherwise, error('未知参数: %s', key);
    end
end

results = struct();
results.params = p;
results.pass = false;
tx = []; rx = []; data = []; buf = [];

try
    %% ---- 1. 生成连续子帧电文 ----
    sfBits = [];
    metas = [];
    for k = 1:p.NFrames
        [b, m] = generateGpsSubframe(mod(k-1, 5) + 1, p.TOW0 + (k-1), ...
            'TlmMsg', de2bi(20 + k, 6, 'left-msb'));
        sfBits = [sfBits, b]; %#ok<AGROW>
        metas  = [metas, m]; %#ok<AGROW>
    end
    results.txBits = sfBits;
    results.txMetas = metas;
    fprintf('============================================\n');
    fprintf(' 连续 GPS 子帧电文收发验证（真实环境模拟）\n');
    fprintf('============================================\n');
    fprintf('电文   : %d 个子帧（%d 位 = %.1f s），TOW %d..%d\n', ...
        p.NFrames, numel(sfBits), numel(sfBits)/50, p.TOW0, p.TOW0+p.NFrames-1);

    %% ---- 2. 发射/合成 ----
    buf = generateGnssTxBuffer(p.PRN, p.Fs, ...
        'Amplitude', p.TxAmplitude, 'NavBits', sfBits);
    if numel(buf) > 2^24
        error('TX 缓冲 %d 采样超过 Pluto 上限 2^24：请减少 NFrames 或降低采样率', numel(buf));
    end
    if p.Synthetic
        % 离线：合成信号 + 高斯噪声（C/N0=45 dB-Hz 等效）
        sigma = p.TxAmplitude * sqrt(p.Fs / 10^4.5);
        rng(20260807);
        noise = (randn(numel(buf), 1) + 1j*randn(numel(buf), 1)) * sigma/sqrt(2);
        data = buf + noise;
        fprintf('[SYN] 合成信号 %d 采样（%.1f s），C/N0=45 dB-Hz 等效\n', ...
            numel(data), numel(data)/p.Fs);
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
        fprintf('[TX] 已发射 %d 子帧合成 GPS（缓冲 %.1f s，增益 %.1f dB）\n', ...
            p.NFrames, numel(buf)/p.Fs, p.TxGain);
        pause(0.5);

        fprintf('[RX] capture 采集 %.1f s ...\n', p.CaptureSec);
        % 注意：capture() 单帧上限 2^24 采样（约 6.7 s @2.5 MSPS），且分块调用
        % 帧间不连续（M1 结论）；此处用 step() 连续流（帧间首尾相接）
        frameSamples = round(p.Fs * 0.01);        % 10 ms 帧
        rx = sdrrx('Pluto', 'RadioID', radioID, ...
            'CenterFrequency', p.CenterFreq, 'BasebandSampleRate', p.Fs, ...
            'GainSource', 'Manual', 'Gain', p.RxGain, 'OutputDataType', 'double', ...
            'SamplesPerFrame', frameSamples);
        try
            rx.kernelBuffersCount = 32;
        catch
        end
        nFrames = round(p.Fs * p.CaptureSec / frameSamples);
        data = zeros(nFrames * frameSamples, 1);
        tCap = tic;
        for k = 1:nFrames
            data((k-1)*frameSamples + (1:frameSamples)) = step(rx);
        end
        fprintf('  连续流采集 %d 帧（%.1f s），耗时 %.1f s\n', ...
            nFrames, nFrames*frameSamples/p.Fs, toc(tCap));
        release(rx); delete(rx); rx = [];
        release(tx); delete(tx); tx = [];
        fprintf('  采集 %d 采样，RMS=%.5f 削波=%.2f%%\n', ...
            numel(data), rms(data), mean(abs(data) > 0.999)*100);
        clear buf;
    end

    %% ---- 3. 捕获 ----
    fprintf('[ACQ] 捕获 ...\n');
    acq = acquisition(data, p.Fs, 'Verbose', false, ...
        'IntegrationMs', 5, 'NonCoherentN', 10, 'DopplerStep', 100);
    r1 = acq.results([acq.results.PRN] == p.PRN);
    fprintf('  PRN %2d: metric=%.1f doppler=%+7.1f Hz codePhase=%5d 检测=%d\n', ...
        p.PRN, r1.metric, r1.dopplerHz, r1.codePhase, r1.detected);
    results.acq = acq;

    %% ---- 4. 解调 + 比特边缘检测 ----
    fprintf('[DEMOD] 解调 1 ms 相关 ...\n');
    o1 = demodulateNavBits(data, p.Fs, acq, p.PRN);
    edge = gnssBitEdgeDetect(o1.msValues);
    fprintf('  比特边缘检测: 最优偏移 %d ms（能量峰/次峰比 %.1f，边界翻转率 %.2f）\n', ...
        edge.bitOffsetMs, edge.peakToSecond, edge.flipRate(edge.bitOffsetMs+1));
    o2 = demodulateNavBits(data, p.Fs, acq, p.PRN, ...
        'BitOffsetMs', edge.bitOffsetMs);
    bits = o2.bits;
    fprintf('  解调比特数: %d（%.1f s x 50 bps）\n', numel(bits), numel(bits)/50);
    results.edge = edge;
    results.bits = bits;
    clear data o1 o2;

    %% ---- 5. 子帧同步 + 解码 + 对比 ----
    fprintf('[SYNC] 子帧同步（前导码 + 奇偶校验）...\n');
    ref = struct('bits', sfBits, 'metas', metas);
    dec = gnssSubframeDecode(bits, 'Reference', ref);
    results.dec = dec;
    fprintf('  有效子帧 %d 个（前导码+奇偶校验验证，含极性消除）\n', ...
        numel(dec.syncIndex));
    if ~isempty(dec.syncIndex)
        fprintf('  有效子帧起点（位索引）: %s\n', mat2str(dec.syncIndex));
        for k = 1:numel(dec.subframes)
            s = dec.subframes(k);
            fprintf('    子帧 %d: TOW=%d, 子帧号=%d, TLM=%s\n', ...
                k, s.tow, s.subframeId, mat2str(s.tlmMsg));
        end
        if isfield(dec, 'compare')
            for k = 1:numel(dec.compare)
                c = dec.compare(k);
                if c.matched
                    fprintf('    对比: TLM=%d TOW=%d SFID=%d 数据字=%d 比特错误=%d\n', ...
                        c.tlmMsgOK, c.towOK, c.sfidOK, c.dataOK, c.bitErrors);
                end
            end
        end
    end

    %% ---- 6. 判定 ----
    nOK = 0;
    if isfield(dec, 'compare') && ~isempty(dec.compare)
        nOK = sum([dec.compare.matched] & ([dec.compare.tlmMsgOK] & ...
              [dec.compare.towOK] & [dec.compare.sfidOK] & ...
              [dec.compare.dataOK] & ([dec.compare.bitErrors] == 0)));
    end
    results.nGoodSubframes = nOK;
    results.pass = r1.detected && nOK >= 1;
    fprintf('\n============================================\n');
    fprintf(' 连续电文验证结论: %s（有效子帧 %d/%d 全对）\n', ...
        passStr(results.pass), nOK, numel(dec.syncIndex));
    fprintf('============================================\n');

catch err
    fprintf('\n[连续电文验证中断]: %s\n', err.message);
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
if isfield(results, 'edge')
    try
        outDir = fullfile(fileparts(mfilename('fullpath')), 'data');
        if ~exist(outDir, 'dir'), mkdir(outDir); end
        ts = datestr(now, 'yyyymmdd_HHMMSS');
        pngFile = fullfile(outDir, ['gnss_continuous_' ts '.png']);
        plotContinuous(results, p, pngFile);
        fprintf('图形已保存: %s\n', pngFile);
    catch e
        fprintf('绘图跳过: %s\n', e.message);
    end
end

%% ---- 保存结果 ----
outDir = fullfile(fileparts(mfilename('fullpath')), 'data');
if ~exist(outDir, 'dir'), mkdir(outDir); end
ts = datestr(now, 'yyyymmdd_HHMMSS');
matFile = fullfile(outDir, ['gnss_continuous_' ts '.mat']);
save(matFile, 'results', 'p');
fprintf('结果已保存: %s\n', matFile);
end

%% ---- 绘图 ----
function plotContinuous(results, p, pngFile)
fig = figure('Visible', 'off', 'Position', [100 100 1100 760]);

% (1) 捕获指标
subplot(2,2,1);
mets = [results.acq.results.metric];
bar(1:32, mets, 'FaceColor', [0.6 0.6 0.6]);
hold on;
bar(p.PRN, mets(p.PRN), 'FaceColor', [0.85 0.33 0.10]);
hold off;
xlabel('PRN'); ylabel('metric');
title(sprintf('Acquisition (PRN %d = %.1f)', p.PRN, mets(p.PRN)));
grid on;

% (2) 比特边缘检测
subplot(2,2,2);
stem(0:19, results.edge.energy, 'MarkerSize', 4);
hold on;
stem(results.edge.bitOffsetMs, results.edge.energy(results.edge.bitOffsetMs+1), ...
    'r', 'LineWidth', 2);
hold off;
xlabel('bit sync offset (ms)'); ylabel('mean |20ms corr|');
title(sprintf('Bit edge detection (best = %d ms)', results.edge.bitOffsetMs));
grid on;

% (3) 子帧同步
subplot(2,2,3);
pre = [1 0 0 0 1 0 1 1];
cands = strfind(results.bits, pre);
valid = results.dec.syncIndex;
stem(cands, ones(size(cands)), 'b', 'MarkerSize', 6);
hold on;
stem(valid, ones(size(valid)), 'r', 'LineWidth', 2);
hold off;
ylim([0 1.5]);
xlabel('bit index'); ylabel('marker');
title(sprintf('Subframe sync (preamble candidates, red = parity OK)'));
grid on;

% (4) 对比结果
subplot(2,2,4);
if isfield(results.dec, 'compare') && ~isempty(results.dec.compare)
    c = results.dec.compare;
    names = {'TLM','TOW','SFID','DATA','BITS'};
    vals = zeros(numel(c), 5);
    for k = 1:numel(c)
        vals(k, :) = [c(k).tlmMsgOK, c(k).towOK, c(k).sfidOK, c(k).dataOK, c(k).bitErrors == 0];
    end
    imagesc(vals);
    colormap(gca, [0.85 0.33 0.10; 0.30 0.65 0.30]);
    set(gca, 'XTick', 1:5, 'XTickLabel', names, 'YTick', 1:numel(c));
    colorbar('Ticks', [0.25 0.75], 'TickLabels', {'FAIL','OK'});
    title('TX vs RX compare per subframe');
else
    text(0.5, 0.5, 'no valid subframe', 'HorizontalAlignment', 'center', 'Units', 'normalized');
    axis off;
end

exportgraphics(fig, pngFile, 'Resolution', 110);
close(fig);
end

%% ---- 工具函数 ----
function s = passStr(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end
