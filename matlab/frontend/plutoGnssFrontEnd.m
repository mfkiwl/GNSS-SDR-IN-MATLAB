function plutoGnssFrontEnd(varargin)
%PLUTOGNSSFRONTEND 配置 PlutoSDR 前端并采集 GPS L1 IQ 数据
%   用法：
%     plutoGnssFrontEnd                                  % 使用默认参数
%     plutoGnssFrontEnd('Fs',5e6,'DurationMs',1000)      % 覆盖采样率/时长
%     plutoGnssFrontEnd('GainMode','Manual','GainDb',40) % 手动增益
%
%   输出（保存到 data\ 目录）：
%     pluto_gnss_<时间戳>.mat  - 复杂 IQ（double）+ 采集参数
%     pluto_gnss_<时间戳>.bin  - int8 交织 I/Q（SoftGNSS 可直接读取）

p = gnssSettings();

% ---- 解析可选参数 ----
for k = 1:2:numel(varargin)
    key = varargin{k};
    val = varargin{k+1};
    switch lower(key)
        case 'fs',           p.fs = val;
        case 'centerfreq',   p.centerFreq = val;
        case 'durationms',   p.durationMs = val;
        case 'gainmode',     p.gainMode = val;
        case 'gaindb',       p.gainDb = val;
        otherwise, error('未知参数: %s', key);
    end
end

if ~exist(p.outputDir, 'dir')
    mkdir(p.outputDir);
end

%% ---- 自动检测 PlutoSDR ----
r = findPlutoRadio();
if isempty(r)
    error(['未找到 PlutoSDR：请检查 USB 连接。' ...
           '正常时系统应出现 "PlutoSDR Serial Console (COMx)" 和 ' ...
           '"PlutoSDR USB Ethernet/RNDIS Gadget" 两个设备。']);
end
radioID = r(1).RadioID;
fprintf('找到 PlutoSDR：%s（序列号 %s）\n', radioID, r(1).SerialNum);

%% ---- 配置 PlutoSDR 接收机 ----
fprintf('连接 PlutoSDR：中心频率 %.6f MHz，采样率 %.3f MSPS ...\n', ...
        p.centerFreq/1e6, p.fs/1e6);

rx = sdrrx('Pluto', ...
    'RadioID',          radioID, ...
    'CenterFrequency',  p.centerFreq, ...
    'BasebandSampleRate', p.fs, ...
    'GainSource',       p.gainMode, ...
    'OutputDataType',   'double');

if strcmpi(p.gainMode, 'Manual')
    rx.Gain = p.gainDb;
end

%% ---- 采集 ----
nSamp = round(p.fs * p.durationMs / 1000);
[data, mdata] = capture(rx, nSamp);
fprintf('采集完成：%d 采样（%.1f ms @ %.2f MSPS）\n', ...
        numel(data), numel(data)/p.fs*1000, p.fs/1e6);

%% ---- 基本校验 ----
rmsV = rms(data);
pk   = max(abs(data));
fprintf('信号校验：RMS=%.5f，峰值=%.5f，峰值/RMS=%.2f\n', rmsV, pk, pk/max(rmsV,eps));
if pk < 1e-6
    warning('采集到的信号几乎为零，请检查天线/增益/连接。');
end

%% ---- 保存：.mat + .bin(int8 交织，SoftGNSS 兼容) ----
timeStamp = datestr(now, 'yyyymmdd_HHMMSS');
matFile = fullfile(p.outputDir, ['pluto_gnss_' timeStamp '.mat']);
binFile = fullfile(p.outputDir, ['pluto_gnss_' timeStamp '.bin']);

scale = 120 / max(abs(data));          % 防止削波，充分利用 int8 动态范围
i8 = int8(round(real(data)*scale));
q8 = int8(round(imag(data)*scale));
iqInterleaved = reshape([i8.'; q8.'], [], 1);

fid = fopen(binFile, 'wb');
fwrite(fid, iqInterleaved, 'int8');
fclose(fid);

save(matFile, 'data', 'p', 'mdata');

fprintf('已保存：\n  %s\n  %s\n', matFile, binFile);
fprintf('建议下一步：用 SoftGNSS 处理该文件（IF=0, fs=%.3f MHz, int8）\n', p.fs/1e6);
end
