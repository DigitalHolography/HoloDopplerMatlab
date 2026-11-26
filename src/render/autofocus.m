function z_opti = autofocus(rend, Params)

zmin = Params.autofocusRange1;
zmax = Params.autofocusRange2;

% Create waitbar BEFORE referencing it in options
f = waitbar(0, 'Autofocus in progress. Please wait...');
styleWaitbar(f);
cleanup = onCleanup(@() close(f));  % ensures waitbar closes even on error

% Cost function with boundary penalty (already includes clamp logic)
cost = @(z) cost_function(rend, Params, z);
obj = @(z) cost(z) + 1e12 * (z < zmin || z > zmax);

% Setup optimization options
options = optimset('TolX', 1e-2, 'Display', 'off', 'MaxFunEvals', 30, ...
    'OutputFcn', @(x, optimValues, state) waitbar_update(x, optimValues, state, f));

z0 = (zmin + zmax) / 2;

[zopti, fval, exitflag, output] = fminsearch(obj, z0, options);

if exitflag ~= 1
    fprintf("Autofocus did not converge. Keeping original z = %.6f\n", Params.spatialPropagation);
    z_opti = Params.spatialPropagation;
else
    fprintf("Autofocus converged in %d iterations. Optimal z = %.6f with cost = %.6f\n", ...
        output.iterations, zopti, fval);
    z_opti = zopti;
end

end

% -------------------------------------------------------------------------
function img = renderM0(rend, Params, z)
Params.spatialPropagation = z;
rend.Render(Params, {"power_Doppler"}, cache_intermediate_results = false);
img = rend.getImages({"power_Doppler"});
img = img{1};
end

% -------------------------------------------------------------------------
function c = cost_function(rend, Params, z)
img = renderM0(rend, Params, z);
c = cost_2(img);
end

% -------------------------------------------------------------------------
function v = cost_2(I)
G = edge(I, 'sobel');
disk = diskMask(size(I, 2), size(I, 1), 0.35);
v = -mean(G(disk));
end

% -------------------------------------------------------------------------
function stop = waitbar_update(~, optimValues, state, f)
stop = false;
if strcmp(state, 'iter')
    waitbar(optimValues.iteration / 30, f, ...
        sprintf('Autofocus iteration %d', optimValues.iteration));
end
end