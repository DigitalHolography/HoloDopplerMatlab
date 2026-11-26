function [freq_low, freq_high] = composite(SH, f1, f2, f3, fs, batchSize, gw)
% reconstructs two different holograms with different frequency ranges
% that can be combined to generate a composite color image.

% Calculate the zeroth moment of the spectrum
SH = abs(SH);

% Create frequency weights for the zeroth moment calculation
f = fftfreq(batchSize, 1 / fs);
abs_f = abs(f);

% Boolean mask for the visible window [f1, f2]
mask_low = (abs_f >= f1) & (abs_f <= f2);
mask_high = (abs_f >= f2) & (abs_f <= f3);

% integration
freq_low = sum(SH .* reshape(mask_low, 1, 1, []), 3);
freq_high = sum(SH .* reshape(mask_high, 1, 1, []), 3);

% normalization
if nargin > 6
    freq_low = freq_low ./ imgaussfilt(freq_low, gw);
    freq_high = freq_high ./ imgaussfilt(freq_high, gw);
end

end
