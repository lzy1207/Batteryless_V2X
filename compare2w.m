%% run_per_and_success_compare_multidelta_MIMO_STS2.m
% Figure-1: Wi-Fi PER vs SNR (baseline + Wi-Fi(Δ))
% Figure-2: Glaze PER vs SNR (Glaze(Δ) only)
% Figure-3: Success packet counts vs SNR (Wi-Fi baseline/Wi-Fi(Δ)/Glaze(Δ))
%
% Put this script in the same folder with:
%   box0Simulation.m, glazeBuildPacket.m, glazeManchesterEncode.m, glazeDecode.m, ...
% or add that folder to MATLAB path.

clear; clc; close all;
rng(1); % 固定随机数，便于论文复现

%% ===== MIMO settings =====
Nt   = 2;
Nr   = 2;
Nsts = 2;

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
snrVec = -12:3:9;

maxNumPackets = 100;
maxNumErrors  = maxNumPackets;   % 关键：保证每个点都跑满 maxNumPackets，便于“成功包个数”对比

%% ===== Glaze params =====
deltaList = [1 2 3];

glz = struct;
glz.Enable   = true;
glz.Delta_dB = deltaList(1);     % placeholder, will override in loop
glz.Rb       = 20e3;
glz.RateBits = int8([1;1]);
glz.PayloadBits = int8(randi([0 1], 25, 1));

% Fit check（Δ 不影响是否 fit，只看 Rb/包长/HE-Data）
[fits, needSamp, availSamp, Nhb] = glazeFitCheck(cfgHE, glz);
fprintf("Glaze fit check: fits=%d, needSamp=%d, availSamp=%d, Nhb=%d (Rb=%.0f)\n", ...
    fits, needSamp, availSamp, Nhb, glz.Rb);
if ~fits
    warning("Glaze packet does NOT fit into HE-Data. 低 SNR 下可能出现 Short/NoDetect。");
end

%% ===== Storage =====
% PER
perWiFiBase   = zeros(1, numel(snrVec));
perWiFiDelta  = zeros(numel(deltaList), numel(snrVec));
perGlzDelta   = zeros(numel(deltaList), numel(snrVec));

% Success counts
succWiFiBase  = zeros(1, numel(snrVec));
succWiFiDelta = zeros(numel(deltaList), numel(snrVec));
succGlzDelta  = zeros(numel(deltaList), numel(snrVec));

%% ===== Run =====
for ii = 1:numel(snrVec)

    % ---- baseline sim params ----
    sp = struct;
    sp.Config = cfgHE;

    % 同一 SNR 下 baseline 和各 Δ 用同一个 substream（保证对比公平）
    sp.RandomSubstream = ii;

    sp.MaxNumPackets = maxNumPackets;
    sp.MaxNumErrors  = maxNumErrors;
    sp.SNR = snrVec(ii);
    sp.Channel = clone(tgax);

    sp.DelayProfile = string(tgax.DelayProfile);
    sp.NumTransmitAntennas = Nt;
    sp.NumReceiveAntennas  = Nr;
    sp.MCS = cfgHE.MCS;

    % ---- baseline ----
    out0 = box0Simulation(sp);
    perWiFiBase(ii)  = out0.packetErrorRate;
    succWiFiBase(ii) = out0.numPkt - nansum(out0.perStore(1:out0.numPkt));

    % ---- with Glaze for each Δ ----
    for id = 1:numel(deltaList)
        glzTmp = glz;
        glzTmp.Delta_dB = deltaList(id);

        sp2 = sp;
        sp2.Glaze = glzTmp;

        out1 = box0Simulation(sp2);

        perWiFiDelta(id, ii)  = out1.packetErrorRate;
        perGlzDelta(id,  ii)  = out1.glazePacketErrorRate;

        succWiFiDelta(id, ii) = out1.numPkt - nansum(out1.perStore(1:out1.numPkt));
        succGlzDelta(id,  ii) = out1.glzSuccessCnt;   % 直接用 box0Simulation 统计的 Success

        fprintf("SNR=%2d | Δ=%d dB | WiFi base PER=%.4f | WiFi(+Glz) PER=%.4f | Glz PER=%.4f | WiFi succ=%d | Glz succ=%d\n", ...
            snrVec(ii), deltaList(id), perWiFiBase(ii), perWiFiDelta(id,ii), perGlzDelta(id,ii), ...
            succWiFiDelta(id,ii), succGlzDelta(id,ii));
    end
end

