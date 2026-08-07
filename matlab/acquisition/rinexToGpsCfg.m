function out = rinexToGpsCfg(nav, prn, varargin)
%RINEXTOGPSCFG 官方 RINEX 广播星历 → MathWorks HelperGPSNavigationConfig → LNAV 比特
%
%   out = rinexToGpsCfg(nav, prn)
%   out = rinexToGpsCfg(nav, prn, 'Tow', 80000)
%
%   输入:
%     nav - 星历来源，三种均可：
%           1) readRinexNav 输出（含 .gpsEph 结构数组，RINEX 2）
%           2) rinexread 输出（含 .GPS 表，RINEX 3，字段自动归一化）
%           3) 单条星历结构（须含 .PRN 与 RINEX 2 字段名）
%     prn - 待编码卫星 PRN
%   可选参数 (Name-Value):
%     'Tow'         - 子帧 1 的 HOW TOW（6 s 为单位，0..100799）；
%                     默认按所选记录历元 UTC+leap 换算 GPS 秒周并下取整到 6 s
%     'EpochIdx'    - 该 PRN 的记录序号（1=最早；默认最后一条）
%     'FrameIndices'- 编码帧数（默认 [1]，输出 1 帧 = 5 子帧 = 1500 位）
%
%   输出:
%     out.eph       - 选中的星历记录（自然单位，RINEX 2 字段名）
%     out.cfg       - HelperGPSNavigationConfig 对象（LNAV）
%     out.bits      - 1500 x 1 比特（官方 HelperGPSNAVDataEncode 输出）
%     out.subframes - 5 x 300 double，第 k 子帧 = subframes(k,:)
%     out.towBase   - 子帧 1 的 TOW
%     out.metas     - 每子帧一条参考结构（供 gnssSubframeDecode 对比）
%
%   说明:
%     - RINEX 角度单位为半周（semi-circle），与 IS-GPS-200 自然单位一致，
%       直接填入 HelperGPSCEIConfig，由官方编码器按 ICD 缩放因子量化
%     - HelperGPSNAVDataEncode 对 FrameIndices=[1] 输出 5 个子帧共 1500 位，
%       HOWTOW 每子帧自动 +1（6 s）
%     - 依赖 MathWorks 官方 Helper（R2022b 自带，需 addpath
%       D:\tools\matlab2022b\examples\satcom\main）

%% ---- 参数 ----
p = struct();
p.Tow          = [];
p.EpochIdx     = [];
p.FrameIndices = [1];
for k = 1:2:numel(varargin)
    key = varargin{k};
    val = varargin{k+1};
    switch lower(key)
        case 'tow',           p.Tow = val;
        case 'epochidx',      p.EpochIdx = val;
        case 'frameindices',  p.FrameIndices = val(:).';
        otherwise, error('未知参数: %s', key);
    end
end

%% ---- 归一化到单条星历（RINEX 2 字段名）----
eph = normalizeEph(nav, prn, p.EpochIdx);
if isempty(eph)
    error('RINEX 中未找到 PRN %d 的星历记录', prn);
end

%% ---- 头部辅助信息（电离层/UTC，供子帧 4/5）----
header = struct();
if isfield(nav, 'header')
    header = nav.header;
end

