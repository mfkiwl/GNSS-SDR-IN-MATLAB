function results = verifyOfficialEphemeris(varargin)
%VERIFYOFFICIALEPHEMERIS 官方 RINEX 星历 → 官方编码 → TX/RX 闭环验证
%
%   流程:
%     1. 解析官方 RINEX 广播星历（默认 data/auto2190.26n，RINEX 2.11）
%     2. 选 PRN（默认 5；该 PRN 无记录则取第一颗健康星）
%     3. rinexToGpsCfg 映射到 HelperGPSCEIConfig，官方编码 LNAV 子帧 1-5
%     4. 官方解码器 HelperGPSLNAVDataDecode 交叉验证子帧 1-3
%        （10 字奇偶全过 + 全部星历字段量化误差在 1 LSB 内）
%     5. Synthetic 闭环：900 位（子帧 1-3）TX 缓冲 → 注入多普勒/码相位/噪声
%        → 捕获 → DLL/PLL 跟踪 → 解调 → gnssSubframeDecode 端到端对比
%     6. 判定 PASS/FAIL，保存 .mat/.png
%
%   用法:
%     verifyOfficialEphemeris                          % Synthetic（默认）
%     verifyOfficialEphemeris('PRN', 2)
%     verifyOfficialEphemeris('RinexFile', <路径>)
%
%   参数 (Name-Value):
%     'Synthetic'   - true 离线模拟（默认）；false 硬件闭环（TX 仅子帧 1）
%     'PRN'         - 目标卫星（默认 5）
%     'RinexFile'   - RINEX 2 导航文件（默认 data/auto2190.26n）
%     'CaptureSec'  - 采集时长（默认 18.6：覆盖 900 位 = 18 s 完整周期）
%     'SyntheticDopplerHz' / 'SyntheticCodePhase' / 'SyntheticCN0'
%     'PllBandwidth' / 'DllBandwidth' / 'CorrSpacing'
%
%   说明:
%     - 子帧 1-3 承载完整时钟+星历（M4 定位所需），官方 Helper 编码器
%       按 IS-GPS-200L 缩放因子量化，与真实卫星播发完全同构
%     - 硬件模式 TX 缓冲上限 2^24 采样（2.5 MHz 下 6 s = 1 个子帧），
%       完整 3 子帧星历仅 Synthetic 验证

%% ---- 参数 ----
p = struct();
p.Synthetic   = true;
p.PRN         = 5;
p.RinexFile   = fullfile(fileparts(mfilename('fullpath')), 'data', 'auto2190.26n');
p.Fs          = 2.5e6;
p.CaptureSec  = 18.6;
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
        case 'synthetic',        p.Synthetic = val;
        case 'prn',              p.PRN = val;
        case 'rinexfile',        p.RinexFile = val;
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
rx = []; tx = [];

