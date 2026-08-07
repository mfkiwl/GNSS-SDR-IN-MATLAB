function results = verifyGnssPositioning(varargin)
%VERIFYGNSSPOSITIONING M4.2 多星 TX → 伪距 → 最小二乘定位验证
%
%   原理:
%     以真实 GPS 星座几何为基准：取官方 RINEX 星历在统一发射时刻 T_sf
%     计算 N 颗卫星的 ECEF 位置，以已知参考点 X0（WGS84）到各星的真实
%     距离为伪距，按 ρ = c·delay/fs 折算成码延迟注入多星 TX 缓冲。
%     接收端（Synthetic 闭环）多通道捕获/跟踪 → 子帧同步 → 星历解析 →
%     由 TOW + 码相位重构伪距 → 最小二乘解 X_est。若整条链路正确，
%     X_est 应回到 X0（误差 < 300 m）。
%
%   用法:
%     verifyGnssPositioning
%     verifyGnssPositioning('NumSats', 6, 'RefLat', 31.2304, 'RefLon', 121.4737)
%
%   参数: 'NumSats'(默认 6) / 'RefLat' / 'RefLon' / 'RefH'(默认 0) /
%         'RinexFile' / 'CaptureSec'(默认 28：有效比特 >=1199 才保证任意
%           对齐含完整子帧 1) / 'CN0'(默认 42) /
%         'Fs' / 'PllBandwidth' / 'DllBandwidth' / 'CorrSpacing'

p = struct();
p.NumSats     = 6;
p.RefLat      = 31.2304;      % 上海市中心（WGS84）
p.RefLon      = 121.4737;
p.RefH        = 0;
p.RinexFile   = fullfile(fileparts(mfilename('fullpath')), 'data', 'auto2190.26n');
p.CaptureSec  = 28;
p.CN0         = 42;
p.Fs          = 2.5e6;
p.PllBandwidth = 18;
p.DllBandwidth = 2;
p.CorrSpacing  = 0.5;

for k = 1:2:numel(varargin)
    key = varargin{k};
    val = varargin{k+1};
    switch lower(key)
        case 'numsats',      p.NumSats = val;
        case 'reflat',       p.RefLat = val;
        case 'reflon',       p.RefLon = val;
        case 'refh',         p.RefH = val;
        case 'rinexfile',    p.RinexFile = val;
        case 'capturesec',   p.CaptureSec = val;
        case 'cn0',          p.CN0 = val;
        case 'fs',           p.Fs = val;
        case 'pllbandwidth', p.PllBandwidth = val;
        case 'dllbandwidth', p.DllBandwidth = val;
        case 'corrspacing',  p.CorrSpacing = val;
        otherwise, error('未知参数: %s', key);
    end
end

c = 299792458;
results = struct();
results.params = p;
results.pass = false;

