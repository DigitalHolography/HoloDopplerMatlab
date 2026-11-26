function [fitObj, gof] = fit_spectrum_voigt( ...
    axis_x, signal, f1, f2, opt)
%FIT_SPECTRUM_VOIGT Fit an aliased, area-normalized peak profile.
%
% Fitting band:
%   f1 <= abs(x) <= f2
%
% Model:
%   y = A * [(1-eta)*Gperiodic + eta*Lperiodic] + C
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
% Hard-coded profile selection:
%   PROFILE_MODE = 'pseudo-voigt'
%   PROFILE_MODE = 'gaussian'
%   PROFILE_MODE = 'lorentzian'
%
% Constraints:
%   A >= 0
%   w > 0
%   0 <= eta <= 1, when eta is optimized
%   C >= 0
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

    opt.annotation (1, 1) logical = true
    opt.plot (1, 1) logical = false
    opt.verbose (1, 1) logical = true

end

%% Hard-coded profile selection

% PROFILE_MODE = 'pseudo-voigt';
PROFILE_MODE = 'gaussian';
% PROFILE_MODE = 'lorentzian';

switch PROFILE_MODE

    case 'pseudo-voigt'

        fitEta = true;
        fixedEta = NaN;

        parameterNames = {'A', 'w', 'eta', 'C'};
        modelName = 'Aliased pseudo-Voigt';

    case 'gaussian'

        fitEta = false;
        fixedEta = 0;

        parameterNames = {'A', 'w', 'C'};
        modelName = 'Aliased Gaussian';

    case 'lorentzian'

        fitEta = false;
        fixedEta = 1;

        parameterNames = {'A', 'w', 'C'};
        modelName = 'Aliased Lorentzian';

    otherwise

        error('fit_spectrum_voigt:InvalidProfile', ...
            'Unknown PROFILE_MODE: "%s".', PROFILE_MODE);

end

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

nFree = numel(parameterNames);

assert(numel(xf) > nFree ...
    && numel(unique(xf)) > nFree, ...
    ['More than %d distinct finite fitting coordinates ' ...
 'are required for this profile.'], nFree);

[xf, order] = sort(xf);

yf = yf(order);
mf = mf(order);

%% Fix the center using M1/M0

assert(all(isfinite(mf)) && all(mf >= 0), ...
    ['Moment weights must be finite and nonnegative ' ...
     'throughout the fitting band. Provide momentSignal=S ' ...
 'when fitting log10(S).']);

momentScale = max(mf);

assert(momentScale > 0, ...
'The moment signal must contain positive weights.');

% Normalize the weights to improve numerical scaling.
normalizedMomentWeights = mf / momentScale;

normalizedM0 = sum(normalizedMomentWeights);

xScale = max(abs(xf));

normalizedM1 = sum( ...
    (xf / xScale) .* normalizedMomentWeights);

mu = xScale * normalizedM1 / normalizedM0;

% Discrete moments, before numerical normalization.
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

%% Initial parameters

w0 = (f2 - f1) / (3 * xScale);

if fitEta
    eta0 = 0.5;
else
    eta0 = fixedEta;
end

signalContrast = max(ys) - min(ys);

assert(signalContrast > 0, ...
'The selected signal is constant; a peak cannot be identified.');

unitProfile0 = pseudo_voigt_aliased( ...
    [1, muScaled, w0, eta0, 0], xs, FsScaled);

unitContrast0 = max(unitProfile0) - min(unitProfile0);

assert(isfinite(unitContrast0) && unitContrast0 > 0, ...
'The initial aliased profile is numerically constant.');

A0 = signalContrast / unitContrast0;

% Initial baseline must satisfy C >= 0.
C0 = max(0, min(ys) - A0 * min(unitProfile0));

minWidth = 1e-8;

if fitEta

    % Free parameters: [A, w, eta, C].
    q0 = [A0, w0, eta0, C0];

    lb = [0, minWidth, 0, 0];
    ub = [Inf, Inf, 1, Inf];

else

    % Free parameters: [A, w, C].
    q0 = [A0, w0, C0];

    lb = [0, minWidth, 0];
    ub = [Inf, Inf, Inf];

end

modelScaled = @(q, xq) pseudo_voigt_aliased( ...
    expand_parameters(q, muScaled, fitEta, fixedEta), ...
    xq, FsScaled);

%% Fit

options = optimoptions('lsqcurvefit', ...
    'Display', 'off', ...
    'MaxIterations', 2000, ...
    'MaxFunctionEvaluations', 20000);

fitTimer = tic;

[q, resnorm, residual, exitflag, output] = lsqcurvefit( ...
    modelScaled, q0, xs, ys, lb, ub, options);

elapsedTime = toc(fitTimer);

p = expand_parameters(q, muScaled, fitEta, fixedEta);

%% Convert to original units

fitObj.A = p(1) * yScale * xScale;
fitObj.mu = mu;
fitObj.w = p(3) * xScale;
fitObj.eta = p(4);
fitObj.C = p(5) * yScale;

fitObj.sigma = fitObj.w / (2 * sqrt(2 * log(2)));
fitObj.gamma = fitObj.w / 2;
fitObj.fwhm = fitObj.w;

fitObj.model = modelName;
fitObj.profileMode = PROFILE_MODE;
fitObj.Fs = Fs;

fitObj.muMethod = 'M1/M0 over the fitting samples';
fitObj.muFixed = true;
fitObj.momentSource = momentSource;
fitObj.M0 = M0;
fitObj.M1 = M1;

fitObj.etaFixed = ~fitEta;
fitObj.freeParameterNames = parameterNames;

if strcmp(PROFILE_MODE, 'gaussian')

    fitObj.profileType = 'Gaussian only';