%% ---- 构造官方 CEI 配置 ----
cei = HelperGPSCEIConfig();
cei.SVHealth                    = eph.SVHealth;
cei.IssueOfDataClock            = eph.IODC;
cei.URAID                       = eph.URA;
cei.WeekNumber                  = eph.Week;
cei.GroupDelayDifferential      = eph.TGD;
cei.SVClockCorrectionCoefficients = [eph.Af0; eph.Af1; eph.Af2];
cei.ReferenceTimeOfClock        = tocSecondsOfWeek(eph, header);
cei.SemiMajorAxisLength         = eph.SqrtA^2;   % 编码器内部再开方（sqrtA）
cei.MeanMotionDifference        = eph.DeltaN;
cei.Eccentricity                = eph.Ecc;
cei.MeanAnomaly                 = eph.M0;
cei.ReferenceTimeOfEphemeris    = eph.Toe;
cei.HarmonicCorrectionTerms     = [eph.Cis; eph.Cic; eph.Crs; eph.Crc; eph.Cus; eph.Cuc];
cei.IssueOfDataEphemeris        = eph.IODE;
cei.ArgumentOfPerigee           = eph.omega;
cei.RateOfRightAscension        = eph.OmegaDot;
cei.LongitudeOfAscendingNode    = eph.Omega0;
cei.Inclination                 = eph.i0;
cei.InclinationRate             = eph.IDOT;
if isfinite(eph.FitInterval)
    cei.FitIntervalFlag = double(eph.FitInterval ~= 4);
else
    cei.FitIntervalFlag = 0;
end

%% ---- TOW ----
if isempty(p.Tow)
    towBase = floor(tocSecondsOfWeek(eph, header) / 6);
    towBase = mod(towBase, 100800);
else
    towBase = p.Tow;
end
if towBase < 0 || towBase > 100799
    error('TOW 越界: %d（须 0..100799）', towBase);
end

%% ---- 导航配置 + 官方编码 ----
cfg = HelperGPSNavigationConfig();
cfg.DataType      = "LNAV";
cfg.PRNID         = prn;
cfg.FrameIndices  = p.FrameIndices;
cfg.HOWTOW        = towBase;
cfg.TLMMessage    = 0;
if eph.CodesOnL2 == 0
    cfg.CodesOnL2 = "C/A-code";
else
    cfg.CodesOnL2 = "P-code";
end
cfg.L2PDataFlag   = eph.L2PFlag;
cfg.CEIDataSet    = cei;
if isfield(header, 'ionAlpha') && all(isfinite(header.ionAlpha))
    cfg.Ionosphere.Alpha = header.ionAlpha(:);
    cfg.Ionosphere.Beta  = header.ionBeta(:);
end
if isfield(header, 'utcA0') && isfinite(header.utcA0)
    cfg.UTC.UTCTimeCoefficients = [header.utcA0; header.utcA1; 0];
    cfg.UTC.ReferenceTimeUTCData = header.utcT;
    cfg.UTC.TimeDataReferenceWeekNumber = header.utcW;
    if isfinite(header.leapSeconds)
        cfg.UTC.PastLeapSecondCount = header.leapSeconds;
        cfg.UTC.LeapSecondReferenceWeekNumber = header.utcW;
        cfg.UTC.FutureLeapSecondCount = header.leapSeconds;
    end
end

bits = HelperGPSNAVDataEncode(cfg);   % 列向量 1500x1
subframes = reshape(bits, 300, 5).';   % 5x300，第 k 子帧一行

%% ---- 参考元数据（供 gnssSubframeDecode 端到端对比）----
% 注意：发送字含 ICD D30 位反转，须先还原成逻辑数据再提取字段，
% 与 gnssSubframeDecode 的解析口径一致
metas = struct('tow', {}, 'subframeId', {}, 'tlmMsg', {}, ...
    'dataWords', {}, 'bits300', {}, 'preamble', {});
for k = 1:5
    sf  = bits((k-1)*300 + 1 : k*300);
    w   = reshape(sf, 30, 10).';
    logWords = zeros(10, 24);
    prevD30 = 0;
    for wi = 1:10
        logWords(wi, :) = mod(w(wi, 1:24) + prevD30, 2);
        prevD30 = w(wi, 30);
    end
    metas(k).tow        = bi2de(logWords(2, 1:17), 'left-msb');
    metas(k).subframeId = bi2de(logWords(2, 20:22), 'left-msb');
    metas(k).tlmMsg     = logWords(1, 9:14);
    metas(k).dataWords  = logWords(3:10, :);
    metas(k).bits300    = sf.';
    metas(k).preamble   = w(1, 1:8);   % 字 1 无反转，前导码即发送值