try
    fprintf('==========================================================\n');
    fprintf(' 官方 RINEX 星历 → 官方编码 → TX/RX 闭环验证\n');
    fprintf('==========================================================\n');

    %% ---- 1. 解析 RINEX ----
    fprintf('[RINEX] 解析 %s ...\n', p.RinexFile);
    nav = readRinexNav(p.RinexFile);
    results.nav = nav;
    fprintf('  版本 %.2f %s，GPS 星历记录 %d 条，leap=%g\n', ...
        nav.header.version, strtrim(nav.header.type), ...
        numel(nav.gpsEph), nav.header.leapSeconds);

    prnList = unique([nav.gpsEph.PRN]);
    if ~any(prnList == p.PRN)
        healthy = prnList;
        fprintf('  PRN %d 无记录，改用第一颗健康星 PRN %d\n', p.PRN, healthy(1));
        p.PRN = healthy(1);
    end
    results.params.PRN = p.PRN;

    %% ---- 2. 映射 + 官方编码 ----
    fprintf('[ENCODE] PRN %d → HelperGPSNavigationConfig（LNAV）...\n', p.PRN);
    out = rinexToGpsCfg(nav, p.PRN);
    results.out = out;
    sf1 = out.subframes(1, :);
    sf2 = out.subframes(2, :);
    sf3 = out.subframes(3, :);
    fprintf('  子帧1-3 生成完毕，TOW 基准 %d（子帧1=%d, 子帧2=%d, 子帧3=%d）\n', ...
        out.towBase, out.metas(1).tow, out.metas(2).tow, out.metas(3).tow);
    fprintf('  星历源值: af0=%+.3e s  af1=%+.3e s/s  sqrtA=%.4f m^0.5  ecc=%.8f\n', ...
        out.eph.Af0, out.eph.Af1, out.eph.SqrtA, out.eph.Ecc);
    fprintf('            Toe=%g  toc(周内)=%.1f s  week=%d  IODE=%d IODC=%d\n', ...
        out.eph.Toe, tocSowOf(out.eph, nav.header), out.eph.Week, ...
        out.eph.IODE, out.eph.IODC);

    %% ---- 3. 官方解码器交叉验证（子帧 1-3）----
    fprintf('[DECODE] HelperGPSLNAVDataDecode 交叉验证 ...\n');
    [fieldsOK, parityOK, fieldList] = crossCheckOfficial(out);
    results.crossCheck = struct('fieldsOK', fieldsOK, 'parityOK', parityOK, ...
        'fieldList', fieldList);
    fprintf('  奇偶校验: %s（30 字全过）\n', passStr(all(parityOK)));
    nBad = sum(~fieldsOK);
    fprintf('  星历字段: %d 项全部在量化误差内%s\n', numel(fieldList), ...
        passStr(nBad == 0));
    if nBad > 0
        bad = fieldList(~fieldsOK);
        fprintf('  超差字段: %s\n', strjoin(bad, ', '));
    end

    %% ---- 4. 合成/硬件信号 ----
    sfBits = [sf1, sf2, sf3];   % 900 位（18 s）
    results.txBits = sfBits;
    results.txMetas = out.metas(1:3);

    if p.Synthetic
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
        truth = struct('codePhase', mod(p.SyntheticCodePhase, ...
            round(p.Fs*1e-3)), 'dopplerHz', p.SyntheticDopplerHz, ...
            'cn0dBHz', p.SyntheticCN0);
        fprintf('[SYN] 合成信号 %.1f s（%d 采样），缓冲 900 位子帧1-3\n', ...
            nSamp/p.Fs, nSamp);
    else
        sfBits = sf1;                       % 硬件 TX 仅子帧 1（6 s 缓冲）
        results.txBits = sfBits;
        results.txMetas = out.metas(1);
        buf = generateGnssTxBuffer(p.PRN, p.Fs, 'Amplitude', 0.1, ...
            'NavBits', sf1);
        if numel(buf) > 2^24
            error('TX 缓冲 %d 采样超过 Pluto 上限 2^24', numel(buf));
        end
        r = findPlutoRadio();
        if isempty(r), error('未找到 PlutoSDR'); end
        radioID = r(1).RadioID;
        tx = sdrtx('Pluto', 'RadioID', radioID, ...
            'CenterFrequency', 1575.42e6, 'BasebandSampleRate', p.Fs, ...
            'Gain', -65);
        tx.transmitRepeat(buf);
        fprintf('[TX] 已发射官方子帧1 合成 GPS（6 s 缓冲，增益 -65 dB）\n');
        pause(0.5);
        nSamp = round(p.Fs * p.CaptureSec);
        frameSamples = round(p.Fs * 0.01);
        rx = sdrrx('Pluto', 'RadioID', radioID, ...
            'CenterFrequency', 1575.42e6, 'BasebandSampleRate', p.Fs, ...
            'GainSource', 'Manual', 'Gain', 20, 'OutputDataType', 'double', ...
            'SamplesPerFrame', frameSamples);
        try, rx.kernelBuffersCount = 32; catch, end
        nFrames = round(nSamp / frameSamples);
        data = zeros(nFrames * frameSamples, 1);
        for kk = 1:nFrames
            data((kk-1)*frameSamples + (1:frameSamples)) = step(rx);
        end
        release(rx); delete(rx); rx = [];
        release(tx); delete(tx); tx = [];
        truth = struct('codePhase', NaN, 'dopplerHz', 0, 'cn0dBHz', NaN);
        fprintf('[RX] 硬件闭环采集 %.1f s 完成\n', nSamp/p.Fs);
    end
    results.truth = truth;

    %% ---- 5. 捕获 + 跟踪 ----
    fprintf('[ACQ] 捕获 ...\n');
    acq = acquisition(data, p.Fs, 'Verbose', false, ...
        'IntegrationMs', 5, 'NonCoherentN', 10, 'DopplerStep', 100);
    r1 = acq.results([acq.results.PRN] == p.PRN);
    others = [acq.results.metric];
    others([acq.results.PRN] == p.PRN) = -inf;
    dominance = r1.metric / max(max(others), eps);
    fprintf('  PRN %2d: metric=%.1f doppler=%+7.1f Hz codePhase=%5d 领先度=%.1f\n', ...
        p.PRN, r1.metric, r1.dopplerHz, r1.codePhase, dominance);
    results.acq = acq;

    fprintf('[TRK] DLL+PLL 跟踪 ...\n');
    trk = tracking(data, p.Fs, acq, 'PRNList', p.PRN, ...
        'PllBandwidth', p.PllBandwidth, 'DllBandwidth', p.DllBandwidth, ...
        'CorrSpacing', p.CorrSpacing, 'ReferenceBits', sfBits);
    t1 = trk(1);
    results.trk = t1;
    nMs = numel(t1.carrierFreq);
    n1s = min(1000, nMs);
    fEst = median(t1.carrierFreq(end-n1s+1 : end));
    cn0w = t1.CN0dBHz;
    nW1s = min(50, numel(cn0w));
    cn0Med = median(cn0w(end-nW1s+1 : end));
    fprintf('  CN0=%.1f dB-Hz  f_est=%+8.2f Hz  lock=%d  比特误码=%d/%d\n', ...
        cn0Med, fEst, t1.lock, t1.numErrors, numel(t1.bits));

    %% ---- 6. 子帧同步 + 解码 ----
    fprintf('[SYNC] gnssSubframeDecode（前导码 + 奇偶校验）...\n');
    ref = struct('bits', sfBits, 'metas', out.metas(1:numel(sfBits)/300));
    dec = gnssSubframeDecode(t1.bits, 'Reference', ref);
    results.dec = dec;
    nOK = 0;
    if isfield(dec, 'compare') && ~isempty(dec.compare)
        for k = 1:numel(dec.compare)
            c = dec.compare(k);
            if c.matched
                fprintf('    子帧 %d: TOW=%d 子帧号=%d 比特错误=%d 全字段匹配=%s\n', ...
                    k, dec.subframes(k).tow, dec.subframes(k).subframeId, ...
                    c.bitErrors, passStr(c.tlmMsgOK && c.towOK && ...
                    c.sfidOK && c.dataOK));
                if c.tlmMsgOK && c.towOK && c.sfidOK && c.dataOK && ...
                        c.bitErrors == 0
                    nOK = nOK + 1;
                end
            end
        end
    end

    %% ---- 7. 判定 ----
    msLen = round(p.Fs * 1e-3);
    if p.Synthetic
        fErr = abs(fEst - truth.dopplerHz);
        dErr = abs(mod(mean(t1.codePhase(end-n1s+1:end)) - truth.codePhase + ...
            msLen/2, msLen) - msLen/2);
        cn0OK = cn0Med >= truth.cn0dBHz - 5 && cn0Med <= truth.cn0dBHz + 5;
        estOK = fErr <= 5 && dErr <= 2;
    else
        fErr = abs(fEst); dErr = NaN;
        cn0OK = cn0Med >= 35; estOK = fErr <= 3;
    end
    acqOK = r1.detected && dominance >= 3;
    results.metrics = struct('cn0Median', cn0Med, 'fEst', fEst, ...
        'fErr', fErr, 'dErr', dErr, 'cn0OK', cn0OK, 'acqOK', acqOK, ...
        'estOK', estOK, 'subframesOK', nOK, 'fieldsOK', sum(fieldsOK), ...
        'parityOK', all(parityOK));

    results.pass = acqOK && t1.lock && cn0OK && estOK && ...
        all(parityOK) && (nBad == 0) && nOK >= 1;

    fprintf('\n==========================================================\n');
    fprintf(' 结论: %s（编码一致性=%d/%d 奇偶=%d 捕获=%d 锁定=%d C/N0=%d 参数=%d 子帧=%d）\n', ...
        passStr(results.pass), sum(fieldsOK), numel(fieldList), all(parityOK), ...
        acqOK, t1.lock, cn0OK, estOK, nOK);
    fprintf('==========================================================\n');