try
    fprintf('==========================================================\n');
    fprintf(' M4.2 多星定位验证：注入真实星座伪距 → 最小二乘解参考点\n');
    fprintf('==========================================================\n');

    %% ---- 1. 参考点 + 星历源 ----
    X0 = geodetic2Ecef(p.RefLat, p.RefLon, p.RefH);
    fprintf('[REF] 参考点 WGS84 (%.5f, %.5f, %.1f m) → ECEF %s\n', ...
        p.RefLat, p.RefLon, p.RefH, mat2str(X0', 6));
    nav = readRinexNav(p.RinexFile);

    %% ---- 2. 统一发射时刻 + 选星（距 T_sf 2h 内、仰角 > 15°）----
    prnsAll = unique([nav.gpsEph.PRN]);
    % 用最新记录历元定 T_sf（6 s 量化），保证各星最新记录在拟合区间内
    sowAll = arrayfun(@(e) mod((e.TocEpoch - datenum(1980,1,6))*86400, 604800), ...
        nav.gpsEph);
    tow = floor(max(sowAll) / 6);
    T_sf = (tow - 1) * 6;      % 子帧 1 起点 GPS 秒周
    fprintf('[EPOCH] 统一 T_sf = %d s（TOW 基准 %d，week %d）\n', ...
        T_sf, tow, nav.gpsEph(1).Week);

    cand = struct('prn', {}, 'eph', {}, 'pos', {}, 'elev', {});
    for prn = prnsAll
        rows = find([nav.gpsEph.PRN] == prn);
        sq = arrayfun(@(e) e.SqrtA, nav.gpsEph(rows));
        te = arrayfun(@(e) e.Toe, nav.gpsEph(rows));
        v = rows(sq > 1e3 & te > 0);
        if isempty(v), continue; end
        e = nav.gpsEph(v(end));
        if abs(e.Toe - T_sf) > 7200, continue; end   % 2h 拟合区间
        ep = ephFromRecord(e);
        try
            pos = satellitePosition(ep, T_sf);
            los = pos - X0;
            elev = asin(los.' * upVec(X0) / norm(los));
            if rad2deg(elev) > 15
                cand(end+1) = struct('prn', prn, 'eph', ep, 'pos', pos, ...
                    'elev', rad2deg(elev)); %#ok<AGROW>
            end
        catch
        end
    end
    if numel(cand) < p.NumSats
        error('候选卫星不足：%d < %d（检查 T_sf 拟合区间与仰角）', ...
            numel(cand), p.NumSats);
    end
    % 按仰角取前 NumSats（保证几何分布）
    [~, si] = sort([cand.elev], 'descend');
    cand = cand(si(1:p.NumSats));
    prns = [cand.prn];
    fprintf('[SATS] 选用 %d 颗：%s\n', numel(prns), mat2str(prns));

    %% ---- 3. 注入伪距（真实几何）+ 编码每星子帧 1-3 ----
    delays = zeros(1, p.NumSats);
    navbits = cell(1, p.NumSats);
    for i = 1:p.NumSats
        rng_i = norm(cand(i).pos - X0);
        delays(i) = round(rng_i * p.Fs / c);       % 采样点
        out = rinexToGpsCfg(nav, prns(i), 'Tow', tow);
        navbits{i} = [out.subframes(1,:), out.subframes(2,:), out.subframes(3,:)];
        fprintf('  PRN %2d: 真实距离 %.1f km → 延迟 %d 采样 (%.2f ms)\n', ...
            prns(i), rng_i/1e3, delays(i), delays(i)/p.Fs*1e3);
    end
    results.injected = struct('prns', prns, 'delays', delays, 'T_sf', T_sf, ...
        'satPos', [cand.pos], 'X0', X0);

    %% ---- 4. 多星 TX 缓冲 + 合成信号 ----
    fprintf('[TX] 生成 %d 星叠加缓冲（900 位 = 18 s）...\n', p.NumSats);
    buf = generateMultiSatTxBuffer(prns, p.Fs, ...
        'DelaysSamples', delays, 'NavBitsList', navbits, ...
        'Amplitudes', 0.3*ones(1, p.NumSats));
    fprintf('  缓冲 %d 采样（%.1f s），峰值 %.3f\n', numel(buf), ...
        numel(buf)/p.Fs, max(abs(buf)));

    nSamp = round(p.Fs * p.CaptureSec);
    nRep = ceil(nSamp / numel(buf));
    data0 = repmat(buf, nRep, 1);
    data0 = data0(1:nSamp);
    A_sat = 1 / p.NumSats;                        % 归一化后单星峰值近似
    sigma = A_sat * sqrt(p.Fs / 10^(p.CN0/10));
    rng(20260807);
    noise = (randn(nSamp,1) + 1j*randn(nSamp,1)) * sigma/sqrt(2);
    data = data0 + noise;
    fprintf('[SYN] %.1f s 信号，目标单星 C/N0=%d dB-Hz（σ=%.3e）\n', ...
        nSamp/p.Fs, p.CN0, sigma);
    clear buf data0;

    %% ---- 5. 多通道捕获 + 跟踪 ----
    fprintf('[ACQ] 捕获 ...\n');
    acq = acquisition(data, p.Fs, 'Verbose', false, ...
        'IntegrationMs', 5, 'NonCoherentN', 10, 'DopplerStep', 100);
    det = [acq.results.PRN];
    det = det([acq.results.detected]);
    miss = setdiff(prns, det);
    fprintf('  检测到 %d 颗：%s%s\n', numel(det), mat2str(det), ...
        ternaryStr(isempty(miss), '', ['，未检出: ' mat2str(miss)]));
    results.acq = acq;
    if ~isempty(miss), error('捕获漏星: %s', mat2str(miss)); end

    fprintf('[TRK] DLL+PLL 多通道跟踪 ...\n');
    trk = tracking(data, p.Fs, acq, 'PRNList', prns, ...
        'PllBandwidth', p.PllBandwidth, 'DllBandwidth', p.DllBandwidth, ...
        'CorrSpacing', p.CorrSpacing);
    results.trk = trk;

    %% ---- 6. 每星：子帧解码 → 星历 → 卫星位置 → 伪距 ----
    rho = zeros(1, p.NumSats);
    satPosRx = zeros(3, p.NumSats);
    eCodeAll = zeros(1, p.NumSats);
    for i = 1:p.NumSats
        t1 = trk(i);
        dec = gnssSubframeDecode(t1.bits);
        if isempty(dec.syncIndex)
            error('PRN %d 未解出子帧', prns(i));
        end
        % 统一锚定子帧 1（TOW 基准一致，避免不同子帧发射时刻差异）
        sf1idx = find([dec.subframes.subframeId] == 1, 1);
        if isempty(sf1idx)
            error('PRN %d 未解出子帧 1（须含完整子帧 1 组）', prns(i));
        end
        sf  = dec.subframes(sf1idx);
        [rho(i), eCode] = gnssPseudorange(t1, sf, dec.syncIndex(sf1idx), p.Fs);
        eCodeAll(i) = eCode;
        ep = gnssEphDecode(dec.subframes);
        satPosRx(:, i) = satellitePosition(ep, (sf.tow - 1)*6);
        fprintf('  PRN %2d: 子帧 TOW=%d 锚定采样=%d 伪距=%.3f km\n', ...
            prns(i), sf.tow, eCode, rho(i)/1e3);
    end
    % 所有星须锚定在同一 18 s 重复周期内（伪距时标一致性）
    if max(eCodeAll) - min(eCodeAll) > 18e3 * p.Fs
        error('卫星锚定跨 18 s 重复周期，伪距时标不一致');
    end
    results.rho = rho;
    results.satPosRx = satPosRx;

    %% ---- 7. 最小二乘定位 ----
    [posEst, bias, gdop, res] = leastSquaresPosition(rho(:), satPosRx, [0;0;0]);
    [latEst, lonEst, hEst] = ecef2Geodetic(posEst);
    dPos = norm(posEst - X0);
    fprintf('\n[LS] 解算位置 ECEF %s\n', mat2str(posEst', 6));
    fprintf('     WGS84 (%.6f, %.6f, %.1f m)，与参考点误差 %.1f m\n', ...
        latEst, lonEst, hEst, dPos);
    fprintf('     钟差等效距离 %.3f km，GDOP %.2f，伪距残差 RMS %.1f m\n', ...
        bias/1e3, gdop, rms(res));

    %% ---- 8. 伪距一致性自检（相对注入延迟）----
    rhoRel = rho - mean(rho);
    injRel = c*delays/p.Fs - mean(c*delays/p.Fs);
    dRho = max(abs(rhoRel - injRel));
    fprintf('[CHK] 伪距相对差 vs 注入延迟：最大偏差 %.1f m\n', dRho);

    %% ---- 9. 判定 ----
    posOK = dPos < 300;
    rhoOK = dRho < 500;
    gdopOK = gdop < 15;
    resOK = rms(res) < 300;
    results.metrics = struct('dPos', dPos, 'lat', latEst, 'lon', lonEst, ...
        'h', hEst, 'gdop', gdop, 'resRms', rms(res), 'dRho', dRho, ...
        'posOK', posOK, 'rhoOK', rhoOK, 'gdopOK', gdopOK, 'resOK', resOK);
    results.posEst = posEst;
    results.pass = posOK && rhoOK && gdopOK && resOK;

    fprintf('\n==========================================================\n');
    fprintf(' 结论: %s（位置误差 %.0f m 门限300 | 伪距一致 %.0f m 门限500 | GDOP %.1f 门限15 | 残差 %.0f m 门限300）\n', ...
        passStr(results.pass), dPos, dRho, gdop, rms(res));
    fprintf('==========================================================\n');

catch err
    fprintf('\n[验证中断]: %s\n', err.message);
    results.error = err.message;
    results.pass = false;
end

%% ---- 保存 ----
try
    outDir = fullfile(fileparts(mfilename('fullpath')), 'data');
    if ~exist(outDir, 'dir'), mkdir(outDir); end
    ts = datestr(now, 'yyyymmdd_HHMMSS');
    matFile = fullfile(outDir, ['gnss_positioning_' ts '.mat']);
    save(matFile, 'results');
    results.matFile = matFile;
    fprintf('结果已保存: %s\n', matFile);
catch e
    fprintf('保存跳过: %s\n', e.message);
end
end

%% ---- 工具 ----
function X = geodetic2Ecef(lat, lon, h)
a = 6378137.0;
f = 1/298.257223563;
e2 = f*(2-f);
phi = deg2rad(lat); lam = deg2rad(lon);
N = a / sqrt(1 - e2*sin(phi)^2);
X = [(N+h)*cos(phi)*cos(lam); (N+h)*cos(phi)*sin(lam); (N*(1-e2)+h)*sin(phi)];
end

function [lat, lon, h] = ecef2Geodetic(X)
a = 6378137.0;
f = 1/298.257223563;
e2 = f*(2-f);
x = X(1); y = X(2); z = X(3);
lon = atan2(y, x);
pp = sqrt(x^2 + y^2);
phi = atan2(z, pp*(1-e2));
for it = 1:6
    N = a / sqrt(1 - e2*sin(phi)^2);
    h = pp/cos(phi) - N;
    phi = atan2(z, pp*(1 - e2*N/(N+h)));
end
lat = rad2deg(phi);
lon = rad2deg(lon);
end

function u = upVec(X)
% 接收机位置处的天顶单位向量（ENU 的 U）
[lat, lon] = ecef2Geodetic(X);
phi = deg2rad(lat); lam = deg2rad(lon);
u = [cos(phi)*cos(lam); cos(phi)*sin(lam); sin(phi)];
end

function ep = ephFromRecord(e)
% RINEX 记录 → satellitePosition 兼容结构
ep.SqrtA = e.SqrtA;   ep.DeltaN = e.DeltaN; ep.M0 = e.M0;
ep.Ecc = e.Ecc;       ep.omega = e.omega;
ep.Cuc = e.Cuc;       ep.Cus = e.Cus;
ep.Crc = e.Crc;       ep.Crs = e.Crs;
ep.i0 = e.i0;         ep.IDOT = e.IDOT;
ep.Cic = e.Cic;       ep.Cis = e.Cis;
ep.Omega0 = e.Omega0; ep.OmegaDot = e.OmegaDot;
ep.Toe = e.Toe;       ep.Toc = e.Toe;
ep.Af0 = 0; ep.Af1 = 0; ep.Af2 = 0;
end

function s = passStr(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end

function s = ternaryStr(c, a, b)
if c, s = a; else, s = b; end
end
