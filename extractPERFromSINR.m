function ps = extractPERFromSINR(sinrLin, mcs)
%extractPERFromSINR  Minimal replacement helper used by box0Simulation.
%   ps = extractPERFromSINR(sinrLin, mcs) returns a "success probability"
%   in [0,1] for each SINR entry (same size as sinrLin).
%
%   NOTE: This is a lightweight monotonic model (logistic vs SINR_dB).
%   It is NOT an 11ax-standard-accurate link abstraction, but it restores
%   functionality so your simulation can run and be tuned later.

% Protect
sinrLin = max(sinrLin, 1e-12);
sinr_dB = 10*log10(sinrLin);

% Rough SNR thresholds (dB) for HE SU MCS0~11 (tunable)
% Interpreted as the point where success prob ~ 0.5.
th = [-1  2  4  6  8 10 12 14 16 18 20 22];  % you can tune these

idx = min(max(mcs+1,1), numel(th));
b = th(idx);       % midpoint
a = 1.3;           % slope (bigger -> steeper)

% Success probability per tone/stream
ps = 1 ./ (1 + exp(-a*(sinr_dB - b)));
end
