function buf = generateMultiSatTxBuffer(prnList, fs, varargin)
%GENERATEMULTISATTXBUF 生成多颗模拟 GPS 卫星叠加的 TX 基带缓冲
%
%   buf = generateMultiSatTxBuffer(prnList, fs)
%   buf = generateMultiSatTxBuffer([5 8 13], fs, 'DelaysSamples', [0 1000 5000])
%
%   输入:
%     prnList - 卫星 PRN 列表（行向量）
%     fs      - 采样率 (Hz)
%   可选参数 (Name-Value):
%     'DelaysSamples' - 每颗星相对缓冲起点的码延迟（采样点，行向量，
%                       默认全 0）。用于注入伪距（ρ = c·delay/fs）
%     'NavBitsList'   - 每颗星的电文比特（cell，每项行向量，长度须一致；
%                       默认 20 ms 纯码）
%     'Amplitudes'    - 每颗星幅度（默认全 0.3）
%     'DopplersHz'    - 每颗星载波多普勒（默认全 0；注意 transmitRepeat
%                       缓冲回绕时载波相位跳变，小多普勒可接受）
%     'Normalize'     - 是否把叠加结果归一化到峰值 1（默认 true；
%                       硬件 TX 建议 false + 每星幅度 0.1，保持与单星
%                       已验证档位一致，避免归一化把单星功率压得太低）
%
%   输出:
%     buf - Nx1 复基带（整数个码周期，可 transmitRepeat）
%
%   说明:
%     - 每颗星按 generateGnssTxBuffer 生成单星缓冲后 circshift 延迟再叠加；
%       circshift 回绕即周期流中的码相位延迟（transmitRepeat 下正确）
%     - 所有星共用同一电文缓冲长度（= NavBits 数 x 20 ms），子帧起点
%       相对各自码延迟偏移，与真实多星电文结构一致

p = struct();
p.DelaysSamples = zeros(1, numel(prnList));
p.NavBitsList   = {};
p.Amplitudes    = 0.3 * ones(1, numel(prnList));
p.DopplersHz    = zeros(1, numel(prnList));
p.Normalize     = true;

for k = 1:2:numel(varargin)
    key = varargin{k};
    val = varargin{k+1};
    switch lower(key)
        case 'delayssamples', p.DelaysSamples = val(:).';
        case 'navbitslist',   p.NavBitsList = val;
        case 'amplitudes',    p.Amplitudes = val(:).';
        case 'dopplershz',    p.DopplersHz = val(:).';
        case 'normalize',     p.Normalize = val;
        otherwise, error('未知参数: %s', key);
    end
end

nSat = numel(prnList);
if numel(p.DelaysSamples) ~= nSat, error('DelaysSamples 长度须等于 PRN 数'); end
if numel(p.Amplitudes) ~= nSat,    error('Amplitudes 长度须等于 PRN 数'); end
if numel(p.DopplersHz) ~= nSat,    error('DopplersHz 长度须等于 PRN 数'); end
if ~isempty(p.NavBitsList) && numel(p.NavBitsList) ~= nSat
    error('NavBitsList 须为每星一项的 cell');
end

% 缓冲长度：以第一颗星的电文长度为准（默认 20 ms 纯码）
if isempty(p.NavBitsList)
    nav = cell(1, nSat);
    for i = 1:nSat, nav{i} = []; end
else
    nav = p.NavBitsList;
    L = numel(nav{1});
    for i = 2:nSat
        if numel(nav{i}) ~= L
            error('各星 NavBits 长度必须一致（%d vs %d）', L, numel(nav{i}));
        end
    end
end

% 逐星生成并叠加（幅度归一化到单星峰值，避免多星叠加削波）
msLen = round(fs * 1e-3);
buf = zeros(round(fs * 0.02 * max(1, numel(nav{1}))), 1);
for i = 1:nSat
    sig = generateGnssTxBuffer(prnList(i), fs, ...
        'Amplitude', p.Amplitudes(i), 'NavBits', nav{i});
    if p.DopplersHz(i) ~= 0
        t = (0:numel(sig)-1).';
        sig = sig .* exp(1j*2*pi*p.DopplersHz(i)*t/fs);
    end
    d = mod(round(p.DelaysSamples(i)), numel(sig));
    buf = buf + circshift(sig, d);
end

% 整体归一化（保持峰值不超过 1，便于 TX 幅度控制；硬件多星需关掉）
if p.Normalize
    buf = buf / max(abs(buf));
end
buf = complex(buf(:), 0);   % 强制复数类：MATLAB 的 + 会把零虚部折叠成实数，
                            % 而 Pluto TX 要求 I/Q（complex）输入
end