elseif strcmp(PROFILE_MODE, 'lorentzian')

    fitObj.profileType = 'Lorentzian only';

elseif fitObj.eta < 0.25

    fitObj.profileType = 'Gaussian-dominant';

elseif fitObj.eta > 0.75

    fitObj.profileType = 'Lorentzian-dominant';

else

    fitObj.profileType = 'Mixed Gaussian/Lorentzian';

end

params = [ ...
              fitObj.A, fitObj.mu, fitObj.w, fitObj.eta, fitObj.C];

fitObj.evaluate = @(xq) ...
    pseudo_voigt_aliased(params, double(xq), Fs);

fitObj.evaluateIntrinsic = @(xq) ...
    pseudo_voigt(params, double(xq));

%% Goodness of fit

yfit = fitObj.evaluate(xf);

SSE = sum((yf - yfit) .^ 2);
SST = sum((yf - mean(yf)) .^ 2);

gof.rsquare = NaN;

if SST > 0
    gof.rsquare = 1 - SSE / SST;
end

gof.sse = SSE;

% Sample-wise RMS of residuals.
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

% Numerical proximity to bounds, in scaled parameter coordinates.
boundTolerance = 1e-6 * (1 + abs(q));

gof.atLowerBound = ...
    isfinite(lb) & abs(q - lb) <= boundTolerance;

gof.atUpperBound = ...
    isfinite(ub) & abs(q - ub) <= boundTolerance;

gof.freeParameterNames = parameterNames;

if exitflag <= 0

    warning('fit_spectrum_voigt:Convergence', ...
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
                           '%s\n' ...
                           '\\mu = %.4g (M_1/M_0, fixed)\n' ...
                           'FWHM = %.4g\n' ...
                           '\\eta = %.3f\n' ...
                           'C = %.4g\n' ...
                       'R^2 = %.4f'], ...
            fitObj.model, ...
            fitObj.profileType, ...
            fitObj.mu, ...
            fitObj.fwhm, ...
            fitObj.eta, ...
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

function p = expand_parameters(q, mu, fitEta, fixedEta)
% Construct the full model vector [A, mu, w, eta, C].

if fitEta

    p = [q(1), mu, q(2), q(3), q(4)];

else

    p = [q(1), mu, q(2), fixedEta, q(3)];

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

fprintf('Profile          : %s\n', fitObj.profileType);
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
fprintf('  w / FWHM       = %.8g\n', fitObj.w);
fprintf('  w / Fs         = %.6g\n', fitObj.w / fitObj.Fs);

if fitObj.etaFixed
    fprintf('  eta            = %.6f  [fixed]\n', fitObj.eta);
else
    fprintf('  eta            = %.6f  [optimized]\n', fitObj.eta);
end

fprintf('  C              = %.8g  [C >= 0]\n', fitObj.C);
fprintf('  sigma          = %.8g\n', fitObj.sigma);
fprintf('  gamma          = %.8g\n', fitObj.gamma);

fprintf('\nCenter estimation\n');
fprintf('  Weights        : %s\n', fitObj.momentSource);
fprintf('  M0             = %.8g\n', fitObj.M0);
fprintf('  M1             = %.8g\n', fitObj.M1);
fprintf('  Baseline       : not subtracted from moment weights\n');

fprintf('\nFit quality on the selected samples\n');
fprintf('  R^2            = %.6f\n', gof.rsquare);
fprintf('  SSE            = %.8g\n', gof.sse);
fprintf('  RMSE           = %.8g\n', gof.rmse);
fprintf('  Mean residual  = %.8g  [model - data]\n', ...
    gof.meanResidual);
fprintf('  Max |residual| = %.8g\n', gof.maxAbsResidual);
fprintf('  DFE            = %d  [conditional on fixed mu]\n', ...
    gof.dfe);

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

function y = pseudo_voigt(p, x)
% Intrinsic, area-normalized Gaussian/Lorentzian mixture.

A = p(1);
mu = p(2);
w = p(3);
eta = p(4);
C = p(5);

sigma = w / (2 * sqrt(2 * log(2)));
gamma = w / 2;

dx = x - mu;
profile = zeros(size(x));

if eta < 1

    G = exp(-0.5 * (dx ./ sigma) .^ 2) ...
        / (sigma * sqrt(2 * pi));

    profile = profile + (1 - eta) .* G;

end

if eta > 0

    L = gamma ./ (pi * (dx .^ 2 + gamma ^ 2));

    profile = profile + eta .* L;

end

y = A .* profile + C;

end

function y = pseudo_voigt_aliased(p, x, Fs)
% Periodized, area-normalized Gaussian/Lorentzian mixture.

A = p(1);
mu = p(2);
w = p(3);
eta = p(4);
C = p(5);

sigma = w / (2 * sqrt(2 * log(2)));
gamma = w / 2;

dx = mod(x - mu + Fs / 2, Fs) - Fs / 2;

profile = zeros(size(x));

% Skip the Gaussian calculation when it is disabled.
if eta < 1

    Gper = gaussian_periodic(dx, sigma, Fs);

    profile = profile + (1 - eta) .* Gper;

end

% Skip the Lorentzian calculation when it is disabled.
if eta > 0

    a = 2 * pi * gamma / Fs;
    theta = 2 * pi * dx / Fs;

    q = exp(-a);

    numerator = -expm1(-2 * a);

    denominator = (-expm1(-a)) ^ 2 ...
        + 4 * q .* sin(theta / 2) .^ 2;

    Lper = numerator ./ (Fs * denominator);

    profile = profile + eta .* Lper;

end

y = A .* profile + C;

end

function Gper = gaussian_periodic(dx, sigma, Fs)
% Periodic Gaussian: spatial image sum or Fourier series.

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
