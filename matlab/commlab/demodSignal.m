function d = demodSignal(mode, t, s, p, info)
%DEMODSIGNAL 解调/分接
%   d = demodSignal(mode, t, s, p, info)
%   返回结构体 d：
%   - AM/FM : d.m  解调波形
%   - ASK/FSK : d.m 判决波形, d.bits 判决比特
%   - QAM   : d.mI/d.mQ 判决波形, d.sym 判决符号, d.r 接收星座点
%   - TDM/FDM : d.m1/d.m2 两路还原信号

d = struct();
switch mode
    case 'AM'
        env = abs(hilbert(s));
        env = lowpass(env, min(4*p.fm, 0.4*p.fs), p.fs);
        d.m = env - 1;
        d.m = fitGain(d.m, info.mBase);

    case 'FM'
        ph = unwrap(angle(hilbert(s)));
        inst = [0; diff(ph)] * p.fs/(2*pi);
        dev = lowpass(inst - p.fc, min(4*p.fm, 0.4*p.fs), p.fs);
        dev = dev - mean(dev);
        d.m = fitGain(dev, info.mBase);

    case 'ASK'
        env = abs(hilbert(s));
        thr = (max(env) + min(env))/2;
        d.bits = decideBits(env, info.sps, info.nb, thr);
        d.m = kron(double(d.bits), ones(info.sps,1));
        d.m = d.m(1:numel(s));

    case 'FSK'
        sps = info.sps;
        nb  = info.nb;
        nfull = sps*nb;
        seg = reshape(s(1:nfull), sps, nb);
        tseg = (0:sps-1)'/p.fs;
        f1 = p.fc + p.fdev;
        f0 = p.fc - p.fdev;
        % 非相干正交相关检测（对连续相位不敏感）
        z1 = sqrt(sum(seg .* cos(2*pi*f1*tseg), 1).^2 + ...
                  sum(seg .* sin(2*pi*f1*tseg), 1).^2);
        z0 = sqrt(sum(seg .* cos(2*pi*f0*tseg), 1).^2 + ...
                  sum(seg .* sin(2*pi*f0*tseg), 1).^2);
        d.bits = double(z1 > z0)';
        d.m = kron(double(d.bits), ones(sps,1));
        d.m = d.m(1:numel(s));

    case 'QAM'
        M = p.M;
        sps = info.sps;
        nfull = floor(numel(s)/sps)*sps;
        refI = cos(2*pi*p.fc*t);
        refQ = -sin(2*pi*p.fc*t);
        xi = 2*s(1:nfull).*refI(1:nfull);
        xq = 2*s(1:nfull).*refQ(1:nfull);
        SI = mean(reshape(xi, sps, []), 1);
        SQ = mean(reshape(xq, sps, []), 1);
        d.r = SI + 1j*SQ;
        d.sym = qamdemod(d.r, M, 'gray');
        d.sym = d.sym(:);
        rx = qammod(d.sym, M, 'gray');
        d.mI = kron(real(rx), ones(sps,1));
        d.mQ = kron(imag(rx), ones(sps,1));
        d.mI = d.mI(1:numel(s));
        d.mQ = d.mQ(1:numel(s));
        d.m = d.mI;

    case 'TDM'
        s1 = s(1:2:end);
        s2 = s(2:2:end);
        d.m1 = lowpass(s1, 4*p.fm,  p.fs/2);
        d.m2 = lowpass(s2, 4*p.fm2, p.fs/2);
        d.m1 = fitGain(d.m1, info.m1);
        d.m2 = fitGain(d.m2, info.m2);

    case 'FDM'
        bp1 = bandpass(s, [p.fc-8,  p.fc+8],  p.fs);
        bp2 = bandpass(s, [p.fc2-8, p.fc2+8], p.fs);
        e1 = abs(hilbert(bp1));
        e2 = abs(hilbert(bp2));
        d.m1 = lowpass(e1-1, 3*p.fm,  p.fs);
        d.m2 = lowpass(e2-1, 3*p.fm2, p.fs);
        d.m1 = fitGain(d.m1, info.m1);
        d.m2 = fitGain(d.m2, info.m2);
end
end

function y = fitGain(x, ref)
% 最小二乘幅度对齐，便于与原始基带信号对比
x = x(:);
ref = ref(:);
n = min(numel(x), numel(ref));
x = x(1:n);
ref = ref(1:n);
g = (ref'*x)/(x'*x + eps);
y = x*g;
end

function bits = decideBits(env, sps, nb, thr)
% 每个比特窗口取包络平均并与门限比较
nfull = min(sps*nb, numel(env));
seg = reshape(env(1:nfull), sps, []);
bits = double(mean(seg, 1) > thr)';
end
