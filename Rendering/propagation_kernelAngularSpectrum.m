function kernel = propagation_kernelAngularSpectrum( ...
    Nx, Ny, z, lambda, ppx, ppy, use_double_precision)

Nx = double(Nx);
Ny = double(Ny);

ppx = double(ppx);
ppy = double(ppy);

u_step = 1.0 / (Nx * ppx);
v_step = 1.0 / (Ny * ppy);

u = ((1:Nx) - 1 - round(Nx / 2)) * u_step;
v = ((1:Ny) - 1 - round(Ny / 2)) * v_step;

a = 1;

[U, V] = meshgrid(a * u, a * v);

kernel = exp( ...
    2 * 1i * pi * z / lambda ...
    * sqrt(1 - lambda ^ 2 * U .^ 2 - lambda ^ 2 * V .^ 2));

if ~use_double_precision
    kernel = single(kernel);
end

end
