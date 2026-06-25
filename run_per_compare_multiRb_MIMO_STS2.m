%% run_per_compare_multiRb_MIMO_STS2.m
% 目的：
%   固定 Δ（衰减量），扫 Glaze 比特率 Rb，
%   画出：
%     - Wi-Fi baseline PER vs SNR
%     - Wi-Fi(+Glaze) PER vs SNR (different Rb)
%     - Glaze PER vs SNR (different Rb)
%
% 依赖文件（同目录或已加入 path）:
%   box0Simulation.m, glazeBuildPacket.m, glazeManchesterEncode.m, glazeDecode.m, ...
%
% 注意：
%   你的仿真框架目前是“每个 Wi-Fi PPDU 的 HE-Data 段内嵌 1 个 Glaze 包（若 fit）”。
%   若某个 Rb 不 fit，则只会嵌入前半段（后续 half-bit 不存在），Glaze PER 往往会很差（NoDetect/Mismatch）。
%
% Author: (based on your multidelta script)

clear; clc; close all;
rng(1);

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
maxNumErrors  = maxNumPackets;  % 保证每个 SNR 点跑满，便于公平对比

%% ===== Glaze params (FIX Delta, SWEEP Rb) =====
deltaFixed_dB = 3;   % <<< 固定衰减量 Δ（你可改成 1/2/3/4/6/8 等）

% 建议 RbList 里既包含你关心的点，也包含“fit”的点（否则 Glaze 会因为不完整包而很差）
% 你也可以直接改成你想要的一组，比如 [5e3 10e3 13e3 20e3 50e3 100e3]
RbList = [10e3 20e3 40e3 100e3];   % bps

glz = struct;
glz.Enable   = true;
glz.Delta_dB = deltaFixed_dB;
glz.Rb       = RbList(1);     % placeholder
glz.RateBits = int8([1;1]);   % header bits（你的 decode 用 Rb 入参，不靠 RateBits）
glz.PayloadBits = int8(randi([0 1], 25, 1)); % 25-bit payload（glazeBuildPacket 会 pad/clip 到 25）

%% ===== Fit check for each Rb =====
fitsRb   = false(1, numel(RbList));
needSamp = zeros(1, numel(RbList));
availSamp= zeros(1, numel(RbList));
NhbRb    = zeros(1, numel(RbList));

for ir = 1:numel(RbList)
    glzTmp = glz;
    glzTmp.Rb = RbList(ir);
    [fitsRb(ir), needSamp(ir), availSamp(ir), NhbRb(ir)] = glazeFitCheck(cfgHE, glzTmp);
    fprintf("FitCheck | Rb=%.0f bps | fits=%d | needSamp=%d | availSamp=%d | Nhb=%d\n", ...
        RbList(ir), fitsRb(ir), needSamp(ir), availSamp(ir), NhbRb(ir));
end

%% ===== Storage =====
perWiFiBase = zeros(1, numel(snrVec));
perWiFiRb   = zeros(numel(RbList), numel(snrVec));
perGlzRb    = zeros(numel(RbList), numel(snrVec));

%% ===== Run =====
for ii = 1:numel(snrVec)

    % ---- baseline sim params ----
    sp = struct;
    sp.Config = cfgHE;

    % 同一 SNR 下 baseline 与各 Rb 用同一个 substream，保证对比公平
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
    perWiFiBase(ii) = out0.packetErrorRate;

    % ---- with Glaze for each Rb ----
    for ir = 1:numel(RbList)
        glzTmp = glz;
        glzTmp.Rb = RbList(ir);

        sp2 = sp;
        sp2.Glaze = glzTmp;

        out1 = box0Simulation(sp2);

        perWiFiRb(ir, ii) = out1.packetErrorRate;
        perGlzRb(ir,  ii) = out1.glazePacketErrorRate;

        fprintf("SNR=%2d | Δ=%g dB | Rb=%8.0f | fit=%d | WiFi base PER=%.4f | WiFi(+Glz) PER=%.4f | Glz PER=%.4f\n", ...
            snrVec(ii), deltaFixed_dB, RbList(ir), fitsRb(ir), ...
            perWiFiBase(ii), perWiFiRb(ir,ii), perGlzRb(ir,ii));
    end
end

%% ===== Plot (log y-axis safe) =====
floorPER = 1/maxNumPackets;
axisMin  = 1e-3;

perWiFiBase_plot = max(perWiFiBase, floorPER);
perWiFiRb_plot   = max(perWiFiRb,   floorPER);
perGlzRb_plot    = max(perGlzRb,    floorPER);

mk = {'s','d','^','v','>','<','p','h','x','+'};

%% =========================
%  Figure 1: Wi-Fi PER only
%% =========================
figure; hold on;

semilogy(snrVec, perWiFiBase_plot, 'k-o', 'LineWidth', 1.6, 'MarkerSize', 6, ...
    'DisplayName','Wi-Fi baseline');

for ir = 1:numel(RbList)
    semilogy(snrVec, perWiFiRb_plot(ir,:), ['-' mk{mod(ir-1,numel(mk))+1}], ...
        'LineWidth', 1.2, 'MarkerSize', 6, ...
        'DisplayName', sprintf('Wi-Fi (Glaze \\Delta=%g dB, R_b=%.0f kbps)', deltaFixed_dB, RbList(ir)/1e3));
end

xlabel('SNR (dB)');
ylabel('Wi-Fi PER');
title(sprintf('Wi-Fi PER vs SNR | %dx%d MIMO, Nsts=%d, MCS%d, %s', ...
    Nt, Nr, Nsts, cfgHE.MCS, cfgHE.ChannelBandwidth));
legend('Location','best');
applyPERLogAxis(axisMin);

%% =========================
%  Figure 2: Glaze PER only
%% =========================
figure; hold on;

for ir = 1:numel(RbList)
    semilogy(snrVec, perGlzRb_plot(ir,:), ['-' mk{mod(ir-1,numel(mk))+1}], ...
        'LineWidth', 1.4, 'MarkerSize', 6, ...
        'DisplayName', sprintf('Glaze PER (\\Delta=%g dB, R_b=%.0f kbps)', deltaFixed_dB, RbList(ir)/1e3));
end

xlabel('SNR (dB)');
ylabel('Glaze PER');
title(sprintf('Glaze PER vs SNR | %dx%d MIMO, Nsts=%d, \\Delta=%g dB', ...
    Nt, Nr, Nsts, deltaFixed_dB));
legend('Location','best');
applyPERLogAxis(axisMin);

%% ===== local helpers =====
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
    ax = gca;
    set(ax,'YScale','log');

    grid(ax,'on');
    set(ax,'YMinorGrid','on');
    set(ax,'YMinorTick','on');
    set(ax,'GridLineStyle','-');
    set(ax,'MinorGridLineStyle',':');

    yt = [1e-3 1e-2 1e-1 1e0];
    set(ax,'YTick', yt);
    set(ax,'YTickLabel', {'10^{-3}','10^{-2}','10^{-1}','10^{0}'});
    ylim([axisMin 1]);
end
