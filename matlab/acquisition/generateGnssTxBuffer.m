function buf = generateGnssTxBuffer(prn, fs, varargin)
%GENERATEGNSSTXBUFFER 生成用于 PlutoSDR TX 的合成 GPS L1 C/A 码基带缓冲
%
%   buf = generateGnssTxBuffer(prn, fs)                 % 默认 20 ms 纯码
%   buf = generateGnssTxBuffer(8, 2.5e6, 'NavBits', [1 0 1])
%
%   可选参数 (Name-Value):
%     'DurationMs' - 缓冲时长 (ms)，默认 20；须为整数（含整数个码周期）
%     'Amplitude'  - 基带幅度，默认 0.3
%     'NavBits'    - 50 bps 导航电文比特（每比特 20 ms），默认 [] 表示全 1
%
%   说明:
%     - 缓冲为整数个 C/A 码周期（1 ms），保证 transmitRepeat 相位连续
%       （M1 关键发现：非整数周期会导致发送端逐帧跳相）
%     - 有 NavBits 时缓冲时长 = 20*numel(NavBits) ms，码周期与电文比特均整数

%% ---- 默认参数 ----
p = struct();
p.DurationMs = 20;
p.Amplitude  = 0.3;
p.NavBits    = [];

for k = 1:2:numel(varargin)
    key = varargin{k};
    val = varargin{k+1};
    switch lower(key)
        case 'durationms', p.DurationMs = val;
        case 'amplitude',  p.Amplitude = val;
        case 'navbits',    p.NavBits = val(:).';
        otherwise, error('未知参数: %s', key);
    end
end

%% ---- C/A 码参数 ----
try
    st            = gnssSettings();
    codeFreqBasis = st.codeFreqBasis;
    codeLength    = st.codeLength;
catch
    codeFreqBasis = 1.023e6;
    codeLength    = 1023;
end

%% ---- 1 ms 码序列（与 acquisition.m / generateSyntheticGpsSignal.m 同法采样）----
msLen = round(fs * 1e-3);
ca    = gnssCACode(prn, 'GPS');
bip   = 2*double(ca) - 1;
nms   = (0:msLen-1).';
chip  = mod(floor(nms * codeFreqBasis / fs), codeLength) + 1;
code1 = bip(chip);

%% ---- 组装缓冲 ----
if isempty(p.NavBits)
    buf = repmat(code1, p.DurationMs, 1);
else
    bitSigns = 2*p.NavBits(:) - 1;
    seg      = repmat(code1, 20, 1);          % 1 个电文比特 = 20 ms = 20 个码周期
    buf      = kron(bitSigns, seg);
end

buf = p.Amplitude * buf / max(abs(buf));
buf = complex(buf(:), 0);      % BPSK：I=码序列, Q=0（Pluto TX 要求复数 I/Q）
end
