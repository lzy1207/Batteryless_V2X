%% run_per_and_power_compare_MIMO.m  (MIMO version: 2x2, Nsts=1 recommended)
clear; clc; close all;

%% =======================
%% 0) MIMO setting (NEW)
%% =======================
Nt  = 2;   % <-- MIMO: number of TX antennas
Nr  = 2;   % <-- MIMO: number of RX antennas
Nsts = 1;  % <-- 推荐先用 1（波束成形/分集）。想做空分复用可改 2（需要 Nr>=2 且更复杂）

%% 1) Wi-Fi PHY config
cfgHE = wlanHESUConfig;
cfgHE.ChannelBandwidth = 'CBW20';
cfgHE.MCS = 0;
cfgHE.APEPLength = 5000;      % bytes
cfgHE.GuardInterval = 0.8;
cfgHE.ChannelCoding = 'LDPC';

cfgHE.NumTransmitAntennas  = Nt;
cfgHE.NumSpaceTimeStreams  = Nsts;   % Nsts=1 最稳

%% 2) TGax channel
tgax = wlanTGaxChannel;
tgax.DelayProfile = 'Model-D';
tgax.ChannelBandwidth = cfgHE.ChannelBandwidth;
tgax.NumTransmitAntennas = Nt;
tgax.NumReceiveAntennas  = Nr;
tgax.TransmitReceiveDistance = 15;
tgax.LargeScaleFadingEffect = 'None';
tgax.SampleRate = wlanSampleRate(cfgHE);
tgax.PathGainsOutputPort = true;
tgax.NormalizeChannelOutputs = false;

%% 3) Simulation controls
snrVec = 0:3:30;
maxNumPackets = 200;
maxNumErrors  = 50;

%% 4) Glaze params
glz = struct;
glz.Enable   = true;
glz.Delta_dB = 2;            % 你现在的实验结果看起来就是这种量级；想更强可改 6/8
glz.Rb       = 11e3;         % 11 kbps
glz.RateBits = int8([1;1]);
glz.PayloadBits = int8(randi([0 1], 25, 1));

% ---- Fit check: 是否能完整放入 HE-Data ----
[fits, needSamp, availSamp, Nhb] = glazeFitCheck(cfgHE, glz);
fprintf("Glaze fit check: fits=%d, needSamp=%d, availSamp=%d, Nhb=%d (Rb=%.0f)\n", ...
    fits, needSamp, availSamp, Nhb, glz.Rb);
if ~fits
    warning("Glaze packet does NOT fit in a single PPDU HE-Data. Increase Rb or shorten payload / use multi-PPDU overlay.");
end

%% 5) Run baseline & Wi-Fi+Glaze
perBase        = zeros(size(snrVec));
perWiFiWithGlz = zeros(size(snrVec));
perGlz         = zeros(size(snrVec));

for i = 1:numel(snrVec)
    % -------- baseline (NO Glaze field) --------
    sp = struct;
    sp.Config = cfgHE;
    sp.RandomSubstream = 1;
    sp.MaxNumPackets = maxNumPackets;
    sp.MaxNumErrors  = maxNumErrors;
    sp.SNR = snrVec(i);

    sp.Channel = clone(tgax);
    sp.DelayProfile = string(tgax.DelayProfile);

    % 仅用于 box0Simulation 的 disp 打印/标注
    sp.NumTransmitAntennas = Nt;
    sp.NumReceiveAntennas  = Nr;
    sp.MCS = cfgHE.MCS;

    out0 = box0Simulation(sp);
    perBase(i) = out0.packetErrorRate;

    % -------- with Glaze --------
    sp2 = sp;
    sp2.Glaze = glz;
    out1 = box0Simulation(sp2);

    perWiFiWithGlz(i) = out1.packetErrorRate;
    perGlz(i)         = out1.glazePacketErrorRate;

    fprintf("SNR=%2d dB | WiFi PER(base)=%.4f | WiFi PER(+Glz)=%.4f | Glz PER=%.4f | success=%d mismatch=%d nodetect=%d | meanCorr=%.3f\n", ...
        snrVec(i), perBase(i), perWiFiWithGlz(i), perGlz(i), ...
        out1.glzSuccessCnt, out1.glzMismatchCnt, out1.glzNoDetectCnt, ...
        mean(out1.glzCorrPeakStore,'omitnan'));
end

%% 6) Plot PER curves
figure;
semilogy(snrVec, perBase, 'o-'); hold on; grid on;
semilogy(snrVec, perWiFiWithGlz, 's-');
semilogy(snrVec, perGlz, '^-');
xlabel('SNR (dB)'); ylabel('Packet Error Rate');
legend('Wi-Fi baseline','Wi-Fi with Glaze','Glaze packet error rate','Location','best');
title(sprintf('PER comparison (MIMO: %dx%d, Nsts=%d)', Nt, Nr, Nsts));

%% 7) (Optional) TX waveform avg power comparison (rough)
% 说明：这里用 wlanWaveformGenerator 的默认空间映射生成一个波形，仅用于“有无 Glaze 的平均功率差”示意。
try
    txPSDU  = randi([0 1], cfgHE.APEPLength*8, 1, 'int8');
    txOrigM = wlanWaveformGenerator(txPSDU, cfgHE);   % [Nsamp x Nt]
    ind = wlanFieldIndices(cfgHE);
    Fs  = wlanSampleRate(cfgHE);

    pktG   = glazeBuildPacket(glz.PayloadBits, glz.RateBits);
    halfLv = glazeManchesterEncode(pktG.bits);

    % glazeEmbed 若不支持矩阵输入，则逐天线处理
    try
        [txGlzM, ~] = glazeEmbed(txOrigM, halfLv, Fs, glz.Rb, glz.Delta_dB, ind.HEData);
    catch
        txGlzM = txOrigM;
        for ant = 1:size(txOrigM,2)
            [txGlzM(:,ant), ~] = glazeEmbed(txOrigM(:,ant), halfLv, Fs, glz.Rb, glz.Delta_dB, ind.HEData);
        end
    end

    Ptx_orig = mean(abs(txOrigM(:)).^2);
    Ptx_glz  = mean(abs(txGlzM(:)).^2);

    figure;
    bar([10*log10(Ptx_orig), 10*log10(Ptx_glz)]);
    grid on;
    set(gca,'XTickLabel',{'Wi-Fi TX','Wi-Fi+Glaze TX'});
    ylabel('Avg power (dB, arbitrary)');
    title(sprintf('TX waveform average power (MIMO %dx%d, Nsts=%d)', Nt, Nr, Nsts));
catch ME
    warning("Skip TX power comparison block due to: %s", ME.message);
end

%% =========================
%% local helper functions
%% =========================
function [fits, needSamp, availSamp, Nhb] = glazeFitCheck(cfgHE, glz)
% 检查：完整 Glaze 包（Manchester 后）需要多少采样点，HE-Data 有多少采样点
Fs  = wlanSampleRate(cfgHE);
ind = wlanFieldIndices(cfgHE);

pktG   = glazeBuildPacket(glz.PayloadBits, glz.RateBits);
halfLv = glazeManchesterEncode(pktG.bits);

Nhb = max(1, round(Fs/(2*glz.Rb)));             % samples per half-bit
needSamp  = numel(halfLv) * Nhb;               % 需要的采样点
availSamp = ind.HEData(2) - ind.HEData(1) + 1; % HE-Data 可用采样点

fits = needSamp <= availSamp;
end
