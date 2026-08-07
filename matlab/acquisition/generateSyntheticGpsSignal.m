function [sig, truth] = generateSyntheticGpsSignal(varargin)
%GENERATESYNTHETICGPSSIGNAL 生成 GPS L1 C/A 复基带合成信号（离线测试用）
%
%   [sig, truth] = generateSyntheticGpsSignal('PRN', 5, 'Fs', 2.5e6)
%
%   可选参数 (Name-Value):
%     'PRN'        - PRN 号，默认 5
%     'Fs'         - 采样率 (Hz)，默认 2.5e6
%     'DurationMs' - 时长 (ms)，默认 20
%     'CodePhase'  - 码相位（采样点，0-based：从块起点到下一个码周期
%                    起点的延迟，与 acquisition.m 输出语义一致），默认 0
%     'DopplerHz'  - 多普勒频移 (Hz)，默认 0（正数 = 高于中心频率）
%     'CN0dBHz'    - 载噪比 (dB-Hz)，默认 45；Inf = 不加噪声
%     'Seed'       - 随机种子，默认 42（保证可复现）
%     'Amplitude'  - 信号幅度，默认 1
%
%   输出:
%     sig   - 复基带 IQ（列向量）
%     truth - 真实参数结构（供测试断言使用）

%% ---- 默认参数 ----
p = struct();
p.PRN        = 5;
p.Fs         = 2.5e6;
p.DurationMs = 20;
p.CodePhase  = 0;
p.DopplerHz  = 0;
p.CN0dBHz    = 45;
p.Seed       = 42;
p.Amplitude  = 1;

% ---- 解析可选参数 ----
for k = 1:2:numel(varargin)
    key = varargin{k};
    val = varargin{k+1};
    switch lower(key)
        case 'prn',        p.PRN = val;
        case 'fs',         p.Fs = val;
        case 'durationms', p.DurationMs = val;
        case 'codephase',  p.CodePhase = val;
        case 'dopplerhz',  p.DopplerHz = val;
        case 'cn0dbhz',    p.CN0dBHz = val;
        case 'seed',       p.Seed = val;
        case 'amplitude',  p.Amplitude = val;
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

%% ---- 合成信号 ----
n  = (0 : round(p.Fs*p.DurationMs/1000) - 1).';
ca = gnssCACode(p.PRN, 'GPS');
bip = 2*double(ca) - 1;

% 按采样时刻直接取码片：码周期起点位于样本 p.CodePhase 处
% （与 acquisition.m 的码相位输出语义一致）
chip = mod(floor((n - p.CodePhase) * codeFreqBasis / p.Fs), codeLength) + 1;
codeStream = bip(chip);

carrier = exp(1j * 2*pi * p.DopplerHz * n / p.Fs);
sig = p.Amplitude * codeStream .* carrier;

if isfinite(p.CN0dBHz)
    rng(p.Seed);
    sigma = p.Amplitude * sqrt(p.Fs / 10^(p.CN0dBHz/10));
    sig = sig + (randn(size(sig)) + 1j*randn(size(sig))) * sigma/sqrt(2);
end

truth = struct('PRN', p.PRN, 'Fs', p.Fs, 'DurationMs', p.DurationMs, ...
    'CodePhase', p.CodePhase, 'DopplerHz', p.DopplerHz, ...
    'CN0dBHz', p.CN0dBHz, 'Seed', p.Seed, 'Amplitude', p.Amplitude, ...
    'Length', numel(sig));
end
