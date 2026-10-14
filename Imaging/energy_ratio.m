function [ratio, f_c] = energy_ratio(SH, f1, f2, fi1, fi2, fs, batchSize)
    %ENERGY_RATIO High-/low-frequency mean ratio relative to the centroid.
    %
    % Centroid estimation band: fi1 <= |f| <= f2.
    %
    % Compensated low band:  fi1 <= |f - f_c| < fi2.
    % Compensated high band: fi2 <= |f - f_c| <= f2.
    %
    % f1 is retained for compatibility but is not used.

    arguments
        SH
        f1 (1, 1) double {mustBeNonnegative}
        f2 (1, 1) double {mustBePositive}
        fi1 (1, 1) double {mustBeNonnegative}
        fi2 (1, 1) double {mustBeNonnegative}
        fs (1, 1) double {mustBePositive}
        batchSize (1, 1) double {mustBeInteger, mustBePositive}
    end

    if ~(fi1 < fi2 && fi2 < f2)
        error('energy_ratio:InvalidBands', ...
        'Band limits must satisfy fi1 < fi2 < f2.');
    end

    if size(SH, 3) ~= batchSize
        error('energy_ratio:InvalidSize', ...
        'The third dimension of SH must equal batchSize.');
    end

    S = abs(SH);

    f = fftfreq(batchSize, 1 / fs);
    F = reshape(f, 1, 1, []);

    % Estimation du centroïde sur la bande bilatérale originale
    centerMask = abs(f) >= fi1 & abs(f) <= f2;

    if ~any(centerMask)
        error('energy_ratio:EmptyCenterBand', ...
        'The centroid estimation band contains no FFT bin.');
    end

    Sc = S(:, :, centerMask);
    Fc = reshape(f(centerMask), 1, 1, []);

    M0 = sum(Sc, 3, 'omitnan');
    M1 = sum(Sc .* Fc, 3, 'omitnan');

    f_c = M1 ./ M0;
    validCenter = isfinite(f_c) & isfinite(M0) & M0 > 0;
    f_c(~validCenter) = NaN;

    % Distance fréquentielle au centroïde de chaque pixel
    absFrel = abs(F - f_c);

    lowMask = absFrel >= fi1 & absFrel < fi2;
    highMask = absFrel >= fi2 & absFrel <= f2;

    % Les bins exclus deviennent NaN :
    % ils ne doivent pas entrer dans le dénominateur de mean.
    SL = S;
    SL(~lowMask) = NaN;
    PL = mean(SL, 3, 'omitnan');
    clear SL

    SHigh = S;
    SHigh(~highMask) = NaN;
    PH = mean(SHigh, 3, 'omitnan');

    ratio = PH ./ PL;
    ratio(~validCenter | ~isfinite(ratio) | PL <= 0) = NaN;

end
