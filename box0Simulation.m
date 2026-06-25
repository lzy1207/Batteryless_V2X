function out = box0Simulation(simParams)
% box0Simulation Example helper function
%
% Modified for: MIMO common-mode Glaze embedding (works for Nt>1, Nsts>=1)

% ---- Glaze parameters (optional) ----
glazeEnable = isfield(simParams,'Glaze') && isfield(simParams.Glaze,'Enable') && simParams.Glaze.Enable;
if glazeEnable
    glz = simParams.Glaze;   % struct
end

% Extract configuration
cfgHE = simParams.Config;
substreamidx = simParams.RandomSubstream;
maxNumPackets = simParams.MaxNumPackets;
maxNumErrors = simParams.MaxNumErrors;
snr = simParams.SNR;
tgaxChannel = simParams.Channel;

% Create an NDP packet with the correct number of space-time streams to
% generate enough LTF symbols (beamforming sounding)
cfgNDP = wlanHESUConfig('APEPLength',0,'GuardInterval',0.8); % No data in an NDP
cfgNDP.ChannelBandwidth = cfgHE.ChannelBandwidth;
cfgNDP.NumTransmitAntennas = cfgHE.NumTransmitAntennas;
cfgNDP.NumSpaceTimeStreams = cfgHE.NumTransmitAntennas;

% Set random substream index per iteration
stream = RandStream('combRecursive','Seed',99);
stream.Substream = substreamidx;
RandStream.setGlobalStream(stream);

% Indices to extract fields from the PPDU
ind = wlanFieldIndices(cfgHE);

% OFDM parameters (HE-Data)
ofdmInfo = wlanHEOFDMInfo('HE-Data',cfgHE);

% AWGN channel per SNR point
awgnChannel = comm.AWGNChannel;
awgnChannel.NoiseMethod = 'Signal to noise ratio (SNR)';
awgnChannel.SNR = snr-10*log10(ofdmInfo.FFTLength/ofdmInfo.NumTones);
N0 = 10^(-awgnChannel.SNR/10); %#ok<NASGU>

% Channel filter coefficients
chanInfo = info(tgaxChannel);
pathFilters = chanInfo.ChannelFilterCoefficients; % [Np x Nh]

% Loop storage
perStore = nan(maxNumPackets,1);
perAbsStore = nan(maxNumPackets,1);
perAbsRawStore = nan(maxNumPackets,1);
snreffStore = nan(maxNumPackets,1); %#ok<NASGU>
glazePerStore = nan(maxNumPackets,1);
sinrStore = nan(ofdmInfo.NumTones,cfgHE.NumSpaceTimeStreams,maxNumPackets);

numPacketErrors = 0;
numPacketErrorsAbs = 0;
numGlazeErrors = 0;

% ===== Glaze debug counters =====
glzNoDetectCnt = 0;
glzDetectedCnt = 0;
glzMismatchCnt = 0;
glzSuccessCnt  = 0;

glzCorrPeakStore = nan(maxNumPackets,1);
glzAppliedHalfStore = nan(maxNumPackets,1);
glzNeedHalfStore    = nan(maxNumPackets,1);
glzAvailSampStore   = nan(maxNumPackets,1);
glzNeedSampStore    = nan(maxNumPackets,1);
glzStatusStore      = strings(maxNumPackets,1);

numPkt = 1;

