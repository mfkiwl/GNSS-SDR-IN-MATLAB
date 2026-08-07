function out = demodulateNavBits(data, fs, acq, prn, varargin)
%DEMODULATENAVBITS 从 GPS L1 C/A 信号中解调 50 bps 导航电文比特
%
%   out = demodulateNavBits(data, fs, acq, prn)
%
%   输入:
%     data - 复基带 IQ（与 acquisition 使用的同一段数据）
%     fs   - 采样率 (Hz)
%     acq  - acquisition() 输出结构（含 results 数组）
%     prn  - 目标卫星 PRN
%
%   可选参数 (Name-Value):
%     'ReferenceBits' - 已知参考电文比特（用于位同步与匹配统计）
%     'BitOffsetMs'   - 指定位同步偏移 (0~19 ms)，跳过自动搜索
%     'CodePhase'     - 覆盖码相位（1-based），默认取捕获结果
%     'DopplerHz'     - 覆盖多普勒 (Hz)，默认取捕获结果
%
%   输出 out:
%     .bits          - 解调比特（0/1 行向量，最佳位同步偏移下）
%     .soft          - 每比特软值（相位旋转后实部，符号判决依据）
%     .acc           - 每比特复数累加值（20 ms 相干积分）
%     .msValues      - 每 1 ms 相关复数（去载波去码后）
%     .bitOffsetMs   - 位同步偏移 (0~19 ms)
%     .numErrors     - 与参考比特的错位数（提供 ReferenceBits 时）
%     .matchRate     - 匹配率（提供 ReferenceBits 时）
%     .refBits       - 对齐后的参考比特（提供 ReferenceBits 时）

%% ---- 参数 ----
p = struct();
p.ReferenceBits = [];
p.BitOffsetMs  = [];
p.CodePhase = [];
p.DopplerHz  = [];

for k = 1:2:numel(varargin)
    key = varargin{k};
    val = varargin{k+1};
    switch lower(key)
        case 'referencebits', p.ReferenceBits = val(:).';
        case 'bitoffsetms',   p.BitOffsetMs = val;
        case 'codephase',     p.CodePhase = val;
        case 'dopplerhz',     p.DopplerHz = val;
        otherwise, error('未知参数: %s', key);
    end
end

%% ---- 取捕获结果 ----
idx = find([acq.results.PRN] == prn);
if isempty(idx)
    error('acq 中没有 PRN %d 的捕获结果', prn);
end
r = acq.results(idx(1));
codePhase = p.CodePhase;  if isempty(codePhase), codePhase = r.codePhase; end
dopplerHz = p.DopplerHz;  if isempty(dopplerHz), dopplerHz = r.dopplerHz; end

%% ---- C/A 码 ----
try
    st            = gnssSettings();
    codeFreqBasis = st.codeFreqBasis;
    codeLength    = st.codeLength;
catch
    codeFreqBasis = 1.023e6;
    codeLength    = 1023;
end
msLen = round(fs * 1e-3);
ca    = gnssCACode(prn, 'GPS');
bip   = 2*double(ca) - 1;
nms   = (0:msLen-1).';
chip  = mod(floor(nms * codeFreqBasis / fs), codeLength) + 1;
code1 = bip(chip);

data = data(:);
nMs  = floor(numel(data) / msLen);
if nMs < 20
    error('数据长度不足一个电文比特（需要 >= 20 ms）');
end

delay0 = mod(codePhase - 1, msLen);     % 1 ms 内的码延迟（0-based）

%% ---- 码相位精对齐（±3 采样扫描，取 20 ms 能量最大）----
searchD = mod(delay0-3 : delay0+3, msLen);
bestE = -inf; bestD = delay0;
for d = searchD
    codeA = circshift(code1, d);
    e = 0;
    for i = 1:min(20, nMs)
        idx1 = (i-1)*msLen + (1:msLen);
        t1   = (i-1)*msLen + (0:msLen-1).';
        x    = data(idx1) .* exp(-1j*2*pi*dopplerHz*t1/fs) .* codeA;
        e    = e + abs(sum(x))^2;
    end
    if e > bestE, bestE = e; bestD = d; end
end

%% ---- 逐 1 ms 相关（剥码 + 去载波）----
codeA  = circshift(code1, bestD);
msVals = zeros(nMs, 1);
for i = 1:nMs
    idx1 = (i-1)*msLen + (1:msLen);
    t1   = (i-1)*msLen + (0:msLen-1).';
    x    = data(idx1) .* exp(-1j*2*pi*dopplerHz*t1/fs) .* codeA;
    msVals(i) = sum(x);
end

%% ---- 位同步：候选偏移 0~19 ms，按 20 ms 分组相干累加 ----
cands = struct('acc', {}, 'soft', {}, 'bits', {}, 'score', {});
for k = 0:19
    nB = floor((nMs - k) / 20);
    acc = zeros(nB, 1);
    for j = 1:nB
        acc(j) = sum(msVals(k + (j-1)*20 + (1:20)));
    end
    [~, mi] = max(abs(acc));
    phi  = angle(acc(mi));               % 以能量最大的比特校准残余载波相位
    soft = real(acc * exp(-1j*phi));
    bits = double(soft > 0).';           % 行向量，与参考比特逐位比较
    score = -inf;
    if ~isempty(p.ReferenceBits)
        ref = p.ReferenceBits(:)';
        L   = numel(ref);
        % 按 40 位周期循环生成参考（不能对截断序列 circshift：
        % 99 不是 40 的倍数，会破坏周期结构）
        for s = 0:L-1
            refCyc = ref(mod((0:nB-1) + s, L) + 1);
            score = max(score, sum(bits == refCyc));
        end
    end
    cands(end+1) = struct('acc', acc, 'soft', soft, 'bits', bits, 'score', score); %#ok<AGROW>
end

%% ---- 选择最佳位同步偏移 ----
if ~isempty(p.BitOffsetMs)
    bestK = p.BitOffsetMs + 1;                % 1-based 索引
    bestK = max(1, min(numel(cands), bestK));
elseif ~isempty(p.ReferenceBits)
    [~, bestK] = max([cands.score]);
else
    bestK = 1;                            % 无参考时默认偏移 0 ms
end
bestK = bestK - 1;                        % 0-based

out.bitOffsetMs = bestK;
out.msValues    = msVals;
out.acc         = cands(bestK+1).acc;
out.soft        = cands(bestK+1).soft;
out.bits        = cands(bestK+1).bits;
out.bitScores   = [cands.score];

if ~isempty(p.ReferenceBits)
    ref = p.ReferenceBits(:)';
    L   = numel(ref);
    nB  = numel(out.bits);
    bestScore = -inf; bestShift = 0;
    for s = 0:L-1
        refCyc = ref(mod((0:nB-1) + s, L) + 1);
        sc = sum(out.bits == refCyc);
        if sc > bestScore, bestScore = sc; bestShift = s; end
    end
    out.refBits   = ref(mod((0:nB-1) + bestShift, L) + 1);
    out.numErrors = nB - bestScore;
    out.matchRate = bestScore / nB;
end
end
