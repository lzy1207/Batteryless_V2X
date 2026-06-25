%% run_per_and_power_compare.m SISO
clear; clc; close all;

%% 1) Wi-Fi PHY config
cfgHE = wlanHESUConfig;
cfgHE.ChannelBandwidth = 'CBW20';   % <- 带宽
cfgHE.MCS = 0;                      % <- MCS（注意：如果你后面做 mcs 扫描，这里会被覆盖）
cfgHE.APEPLength = 5000;            % <- APEP长度（bytes，过大可能触发 TxTime 上限报错）
cfgHE.GuardInterval = 0.8;          % <- GI
cfgHE.NumTransmitAntennas = 1;
cfgHE.NumSpaceTimeStreams = 1;

%% --- Cap APEPLength to satisfy PPDU TxTime limit (avoid validateMCSLengthTxTime error) ---
%% cfgHE.APEPLength = 8000;  % 你想要的初值
%%cfgHE = capApeLengthToValid(cfgHE);

%%function cfg = capApeLengthToValid(cfg)
    % wlanFieldIndices 会触发 validateConfig；不合法就减小 APEPLength
  %%  while true
   %%     try
    %        wlanFieldIndices(cfg); % only for validation
    %        break;
    %    catch
    %        cfg.APEPLength = max(1, floor(cfg.APEPLength*0.95)); % 每次减 5%
     %       if cfg.APEPLength <= 1
     %           rethrow(lasterror);
     %       end
     %   end
  %  end
%end 

cfgHE.NumTransmitAntennas = 1;
cfgHE.NumSpaceTimeStreams = 1;
cfgHE.GuardInterval = 0.8;

%% 2) TGax channel (simple)
tgax = wlanTGaxChannel;
tgax.DelayProfile = 'Model-D';
tgax.ChannelBandwidth = cfgHE.ChannelBandwidth;
tgax.NumTransmitAntennas = cfgHE.NumTransmitAntennas;
tgax.NumReceiveAntennas  = 1;
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
glz.Delta_dB = 2;
glz.Rb       = 11e3;                % ★关键：从 5 kbps 改成 10 kbps
glz.RateBits = int8([1;1]);
glz.PayloadBits = int8(randi([0 1], 25, 1));

% ---- 一步自检：Glaze 包是否能完整放进 HE-Data ----
[fits, needSamp, availSamp, Nhb] = glazeFitCheck(cfgHE, glz);
fprintf("Glaze fit check: fits=%d, needSamp=%d, availSamp=%d, Nhb=%d (Rb=%.0f)\n", ...
    fits, needSamp, availSamp, Nhb, glz.Rb);

if ~fits
    warning("Glaze packet does NOT fit in a single PPDU HE-Data. Increase Rb or use multi-PPDU burst overlay.");
end

%% 5) Run baseline & Glaze
perBase = zeros(size(snrVec));
perWiFiWithGlaze = zeros(size(snrVec));
perGlaze = zeros(size(snrVec));

for i = 1:numel(snrVec)
    % Baseline
    sp = struct;
    sp.Config = cfgHE;
    sp.RandomSubstream = 1;
    sp.MaxNumPackets = maxNumPackets;
    sp.MaxNumErrors = maxNumErrors;
    sp.SNR = snrVec(i);
    sp.Channel = clone(tgax);
    sp.DelayProfile = string(tgax.DelayProfile);
    sp.NumTransmitAntennas = cfgHE.NumTransmitAntennas;
    sp.NumReceiveAntennas  = tgax.NumReceiveAntennas;
    sp.MCS = cfgHE.MCS;
    sp.Glaze = struct('Enable', false);

    out0 = box0Simulation(sp);
    perBase(i) = out0.packetErrorRate;

    % With Glaze
    sp2 = sp;
    sp2.Glaze = glz;
    out1 = box0Simulation(sp2);
    perWiFiWithGlaze(i) = out1.packetErrorRate;
    fprintf("SNR=%2d dB | Glaze PER=%.2f | success=%d, mismatch=%d, nodetect=%d | meanCorr=%.3f | needSamp~%.0f availSamp~%.0f\n", ...
    snrVec(i), out1.glazePacketErrorRate, out1.glzSuccessCnt, out1.glzMismatchCnt, out1.glzNoDetectCnt, ...
    mean(out1.glzCorrPeakStore,'omitnan'), mean(out1.glzNeedSampStore,'omitnan'), mean(out1.glzAvailSampStore,'omitnan'));

    perGlaze(i) = out1.glazePacketErrorRate;
