function p = defaultParams()
%DEFAULTPARAMS 返回通信实验平台的默认仿真参数
p = struct( ...
    'mode',    'AM', ...      % 调制方式
    'fc',      25,  ...       % 载波频率 (Hz)
    'fm',      1,   ...       % 基带频率 (Hz)
    'fm2',     3,   ...       % 第二通道频率 (Hz)
    'fs',      1000, ...      % 采样率 (Hz)
    'T',       4,   ...       % 仿真时长 (s)
    'mu',      0.5, ...       % AM 调制度
    'beta',    5,   ...       % FM 调频指数
    'M',       16,  ...       % QAM 阶数
    'fdev',    10,  ...       % FSK 频偏 (Hz)
    'fc2',     65,  ...       % FDM 第二载波 (Hz)
    'snr',     30,  ...       % 信噪比 (dB)
    'noiseOn', false);        % 是否加入高斯白噪声
end
