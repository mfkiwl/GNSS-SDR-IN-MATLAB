function [word30, d29, d30] = gpsWordParity(data24, prevD29, prevD30, wordNumber)
%GPSWORDPARITY GPS 导航电文 30 位字奇偶校验（ICD-GPS-200 §20.3.5.4）
%
%   [word30, d29, d30] = gpsWordParity(data24, prevD29, prevD30)
%   [word30, d29, d30] = gpsWordParity(data24, prevD29, prevD30, wordNumber)
%
%   输入:
%     data24     - 1x24 逻辑数据位（bit1..bit24，未反转）
%     prevD29    - 前一个字的 D29 校验位（子帧首字为 0）
%     prevD30    - 前一个字的 D30 校验位（子帧首字为 0）
%     wordNumber - 字序号 1..10（可选）。字 2（HOW）与字 10 为 ICD 特例：
%                  D29/D30 恒为 0，bit23/24 由校验方程反推，且反馈重置为 0。
%                  缺省按普通字处理（连续反馈链）。
%   输出:
%     word30 - 1x30 完整发送字（bit1..24 已按 ICD 做 D30 位反转，
%              字 2/10 的 bit23/24 为反推值）
%     d29, d30 - 本字 D29/D30（供下一个字反馈；字 2/10 后恒为 0）
%
%   说明（与 MathWorks 官方 HelperGPSNAVDataEncode/gpsLNavWordEnc 逐位一致）:
%     - ICD 位反转：若前字 D30=1，本字 bit1..24 全部取反（BPSK 极性），
%       校验位按逻辑数据计算
%     - 字 2（HOW）与字 10 的 D29/D30 恒为 0（GPS.gov PIRN IS-200J-001、
%       gnsstk LNavTLMHOWFilter 等多源确认），使后续子帧奇偶链有效

data24 = double(data24(:).');
if numel(data24) ~= 24
    error('data24 必须为 24 位');
end
p29 = double(prevD29);
p30 = double(prevD30);
d = data24;

% ICD-GPS-200 §20.3.5.4 校验位参与数据位索引（D25..D30 依次）
parityTable = { ...
    [1 2 3 5 6 10 11 12 13 14 17 18 20 23], ...
    [2 3 4 6 7 11 12 13 14 15 18 19 21 24], ...
    [1 3 4 5 7 8 12 13 14 15 16 19 20 22], ...
    [2 4 5 6 8 9 13 14 15 16 17 20 21 23], ...
    [1 3 5 6 7 9 10 14 15 16 17 18 21 22 24], ...
    [3 5 6 8 9 10 11 13 15 19 22 23 24]};

if wordNumber == 2 || wordNumber == 10
    % ---- HOW / 字 10 特例：22 数据位，bit23/24 反推使 D29=D30=0 ----
    d25 = parityTable{1}; d26 = parityTable{2};
    d27 = parityTable{3}; d28 = parityTable{4};
    d29p = parityTable{5}; d30p = parityTable{6};

    bit24 = mod(sum(d(d29p(d29p < 23))) + p30, 2);
    bit23 = mod(sum(d(d30p(d30p < 23))) + bit24 + p29, 2);

    word30 = zeros(1, 30);
    word30(1:22) = mod(d(1:22) + p30, 2);
    word30(23) = mod(p30 + bit23, 2);
    word30(24) = mod(p30 + bit24, 2);
    word30(25) = mod(p29 + sum(d(d25(d25 < 23))) + bit23, 2);
    word30(26) = mod(p30 + sum(d(d26(d26 < 23))) + bit24, 2);
    word30(27) = mod(p29 + sum(d(d27(d27 < 23))), 2);
    word30(28) = mod(p30 + sum(d(d28(d28 < 23))) + bit23, 2);
    word30(29) = 0;
    word30(30) = 0;
    d29 = 0;
    d30 = 0;
else
    % ---- 普通字：24 位逻辑数据先做 D30 位反转，再按标准方程 ----
    invData = mod(d + p30, 2);
    % D25/D27/D30 用前字 D29；D26/D28/D29 用前字 D30
    prevUse = [p29 p30 p29 p30 p30 p29];
    par = zeros(1, 6);
    for k = 1:6
        par(k) = xor(prevUse(k), mod(sum(d(parityTable{k})), 2));
    end
    word30 = [invData, par];
    d29 = par(5);
    d30 = par(6);
end
end
