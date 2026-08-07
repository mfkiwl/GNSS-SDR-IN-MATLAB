function results = verifyGnssEphDecode(varargin)
%VERIFYGNSSEPHDECODE M4 星历解析验证：子帧比特 → 星历字段 → 卫星位置
%
%   阶段 A（快速，确定性）：
%     官方 RINEX → 官方编码（rinexToGpsCfg）→ gnssSubframeDecode →
%     gnssEphDecode → 与 RINEX 源值逐字段对比（量化容差 + 字段回绕）
%     + satellitePosition 合理性（轨道半径 / 60 s 位移）
%   阶段 B（完整合成闭环，默认开）：
%     TX 900 位官方子帧1-3 → 注入多普勒/码相位/噪声 → 捕获 → DLL/PLL
%     跟踪 → 解调 → gnssSubframeDecode → gnssEphDecode → 同上对比
%
%   用法:
%     verifyGnssEphDecode                 % A + B（Synthetic）
%     verifyGnssEphDecode('FullLoop', false)   % 仅阶段 A
%     verifyGnssEphDecode('PRN', 2)
%
%   参数: 'PRN' / 'RinexFile' / 'FullLoop' / 'CaptureSec'(默认 24，保证
%          任意位对齐下含完整子帧 1/2/3 组) / 'SyntheticDopplerHz' ...

p = struct();
p.PRN         = 5;
p.RinexFile   = fullfile(fileparts(mfilename('fullpath')), 'data', 'auto2190.26n');
p.FullLoop    = true;
p.Fs          = 2.5e6;
p.CaptureSec  = 24;
p.SyntheticDopplerHz = 1200;
p.SyntheticCodePhase = 777;
p.SyntheticCN0       = 45;
p.PllBandwidth = 18;
p.DllBandwidth = 2;
p.CorrSpacing  = 0.5;

for k = 1:2:numel(varargin)
    key = varargin{k};
    val = varargin{k+1};
    switch lower(key)
        case 'prn',              p.PRN = val;
        case 'rinexfile',        p.RinexFile = val;
        case 'fullloop',         p.FullLoop = val;
        case 'fs',               p.Fs = val;
        case 'capturesec',       p.CaptureSec = val;
        case 'syntheticdopplerhz', p.SyntheticDopplerHz = val;
        case 'syntheticcodephase', p.SyntheticCodePhase = val;
        case 'syntheticcn0',     p.SyntheticCN0 = val;
        case 'pllbandwidth',     p.PllBandwidth = val;
        case 'dllbandwidth',     p.DllBandwidth = val;
        case 'corrspacing',      p.CorrSpacing = val;
        otherwise, error('未知参数: %s', key);
    end
end

results = struct();
results.params = p;
results.pass = false;

