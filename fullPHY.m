%% mcs 0
% ---- Ensure helper files visible to workers ----
thisDir = fileparts(mfilename('fullpath'));
addpath(genpath(thisDir));

pool = gcp('nocreate');
if ~isempty(pool)
    delete(pool);          % 路径变更后建议重启并行池
end
parpool('Processes');      % 或者 parpool; 用你现在的 profile

clear all
tStart = tic;% Simulation Parameters
mcs = [0]; % Vector of MCS to simulate between 0 and 11
numTxRx = [1 1]; % Matrix of MIMO schemes, each row is [numTx numRx]
Nsts = 1; % Number of space-time streams
chan = "Model-D"; % String array of delay profiles to simulate
maxNumPackets = 1e2; % The maximum number of packets at an SNR point
maxnumberrors = maxNumPackets;  % The maximum number of packet errors at an SNR point

% Fixed PHY configuration for all simulations
cfgHE = wlanHESUConfig;
cfgHE.ChannelBandwidth = 'CBW20'; % Channel bandwidth
bandwidth = cfgHE.ChannelBandwidth;
cfgHE.APEPLength = 1000;          % Payload length in bytes
cfgHE.ChannelCoding = 'LDPC';     % Channel coding


% Generate simParams (one entry per SNR point)
simParams0 = getBox0SimParams(chan,numTxRx,mcs,cfgHE,maxnumberrors,maxNumPackets,Nsts);
snrs = [simParams0.SNR];

%% ===== Glaze params (按你当前实验参数写) =====
glz = struct;
glz.Enable     = true;
glz.Delta_dB   = 8;                 % 你说的 Δ=8
glz.Rb         = 11e3;              % Rb≈11k
glz.RateBits   = int8([1;1]);
glz.PayloadBits= int8(randi([0 1], 25, 1));  % 例子：25 bits payload（你可换成固定序列）

% ---- baseline & glaze 两套 simParams ----
simParamsBase = simParams0;


% ---- 合并，一次 parfor 跑完 ----
simParamsAll = [simParamsBase simParamsGlz];
resultsAll = cell(1,numel(simParamsAll));
parfor isim = 1:numel(simParamsAll)
    resultsAll{isim} = box0Simulation(simParamsAll(isim));
end

% ---- 拆回两套结果 ----
N0 = numel(simParams0);
resultsBase = resultsAll(1:N0);
resultsGlz  = resultsAll(N0+1:end);

%% ===== 画你要的三条曲线 =====
snrVec = [simParamsBase.SNR];
[snrVec, ord] = sort(snrVec);
resultsBase = resultsBase(ord);
resultsGlz  = resultsGlz(ord);

perBase = cellfun(@(r) r.packetErrorRate, resultsBase);
perWiFiWithGlz = cellfun(@(r) r.packetErrorRate, resultsGlz);

% glazePacketErrorRate 这个字段要求你的 box0Simulation 里有统计输出
perGlz = nan(size(perBase));
for i = 1:numel(resultsGlz)
    if isfield(resultsGlz{i}, 'glazePacketErrorRate')
        perGlz(i) = resultsGlz{i}.glazePacketErrorRate;
    end
end

figure;
semilogy(snrVec, perBase, 'o-'); hold on; grid on;
semilogy(snrVec, perWiFiWithGlz, 's-');
semilogy(snrVec, perGlz, '^-');
xlabel('SNR (dB)'); ylabel('Packet Error Rate');
legend('Wi-Fi baseline PER','Wi-Fi PER with Glaze','Glaze packet error rate', 'Location','best');
title(sprintf('PER sweep (%s, MCS=%s, %s)', cfgHE.ChannelBandwidth, mat2str(mcs), char(chan)));
