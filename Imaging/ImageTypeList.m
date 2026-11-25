classdef ImageTypeList < handle
% Registry and construction of pipeline images.

properties
    % Doppler
    power_Doppler
    power_1_Doppler
    power_2_Doppler
    color_Doppler
    directional_Doppler
    broadening
    power_Doppler_wiener
    power_adapt

    % Moments
    moment_0
    moment_1
    moment_2
    arg_0
    f_RMS

    % Fields
    SH
    SH_avg
    FH_modulus_mean
    FH_arg_mean

    % SVD
    SVD_cov
    SVD_U

    % Statistics
    cumulative_distribution
    band_ratio
    entropy

    % Gaussian estimates
    gaussian_w
    sigma
    h1
    h2
    harmonic_spectrum

    % Frequency bands
    HF_M0
    LF_M0
end

methods

    function obj = ImageTypeList()
        % Property name -> ImageType export name.
        definitions = {
                       'power_Doppler', 'power'
                       'power_1_Doppler', 'power1'
                       'power_2_Doppler', 'power2'
                       'color_Doppler', 'color'
                       'directional_Doppler', 'directional'
                       'broadening', 'broadening'
                       'power_Doppler_wiener', 'power_wiener'
                       'power_adapt', 'power_adapt'
                       'moment_0', 'M0'
                       'moment_1', 'M1'
                       'moment_2', 'M2'
                       'arg_0', 'arg0'
                       'f_RMS', 'f_RMS'
                       'SH', 'SH'
                       'SH_avg', 'SH_avg'
                       'FH_modulus_mean', 'FH_modulus_mean'
                       'FH_arg_mean', 'FH_arg_mean'
                       'SVD_cov', 'SVD_cov'
                       'SVD_U', 'SVD_U'
                       'cumulative_distribution', 'cdf'
                       'band_ratio', 'energy_ratio'
                       'entropy', 'entropy'
                       'gaussian_w', 'gaussian_w'
                       'sigma', 'sigma'
                       'h1', 'h1'
                       'h2', 'h2'
                       'harmonic_spectrum', 'harmonic_spectrum'
                       'HF_M0', 'HF_M0'
                       'LF_M0', 'LF_M0'
                       };

        for k = 1:size(definitions, 1)
            obj.(definitions{k, 1}) = ImageType(definitions{k, 2});
        end

        obj.power_Doppler.parameters = struct('M0sqrt', []);

        obj.color_Doppler.parameters = struct( ...
            'freq_low', [], 'freq_high', []);

        obj.directional_Doppler.parameters = struct( ...
            'M0_pos', [], 'M0_neg', []);

        fieldParameters = struct( ...
            'SH', [], ...
            'spatial_binning', [], ...
            'original_size', [], ...
            'binned_size', [], ...
            'crop_size', [], ...
            'reduction', []);

        obj.SH.parameters = fieldParameters;
        obj.SH.parameters.vector = [];
        obj.SH_avg.parameters = fieldParameters;

        obj.harmonic_spectrum.parameters = ...
            obj.emptyHarmonicParameters();

    end

    function clear(obj, varargin)
        names = obj.targetNames(varargin);

        for k = 1:numel(names)
            obj.(names{k}).clear();
        end

    end

    function select(obj, varargin)
        obj.clear();

        if isempty(varargin)
            return
        end

        names = obj.targetNames(varargin);

        for k = 1:numel(names)
            obj.(names{k}).select();
        end

    end

    function copy_from(obj, src)
        names = fieldnames(src);

        for k = 1:numel(names)
            obj.(names{k}).copy_from(src.(names{k}));
        end

    end

    function images2png(obj, prefix, folder, varargin)
        names = obj.targetNames(varargin);

        for k = 1:numel(names)
            slot = obj.(names{k});

            if slot.is_selected
                slot.image2png(prefix, folder);
            end

        end

    end

    function construct_image(obj, Params, SHin)

        if isempty(SHin)
            return
        end

        [~, ~, N] = size(SHin);

        fs = Params.fs;
        f1 = Params.frequencyRange1;
        f2 = Params.frequencyRange2;
        fr1 = Params.frequencyRangeBandRatio1;
        fr2 = Params.frequencyRangeBandRatio2;
        gw = Params.flatfield_gw;

        % Reject invalid input before constructing any image.
        badInput = ~isfinite(SHin);

        if any(badInput(:))
            error('ImageTypeList:NonfiniteInput', ...
                ['SHin already contains invalid values before image construction: ' ...
                 '%d NaN and %d Inf out of %d samples. ' ...
             'Inspect the upstream rendering pipeline.'], ...
                nnz(isnan(SHin)), nnz(isinf(SHin)), numel(SHin));
        end

        S = abs(SHin) .^ 2;

        if any(~isfinite(S(:)))
            error('ImageTypeList:NonfinitePower', ...
                ['Power computation produced nonfinite values from finite SHin. ' ...
             'Check input magnitudes and numeric precision.']);
        end

        if Params.CornerCompensation
            S = obj.compensateCorners(S);

            if any(~isfinite(S(:)))
                error('ImageTypeList:NonfiniteCompensatedPower', ...
                'Corner compensation produced nonfinite power values.');
            end

        end

        % Doppler power.
        if obj.power_Doppler.is_selected
            obj.power_Doppler.image = ...
                moment0(S, f1, f2, fs, N, gw);
        end

        if obj.power_1_Doppler.is_selected
            obj.power_1_Doppler.image = ...
                moment1(S, f1, f2, fs, N, gw);
        end

        if obj.power_2_Doppler.is_selected
            obj.power_2_Doppler.image = ...
                moment2(S, f1, f2, fs, N, gw);
        end

        if obj.power_Doppler_wiener.is_selected
            base = moment0(S, f1, f2, fs, N, gw);
            obj.power_Doppler_wiener.image = wiener2(base, [2 2], 10);
        end

        if obj.power_adapt.is_selected
            base = moment0(S, f1, f2, fs, N);
            obj.power_adapt.image = adapthisteq( ...
                rescale(base), 'NumTiles', [12 12], 'NBins', 128);
        end

        % Color and directional Doppler.
        if obj.color_Doppler.is_selected
            M0 = moment0(S, f1, f2, fs, N, gw);
            [low, high] = composite(S, f1, fr2, f2, fs, N, gw);

            obj.color_Doppler.image = ...
                construct_colored_image(M0, low, high);
        end

        if obj.directional_Doppler.is_selected
            [positive, negative] = directional( ...
                S, f1, f2, fs, N, max(gw, 20));

            obj.directional_Doppler.image = ...
                construct_directional_image(positive, negative);
        end

        if obj.broadening.is_selected

            if any(~isfinite(S(:)))
                error('ImageTypeList:NonfiniteBroadeningInput', ...
                    ['S contains nonfinite values immediately before broadening: ' ...
                 '%d NaN and %d Inf out of %d samples.'], ...
                    nnz(isnan(S)), nnz(isinf(S)), numel(S));
            end

            obj.broadening.image = obj.renderBroadeningPlot(S, Params);
        end

        % Raw spectra: spatial binning only.
        if obj.anySelected('SH', 'SH_avg')
            obj.storeSpectra(S, Params);
        end

        % Reuse M0 and M2 when f_RMS is also requested.
        if obj.anySelected('moment_0', 'f_RMS')
            M0 = moment0(S, f1, f2, fs, N);

            if obj.moment_0.is_selected
                obj.moment_0.image = M0;
            end

        end

        if obj.anySelected('moment_2', 'f_RMS')
            M2 = moment2(S, f1, f2, fs, N);

            if obj.moment_2.is_selected
                obj.moment_2.image = M2;
            end

        end

        if obj.moment_1.is_selected
            obj.moment_1.image = moment1(S, f1, f2, fs, N);
        end

        if obj.arg_0.is_selected
            obj.arg_0.image = moment0(angle(SHin), f1, f2, fs, N);
        end

        if obj.f_RMS.is_selected
            denominator = M0;
            denominator(~isfinite(denominator) | denominator <= 0) = NaN;

            obj.f_RMS.image = sqrt(M2 ./ denominator);
        end

        % Frequency bands and statistics.
        if obj.HF_M0.is_selected
            obj.HF_M0.image = moment0(S, fr2, f2, fs, N);
        end

        if obj.LF_M0.is_selected
            obj.LF_M0.image = moment0(S, f1, fr1, fs, N);
        end

        if obj.cumulative_distribution.is_selected
            obj.cumulative_distribution.image = ...
                cdf(S, f1, f2, fs, 0.5, N);
        end

        if obj.band_ratio.is_selected
            obj.band_ratio.image = ...
                energy_ratio(S, f1, f2, fr1, fr2, fs, N);
        end

        if obj.entropy.is_selected
            obj.entropy.image = spectral_entropy(S, f1, f2, fs, N);
        end

        % Original Gaussian width: complete spectrum.
        needDiagnostic = obj.harmonic_spectrum.is_selected;

        needGaussian = obj.anySelected( ...
            'gaussian_w', 'sigma', 'h1', 'h2', 'harmonic_spectrum');

        if needGaussian

            if needDiagnostic
                [I_FWHM, I_sigma, I_h1, I_h2, diagnostic] = ...
                    gaussian_width(S, 0, fs / 2, fs, N, 0);
            else
                [I_FWHM, I_sigma, I_h1, I_h2] = ...
                    gaussian_width(S, 0, fs / 2, fs, N, 0);
            end

            if obj.gaussian_w.is_selected
                obj.gaussian_w.image = I_FWHM;
            end

            if obj.sigma.is_selected
                obj.sigma.image = I_sigma;
            end

            if obj.h1.is_selected
                obj.h1.image = I_h1;
            end

            if obj.h2.is_selected
                obj.h2.image = I_h2;
            end

            if needDiagnostic
                obj.setHarmonicSpectrum( ...
                    diagnostic.fft, ...
                    diagnostic.axis, ...
                    diagnostic.harmonicIndices, ...
                    diagnostic.axisLabel);
            end

        end

    end

    function construct_image_from_FH(obj, Params, FHin)

        if isempty(FHin)
            return
        end

        angular = strcmp(Params.spatialTransform, 'angular spectrum');

        if obj.FH_modulus_mean.is_selected
            image = mean(abs(FHin), 3);

            if angular
                image = log10(fftshift(image));
            end

            obj.FH_modulus_mean.image = squeeze(image);
        end

        if obj.FH_arg_mean.is_selected
            image = mean(angle(FHin), 3);

            if angular
                image = fftshift(image);
            end

            obj.FH_arg_mean.image = squeeze(image);
        end

    end

    function construct_image_from_SVD(obj, ~, covariance, U, spatialSize)

        if isempty(covariance)
            obj.SVD_cov.image = [];
            obj.SVD_U.image = [];
            return
        end

        if obj.SVD_cov.is_selected
            obj.SVD_cov.image = abs(covariance);
        end

        if obj.SVD_U.is_selected
            obj.SVD_U.image = obj.renderSvdMontage(U, spatialSize);
        end

    end

