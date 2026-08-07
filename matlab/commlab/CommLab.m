function fig = CommLab()
%COMMLAB 通信原理实验平台（交互式调制解调演示）
%   运行：在 MATLAB 命令窗口输入  CommLab  或  run('CommLab.m')
%   演示：AM / FM / ASK / QAM / FSK 调制解调，TDM 时分复用，FDM 频分复用
%   交互：参数调节、噪声叠加、波形播放动画、解调对比、频谱/星座图、截图导出

p = defaultParams();

% ---------- 数据缓存 ----------
D = struct('t', [], 's', [], 'info', [], 'd', [], ...
           'timer', [], 'animPos', 0, 'hasRun', false);

% ---------- 主窗口 ----------
fig = uifigure('Name', '通信原理实验平台 - 调制解调与复用演示', ...
               'Position', [60 60 1320 840]);
main = uigridlayout(fig, [1 2]);
main.ColumnWidth = {330, '1x'};
main.RowHeight = {'1x'};
main.Padding = [8 8 8 8];

% ================= 左侧：参数与操作 =================
leftPanel = uipanel(main, 'Title', '仿真参数与操作');
leftGridMain = uigridlayout(leftPanel, [3 1]);
leftGridMain.RowHeight = {'1x', 'fit', 'fit'};
leftGridMain.RowSpacing = 6;

leftGrid = uigridlayout(leftGridMain, [1 2]);
leftGrid.ColumnWidth = {170, '1x'};

ctrl = uigridlayout(leftGrid, [13 2]);
ctrl.RowHeight = repmat({'fit'}, 1, 13);
ctrl.RowSpacing = 7;

A = struct();

% 行1 调制方式
A.modeLabel = uilabel(ctrl, 'Text', '调制方式');
A.modeLabel.Layout.Row = 1; A.modeLabel.Layout.Column = 1;
A.modeDD = uidropdown(ctrl, 'Items', {'AM','FM','ASK','QAM','FSK','TDM','FDM'}, 'Value', p.mode);
A.modeDD.Layout.Row = 1; A.modeDD.Layout.Column = 2;

% 行2 载波频率
A.fcLabel = uilabel(ctrl, 'Text', '载波频率 fc (Hz)');
A.fcLabel.Layout.Row = 2; A.fcLabel.Layout.Column = 1;
A.fcEdit = uieditfield(ctrl, 'numeric', 'Value', p.fc, 'Limits', [10 200], ...
                       'ValueDisplayFormat', '%.1f');
A.fcEdit.Layout.Row = 2; A.fcEdit.Layout.Column = 2;

% 行3 基带频率
A.fmLabel = uilabel(ctrl, 'Text', '基带频率 fm (Hz)');
A.fmLabel.Layout.Row = 3; A.fmLabel.Layout.Column = 1;
A.fmEdit = uieditfield(ctrl, 'numeric', 'Value', p.fm, 'Limits', [0.2 10], ...
                       'ValueDisplayFormat', '%.2f');
A.fmEdit.Layout.Row = 3; A.fmEdit.Layout.Column = 2;

% 行4 第二通道频率
A.fm2Label = uilabel(ctrl, 'Text', '第二通道 fm2 (Hz)');
A.fm2Label.Layout.Row = 4; A.fm2Label.Layout.Column = 1;
A.fm2Edit = uieditfield(ctrl, 'numeric', 'Value', p.fm2, 'Limits', [0.2 10], ...
                        'ValueDisplayFormat', '%.2f');
A.fm2Edit.Layout.Row = 4; A.fm2Edit.Layout.Column = 2;

% 行5 采样率
A.fsLabel = uilabel(ctrl, 'Text', '采样率 fs (Hz)');
A.fsLabel.Layout.Row = 5; A.fsLabel.Layout.Column = 1;
A.fsEdit = uieditfield(ctrl, 'numeric', 'Value', p.fs, 'Limits', [200 5000], ...
                       'ValueDisplayFormat', '%.0f');