try
    fprintf('==========================================================\n');
    fprintf(' M4 星历解析验证：子帧比特 → 星历字段 → 卫星位置\n');
    fprintf('==========================================================\n');

    %% ---- 源：官方 RINEX + 官方编码 ----
    fprintf('[SRC] 解析 %s ...\n', p.RinexFile);
    nav = readRinexNav(p.RinexFile);
    prnList = unique([nav.gpsEph.PRN]);
    if ~any(prnList == p.PRN)
        p.PRN = prnList(1);
        fprintf('  PRN 5 无记录，改用 PRN %d\n', p.PRN);
    end
    out = rinexToGpsCfg(nav, p.PRN);
    results.out = out;
    fprintf('  PRN %d 官方编码完成，TOW 基准 %d\n', p.PRN, out.towBase);
    srcRef = out.eph;
    srcRef.Toc = out.cfg.CEIDataSet.ReferenceTimeOfClock;   % 周内秒（源）

    %% ---- 阶段 A：直接解码官方比特 ----
    fprintf('[STAGE A] 官方比特 → gnssEphDecode ...\n');
    decA = gnssSubframeDecode([out.subframes(1,:), out.subframes(2,:), ...
        out.subframes(3,:)]);
    ephA = gnssEphDecode(decA.subframes);
    results.stageA = compareEph(ephA, srcRef);
    printEphCompare('A', results.stageA, ephA);

    % 星座几何统计验证（32 PRN 官方星历 → 同一时刻卫星位置）
    cons = constellationCheck(nav);
    results.constellation = cons;
    fprintf('  [CONST] %d 星半径 %.4e±%.1e m (%s)，整周期对径比 %.4f±%.4f (%s)\n', ...
        cons.nUsed, cons.rMean, cons.rStd, passStr(cons.rOK), ...
        cons.periodMean, cons.periodStd, passStr(cons.periodOK));

    %% ---- 阶段 B：完整合成闭环 ----
    if p.FullLoop
        fprintf('[STAGE B] 合成闭环：TX 900 位 → 捕获 → 跟踪 → 解码 ...\n');
        sfBits = [out.subframes(1,:), out.subframes(2,:), out.subframes(3,:)];
        buf = generateGnssTxBuffer(p.PRN, p.Fs, 'Amplitude', 0.3, ...
            'NavBits', sfBits);
        nSamp = round(p.Fs * p.CaptureSec);
        nRep = ceil(nSamp / numel(buf));
        data0 = repmat(buf, nRep, 1);
        data0 = data0(1:nSamp);
        data0 = circshift(data0, mod(p.SyntheticCodePhase, numel(data0)));
        tAll = (0:nSamp-1).';
        data0 = data0 .* exp(1j*2*pi*p.SyntheticDopplerHz*tAll/p.Fs);
        sigma = 0.3 * sqrt(p.Fs / 10^(p.SyntheticCN0/10));
        rng(20260807);
        noise = (randn(nSamp,1) + 1j*randn(nSamp,1)) * sigma/sqrt(2);
        data = data0 + noise;
        fprintf('  合成信号 %.1f s（%d 采样）\n', nSamp/p.Fs, nSamp);

        acq = acquisition(data, p.Fs, 'Verbose', false, ...
            'IntegrationMs', 5, 'NonCoherentN', 10, 'DopplerStep', 100);
        r1 = acq.results([acq.results.PRN] == p.PRN);
        others = [acq.results.metric];
        others([acq.results.PRN] == p.PRN) = -inf;
        dom = r1.metric / max(max(others), eps);
        fprintf('  捕获: metric=%.1f doppler=%+.1f Hz 领先度=%.1f\n', ...
            r1.metric, r1.dopplerHz, dom);
        results.acq = acq;

        trk = tracking(data, p.Fs, acq, 'PRNList', p.PRN, ...
            'PllBandwidth', p.PllBandwidth, 'DllBandwidth', p.DllBandwidth, ...
            'CorrSpacing', p.CorrSpacing, 'ReferenceBits', sfBits);
        t1 = trk(1);
        results.trk = t1;
        nW = min(50, numel(t1.CN0dBHz));
        fprintf('  跟踪: lock=%d CN0=%.1f dB-Hz 误码=%d/%d\n', t1.lock, ...
            median(t1.CN0dBHz(end-nW+1:end)), t1.numErrors, numel(t1.bits));

        decB = gnssSubframeDecode(t1.bits);
        ephB = gnssEphDecode(decB.subframes);
        results.stageB = compareEph(ephB, srcRef);
        printEphCompare('B', results.stageB, ephB);
    else
        results.stageB = [];
    end

    %% ---- 判定 ----
    sA = results.stageA;
    passA = sA.nFieldsOK == sA.nFields && sA.posOK && sA.moveOK && ...
        cons.rOK && cons.periodOK;
    if p.FullLoop
        sB = results.stageB;
        passB = sB.nFieldsOK == sB.nFields && sB.posOK && sB.moveOK;
        results.pass = passA && passB && results.trk.lock && ...
            results.trk.numErrors == 0 && sB.nFields >= 24;
    else
        results.pass = passA;
    end

    fprintf('\n==========================================================\n');
    fprintf(' 结论: %s（A: 字段 %d/%d 位置=%d 位移=%d 星座=%d', ...
        passStr(results.pass), sA.nFieldsOK, sA.nFields, sA.posOK, sA.moveOK, ...
        cons.rOK && cons.periodOK);
    if p.FullLoop
        sB = results.stageB;
        fprintf('；B: 字段 %d/%d 位置=%d 位移=%d', ...
            sB.nFieldsOK, sB.nFields, sB.posOK, sB.moveOK);
    end
    fprintf('）\n');
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
    matFile = fullfile(outDir, ['gnss_eph_decode_' ts '.mat']);
    save(matFile, 'results');
    results.matFile = matFile;
    fprintf('结果已保存: %s\n', matFile);
catch e
    fprintf('保存跳过: %s\n', e.message);
end
end

%% ---- 星历字段对比（量化容差 + 字段回绕）----
function st = compareEph(eph, src)
st = struct();
st.nFields = 0;
st.nFieldsOK = 0;
st.bad = {};
st.posOK = false;
st.moveOK = false;
st.r = NaN;
st.dr60 = NaN;

