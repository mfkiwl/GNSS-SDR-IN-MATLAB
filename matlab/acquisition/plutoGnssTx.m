function plutoGnssTx(varargin)
%PLUTOGNSSTX PlutoSDR TX 发射合成 GPS L1 C/A 码信号（回环/天线测试）
%
%   用法：
%     plutoGnssTx                                % 默认：PRN5，20 ms 缓冲，低功率
%     plutoGnssTx('PRN', 8, 'DurationSec', 30)   % 指定 PRN 与发射时长
%     plutoGnssTx('Gain', 20, 'Amplitude', 0.3)  % 提高功率（天线测试时用）
%
%   可选参数 (Name-Value)：
%     'PRN'         - 发射的 C/A 码 PRN，默认 5
%     'Fs'          - 采样率，默认 2.5e6（必须与 RX 一致，Pluto 共享基带时钟）
%     'CenterFreq'  - 中心频率，默认 1575.42e6
%     'Gain'        - TX 增益 (dB)，范围 0 ~ -89.75；0 = 最大输出，
%                     默认 -30（回环/天线测试建议从衰减档起步）
%     'Amplitude'   - 基带幅度，默认 0.3
%     'DurationSec' - 发射时长 (s)，默认 20
%     'NavBits'     - 50 bps 导航电文比特（每比特 20 ms），默认 [] 表示全 1
%
%   注意：1575.42 MHz 为受保护频段，仅限室内低功率短时测试。

%% ---- 参数 ----
p = struct();
p.PRN         = 5;
p.Fs          = 2.5e6;
p.CenterFreq  = 1575.42e6;
p.Gain        = -30;
p.Amplitude   = 0.3;
p.DurationSec = 20;
p.NavBits     = [];

for k = 1:2:numel(varargin)
    key = varargin{k};
    val = varargin{k+1};
    switch lower(key)
        case 'prn',         p.PRN = val;
        case 'fs',          p.Fs = val;
        case 'centerfreq',  p.CenterFreq = val;
        case 'gain',        p.Gain = val;
        case 'amplitude',   p.Amplitude = val;
        case 'durationsec', p.DurationSec = val;
        case 'navbits',     p.NavBits = val(:).';
        otherwise, error('未知参数: %s', key);
    end
end

%% ---- 设备检测 ----
r = findPlutoRadio();
if isempty(r)
    error('未找到 PlutoSDR：请检查 USB 连接。');
end
radioID = r(1).RadioID;
fprintf('PlutoSDR: %s (序列号 %s)\n', radioID, r(1).SerialNum);

%% ---- 生成缓冲并发射 ----
buf = generateGnssTxBuffer(p.PRN, p.Fs, ...
    'Amplitude', p.Amplitude, 'NavBits', p.NavBits);
fprintf('发射 PRN %d 合成 GPS L1 C/A 码（%.1f MHz，%.3f MSPS，增益 %.1f dB，缓冲 %d ms，时长 %d s）\n', ...
    p.PRN, p.CenterFreq/1e6, p.Fs/1e6, p.Gain, numel(buf)/p.Fs*1000, p.DurationSec);

tx = sdrtx('Pluto', 'RadioID', radioID, ...
    'CenterFrequency', p.CenterFreq, 'BasebandSampleRate', p.Fs, ...
    'Gain', p.Gain);
try
    tx.transmitRepeat(buf);
    fprintf('已开始重复发射，%d 秒后自动停止（Ctrl+C 可提前中止）...\n', p.DurationSec);
    pause(p.DurationSec);
    release(tx);
    fprintf('发射已停止。\n');
catch err
    release(tx);
    rethrow(err);
end
delete(tx);
end
