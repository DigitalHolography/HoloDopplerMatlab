function [fitObj, gof] = fit_spectrum_gaussian( ...
    axis_x, signal, f1, f2, opt)
%FIT_SPECTRUM_GAUSSIAN Fit an aliased Gaussian without baseline.
%
% Fitting band:
%   f1 <= abs(x) <= f2
%
% Model:
%   y = A * Gperiodic(x; mu, w, Fs) + C
%
% Optimized parameters:
%   A >= 0
%   w > 0
%   C >= 0
%
% The center is NOT optimized:
%   mu = M1 / M0
%
% Moments are discrete sums over the selected fitting samples:
%   M0 = sum(momentSignal)
%   M1 = sum(x .* momentSignal)
%
% If momentSignal is omitted, signal is used for the moments.
%
% Width convention:
%   w = intrinsic Gaussian FWHM
%   sigma = w / (2 * sqrt(2 * log(2)))
%
% All frequencies, including Fs, must use the same units.
%
% verbose controls console output only.
% plot controls automatic curve plotting.
% annotation controls automatic text annotation.
%
% Requires Optimization Toolbox.

arguments
    axis_x (:, 1) {mustBeNumeric, mustBeReal}
    signal (:, 1) {mustBeNumeric, mustBeReal}

    f1 (1, 1) ...
        {mustBeNumeric, mustBeReal, mustBeFinite, mustBePositive}

    f2 (1, 1) ...
        {mustBeNumeric, mustBeReal, mustBeFinite, ...
        mustBePositive, mustBeGreaterThan(f2, f1)}

    opt.Fs (1, 1) double ...
        {mustBeReal, mustBePositive} = NaN

    opt.momentSignal {mustBeNumeric, mustBeReal} = []

    opt.annotation (1, 1) logical = false
    opt.plot (1, 1) logical = false
    opt.verbose (1, 1) logical = true
end

%% Model configuration

modelName = 'Aliased Gaussian, no baseline';
parameterNames = {'A', 'w'};
nFree = numel(parameterNames);

%% Validate and prepare data

assert(isfinite(opt.Fs), ...
    'Provide a finite sampling frequency using Fs=... .');

Fs = opt.Fs;

assert(f2 <= Fs / 2, ...
    'f2 must not exceed the Nyquist frequency Fs/2.');

x = double(axis_x);
y = double(signal);

assert(numel(x) == numel(y), ...
    'axis_x and signal must have the same number of elements.');

if isempty(opt.momentSignal)
    momentSignal = y;
    momentSource = 'signal';
else
    assert(isvector(opt.momentSignal), ...
        'momentSignal must be a vector.');

    momentSignal = double(opt.momentSignal(:));
    momentSource = 'momentSignal';

    assert(numel(momentSignal) == numel(x), ...
        'momentSignal and axis_x must have the same length.');
end

fitMask = ...
    isfinite(x) & isfinite(y) ...
    & abs(x) >= f1 & abs(x) <= f2;

xf = x(fitMask);
yf = y(fitMask);
mf = momentSignal(fitMask);

assert(numel(xf) > nFree ...
    && numel(unique(xf)) > nFree, ...
    ['More than %d distinct finite fitting coordinates ' ...
    'are required.'], nFree);

[xf, order] = sort(xf);
yf = yf(order);
mf = mf(order);

%% Fix the center using M1/M0

assert(all(isfinite(mf)) && all(mf >= 0), ...
    ['Moment weights must be finite and nonnegative ' ...
    'throughout the fitting band.']);

momentScale = max(mf);

assert(momentScale > 0, ...
    'The moment signal must contain positive weights.');

normalizedMomentWeights = mf / momentScale;
normalizedM0 = sum(normalizedMomentWeights);

xScale = max(abs(xf));

normalizedM1 = sum( ...
    (xf / xScale) .* normalizedMomentWeights);

mu = xScale * normalizedM1 / normalizedM0;

M0 = momentScale * normalizedM0;
M1 = momentScale * xScale * normalizedM1;

%% Numerical scaling

yScale = max(abs(yf));

assert(xScale > 0 && yScale > 0, ...
    'The selected coordinates and signal must not be all zero.');

xs = xf / xScale;
ys = yf / yScale;

muScaled = mu / xScale;
FsScaled = Fs / xScale;

assert(max(ys) > min(ys), ...
    'The selected signal is constant; a peak cannot be identified.');

%% Initial parameters

w0 = (f2 - f1) / (3 * xScale);

unitProfile0 = gaussian_aliased( ...
    [1, muScaled, w0, 0], xs, FsScaled);

signalContrast = max(ys) - min(ys);
unitContrast0 = max(unitProfile0) - min(unitProfile0);

assert(all(isfinite(unitProfile0)) && unitContrast0 > 0, ...
    'The initial aliased profile is numerically constant.');

A0 = signalContrast / unitContrast0;