A.fsEdit.Layout.Row = 5; A.fsEdit.Layout.Column = 2;

% 行6 仿真时长
A.tLabel = uilabel(ctrl, 'Text', '仿真时长 T (s)');
A.tLabel.Layout.Row = 6; A.tLabel.Layout.Column = 1;
A.tEdit = uieditfield(ctrl, 'numeric', 'Value', p.T, 'Limits', [1 10], ...
                      'ValueDisplayFormat', '%.1f');
A.tEdit.Layout.Row = 6; A.tEdit.Layout.Column = 2;

% 行7 AM 调制度
A.muLabel = uilabel(ctrl, 'Text', 'AM 调制度 μ');
A.muLabel.Layout.Row = 7; A.muLabel.Layout.Column = 1;
A.muSlider = uislider(ctrl, 'Value', p.mu, 'Limits', [0.05 0.95], ...
                      'MajorTicks', [0.05 0.3 0.5 0.7 0.95]);
A.muSlider.Layout.Row = 7; A.muSlider.Layout.Column = 2;

% 行8 FM 调频指数
A.betaLabel = uilabel(ctrl, 'Text', 'FM 调频指数 β');
A.betaLabel.Layout.Row = 8; A.betaLabel.Layout.Column = 1;
A.betaEdit = uieditfield(ctrl, 'numeric', 'Value', p.beta, 'Limits', [0.5 20], ...
                         'ValueDisplayFormat', '%.1f');
A.betaEdit.Layout.Row = 8; A.betaEdit.Layout.Column = 2;

% 行9 QAM 阶数
A.mLabel = uilabel(ctrl, 'Text', 'QAM 阶数 M');
A.mLabel.Layout.Row = 9; A.mLabel.Layout.Column = 1;
A.mDD = uidropdown(ctrl, 'Items', {'4','16','64'}, 'Value', num2str(p.M));
A.mDD.Layout.Row = 9; A.mDD.Layout.Column = 2;

% 行10 FSK 频偏
A.fdevLabel = uilabel(ctrl, 'Text', 'FSK 频偏 Δf (Hz)');
A.fdevLabel.Layout.Row = 10; A.fdevLabel.Layout.Column = 1;
A.fdevEdit = uieditfield(ctrl, 'numeric', 'Value', p.fdev, 'Limits', [1 50], ...
                         'ValueDisplayFormat', '%.1f');
A.fdevEdit.Layout.Row = 10; A.fdevEdit.Layout.Column = 2;

% 行11 FDM 第二载波
A.fc2Label = uilabel(ctrl, 'Text', 'FDM 第二载波 fc2 (Hz)');
A.fc2Label.Layout.Row = 11; A.fc2Label.Layout.Column = 1;
A.fc2Edit = uieditfield(ctrl, 'numeric', 'Value', p.fc2, 'Limits', [30 400], ...
                        'ValueDisplayFormat', '%.0f');
A.fc2Edit.Layout.Row = 11; A.fc2Edit.Layout.Column = 2;

% 行12 噪声开关
A.noiseLabel = uilabel(ctrl, 'Text', '信道噪声');
A.noiseLabel.Layout.Row = 12; A.noiseLabel.Layout.Column = 1;
A.noiseChk = uicheckbox(ctrl, 'Text', '加入高斯白噪声', 'Value', p.noiseOn);
A.noiseChk.Layout.Row = 12; A.noiseChk.Layout.Column = 2;

% 行13 SNR
A.snrLabel = uilabel(ctrl, 'Text', '信噪比 SNR (dB)');
A.snrLabel.Layout.Row = 13; A.snrLabel.Layout.Column = 1;
A.snrSlider = uislider(ctrl, 'Value', p.snr, 'Limits', [-10 40], ...
                       'MajorTicks', [-10 0 10 20 30 40]);
