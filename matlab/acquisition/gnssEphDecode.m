function eph = gnssEphDecode(sfList)
%GNSSEPHDECODE 从已同步的 GPS 子帧（1/2/3）提取完整广播星历
%
%   eph = gnssEphDecode(sfList)
%
%   输入:
%     sfList - gnssSubframeDecode 输出的子帧结构数组（含 .subframeId /
%              .dataWords(8x24 逻辑位) / .tow）；内部取每个子帧号首次出现
%   输出:
%     eph - 星历结构（RINEX 2 风格字段名，便于与官方数据对比）：
%         .Week .Tow .URA .SVHealth .IODC .TGD .Toc
%         .Af0 .Af1 .Af2
%         .IODE .Crs .DeltaN .M0 .Cuc .Ecc .Cus .SqrtA
%         .Toe .Cic .Omega0 .Cis .i0 .Crc .omega .OmegaDot .IDOT
%         .FitIntervalFlag .AgeOfDataOffset
%         角度/速率为半周（semi-circle），与 RINEX/IS-GPS-200 自然单位一致
%
%   说明:
%     - 位宽/缩放/有符号性与 MathWorks 官方 HelperGPSLNAVDataDecode
%       完全一致（Ecc/sqrtA/Toe/Toc 无符号，其余有符号二补码）
%     - 要求子帧 1/2/3 齐全；缺失时对应字段返回 NaN

sf1 = pickSf(sfList, 1);
sf2 = pickSf(sfList, 2);
sf3 = pickSf(sfList, 3);

eph = struct();
eph.Week = NaN; eph.Tow = NaN; eph.URA = NaN; eph.SVHealth = NaN;
eph.IODC = NaN; eph.TGD = NaN; eph.Toc = NaN;
eph.Af0 = NaN; eph.Af1 = NaN; eph.Af2 = NaN;
eph.IODE = NaN; eph.Crs = NaN; eph.DeltaN = NaN; eph.M0 = NaN;
eph.Cuc = NaN; eph.Ecc = NaN; eph.Cus = NaN; eph.SqrtA = NaN;
eph.Toe = NaN; eph.Cic = NaN; eph.Omega0 = NaN; eph.Cis = NaN;
eph.i0 = NaN; eph.Crc = NaN; eph.omega = NaN; eph.OmegaDot = NaN;
eph.IDOT = NaN; eph.FitIntervalFlag = NaN; eph.AgeOfDataOffset = NaN;

%% ---- 子帧 1：时钟/完好性 ----
if ~isempty(sf1)
    w = sf1.dataWords;   % 8x24，行 = 数据字 3..10
    eph.Week      = bits2num(w(1, 1:10), false);
    eph.URA       = bits2num(w(1, 13:16), false);
    eph.SVHealth  = bits2num(w(1, 17:22), false);
    eph.IODC      = bits2num([w(1, 23:24), w(6, 1:8)], false);
    eph.TGD       = bits2num(w(5, 17:24), true) * 2^-31;
    eph.Toc       = bits2num(w(6, 9:24), false) * 16;
    eph.Af2       = bits2num(w(7, 1:8),  true) * 2^-55;
    eph.Af1       = bits2num(w(7, 9:24), true) * 2^-43;
    eph.Af0       = bits2num(w(8, 1:22), true) * 2^-31;
    eph.Tow       = sf1.tow;
end

%% ---- 子帧 2：轨道根数（上）----
if ~isempty(sf2)
    w = sf2.dataWords;
    eph.IODE     = bits2num(w(1, 1:8), false);
    eph.Crs      = bits2num(w(1, 9:24), true) * 2^-5;
    eph.DeltaN   = bits2num(w(2, 1:16), true) * 2^-43;
    eph.M0       = bits2num([w(2, 17:24), w(3, 1:24)], true) * 2^-31;
    eph.Cuc      = bits2num(w(4, 1:16), true) * 2^-29;
    eph.Ecc      = bits2num([w(4, 17:24), w(5, 1:24)], false) * 2^-33;
    eph.Cus      = bits2num(w(6, 1:16), true) * 2^-29;
    eph.SqrtA    = bits2num([w(6, 17:24), w(7, 1:24)], false) * 2^-19;
    eph.Toe      = bits2num(w(8, 1:16), false) * 16;
    eph.FitIntervalFlag = w(8, 17);
    eph.AgeOfDataOffset = bits2num(w(8, 18:22), false) * 900;
end

%% ---- 子帧 3：轨道根数（下）----
if ~isempty(sf3)
    w = sf3.dataWords;
    eph.Cic      = bits2num(w(1, 1:16), true) * 2^-29;
    eph.Omega0   = bits2num([w(1, 17:24), w(2, 1:24)], true) * 2^-31;
    eph.Cis      = bits2num(w(3, 1:16), true) * 2^-29;
    eph.i0       = bits2num([w(3, 17:24), w(4, 1:24)], true) * 2^-31;
    eph.Crc      = bits2num(w(5, 1:16), true) * 2^-5;
    eph.omega    = bits2num([w(5, 17:24), w(6, 1:24)], true) * 2^-31;
    eph.OmegaDot = bits2num(w(7, 1:24), true) * 2^-43;
    if isnan(eph.IODE)
        eph.IODE = bits2num(w(8, 1:8), false);
    end
    eph.IDOT     = bits2num(w(8, 9:22), true) * 2^-43;
end
end

%% ---- 取指定子帧号的首次出现 ----
function sf = pickSf(sfList, id)
idx = find([sfList.subframeId] == id, 1);
if isempty(idx)
    sf = [];
else
    sf = sfList(idx);
end
end

%% ---- 比特 → 整数（MSB 左，可选二补码）----
function v = bits2num(bits, isSigned)
bits = double(bits(:).');
n = numel(bits);
v = bi2de(bits, 'left-msb');
if isSigned && v >= 2^(n-1)
    v = v - 2^n;
end
end
