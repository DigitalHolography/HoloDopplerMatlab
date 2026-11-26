function [coefficientRad, phaseEstimate, diagnostics] = ...
    estimateDefocusAngularSH(shiftsY, shiftsX, imageSize, ...
    pixelPitch, wavelength, zPropagation, opts)
%ESTIMATEDEFOCUSANGULARSH Fit Noll Z4 from Shack-Hartmann displacements.
%
%   This is a one-mode MATLAB port of HoloDoppler Python's Angular
%   Spectrum Zernike fit. SHIFTSY and SHIFTSX are [NySub, NxSub] subimage
%   shifts in pixels. IMAGESIZE is [Ny Nx], PIXELPITCH is [ppy ppx] in
%   metres, WAVELENGTH and ZPROPAGATION are in metres.
%
%   PHASEESTIMATE follows the Python Angular Spectrum return convention:
%       phaseEstimate = -coefficientRad * Z4.
%   Consequently, the correction term is exp(-1i*phaseEstimate), or simply
%   correctDefocusZernike(..., Convention="python-angular").

arguments
    shiftsY {mustBeNumeric, mustBeReal}
    shiftsX {mustBeNumeric, mustBeReal}
    imageSize (1,2) double {mustBeInteger, mustBePositive}
    pixelPitch (1,2) double {mustBeReal, mustBeFinite, mustBePositive}
    wavelength (1,1) double {mustBeReal, mustBeFinite, mustBePositive}
    zPropagation (1,1) double {mustBeReal, mustBeFinite, mustBeNonzero}
    opts.PupilRadius (1,1) double {mustBeReal, mustBeFinite, mustBePositive} = 2
end

if ~isequal(size(shiftsY), size(shiftsX)) || ~ismatrix(shiftsY)
    error('estimateDefocusAngularSH:ShiftSizeMismatch', ...
        'shiftsY and shiftsX must be 2-D arrays of identical size.');
end

if ~isfloat(shiftsY), shiftsY = single(shiftsY); end
if ~isfloat(shiftsX), shiftsX = single(shiftsX); end

numRows = imageSize(1);
numCols = imageSize(2);
numYSub = size(shiftsY, 1);
numXSub = size(shiftsY, 2);
subRows = floor(numRows / numYSub);
subCols = floor(numCols / numXSub);

if subRows < 1 || subCols < 1
    error('estimateDefocusAngularSH:TooManySubapertures', ...
        'The subaperture grid is larger than the image.');
end

prototype = shiftsY(1);
height = numRows * pixelPitch(1);
width = numCols * pixelPitch(2);
normalizationLength = min(height, width);
rowHalfExtent = height / normalizationLength;
colHalfExtent = width / normalizationLength;

y = cast(linspace(-rowHalfExtent, rowHalfExtent, numRows), ...
    'like', prototype);
x = cast(linspace(-colHalfExtent, colHalfExtent, numCols), ...
    'like', prototype);
[X, Y] = meshgrid(x, y);
rhoSquared = X.^2 + Y.^2;
support = rhoSquared <= cast(opts.PupilRadius^2, 'like', prototype);
Z4 = cast(sqrt(3), 'like', prototype) .* (2 .* rhoSquared - 1);
Z4(~support) = NaN;

% MATLAB gradient returns column/X derivative first, then row/Y derivative.
[dZdx, dZdy] = gradient(Z4, pixelPitch(2), pixelPitch(1));
Gy = zeros(numYSub, numXSub, 'like', prototype);
Gx = zeros(numYSub, numXSub, 'like', prototype);

for iy = 1:numYSub
    rows = (iy - 1) * subRows + (1:subRows);

    for ix = 1:numXSub
        cols = (ix - 1) * subCols + (1:subCols);
        blockY = dZdy(rows, cols);
        blockX = dZdx(rows, cols);
        Gy(iy, ix) = mean(blockY(:), 'omitnan');
        Gx(iy, ix) = mean(blockX(:), 'omitnan');
    end
end

wavefrontScale = cast(wavelength / (2*pi), 'like', prototype);
Gy = Gy .* wavefrontScale;
Gx = Gx .* wavefrontScale;

slopesY = shiftsY .* cast(pixelPitch(1) * numYSub / zPropagation, ...
    'like', shiftsY);
slopesX = shiftsX .* cast(pixelPitch(2) * numXSub / zPropagation, ...
    'like', shiftsX);

A = [Gy(:); Gx(:)];
b = [slopesY(:); slopesX(:)];
valid = isfinite(A) & isfinite(b);

if nnz(valid) < 2 || norm(A(valid)) == 0
    error('estimateDefocusAngularSH:InsufficientData', ...
        'Not enough finite, informative subaperture shifts to fit defocus.');
end

coefficientRad = A(valid) \ b(valid);
phaseEstimate = -coefficientRad .* Z4;
phaseEstimate(~support) = NaN;

if nargout >= 3
    residual = A(valid) .* coefficientRad - b(valid);
    diagnostics = struct();
    diagnostics.validCount = nnz(valid);
    diagnostics.designVectorY = Gy;
    diagnostics.designVectorX = Gx;
    diagnostics.slopesY = slopesY;
    diagnostics.slopesX = slopesX;
    diagnostics.residualRMS = sqrt(mean(abs(residual).^2));
    diagnostics.zernikeMode = Z4;
    diagnostics.support = support;
end
end

function mustBeNonzero(value)
if value == 0
    error('estimateDefocusAngularSH:ZeroPropagation', ...
        'zPropagation must be non-zero.');
end
end
