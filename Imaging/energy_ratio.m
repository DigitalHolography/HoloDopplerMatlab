function [ratio, f_c] = energy_ratio(SH, f1, f2, fi1, fi2, fs, batchSize)
%ENERGY_RATIO High-/low-frequency mean ratio relative to the centroid.
%
% Centroid estimation band: fi1 <= |f| <= f2.
%
% Compensated low band:  fi1 <= |f - f_c| < fi2.
% Compensated high band: fi2 <= |f - f_c| <= f2.
%
% f1 is retained for compatibility but is not used.
% SH must use the same frequency ordering as fftfreq.
% Spectral weights are abs(SH).

arguments
    SH
    f1 (1, 1) double {mustBeNonnegative}
    f2 (1, 1) double {mustBePositive}
    fi1 (1, 1) double {mustBeNonnegative}
    fi2 (1, 1) double {mustBeNonnegative}
    fs (1, 1) double {mustBePositive}
    batchSize (1, 1) double {mustBeInteger, mustBePositive}
end

if ~(fi1 < fi2 && fi2 < f2)
    error('energy_ratio:InvalidBands', ...
        'Band limits must satisfy fi1 < fi2 < f2.');
end

if size(SH, 3) ~= batchSize
    error('energy_ratio:InvalidSize', ...
        'The third dimension of SH must equal batchSize.');
end

S = abs(SH);
f = reshape(fftfreq(batchSize, 1 / fs), 1, 1, []);

% Exclude nonfinite samples from both sums and sample counts.
validSample = isfinite(S);
S(~validSample) = 0;

% Estimate the signed centroid in a fixed frequency band.
centerMask = abs(f) >= fi1 & abs(f) <= f2;

if ~any(centerMask(:))
    error('energy_ratio:EmptyCenterBand', ...
        'The centroid estimation band contains no FFT bin.');
end

Scenter = S .* centerMask;

M0 = sum(Scenter, 3);
M1 = sum(Scenter .* f, 3);

f_c = M1 ./ M0;

validCenter = M0 > 0 & isfinite(M0) & isfinite(f_c);
f_c(~validCenter) = NaN;

% Pixel-dependent bands relative to the centroid.
relativeF = abs(f - f_c);

lowMask  = relativeF >= fi1 & relativeF < fi2;
highMask = relativeF >= fi2 & relativeF <= f2;

% Count only finite samples within each compensated band.
nLow  = sum(lowMask  & validSample, 3);
nHigh = sum(highMask & validSample, 3);

PL = sum(S .* lowMask, 3) ./ nLow;
PH = sum(S .* highMask, 3) ./ nHigh;

ratio = PH ./ PL;

invalidRatio = ~validCenter ...
    | nLow == 0 ...
    | nHigh == 0 ...
    | PL <= 0 ...
    | ~isfinite(ratio);

ratio(invalidRatio) = NaN;

end