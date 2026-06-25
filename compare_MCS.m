%% run_compare_MCS_WIFIplusGlaze_and_Glaze_PER_logY.m  (MATLAB R2024a)
% Two figures (log-y):
%   Fig1: Wi-Fi(+Glaze) PER vs SINR  (Y in log scale, min=1e-3)
%   Fig2: Glaze PER vs SINR          (Y in log scale, min=1e-3)
% Fixed: Delta_dB=1, Rb=20e3
% MCS: [0 1 2]
% Parallel: parpool + parfor

clear; clc; close all;

%% ===== Project path (ensure box0Simulation.m etc. are on path) =====
PROJECT_DIR = fileparts(mfilename('fullpath'));
addpath(genpath(PROJECT_DIR));

%% ===== Parallel pool =====
if isempty(gcp('nocreate'))
    parpool('local');
end

%% ===== Reproducibility =====
rng(1);

%% ===== Sweep settings =====
sinrVec = 0:3:18;       % SINR(dB)
maxNumPackets = 3000;
maxNumErrors  = 3000;

%% ===== Fixed Glaze params =====
delta_dB = 1;
Rb       = 20e3;

glzBase = struct;
glzBase.Enable      = true;
glzBase.Delta_dB    = delta_dB;
glzBase.Rb          = Rb;
glzBase.RateBits    = int8([1;1]);
glzBase.PayloadBits = int8(randi([0 1], 25, 1));   % 25 bits（与你现有 glazeBuildPacket 匹配）

%% ===== MIMO settings =====
Nt   = 2;
Nr   = 2;
Nsts = 2;

%% ===== MCS list =====
mcsList = [0 1 2];

%% ===== Results (rows: MCS, cols: SINR) =====
perWifiGlz = nan(numel(mcsList), numel(sinrVec));  % Wi-Fi(+Glaze) PER
perGlz     = nan(numel(mcsList), numel(sinrVec));  % Glaze PER

tAll = tic;

for im = 1:numel(mcsList)
    mcs = mcsList(im);

    % ---- Fit check (optional) ----
    cfgCheck = makeCfgHE(Nt, Nsts, mcs);
    [fits, needSamp, availSamp, Nhb] = glazeFitCheck(cfgCheck, glzBase);
    fprintf("[MCS=%d] Glaze fit check: fits=%d, needSamp=%d, availSamp=%d, Nhb=%d (Rb=%.0f)\n", ...
        mcs, fits, needSamp, availSamp, Nhb, glzBase.Rb);

    wRow = nan(1, numel(sinrVec));
    gRow = nan(1, numel(sinrVec));

    parfor ii = 1:numel(sinrVec)

        % --- HE config (inside parfor) ---
        cfgHE = makeCfgHE(Nt, Nsts, mcs);

        % --- TGax channel (inside parfor) ---
        tgax = makeTGaxChannel(cfgHE, Nt, Nr);

        % --- simParams (match your box0Simulation expectations) ---
        sp = struct;
        sp.Config          = cfgHE;
        sp.RandomSubstream = (im-1)*10000 + ii;
        sp.MaxNumPackets   = maxNumPackets;
        sp.MaxNumErrors    = maxNumErrors;

        sp.SNR             = sinrVec(ii);   % 扫描量（你这里用 SINR 也行）
        sp.Channel         = tgax;
        sp.Glaze           = glzBase;

        % fields accessed by box0Simulation printout (if any)
        sp.MCS                = mcs;
        sp.DelayProfile        = 'Model-D';
        sp.NumTransmitAntennas = Nt;
        sp.NumReceiveAntennas  = Nr;

        % ===== Run simulation =====
        out = box0Simulation(sp);

        wRow(ii) = out.packetErrorRate;        % Wi-Fi(+Glaze) PER
        gRow(ii) = out.glazePacketErrorRate;   % Glaze PER
    end

    perWifiGlz(im,:) = wRow;
    perGlz(im,:)     = gRow;
