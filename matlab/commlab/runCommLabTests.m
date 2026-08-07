function runCommLabTests()
%RUNCOMMLABTESTS 通信实验平台单元测试
%   1) 核心调制/解调正确性（无噪声）
%   2) 带噪声路径
%   3) GUI 冒烟测试

p = defaultParams();
p.noiseOn = false;
modes = {'AM','FM','ASK','QAM','FSK','TDM','FDM'};

fprintf('===== 调制/解调正确性测试（无噪声） =====\n');
nPass = 0;
for i = 1:numel(modes)
    p.mode = modes{i};
    t = (0:1/p.fs:p.T-1/p.fs)';
    [m, s, info] = genSignal(p.mode, t, p);
    d = demodSignal(p.mode, t(1:numel(s)), s, p, info);
    [ok, msg] = checkMode(p.mode, m, d, info);
    if ok, nPass = nPass + 1; end
    fprintf('%-4s : %s  %s\n', p.mode, tern(ok,'PASS','FAIL'), msg);
end
fprintf('无噪声通过 %d/%d\n\n', nPass, numel(modes));

fprintf('===== 带噪声测试 =====\n');
p.noiseOn = true; p.snr = 30;
p.mode = 'AM';
t = (0:1/p.fs:p.T-1/p.fs)';
[m, s, info] = genSignal(p.mode, t, p);
d = demodSignal(p.mode, t, s, p, info);
[ok1, msg1] = checkMode(p.mode, m, d, info);
fprintf('AM  SNR=30dB : %s  %s\n', tern(ok1,'PASS','FAIL'), msg1);

p.mode = 'QAM';
[m, s, info] = genSignal(p.mode, t, p);
d = demodSignal(p.mode, t, s, p, info);
[ok2, msg2] = checkMode(p.mode, m, d, info);
fprintf('QAM SNR=30dB : %s  %s\n', tern(ok2,'PASS','FAIL'), msg2);

fprintf('\n===== GUI 冒烟测试 =====\n');
try
    fig = CommLab();
    drawnow;
    A = fig.UserData.app;
    % 遍历所有调制方式触发一次仿真
    for i = 1:numel(modes)
        A.modeDD.Value = modes{i};
        A.modeDD.ValueChangedFcn(A.modeDD, []);
        drawnow;
    end
    A.demodBtn.ButtonPushedFcn(A.demodBtn, []);
    drawnow;
    nAx = numel(findall(fig, 'Type', 'axes'));
    fprintf('GUI_OK  axes=%d\n', nAx);
    delete(fig);
catch err
    fprintf('GUI_FAIL: %s\n', err.message);
end
fprintf('\nALL_DONE\n');
end

function [ok, msg] = checkMode(mode, m, d, info)
switch mode
    case {'AM','FM'}
        r = corrMetric(d.m, info.mBase);
        ok = r > 0.9;
        msg = sprintf('相关系数 r=%.4f', r);
    case {'ASK','FSK'}
        n = min(numel(d.bits), numel(info.bits));
        err = sum(d.bits(1:n) ~= info.bits(1:n));
        ok = err == 0;
        msg = sprintf('误比特 %d/%d', err, n);
    case 'QAM'
        n = min(numel(d.sym), numel(info.data));
        err = sum(d.sym(1:n) ~= info.data(1:n));
        ok = err == 0;
        msg = sprintf('误符号 %d/%d', err, n);
    case {'TDM','FDM'}
        r1 = corrMetric(d.m1, info.m1);
        r2 = corrMetric(d.m2, info.m2);
        ok = r1 > 0.8 && r2 > 0.8;
        msg = sprintf('通道1 r=%.4f, 通道2 r=%.4f', r1, r2);
    otherwise
        ok = false;
        msg = '未知模式';
end
end

function r = corrMetric(x, y)
x = x(:); y = y(:);
n = min(numel(x), numel(y));
x = x(1:n) - mean(x(1:n));
y = y(1:n) - mean(y(1:n));
r = (x'*y)/sqrt((x'*x)*(y'*y) + eps);
end

function s = tern(cond, a, b)
if cond, s = a; else, s = b; end
end
