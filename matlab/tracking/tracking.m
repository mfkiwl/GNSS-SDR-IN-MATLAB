function trk = tracking(data, fs, acq, varargin)
%TRACKING GPS L1 C/A 信号跟踪（DLL + PLL 多通道）
%
%   trk = tracking(data, fs, acq)
%   trk = tracking(data, fs, acq, 'PRNList', [5 8], 'PllBandwidth', 10)
%
%   输入:
%     data - 复基带 IQ（列向量，与 acquisition() 使用的同一段数据）
%     fs   - 采样率 (Hz)
%     acq  - acquisition() 输出结构（须含 results.codePhase / dopplerHz）
%
%   可选参数 (Name-Value):
%     'PRNList'       - 待跟踪 PRN 列表，默认 acq.detectedPRN
%     'IntegrationMs' - 环路相干积分时长 (ms)，默认 1（允许 1~10）
%     'PllBandwidth'  - PLL 环路带宽 (Hz)，默认 18
%     'DllBandwidth'  - DLL 环路带宽 (Hz)，默认 2
%     'CorrSpacing'   - 超前/滞后相关器间距 (chips)，默认 0.5
%     'ReferenceBits' - 已知电文比特（可选，位同步评分与误码统计）
%     'CN0Threshold'  - 锁定判定 C/N0 门限 (dB-Hz)，默认 30
%     'Verbose'       - 是否打印逐通道进度，默认 true
%
%   输出（单通道为标量结构，多通道为 1xN 结构数组）:
%     trk(k).PRN / acqCodePhase / acqDoppler - 初值（捕获结果）
%     trk(k).codePhase    - 每 ms 码相位（0-based 采样点，码周期内）
%     trk(k).carrierFreq  - 每 ms 载波频率估计 (Hz)
%     trk(k).carrierPhase - 每 ms 本地载波相位 (rad)
%     trk(k).I_P/Q_P/I_E/Q_E/I_L/Q_L - 每 ms 相关值（环路更新粒度按
%                                       IntegrationMs 累加后使用）
%     trk(k).discrPll / discrDll      - 每 ms 鉴别器输出（块内保持）
%     trk(k).CN0dBHz      - 每 20 ms C/N0 (dB-Hz)
%     trk(k).msValues     - I_P + j*Q_P（供位同步/电文解调）
%     trk(k).bitOffsetMs  - 位同步偏移 (0~19 ms)
%     trk(k).bits         - 解调比特（0/1 行向量）
%     trk(k).numErrors / matchRate / refBits - 提供 ReferenceBits 时
%     trk(k).lock         - 锁定判定（C/N0 + PLL/DLL 残差）
%     trk(k).lockMetrics  - 锁定指标明细
%
%   参考: SoftGNSS tracking.m（DLL/PLL 环路结构），参数语义与
%   acquisition.m / demodulateNavBits.m 保持一致。

%% ---- 默认参数 ----
p = struct();
p.PRNList       = [];
p.IntegrationMs = 1;
p.PllBandwidth  = 18;
p.DllBandwidth  = 2;
p.CorrSpacing   = 0.5;
p.ReferenceBits = [];
p.CN0Threshold  = 30;
p.Verbose       = true;

for k = 1:2:numel(varargin)
    key = varargin{k};
    val = varargin{k+1};
    switch lower(key)
        case 'prnlist',       p.PRNList = val(:).';
        case 'integrationms', p.IntegrationMs = val;
        case 'pllbandwidth',  p.PllBandwidth = val;
        case 'dllbandwidth',  p.DllBandwidth = val;
        case 'corrspacing',   p.CorrSpacing = val;
        case 'referencebits', p.ReferenceBits = val(:).';
        case 'cn0threshold',  p.CN0Threshold = val;
        case 'verbose',       p.Verbose = val;
        otherwise, error('未知参数: %s', key);
    end
end

%% ---- 输入检查与公共参数 ----
data = data(:);
if ~isfloat(data)
    error('data 必须为浮点类型（complex double）');
end
if ~isscalar(fs) || fs <= 0
    error('fs 必须为正标量');
end
if p.IntegrationMs < 1 || p.IntegrationMs > 10 || ...
        round(p.IntegrationMs) ~= p.IntegrationMs
    error('IntegrationMs 须为 1~10 的整数');
end