A.snrSlider.Layout.Row = 13; A.snrSlider.Layout.Column = 2;

% ---------- 右侧按钮列 ----------
btns = uigridlayout(leftGrid, [5 1]);
btns.RowHeight = repmat({'fit'}, 1, 5);
btns.RowSpacing = 8;

A.runBtn = uibutton(btns, 'push', 'Text', '开始仿真', ...
                    'BackgroundColor', [0.05 0.45 0.85], 'FontColor', 'white', 'FontWeight', 'bold');
A.runBtn.Layout.Row = 1;
A.demodBtn = uibutton(btns, 'push', 'Text', '解调演示', ...
                      'BackgroundColor', [0.0 0.6 0.35], 'FontColor', 'white', 'FontWeight', 'bold');
A.demodBtn.Layout.Row = 2;
A.animBtn = uibutton(btns, 'push', 'Text', '播放波形');
A.animBtn.Layout.Row = 3;
A.shotBtn = uibutton(btns, 'push', 'Text', '导出截图 (PNG)');
A.shotBtn.Layout.Row = 4;
A.resetBtn = uibutton(btns, 'push', 'Text', '重置参数');
A.resetBtn.Layout.Row = 5;

% 底部：说明与状态（整行，无需跨行列）
A.hintLabel = uilabel(leftGridMain, 'Text', '', 'FontColor', [0.4 0.4 0.4], ...
                      'WordWrap', 'on');
A.hintLabel.Layout.Row = 2; A.hintLabel.Layout.Column = 1;
A.statusLabel = uilabel(leftGridMain, 'Text', '就绪：点击"开始仿真"', ...
                        'FontColor', [0.2 0.4 0.8], 'WordWrap', 'on');
A.statusLabel.Layout.Row = 3; A.statusLabel.Layout.Column = 1;

% ================= 右侧：可视化面板 =================
visPanel = uipanel(main, 'Title', '可视化');
vg = uigridlayout(visPanel, [2 2]);
vg.RowHeight = {'1x', '1x'};
vg.ColumnWidth = {'1x', '1x'};

A.timeAx = uiaxes(vg);
A.timeAx.Layout.Row = 1; A.timeAx.Layout.Column = 1;
A.spectAx = uiaxes(vg);
A.spectAx.Layout.Row = 1; A.spectAx.Layout.Column = 2;
A.demodAx = uiaxes(vg);
A.demodAx.Layout.Row = 2; A.demodAx.Layout.Column = 1;
A.extraAx = uiaxes(vg);
A.extraAx.Layout.Row = 2; A.extraAx.Layout.Column = 2;

% ================= 回调绑定 =================
A.modeDD.ValueChangedFcn      = @(s,e) onModeChanged();
A.fcEdit.ValueChangedFcn      = @(s,e) onParamChanged();
A.fmEdit.ValueChangedFcn      = @(s,e) onParamChanged();
A.fm2Edit.ValueChangedFcn     = @(s,e) onParamChanged();
A.fsEdit.ValueChangedFcn      = @(s,e) onParamChanged();
A.tEdit.ValueChangedFcn       = @(s,e) onParamChanged();
A.muSlider.ValueChangedFcn    = @(s,e) onParamChanged();
A.betaEdit.ValueChangedFcn    = @(s,e) onParamChanged();
A.mDD.ValueChangedFcn         = @(s,e) onParamChanged();
A.fdevEdit.ValueChangedFcn    = @(s,e) onParamChanged();
A.fc2Edit.ValueChangedFcn     = @(s,e) onParamChanged();
A.noiseChk.ValueChangedFcn    = @(s,e) onParamChanged();
A.snrSlider.ValueChangedFcn   = @(s,e) onParamChanged();

A.runBtn.ButtonPushedFcn   = @(s,e) onRun();
A.demodBtn.ButtonPushedFcn = @(s,e) onDemod();
A.animBtn.ButtonPushedFcn  = @(s,e) toggleAnim();
A.shotBtn.ButtonPushedFcn  = @(s,e) onScreenshot();
A.resetBtn.ButtonPushedFcn = @(s,e) onReset();