end

fprintf("Done. Total time = %.2f s\n", toc(tAll));

%% ====== Log-y display settings ======
PER_FLOOR = 1e-3;                     % 纵轴最小 10^-3
perWifiGlz_plot = max(perWifiGlz, PER_FLOOR);
perGlz_plot     = max(perGlz,     PER_FLOOR);

mk = {'o','s','d','^','v','>','<','p','h','x','+'};

%% ===================== Figure 1: Wi-Fi(+Glaze) PER vs SINR (log-y) =====================
figure; hold on; grid on;
for im = 1:numel(mcsList)
    mcs = mcsList(im);
    h = semilogy(sinrVec, perWifiGlz_plot(im,:), ['-' mk{mod(im-1,numel(mk))+1}], ...
        'LineWidth', 1.6, 'MarkerSize', 6);
    h.DisplayName = sprintf('Wi-Fi(+Glaze) PER, MCS=%d', mcs);
end
xlabel('SINR (dB)');
ylabel('PER (log scale)');
title(sprintf('Wi-Fi(+Glaze) PER vs SINR | Nt=%d Nr=%d Nsts=%d | \\Delta=%d dB, R_b=%.0f kbps', ...
    Nt, Nr, Nsts, delta_dB, Rb/1e3));
ylim([PER_FLOOR 1]);
set(gca,'YScale','log','YMinorGrid','on','YTick',10.^(-3:0));
legend('Location','best');

%% ===================== Figure 2: Glaze PER vs SINR (log-y) =====================
figure; hold on; grid on;
for im = 1:numel(mcsList)
    mcs = mcsList(im);
    h = semilogy(sinrVec, perGlz_plot(im,:), ['--' mk{mod(im-1,numel(mk))+1}], ...
        'LineWidth', 1.6, 'MarkerSize', 6);
    h.DisplayName = sprintf('Glaze PER, MCS=%d', mcs);
end
xlabel('SINR (dB)');
ylabel('PER (log scale)');
title(sprintf('Glaze PER vs SINR | Nt=%d Nr=%d Nsts=%d | \\Delta=%d dB, R_b=%.0f kbps', ...
    Nt, Nr, Nsts, delta_dB, Rb/1e3));
ylim([PER_FLOOR 1]);
set(gca,'YScale','log','YMinorGrid','on','YTick',10.^(-3:0));
legend('Location','best');

%% ===================== Local functions =====================
function cfgHE = makeCfgHE(Nt, Nsts, mcs)
    cfgHE = wlanHESUConfig;
    cfgHE.ChannelBandwidth = 'CBW20';
    cfgHE.MCS = mcs;
    cfgHE.APEPLength = 8000;      % bytes
    cfgHE.GuardInterval = 0.8;
    cfgHE.ChannelCoding = 'LDPC';
    cfgHE.NumTransmitAntennas = Nt;
    cfgHE.NumSpaceTimeStreams = Nsts;
end

function tgax = makeTGaxChannel(cfgHE, Nt, Nr)
    tgax = wlanTGaxChannel;
    setIfProp(tgax,'DelayProfile','Model-D');
    setIfProp(tgax,'ChannelBandwidth',cfgHE.ChannelBandwidth);
    setIfProp(tgax,'NumTransmitAntennas',Nt);
    setIfProp(tgax,'NumReceiveAntennas',Nr);
    setIfProp(tgax,'TransmitReceiveDistance',15);
    setIfProp(tgax,'LargeScaleFadingEffect','None');
    fs = wlanSampleRate(cfgHE);
    setIfProp(tgax,'SampleRate',fs);
    setIfProp(tgax,'PathGainsOutputPort',true);
    setIfProp(tgax,'NormalizeChannelOutputs',false);
end

function setIfProp(obj, propName, val)
    if isprop(obj, propName)
        obj.(propName) = val;
    end
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
