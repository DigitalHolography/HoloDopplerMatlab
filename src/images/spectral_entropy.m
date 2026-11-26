function [spectral_entropy] = spectral_entropy(SH, f1, f2, fs, batchSize)

arguments
    SH
    f1
    f2
    fs
    batchSize
end

SH = abs(SH);

% Frequency axis
f = fftfreq(batchSize, 1 / fs);
abs_f = abs(f);

% Boolean mask for the visible window [f1, f2]
mask = (abs_f >= f1) & (abs_f <= f2);

% Apply mask — zero out frequencies outside the window
SH_masked = SH .* reshape(mask, 1, 1, []);
p = SH_masked; % normalized: sums to 1 along dim 3

% Spectral entropy: H = -sum(p * log(p))
% Convention: 0*log(0) = 0, so mask out zero entries
safe_log = zeros(size(p), 'like', p);
nonzero = p > 0;
safe_log(nonzero) = log(p(nonzero)); % natural log

spectral_entropy = -sum(p .* safe_log, 3); % (batch x channels)

end