fig.CloseRequestFcn = @(s,e) onClose();

% 供测试/外部访问
fig.UserData.app = A;

% 初始运行
updateControlVisibility(p.mode);
runSimulation();

% ============================================================
%  嵌套回调函数
% ============================================================
    function onModeChanged()
        updateParams();
        updateControlVisibility(p.mode);
        runSimulation();
    end

    function onParamChanged()
        updateParams();
        if D.hasRun
            runSimulation();
        end
    end

    function onRun()
        updateParams();
        runSimulation();
    end

    function onDemod()
        if ~D.hasRun
            runSimulation();
        end
        D.d = demodSignal(p.mode, D.t, D.s, p, D.info);
        plotDemod();
    end

    function onReset()
        p = defaultParams();
        A.modeDD.Value  = p.mode;
        A.fcEdit.Value  = p.fc;
        A.fmEdit.Value  = p.fm;
        A.fm2Edit.Value = p.fm2;
        A.fsEdit.Value  = p.fs;
        A.tEdit.Value   = p.T;
        A.muSlider.Value = p.mu;
        A.betaEdit.Value = p.beta;
        A.mDD.Value      = num2str(p.M);
        A.fdevEdit.Value = p.fdev;
        A.fc2Edit.Value  = p.fc2;
        A.noiseChk.Value = p.noiseOn;
        A.snrSlider.Value = p.snr;
        updateControlVisibility(p.mode);
        runSimulation();
    end

    function onScreenshot()
        fname = fullfile(pwd, sprintf('commlab_%s_%s.png', p.mode, datestr(now,'HHMMSS')));
        exportgraphics(fig, fname, 'Resolution', 150);
        A.statusLabel.Text = sprintf('已导出截图：%s', fname);
    end

    function onClose()
        if ~isempty(D.timer) && isvalid(D.timer)
            stop(D.timer);
            delete(D.timer);
        end
        delete(fig);
    end

