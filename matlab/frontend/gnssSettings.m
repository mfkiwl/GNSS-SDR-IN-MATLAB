function s = gnssSettings()
%GNSSSETTINGS GNSS 接收前端与处理参数（PlutoSDR + GPS L1 C/A）
%   返回参数结构体，供 plutoGnssFrontEnd.m 使用。
s = struct();

%% ---- 射频前端（PlutoSDR / AD9363）----
s.centerFreq    = 1575.42e6;    % GPS L1 载波频率 (Hz)
s.fs            = 2.5e6;        % 采样率 (Hz)，≥ 2.046e6 即可容纳 C/A 码主瓣
s.gainMode      = 'AGC Slow Attack';  % 或 'Manual'
s.gainDb        = 50;           % Manual 模式下的接收增益 (dB)

%% ---- 采集 ----
s.durationMs    = 2000;         % 默认采集时长 (ms)
s.outputDir     = fullfile(fileparts(mfilename('fullpath')), 'data');

%% ---- 接收机处理（对接 SoftGNSS / 教材代码）----
s.IF            = 0;            % Pluto 直接下变频到零中频
s.codeFreqBasis = 1.023e6;      % C/A 码速率 (Hz)
s.codeLength    = 1023;         % C/A 码长度 (chips)
s.dataType      = 'int8';       % 落盘格式（SoftGNSS 兼容：交织 I/Q int8）
s.satList       = 1:32;         % 待捕获 PRN 列表
end