while numPacketErrors<=maxNumErrors && numPkt<=maxNumPackets
    reset(tgaxChannel);

    % -------- Beamforming sounding (NDP) --------
    txNDP = wlanWaveformGenerator([],cfgNDP);
    rxNDP = tgaxChannel([txNDP; zeros(50,size(txNDP,2))]);

    staFeedback = heUserBeamformingFeedback(rxNDP,cfgNDP);
    steeringMatrix = heSUCalculateSteeringMatrix(staFeedback,cfgHE,cfgNDP);

    cfgHE.SpatialMapping = 'Custom';
    cfgHE.SpatialMappingMatrix = steeringMatrix;

    % -------- Data PPDU --------
    psduLength = getPSDULength(cfgHE);
    txPSDU = randi([0 1],psduLength*8,1,'int8');
    tx = wlanWaveformGenerator(txPSDU,cfgHE); % [Nsamp x Nt]

    % ===== Glaze overlay (COMMON-MODE across all TX antennas) =====
    if glazeEnable
        fs = wlanSampleRate(cfgHE);

        pktG   = glazeBuildPacket(glz.PayloadBits, glz.RateBits);
        halfLv = glazeManchesterEncode(pktG.bits);

        % IMPORTANT: common-mode overlay on HE-Data for ALL Tx antennas
        [tx, glazeTxInfo] = glazeEmbedCommonMode(tx, halfLv, fs, glz.Rb, glz.Delta_dB, ind.HEData);

        % Record fit / applied info
        needHalf  = double(numel(halfLv));
        availSamp = double(ind.HEData(2) - ind.HEData(1) + 1);
        needSamp  = needHalf * double(glazeTxInfo.Nhb);

        glzAppliedHalfStore(numPkt) = double(glazeTxInfo.numHalfBitsApplied);
        glzNeedHalfStore(numPkt)    = needHalf;
        glzAvailSampStore(numPkt)   = availSamp;
        glzNeedSampStore(numPkt)    = needSamp;
    end

    % Add trailing zeros to allow for channel delay
    txPad = [tx; zeros(50,cfgHE.NumTransmitAntennas)];

    % Pass through fading TGax channel
    [rx,pathGains] = tgaxChannel(txPad);

    % Perfect timing offset and channel matrix for HE-LTF field
    heltfPathGains = pathGains(ind.HELTF(1):ind.HELTF(2),:,:,:,:);
    pktOffset = channelDelay(heltfPathGains,pathFilters);
    chan = helperPerfectChannelEstimate(heltfPathGains,pathFilters, ...
        ofdmInfo.FFTLength,ofdmInfo.CPLength,ofdmInfo.ActiveFFTIndices,pktOffset);

    % Add AWGN
    rx = awgnChannel(rx);

    % ===== Glaze receiver =====
    if glazeEnable
        fs = wlanSampleRate(cfgHE);

        % Cut HE-Data region using pktOffset
        rxGlazeSeg = rx(pktOffset+(ind.HEData(1):ind.HEData(2)), :);  % [Nsamp x Nr]

        % Energy combining (safe)
        rxGlaze1 = sum(rxGlazeSeg,2) / sqrt(size(rxGlazeSeg,2));      % [Nsamp x 1]
        [pktHat, det] = glazeDecode(rxGlaze1, fs, glz.Rb);

        if isfield(det,'corrPeakNorm')
            glzCorrPeakStore(numPkt) = det.corrPeakNorm;
        elseif isfield(det,'corrPeak')
            glzCorrPeakStore(numPkt) = det.corrPeak;
        end

        % Tx payload for comparison (25 bits)
        txData = int8(glz.PayloadBits(:));
        if numel(txData) < 25
            txData = [txData; zeros(25-numel(txData),1,'int8')];
        else
            txData = txData(1:25);
        end

        % Short / NoDetect / Mismatch / Success
        if glzAvailSampStore(numPkt) < glzNeedSampStore(numPkt)
            glzStatusStore(numPkt) = "Short";
            glzNoDetectCnt = glzNoDetectCnt + 1;
            glazePacketError = true;
        else
            if ~det.found
                glzStatusStore(numPkt) = "NoDetect";
                glzNoDetectCnt = glzNoDetectCnt + 1;
                glazePacketError = true;
            else
                glzDetectedCnt = glzDetectedCnt + 1;
                if isfield(pktHat,'data') && isequal(pktHat.data, txData)
                    glzStatusStore(numPkt) = "Success";
                    glzSuccessCnt = glzSuccessCnt + 1;
                    glazePacketError = false;
                else
                    glzStatusStore(numPkt) = "Mismatch";
                    glzMismatchCnt = glzMismatchCnt + 1;
                    glazePacketError = true;
                end
            end
        end

        glazePacketError = double(logical(glazePacketError));
        glazePerStore(numPkt) = glazePacketError;
        numGlazeErrors = numGlazeErrors + glazePacketError;
    end

    % ===== Wi-Fi PHY decode =====
    rxData = rx(pktOffset+(ind.HEData(1):ind.HEData(2)),:);
    demodSym = wlanHEDemodulate(rxData,'HE-Data',cfgHE);

    demodDataSym = demodSym(ofdmInfo.DataIndices,:,:);

    chanEst = heChannelToChannelEstimate(chan,cfgHE);
    chanEstAv = permute(mean(chanEst,2),[1 3 4 2]);
    chanEstData = chanEstAv(ofdmInfo.DataIndices,:,:);

    chanEstSSPilots = permute(sum(chanEst(ofdmInfo.PilotIndices,:,:,:),3),[1 2 4 5 3]);
    demodPilotSym = demodSym(ofdmInfo.PilotIndices,:,:);
    nVarEst = heNoiseEstimate(demodPilotSym,chanEstSSPilots,cfgHE);

    [eqDataSym,csi] = heEqualizeCombine(demodDataSym,chanEstData,nVarEst,cfgHE);
    rxPSDU = wlanHEDataBitRecover(eqDataSym,nVarEst,csi,cfgHE);

    packetError = ~isequal(txPSDU,rxPSDU);
    perStore(numPkt) = packetError;
    numPacketErrors = numPacketErrors + packetError;

    numPkt = numPkt + 1;