% ============================================================
%  仿真与绘图
% ============================================================
    function runSimulation()
        updateParams();
        D.t = (0:1/p.fs:p.T-1/p.fs)';
        [D.m, D.s, D.info] = genSignal(p.mode, D.t, p);
        if numel(D.s) < numel(D.t)
            D.t = D.t(1:numel(D.s));
        end
        D.d = [];
        D.hasRun = true;
        D.animPos = 0;
        if ~isempty(D.timer) && isvalid(D.timer) && strcmp(D.timer.Running,'on')
            stop(D.timer);
            A.animBtn.Text = '播放波形';
        end
        plotAll();
    end

    function plotAll()
        plotTime();
        plotSpectrum();
        plotExtra();
        cla(A.demodAx);
        text(A.demodAx, 0.5, 0.5, '点击"解调演示"查看解调结果', ...
             'Units', 'normalized', 'HorizontalAlignment', 'center');
        A.statusLabel.Text = sprintf('已生成 %s 信号：时长 %.1f s，%d 个采样点', ...
                                     p.mode, p.T, numel(D.s));
    end

    function plotTime()
        t = D.t; s = D.s; info = D.info;
        cla(A.timeAx);
        hold(A.timeAx, 'on');
        win = min(1.5, p.T);
        switch p.mode
            case {'AM','FM'}
                plot(A.timeAx, t, info.mBase, 'Color', [0 0.3 0.8], 'LineWidth', 1.2);
                plot(A.timeAx, t, s, 'Color', [0.85 0.2 0.2], 'LineWidth', 1.0);
                legend(A.timeAx, {'基带信号','已调信号'}, 'Location', 'northeast');
            case {'ASK','FSK'}
                plot(A.timeAx, t, info.mBase, 'Color', [0 0.3 0.8], 'LineWidth', 1.2);
                plot(A.timeAx, t, s, 'Color', [0.85 0.2 0.2], 'LineWidth', 1.0);
                legend(A.timeAx, {'二进制比特(基带)','已调信号'}, 'Location', 'northeast');
            case 'QAM'
                plot(A.timeAx, t, info.mI, 'Color', [0 0.3 0.8], 'LineWidth', 1.0);
                plot(A.timeAx, t, info.mQ, 'Color', [0 0.6 0.3], 'LineWidth', 1.0);
                plot(A.timeAx, t, s, 'Color', [0.85 0.2 0.2], 'LineWidth', 1.0);
                legend(A.timeAx, {'I 路基带','Q 路基带','已调信号'}, 'Location', 'northeast');
            case 'TDM'
                win = min(0.5, p.T);
                idx = t <= win;
                plot(A.timeAx, t(idx), info.m1(idx), 'b', 'LineWidth', 1.2);
                plot(A.timeAx, t(idx), info.m2(idx), 'g', 'LineWidth', 1.2);
                plot(A.timeAx, t(idx), s(idx), 'r', 'LineWidth', 1.0);
                legend(A.timeAx, {'通道1','通道2','TDM 复用帧'}, 'Location', 'northeast');
            case 'FDM'
                win = min(1.0, p.T);
                idx = t <= win;
                plot(A.timeAx, t(idx), info.m1(idx), 'b', 'LineWidth', 1.2);
                plot(A.timeAx, t(idx), info.m2(idx), 'g', 'LineWidth', 1.2);
                plot(A.timeAx, t(idx), s(idx), 'r', 'LineWidth', 1.0);
                legend(A.timeAx, {'通道1','通道2','FDM 合成信号'}, 'Location', 'northeast');
        end
        xlim(A.timeAx, [0 win]);
        grid(A.timeAx, 'on');
        title(A.timeAx, '时域波形：基带信号与已调/复用信号');
        xlabel(A.timeAx, '时间 t (s)');
        ylabel(A.timeAx, '幅度');
        A.timeAx.FontSize = 10;
    end

    function plotSpectrum()
        [f, X] = computeSpectrum(D.s, p.fs);
        cla(A.spectAx);
        plot(A.spectAx, f, abs(X)/max(abs(X)), 'LineWidth', 1.0, 'Color', [0.3 0.3 0.7]);
        hold(A.spectAx, 'on');
        yl = ylim(A.spectAx);
        if strcmp(p.mode, 'FDM')
            plot(A.spectAx, [p.fc p.fc], yl, '--r');
            plot(A.spectAx, [p.fc2 p.fc2], yl, '--r');
            legend(A.spectAx, {'频谱','通道1载波','通道2载波'}, 'Location', 'northeast');
        elseif ~strcmp(p.mode, 'TDM')
            plot(A.spectAx, [p.fc p.fc], yl, '--r');
            legend(A.spectAx, {'频谱','载波'}, 'Location', 'northeast');
        end
        xlim(A.spectAx, [-0.4*p.fs 0.4*p.fs]);
        grid(A.spectAx, 'on');
        title(A.spectAx, '已调信号频谱（归一化）');
        xlabel(A.spectAx, '频率 f (Hz)');
        ylabel(A.spectAx, '归一化幅度');
        A.spectAx.FontSize = 10;
    end

    function plotExtra()
        cla(A.extraAx);
        hold(A.extraAx, 'on');
        switch p.mode
            case 'AM'
                env = abs(hilbert(D.s));
                plot(A.extraAx, D.t, env, 'Color', [0.9 0.5 0.1], 'LineWidth', 1.1);
                title(A.extraAx, 'AM 包络（检波前）');
                xlabel(A.extraAx, '时间 t (s)');
            case 'FM'
                ph = unwrap(angle(hilbert(D.s)));
                inst = [0; diff(ph)] * p.fs/(2*pi);
                plot(A.extraAx, D.t, inst, 'm', 'LineWidth', 1.0);
                yl = ylim(A.extraAx);
                plot(A.extraAx, [D.t(1) D.t(end)], [p.fc p.fc], '--r');
                title(A.extraAx, 'FM 瞬时频率（含载波）');
                xlabel(A.extraAx, '时间 t (s)');
            case 'ASK'
                env = abs(hilbert(D.s));
                thr = (max(env) + min(env))/2;
                plot(A.extraAx, D.t, env, 'Color', [0.9 0.5 0.1], 'LineWidth', 1.0);
                plot(A.extraAx, [D.t(1) D.t(end)], [thr thr], '--r');
                title(A.extraAx, 'ASK 包络与判决门限');
                xlabel(A.extraAx, '时间 t (s)');
            case 'FSK'
                ph = unwrap(angle(hilbert(D.s)));
                inst = [0; diff(ph)] * p.fs/(2*pi);
                plot(A.extraAx, D.t, inst, 'm', 'LineWidth', 1.0);
                yl = ylim(A.extraAx);
                plot(A.extraAx, [D.t(1) D.t(end)], [p.fc+p.fdev p.fc+p.fdev], '--r');
                plot(A.extraAx, [D.t(1) D.t(end)], [p.fc-p.fdev p.fc-p.fdev], '--r');
                title(A.extraAx, 'FSK 瞬时频率（±Δf 两电平）');
                xlabel(A.extraAx, '时间 t (s)');
            case 'QAM'
                plot(A.extraAx, real(D.info.sym), imag(D.info.sym), 'bo', ...
                     'MarkerSize', 7, 'LineWidth', 1.2);
                if ~isempty(D.d) && isfield(D.d, 'r')
                    plot(A.extraAx, real(D.d.r), imag(D.d.r), 'r.', 'MarkerSize', 8);
                    legend(A.extraAx, {'发射星座','接收星座'}, 'Location', 'best');
                else
                    legend(A.extraAx, {'发射星座'}, 'Location', 'best');
                end
                axis(A.extraAx, 'equal');
                grid(A.extraAx, 'on');
                title(A.extraAx, sprintf('%d-QAM 星座图', p.M));
                xlabel(A.extraAx, '同相分量 I');
                ylabel(A.extraAx, '正交分量 Q');
            case 'TDM'
                n = min(40, numel(D.s));
                stem(A.extraAx, D.t(1:n), D.s(1:n), 'filled', 'MarkerSize', 4, ...
                     'Color', [0.2 0.6 0.8]);
                title(A.extraAx, 'TDM 帧结构（前 40 采样，两通道交替）');
                xlabel(A.extraAx, '时间 t (s)');
            case 'FDM'
                [f, X] = computeSpectrum(D.s, p.fs);
                plot(A.extraAx, f, abs(X)/max(abs(X)), 'LineWidth', 0.8, 'Color', [0.3 0.3 0.7]);
                yl = ylim(A.extraAx);
                plot(A.extraAx, [p.fc p.fc], yl, '--r');
                plot(A.extraAx, [p.fc2 p.fc2], yl, '--r');
                title(A.extraAx, 'FDM 频谱：两个子频带');
                xlabel(A.extraAx, '频率 f (Hz)');
                xlim(A.extraAx, [-0.4*p.fs 0.4*p.fs]);
        end
        grid(A.extraAx, 'on');
        A.extraAx.FontSize = 10;
    end

    function plotDemod()
        d = D.d; t = D.t; info = D.info;
        cla(A.demodAx);
        hold(A.demodAx, 'on');
        switch p.mode
            case {'AM','FM'}
                plot(A.demodAx, t, info.mBase, 'Color', [0 0.3 0.8], 'LineWidth', 1.2);
                plot(A.demodAx, t, d.m, 'Color', [0.85 0.3 0.2], 'LineStyle', '--', 'LineWidth', 1.0);
                legend(A.demodAx, {'原始基带','解调输出'}, 'Location', 'best');
                title(A.demodAx, '解调对比');
                r = corrMetric(info.mBase, d.m);
                A.statusLabel.Text = sprintf('解调完成（%s）：与原始信号相关系数 r = %.4f', p.mode, r);
            case {'ASK','FSK'}
                plot(A.demodAx, t, info.mBase, 'Color', [0 0.3 0.8], 'LineWidth', 1.2);
                plot(A.demodAx, t, d.m, 'Color', [0.85 0.3 0.2], 'LineStyle', '--', 'LineWidth', 1.0);
                legend(A.demodAx, {'原始比特','解调比特'}, 'Location', 'best');
                title(A.demodAx, '解调对比');
                n = min(numel(d.bits), numel(info.bits));
                err = sum(d.bits(1:n) ~= info.bits(1:n));
                A.statusLabel.Text = sprintf('解调完成（%s）：误码率 BER = %.4f（%d/%d）', ...
                                             p.mode, err/n, err, n);
            case 'QAM'
                n = min(numel(d.mI), numel(info.mI));
                plot(A.demodAx, t(1:n), info.mI(1:n), 'Color', [0 0.3 0.8], 'LineWidth', 1.0);
                plot(A.demodAx, t(1:n), d.mI(1:n), 'Color', [0.85 0.3 0.2], 'LineStyle', '--', 'LineWidth', 1.0);
                plot(A.demodAx, t(1:n), info.mQ(1:n), 'Color', [0 0.6 0.3], 'LineWidth', 1.0);
                plot(A.demodAx, t(1:n), d.mQ(1:n), 'Color', [0.9 0.6 0.2], 'LineStyle', '--', 'LineWidth', 1.0);
                legend(A.demodAx, {'原始 I','解调 I','原始 Q','解调 Q'}, 'Location', 'best');
                title(A.demodAx, '解调对比（I/Q 支路）');
                nSym = min(numel(d.sym), numel(info.data));
                err = sum(d.sym(1:nSym) ~= info.data(1:nSym));
                A.statusLabel.Text = sprintf('解调完成（%d-QAM）：误符号率 SER = %.4f（%d/%d）', ...
                                             p.M, err/nSym, err, nSym);
            case {'TDM','FDM'}
                plot(A.demodAx, t, info.m1, 'Color', [0 0.3 0.8], 'LineWidth', 1.2);
                plot(A.demodAx, t, d.m1, 'Color', [0.85 0.3 0.2], 'LineStyle', '--', 'LineWidth', 1.0);
                legend(A.demodAx, {'通道1 原始','通道1 解调'}, 'Location', 'best');
                title(A.demodAx, '通道1 解调对比');
                cla(A.extraAx);
                hold(A.extraAx, 'on');
                plot(A.extraAx, t, info.m2, 'Color', [0 0.6 0.3], 'LineWidth', 1.2);
                plot(A.extraAx, t, d.m2, 'Color', [0.85 0.3 0.2], 'LineStyle', '--', 'LineWidth', 1.0);
                legend(A.extraAx, {'通道2 原始','通道2 解调'}, 'Location', 'best');
                title(A.extraAx, '通道2 解调对比');
                r1 = corrMetric(info.m1, d.m1);
                r2 = corrMetric(info.m2, d.m2);
                A.statusLabel.Text = sprintf('解调完成（%s）：通道1 r=%.4f，通道2 r=%.4f', p.mode, r1, r2);
        end
        grid(A.demodAx, 'on');
        xlabel(A.demodAx, '时间 t (s)');
        A.demodAx.FontSize = 10;
    end

