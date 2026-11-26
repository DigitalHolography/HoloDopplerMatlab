function [fitObj, gof] = fit_spectrum(axis_x, signal, f1, f2, opt)
% Fit a spectrum to a model of the form:
%   y = a + b*log10(g^2) - b*log10(x^2 + g^2)
% where:
%   a = baseline level
%   b = slope of the log10 term
%   g = width parameter (in kHz)

arguments
    axis_x (:, 1) {mustBeNumeric}
    signal (:, 1) {mustBeNumeric}
    f1 (1, 1) {mustBeNumeric, mustBePositive}
    f2 (1, 1) {mustBeNumeric, mustBePositive, mustBeGreaterThan(f2, f1)}
    opt.annotation (1, 1) logical = true
    opt.verbose (1, 1) logical = true
end

% Model
x = double(axis_x(:));
y = double(signal(:));

% Initial guess for center (g) can be the centroid of the spectrum, or a fraction of the fitting range
x0 = sum(x .* y) / sum(y); % centroid as initial guess for center
x = x - x0; % shift x to center around initial guess

% Restrict to fitting range
fitMask = (abs(x) <= f2) & (abs(x) >= f1);
xf = x(fitMask);
yf = y(fitMask);

% Symmetric Fit
xf_fit = xf;
yf_fit = yf;

% Define fit type
ft = fittype('a + b*log10(g^2) - b*log10((x).^2 + g^2)', ...
    'independent', 'x', 'coefficients', {'a', 'b', 'g'});

% Initial guesses
% a ~ min(y), b ~ (max-min)/log10(range^2/g^2)
a0 = min(yf_fit);
g0 = max((f1 + eps) * 0.25, (f2 + eps) * 0.02); % width guess in kHz
b0 = 1; % slope guess
start = [a0, b0, g0];

% Bounds (helps prevent nonsense fits)
lb = [-Inf, -Inf, 0]; % relax if needed
ub = [Inf, Inf, Inf];

opts = fitoptions(ft);
opts.StartPoint = start;
opts.Lower = lb;
opts.Upper = ub;
opts.Robust = 'Bisquare'; % robust to spikes/outliers
opts.MaxIter = 2000;
opts.Display = 'off';

% Fit
warning('off')
[fitObj, gof] = fit(xf_fit, yf_fit, ft, opts);
warning('on')

% Evaluate fit over full axis for overlay
xx = linspace(min(x), max(x), 2000).';
yy = fitObj.a + fitObj.b * log10(fitObj.g ^ 2) - fitObj.b * log10(xx .^ 2 + fitObj.g ^ 2);

% Plot overlay
if opt.verbose
    p_fit = plot(xx, yy, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Fit: a - b log10(x^2+g^2)');
end

% Report parameters in command window and optionally on plot
txt = sprintf('Fit: a=%.3g, b=%.3g,\ng=%.3g kHz | R^2=%.4f', fitObj.a, fitObj.b, fitObj.g, gof.rsquare);

% Put a small annotation in the corner
if opt.annotation
    yl = ylim;
    xl = xlim;
    text(xl(1) + 0.02 * range(xl), yl(2) - 0.2 * range(yl), txt, ...
        'FontSize', 9, 'Color', 'r', 'Interpreter', 'none');
    uistack(p_fit, 'top');
end

if opt.verbose
    disp(txt);
    fprintf('---------------\n');
end

end