checks = struct('name', {}, 'got', {}, 'exp', {}, 'tol', {}, 'wrap', {});

% 子帧 1
checks(end+1) = struct('name','Week','got',eph.Week,'exp',mod(src.Week,1024),'tol',0,'wrap',0);
checks(end+1) = struct('name','URA','got',eph.URA,'exp',src.URA,'tol',0,'wrap',0);
checks(end+1) = struct('name','SVHealth','got',eph.SVHealth,'exp',src.SVHealth,'tol',0,'wrap',0);
checks(end+1) = struct('name','IODC','got',eph.IODC,'exp',src.IODC,'tol',0,'wrap',0);
checks(end+1) = struct('name','TGD','got',eph.TGD,'exp',src.TGD,'tol',2^-31/2,'wrap',0);
checks(end+1) = struct('name','Toc','got',eph.Toc,'exp',src.Toc,'tol',8,'wrap',0);
checks(end+1) = struct('name','Af0','got',eph.Af0,'exp',src.Af0,'tol',2^-31/2,'wrap',0);
checks(end+1) = struct('name','Af1','got',eph.Af1,'exp',src.Af1,'tol',2^-43/2,'wrap',0);
checks(end+1) = struct('name','Af2','got',eph.Af2,'exp',src.Af2,'tol',2^-55/2,'wrap',0);
% 子帧 2
checks(end+1) = struct('name','IODE','got',eph.IODE,'exp',src.IODE,'tol',0,'wrap',0);
checks(end+1) = struct('name','Crs','got',eph.Crs,'exp',src.Crs,'tol',2^-5/2,'wrap',0);
checks(end+1) = struct('name','DeltaN','got',eph.DeltaN,'exp',src.DeltaN,'tol',2^-43/2,'wrap',2^-27);
checks(end+1) = struct('name','M0','got',eph.M0,'exp',src.M0,'tol',2^-31/2,'wrap',2);
checks(end+1) = struct('name','Cuc','got',eph.Cuc,'exp',src.Cuc,'tol',2^-29/2,'wrap',0);
checks(end+1) = struct('name','Ecc','got',eph.Ecc,'exp',src.Ecc,'tol',2^-33/2,'wrap',0);
checks(end+1) = struct('name','Cus','got',eph.Cus,'exp',src.Cus,'tol',2^-29/2,'wrap',0);
checks(end+1) = struct('name','SqrtA','got',eph.SqrtA,'exp',src.SqrtA,'tol',2^-19/2,'wrap',0);
checks(end+1) = struct('name','Toe','got',eph.Toe,'exp',src.Toe,'tol',8,'wrap',0);
% 子帧 3
checks(end+1) = struct('name','Cic','got',eph.Cic,'exp',src.Cic,'tol',2^-29/2,'wrap',0);
checks(end+1) = struct('name','Omega0','got',eph.Omega0,'exp',src.Omega0,'tol',2^-31/2,'wrap',2);
checks(end+1) = struct('name','Cis','got',eph.Cis,'exp',src.Cis,'tol',2^-29/2,'wrap',0);
checks(end+1) = struct('name','i0','got',eph.i0,'exp',src.i0,'tol',2^-31/2,'wrap',2);
checks(end+1) = struct('name','Crc','got',eph.Crc,'exp',src.Crc,'tol',2^-5/2,'wrap',0);
checks(end+1) = struct('name','omega','got',eph.omega,'exp',src.omega,'tol',2^-31/2,'wrap',2);
checks(end+1) = struct('name','OmegaDot','got',eph.OmegaDot,'exp',src.OmegaDot,'tol',2^-43/2,'wrap',2^-19);
checks(end+1) = struct('name','IDOT','got',eph.IDOT,'exp',src.IDOT,'tol',2^-43/2,'wrap',2^-29);

st.nFields = numel(checks);
for c = checks
    if c.wrap > 0
        d = abs(mod(c.got - c.exp + c.wrap/2, c.wrap) - c.wrap/2);
    else
        d = abs(c.got - c.exp);
    end
    ok = d <= c.tol + 1e-12*max(abs(c.exp), 1);
    st.nFieldsOK = st.nFieldsOK + ok;
    if ~ok, st.bad{end+1} = c.name; end %#ok<AGROW>
end