% ============================================================
%  动画与辅助
% ============================================================
    function toggleAnim()
        if ~D.hasRun
            runSimulation();
        end
        if ~isempty(D.timer) && isvalid(D.timer) && strcmp(D.timer.Running, 'on')
            stop(D.timer);
            A.animBtn.Text = '播放波形';
        else
            if isempty(D.timer) || ~isvalid(D.timer)
                D.timer = timer('TimerFcn', @animStep, 'Period', 0.05, ...
                                'ExecutionMode', 'fixedSpacing');
            end
            start(D.timer);
            A.animBtn.Text = '暂停播放';
        end
    end

    function animStep(~, ~)
        win = min(1.5, p.T);
        D.animPos = D.animPos + 0.05;
        if D.animPos > p.T - win
            D.animPos = 0;
        end
        xlim(A.timeAx, [D.animPos, D.animPos + win]);
    end

    function updateParams()
        p.mode    = A.modeDD.Value;
        p.fc      = A.fcEdit.Value;
        p.fm      = A.fmEdit.Value;
        p.fm2     = A.fm2Edit.Value;
        p.fs      = A.fsEdit.Value;
        p.T       = A.tEdit.Value;
        p.mu      = A.muSlider.Value;
        p.beta    = A.betaEdit.Value;
        p.M       = str2double(A.mDD.Value);
        p.fdev    = A.fdevEdit.Value;
        p.fc2     = A.fc2Edit.Value;
        p.noiseOn = A.noiseChk.Value;
        p.snr     = A.snrSlider.Value;
    end

    function updateControlVisibility(mode)
        am  = strcmp(mode,'AM');
        fm  = strcmp(mode,'FM');
        ask = strcmp(mode,'ASK');
        qam = strcmp(mode,'QAM');
        fsk = strcmp(mode,'FSK');
        tdm = strcmp(mode,'TDM');
        fdm = strcmp(mode,'FDM');

        setPairVisible(A.fcLabel,  A.fcEdit,  ~tdm);
        setPairVisible(A.fmLabel,  A.fmEdit,  ~fsk);
        setPairVisible(A.fm2Label, A.fm2Edit, tdm || fdm);
        setPairVisible(A.muLabel,  A.muSlider, am);
        setPairVisible(A.betaLabel, A.betaEdit, fm);
        setPairVisible(A.mLabel,   A.mDD,     qam);
        setPairVisible(A.fdevLabel, A.fdevEdit, fsk);
        setPairVisible(A.fc2Label,  A.fc2Edit,  fdm);
        A.hintLabel.Text = hintText(mode);
    end

    function setPairVisible(h1, h2, vis)
        h1.Visible = vis;
        h2.Visible = vis;
    end

    function txt = hintText(mode)
        switch mode
            case 'AM',  txt = 'AM 调幅：包络携带信息，包络检波解调。调节 μ 改变调制度。';
            case 'FM',  txt = 'FM 调频：瞬时频率携带信息，β 越大带宽越宽，鉴频解调。';
            case 'ASK', txt = 'ASK 幅移键控：0/1 控制载波通断，包络加门限判决解调。';
            case 'QAM', txt = 'QAM 正交幅度调制：I/Q 两路正交载波，星座图观察，相干解调。';
            case 'FSK', txt = 'FSK 频移键控：0/1 对应两个频率（连续相位），相关判决解调。';
            case 'TDM', txt = 'TDM 时分复用：多路信号按时间片交替传输，接收端分接还原。';
            case 'FDM', txt = 'FDM 频分复用：多路信号占用不同频带同时传输，带通滤波分离。';
        end
    end
end

function [f, X] = computeSpectrum(s, fs)
%COMPUTESPECTRUM 单边/双边频谱（fftshift）
N = numel(s);
X = fftshift(fft(s));
f = (-N/2:N/2-1)/N*fs;
end

function r = corrMetric(x, y)
%CORRMETRIC 相关系数
x = x(:); y = y(:);
n = min(numel(x), numel(y));
x = x(1:n) - mean(x(1:n));
y = y(1:n) - mean(y(1:n));
r = (x'*y)/sqrt((x'*x)*(y'*y) + eps);
end
