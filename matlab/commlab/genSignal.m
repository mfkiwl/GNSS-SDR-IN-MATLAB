function [m, s, info] = genSignal(mode, t, p)
%GENSIGNAL 生成调制/复用信号
%   [m, s, info] = genSignal(mode, t, p)
%   m    : 基带信号（AM/FM/ASK/FSK/QAM 为波形，TDM/FDM 为 struct(m1,m2)）
%   s    : 已调/复用信号（若 p.noiseOn 为真，则叠加高斯白噪声）
%   info : 附加信息（比特序列、QAM 星座、采样参数等）

fs = p.fs;
N  = numel(t);
info = struct();

switch mode
    case 'AM'
        mBase = cos(2*pi*p.fm*t);
        m = 1 + p.mu*mBase;
        s = m .* cos(2*pi*p.fc*t);
        info.mBase = mBase;

    case 'FM'
        mBase = cos(2*pi*p.fm*t);
        m = mBase;
        s = cos(2*pi*p.fc*t + p.beta*sin(2*pi*p.fm*t));
        info.mBase = mBase;

    case {'ASK','FSK'}
        Tb = 0.05;
        nb = max(1, floor(p.T/Tb));
        bits = randi([0 1], nb, 1);
        sps = round(Tb*fs);
        mBase = kron(bits, ones(sps,1));
        mBase = mBase(1:N);
        m = mBase;
        info.mBase = mBase;
        info.bits  = bits;
        info.nb    = nb;
        info.sps   = sps;
        info.Tb    = Tb;
        if strcmp(mode,'ASK')
            s = mBase .* cos(2*pi*p.fc*t);
        else
            % 连续相位 FSK (CPFSK)
            fctl = p.fdev*(2*mBase - 1);
            phase = 2*pi*(p.fc*t + cumsum(fctl)/fs);
            s = cos(phase);
        end

    case 'QAM'
        M = p.M;
        Tsym = 0.1;
        nsym = max(1, floor(p.T/Tsym));
        data = randi([0 M-1], nsym, 1);
        sym = qammod(data, M, 'gray');
        sps = round(Tsym*fs);
        mI = kron(real(sym), ones(sps,1)); mI = mI(1:N);
        mQ = kron(imag(sym), ones(sps,1)); mQ = mQ(1:N);
        m = mI;
        s = mI .* cos(2*pi*p.fc*t) - mQ .* sin(2*pi*p.fc*t);
        info.mBase = mI;
        info.mI = mI;
        info.mQ = mQ;
        info.sym = sym;
        info.data = data;
        info.nsym = nsym;
        info.sps = sps;
        info.Tsym = Tsym;

    case 'TDM'
        m1 = sin(2*pi*p.fm*t) + 0.3*sin(2*pi*2*p.fm*t);
        m2 = 0.8*sin(2*pi*p.fm2*t + pi/4);
        M2 = floor(N/2);
        s = zeros(2*M2, 1);
        s(1:2:end) = m1(1:M2);
        s(2:2:end) = m2(1:M2);
        m = struct('m1', m1(1:M2), 'm2', m2(1:M2));
        info.m1 = m.m1;
        info.m2 = m.m2;
        info.M2 = M2;

    case 'FDM'
        m1 = 0.6*cos(2*pi*p.fm*t) + 0.2*cos(2*pi*2*p.fm*t);
        m2 = 0.6*cos(2*pi*p.fm2*t) + 0.2*cos(2*pi*2*p.fm2*t);
        s = (1+m1).*cos(2*pi*p.fc*t) + (1+m2).*cos(2*pi*p.fc2*t);
        m = struct('m1', m1, 'm2', m2);
        info.m1 = m1;
        info.m2 = m2;
end

if p.noiseOn
    s = awgn(s, p.snr, 'measured');
end
info.N = numel(s);
end
