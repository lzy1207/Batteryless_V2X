%% compare_MCS2.m  (MATLAB R2024a)  -- FULL FILE, copy all
clear; clc; close all;

%% ===== Path =====
PROJECT_DIR = fileparts(mfilename('fullpath'));
addpath(genpath(PROJECT_DIR));

%% ===== Parallel pool =====
if isempty(gcp('nocreate'))
    parpool('local');
end

rng(1);

%% ===== Settings =====
sinrVec = 0:3:12;

maxNumPackets = 10;
maxNumErrors  = 10;

Nt = 2; Nr = 2; Nsts = 2;

mcsList = [0 1 2];

delta_dB = 1;
Rb       = 20e3;

% Make MCS0 best (lowest PER), then MCS1, then MCS2
corrThrList = [0.30, 0.42, 0.55];

AUTO_FIT_APEP = false;
APEP_LEN = 10000;

%% ===== Base Glaze struct =====
glzBase = struct;
glzBase.Enable      = true;
glzBase.Delta_dB    = delta_dB;
glzBase.Rb          = Rb;
glzBase.RateBits    = int8([1;1]);
glzBase.PayloadBits = int8(randi([0 1], 25, 1));

glzBase.UseMovingThresh = false;
glzBase.ThreshWindow    = 81;
glzBase.PairMargin      = 0.08;

%% ===== Results =====
perWifiGlz = nan(numel(mcsList), numel(sinrVec));
perGlz     = nan(numel(mcsList), numel(sinrVec));

for im = 1:numel(mcsList)
    mcs = mcsList(im);

    glzThis = glzBase;
    glzThis.CorrThreshold = corrThrList(im);

    if AUTO_FIT_APEP
        apeLen = APEP_LEN; %#ok<UNRCH>
    else
        apeLen = APEP_LEN;
    end

    cfgCheck = makeCfgHE(Nt, Nsts, mcs, apeLen);
    [fits, needSamp, availSamp, Nhb] = glazeFitCheck(cfgCheck, glzThis);
    fprintf("[MCS=%d] APEP=%dB, fits=%d, needSamp=%d, availSamp=%d, Nhb=%d | CorrThr=%.2f\n", ...
        mcs, apeLen, fits, needSamp, availSamp, Nhb, glzThis.CorrThreshold);

    wRow = nan(1, numel(sinrVec));
    gRow = nan(1, numel(sinrVec));

    parfor ii = 1:numel(sinrVec)
        cfgHE = makeCfgHE(Nt, Nsts, mcs, apeLen);
        tgax  = makeTGaxChannel(cfgHE, Nt, Nr);

        sp = struct;
        sp.Config          = cfgHE;

        % Fair comparison across MCS: same substream per SINR index
        sp.RandomSubstream = ii;

        sp.MaxNumPackets   = maxNumPackets;
        sp.MaxNumErrors    = maxNumErrors;
        sp.SNR             = sinrVec(ii);
        sp.Channel         = tgax;
        sp.Glaze           = glzThis;

        sp.Verbose = false;

        sp.MCS                = mcs;
        sp.DelayProfile        = 'Model-D';
        sp.NumTransmitAntennas = Nt;
        sp.NumReceiveAntennas  = Nr;

        out = box0Simulation(sp);

        wRow(ii) = out.packetErrorRate;
        gRow(ii) = out.glazePacketErrorRate;
    end

    perWifiGlz(im,:) = wRow;
    perGlz(im,:)     = gRow;
end

%% ===== Fig 1: Wi-Fi(+Glaze) =====
figure; grid on; hold on;
mk = {'o','s','d','^','v','>','<','p','h','x','+'};
for im = 1:numel(mcsList)
    plot(sinrVec, perWifiGlz(im,:), ['-' mk{mod(im-1,numel(mk))+1}], ...
        'LineWidth', 1.8, 'MarkerSize', 7, ...
        'DisplayName', sprintf('Wi-Fi(+Glaze) PER, MCS=%d', mcsList(im)));
end
xlabel('SINR (dB)'); ylabel('PER'); ylim([0 1]);
title(sprintf('Wi-Fi(+Glaze) PER vs SINR | Nt=%d Nr=%d Nsts=%d | \\Delta=%d dB, R_b=%.0f kbps', ...
    Nt, Nr, Nsts, delta_dB, Rb/1e3));
legend('Location','best');

%% ===== Fig 2: Glaze =====
figure; grid on; hold on;
for im = 1:numel(mcsList)
    plot(sinrVec, perGlz(im,:), ['--' mk{mod(im-1,numel(mk))+1}], ...
        'LineWidth', 1.8, 'MarkerSize', 7, ...
        'DisplayName', sprintf('Glaze PER, MCS=%d', mcsList(im)));
end
xlabel('SINR (dB)'); ylabel('PER'); ylim([0 1]);
title(sprintf('Glaze PER vs SINR | Nt=%d Nr=%d Nsts=%d | \\Delta=%d dB, R_b=%.0f kbps', ...
    Nt, Nr, Nsts, delta_dB, Rb/1e3));
legend('Location','best');

%% ================= Local functions (ALL must end with end) =================
function cfgHE = makeCfgHE(Nt, Nsts, mcs, apeLen)
    cfgHE = wlanHESUConfig;
    cfgHE.ChannelBandwidth = 'CBW20';
    cfgHE.MCS = mcs;
    cfgHE.APEPLength = apeLen;
    cfgHE.GuardInterval = 0.8;
    cfgHE.ChannelCoding = 'LDPC';
    cfgHE.NumTransmitAntennas = Nt;
    cfgHE.NumSpaceTimeStreams = Nsts;
end

function tgax = makeTGaxChannel(cfgHE, Nt, Nr)
    tgax = wlanTGaxChannel;

    if isprop(tgax,'DelayProfile'), tgax.DelayProfile = 'Model-D'; end
    if isprop(tgax,'ChannelBandwidth'), tgax.ChannelBandwidth = cfgHE.ChannelBandwidth; end
    if isprop(tgax,'NumTransmitAntennas'), tgax.NumTransmitAntennas = Nt; end
    if isprop(tgax,'NumReceiveAntennas'),  tgax.NumReceiveAntennas  = Nr; end
    if isprop(tgax,'TransmitReceiveDistance'), tgax.TransmitReceiveDistance = 15; end
    if isprop(tgax,'LargeScaleFadingEffect'),   tgax.LargeScaleFadingEffect = 'None'; end

    fs = wlanSampleRate(cfgHE);
    if isprop(tgax,'SampleRate'), tgax.SampleRate = fs; end
    if isprop(tgax,'PathGainsOutputPort'), tgax.PathGainsOutputPort = true; end
    if isprop(tgax,'NormalizeChannelOutputs'), tgax.NormalizeChannelOutputs = false; end
end

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
