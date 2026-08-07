function acq = acquisition(sig, fs, varargin)
%ACQUISITION GPS L1 C/A 信号捕获（FFT 并行码相位搜索）
%
%   acq = acquisition(sig, fs) 对复基带 IQ 信号执行 32 颗 PRN 的
%   二维搜索（码相位 x 多普勒），返回每颗卫星的捕获结果。
%
%   输入:
%     sig   - 复基带 IQ（double 列向量），零中频或低中频均可
%     fs    - 采样率 (Hz)
%
%   可选参数 (Name-Value):
%     'PRNList'       - 待搜索 PRN 列表，默认 1:32
%     'DopplerRange'  - 多普勒搜索半带宽 (Hz)，默认 10000（即 +-10 kHz）
%     'DopplerStep'   - 多普勒搜索步进 (Hz)，默认 500
%     'IntegrationMs' - 相干积分时长 (ms)，默认 1
%     'NonCoherentN'  - 非相干累加的积分块数，默认 10
%     'Threshold'     - 检测门限（峰值/噪声均值），默认 6
%     'IF'            - 中频 (Hz)，Pluto 零中频为 0，默认 0
%     'Verbose'       - 是否打印逐星进度，默认 true
%
%   输出:
%     acq.settings      - 实际使用的参数
%     acq.results       - 结构数组（每颗 PRN 一项）:
%         .PRN          - PRN 号
%         .codePhase    - 码相位（采样点，1-based，码周期内）
%         .dopplerHz    - 多普勒频移 (Hz)
%         .metric       - 检测指标（峰值/噪声均值）
%         .detected     - 是否超过门限
%     acq.detectedPRN   - 检测到卫星的 PRN 列表
%
%   参考: SoftGNSS acquisition.m（FFT 并行码相位搜索思想）

%% ---- 默认参数 ----
p = struct();
p.PRNList       = 1:32;
p.DopplerRange  = 10000;
p.DopplerStep   = 500;
p.IntegrationMs = 1;
p.NonCoherentN  = 10;
p.Threshold     = 6;
p.IF            = 0;
p.Verbose       = true;

% ---- 解析可选参数 ----
for k = 1:2:numel(varargin)
    key = varargin{k};
    val = varargin{k+1};
    switch lower(key)
        case 'prnlist',       p.PRNList = val;
        case 'dopplerrange',  p.DopplerRange = val;
        case 'dopplerstep',   p.DopplerStep = val;
        case 'integrationms', p.IntegrationMs = val;
        case 'noncoherentn',  p.NonCoherentN = val;
        case 'threshold',     p.Threshold = val;
        case 'if',            p.IF = val;
        case 'verbose',       p.Verbose = val;
        otherwise, error('未知参数: %s', key);
    end
end

%% ---- 输入检查 ----
sig = sig(:);
if ~isfloat(sig)
    error('sig 必须为浮点类型（complex double）');
end
if ~isscalar(fs) || fs <= 0
    error('fs 必须为正标量');
end

msLen  = round(fs * 1e-3);             % 1 ms 采样点数
blkLen = msLen * p.IntegrationMs;      % 单个相干积分块长度（采样点）
need   = blkLen * p.NonCoherentN;
if numel(sig) < need
    error('信号长度不足: 需要至少 %d 采样点（%.1f ms），实际 %d', ...
          need, need/fs*1000, numel(sig));
end

%% ---- C/A 码参数（与 gnssSettings 保持一致，缺省时用常量） ----
try
    st            = gnssSettings();
    codeFreqBasis = st.codeFreqBasis;
    codeLength    = st.codeLength;
catch
    codeFreqBasis = 1.023e6;
    codeLength    = 1023;
end

dopplers = -p.DopplerRange : p.DopplerStep : p.DopplerRange;
nDop     = numel(dopplers);
tIdx     = (0 : need-1).';             % 全局采样索引，保证载波相位跨块连续

%% ---- 逐 PRN 二维搜索 ----
results = struct('PRN', {}, 'codePhase', {}, ...
                 'dopplerHz', {}, 'metric', {}, 'detected', {});
tStart = tic;

for prn = p.PRNList(:)'
    prn = prn(1);

    % 生成该 PRN 的 C/A 码并重采样到 fs（1 个码周期 = 1 ms）
    ca   = gnssCACode(prn, 'GPS');
    bip  = 2*double(ca) - 1;                             % 0/1 -> +-1 (double)
    nms  = (0:msLen-1).';
    chip = mod(floor(nms * codeFreqBasis / fs), codeLength) + 1;
    code1    = bip(chip);                                % 1 ms 码序列
    codeRep  = repmat(code1, p.IntegrationMs, 1);        % 相干积分码副本
    % 圆周相关（FFT 长度 = 块长）：码相位搜索要求码周期内回绕对齐，
    % 不能用零填充线性相关（大码相位会错位）
    codeF    = conj(fft(codeRep));                       % 频域码副本

    bestMetric = -inf;
    bestDop    = NaN;
    bestPhase  = NaN;

    for iDop = 1:nDop
        fd   = dopplers(iDop);
        fcar = p.IF + fd;
        acc  = zeros(blkLen, 1);

        for b = 1:p.NonCoherentN
            idx = (b-1)*blkLen + (1:blkLen);
            x   = sig(idx) .* exp(-1j*2*pi*fcar*tIdx(idx)/fs);
            corr = ifft(fft(x) .* codeF);
            acc  = acc + abs(corr).^2;
        end

        [peak, peakIdx] = max(acc);
        excl = true(blkLen, 1);
        lo = max(1, peakIdx-2);
        hi = min(blkLen, peakIdx+2);
        excl(lo:hi) = false;
        noiseMean = mean(acc(excl));
        metric    = peak / noiseMean;

        if metric > bestMetric
            bestMetric = metric;
            bestDop    = fd;
            bestPhase  = peakIdx;
        end
    end

    isDetected = bestMetric >= p.Threshold;
    results(end+1) = struct('PRN', prn, 'codePhase', bestPhase, ... %#ok<AGROW>
        'dopplerHz', bestDop, 'metric', bestMetric, 'detected', isDetected);

    if p.Verbose
        flagStr = '';
        if isDetected, flagStr = '  <-- DETECTED'; end
        fprintf('PRN %2d: doppler=%+7.1f Hz, codePhase=%4d, metric=%7.1f%s\n', ...
            prn, bestDop, bestPhase, bestMetric, flagStr);
    end
end

%% ---- 汇总输出 ----
acq.settings = p;
acq.results  = results;
detMask = [results.detected];
if any(detMask)
    acq.detectedPRN = [results(detMask).PRN];
else
    acq.detectedPRN = [];
end

fprintf('捕获完成: 检测到 %d 颗卫星 %s，用时 %.1f s\n', ...
        numel(acq.detectedPRN), mat2str(acq.detectedPRN), toc(tStart));
end