end

%% 6) Plot PER curves
figure;
semilogy(snrVec, perBase, 'o-'); hold on;
semilogy(snrVec, perWiFiWithGlaze, 's-');
semilogy(snrVec, perGlaze, '^-');
grid on;
xlabel('SNR (dB)');
ylabel('Packet Error Rate');
legend('Wi-Fi baseline PER','Wi-Fi PER with Glaze','Glaze packet error rate');
title('PER comparison: legacy Wi-Fi vs Glaze overlay');

%% 7) Power comparison (TX waveform power + RX power consumption)
% TX average power: compute once from one waveform
txPSDU  = randi([0 1], cfgHE.APEPLength*8, 1, 'int8');
txOrigM = wlanWaveformGenerator(txPSDU, cfgHE);
ind = wlanFieldIndices(cfgHE);

pktG   = glazeBuildPacket(glz.PayloadBits, glz.RateBits);
halfLv = glazeManchesterEncode(pktG.bits);
[txGlzM, ~] = glazeEmbed(txOrigM, halfLv, wlanSampleRate(cfgHE), glz.Rb, glz.Delta_dB, ind.HEData);

Ptx_orig = mean(abs(txOrigM(:)).^2);
Ptx_glz  = mean(abs(txGlzM(:)).^2);

% RX power consumption:
% Glaze receiver power from paper (example numbers): 50µW listen, 800µW decode@5kbps :contentReference[oaicite:10]{index=10}
Pglaze_listen_uW = 50;
Pglaze_decode_uW = 800;  % at 5kbps (示例)，你若用 10kbps 可按实现假设调整

% Legacy Wi-Fi RX power: 这里需要你用 datasheet/测量值填（mW级~百mW级都常见）
Pwifi_rx_mW = 200; % <-- 你替换成真实值

figure;
subplot(1,2,1);
bar([10*log10(Ptx_orig), 10*log10(Ptx_glz)]);
grid on;
set(gca,'XTickLabel',{'Original','Glazed'});
ylabel('Avg TX power (dB, relative units)');
title('Transmit waveform average power');

subplot(1,2,2);
bar([Pwifi_rx_mW*1e3, Pglaze_listen_uW, Pglaze_decode_uW]); % 转成 µW
grid on;
set(gca,'XTickLabel',{'Wi-Fi RX (set)','Glaze listen','Glaze decode'});
ylabel('Power (µW)');
title('Receiver power comparison');




function cfg = capApeLengthToValid(cfg)
% 把 APEPLength 缩小到 wlanFieldIndices 不报错为止（满足 TxTime 上限）
while true
    try
        wlanFieldIndices(cfg); % triggers validateConfig internally
        break;
    catch
        cfg.APEPLength = max(1, floor(cfg.APEPLength*0.98)); % 每次减 2%
        if cfg.APEPLength <= 1
            rethrow(lasterror);
        end
    end
end
end

function [fits, needSamp, availSamp, Nhb] = glazeFitCheck(cfgHE, glz)
% 检查：完整 Glaze 包（Manchester 后）需要多少采样点，HE-Data 有多少采样点
Fs  = wlanSampleRate(cfgHE);
ind = wlanFieldIndices(cfgHE);

pktG   = glazeBuildPacket(glz.PayloadBits, glz.RateBits);
halfLv = glazeManchesterEncode(pktG.bits);

Nhb = max(1, round(Fs/(2*glz.Rb)));            % samples per half-bit
needSamp  = numel(halfLv) * Nhb;              % 需要的采样点
availSamp = ind.HEData(2) - ind.HEData(1) + 1;% HE-Data 可用采样点

fits = needSamp <= availSamp;
end