end

methods (Access = private)

    function names = targetNames(obj, names)

        if isempty(names) || ...
                (isscalar(names) && strcmpi(string(names{1}), "all"))
            names = fieldnames(obj);
        end

    end

    function selected = anySelected(obj, varargin)
        selected = false;

        for k = 1:numel(varargin)

            if obj.(varargin{k}).is_selected
                selected = true;
                return
            end

        end

    end

    function S = compensateCorners(~, S)
        [Nx, Ny, ~] = size(S);

        outside = ~logical(diskMask(Ny, Nx, 1.2));

        assert(isequal(size(outside), [Nx Ny]), ...
            'ImageTypeList:InvalidCornerMask', ...
        'Corner mask must match the image dimensions.');

        outsideSpectra = reshape(S, Nx * Ny, []);
        reference = mean(outsideSpectra(outside(:), :), 1, 'omitnan');
        reference(~isfinite(reference) | reference <= 0) = 1;

        S = S ./ reshape(reference, 1, 1, []);
    end

    function storeSpectra(obj, S, Params)
        factor = 16;

        if isfield(Params, 'SHSpatialBinning') && ...
                ~isempty(Params.SHSpatialBinning)
            factor = Params.SHSpatialBinning;
        end

        [binned, info] = obj.spatialBinPower(S, factor);
        f = fftfreq(size(S, 3), 1 / Params.fs);

        if obj.SH.is_selected
            parameters = info;
            parameters.SH = binned;
            parameters.vector = f;

            obj.SH.parameters = parameters;

            mask = abs(f) >= Params.frequencyRange1 ...
                & abs(f) <= Params.frequencyRange2;

            if any(mask)
                obj.SH.image = mean(binned(:, :, mask), 3, 'omitnan');
            else
                obj.SH.image = mean(binned, 3, 'omitnan');
            end

        end

        if obj.SH_avg.is_selected
            parameters = info;
            parameters.SH = mean(binned, 3, 'omitnan');

            obj.SH_avg.parameters = parameters;
        end

    end

    function setHarmonicSpectrum(obj, coefficients, axisValues, indices, label)
        slot = obj.harmonic_spectrum;

        if ~slot.is_selected
            return
        end

        slot.image = [];
        slot.parameters = obj.emptyHarmonicParameters();

        [slot.image, slot.parameters] = renderHarmonicSpectrum( ...
            coefficients, axisValues, indices, label);
    end

    function parameters = emptyHarmonicParameters(~)
        parameters = struct( ...
            'axis', [], ...
            'axisLabel', [], ...
            'inputAxis', [], ...
            'inputAxisLabel', [], ...
            'fft', [], ...
            'harmonicIndices', [], ...
            'harmonicCoefficients', []);
    end

    function [out, info] = spatialBinPower(~, in, factor)
        validateattributes(factor, {'numeric'}, ...
            {'scalar', 'real', 'finite', 'integer', 'positive'});

        factor = double(factor);

        [nRows, nCols, nFreq] = size(in);
        nRowsOut = floor(nRows / factor);
        nColsOut = floor(nCols / factor);

        assert(nRowsOut >= 1 && nColsOut >= 1, ...
            'ImageTypeList:SHBinningTooLarge', ...
        'SHSpatialBinning exceeds the spatial image size.');

        cropSize = [nRowsOut nColsOut] * factor;

        if factor == 1
            out = in;
        else
            work = in(1:cropSize(1), 1:cropSize(2), :);
            work = reshape(work, ...
                factor, nRowsOut, factor, nColsOut, nFreq);

            valid = isfinite(work);
            work(~valid) = 0;

            numerator = sum(sum(work, 1), 3);
            denominator = sum(sum(valid, 1), 3);

            numerator = reshape(numerator, nRowsOut, nColsOut, nFreq);
            denominator = reshape(denominator, nRowsOut, nColsOut, nFreq);

            out = numerator ./ denominator;
            out(denominator == 0) = NaN;
            out = cast(out, 'like', in);
        end

        info = struct( ...
            'spatial_binning', [factor factor], ...
            'original_size', size(in), ...
            'binned_size', size(out), ...
            'crop_size', cropSize, ...
            'reduction', 'block_mean_power');
    end

    function image = renderBroadeningPlot(~, S, Params)
        image = [];

        try
            fig = figure('Visible', 'off');
            cleanup = onCleanup(@() close(fig));

            mask = diskMask( ...
                size(S, 1), size(S, 2), Params.registrationDiskRatio)';

            spectrum_ploting( ...
                S, mask, Params.fs, ...
                Params.frequencyRange1, Params.frequencyRange2);

            frame = getframe(fig);
            image = frame.cdata;
        catch E
            MEdisp(E);
        end

    end

    function image = renderSvdMontage(~, U, spatialSize)
        image = [];

        try
            fig = figure('Visible', 'off');
            cleanup = onCleanup(@() close(fig));

            U = abs(reshape(U, spatialSize(1), spatialSize(2), []));
            U = rescale(U, ...
                'InputMin', min(U, [], [1 2]), ...
                'InputMax', max(U, [], [1 2]));

            tiles = arrayfun( ...
                @(k) U(:, :, k)', 1:size(U, 3), ...
                'UniformOutput', false);

            montage(tiles, 'BorderSize', [0 0]);
            set(gca, 'Position', [0 0 1 1]);

            frame = getframe(fig);
            image = frame.cdata;
        catch E
            MEdisp(E);
        end

    end

end

end
