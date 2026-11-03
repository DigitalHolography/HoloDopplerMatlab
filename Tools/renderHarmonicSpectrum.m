function [img, data] = renderHarmonicSpectrum( ...
    fftValues, spectralAxis, harmonicIndices, axisLabel)
% RENDERHARMONICSPECTRUM Render an existing FFT without changing its values.
%
% Both the FFT and its coordinate axis must be vectors in matching order.
% harmonicIndices contains the indices actually used to extract h1 and h2.

if nargin < 4
    axisLabel = 'Spectral coordinate';
end

% Accept FFT data coming from a GPU calculation.
if isa(fftValues, 'gpuArray')
    fftValues = gather(fftValues);
end

if isa(spectralAxis, 'gpuArray')
    spectralAxis = gather(spectralAxis);
end

if isa(harmonicIndices, 'gpuArray')
    harmonicIndices = gather(harmonicIndices);
end

validateattributes(fftValues, {'single', 'double'}, ...
    {'vector', 'nonempty', 'finite'}, mfilename, 'fftValues');

validateattributes(spectralAxis, {'numeric'}, ...
    {'vector', 'real', 'finite', 'numel', numel(fftValues)}, ...
    mfilename, 'spectralAxis');

validateattributes(harmonicIndices, {'numeric'}, ...
    {'vector', 'numel', 2, 'integer', 'positive', ...
     '<=', numel(fftValues)}, ...
    mfilename, 'harmonicIndices');

fftValues = fftValues(:);
spectralAxis = double(spectralAxis(:));
harmonicIndices = double(harmonicIndices(:));

% Preserve every FFT coefficient and its original extraction index.
% If the supplied axis is ambiguous, display array positions instead.
inputSpectralAxis = spectralAxis;
inputAxisLabel = char(string(axisLabel));

if numel(unique(spectralAxis)) ~= numel(spectralAxis)
    warning('HoloDoppler:HarmonicSpectrum:DuplicateCoordinates', ...
        ['The supplied spectral axis contains repeated coordinates. ' ...
        'Displaying FFT array indices instead; FFT values and ' ...
        'harmonic extraction indices are unchanged.']);

    spectralAxis = (1:numel(fftValues)).';
    axisLabel = 'FFT array index (MATLAB, one-based)';
end

data = struct( ...
    'axis', spectralAxis, ...
    'axisLabel', char(string(axisLabel)), ...
    'inputAxis', inputSpectralAxis, ...
    'inputAxisLabel', inputAxisLabel, ...
    'fft', fftValues, ...
    'harmonicIndices', harmonicIndices, ...
    'harmonicCoefficients', fftValues(harmonicIndices));

% Sort only the plotted coordinates.
% Stored FFT values and extraction indices remain unchanged.
[x, order] = sort(spectralAxis);
amplitude = double(abs(fftValues));
phase = double(angle(fftValues));

fig = figure( ...
    'Visible', 'off', ...
    'Color', 'white', ...
    'Position', [100 100 1000 650], ...
    'MenuBar', 'none', ...
    'ToolBar', 'none', ...
    'NumberTitle', 'off', ...
    'Name', 'Harmonic spectrum');

cleanup = onCleanup(@() delete(fig)); %#ok<NASGU>

layout = tiledlayout(fig, 2, 1, ...
    'TileSpacing', 'compact', ...
    'Padding', 'compact');

colors = [0.85 0.20 0.15; 0.15 0.55 0.20];

% Amplitude: show the original FFT modulus, without rescaling.
axAmplitude = nexttile(layout);

plot(axAmplitude, x, amplitude(order), ...
    'Color', [0.15 0.35 0.75], ...
    'LineWidth', 1.2);

hold(axAmplitude, 'on');
grid(axAmplitude, 'on');

ylabel(axAmplitude, '|FFT|');
title(axAmplitude, 'FFT used for harmonic extraction');

% Phase is undefined at exactly zero amplitude.
phase(amplitude == 0) = NaN;

axPhase = nexttile(layout);

plot(axPhase, x, phase(order), ...
    'Color', [0.15 0.35 0.75], ...
    'LineWidth', 1);

hold(axPhase, 'on');
grid(axPhase, 'on');

ylabel(axPhase, 'Phase (rad)');
xlabel(axPhase, data.axisLabel);
ylim(axPhase, [-pi pi]);
yticks(axPhase, [-pi 0 pi]);
yticklabels(axPhase, {'-pi', '0', 'pi'});

for k = 1:2
    index = harmonicIndices(k);
    coordinate = spectralAxis(index);
    label = sprintf('h%d', k);

    xline(axAmplitude, coordinate, '--', label, ...
        'Color', colors(k, :), ...
        'LineWidth', 1.2);

    plot(axAmplitude, coordinate, amplitude(index), 'o', ...
        'Color', colors(k, :), ...
        'MarkerFaceColor', colors(k, :));

    xline(axPhase, coordinate, '--', ...
        'Color', colors(k, :), ...
        'LineWidth', 1.2);

    plot(axPhase, coordinate, phase(index), 'o', ...
        'Color', colors(k, :), ...
        'MarkerFaceColor', colors(k, :));
end

linkaxes([axAmplitude axPhase], 'x');

% Rasterize the diagnostic without getframe.
temporaryImage = [tempname '.png'];
fileCleanup = onCleanup(@() deleteTemporaryImage(temporaryImage)); %#ok<NASGU>

exportgraphics(fig, temporaryImage, ...
    'Resolution', 120, ...
    'BackgroundColor', 'white');

img = imread(temporaryImage);

end

function deleteTemporaryImage(filename)

if isfile(filename)
    delete(filename);
end

end
