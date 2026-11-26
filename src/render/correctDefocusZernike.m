function [correctedField, phaseTerm, info] = correctDefocusZernike( ...
    field, coefficientRad, opts)
%CORRECTDEFOCUSZERNIKE Correct Zernike defocus on a complex field or stack.
%
%   correctedField = correctDefocusZernike(field, coefficientRad)
%   applies the HoloDoppler-Python Angular Spectrum convention. FIELD must
%   be [rows, columns, ...], typically [Ny, Nx, Nt]. COEFFICIENTRAD is the
%   fitted Noll mode-4 coefficient returned by the Python Angular Spectrum
%   Shack-Hartmann fit, in radians.
%
%   Name-value options:
%     PixelPitch   [rowPitch columnPitch], metres. Default [1 1].
%     PupilRadius  Zernike support radius. Default 2 (Python parity).
%     Convention   "python-angular" (default) or "physical-phase".
%     OutsidePupil "zero" (Python parity) or "preserve".
%
%   The normalized defocus mode is
%       Z4 = sqrt(3) * (2*rho^2 - 1).
%
%   Python Angular Spectrum parity requires exp(+1i*c4*Z4), because its
%   fit routine returns the negative reconstructed phase before the common
%   exp(-1i*phase) correction is formed. "physical-phase" instead applies
%   exp(-1i*c4*Z4).
%
%   Example:
%     [framesCorrected, phaseTerm] = correctDefocusZernike( ...
%         frames, c4, PixelPitch=[ppy ppx], ...
%         Convention="python-angular");

arguments
    field {mustBeNumeric}
    coefficientRad (1,1) {mustBeNumeric, mustBeReal, mustBeFinite}
    opts.PixelPitch (1,2) double {mustBeReal, mustBeFinite, mustBePositive} = [1 1]
    opts.PupilRadius (1,1) double {mustBeReal, mustBeFinite, mustBePositive} = 2
    opts.Convention (1,1) string {mustBeMember(opts.Convention, ...
        ["python-angular", "physical-phase"])} = "python-angular"
    opts.OutsidePupil (1,1) string {mustBeMember(opts.OutsidePupil, ...
        ["zero", "preserve"])} = "zero"
end

if isempty(field) || ndims(field) < 2
    error('correctDefocusZernike:InvalidField', ...
        'field must contain at least two non-empty spatial dimensions.');
end

if ~isfloat(field)
    field = single(field);
end

numRows = size(field, 1);
numCols = size(field, 2);
prototype = real(field(1));

rowPitch = opts.PixelPitch(1);
colPitch = opts.PixelPitch(2);
height = numRows * rowPitch;
width = numCols * colPitch;
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

coefficient = cast(coefficientRad, 'like', prototype);
aberrationPhase = coefficient .* Z4;

if opts.Convention == "python-angular"
    correctionSign = 1;
else
    correctionSign = -1;
end

zeroMap = zeros(numRows, numCols, 'like', prototype);
phaseTerm = complex(zeroMap, zeroMap);

if opts.OutsidePupil == "preserve"
    phaseTerm(:) = 1;
end

imaginaryUnit = complex(zeros(1, 'like', prototype), ...
    ones(1, 'like', prototype));
signedPhase = cast(correctionSign, 'like', prototype) .* aberrationPhase;
phaseTerm(support) = exp(imaginaryUnit .* signedPhase(support));

maskShape = ones(1, max(ndims(field), 2));
maskShape(1:2) = [numRows, numCols];
correctedField = field .* reshape(phaseTerm, maskShape);

if nargout >= 3
    info = struct();
    info.mode = 4;
    info.modeName = 'defocus';
    info.coefficientRad = coefficientRad;
    info.convention = char(opts.Convention);
    info.correctionSign = correctionSign;
    info.pixelPitch = opts.PixelPitch;
    info.pupilRadius = opts.PupilRadius;
    info.support = support;
    info.zernikeMode = Z4;
    info.aberrationPhase = aberrationPhase;
    info.appliedPhase = signedPhase;
end
end