end

%% ---- 输出 ----
out = struct();
out.eph       = eph;
out.cfg       = cfg;
out.bits      = bits;
out.subframes = subframes;
out.towBase   = towBase;
out.metas     = metas;
end

%% ---- 局部函数：归一化星历 ----
function eph = normalizeEph(nav, prn, epochIdx)
if isfield(nav, 'GPS') && (istable(nav.GPS) || istimetable(nav.GPS))
    % rinexread（RINEX 3）输出：GPS 表（timetable）
    T = nav.GPS;
    rows = find(T.SatelliteID == prn);
    if isempty(rows), eph = []; return; end
    if ~isempty(epochIdx)
        rows = rows(min(epochIdx, numel(rows)));
    else
        rows = rows(end);
    end
    r = T(rows, :);
    eph = struct();
    eph.PRN = r.SatelliteID;
    eph.Af0 = r.SVClockBias;      eph.Af1 = r.SVClockDrift;
    eph.Af2 = r.SVClockDriftRate;
    eph.IODE = r.IODE;            eph.Crs = r.Crs;
    eph.DeltaN = r.Delta_n;       eph.M0 = r.M0;
    eph.Cuc = r.Cuc;              eph.Ecc = r.Eccentricity;
    eph.Cus = r.Cus;              eph.SqrtA = r.sqrtA;
    eph.Toe = r.Toe;              eph.Cic = r.Cic;
    eph.Omega0 = r.OMEGA0;        eph.Cis = r.Cis;
    eph.i0 = r.i0;                eph.Crc = r.Crc;
    eph.omega = r.omega;          eph.OmegaDot = r.OMEGA_DOT;
    eph.IDOT = r.IDOT;
    eph.CodesOnL2 = r.L2ChannelCodes;
    eph.Week = r.GPSWeek;         eph.L2PFlag = r.L2PDataFlag;
    eph.URA = r.SVAccuracy;       eph.SVHealth = r.SVHealth;
    eph.TGD = r.TGD;              eph.IODC = r.IODC;
    eph.TransTime = r.TransmissionTime;
    eph.FitInterval = r.FitInterval;
    try
        eph.TocEpoch = datenum(T.Time(rows));
    catch
        eph.TocEpoch = NaN;
    end
elseif isfield(nav, 'gpsEph')
    rows = find([nav.gpsEph.PRN] == prn);
    if isempty(rows), eph = []; return; end
    if isempty(epochIdx)
        % 默认取最新且轨道有效的记录（真实 RINEX 含零占位星历，
        % 如 SVHealth=63 的空白记录，须跳过）
        sq = arrayfun(@(e) e.SqrtA, nav.gpsEph(rows));
        te = arrayfun(@(e) e.Toe, nav.gpsEph(rows));
        valid = rows(sq > 1e3 & te > 0);
        if ~isempty(valid), rows = valid(end); else, rows = rows(end); end
    else
        rows = rows(min(epochIdx, numel(rows)));
    end
    eph = nav.gpsEph(rows);
elseif isfield(nav, 'PRN')
    eph = nav;
else
    error('无法识别的星历输入（需要 .gpsEph / .GPS / .PRN 字段）');
end
end

%% ---- 局部函数：toc 秒周 ----
function tocSow = tocSecondsOfWeek(eph, header)
leap = 0;
if isfield(header, 'leapSeconds') && isfinite(header.leapSeconds)
    leap = header.leapSeconds;
end
if isfield(eph, 'TocEpoch') && isfinite(eph.TocEpoch)
    gpsEpoch = datenum(1980, 1, 6);
    tocSow = mod((eph.TocEpoch - gpsEpoch) * 86400 + leap, 604800);
else
    tocSow = eph.Toe;   % 回退：用 Toe 近似（仅当无历元信息）
end
end
