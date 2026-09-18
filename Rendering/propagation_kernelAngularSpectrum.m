function kernel = propagation_kernelAngularSpectrum( ...
    Nx, Ny, z, lambda, ppx, ppy, use_double_precision)

arguments
    Nx (1, 1) {mustBePositive, mustBeInteger}
    Ny (1, 1) {mustBePositive, mustBeInteger}
    z (1, 1) double
    lambda (1, 1) double {mustBePositive}
    ppx (1, 1) double {mustBePositive}
    ppy (1, 1) double {mustBePositive}
    use_double_precision (1, 1) logical = false
end

Nx = double(Nx);
Ny = double(Ny);

% Grilles de fréquences spatiales dans l'ordre attendu par fft2 :
% dimension 1 : axe x ; dimension 2 : axe y.
fx = ifftshift( ...
    (-floor(Nx / 2):ceil(Nx / 2) - 1) / (Nx * ppx));

fy = ifftshift( ...
    (-floor(Ny / 2):ceil(Ny / 2) - 1) / (Ny * ppy));

[FX, FY] = ndgrid(fx, fy);

q = 1 - (lambda * FX) .^ 2 - (lambda * FY) .^ 2;

% Les composantes q < 0 sont évanescentes.
% Elles sont supprimées pour éviter des instabilités numériques,
% notamment si z est négatif.
isPropagating = q >= 0;

kernel = complex(zeros(Nx, Ny));

kernel(isPropagating) = exp( ...
    1i * 2 * pi * z / lambda .* ...
    sqrt(q(isPropagating)));

if ~use_double_precision
    kernel = single(kernel);
end

end
