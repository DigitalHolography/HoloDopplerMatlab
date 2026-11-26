function [cdf_freq, f_q, f_c] = cdf(SH, f1, f2, fs, floor, batchSize)
arguments
    SH
    f1 (1,1) double {mustBeNonnegative}
    f2 (1,1) double {mustBePositive}
    fs (1,1) double {mustBePositive}
    floor (1,1) double {mustBeGreaterThan(floor,0), ...
                       mustBeLessThan(floor,1)}
    batchSize (1,1) double {mustBeInteger, mustBePositive}
end

if size(SH, 3) ~= batchSize
    error('cdf:SizeMismatch', ...
        'size(SH,3) doit être égal à batchSize.');
end

if f2 <= f1
    error('cdf:InvalidBand', 'f2 doit être supérieur à f1.');
end

% Sélection de la bande positive sur les fréquences réelles de la FFT
f_axis = fftfreq(batchSize, 1 / fs);
band = (f_axis >= f1) & (f_axis <= f2);

f = f_axis(band);
S = abs(SH(:, :, band));

nFreq = numel(f);
if nFreq < 2
    error('cdf:InsufficientBins', ...
        'La bande doit contenir au moins deux bins fréquentiels.');
end

% Intégrale cumulative par trapèzes
A = cumtrapz(f, S, 3);
M0 = A(:, :, end);

% Pixels dont l'intégrale est exploitable
valid = isfinite(M0) & (M0 > 0);
denom = M0;
denom(~valid) = 1;

CDF = A ./ denom;

% Centroïde spectral calculé avec la même intégration
M1 = trapz(f, S .* reshape(f, 1, 1, []), 3);
f_c = M1 ./ denom;

% Premier bin où la CDF atteint le seuil
idxHi = sum(CDF < floor, 3) + 1;
idxHi = min(max(idxHi, 2), nFreq);
idxLo = idxHi - 1;

% Indices linéaires pour récupérer les bornes de chaque pixel
nPixels = size(S, 1) * size(S, 2);
pixelIdx = reshape(1:nPixels, size(M0));

linLo = pixelIdx + (idxLo - 1) * nPixels;
linHi = pixelIdx + (idxHi - 1) * nPixels;

cLo = CDF(linLo);
cHi = CDF(linHi);

% Interpolation linéaire de la CDF entre les deux bins
dC = cHi - cLo;
valid = valid & isfinite(dC) & (dC > 0);
dC(~valid) = 1;

alpha = (floor - cLo) ./ dC;
alpha = min(max(alpha, 0), 1);

fLo = reshape(f(idxLo), size(M0));
fHi = reshape(f(idxHi), size(M0));

f_q = fLo + alpha .* (fHi - fLo);

% Compensation de la fréquence centrale
cdf_freq = f_q - f_c;

cdf_freq(~valid) = NaN;
f_q(~valid) = NaN;
f_c(~valid) = NaN;

end