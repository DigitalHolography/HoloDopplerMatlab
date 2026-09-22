function [fitObj, gof] = fit_spectrum_voigt(axis_x, signal, f1, f2, opt)

arguments
    axis_x (:, 1) {mustBeNumeric}
    signal (:, 1) {mustBeNumeric}
    f1 (1, 1) {mustBeNumeric, mustBePositive}
    f2 (1, 1) {mustBeNumeric, mustBePositive, mustBeGreaterThan(f2, f1)}
    opt.annotation (1, 1) logical = true
    opt.verbose (1, 1) logical = true
end

x = double(axis_x(:));
y = double(signal(:));

% --- Restrict fitting range ---
fitMask = (abs(x) <= f2) & (abs(x) >= f1);
xf = x(fitMask);
yf = y(fitMask);

% --- Initial guesses ---
[~, idxMax] = max(yf);
mu0 = xf(idxMax); % center
A0 = max(yf) - min(yf); % amplitude
C0 = min(yf); % baseline

width_est = (f2 - f1) / 6;
sigma0 = width_est / 2; % Gaussian width guess
gamma0 = width_est / 4;

p0 = [A0, mu0, sigma0, gamma0, C0];

lb = [0, min(xf), 0, 0, -Inf];
ub = [Inf, max(xf), Inf, 1, Inf];

opts = optimoptions('lsqcurvefit', 'Display', 'off');

% ----- Voigt model -----
voigt_model = @(p, x) pseudo_voigt(p, x);

params = lsqcurvefit(voigt_model, p0, xf, yf, lb, ub, opts);

% ----- Fit -----
options = optimoptions('lsqcurvefit', ...
    'Display', 'off', ...
    'MaxIterations', 2000);

p = lsqcurvefit(voigt_model, p0, xf, yf, lb, ub, options);

% ----- Outputs -----
fitObj.A = p(1);
fitObj.mu = p(2);
fitObj.w = p(3);
fitObj.eta = p(4);
fitObj.C = p(5);

yfit = voigt_model(params, xf);
Rsq = 1 - sum((yf - yfit) .^ 2) / sum((yf - mean(yf)) .^ 2);

gof.rsquare = Rsq;

% ----- Plot -----
xx = linspace(min(x), max(x), 2000).';
yy = voigt_model(p, xx);

if opt.verbose
    plot(xx, yy, 'r--', 'LineWidth', 1.5);
end

txt = sprintf(['Voigt Fit:\nA=%.3g\nmu=%.3g\n' ...
               'w=%.3g\neta=%.3g\nC=%.3f\nR^2=%.4f\n'], ...
    fitObj.A, fitObj.mu, fitObj.w, fitObj.eta, fitObj.C, gof.rsquare);

if opt.annotation
    yl = ylim;
    xl = xlim;
    text(xl(1) + 0.02 * range(xl), yl(2) - 0.25 * range(yl), txt, ...
        'FontSize', 9, 'Color', 'r');
end

if opt.verbose
    disp(txt);
end

fwhm = 0.5346 * (2 * fitObj.eta) + ...
    sqrt(0.2166 * (2 * fitObj.eta) ^ 2 + ...
    (2 * sqrt(2 * log(2)) * fitObj.w) ^ 2);

fprintf('Estimated FWHM: %f\n', fwhm);

end

function y = pseudo_voigt(p, x)

A = p(1); % amplitude
mu = p(2); % center
w = p(3); % FWHM, gamma and sigma will be derived from this
eta = p(4); % mixing, 0 = pure Gaussian, 1 = pure Lorentzian
C = p(5);

% Gaussian part (FWHM form)
sigma = w / (2 * sqrt(2 * log(2)));
G = exp(- (x - mu) .^ 2 / (2 * sigma ^ 2)) / (sigma * sqrt(2 * pi));

% Lorentzian part (FWHM form)
gamma = w / 2;
L = gamma ./ (pi * ((x - mu) .^ 2 + gamma ^ 2));

V = eta * L + (1 - eta) * G;

y = A * V + C; % Add baseline

end