% Initial baseline must satisfy C >= 0.
C0 = max(0, min(ys) - A0 * min(unitProfile0));

minWidth = 1e-8;

% Free parameters: [A, w, C].
q0 = [A0, w0, C0];
lb = [0, minWidth, 0];
ub = [Inf, Inf, Inf];

modelScaled = @(q, xq) gaussian_aliased( ...
    [q(1), muScaled, q(2), q(3)], xq, FsScaled);

%% Fit

options = optimoptions('lsqcurvefit', ...
    'Display', 'off', ...
    'MaxIterations', 2000, ...
    'MaxFunctionEvaluations', 20000);

fitTimer = tic;

[q, resnorm, residual, exitflag, output] = lsqcurvefit( ...
    modelScaled, q0, xs, ys, lb, ub, options);

elapsedTime = toc(fitTimer);

%% Convert to original units

fitObj.A = q(1) * yScale * xScale;
fitObj.mu = mu;
fitObj.w = q(2) * xScale;
fitObj.C = q(3) * yScale;

fitObj.sigma = fitObj.w / (2 * sqrt(2 * log(2)));
fitObj.fwhm = fitObj.w;

fitObj.model = modelName;
fitObj.profileMode = 'gaussian';
fitObj.Fs = Fs;

fitObj.muMethod = 'M1/M0 over the fitting samples';
fitObj.muFixed = true;

fitObj.momentSource = momentSource;
fitObj.M0 = M0;
fitObj.M1 = M1;

fitObj.freeParameterNames = parameterNames;

params = [fitObj.A, fitObj.mu, fitObj.w, fitObj.C];

fitObj.evaluate = @(xq) ...
    gaussian_aliased(params, double(xq), Fs);

fitObj.evaluateIntrinsic = @(xq) ...
    gaussian_intrinsic(params, double(xq));

%% Goodness of fit

yfit = fitObj.evaluate(xf);

SSE = sum((yf - yfit) .^ 2);
SST = sum((yf - mean(yf)) .^ 2);

gof.rsquare = NaN;

if SST > 0
    gof.rsquare = 1 - SSE / SST;
end

gof.sse = SSE;
gof.rmse = sqrt(SSE / numel(yf));

% Conditional on the center already being fixed.
gof.dfe = numel(yf) - nFree;
gof.nFreeParameters = nFree;
gof.nSamples = numel(yf);

gof.exitflag = exitflag;
gof.output = output;
gof.elapsedTime = elapsedTime;

gof.resnorm = resnorm * yScale ^ 2;
gof.residual = residual * yScale;

gof.meanResidual = mean(gof.residual);
gof.maxAbsResidual = max(abs(gof.residual));

gof.x = xf;
gof.y = yf;
gof.yfit = yfit;

boundTolerance = 1e-6 * (1 + abs(q));

gof.atLowerBound = ...
    isfinite(lb) & abs(q - lb) <= boundTolerance;

gof.atUpperBound = ...
    isfinite(ub) & abs(q - ub) <= boundTolerance;

gof.freeParameterNames = parameterNames;

if exitflag <= 0
    warning('fit_spectrum_gaussian:Convergence', ...
        'The optimizer did not report successful convergence: %s', ...
        output.message);
end

%% Console report: no graphics side effects

if opt.verbose
    print_fit_report(fitObj, gof, f1, f2);
end

%% Optional plot and annotation

if opt.plot || opt.annotation
    ax = gca;

    if opt.plot
        xx = linspace(-f2, f2, 2000).';
        yy = fitObj.evaluate(xx);

        yy(abs(xx) < f1 | abs(xx) > f2) = NaN;

        wasHeld = ishold(ax);
        hold(ax, 'on');

        plot(ax, xx, yy, ...
            'Color', [0.85, 0.1, 0.1], ...
            'LineStyle', '--', ...
            'LineWidth', 1.8, ...
            'DisplayName', modelName);

        if ~wasHeld
            hold(ax, 'off');
        end
    end

    if opt.annotation
        txt = sprintf([ ...
            '%s\n' ...
            'A = %.4g\n' ...
            '\\mu = %.4g (M_1/M_0, fixed)\n' ...
            'Intrinsic FWHM = %.4g\n' ...
            '\\sigma = %.4g\n' ...
            'C = %.4g\n' ...
            'R^2 = %.4f'], ...
            fitObj.model, ...
            fitObj.A, ...
            fitObj.mu, ...
            fitObj.fwhm, ...
            fitObj.sigma, ...
            fitObj.C, ...
            gof.rsquare);

        text(ax, 0.02, 0.98, txt, ...
            'Units', 'normalized', ...
            'HorizontalAlignment', 'left', ...
            'VerticalAlignment', 'top', ...
            'Interpreter', 'tex', ...
            'FontSize', 9, ...
            'Color', [0.85, 0.1, 0.1]);
    end
end

end


