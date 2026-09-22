function ratio = energy_ratio(SH, f1, f2, fi1, fi2, fs, batchSize)
%ENERGY_RATIO Ratio of mean high- to low-frequency spectral power.
%
% The global support is f1 <= |f| <= f2. The low band contains frequencies
% below fi1; the high band contains frequencies at or above fi2. Therefore,
% when fi1 == fi2, their common boundary belongs only to the high band.

arguments
    SH
    f1 (1,1) double {mustBeNonnegative}
    f2 (1,1) double {mustBePositive}
    fi1 (1,1) double {mustBeNonnegative}
    fi2 (1,1) double {mustBeNonnegative}
    fs (1,1) double {mustBePositive}
    batchSize (1,1) double {mustBeInteger,mustBePositive}
end

if f2 <= f1
    error('energy_ratio:InvalidSupport', 'f2 must be greater than f1.');
end

SH = abs(SH);
f = fftfreq(batchSize, 1 / fs);
absF = abs(f);
support = absF >= f1 & absF <= f2;
lowMask = support & absF < fi1;
highMask = support & absF >= fi2;

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
ratio(~isfinite(ratio) | PL <= 0) = NaN;
end
