function [bits300, meta] = generateGpsSubframe(subframeId, tow, varargin)
%GENERATEGPSSUBFRAME 生成 GPS 导航电文子帧（300 位 / 6 秒，含奇偶校验）
%
%   [bits300, meta] = generateGpsSubframe(subframeId, tow)
%
%   输入:
%     subframeId - 子帧号 1..5
%     tow        - TOW 计数（6 秒为单位，0..403199）
%   可选参数 (Name-Value):
%     'TlmMsg'    - TLM 字消息 6 位（默认 [0 0 0 0 0 0]）
%     'DataWords' - 8 个数据字内容（8x24 矩阵；默认按字序号生成固定模式）
%
%   输出:
%     bits300 - 1x300 子帧比特（bit1 为子帧首比特）
%     meta    - 结构体：字列表、字段值（供对比用）

%% ---- 参数 ----
p = struct();
p.TlmMsg = zeros(1, 6);
p.DataWords = [];

for k = 1:2:numel(varargin)
    key = varargin{k};
    val = varargin{k+1};
    switch lower(key)
        case 'tlmmsg',   p.TlmMsg = val(:).';
        case 'datawords', p.DataWords = val;
        otherwise, error('未知参数: %s', key);
    end
end

if numel(p.TlmMsg) ~= 6, error('TlmMsg 必须为 6 位'); end
if ~isscalar(subframeId) || subframeId < 1 || subframeId > 5
    error('subframeId 必须为 1..5');
end

%% ---- 默认数据字（固定模式 + 字序号，便于对比）----
if isempty(p.DataWords)
    dw = zeros(8, 24);
    for w = 1:8
        % bit9..bit16 为字序号（8 位），其余为固定 1010 模式
        base = repmat([1 0], 1, 12);
        base(9:16) = de2bi(w, 8, 'left-msb');
        dw(w, :) = base;
    end
    p.DataWords = dw;
else
    if size(p.DataWords, 1) ~= 8 || size(p.DataWords, 2) ~= 24
        error('DataWords 必须为 8x24');
    end
end

%% ---- 逐字组装 + 奇偶校验 ----
preamble = [1 0 0 0 1 0 1 1];
pD29 = 0; pD30 = 0;      % 子帧首字的前字校验位为 0

% 字 1: TLM
tlmL = [preamble, p.TlmMsg, 1, 1, zeros(1,6), 0, 0];
[w1, pD29, pD30] = gpsWordParity(tlmL, pD29, pD30);

% 字 2: HOW
tow17 = de2bi(tow, 17, 'left-msb');
sfid3 = de2bi(subframeId, 3, 'left-msb');
howL = [tow17, 0, 0, sfid3, 0, 0];
[w2, pD29, pD30] = gpsWordParity(howL, pD29, pD30);

% 字 3..10: 数据字
words = cell(1, 10);
words{1} = w1; words{2} = w2;
for w = 1:8
    [words{w+2}, pD29, pD30] = gpsWordParity(p.DataWords(w, :), pD29, pD30);
end

bits300 = cell2mat(words(:).');

%% ---- 元数据 ----
meta = struct();
meta.subframeId = subframeId;
meta.tow        = tow;
meta.tlmMsg     = p.TlmMsg;
meta.preamble   = preamble;
meta.dataWords  = p.DataWords;
meta.words30    = reshape(bits300, 30, 10).';   % 10x30，每行一个字
meta.bits300    = bits300;
end