function y = gaussian_intrinsic(p, x)
% Intrinsic, area-normalized Gaussian with baseline.
% p = [A, mu, w, C].

A = p(1);
mu = p(2);
w = p(3);
C = p(4);

sigma = w / (2 * sqrt(2 * log(2)));

z = (x - mu) / sigma;

y = A * exp(-0.5 * z .^ 2) / (sigma * sqrt(2 * pi)) + C;

end


function y = gaussian_aliased(p, x, Fs)
% Periodized, area-normalized Gaussian with baseline.
% p = [A, mu, w, C].

A = p(1);
mu = p(2);
w = p(3);
C = p(4);

sigma = w / (2 * sqrt(2 * log(2)));

dx = mod(x - mu + Fs / 2, Fs) - Fs / 2;

y = A .* gaussian_periodic(dx, sigma, Fs) + C;

end


function Gper = gaussian_periodic(dx, sigma, Fs)
% Periodic Gaussian: image sum or Fourier series.

tol = 1e-12;
ratio = sigma / Fs;

if ratio < 0.2
    cutoff = sqrt(2 * log(1 / tol));
    K = ceil(0.5 + cutoff * ratio);

    Gper = zeros(size(dx));

    for k = -K:K
        z = (dx + k * Fs) / sigma;
        Gper = Gper + exp(-0.5 * z .^ 2);
    end

    Gper = Gper / (sigma * sqrt(2 * pi));
else
    N = ceil( ...
        sqrt(2 * log(1 / tol)) / (2 * pi * ratio));

    theta = 2 * pi * dx / Fs;

    Gper = ones(size(dx));

    for n = 1:N
        coefficient = exp(-2 * pi ^ 2 * (ratio * n) ^ 2);

        Gper = Gper ...
            + 2 * coefficient .* cos(n * theta);
    end

    Gper = Gper / Fs;
end

end


function print_fit_report(fitObj, gof, f1, f2)
% Console-only diagnostic report.

separator = repmat('-', 1, 70);

if gof.exitflag > 0
    status = 'Converged';
else
    status = 'Not successfully converged';
end

fprintf('\n%s\n', separator);
fprintf('%s\n', fitObj.model);
fprintf('%s\n', separator);

fprintf('Status           : %s (exitflag = %d)\n', ...
    status, gof.exitflag);

fprintf('Fitting band     : %.6g <= |f| <= %.6g\n', f1, f2);
fprintf('Sampling freq.   : %.6g\n', fitObj.Fs);
fprintf('Samples          : %d\n', gof.nSamples);
fprintf('Free parameters  : %d\n', gof.nFreeParameters);
fprintf('Elapsed time     : %.3f s\n', gof.elapsedTime);

fprintf('\nParameters in input units\n');
fprintf('  A              = %.8g\n', fitObj.A);
fprintf('  mu             = %.8g  [fixed: M1/M0]\n', fitObj.mu);
fprintf('  w / FWHM       = %.8g  [intrinsic]\n', fitObj.w);
fprintf('  w / Fs         = %.6g\n', fitObj.w / fitObj.Fs);
fprintf('  sigma          = %.8g\n', fitObj.sigma);
fprintf('  C              = %.8g  [C >= 0]\n', fitObj.C);

fprintf('\nCenter estimation\n');
fprintf('  Weights        : %s\n', fitObj.momentSource);
fprintf('  M0             = %.8g\n', fitObj.M0);
fprintf('  M1             = %.8g\n', fitObj.M1);

fprintf('\nFit quality on the selected samples\n');
fprintf('  R^2            = %.6f\n', gof.rsquare);
fprintf('  SSE            = %.8g\n', gof.sse);
fprintf('  RMSE           = %.8g\n', gof.rmse);

fprintf('  Mean residual  = %.8g  [model - data]\n', ...
    gof.meanResidual);

fprintf('  Max |residual| = %.8g\n', gof.maxAbsResidual);
fprintf('  DFE            = %d  [conditional on fixed mu]\n', gof.dfe);

if isfield(gof.output, 'iterations')
    fprintf('  Iterations     = %d\n', gof.output.iterations);
end

if isfield(gof.output, 'funcCount')
    fprintf('  Function calls = %d\n', gof.output.funcCount);
end

if isfield(gof.output, 'firstorderopt')
    fprintf('  Optimality     = %.6g\n', ...
        gof.output.firstorderopt);
end

activeLower = gof.freeParameterNames(gof.atLowerBound);
activeUpper = gof.freeParameterNames(gof.atUpperBound);

if ~isempty(activeLower)
    fprintf('\nNear lower bound : %s\n', ...
        strjoin(activeLower, ', '));
end

if ~isempty(activeUpper)
    fprintf('Near upper bound : %s\n', ...
        strjoin(activeUpper, ', '));
end

fprintf('\nSolver message\n%s\n', strtrim(gof.output.message));
fprintf('%s\n', separator);

end