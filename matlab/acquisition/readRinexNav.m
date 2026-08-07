function nav = readRinexNav(filename)
%READRINEXNAV 解析 RINEX 2.x GPS 广播星历文件（NAV 电文，format 2.10/2.11）
%
%   nav = readRinexNav(filename)
%
%   输入:
%     filename - RINEX 2 GPS 导航文件路径（如 brdc2190.26n）
%   输出:
%     nav.header - 头文件信息：
%         .version / .type / .leapSeconds / .ionAlpha(4) / .ionBeta(4)
%         .utcA0 / .utcA1 / .utcT / .utcW
%     nav.gpsEph - 1xN 结构数组，每颗卫星的每次播发一条记录：
%         .PRN .TocEpoch(datenum) .Af0 .Af1 .Af2
%         .IODE .Crs .DeltaN .M0 .Cuc .Ecc .Cus .SqrtA
%         .Toe .Cic .Omega0 .Cis .i0 .Crc .omega .OmegaDot .IDOT
%         .CodesOnL2 .Week .L2PFlag .URA .SVHealth .TGD .IODC
%         .TransTime .FitInterval
%
%   说明:
%     - R2022b 的 rinexread 只支持 RINEX 3，本函数为 RINEX 2 经典 brdc
%       格式的自包含解析器（固定列宽，见 RINEX 2.11 规范）
%     - 角度/速率单位与 RINEX 一致（半周，semi-circle），直接对接
%       IS-GPS-200 自然单位，可原样填入 HelperGPSCEIConfig
%
%   参考: RINEX 2.11 格式规范（GPS NAV 记录：首行 + 7 行星历）

%% ---- 读文件（跳过空行，UTF-8/ASCII）----
fid = fopen(filename, 'r');
if fid < 0
    error('无法打开文件: %s', filename);
end
raw = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
fclose(fid);
lines = raw{1};
lines = lines(~cellfun(@isempty, strtrim(lines)));

%% ---- 头文件 ----
nav.header = struct();
nav.header.version = NaN;
nav.header.type = '';
nav.header.leapSeconds = NaN;
nav.header.ionAlpha = NaN(4,1);
nav.header.ionBeta  = NaN(4,1);
nav.header.utcA0 = NaN;
nav.header.utcA1 = NaN;
nav.header.utcT = NaN;
nav.header.utcW = NaN;

k = 1;
n = numel(lines);
while k <= n
    ln = lines{k};
    if numel(ln) >= 20 && contains(ln, 'RINEX VERSION / TYPE')
        nav.header.version = str2double(ln(1:9));
        nav.header.type = strtrim(ln(21:40));
    elseif contains(ln, 'LEAP SECONDS')
        v = sscanf(ln, '%d');
        if ~isempty(v), nav.header.leapSeconds = v(1); end
    elseif contains(ln, 'ION ALPHA')
        nav.header.ionAlpha = sscanf(ln, '%f', 4);
    elseif contains(ln, 'ION BETA')
        nav.header.ionBeta = sscanf(ln, '%f', 4);
    elseif contains(ln, 'DELTA-UTC')
        v = sscanf(ln, '%f', 4);
        if numel(v) == 4
            nav.header.utcA0 = v(1);
            nav.header.utcA1 = v(2);
            nav.header.utcT  = v(3);
            nav.header.utcW  = v(4);
        end
    elseif contains(ln, 'END OF HEADER')
        k = k + 1;
        break;
    end
    k = k + 1;
end

%% ---- 数据记录 ----
% 记录首行形如: " 5 26 08 07 00 00  0.0  af0  af1  af2"
%   I2,1X,5(I2,1X),F5.1,3X,3D19.12
% 后续 7 行星历: 3X,4D19.12（第 8 行 TransTime/FitInterval 可选）
isRecordStart = @(s) ~isempty(regexp(s, ...
    '^\s*\d{1,2}\s+\d{2}\s+\d{2}\s+\d{2}\s+\d{2}\s+\d{2}\s+', 'once'));

