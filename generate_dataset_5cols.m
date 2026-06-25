% 输出列: wifiBaseline_PER | wifiGlaze_PER | glaze_PER | delta_dB | Rb_kbps
% 保存路径: D:\matlab_project\Single User full PHY_MIMO_test1\Single User full PHY_MIMO_1\dataset_5cols.csv

clear; clc; close all;
rng(1);

%% ========== 可调参数 ==========
SINR_dB        = 10;     % 可调0，5，10

% ===== delta 先在线性域扫，再转 dB =====
delta_lin_min  = 1;      % 0 dB 对应 1
delta_lin_max  = 2;      % 3.0103 dB 对应 2
delta_lin_step = 0.25;   % 线性域步长（可调）

Rb_kbps_min    = 30;
Rb_kbps_max    = 70;
Rb_kbps_step   = 1.6;     % 可调

numPackets     = 10;    % 可调

% ===== 指定输出目录（按你的要求）=====
outDir = '/public/home/zhaoyu.liu/test_1';
if ~exist(outDir, 'dir')
    mkdir(outDir);
end
outCsv = fullfile(outDir, 'dataset_5cols.csv');

% 是否每个 (delta,Rb) 点用不同随机子流
useDifferentSubstreamPerPoint = true;
baseSubstream = 1;

%% ========== Wi-Fi PHY ==========
Nt   = 2;
Nr   = 2;
Nsts = 2;

cfgHE = wlanHESUConfig;
cfgHE.ChannelBandwidth = 'CBW20';
cfgHE.MCS = 0;
cfgHE.APEPLength = 4000;       % bytes
cfgHE.GuardInterval = 0.8;
cfgHE.ChannelCoding = 'LDPC';
cfgHE.NumTransmitAntennas = Nt;
cfgHE.NumSpaceTimeStreams = Nsts;

%% ========== TGax channel ==========
chanT = wlanTGaxChannel;
chanT.DelayProfile = 'Model-D';
chanT.ChannelBandwidth = cfgHE.ChannelBandwidth;
chanT.NumTransmitAntennas = Nt;
chanT.NumReceiveAntennas  = Nr;
chanT.TransmitReceiveDistance = 15;
chanT.LargeScaleFadingEffect = 'None';
chanT.SampleRate = wlanSampleRate(cfgHE);
chanT.PathGainsOutputPort = true;
chanT.NormalizeChannelOutputs = false;

%% ========== Glaze 固定字段（每个点会覆盖 Delta/Rb） ==========
glz0 = struct;
glz0.Enable      = true;
glz0.Delta_dB    = 0;                 % 占位
glz0.Rb          = 30e3;              % 占位
glz0.RateBits    = int8([0;0]);
glz0.PayloadBits = int8(randi([0 1], 25, 1)); % 25 bits payload

%% ========== 扫描网格 ==========
% 先生成线性域 delta，再映射到 dB
deltaLinVec = delta_lin_min:delta_lin_step:delta_lin_max;
delta_dB_vec = 10*log10(deltaLinVec);

Rbvec  = Rb_kbps_min:Rb_kbps_step:Rb_kbps_max;

nRows = numel(delta_dB_vec) * numel(Rbvec);

% 你要的 5 列（把 O_dB 改成 delta_dB）
results = table('Size',[nRows 5], ...
    'VariableTypes', {'double','double','double','double','double'}, ...
    'VariableNames', {'wifiBaseline_PER','wifiGlaze_PER','glaze_PER','delta_dB','Rb_kbps'});

%% ========== 展平网格（parfor 必备） ==========
deltaLinVec  = delta_lin_min:delta_lin_step:delta_lin_max;
delta_dB_vec = 10*log10(deltaLinVec);
Rbvec        = Rb_kbps_min:Rb_kbps_step:Rb_kbps_max;

[DeltaDBGrid, RbGrid] = ndgrid(delta_dB_vec, Rbvec);
DeltaDBList = DeltaDBGrid(:);
RbList      = RbGrid(:);

% 仅用于打印：把 delta_dB 反查回线性域（避免浮点误差，用插值/查表更稳）
DeltaLinList = 10.^(DeltaDBList/10);

nRows = numel(DeltaDBList);

%% ========== 预分配结果（parfor 里不能直接写 table） ==========
wifiBaseline_PER = nan(nRows,1);
wifiGlaze_PER    = nan(nRows,1);
glaze_PER        = nan(nRows,1);
delta_dB_col     = DeltaDBList;
Rb_kbps_col      = RbList;

%% ========== 并行池 ==========
% 先关旧池（如果有）
p = gcp('nocreate');
if ~isempty(p)
    delete(p);
