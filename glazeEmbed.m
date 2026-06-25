function [txOut, info] = glazeEmbed(txIn, halfLevels, Fs, Rb, Delta_dB, sampRange)
% Apply piecewise attenuation on txIn to embed Glaze half-bits.
% txIn: Ns-by-Nt complex baseband
% halfLevels: 0/1 vector (Manchester output)
% Fs: sample rate
% Rb: bit rate (bps)
% Delta_dB: attenuation for level 0 (dB). level 1 -> 0 dB attenuation
% sampRange: [start end] samples to apply (e.g., ind.HEData)

txOut = txIn;
Ns = size(txIn,1);

if nargin < 6 || isempty(sampRange)
    sampRange = [1 Ns];
end
s0 = max(1, sampRange(1));
s1 = min(Ns, sampRange(2));

% Samples per half-bit
Nhb = max(1, round(Fs/(2*Rb)));

a0 = 10^(-Delta_dB/20); % amplitude scale for 0-level
a1 = 1;                 % amplitude scale for 1-level

alpha = ones(Ns,1);
p = s0;
nApplied = 0;

for i = 1:numel(halfLevels)
    idx = p : min(p+Nhb-1, s1);
    if isempty(idx)
        break
    end
    alpha(idx) = (halfLevels(i)==0)*a0 + (halfLevels(i)==1)*a1;
    p = p + Nhb;
    nApplied = nApplied + 1;
end

txOut = bsxfun(@times, txIn, alpha);

info.alpha = alpha;
info.Nhb = Nhb;
info.numHalfBitsApplied = nApplied;
info.sampRange = [s0 s1];
info.a0 = a0;
info.a1 = a1;
end
