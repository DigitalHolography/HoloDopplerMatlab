function Hout = polynomial_clutter_filter(Hin, degree)
%POLYNOMIAL_CLUTTER_FILTER Remove a temporal polynomial at each pixel.
%
%   Hout = polynomial_clutter_filter(Hin, degree)
%
% Inputs:
%   Hin    : single or double field [Nx, Ny, Nt].
%            Real or complex; CPU array or gpuArray.
%            Samples must be uniformly spaced in time.
%
%   degree : nonnegative integer smaller than Nt.
%            0 removes the temporal mean.
%            1 removes a constant plus a linear trend.
%            2 also removes a quadratic trend.
%
% Output:
%   Hout   : filtered field, with the same size, precision and
%            device placement as Hin.
%
% The polynomial basis is constructed in double precision on the CPU,
% then cast to the precision and device of Hin before filtering.
%
% Nonfinite samples are not supported: they propagate through the fit.

arguments
    Hin
    degree (1, 1) double ...
        {mustBeReal, mustBeFinite, mustBeInteger, mustBeNonnegative}
end

% Validate the underlying data type without gathering the field.
onGPU = isa(Hin, 'gpuArray');

if onGPU
    inputClass = classUnderlying(Hin);
else
    inputClass = class(Hin);
end

if ~ismember(inputClass, {'single', 'double'})
    error('polynomial_clutter_filter:InvalidType', ...
    'Hin must contain single- or double-precision data.');
end

if isempty(Hin) || ndims(Hin) > 3
    error('polynomial_clutter_filter:InvalidSize', ...
    'Hin must be nonempty, with time along dimension 3.');
end

if issparse(Hin)
    error('polynomial_clutter_filter:SparseInput', ...
    'Sparse input is not supported.');
end

[nx, ny, nt] = size(Hin);

if degree >= nt
    error('polynomial_clutter_filter:InvalidDegree', ...
        'degree must be smaller than the number of frames (%d).', nt);
end

% Degree zero is exactly temporal mean subtraction.
if degree == 0
    Hout = Hin - mean(Hin, 3);
    return
end

% Normalized time coordinate improves polynomial conditioning.
t = linspace(-1, 1, nt).';

% Legendre recurrence spans polynomials of degree 0 through degree.
% QR subsequently orthonormalizes this sampled basis.
B = zeros(nt, degree + 1);
B(:, 1) = 1;
B(:, 2) = t;

for k = 2:degree
    B(:, k + 1) = ( ...
        (2 * k - 1) * t .* B(:, k) ...
        - (k - 1) * B(:, k - 1)) / k;
end

[Q, ~] = qr(B, 'econ');

% Only the small temporal basis is moved to the GPU.
Q = cast(Q, inputClass);

if onGPU
    Q = gpuArray(Q);
end

% Rows are pixels; columns are time samples.
X = reshape(Hin, nx * ny, nt);

% Q is real, so Q.' equals its conjugate transpose.
% Apply the projection in factored form, without forming an Nt-by-Nt matrix.
coefficients = X * Q;
Xfiltered = X - coefficients * Q.';

Hout = reshape(Xfiltered, size(Hin));

end