end

% 开 12 个 worker
parpool('local',6);

% 每个 worker 只用 1 个计算线程（可选但推荐）
pctRunOnAll maxNumCompThreads(1);


%% ========== 进度回调（可选，但推荐） ==========
dq = parallel.pool.DataQueue;
t0 = tic;
afterEach(dq, @(msg) fprintf("%s\n", msg));

%% ========== parfor 主循环 ==========
parfor k = 1:nRows

    delta_dB = delta_dB_col(k);
    Rb_kbps  = Rb_kbps_col(k);
    Rb_bps   = Rb_kbps * 1e3;

    % --- 每个点的随机子流（与串行 row 逻辑一致，用 k 代替 row） ---
    if useDifferentSubstreamPerPoint
        substream = baseSubstream + (k-1);
    else
        substream = baseSubstream;
    end

    % ==========================================================
    % 为了“并行可复现”：每次迭代都重新构造 cfg 和 channel（别复用 handle）
    % ==========================================================
    cfgLocal = wlanHESUConfig;
    cfgLocal.ChannelBandwidth = 'CBW20';
    cfgLocal.MCS = 0;
    cfgLocal.APEPLength = 4000;      % bytes
    cfgLocal.GuardInterval = 0.8;
    cfgLocal.ChannelCoding = 'LDPC';
    cfgLocal.NumTransmitAntennas = Nt;
    cfgLocal.NumSpaceTimeStreams = Nsts;

    chanLocal = wlanTGaxChannel;
    chanLocal.DelayProfile = 'Model-D';
    chanLocal.ChannelBandwidth = cfgLocal.ChannelBandwidth;
    chanLocal.NumTransmitAntennas = Nt;
    chanLocal.NumReceiveAntennas  = Nr;
    chanLocal.TransmitReceiveDistance = 15;
    chanLocal.LargeScaleFadingEffect = 'None';
    chanLocal.SampleRate = wlanSampleRate(cfgLocal);
    chanLocal.PathGainsOutputPort = true;
    chanLocal.NormalizeChannelOutputs = false;

    % --- 公共 simParams（baseline / +Glaze 公平对比） ---
    sp = struct;
    sp.Config = cfgLocal;
    sp.RandomSubstream = substream;
    sp.MaxNumPackets = numPackets;
    sp.MaxNumErrors  = numPackets;      % 避免 early stop
    sp.SNR = SINR_dB;
    sp.Channel = chanLocal;

    sp.DelayProfile = string(chanLocal.DelayProfile);
    sp.NumTransmitAntennas = Nt;
    sp.NumReceiveAntennas  = Nr;
    sp.MCS = cfgLocal.MCS;
    sp.Verbose = false;

    % =========================
    % 1) WiFi baseline：Glaze OFF
    % =========================
    spBase = sp;
    spBase.Glaze = struct('Enable', false);
    outBase = box0Simulation(spBase);

    % =========================
    % 2) WiFi + Glaze：Glaze ON
    % =========================
    glz = glz0;
    glz.Enable   = true;
    glz.Delta_dB = delta_dB;
    glz.Rb       = Rb_bps;

    spGlz = sp;
    spGlz.Glaze = glz;
    outGlz  = box0Simulation(spGlz);

    % --- 写回结果数组（按 k 位置写，parfor 安全） ---
    wifiBaseline_PER(k) = outBase.packetErrorRate;
    wifiGlaze_PER(k)    = outGlz.packetErrorRate;
    glaze_PER(k)        = outGlz.glazePacketErrorRate;

    % --- 进度打印（异步到主进程，避免 parfor 里 fprintf 乱序刷屏） ---
    if mod(k,10)==0 || k==1 || k==nRows
        msg = sprintf("(k=%d/%d) SINR=%.1f dB | delta=%.4f dB (lin=%.3f) | Rb=%.1f kbps | basePER=%.4g | +GlzPER=%.4g | GlzPER=%.4g | %.1fs", ...
            k, nRows, SINR_dB, delta_dB, DeltaLinList(k), Rb_kbps, ...
            wifiBaseline_PER(k), wifiGlaze_PER(k), glaze_PER(k), toc(t0));
        send(dq, msg);
    end
end

%% ========== 汇总写表 ==========
results = table(wifiBaseline_PER, wifiGlaze_PER, glaze_PER, delta_dB_col, Rb_kbps_col, ...
    'VariableNames', {'wifiBaseline_PER','wifiGlaze_PER','glaze_PER','delta_dB','Rb_kbps'});

writetable(results, outCsv);
fprintf("\nDONE. CSV saved: %s\n", outCsv);