st            = gnssSettings();
codeFreqBasis = st.codeFreqBasis;
codeLength    = st.codeLength;
msLen         = round(fs * 1e-3);
nMs           = floor(numel(data) / msLen);
if nMs < 40
    error('数据长度不足: 至少需要 40 ms，实际 %.1f ms', numel(data)/fs*1000);
end

if isempty(p.PRNList)
    p.PRNList = acq.detectedPRN;
end
if isempty(p.PRNList)
    error('acq.detectedPRN 为空：请先捕获或显式指定 PRNList');
end

%% ---- 环路参数 ----
zeta = 0.7071;
% 二阶环路自然角频率: wn = 8*zeta*BL / (4*zeta^2 + 1)
% PLL: 鉴别器输出 rad -> 频率修正 Hz
wnP = 8*zeta*p.PllBandwidth / (4*zeta^2 + 1);
aP  = 2*zeta*wnP / (2*pi);            % Hz/rad
bP  = wnP^2 * 1e-3 / (2*pi);          % Hz/rad（含 T=1 ms）
% DLL: 鉴别器输出 chip -> 码速率修正 chips/s
wnC = 8*zeta*p.DllBandwidth / (4*zeta^2 + 1);
aC  = 2*zeta*wnC;                     % (chips/s)/chip
bC  = wnC^2 * 1e-3;                   % (chips/s)/chip（含 T=1 ms）
spacingSamp = p.CorrSpacing * fs / codeFreqBasis;   % E/L 间距（采样点）

n = (0:msLen-1).';
out = {};

