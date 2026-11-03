function [w, sigma, h1, h2, diagnostic] = gaussian_width( ...
    SH, f1, f2, fs, batchSize, gw)
%GAUSSIAN_WIDTH Estimate the intrinsic width of an aliased Gaussian.
%
% Model:
%   S(f) = A * Gperiodic(f; mu, sigma, fs) + C
%
% Input:
%   SH        : spectral data, dimensions [Nx, Ny, batchSize].
%               Frequency ordering must match fftfreq(batchSize, 1/fs).
%   f1, f2    : frequency window, which MUST include every FFT bin.
%   fs        : sampling frequency.
%   batchSize : number of frequency bins.
%   gw        : compatibility argument; must be zero.
%
% Outputs:
%   w         : intrinsic Gaussian FWHM, dimensions [Nx, Ny].
%   sigma     : intrinsic Gaussian standard deviation.
%
% The estimator uses the first two Fourier harmonics of the spectrum:
%
%   sigma = fs / (pi*sqrt(6)) * sqrt(log(abs(H1)/abs(H2)))
%   w     = 2*sqrt(2*log(2)) * sigma
%
% The continuous-model formula eliminates:
%   - amplitude A,
%   - center mu,
%   - constant baseline C.
%
% Discrete sums approximate the continuous harmonic integrals.
% Invalid or numerically unresolved estimates are returned as NaN.
%
% Requires:
%   fftfreq
%
% Frequencies and output widths use the same units.

arguments
    SH {mustBeNumeric}
    f1 (1, 1) double {mustBeFinite, mustBeNonnegative}
    f2 (1, 1) double {mustBeFinite, mustBePositive}
    fs (1, 1) double {mustBeFinite, mustBePositive}
    batchSize (1, 1) double ...
        {mustBeInteger, mustBeGreaterThanOrEqual(batchSize, 5)}
    gw (1, 1) double {mustBeFinite, mustBeNonnegative} = 0
end

% Validate dimensions and options

assert(ndims(SH) <= 3 && size(SH, 3) == batchSize, ...
    'gaussian_width:InvalidSize', ...
    'SH must have dimensions [Nx, Ny, batchSize].');

assert(f2 > f1, ...
    'gaussian_width:InvalidBand', ...
    'f2 must be greater than f1.');

assert(gw == 0, ...
    'gaussian_width:UnsupportedCorrection', ...
    ['Use gw=0. Multiplicative flat-field correction is not ' ...
     'applied to this width estimator.']);

% Prepare spectrum and frequency axis

diagnostic = struct( ...
    'fft', [], ...
    'axis', [], ...
    'harmonicIndices', [], ...
    'axisLabel', '');

% Same input convention as moment0:
% use the magnitude, without squaring it.
SH = double(abs(SH));

f = fftfreq(batchSize, 1 / fs);
f = double(f(:));

assert(numel(f) == batchSize && all(isfinite(f)), ...
    'gaussian_width:InvalidFrequencyAxis', ...
    'fftfreq must return batchSize finite frequencies.');

abs_f = abs(f);
mask = (abs_f >= f1) & (abs_f <= f2);

assert(all(mask), ...
    'gaussian_width:IncompleteSpectrum', ...
    ['This estimator requires every bin of a complete FFT period. ' ...
     'Use f1=0 and f2=fs/2, with no masked or missing bins.']);

% Fourier harmonics along the frequency dimension

weight1 = reshape(exp(-1i * 2*pi * f / fs), 1, 1, []);
weight2 = reshape(exp(-1i * 4*pi * f / fs), 1, 1, []);

% The common integration factor df cancels in the harmonic ratio.
H1 = sum(SH .* weight1, 3);
H2 = sum(SH .* weight2, 3);

h1 = abs(H1);
h2 = abs(H2);

% Numerical validity

% Numerical round-off threshold, NOT a measurement-noise threshold.
spectralSum = sum(SH, 3);
harmonicTolerance = 100 * eps('double') .* spectralSum;

valid = ...
    isfinite(spectralSum) & spectralSum > 0 ...
    & isfinite(h1) & isfinite(h2) ...
    & h1 > harmonicTolerance ...
    & h2 > harmonicTolerance ...
    & h1 > h2;

% Estimate intrinsic width

sigma = nan(size(h1), 'like', h1);

logRatio = log(h1(valid)) - log(h2(valid));

sigma(valid) = fs / (pi * sqrt(6)) .* sqrt(logRatio);

w = 2 * sqrt(2 * log(2)) .* sigma;

% Diagnostic: Fourier harmonics of one actual pixel spectrum
% A single vector is required by renderHarmonicSpectrum.
% Prefer a valid pixel with the largest first-harmonic amplitude.
% This is a diagnostic pixel, not a spatially averaged spectrum.

if nargout >= 5
    candidates = valid;

    % If no width estimate is valid, still allow inspection of a finite
    % pixel spectrum to help diagnose the failure.
    if ~any(candidates(:))
        candidates = isfinite(spectralSum) & spectralSum > 0 ...
            & isfinite(h1) & isfinite(h2);
    end

    candidateIndices = find(candidates);

    if isempty(candidateIndices)
        error('gaussian_width:NoDiagnosticPixel', ...
            'No finite, positive-power pixel is available for the diagnostic.');
    end

    [~, bestIndex] = max(h1(candidateIndices));
    pixelIndex = candidateIndices(bestIndex);

    [row, col] = ind2sub(size(h1), pixelIndex);
    spectrum = reshape(SH(row, col, :), [], 1);

    % Verify the ordering required for fft(spectrum) to reproduce the
    % weighted harmonic sums used above. Frequencies may differ by fs
    % because the input axis uses signed FFT frequencies.
    expectedPhase = exp( ...
        -1i * 2*pi * (0:batchSize-1).' / batchSize);

    actualPhase = exp(-1i * 2*pi * f / fs);

    if isa(actualPhase, 'gpuArray')
        orderingError = gather(max(abs(actualPhase - expectedPhase)));
    else
        orderingError = max(abs(actualPhase - expectedPhase));
    end

    assert(orderingError < 1e-10, ...
        'gaussian_width:UnexpectedFrequencyOrdering', ...
        ['The frequency ordering does not match an unshifted FFT. ' ...
        'Reorder the spectrum and its frequency axis consistently.']);

    % Transform along the spectral-bin dimension.
    coefficients = fft(spectrum);

    % Signed harmonic orders in the same ordering as fft().
    % Even N: [0 ... N/2-1 -N/2 ... -1]
    % Odd  N: [0 ... (N-1)/2 -(N-1)/2 ... -1]
    harmonicOrders = (0:batchSize-1).';
    harmonicOrders(harmonicOrders > floor((batchSize-1)/2)) = ...
        harmonicOrders(harmonicOrders > floor((batchSize-1)/2)) ...
        - batchSize;

    diagnostic.fft = coefficients;
    diagnostic.axis = harmonicOrders;
    diagnostic.harmonicIndices = [2 3];
    diagnostic.axisLabel = sprintf( ...
        'Harmonic order | pixel (row=%d, col=%d)', row, col);

    % Retain the exact pixel and source spectrum for inspection.
    diagnostic.pixel = [row col];
    diagnostic.inputSpectrum = spectrum;
    diagnostic.inputFrequency = f;
    diagnostic.selectedHarmonics = [H1(row, col); H2(row, col)];
    diagnostic.widthEstimateValid = valid(row, col);
end

end