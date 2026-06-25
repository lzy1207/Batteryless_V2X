%% demo_plot_wifi_vs_glaze_waveform.m
clear; clc; close all;

%% 1) HE-SU 配置（你也可以换成你自己的 cfgHE）
cfgHE = wlanHESUConfig;
cfgHE.ChannelBandwidth = 'CBW20';
cfgHE.MCS = 0;                 % 低 MCS：包更长，便于容纳 Glaze 比特
cfgHE.APEPLength = 8000;       % bytes：加长包时长（便于演示）
cfgHE.NumTransmitAntennas = 1;
cfgHE.NumSpaceTimeStreams = 1;
cfgHE.GuardInterval = 0.8;

fs  = wlanSampleRate(cfgHE);
ind = wlanFieldIndices(cfgHE);

% 生成 Wi-Fi PSDU 与时域波形
psduLen = cfgHE.APEPLength;                        % bytes
txPSDU  = randi([0 1], psduLen*8, 1, 'int8');
txOrigM = wlanWaveformGenerator(txPSDU, cfgHE);
txOrig  = txOrigM(:,1);

%% 2) 构造 Glaze 数据并叠加（只叠加到 HE-Data 段）
glz.Enable   = true;
glz.Delta_dB = 4;            % 论文常用 4/6/8 dB 评估失真影响 :contentReference[oaicite:3]{index=3}
glz.Rb       = 10e3;         % 10 kbps（论文原型上限）:contentReference[oaicite:4]{index=4}

% Glaze 包结构：STF(9) + LTF(13 Barker) + Data(<=25)  :contentReference[oaicite:5]{index=5}
payloadBits = randi([0 1], 25, 1, 'int8');
rateBits    = [1;1];         % 例：11 -> 10kbps（论文举例：00/01/10/11 对应不同速率）:contentReference[oaicite:6]{index=6}
pktG        = glazeBuildPacket(payloadBits, rateBits);
halfLv      = glazeManchesterEncode(pktG.bits);

% 只在 HE-Data 施加 Glaze（不碰前导，避免破坏 Wi-Fi 同步/估计）
[txGlazeM, ginfo] = glazeEmbed(txOrigM, halfLv, fs, glz.Rb, glz.Delta_dB, ind.HEData);
txGlaze = txGlazeM(:,1);

%% 3) 时域包络对比
t = (0:numel(txOrig)-1).' / fs * 1e3; % ms

% 平滑（模拟包络检波+低通，窗口取 half-bit 的 1/10 左右）
Nhb = ginfo.Nhb;
L   = max(1, round(Nhb/10));
env0 = movmean(abs(txOrig),  L);
env1 = movmean(abs(txGlaze), L);

figure;
plot(t, env0); hold on;
plot(t, env1);
grid on;
xlabel('Time (ms)'); ylabel('Smoothed envelope (arb.)');
legend('Wi-Fi original','Wi-Fi with Glaze');
title('Envelope comparison (original vs Glazed)');

% 放大 HE-Data 开头的一小段，观察 Glaze 的幅度“台阶/跳变”
s0 = ind.HEData(1);
zoomSamp = min(round(2e-3*fs), numel(txOrig)-s0); % 2ms
xlim([t(s0) t(s0+zoomSamp)]);

%% 4) 频谱对比（PSD）
figure;
pwelch(txOrig,  [], [], [], fs, 'centered'); hold on;
pwelch(txGlaze, [], [], [], fs, 'centered');
grid on; legend('Original','Glazed');
title('PSD comparison');

%% 5) 发射平均功率（用于后续功率对比图）
P0 = mean(abs(txOrig).^2);
P1 = mean(abs(txGlaze).^2);
fprintf('Avg TX power ratio (Glazed/Original) = %.2f dB\n', 10*log10(P1/P0));
