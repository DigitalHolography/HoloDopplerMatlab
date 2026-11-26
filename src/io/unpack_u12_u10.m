function unpacked_frame = unpack_u12_u10(bi_compression, packed_frame, unpacked_frame_zeros)
%u12 unpack
if bi_compression == 1024
    unpacked_frame_zeros(1:2:end) = bitor(bitshift(packed_frame(1:3:end), 8), bitand(packed_frame(2:3:end), 240)); %0xF0 = 240
    unpacked_frame_zeros(2:2:end) = bitor(bitshift(bitand(packed_frame(2:3:end), 15), 12), bitshift(packed_frame(3:3:end), 4)); %0x0F = 15
    %u10 unpack
elseif bi_compression == 256
    unpacked_frame_zeros(1:4:end) = bitor(bitshift(packed_frame(1:5:end), 8), bitand(packed_frame(2:5:end), 192)); %0xC0 = 192
    unpacked_frame_zeros(2:4:end) = bitor(bitshift(bitand(packed_frame(2:5:end), 63), 10), bitshift(bitand(packed_frame(3:5:end), 240), 2)); %0x3F = 63 / 0xF0 = 240
    unpacked_frame_zeros(3:4:end) = bitor(bitshift(bitand(packed_frame(3:5:end), 15), 12), bitshift(bitand(packed_frame(4:5:end), 252), 4)); %0x0F = 15 / 0xFC = 252
    unpacked_frame_zeros(4:4:end) = bitor(bitshift(bitand(packed_frame(4:5:end), 3), 14), bitshift(packed_frame(5:5:end), 6)); %0x03 = 3
end

% other way to unpack u10
% elseif bi_compression == 256
%     unpacked_frame_zeros(1:4:end) = bitor(bitshift(packed_frame(1:5:end), 2), bitshift(packed_frame(2:5:end), -6));
%     unpacked_frame_zeros(2:4:end) = bitor(bitshift(bitand(packed_frame(2:5:end), 63), 4), bitshift(packed_frame(3:5:end), -4));
%     unpacked_frame_zeros(3:4:end) = bitor(bitshift(bitand(packed_frame(3:5:end), 15), 6), bitshift(packed_frame(4:5:end), -2));
%     unpacked_frame_zeros(4:4:end) = bitor(bitshift(bitand(packed_frame(4:5:end), 3), 8), packed_frame(5:5:end));
% end

unpacked_frame = unpacked_frame_zeros;
end