%% ---- 逐通道跟踪 ----
for c = 1:numel(p.PRNList)
    prn = p.PRNList(c);
    r   = acq.results(find([acq.results.PRN] == prn, 1)); %#ok<FNDSB>
    if isempty(r)
        error('acq 中没有 PRN %d 的捕获结果', prn);
    end

    d0        = mod(r.codePhase - 1, msLen);   % 码相位 1-based -> 0-based 延迟
    fd0       = r.dopplerHz;
    ca        = gnssCACode(prn, 'GPS');
    bip       = 2*double(ca) - 1;

    % 状态变量
    carrierFreq = fd0;
    carrierPhase = 0;
    codeNco = fd0 * codeFreqBasis / st.centerFreq;  % 码多普勒初值 (chips/s)
    d       = d0;
    pllAcc  = 0;
    dllAcc  = 0;

    % 预分配记录数组
    codePhases    = zeros(nMs, 1);
    carrierFreqs  = zeros(nMs, 1);
    carrierPhases = zeros(nMs, 1);
    iP = zeros(nMs,1); qP = zeros(nMs,1);
    iE = zeros(nMs,1); qE = zeros(nMs,1);
    iL = zeros(nMs,1); qL = zeros(nMs,1);
    discrP = zeros(nMs,1);
    discrC = zeros(nMs,1);

    % 相干积分块累加器
    aIE = 0; aQE = 0; aIP = 0; aQP = 0; aIL = 0; aQL = 0;

    for k = 1:nMs
        idx = (k-1)*msLen + (1:msLen);

        % 本地载波（相位连续，块首相位 = carrierPhase）
        mix = exp(-1j*(2*pi*carrierFreq*n/fs + carrierPhase));
        x   = data(idx) .* mix;

        % 本地 C/A 码（超前/即时/滞后），延迟 d 可为分数
        cIdxP = mod(floor((n - d)          * codeFreqBasis/fs), codeLength) + 1;
        cIdxE = mod(floor((n - (d - spacingSamp)) * codeFreqBasis/fs), codeLength) + 1;
        cIdxL = mod(floor((n - (d + spacingSamp)) * codeFreqBasis/fs), codeLength) + 1;
        cP = bip(cIdxP); cE = bip(cIdxE); cL = bip(cIdxL);

        I_P = sum(real(x .* cP)); Q_P = sum(imag(x .* cP));
        I_E = sum(real(x .* cE)); Q_E = sum(imag(x .* cE));
        I_L = sum(real(x .* cL)); Q_L = sum(imag(x .* cL));

        % 块内相干累加（IntegrationMs=1 时即为单 ms 值）
        aIE = aIE + I_E; aQE = aQE + Q_E;
        aIP = aIP + I_P; aQP = aQP + Q_P;
        aIL = aIL + I_L; aQL = aQL + Q_L;

        if mod(k, p.IntegrationMs) == 0
            % 鉴别器（Costas PLL: atan(Q/I)，对 180° 电文翻转不敏感）
            if aIP == 0 && aQP == 0
                pllErr = 0;
            else
                pllErr = atan(aQP / aIP);
            end
            eAmp = sqrt(aIE^2 + aQE^2);
            lAmp = sqrt(aIL^2 + aQL^2);
            dllErr = (eAmp - lAmp) / (eAmp + lAmp + eps);

            % 环路滤波器（二阶，位置式 PI：输出 = 初值 + Kp*e + Ki*acc。
            % 注意不能用增量式 f += Kp*e（会把比例项也积分成双积分器，
            % 导致噪声下随机游走、频偏下极限环）
            carrierFreq = fd0 + aP*pllErr + bP*pllAcc;
            pllAcc      = pllAcc + pllErr;
            % DLL 负反馈：鉴别器为正（本地码滞后）时减小码速率，
            % 使本地码延迟向真值收敛（正反馈会导致码环跑飞）
            codeNco     = -(aC*dllErr + bC*dllAcc);
            dllAcc      = dllAcc + dllErr;

            % 块内 ms 记录鉴别器（保持值）
            discrP(k-p.IntegrationMs+1 : k) = pllErr;
            discrC(k-p.IntegrationMs+1 : k) = dllErr;
            aIE = 0; aQE = 0; aIP = 0; aQP = 0; aIL = 0; aQL = 0;
        end

        % 推进 NCO（相位连续）
        carrierPhase = carrierPhase + 2*pi*carrierFreq*1e-3;
        carrierPhase = mod(carrierPhase + pi, 2*pi) - pi;   % 包到 [-pi, pi)
        d = mod(d + msLen*(1 + codeNco/codeFreqBasis), msLen);

        % 记录
        codePhases(k)    = d;
        carrierFreqs(k)  = carrierFreq;
        carrierPhases(k) = carrierPhase;
        iP(k) = I_P; qP(k) = Q_P;
        iE(k) = I_E; qE(k) = Q_E;
        iL(k) = I_L; qL(k) = Q_L;
    end

    % 末尾不足一个积分块的累加器：补一次鉴别器/环路更新（若已积累）
    if mod(nMs, p.IntegrationMs) ~= 0
        if aIP == 0 && aQP == 0
            pllErr = 0;
        else
            pllErr = atan(aQP / aIP);
        end
        eAmp = sqrt(aIE^2 + aQE^2);
        lAmp = sqrt(aIL^2 + aQL^2);
        dllErr = (eAmp - lAmp) / (eAmp + lAmp + eps);
        carrierFreq = fd0 + aP*pllErr + bP*pllAcc;
        pllAcc  = pllAcc + pllErr;
        codeNco = -(aC*dllErr + bC*dllAcc);
        dllAcc  = dllAcc + dllErr;
        lastBlock = mod(nMs, p.IntegrationMs);
        discrP(nMs-lastBlock+1 : nMs) = pllErr;
        discrC(nMs-lastBlock+1 : nMs) = dllErr;
    end

    %% ---- 位同步 + 解调比特（用锁定后的数据段）----
    skipMs = min(300, max(50, floor(nMs*0.05)));
    msUse  = (iP(1+skipMs:end) + 1j*qP(1+skipMs:end));
    edge   = gnssBitEdgeDetect(msUse);
    nBu    = floor((numel(msUse) - edge.bitOffsetMs) / 20);
    accB   = zeros(nBu, 1);
    for j = 1:nBu
        accB(j) = sum(msUse(edge.bitOffsetMs + (j-1)*20 + (1:20)));
    end
    [~, mi] = max(abs(accB));
    phi  = angle(accB(mi));                 % 以最强比特校准载波相位
    soft = real(accB * exp(-1j*phi));
    bits = double(soft > 0).';

    %% ---- C/N0（窄带/宽带功率比法，20 ms 窗口按位同步对齐）----
    % 注意：窗口必须对齐数据比特边缘，否则跨比特翻转时窄带功率被抵消，
    % C/N0 会被严重低估（实测可差 ~25 dB）
    bFull = mod(edge.bitOffsetMs + skipMs, 20);
    msFull = iP + 1j*qP;
    nW = floor((nMs - bFull) / 20);
    cn0 = zeros(nW, 1);
    for w = 1:nW
        seg = bFull + (w-1)*20 + (1:20);
        nbp = abs(sum(msFull(seg)))^2;
        wbp = sum(abs(msFull(seg)).^2);
        rr  = min(max(nbp / max(wbp, eps), 1.001), 19.5);
        cn0(w) = 10*log10(1000 * (rr - 1) / (20 - rr));
    end
    if nW >= 5
        cn0 = movmedian(cn0, 5);
    end

    %% ---- 锁定指标 ----
    nRes = min(500, nMs);
    pllRes = mean(abs(discrP(end-nRes+1 : end)));
    dllRes = mean(abs(discrC(end-nRes+1 : end)));
    nCn0 = min(50, nW);
    cn0Med = median(cn0(end-nCn0+1 : end));
    % 码相位稳定性：末 1 s 码延迟的圆周标准差（采样点）
    dLast = codePhases(end-min(1000,nMs)+1 : end);
    dMean = mean(dLast);
    dCirc = mod(dLast - dMean + msLen/2, msLen) - msLen/2;
    dStd  = std(dCirc);
    % PLL 残差阈值取 0.6 rad：CN0 30 时相位噪声均值约 0.55 rad，
    % 0.6 既能覆盖弱信号正常锁定，又能区分真正跑飞（发散时 >0.7）
    lock = (cn0Med >= p.CN0Threshold) && (pllRes <= 0.6) && (dStd <= 1.0);
    lockMetrics = struct('cn0MedianDbHz', cn0Med, 'pllResidualRad', pllRes, ...
        'dllResidual', dllRes, 'codePhaseStd', dStd, ...
        'pllDiscrMean', mean(discrP(end-nRes+1:end)), ...
        'dllDiscrMean', mean(discrC(end-nRes+1:end)));

    %% ---- 组装输出 ----
    ch = struct();
    ch.PRN          = prn;
    ch.acqCodePhase = r.codePhase;
    ch.acqDoppler   = fd0;
    ch.codePhase    = codePhases;
    ch.carrierFreq  = carrierFreqs;
    ch.carrierPhase = carrierPhases;
    ch.I_P = iP; ch.Q_P = qP; ch.I_E = iE; ch.Q_E = qE;
    ch.I_L = iL; ch.Q_L = qL;
    ch.discrPll = discrP;
    ch.discrDll = discrC;
    ch.CN0dBHz  = cn0;
    ch.msValues = iP + 1j*qP;
    ch.bitOffsetMs = edge.bitOffsetMs;
    ch.bits     = bits;
    ch.lock     = lock;
    ch.lockMetrics = lockMetrics;

    if ~isempty(p.ReferenceBits)
        % BPSK 180° 极性模糊：参考匹配须同时测原样/取反两种极性
        % （真实接收机用前导码+奇偶校验消除极性，此处为统计用）
        ref = p.ReferenceBits(:).';
        L   = numel(ref);
        nB  = numel(bits);
        bestScore = -inf; bestShift = 0; bestPol = 1;
        for pol = [1, 0]
            bb = bits;
            if pol == 0, bb = 1 - bits; end
            for s = 0:L-1
                refCyc = ref(mod((0:nB-1) + s, L) + 1);
                sc = sum(bb == refCyc);
                if sc > bestScore, bestScore = sc; bestShift = s; bestPol = pol; end
            end
        end
        ch.refBits   = ref(mod((0:nB-1) + bestShift, L) + 1);
        if bestPol == 0, ch.refBits = 1 - ch.refBits; end
        ch.numErrors = nB - bestScore;
        ch.matchRate = bestScore / nB;
        ch.polarity  = bestPol;   % 1=原样, 0=取反
    end

    out{c} = ch; %#ok<AGROW>

    if p.Verbose
        fprintf('PRN %2d: lock=%d  CN0=%.1f dB-Hz  f=%+8.2f Hz  bitSync=%d ms  bits=%d\n', ...
            prn, lock, cn0Med, median(carrierFreqs(end-nRes+1:end)), ...
            edge.bitOffsetMs, numel(bits));
    end
end

%% ---- 输出：单通道为标量结构，多通道为 1xN 结构数组（trk(1) 均可用）----
if numel(out) == 1
    trk = out{1};
else
    trk = [out{:}];
end
end