%% ============================================================
%  关键改动：对数纵轴必须避免 PER=0（log(0) 不存在）
%  用统计意义下界 floorPER = 1/maxNumPackets（比 eps 更合理）
%% ============================================================
%  关键：对数纵轴 + 固定刻度显示为 10^0,10^-1,10^-2,10^-3（如截图）
%% ============================================================
floorPER = 1/maxNumPackets;   % PER=0 时用于夹紧（统计意义下界）
axisMin  = 1e-3;     % 让坐标下限略低于 1/Npkt（截图中约 5e-4）

perWiFiBase_plot  = max(perWiFiBase, floorPER);
perWiFiDelta_plot = max(perWiFiDelta, floorPER);
perGlzDelta_plot  = max(perGlzDelta,  floorPER);

%% =========================
%  Figure 1: Wi-Fi PER only
%% =========================
figure; hold on;

semilogy(snrVec, perWiFiBase_plot, 'k-o', 'LineWidth', 1.6, 'MarkerSize', 6, ...
    'DisplayName','Wi-Fi baseline');

mk = {'s','d','^','v','>','<','p','h','x','+'};
for id = 1:numel(deltaList)
    semilogy(snrVec, perWiFiDelta_plot(id,:), ['-' mk{mod(id-1,numel(mk))+1}], ...
        'LineWidth', 1.2, 'MarkerSize', 6, ...
        'DisplayName', sprintf('Wi-Fi (Glaze Δ=%d dB)', deltaList(id)));
end

xlabel('SNR (dB)');
ylabel('Wi-Fi PER');
title(sprintf('Wi-Fi PER vs SNR | %dx%d MIMO, Nsts=%d, MCS%d, %s', ...
    Nt, Nr, Nsts, cfgHE.MCS, cfgHE.ChannelBandwidth));
legend('Location','best');

applyPERLogAxis(axisMin);   % <<<<<< 关键：设置对数刻度样式（与截图一致）

%% =========================
%  Figure 2: Glaze PER only
%% =========================
figure; hold on;

for id = 1:numel(deltaList)
    semilogy(snrVec, perGlzDelta_plot(id,:), ['-' mk{mod(id-1,numel(mk))+1}], ...
        'LineWidth', 1.4, 'MarkerSize', 6, ...
        'DisplayName', sprintf('Glaze PER (Δ=%d dB)', deltaList(id)));
end

xlabel('SNR (dB)');
ylabel('Glaze PER');
title(sprintf('Glaze PER vs SNR | %dx%d MIMO, Nsts=%d, R_b=%.0f kbps', ...
    Nt, Nr, Nsts, glz.Rb/1e3));
legend('Location','best');

applyPERLogAxis(axisMin);   % <<<<<< 同样的对数刻度样式

%% ==========================================
%  Figure 3: Success packet count vs SNR
%% ==========================================
figure; grid on; hold on;

% Wi-Fi baseline success (solid thick)
plot(snrVec, succWiFiBase, 'k-o', 'LineWidth', 1.6, 'MarkerSize', 6, ...
    'DisplayName','Wi-Fi success (baseline)');

% Wi-Fi success with Glaze (solid)
for id = 1:numel(deltaList)
    plot(snrVec, succWiFiDelta(id,:), ['-' mk{mod(id-1,numel(mk))+1}], ...
        'LineWidth', 1.2, 'MarkerSize', 6, ...
        'DisplayName', sprintf('Wi-Fi success (Δ=%d dB)', deltaList(id)));
end

% Glaze success (dashed)
for id = 1:numel(deltaList)
    plot(snrVec, succGlzDelta(id,:), ['--' mk{mod(id-1,numel(mk))+1}], ...
        'LineWidth', 1.2, 'MarkerSize', 6, ...
        'DisplayName', sprintf('Glaze success (Δ=%d dB)', deltaList(id)));
end

xlabel('SNR (dB)');
ylabel(sprintf('Successful packets (out of %d)', maxNumPackets));
title(sprintf('Success packet count vs SNR | %dx%d MIMO, Nsts=%d', Nt, Nr, Nsts));
legend('Location','best');
ylim([0 maxNumPackets]);

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


function applyPERLogAxis(axisMin)
% 统一把 PER 图的对数纵轴格式固定成：10^0,10^-1,10^-2,10^-3（如截图）
    ax = gca;

    set(ax,'YScale','log');

    % 主/次网格（截图风格：主网格实线，次网格点线）
    grid(ax,'on');
    set(ax,'YMinorGrid','on');
    set(ax,'YMinorTick','on');
    set(ax,'GridLineStyle','-');
    set(ax,'MinorGridLineStyle',':');

    % 固定只显示这四个刻度
    yt = [1e-3 1e-2 1e-1 1e0];
    set(ax,'YTick', yt);
    set(ax,'YTickLabel', {'10^{-3}','10^{-2}','10^{-1}','10^{0}'});

    % 纵轴范围：下限略低于 1e-3，与你截图一致
    ylim([axisMin 1]);
end
