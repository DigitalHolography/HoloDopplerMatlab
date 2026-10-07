function ratio = energy_ratio(SH, f1, f2, fi1, fi2, fs, batchSize)
%ENERGY_RATIO Ratio of mean high- to low-frequency spectral values.
%
% Low band:  fi1 <= |f| < fi2.
% High band: fi2 <= |f| <= f2.
% The common boundary fi2 belongs only to the high band.
%
% f1 is retained for compatibility but is not used.

arguments
    SH
    f1 (1,1) double {mustBeNonnegative}
    f2 (1,1) double {mustBePositive}
    fi1 (1,1) double {mustBeNonnegative}
    fi2 (1,1) double {mustBeNonnegative}
    fs (1,1) double {mustBePositive}
    batchSize (1,1) double {mustBeInteger,mustBePositive}
end

if ~(fi1 < fi2 && fi2 < f2)
    error('energy_ratio:InvalidBands', ...
        'Band limits must satisfy fi1 < fi2 < f2.');
end

if size(SH, 3) ~= batchSize
    error('energy_ratio:InvalidSize', ...
        'The third dimension of SH must equal batchSize.');
end

SH = abs(SH);

f = fftfreq(batchSize, 1 / fs);
absF = abs(f);

lowMask  = absF >= fi1 & absF < fi2;
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
ratio(~isfinite(ratio) | PL <= 0) = NaN;

end