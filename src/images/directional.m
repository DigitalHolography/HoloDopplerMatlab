function [M0_pos, M0_neg] = directional(SH, f1, f2, fs, batchSize, gw)
% integration interval
% convert frequencies to indices
n1 = ceil(f1 * batchSize / fs);
n2 = ceil(f2 * batchSize / fs);

n1 = max(min(n1, ceil(size(SH, 3) / 2)), 1);
n2 = max(min(n2, ceil(size(SH, 3) / 2)), 1);

% symetric integration interval
n3 = size(SH, 3) - n2 + 1;
n4 = size(SH, 3) - n1 + 1;

M0_pos = squeeze(sum(abs(SH(:, :, n1:n2)), 3));
M0_neg = squeeze(sum(abs(SH(:, :, n3:n4)), 3));

% normalization
N_M0_pos = sum(M0_pos(:));
N_M0_neg = sum(M0_neg(:));

M0Filtered = imgaussfilt(M0_pos + M0_neg, gw);

M0_pos = M0_pos ./ M0Filtered;
N_M0_posFiltered = sum(M0_pos(:));
M0_pos = M0_pos * N_M0_pos / N_M0_posFiltered;

M0_neg = M0_neg ./ M0Filtered;
N_M0_negFiltered = sum(M0_neg(:));
M0_neg = M0_neg * N_M0_neg / N_M0_negFiltered;
end
