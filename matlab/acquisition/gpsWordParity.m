function [word30, d29, d30] = gpsWordParity(data24, prevD29, prevD30)
%GPSWORDPARITY GPS 导航电文 30 位字奇偶校验（ICD-GPS-200 §20.3.5.4）
%
%   [word30, d29, d30] = gpsWordParity(data24, prevD29, prevD30)
%
%   输入:
%     data24   - 1x24 数据位（0/1），对应字内 bit1..bit24
%     prevD29  - 前一个字的 D29 校验位（子帧首字为 0）
%     prevD30  - 前一个字的 D30 校验位（子帧首字为 0）
%   输出:
%     word30   - 1x30 完整字（24 数据位 + 6 校验位 D25..D30）
%     d29, d30 - 本字的 D29/D30（供下一个字使用）

data24 = double(data24(:).');
if numel(data24) ~= 24
    error('data24 必须为 24 位');
end
d = data24;
p29 = double(prevD29);
p30 = double(prevD30);

% ICD-GPS-200 §20.3.5.4 校验位参与数据位索引（D25..D30 依次）
parityTable = { ...
    [1 2 3 5 6 10 11 12 13 14 17 18 20 23], ...
    [2 3 4 6 7 11 12 13 14 15 18 19 21 24], ...
    [1 3 4 5 7 8 12 13 14 15 16 19 20 22], ...
    [2 4 5 6 8 9 13 14 15 16 17 20 21 23], ...
    [1 3 5 6 7 9 10 14 15 16 17 18 21 22 24], ...
    [3 5 6 8 9 10 11 13 15 19 22 23 24]};

% D25/D27/D30 用前字 D29；D26/D28/D29 用前字 D30
prevUse = [p29 p30 p29 p30 p30 p29];
par = zeros(1, 6);
for k = 1:6
    par(k) = xor(prevUse(k), mod(sum(d(parityTable{k})), 2));
end

word30 = [d, par];
d29 = par(5);
d30 = par(6);
end
