%% run_per_compare_MCS_delta3_Rb20k_parallel.m
% Compare PER vs SINR for different MCS (0/2/4)
% Curves:
%   1) Wi-Fi(+Glaze) PER
%   2) Glaze PER
% Fixed:
%   Delta_dB = 3, Rb = 20e3
% Parallel:
%   parpool + parfor

clear; clc; close all;

%% ========== Path (ensure all required .m files are visible) ==========
THIS_DIR = fileparts(mfilename('fullpath'));
addpath(THIS_DIR);  % 如果脚本与box0Simulation等在同一目录就够了
% 若你的函数在其他目录，把那一层 addpath('xxx') 加上即可

%% ========== Parallel pool ==========
if isempty(gcp('nocreate'))
    parpool('local');   % 默认使用本机可用 worker
end

%% ========== Reproducibility ==========
rng(1);  % 固定 Glaze payload 等随机量

%% ========== MIMO settings ==========
Nt   = 2;
Nr   = 2;
Nsts = 2;

%% ========== Sweep settings ==========
sinrVec = 0:2:20;        % 横坐标：SINR(dB)（这里仍由 box0Simulation 的 SNR 参数驱动）
maxNumPackets = 100;     % 每个点最多仿真包数（可加大更平滑）
maxNumErrors  = 100;      % 每个点最多错误数（可加大更平滑）

%% ========== Glaze params (fixed) ==========
delta_dB = 3;
Rb       = 20e3;

glzBase = struct;
glzBase.Enable      = true;
glzBase.Delta_dB    = delta_dB;
glzBase.Rb          = Rb;
glzBase.RateBits    = int8([1;1]);
glzBase.PayloadBits = int8(randi([0 1], 25, 1));   % 25 bits (glazeBuildPacket 内部也会截断/补零到25)

%% ========== MCS list ==========
mcsList = [0 2 4];

% results: rows=MCS, cols=SINR points
perWifiGlz = nan(numel(mcsList), numel(sinrVec));
perGlz     = nan(numel(mcsList), numel(sinrVec));

%% ========== Main loop over MCS ==========
tAll = tic;

for im = 1:numel(mcsList)
    mcs = mcsList(im);

    % ---- Fit check (NOTE: HE-Data length depends on MCS for fixed APEP) ----
    cfgCheck = makeCfgHE(Nt, Nsts, mcs);
    [fits, needSamp, availSamp, Nhb] = glazeFitCheck(cfgCheck, glzBase);
    fprintf("[MCS=%d] Glaze fit check: fits=%d, needSamp=%d, availSamp=%d, Nhb=%d (Rb=%.0f)\n", ...
        mcs, fits, needSamp, availSamp, Nhb, glzBase.Rb);

    if ~fits
        warning("[MCS=%d] Glaze 可能无法完整塞入 HE-Data（会发生截断/不完整叠加），PER 可能显著变差。", mcs);
    end

    % local sliced vectors for parfor
    wRow = nan(1, numel(sinrVec));
    gRow = nan(1, numel(sinrVec));

    % ---- Parallel sweep over SINR ----
    parfor ii = 1:numel(sinrVec)

        % Create cfgHE inside parfor (IMPORTANT: box0Simulation 会修改 cfgHE 的 SpatialMapping 等)
        cfgHE = makeCfgHE(Nt, Nsts, mcs);

        % TGax channel (create inside parfor; do NOT share handle across workers)
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

        % Build simParams
        sp = struct;
        sp.Config = cfgHE;

        % 同一 SINR 点下：不同MCS用相同 substream 索引，有利于公平对比
        sp.RandomSubstream = ii;

        sp.MaxNumPackets = maxNumPackets;
        sp.MaxNumErrors  = maxNumErrors;
        sp.SNR = sinrVec(ii);     % 这里仍使用 box0Simulation 的 SNR 字段驱动
        sp.Channel = tgax;

        % Glaze overlay
        sp.Glaze = glzBase;

        out = box0Simulation(sp);

        wRow(ii) = out.packetErrorRate;        % Wi-Fi(+Glaze) PER
        gRow(ii) = out.glazePacketErrorRate;   % Glaze PER
    end

    perWifiGlz(im,:) = wRow;
    perGlz(im,:)     = gRow;
end

fprintf("Done. Total time = %.2f s\n", toc(tAll));

%% ========== Plot ==========
figure; grid on; hold on;

mk = {'o','s','d','^','v','>','<','p','h','x','+'};

% Wi-Fi(+Glaze): solid
for im = 1:numel(mcsList)
    mcs = mcsList(im);
    h = semilogy(sinrVec, perWifiGlz(im,:), ['-' mk{mod(im-1,numel(mk))+1}], ...
        'LineWidth', 1.6, 'MarkerSize', 6);
    h.DisplayName = sprintf('Wi-Fi(+Glaze) PER, MCS=%d', mcs);
end

% Glaze PER: dashed
for im = 1:numel(mcsList)
    mcs = mcsList(im);
    h = semilogy(sinrVec, perGlz(im,:), ['--' mk{mod(im-1,numel(mk))+1}], ...
        'LineWidth', 1.6, 'MarkerSize', 6);
    h.DisplayName = sprintf('Glaze PER, MCS=%d', mcs);
end

xlabel('SINR (dB)');
ylabel('PER');
title(sprintf('PER vs SINR | \\Delta=%d dB, R_b=%.0f kbps | Nt=%d Nr=%d Nsts=%d', ...
    delta_dB, Rb/1e3, Nt, Nr, Nsts));
legend('Location','best');

%% ===== Local helper: create HE config =====
function cfgHE = makeCfgHE(Nt, Nsts, mcs)
    cfgHE = wlanHESUConfig;
    cfgHE.ChannelBandwidth = 'CBW20';
    cfgHE.MCS = mcs;
    cfgHE.APEPLength = 8000;        % bytes（按你之前设定）
    cfgHE.GuardInterval = 0.8;
    cfgHE.ChannelCoding = 'LDPC';

    cfgHE.NumTransmitAntennas = Nt;
    cfgHE.NumSpaceTimeStreams = Nsts;
end

%% ===== Local helper: Glaze fit check =====
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
