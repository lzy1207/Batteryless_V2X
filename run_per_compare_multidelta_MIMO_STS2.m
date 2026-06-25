%% run_per_compare_multidelta_MIMO_STS2.m
% One figure:
%   Wi-Fi baseline PER
%   Wi-Fi PER with Glaze for Δ = 2/4/6/8 dB
%   Glaze PER for Δ = 2/4/6/8 dB
%
% Requires: box0Simulation.m + glazeBuildPacket.m + glazeManchesterEncode.m + glazeEmbed.m (+ WLAN Toolbox)

clear; clc; close all;
rng(1); % reproducible payload & simulation randomness (via RandStream in box0Simulation)

%% ===== MIMO settings =====
Nt   = 2;
Nr   = 2;
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

%% ===== Glaze params (base) =====
deltaList = [2 4 6 8];     % <<< you want these
glz = struct;
glz.Enable   = true;
glz.Delta_dB = deltaList(1);   % placeholder; will override in loop
glz.Rb       = 15e3;
glz.RateBits = int8([1;1]);
glz.PayloadBits = int8(randi([0 1], 25, 1));  % fixed by rng(1)

% Fit check (Δ does NOT affect fit, only Rb/payload/HE-Data length)
[fits, needSamp, availSamp, Nhb] = glazeFitCheck(cfgHE, glz);
fprintf("Glaze fit check: fits=%d, needSamp=%d, availSamp=%d, Nhb=%d (Rb=%.0f)\n", ...
    fits, needSamp, availSamp, Nhb, glz.Rb);
if ~fits
    warning("Glaze packet does NOT fit into HE-Data. Consider higher Rb / shorter payload / multi-PPDU overlay.");
end

%% ===== Storage =====
perBase      = zeros(1, numel(snrVec));                      % baseline Wi-Fi PER
perWiFiDelta = zeros(numel(deltaList), numel(snrVec));       % Wi-Fi PER with Glaze (each Δ)
perGlzDelta  = zeros(numel(deltaList), numel(snrVec));       % Glaze PER (each Δ)

%% ===== Run baseline & multi-Δ =====
for ii = 1:numel(snrVec)

    % ---- baseline sim params ----
    sp = struct;
    sp.Config = cfgHE;

    % IMPORTANT: use different substream per SNR, but same across Δ at the same SNR
    sp.RandomSubstream = ii;

    sp.MaxNumPackets = maxNumPackets;
    sp.MaxNumErrors  = maxNumErrors;
    sp.SNR = snrVec(ii);
    sp.Channel = clone(tgax);

    % for box0Simulation printing / tagging (optional)
    sp.DelayProfile = string(tgax.DelayProfile);
    sp.NumTransmitAntennas = Nt;
    sp.NumReceiveAntennas  = Nr;
    sp.MCS = cfgHE.MCS;

    % ---- baseline ----
    out0 = box0Simulation(sp);
    perBase(ii) = out0.packetErrorRate;

    % ---- with Glaze for each Δ ----
    for id = 1:numel(deltaList)
        glzTmp = glz;
        glzTmp.Delta_dB = deltaList(id);

        sp2 = sp;
        sp2.Glaze = glzTmp;

        out1 = box0Simulation(sp2);

        perWiFiDelta(id, ii) = out1.packetErrorRate;
        perGlzDelta(id,  ii) = out1.glazePacketErrorRate;

        fprintf("SNR=%2d | Δ=%d dB | WiFi base=%.4f | WiFi(+Glz)=%.4f | Glz PER=%.4f | succ=%d mismatch=%d nodetect=%d | meanCorr=%.3f\n", ...
            snrVec(ii), deltaList(id), perBase(ii), perWiFiDelta(id,ii), perGlzDelta(id,ii), ...
            out1.glzSuccessCnt, out1.glzMismatchCnt, out1.glzNoDetectCnt, ...
            mean(out1.glzCorrPeakStore,'omitnan'));
    end
end

%% ===== Plot: ONE FIGURE, ALL CURVES =====
figure; grid on; hold on;

% baseline (make it visually distinct)
h0 = semilogy(snrVec, perBase, 'k-o', 'LineWidth', 1.6, 'MarkerSize', 6);
h0.DisplayName = 'Wi-Fi baseline';

% style helpers
mk = {'s','d','^','v','>','<','p','h','x','+'};  % enough markers
lwWifi = 1.2;
lwGlz  = 1.2;

% Wi-Fi curves for each Δ (solid)
for id = 1:numel(deltaList)
    hh = semilogy(snrVec, perWiFiDelta(id,:), ['-' mk{mod(id-1,numel(mk))+1}], ...
        'LineWidth', lwWifi, 'MarkerSize', 6);
    hh.DisplayName = sprintf('Wi-Fi (Glaze Δ=%d dB)', deltaList(id));
end

% Glaze PER curves for each Δ (dashed)
for id = 1:numel(deltaList)
    hh = semilogy(snrVec, perGlzDelta(id,:), ['--' mk{mod(id-1,numel(mk))+1}], ...
        'LineWidth', lwGlz, 'MarkerSize', 6);
    hh.DisplayName = sprintf('Glaze PER (Δ=%d dB)', deltaList(id));
end

xlabel('SNR (dB)');
ylabel('PER');
title(sprintf('2x2 MIMO, Nsts=%d, MCS%d, %s | baseline + Wi-Fi(Δ) + Glaze(Δ)', ...
    Nsts, cfgHE.MCS, cfgHE.ChannelBandwidth));
legend('Location','best');

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
