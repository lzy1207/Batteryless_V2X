%% run_per_and_power_compare_MIMO_STS2.m
% 2x2 MIMO + Nsts=2 (spatial multiplexing), with Glaze common-mode overlay
clear; clc; close all;

%% ===== MIMO settings =====
Nt  = 2;
Nr  = 2;
Nsts = 2;     % spatial multiplexing (2 streams)

%% ===== Wi-Fi PHY =====
cfgHE = wlanHESUConfig;
cfgHE.ChannelBandwidth = 'CBW20';
cfgHE.MCS = 0;
cfgHE.APEPLength = 8000;       % bytes
cfgHE.GuardInterval = 0.8;
cfgHE.ChannelCoding = 'LDPC';

cfgHE.NumTransmitAntennas = Nt;
cfgHE.NumSpaceTimeStreams = Nsts;

%% ===== TGax channel =====
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

%% ===== Sweep control =====
snrVec = 0:3:12;
maxNumPackets = 200;
maxNumErrors  = 50;

%% ===== Glaze params =====
glz = struct;
glz.Enable   = true;
glz.Delta_dB = 2;
glz.Rb       = 15e3;
glz.RateBits = int8([1;1]);
glz.PayloadBits = int8(randi([0 1], 25, 1));

% Fit check
[fits, needSamp, availSamp, Nhb] = glazeFitCheck(cfgHE, glz);
fprintf("Glaze fit check: fits=%d, needSamp=%d, availSamp=%d, Nhb=%d (Rb=%.0f)\n", ...
    fits, needSamp, availSamp, Nhb, glz.Rb);
if ~fits
    warning("Glaze packet does NOT fit into HE-Data. Consider higher Rb / shorter payload / multi-PPDU overlay.");
end

%% ===== Run baseline & with-Glaze =====
perBase = zeros(size(snrVec));
perWiFiWithGlz = zeros(size(snrVec));
perGlz = zeros(size(snrVec));

for ii = 1:numel(snrVec)
    % baseline (IMPORTANT: do NOT add sp.Glaze for baseline)
    sp = struct;
    sp.Config = cfgHE;
    sp.RandomSubstream = 1;
    sp.MaxNumPackets = maxNumPackets;
    sp.MaxNumErrors  = maxNumErrors;
    sp.SNR = snrVec(ii);
    sp.Channel = clone(tgax);

    % for box0Simulation printing / tagging
    sp.DelayProfile = string(tgax.DelayProfile);
    sp.NumTransmitAntennas = Nt;
    sp.NumReceiveAntennas  = Nr;
    sp.MCS = cfgHE.MCS;

    out0 = box0Simulation(sp);
    perBase(ii) = out0.packetErrorRate;

    % with Glaze
    sp2 = sp;
    sp2.Glaze = glz;
    out1 = box0Simulation(sp2);

    perWiFiWithGlz(ii) = out1.packetErrorRate;
    perGlz(ii)         = out1.glazePacketErrorRate;

    fprintf("SNR=%2d dB | WiFi PER(base)=%.4f | WiFi PER(+Glz)=%.4f | Glz PER=%.4f | success=%d mismatch=%d nodetect=%d | meanCorr=%.3f\n", ...
        snrVec(ii), perBase(ii), perWiFiWithGlz(ii), perGlz(ii), ...
        out1.glzSuccessCnt, out1.glzMismatchCnt, out1.glzNoDetectCnt, ...
        mean(out1.glzCorrPeakStore,'omitnan'));
end

%% ===== Plot =====
figure;
semilogy(snrVec, perBase, 'o-'); hold on; grid on;
semilogy(snrVec, perWiFiWithGlz, 's-');
semilogy(snrVec, perGlz, '^-');
xlabel('SNR (dB)'); ylabel('PER');
legend('Wi-Fi baseline','Wi-Fi with Glaze','Glaze packet error rate','Location','best');
title(sprintf('2x2 MIMO, Nsts=%d, MCS%d, %s', Nsts, cfgHE.MCS, cfgHE.ChannelBandwidth));

%% ===== local helper =====
function [fits, needSamp, availSamp, Nhb] = glazeFitCheck(cfgHE, glz)
Fs  = wlanSampleRate(cfgHE);
ind = wlanFieldIndices(cfgHE);
pktG   = glazeBuildPacket(glz.PayloadBits, glz.RateBits);
halfLv = glazeManchesterEncode(pktG.bits);

Nhb = max(1, round(Fs/(2*glz.Rb)));
needSamp  = numel(halfLv) * Nhb;
availSamp = ind.HEData(2) - ind.HEData(1) + 1;
fits = needSamp <= availSamp;
end
