function [ratio, f_c] = energy_ratio(SH, f1, f2, fi1, fi2, fs, batchSize)
%ENERGY_RATIO High-/low-frequency mean ratio relative to the centroid.
%
% Centroid estimation band: fi1 <= |f| <= f2.
%
% Compensated low band:  fi1 <= |f - f_c| < fi2.
% Compensated high band: fi2 <= |f - f_c| <= f2.
%
% f1 is retained for compatibility but is not used.

arguments
    SH
    f1 (1, 1) double {mustBeNonnegative}
    f2 (1, 1) double {mustBePositive}
    fi1 (1, 1) double {mustBeNonnegative}
    fi2 (1, 1) double {mustBeNonnegative}
    fs (1, 1) double {mustBePositive}
    batchSize (1, 1) double {mustBeInteger, mustBePositive}
end

if ~(f1 < fi1 && fi1 < fi2 && fi2 < f2)
    error('energy_ratio:InvalidBands', ...
    'Band limits must satisfy f1 < fi1 < fi2 < f2.');
end

if size(SH, 3) ~= batchSize
    error('energy_ratio:InvalidSize', ...
    'The third dimension of SH must equal batchSize.');
end

S = abs(SH);

f = fftfreq(batchSize, 1 / fs);
absF = abs(f);

lowMask = absF >= f1 & absF < fi1;
highMask = absF >= fi2 & absF <= f2;

if ~any(lowMask)
    error('energy_ratio:EmptyLowBand', ...
    'The low-frequency band contains no FFT bin.');
end

if ~any(highMask)
    error('energy_ratio:EmptyHighBand', ...
    'The high-frequency band contains no FFT bin.');
end

PL = mean(SH(:, :, lowMask), 3, 'omitnan');
PH = mean(SH(:, :, highMask), 3, 'omitnan');

ratio = PH ./ PL;
ratio(~validCenter | ~isfinite(ratio) | PL <= 0) = NaN;

end