end

% Remove last increment
numPkt = numPkt - 1;

% PER at this SNR point
packetErrorRate = numPacketErrors/numPkt;
packetErrorRateAbs = numPacketErrorsAbs/numPkt;

% Return results
out = struct;
out.packetErrorRate = packetErrorRate;
out.perStore = perStore;
out.numPkt = numPkt;
out.sinrStore = sinrStore;
out.packetErrorRateAbs = packetErrorRateAbs;
out.perAbsRawStore = perAbsRawStore;
out.perAbsStore = perAbsStore;

out.glazePacketErrorRate = numGlazeErrors/numPkt;
out.glazePerStore = glazePerStore;

% ===== Glaze debug outputs =====
out.glzNoDetectCnt = glzNoDetectCnt;
out.glzDetectedCnt = glzDetectedCnt;
out.glzMismatchCnt = glzMismatchCnt;
out.glzSuccessCnt  = glzSuccessCnt;

out.glzCorrPeakStore   = glzCorrPeakStore(1:numPkt);
out.glzAppliedHalfStore= glzAppliedHalfStore(1:numPkt);
out.glzNeedHalfStore   = glzNeedHalfStore(1:numPkt);
out.glzAvailSampStore  = glzAvailSampStore(1:numPkt);
out.glzNeedSampStore   = glzNeedSampStore(1:numPkt);
out.glzStatusStore     = glzStatusStore(1:numPkt);

% ===== 终端输出（可用 simParams.Verbose 控制，默认输出）=====
if ~isfield(simParams,'Verbose') || simParams.Verbose
    disp([char(simParams.DelayProfile) ' '...
          num2str(simParams.NumTransmitAntennas) '-by-' ...
          num2str(simParams.NumReceiveAntennas) ','...
          ' MCS ' num2str(simParams.MCS) ','...
          ' SNR ' num2str(simParams.SNR) ...
          ' completed after ' num2str(out.numPkt) ' packets,'...
          ' PER:' num2str(out.packetErrorRate)]);
end

end  % <<< 关键修复：这里必须结束 box0Simulation 主函数！


% =====================================================================
% Local helper: COMMON-MODE Glaze embed (safe for integer/double types)
% =====================================================================
function [txOut, info] = glazeEmbedCommonMode(txIn, halfLv, Fs, Rb, Delta_dB, heDataInd)
% Apply Glaze by scaling HE-Data samples with alpha(t), SAME alpha(t) for all TX antennas.
% Works for txIn: [Nsamp x Nt] or [Nsamp x 1].

% Make indices safe
s0 = double(heDataInd(1));
s1 = double(heDataInd(2));

Fs = double(Fs);
Rb = double(Rb);

Nhb = round(Fs/(2*Rb));     % samples per half-bit
Nhb = max(1, Nhb);
Nhb = double(Nhb);

hi = 10^(double(Delta_dB)/40);   % +Delta/2 dB amplitude
lo = 10^(-double(Delta_dB)/40);  % -Delta/2 dB amplitude

availSamp = s1 - s0 + 1;
maxHalf   = floor(availSamp / Nhb);
numHalf   = min(double(numel(halfLv)), double(maxHalf));
numHalf   = max(0, floor(numHalf));

alpha = ones(availSamp,1,'like',real(txIn));

% NOTE: use st:ed indexing to avoid "(k-1)*Nhb + (1:Nhb)" integer+vector issues
for k = 1:numHalf
    if halfLv(k) ~= 0
        a = hi;
    else
        a = lo;
    end
    st = (k-1)*Nhb + 1;
    ed = k*Nhb;
    alpha(st:ed) = a;
end

txOut = txIn;

% Apply alpha to ALL TX antennas
% New MATLAB: implicit expansion works. Old MATLAB: fall back to bsxfun.
try
    txOut(s0:s1,:) = txIn(s0:s1,:) .* alpha;
catch
    txOut(s0:s1,:) = bsxfun(@times, txIn(s0:s1,:), alpha);
end

info = struct;
info.Nhb = Nhb;
info.numHalfBitsApplied = numHalf;

end
