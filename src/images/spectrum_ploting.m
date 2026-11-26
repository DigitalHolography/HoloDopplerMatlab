function spectrum_ploting(SH, mask, fs, f1, f2)
%SPECTRUM_PLOTING Summary of this function goes here
%   Detailed explanation goes here

SH_mask = SH .* mask;
spectrumAVG_mask = squeeze(sum(SH_mask, [1 2])) / nnz(mask);

momentM0 = moment0(SH, f1, f2, fs, size(SH_mask, 3));
momentM2 = moment2(SH, f1, f2, fs, size(SH_mask, 3));

% Use the same spatial region for both spectral moments.
roi = logical(mask);

M0 = mean(momentM0(roi), "all");
M2 = mean(momentM2(roi), "all");

if ~isfinite(M0) || M0 <= 0 || ~isfinite(M2) || M2 < 0
    error('spectrum_ploting:InvalidMoments', ...
        ['Cannot compute spectral RMS: M0=%g, M2=%g. ' ...
     'Check the spatial mask, frequency band, and input spectrum.'], ...
        M0, M2);
end

omegaRMS = sqrt(M2 / M0);

% Find the closest nonnegative FFT frequency.
N = size(SH_mask, 3);
f = fftfreq(N, 1 / fs);
positiveBins = find(f >= 0);

[~, nearestBin] = min(abs(f(positiveBins) - omegaRMS));
omegaRMS_index = positiveBins(nearestBin);

spectralValue = spectrumAVG_mask(omegaRMS_index);

if ~isfinite(spectralValue) || spectralValue <= 0
    I_omega = NaN;
else
    I_omega = log10(spectralValue);
end

axis_x = fftshift(f(:));
range_1 = (-f2 < axis_x) & (axis_x <- f1);
range_2 = (f1 < axis_x) & (axis_x < f2);

spectrumAVG_mask(spectrumAVG_mask <= 0) = NaN;
signal_log = fftshift(log10(spectrumAVG_mask));

hold on;
p_mask = plot(axis_x, signal_log, 'black', 'LineWidth', 1, 'DisplayName', 'Arteries');
area(axis_x(range_1), signal_log(range_1), 'EdgeColor', 'black', 'FaceColor', [0.9 0.9 0.9], 'LineWidth', 1, 'DisplayName', 'Arteries');
area(axis_x(range_2), signal_log(range_2), 'EdgeColor', 'black', 'FaceColor', [0.9 0.9 0.9], 'LineWidth', 1, 'DisplayName', 'Arteries');
xlim([-fs / 2 fs / 2])
sclingrange = abs(fftshift(axis_x)) > f1;
yrange = [.88 * log10(min(spectrumAVG_mask(sclingrange))) 1.08 * log10(max(spectrumAVG_mask(sclingrange)))];
ylim(yrange)

om_RMS_line = line([-omegaRMS omegaRMS], [I_omega I_omega]);
om_RMS_line.Color = 'black';
om_RMS_line.LineStyle = '-';
om_RMS_line.Marker = '|';
om_RMS_line.MarkerSize = 12;
om_RMS_line.LineWidth = 1;

xline(f1, '--')
xline(f2, '--')
xline(-f1, '--')
xline(-f2, '--')

if f1 ~= 0
    xticks([-f2 -f1 f1 f2])
    xticklabels({num2str(round(-f2, 1)), num2str(round(-f1, 1)), num2str(round(f1, 1)), num2str(round(f2, 1))})
else
    xticks([-f2 f2])
    xticklabels({num2str(round(-f2, 1)), num2str(round(f2, 1))})
end

% title(sprintf('f_{RMS} = %.2f kHz', omegaRMS))
fontsize(gca, 12, "points");
xlabel('frequency (kHz)', 'FontSize', 14);
ylabel('log10 S', 'FontSize', 14);
grid on
axis on
box on
pbaspect([1.618 1 1]);
set(gca, 'LineWidth', 2);
uistack(p_mask, 'top');
uistack(gca, 'top');

% fit_spectrum_voigt(axis_x, signal_log, f1, f2);

end
