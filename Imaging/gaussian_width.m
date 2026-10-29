function [w, sigma] = gaussian_width( ...
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

%% Validate dimensions and options

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

%% Prepare spectrum and frequency axis

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

%% Fourier harmonics along the frequency dimension

weight1 = reshape(exp(-1i * 2*pi * f / fs), 1, 1, []);
weight2 = reshape(exp(-1i * 4*pi * f / fs), 1, 1, []);

% The common integration factor df cancels in the harmonic ratio.
H1 = sum(SH .* weight1, 3);
H2 = sum(SH .* weight2, 3);

h1 = abs(H1);
h2 = abs(H2);

%% Numerical validity

% Numerical round-off threshold, NOT a measurement-noise threshold.
spectralSum = sum(SH, 3);
harmonicTolerance = 100 * eps('double') .* spectralSum;

valid = ...
    isfinite(spectralSum) & spectralSum > 0 ...
    & isfinite(h1) & isfinite(h2) ...
    & h1 > harmonicTolerance ...
    & h2 > harmonicTolerance ...
    & h1 > h2;

%% Estimate intrinsic width

sigma = zeros(size(h1));

logRatio = log(h1(valid)) - log(h2(valid));

sigma(valid) = fs / (pi * sqrt(6)) .* sqrt(logRatio);

w = 2 * sqrt(2 * log(2)) .* sigma;

end