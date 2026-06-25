function [pktHat, det] = glazeDecode(rx, Fs, Rb, varargin)
% glazeDecode (calibrated + pairwise Manchester decision)
%
% 输入:
%   rx: Ns-by-Nr 复基带（建议截取叠加区，例如 HE-Data 段）
%   Fs: 采样率
%   Rb: Glaze 比特率（bps）
%
% 可选 Name-Value:
%   'CorrThreshold'   : 归一化相关门限，默认 0.35（可调 0.25~0.55）
%   'UseMovingThresh' : 粗判决 half-bit 用滑动阈值 movmedian，默认 false
%   'ThreshWindow'    : half-bit 域滑动阈值窗口，默认 81
%   'PairMargin'      : 成对判决的最小能量差门限比例，默认 0.08
%                       (abs(e1-e2) < PairMargin*(E1-E0) 视为“低置信度/非法对”)
%
% 输出:
%   pktHat.data : 25 bits
%   det.found   : 是否检测到 LTF
%   det.corrPeakNorm : 归一化相关峰
%   det.E0/E1/thr    : 标定得到的能量与阈值
%   det.illegalPairs : 低置信度 pair 数（可用于调参/统计）

% ----------------- options -----------------
p = inputParser;
addParameter(p,'CorrThreshold',0.35);
addParameter(p,'UseMovingThresh',false);
addParameter(p,'ThreshWindow',81);
addParameter(p,'PairMargin',0.08);
parse(p,varargin{:});
opt = p.Results;

pktHat = struct('data',[]);
det = struct('found',false);

rx = rx(:,:);
env = sqrt(sum(abs(rx).^2, 2));                 % 合并多天线包络

Nhb = max(1, round(Fs/(2*Rb)));                 % 每 half-bit 采样点数
det.Nhb = Nhb;

% 轻度平滑抑制OFDM快速起伏
L = max(1, round(Nhb/8));
envLP = movmean(env, L);

% ----------------- half-bit 能量积分/平均 -----------------
nHalf = floor(numel(envLP)/Nhb);
halfE = zeros(nHalf,1);
for i = 1:nHalf
    idx = (i-1)*Nhb + (1:Nhb);
    halfE(i) = mean(envLP(idx));
end
det.halfE = halfE;

% ----------------- 粗阈值：仅用于“检测LTF起点”（不是用于最终解码） -----------------
if opt.UseMovingThresh
    w = min(opt.ThreshWindow, nHalf);
    if mod(w,2)==0, w = w+1; end
    thrRough = movmedian(halfE, w, 'omitnan');
else
    thrRough = median(halfE,'omitnan') * ones(size(halfE));
end
halfBitsRough = int8(halfE > thrRough);

% ----------------- LTF相关检测（13-bit Barker -> 26 half-bit） -----------------
ltfBits = int8([1;1;1;1;1;0;0;1;1;0;1;0;1]);
ltfHalf = glazeManchesterEncode(ltfBits);       % 26x1 (0/1)

seq = 2*double(ltfHalf) - 1;                    % +/-1
str = 2*double(halfBitsRough) - 1;              % +/-1

c = conv(str, flipud(seq), 'valid');
cNorm = c ./ numel(seq);                        % 归一化相关

[pk, idx] = max(abs(cNorm));
det.corrPeakNorm = pk;
det.ltfStartHalf = idx;
det.found = (pk >= opt.CorrThreshold);

if ~det.found
    return;
end

% ----------------- 幅度标定：用 STF(前7bit wakeup) + LTF 的“已知half-bit模式”估计E0/E1 -----------------
% STF: wakeup7 = 1010101 (7 bits)，Manchester后 14 half-bit
wakeup7 = int8([1;0;1;0;1;0;1]);
stfKnownHalf = glazeManchesterEncode(wakeup7);  % 14 half-bit (0/1)

stfHalfLenAll = 2*9;                            % 9 bits STF -> 18 half-bit（其中后2bit rate未知）
ltfHalfLen    = numel(ltfHalf);                 % 26
stfStartHalf  = det.ltfStartHalf - stfHalfLenAll;

calE = [];
calX = [];

% 只用 STF 的前 7 bit（已知）做标定：它起点在 stfStartHalf
if stfStartHalf >= 1
    stfKnownStart = stfStartHalf;               % STF 起点
    stfKnownEnd   = stfKnownStart + numel(stfKnownHalf) - 1;
    if stfKnownEnd <= nHalf
        calE = [calE; halfE(stfKnownStart:stfKnownEnd)];
        calX = [calX; stfKnownHalf];
    end
end

% 再把 LTF 的 26 half-bit 加进标定
ltfStart = det.ltfStartHalf;
ltfEnd   = ltfStart + ltfHalfLen - 1;
if ltfEnd <= nHalf
    calE = [calE; halfE(ltfStart:ltfEnd)];
    calX = [calX; ltfHalf];
end

% 估计 E0/E1（用 median 更抗异常值）
E0 = median(calE(calX==0),'omitnan');
E1 = median(calE(calX==1),'omitnan');

% 容错：如果估计反了，就交换
if E1 < E0
    tmp = E0; E0 = E1; E1 = tmp;
end

det.E0 = E0; det.E1 = E1;
det.thr = 0.5*(E0+E1);
det.deltaE = E1 - E0;

% ----------------- 取 data 并“成对判决” Manchester（关键改进点） -----------------
dataStartHalf = det.ltfStartHalf + ltfHalfLen;  % STF+LTF 后面就是 data（我们从 LTF 后开始）
needHalf = 2*25;

if dataStartHalf + needHalf - 1 > nHalf
    det.found = false;
    return;
end

dataE = halfE(dataStartHalf : dataStartHalf + needHalf - 1);

% Manchester 成对判决：0->[0 1] => e1<e2；1->[1 0] => e1>e2
dataBits = zeros(25,1,'int8');
illegal = 0;

margin = opt.PairMargin * max(det.deltaE, eps); % eps防止deltaE太小
for k = 1:25
    e1 = dataE(2*k-1);
    e2 = dataE(2*k);

    if abs(e1 - e2) < margin
        illegal = illegal + 1;                  % 差太小，低置信度
        % 低置信度时可用阈值辅助（或者直接判0）
        % 用阈值辅助更稳一点：
        b1 = (e1 > det.thr);
        b2 = (e2 > det.thr);
        if (b1==0 && b2==1)
            dataBits(k)=0;
        elseif (b1==1 && b2==0)
            dataBits(k)=1;
        else
            dataBits(k)=int8(e1 > e2);          % 兜底
        end
    else
        dataBits(k) = int8(e1 > e2);
    end
end

det.illegalPairs = illegal;
det.pairMarginUsed = opt.PairMargin;

pktHat.data = dataBits;

end