catch err
    fprintf('\n[验证中断]: %s\n', err.message);
    results.error = err.message;
    results.pass = false;
end

%% ---- 清理 ----
for obj = {rx, tx}
    o = obj{1};
    if ~isempty(o) && isvalid(o)
        try, release(o); catch, end
        try, delete(o); catch, end
    end
end

%% ---- 保存结果 ----
try
    outDir = fullfile(fileparts(mfilename('fullpath')), 'data');
    if ~exist(outDir, 'dir'), mkdir(outDir); end
    ts = datestr(now, 'yyyymmdd_HHMMSS');
    matFile = fullfile(outDir, ['official_ephemeris_' ts '.mat']);
    save(matFile, 'results');
    fprintf('结果已保存: %s\n', matFile);
    results.matFile = matFile;
    try
        plotOfficial(results, fullfile(outDir, ['official_ephemeris_' ts '.png']));
    catch e
        fprintf('绘图跳过: %s\n', e.message);
    end
catch e
    fprintf('保存跳过: %s\n', e.message);
end
end

%% ---- 官方解码交叉验证 ----
function [fieldsOK, parityOK, fieldList] = crossCheckOfficial(out)
subs = {out.subframes(1,:).', out.subframes(2,:).', out.subframes(3,:).'};
fieldsOK = [];
parityOK = zeros(1, 30);
fieldList = {};

for k = 1:3
    [dcfg, pc] = HelperGPSLNAVDataDecode(subs{k}, struct(), true);
    parityOK((k-1)*10 + (1:10)) = pc;

    % 每子帧独立可查字段（名称 → 解码访问器 + 源值 + 容差）
    checks = struct('name', {}, 'got', {}, 'exp', {}, 'tol', {}, 'wrap', {});
    cei = dcfg.CEIDataSet;

    % 公共字段
    checks = addCheck(checks, 'SubframeID', dcfg.SubframeID, out.metas(k).subframeId, 0);
    checks = addCheck(checks, 'HOWTOW', dcfg.HOWTOW, out.metas(k).tow, 0);
    if isfield(cei, 'WeekNumber')
        checks = addCheck(checks, 'WeekNumber', cei.WeekNumber, mod(out.eph.Week, 1024), 0);
    end

    if k == 1
        checks = addCheck(checks, 'af0', cei.SVClockCorrectionCoefficients(1), ...
            out.eph.Af0, 2^-31/2);
        checks = addCheck(checks, 'af1', cei.SVClockCorrectionCoefficients(2), ...
            out.eph.Af1, 2^-43/2);
        checks = addCheck(checks, 'af2', cei.SVClockCorrectionCoefficients(3), ...
            out.eph.Af2, 2^-55/2);
        checks = addCheck(checks, 'Toc', cei.ReferenceTimeOfClock, ...
            out.cfg.CEIDataSet.ReferenceTimeOfClock, 8);
        checks = addCheck(checks, 'TGD', cei.GroupDelayDifferential, out.eph.TGD, 2^-31/2);
        checks = addCheck(checks, 'IODC', cei.IssueOfDataClock, out.eph.IODC, 0);
        checks = addCheck(checks, 'URAID', cei.URAID, out.eph.URA, 0);
        checks = addCheck(checks, 'SVHealth', cei.SVHealth, out.eph.SVHealth, 0);
    elseif k == 2
        checks = addCheck(checks, 'IODE', cei.IssueOfDataEphemeris, out.eph.IODE, 0);
        checks = addCheck(checks, 'Crs', cei.HarmonicCorrectionTerms(3), out.eph.Crs, 2^-5/2);
        checks = addCheck(checks, 'Cus', cei.HarmonicCorrectionTerms(5), out.eph.Cus, 2^-29/2);
        checks = addCheck(checks, 'Cuc', cei.HarmonicCorrectionTerms(6), out.eph.Cuc, 2^-29/2);
        checks = addCheck(checks, 'DeltaN', cei.MeanMotionDifference, out.eph.DeltaN, 2^-43/2, 2^-27);
        checks = addCheck(checks, 'M0', cei.MeanAnomaly, out.eph.M0, 2^-31/2, 2);
        checks = addCheck(checks, 'Ecc', cei.Eccentricity, out.eph.Ecc, 2^-33/2);
        % sqrtA：编码器对 SemiMajorAxisLength 开方后按 2^-19 量化
        checks = addCheck(checks, 'sqrtA', sqrt(cei.SemiMajorAxisLength), ...
            out.eph.SqrtA, 2^-19/2);
        checks = addCheck(checks, 'Toe', cei.ReferenceTimeOfEphemeris, out.eph.Toe, 8);
    else
        checks = addCheck(checks, 'IODE', cei.IssueOfDataEphemeris, out.eph.IODE, 0);
        checks = addCheck(checks, 'Cis', cei.HarmonicCorrectionTerms(1), out.eph.Cis, 2^-29/2);
        checks = addCheck(checks, 'Cic', cei.HarmonicCorrectionTerms(2), out.eph.Cic, 2^-29/2);
        checks = addCheck(checks, 'Crc', cei.HarmonicCorrectionTerms(4), out.eph.Crc, 2^-5/2);
        checks = addCheck(checks, 'Omega0', cei.LongitudeOfAscendingNode, ...
            out.eph.Omega0, 2^-31/2, 2);
        checks = addCheck(checks, 'i0', cei.Inclination, out.eph.i0, 2^-31/2, 2);
        checks = addCheck(checks, 'omega', cei.ArgumentOfPerigee, out.eph.omega, 2^-31/2, 2);
        checks = addCheck(checks, 'OmegaDot', cei.RateOfRightAscension, ...
            out.eph.OmegaDot, 2^-43/2, 2^-19);
        checks = addCheck(checks, 'IDOT', cei.InclinationRate, out.eph.IDOT, 2^-43/2, 2^-29);
    end

    for c = checks
        fieldList{end+1} = c.name; %#ok<AGROW>
        if ~isempty(c.wrap) && c.wrap > 0
            fieldsOK(end+1) = wrapOK(c.got, c.exp, c.wrap, c.tol); %#ok<AGROW>
        else
            fieldsOK(end+1) = abs(c.got - c.exp) <= c.tol + ... %#ok<AGROW>
                1e-12 * max(abs(c.exp), 1);
        end
    end
end
end

function checks = addCheck(checks, name, got, exp, tol, wrap)
% 辅助：向结构数组追加一条字段检查
if nargin < 6, wrap = 0; end
ch = struct('name', name, 'got', got, 'exp', exp, 'tol', tol, 'wrap', wrap);
if isempty(checks)
    checks = ch;
else
    checks(end+1) = ch; %#ok<NASGU>
end
end

function ok = wrapOK(got, exp, range, tol)
% 二补码回绕比较：|got - exp| 按字段表示范围取模（如 M0 32 位有符号
% 表示范围为 [-1,1) 半周 = 2 半周模）
d = abs(mod(got - exp + range/2, range) - range/2);
ok = d <= tol + 1e-12 * max(abs(exp), 1);
end

%% ---- toc 秒周 ----
function s = tocSowOf(eph, header)
leap = 0;
if ~isempty(header) && isfield(header, 'leapSeconds') && isfinite(header.leapSeconds)
    leap = header.leapSeconds;
end
if isfield(eph, 'TocEpoch') && isfinite(eph.TocEpoch)
    s = mod((eph.TocEpoch - datenum(1980, 1, 6)) * 86400 + leap, 604800);
else
    s = eph.Toe;
end
end

%% ---- 绘图 ----
function plotOfficial(results, pngFile)
f = figure('Visible', 'off', 'Position', [100 100 900 620]);
if isfield(results, 'trk')
    t1 = results.trk;
    subplot(3, 1, 1);
    plot(1:numel(t1.CN0dBHz), t1.CN0dBHz);
    title(sprintf('C/N0 (median %.1f dB-Hz)', ...
        median(t1.CN0dBHz(end-min(50,end)+1:end))));
    xlabel('20 ms 窗口'); ylabel('dB-Hz'); grid on;

    subplot(3, 1, 2);
    plot(1:numel(t1.carrierFreq), t1.carrierFreq - ...
        median(t1.carrierFreq(end-1000+1:end)));
    title('载波频率残差 (Hz)'); xlabel('ms'); ylabel('Hz'); grid on;

    subplot(3, 1, 3);
    b = t1.bits;
    stairs(1:numel(b), b, 'LineWidth', 1);
    hold on;
    stairs(1:numel(b), double(t1.refBits), 'r--');
    legend('解调', '参考'); title('解调比特 vs 参考（官方星历）');
    xlim([1 min(numel(b), 300)]); ylim([-0.2 1.2]);
end
saveas(f, pngFile);
close(f);
fprintf('图形已保存: %s\n', pngFile);
end

%% ---- 字符串工具 ----
function s = passStr(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end
