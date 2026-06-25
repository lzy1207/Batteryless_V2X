function halfLevels = glazeManchesterEncode(bits)
% Manchester coding:
% 0 -> [0 1] (0 to 1 transition)
% 1 -> [1 0] (1 to 0 transition)

bits = int8(bits(:));
halfLevels = zeros(2*numel(bits), 1, 'int8');

for k = 1:numel(bits)
    if bits(k) == 0
        halfLevels(2*k-1:2*k) = int8([0;1]);
    else
        halfLevels(2*k-1:2*k) = int8([1;0]);
    end
end
end