% 卫星位置合理性（t=Toe：轨道半径；60 s 位移 ≈ 3.87 km/s）
try
    [pos0, ~, r] = satellitePosition(eph, eph.Toe);
    [pos60, ~]   = satellitePosition(eph, mod(eph.Toe + 60, 604800));
    st.r = r;
    st.dr60 = norm(pos60 - pos0);
    % ECEF 60 s 位移 = 轨道运动（~231 km）+ 地球自转视运动（0~1925 m/s），
    % 物理范围约 100~350 km；另校验轨道半径稳定性（60 s 内 < 5 km）
    st.posOK  = r > 2.4e7 && r < 2.9e7;
    st.rStable = abs(norm(pos60) - r) < 5e3;
    st.moveOK = st.dr60 > 100e3 && st.dr60 < 400e3 && st.rStable;
catch
    st.posOK = false;
    st.moveOK = false;
end
end

%% ---- 星座几何统计：每星在自身 Toe 处的轨道半径 + 半周期对径检查 ----
function st = constellationCheck(nav)
st = struct('nUsed', 0, 'rMean', NaN, 'rStd', NaN, 'rOK', false, ...
    'periodMean', NaN, 'periodStd', NaN, 'periodOK', false);

mu = 3.986005e14;

prns = unique([nav.gpsEph.PRN]);
rAll = [];
periodRatio = [];
for prn = prns
    rows = find([nav.gpsEph.PRN] == prn);
    sq = arrayfun(@(e) e.SqrtA, nav.gpsEph(rows));
    te = arrayfun(@(e) e.Toe, nav.gpsEph(rows));
    valid = rows(sq > 1e3 & te > 0);
    if isempty(valid), continue; end
    e = nav.gpsEph(valid(end));
    eph.SqrtA = e.SqrtA;  eph.DeltaN = e.DeltaN; eph.M0 = e.M0;
    eph.Ecc = e.Ecc;      eph.omega = e.omega;
    eph.Cuc = e.Cuc;      eph.Cus = e.Cus;
    eph.Crc = e.Crc;      eph.Crs = e.Crs;
    eph.i0 = e.i0;        eph.IDOT = e.IDOT;
    eph.Cic = e.Cic;      eph.Cis = e.Cis;
    eph.Omega0 = e.Omega0; eph.OmegaDot = e.OmegaDot;
    eph.Toe = e.Toe;      eph.Toc = e.Toe;
    eph.Af0 = 0; eph.Af1 = 0; eph.Af2 = 0;
    try
        [p0, ~, r0] = satellitePosition(eph, eph.Toe);
        % 整周期对径：GPS 周期 T≈43084 s ≈ 半个恒星日，一个周期后地球
        % 恰好自转 ~180°，ECEF 位置正好对径，距离 ≈ 2r（~5.3e7 m）
        A = eph.SqrtA^2;
        n = sqrt(mu/A^3) + eph.DeltaN*pi;
        Tfull = 2*pi/n;
        p1 = satellitePosition(eph, mod(eph.Toe + Tfull, 604800));
        rAll(end+1) = r0; %#ok<AGROW>
        periodRatio(end+1) = norm(p1 - p0) / (2*r0); %#ok<AGROW>
    catch
    end
end

st.nUsed = numel(rAll);
if st.nUsed >= 20
    st.rMean = mean(rAll);
    st.rStd = std(rAll);
    st.rOK = st.rMean > 2.4e7 && st.rMean < 2.9e7 && st.rStd < 1e6;
    st.periodMean = mean(periodRatio);
    st.periodStd = std(periodRatio);
    % 整周期对径距离应在 2r 的 ±10% 内（真实卫星约 5.3e7 m）
    st.periodOK = all(periodRatio > 0.9) && all(periodRatio < 1.1);
end
end

function printEphCompare(tag, st, eph)
fprintf('  [%s] 字段 %d/%d 通过', tag, st.nFieldsOK, st.nFields);
if ~isempty(st.bad)
    fprintf('，超差: %s', strjoin(st.bad, ', '));
end
fprintf('\n  [%s] 卫星位置: r=%.4e m (%s)，60 s 位移=%.1f km (%s)\n', ...
    tag, st.r, passStr(st.posOK), st.dr60/1e3, passStr(st.moveOK));
fprintf('  [%s] 星历概要: af0=%+.3e s  sqrtA=%.4f  ecc=%.8f  i0=%.5f 半周\n', ...
    tag, eph.Af0, eph.SqrtA, eph.Ecc, eph.i0);
end

function s = passStr(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end