eph = struct('PRN', {}, 'TocEpoch', {}, 'Af0', {}, 'Af1', {}, 'Af2', {}, ...
    'IODE', {}, 'Crs', {}, 'DeltaN', {}, 'M0', {}, ...
    'Cuc', {}, 'Ecc', {}, 'Cus', {}, 'SqrtA', {}, ...
    'Toe', {}, 'Cic', {}, 'Omega0', {}, 'Cis', {}, ...
    'i0', {}, 'Crc', {}, 'omega', {}, 'OmegaDot', {}, 'IDOT', {}, ...
    'CodesOnL2', {}, 'Week', {}, 'L2PFlag', {}, ...
    'URA', {}, 'SVHealth', {}, 'TGD', {}, 'IODC', {}, ...
    'TransTime', {}, 'FitInterval', {});

idx = 0;
while k <= n
    ln = lines{k};
    if ~isRecordStart(ln)
        k = k + 1;
        continue;
    end

    % 首行
    v = sscanf(ln, '%d %d %d %d %d %d %f %f %f %f');
    if numel(v) < 9
        k = k + 1;
        continue;
    end
    prn = v(1);
    yy  = v(2); mm = v(3); dd = v(4); hh = v(5); mi = v(6); ss = v(7);
    if yy < 80, yy = 2000 + yy; else, yy = 1900 + yy; end

    idx = idx + 1;
    eph(idx).PRN = prn; %#ok<AGROW>
    eph(idx).TocEpoch = datenum(yy, mm, dd, hh, mi, ss); %#ok<AGROW>
    % 数值字段默认置 0（占位/未解析字段保持数值型，避免 [arr] 拼接丢元素）
    numFields = {'Af0','Af1','Af2','IODE','Crs','DeltaN','M0','Cuc','Ecc', ...
        'Cus','SqrtA','Toe','Cic','Omega0','Cis','i0','Crc','omega', ...
        'OmegaDot','IDOT','CodesOnL2','Week','L2PFlag','URA','SVHealth', ...
        'TGD','IODC','TransTime','FitInterval'};
    for f = 1:numel(numFields)
        eph(idx).(numFields{f}) = 0; %#ok<AGROW>
    end
    eph(idx).Af0 = v(8); %#ok<AGROW>
    eph(idx).Af1 = v(9); %#ok<AGROW>
    eph(idx).Af2 = v(10); %#ok<AGROW>

    % 后续 7~8 行星历（每行 4 个 D19.12 字段）
    vals = cell(1, 8);
    got  = zeros(1, 8);
    for j = 1:7
        k = k + 1;
        if k > n, break; end
        vv = sscanf(lines{k}, '%f %f %f %f');
        if numel(vv) < 4, j = j - 1; continue; end
        vals{j} = vv;
        got(j) = 1;
    end
    % 第 8 行（TransTime/FitInterval）：若下一行不是记录首行则消费
    if k + 1 <= n && ~isRecordStart(lines{k+1})
        vv = sscanf(lines{k+1}, '%f %f %f %f');
        if numel(vv) >= 2
            vals{8} = vv;
            got(8) = 1;
            k = k + 1;
        end
    end

    if got(1)
        eph(idx).IODE   = vals{1}(1);
        eph(idx).Crs    = vals{1}(2);
        eph(idx).DeltaN = vals{1}(3);
        eph(idx).M0     = vals{1}(4);
    end
    if got(2)
        eph(idx).Cuc    = vals{2}(1);
        eph(idx).Ecc    = vals{2}(2);
        eph(idx).Cus    = vals{2}(3);
        eph(idx).SqrtA  = vals{2}(4);
    end
    if got(3)
        eph(idx).Toe    = vals{3}(1);
        eph(idx).Cic    = vals{3}(2);
        eph(idx).Omega0 = vals{3}(3);
        eph(idx).Cis    = vals{3}(4);
    end
    if got(4)
        eph(idx).i0       = vals{4}(1);
        eph(idx).Crc      = vals{4}(2);
        eph(idx).omega    = vals{4}(3);
        eph(idx).OmegaDot = vals{4}(4);
    end
    if got(5)
        eph(idx).IDOT     = vals{5}(1);
        eph(idx).CodesOnL2= vals{5}(2);
        eph(idx).Week     = vals{5}(3);
        eph(idx).L2PFlag  = vals{5}(4);
    end
    if got(6)
        eph(idx).URA      = vals{6}(1);
        eph(idx).SVHealth = vals{6}(2);
        eph(idx).TGD      = vals{6}(3);
        eph(idx).IODC     = vals{6}(4);
    end
    if got(7)
        eph(idx).TransTime  = vals{7}(1);
        eph(idx).FitInterval= vals{7}(2);
    end
    k = k + 1;
end

nav.gpsEph = eph;
end
