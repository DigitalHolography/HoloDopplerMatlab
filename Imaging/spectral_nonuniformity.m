function D = spectral_nonuniformity(SH, f1, f2, fs, batchSize)
%SPECTRAL_NONUNIFORMITY Departure from a flat useful-band PSD.
%
% Input:
%   SH        : linear, real, nonnegative PSD [nRows, nCols, nFreq]
%   f1, f2    : useful band, f1 <= |f| <= f2
%   fs        : sampling frequency, Hz
%   batchSize : number of frequency bins
%
% Output:
%   D : dimensionless spectral nonuniformity map
%
%   D = mean((S - mean(S)).^2) / mean(S)^2
%
% A perfectly flat spectrum gives D = 0.
% Invalid or zero-power spectra give NaN.
%
% Frequency ordering follows the project's fftfreq function.
% No FFT shift, flat-field correction or noise subtraction is applied.

    arguments
        SH {mustBeNumeric, mustBeReal}
        f1 (1, 1) ...
            {mustBeNumeric, mustBeReal, mustBeFinite, mustBeNonnegative}
        f2 (1, 1) ...
            {mustBeNumeric, mustBeReal, mustBeFinite, mustBePositive}
        fs (1, 1) ...
            {mustBeNumeric, mustBeReal, mustBeFinite, mustBePositive}
        batchSize (1, 1) ...
            {mustBeNumeric, mustBeInteger, mustBePositive}
    end

    assert(f1 < f2 && f2 <= fs/2, ...
        'Require 0 <= f1 < f2 <= fs/2.');

    assert(size(SH, 3) == batchSize, ...
        'batchSize must match the third dimension of SH.');

    %% Select the useful frequency band

    f = fftfreq(batchSize, 1/fs);

    usefulMask = abs(f) >= f1 & abs(f) <= f2;

    assert(nnz(usefulMask) >= 2, ...
        'The useful band must contain at least two frequency bins.');

    S = SH(:, :, usefulMask);

    %% Validate each pixel spectrum
    % Do not silently remove invalid frequency bins.

    valid = all(isfinite(S) & S >= 0, 3);

    %% Scale each spectrum for numerical stability
    % D is invariant to a multiplicative amplitude factor.

    peak = max(S, [], 3);

    valid = valid & isfinite(peak) & peak > 0;

    safePeak = peak;
    safePeak(~valid) = 1;

    S = S ./ safePeak;

    %% Compute normalized spectral variance

    meanPSD = mean(S, 3);

    spectralVariance = mean( ...
        (S - meanPSD).^2, 3);

    valid = valid & isfinite(meanPSD) & meanPSD > 0;

    safeMean = meanPSD;
    safeMean(~valid) = 1;

    D = spectralVariance ./ safeMean.^2;

    D(~valid) = NaN;

end