function out = gnssSubframeDecode(bits, varargin)
%GNSSSUBFRAMEDECODE GPS 子帧边界同步与电文字解码
%
%   out = gnssSubframeDecode(bits)
%   out = gnssSubframeDecode(bits, 'Reference', ref)
%
%   输入:
%     bits - 解调后的 0/1 比特流（行向量）
%     'Reference' - 发送端结构：ref.bits（发送比特流）、ref.metas（子帧 meta 数组）
%   输出:
%     out.syncIndex     - 通过奇偶校验验证的子帧起点位索引（可能多个）
%     out.polarity      - 每个有效子帧对应的极性（1=原样，0=取反；
%                         BPSK 解调有 180° 相位模糊，由前导码+奇偶校验消除）
%     out.subframes(k)  - 每个有效子帧的解析：
%         .tlmMsg / .tlmCount / .tow / .subframeId / .dataWords(8x24) / .parityOK
%     out.compare(k)    - 与参考的字段对比（提供 Reference 时）：
%         .tlmMsgOK / .towOK / .sfidOK / .dataOK / .bitErrors
%
%   同步方法：搜索 TLM 前导码 10001011，对每个候选按 300 位子帧
%   逐字重算奇偶校验（gpsWordParity），校验通过才确认为子帧边界。

p = struct();
p.Reference = [];
for k = 1:2:numel(varargin)
    key = varargin{k};
    val = varargin{k+1};
    switch lower(key)
        case 'reference', p.Reference = val;
        otherwise, error('未知参数: %s', key);
    end
end

bits = bits(:).';
n = numel(bits);
preamble = [1 0 0 0 1 0 1 1];

%% ---- 前导码候选 + 奇偶校验验证（消除 BPSK 180° 极性模糊）----
validIdx = [];
validPol = [];
for pol = [1, 0]
    b2 = bits;
    if pol == 0, b2 = 1 - bits; end
    cands = strfind(b2, preamble);
    for p0 = cands
        if p0 + 299 > n, continue; end
        sf = b2(p0 : p0+299);
        words = reshape(sf, 30, 10).';
        ok = true;
        prevD29 = 0; prevD30 = 0;
        for w = 1:10
            tx = words(w, :);
            % ICD 位反转还原：逻辑数据 = 发送 bit1..24 XOR 前字 D30
            log24 = mod(tx(1:24) + prevD30, 2);
            [recalc, ~, ~] = gpsWordParity(log24, prevD29, prevD30, w);
            prevD29 = tx(29);
            prevD30 = tx(30);
            if ~isequal(recalc, tx), ok = false; break; end
        end
        if ok
            validIdx(end+1) = p0; %#ok<AGROW>
            validPol(end+1) = pol; %#ok<AGROW>
        end
    end
end
out.syncIndex = validIdx;
out.polarity  = validPol;

%% ---- 解析有效子帧（先逐字还原 D30 位反转，再提取字段）----
sfDec = struct('tlmMsg', {}, 'tlmCount', {}, 'tow', {}, ...
    'subframeId', {}, 'dataWords', {}, 'parityOK', {});
for k = 1:numel(validIdx)
    p0 = validIdx(k);
    pol = validPol(k);
    b2  = bits;
    if pol == 0, b2 = 1 - bits; end
    words = reshape(b2(p0 : p0+299), 30, 10).';
    logWords = zeros(10, 24);
    prevD30 = 0;
    for w = 1:10
        logWords(w, :) = mod(words(w, 1:24) + prevD30, 2);
        prevD30 = words(w, 30);
    end
    sfDec(k).tlmMsg     = logWords(1, 9:14);
    sfDec(k).tlmCount   = bi2de(logWords(1, 17:22), 'left-msb');
    sfDec(k).tow        = bi2de(logWords(2, 1:17), 'left-msb');
    sfDec(k).subframeId = bi2de(logWords(2, 20:22), 'left-msb');
    sfDec(k).dataWords  = logWords(3:10, :);
    sfDec(k).parityOK   = true;
    sfDec(k).polarity   = pol;
end
out.subframes = sfDec;

%% ---- 与发送端参考对比 ----
if ~isempty(p.Reference)
    ref = p.Reference;
    comp = struct('tlmMsgOK', {}, 'towOK', {}, 'sfidOK', {}, ...
        'dataOK', {}, 'bitErrors', {}, 'matched', {});
    for k = 1:numel(sfDec)
        dec = sfDec(k);
        p0k = validIdx(k);
        % 按 TOW 匹配发送端子帧
        mi = find([ref.metas.tow] == dec.tow, 1);
        if isempty(mi)
            comp(k).matched = false;
            comp(k).bitErrors = NaN;
            continue;
        end
        m = ref.metas(mi);
        comp(k).matched   = true;
        comp(k).tlmMsgOK  = isequal(dec.tlmMsg, m.tlmMsg);
        comp(k).towOK     = dec.tow == m.tow;
        comp(k).sfidOK    = dec.subframeId == m.subframeId;
        comp(k).dataOK    = isequal(dec.dataWords, m.dataWords);
        % 发送子帧在 ref.bits 中的位置
        sfPos = strfind(ref.bits, m.bits300);
        if ~isempty(sfPos)
            b2 = bits;
            if validPol(k) == 0, b2 = 1 - bits; end
            comp(k).bitErrors = sum(b2(p0k : p0k+299) ~= ref.bits(sfPos(1) : sfPos(1)+299));
        else
            comp(k).bitErrors = NaN;
        end
    end
    out.compare = comp;
end
end
