function pkt = glazeBuildPacket(payloadBits, rateBits)
% Glaze packet: STF(9 bits) + LTF(13-bit Barker) + DATA(up to 25 bits)
% STF = 7-bit wakeup (redundant 1/0) + 2-bit rate
% LTF = 13-bit Barker code (0/1 form)

if nargin < 2 || isempty(rateBits)
    rateBits = [1;0]; % e.g., "10"
end

payloadBits = int8(payloadBits(:));
if numel(payloadBits) < 25
    payloadBits = [payloadBits; zeros(25-numel(payloadBits),1,'int8')];
else
    payloadBits = payloadBits(1:25);
end
rateBits = int8(rateBits(:));
if numel(rateBits) ~= 2
    error('rateBits must be 2 bits.');
end

% 7-bit wake-up sequence (redundant 1s and 0s)
wakeup7 = int8([1;0;1;0;1;0;1]);

% STF 9 bits
stf = [wakeup7; rateBits];

% 13-bit Barker (0/1 version)
ltf = int8([1;1;1;1;1;0;0;1;1;0;1;0;1]);

pkt.stf  = stf;
pkt.ltf  = ltf;
pkt.data = payloadBits;
pkt.bits = [stf; ltf; payloadBits];

pkt.len.stf  = numel(stf);
pkt.len.ltf  = numel(ltf);
pkt.len.data = numel(payloadBits);
end
