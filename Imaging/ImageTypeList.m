classdef ImageTypeList < handle
% Registry of every image type the rendering pipeline can produce.
%
% Usage pattern:
%   list.select('power_Doppler', 'directional_Doppler')
%   ... run pipeline ...
%   list.construct_image(Params, SH)
%   img = list.power_Doppler.image;

% -----------------------------------------------------------------------
properties
    % --- Doppler variants -----------------------------------------------
    power_Doppler
    power_1_Doppler
    power_2_Doppler

    % --- Spectral moments -----------------------------------------------
    moment_0
    moment_1
    moment_2

    % Computed variables -------------------------------------------------
    color_Doppler
    directional_Doppler
    broadening
    power_Doppler_wiener
    power_adapt

    % --- Spectral moments -----------------------------------------------
    arg_0
    f_RMS

    % --- Raw / intermediate field ---------------------------------------
    SH
    SH_avg
    FH_modulus_mean
    FH_arg_mean

    % --- SVD outputs ----------------------------------------------------
    SVD_cov
    SVD_U

    % --- Spectral statistics --------------------------------------------
    cumulative_distribution
    band_ratio
    color_band_ratio
    entropy

    % --- Frequency buckets ----------------------------------------------
    buckets
    full_buckets

    % High and low frequency images
    HF_M0
    LF_M0
end

% -----------------------------------------------------------------------
methods

    function obj = ImageTypeList()

        % Doppler
        obj.power_Doppler = ImageType('power', struct('M0sqrt', []));
        obj.power_1_Doppler = ImageType('power1');
        obj.power_2_Doppler = ImageType('power2');
        obj.color_Doppler = ImageType('color', struct('freq_low', [], 'freq_high', []));
        obj.directional_Doppler = ImageType('directional', struct('M0_pos', [], 'M0_neg', []));
        obj.broadening = ImageType('broadening');
        obj.power_Doppler_wiener = ImageType('power_wiener');
        obj.power_adapt = ImageType('power_adapt');

        % Moments
        obj.moment_0 = ImageType('M0'); % .raw
        obj.moment_1 = ImageType('M1'); % .raw
        obj.moment_2 = ImageType('M2'); % .raw
        obj.arg_0 = ImageType('arg0');
        obj.f_RMS = ImageType('f_RMS');

        % Raw field
        obj.SH = ImageType('SH', struct( ...
            'vector', [], ...
            'SH', [], ...
            'spatial_binning', [], ...
            'original_size', [], ...
            'binned_size', [], ...
            'crop_size', [], ...
            'reduction', []));
        obj.SH_avg = ImageType('SH_avg', struct( ...
            'SH', [], ...
            'spatial_binning', [], ...
            'original_size', [], ...
            'binned_size', [], ...
            'crop_size', [], ...
            'reduction', []));
        obj.FH_modulus_mean = ImageType('FH_modulus_mean');
        obj.FH_arg_mean = ImageType('FH_arg_mean');

        % SVD
        obj.SVD_cov = ImageType('SVD_cov');
        obj.SVD_U = ImageType('SVD_U');

        % Spectral statistics
        obj.cumulative_distribution = ImageType('cdf');
        obj.band_ratio = ImageType('energy_ratio');
        obj.color_band_ratio = ImageType('color_energy_ratio');
        obj.entropy = ImageType('entropy');

        % Buckets
        obj.buckets = ImageType('buckets', struct('intervals_0', [], 'intervals_1', [], ...
            'intervals_2', [], 'M0', []));
        obj.full_buckets = ImageType('full_buckets', struct('SH_full', []));

        % High and low frequency images
        obj.HF_M0 = ImageType('HF_M0'); % .raw
        obj.LF_M0 = ImageType('LF_M0'); % .raw
    end

    % ------------------------------------------------------------------
    function clear(obj, varargin)
        % clear()          – clear all image types
        % clear(n1, n2, …) – clear only the named types
        targets = obj.resolveTargets(varargin);

        for k = 1:numel(targets)
            obj.(targets{k}).clear();
        end

    end

    % ------------------------------------------------------------------
    function select(obj, varargin)
        % select()          – deselect all (same as clear)
        % select('all')     – select all
        % select(n1, n2, …) – select only named types (all others cleared first)
        obj.clearAll();

        if nargin == 1
            return % caller wants nothing selected
        end

        if numel(varargin) == 1 && ...
                strcmpi(string(varargin{1}), "all")
            allFields = fieldnames(obj);

            for k = 1:numel(allFields)
                obj.(allFields{k}).select();
            end

            return
        end

        for k = 1:numel(varargin)
            obj.(varargin{k}).select();
        end

    end

    % ------------------------------------------------------------------
    function copy_from(obj, src)
        fields = fieldnames(src);

        for k = 1:numel(fields)
            obj.(fields{k}).copy_from(src.(fields{k}));
        end

    end

    % ------------------------------------------------------------------
    function images2png(obj, preview_folder_name, folder_path, varargin)
        % images2png(pfx, dir)          – save all selected images
        % images2png(pfx, dir, n1, …)   – save only named (if selected)
        if isempty(varargin)
            targets = fieldnames(obj);
        else
            targets = varargin;
        end

        for k = 1:numel(targets)
            slot = obj.(targets{k});

            if slot.is_selected
                slot.image2png(preview_folder_name, folder_path);
            end

        end

    end

    % ------------------------------------------------------------------
    function construct_image(obj, Params, SHin)
        % Populate all selected image slots from the short-time-transformed
        % complex field SHin  [Nx × Ny × T].

        if isempty(SHin), return, end

        f1 = Params.frequencyRange1;
        f2 = Params.frequencyRange2;
        fr1 = Params.frequencyRangeBandRatio1;
        fr2 = Params.frequencyRangeBandRatio2;
        [Nx, Ny, batchSize] = size(SHin);
        fs = Params.fs;
        gw = Params.flatfield_gw;

        SH_mod = abs(SHin) .^ 2;
        SH_arg = angle(SHin);

        if Params.CornerCompensation
            disk = diskMask(Ny, Nx, 1.2);
            outsideMask = ~disk;
            largeMask = repmat(outsideMask, [1 1 batchSize]);
            SH_outside = SH_mod;
            SH_outside(~largeMask) = NaN;
            cornerMean = mean(SH_outside, [1 2], 'omitnan');
            cornerMean(~isfinite(cornerMean) | cornerMean <= 0) = 1;
            SH_mod = SH_mod ./ cornerMean;
        end

        % --- Power Doppler variants ------------------------------------
        if obj.power_Doppler.is_selected
            obj.power_Doppler.image = moment0(SH_mod, f1, f2, fs, batchSize, gw);
        end

        if obj.power_Doppler_wiener.is_selected
            base = moment0(SH_mod, f1, f2, fs, batchSize, gw);
            obj.power_Doppler_wiener.image = wiener2(base, [2 2], 10);
        end

        if obj.power_adapt.is_selected
            base = moment0(SH_mod, f1, f2, fs, batchSize);
            obj.power_adapt.image = adapthisteq(rescale(base), ...
                'NumTiles', [12 12], 'NBins', 128);
        end

        if obj.power_1_Doppler.is_selected
            obj.power_1_Doppler.image = moment1(SH_mod, f1, f2, fs, batchSize, gw);
        end

        if obj.power_2_Doppler.is_selected
            obj.power_2_Doppler.image = moment2(SH_mod, f1, f2, fs, batchSize, gw);
        end

        % --- Color / directional Doppler --------------------------------
        if obj.color_Doppler.is_selected
            M0 = moment0(SH_mod, f1, f2, fs, batchSize, gw);
            [M0_low, M0_high] = composite(SH_mod, f1, fr2, f2, fs, batchSize, gw);
            obj.color_Doppler.image = construct_colored_image(M0, M0_low, M0_high);
        end

        if obj.directional_Doppler.is_selected
            [M0_pos, M0_neg] = directional(SH_mod, f1, f2, fs, batchSize, max(gw, 20));
            obj.directional_Doppler.image = construct_directional_image(M0_pos, M0_neg);
        end

        % --- Spectral broadening plot -----------------------------------
        if obj.broadening.is_selected
            obj.broadening.image = obj.renderBroadeningPlot(SH_mod, Params, fs);
        end

        % --- Raw SH output ---------------------------------------------
        % Derived images remain full resolution. Only SH and SH_avg are
        % spatially block-averaged before storage/export. The frequency
        % dimension is not modified.
        if obj.SH.is_selected || obj.SH_avg.is_selected
            binning = 16;

            if isfield(Params, 'SHSpatialBinning') && ...
                    ~isempty(Params.SHSpatialBinning)
                binning = Params.SHSpatialBinning;
            end

            [SH_binned, binInfo] = obj.spatialBinPower( ...
                SH_mod, binning);

            if obj.SH.is_selected
                obj.SH.parameters.SH = SH_binned;
                obj.SH.parameters.vector = fftfreq( ...
                    batchSize, 1 / fs);
                obj.SH.parameters = obj.attachBinningInfo( ...
                    obj.SH.parameters, binInfo);
            end

            if obj.SH_avg.is_selected
                obj.SH_avg.parameters.SH = mean( ...
                    SH_binned, 3, 'omitnan');
                obj.SH_avg.parameters = obj.attachBinningInfo( ...
                    obj.SH_avg.parameters, binInfo);
            end

        end

        if obj.SH.is_selected
            [SH_binned, binInfo] = obj.spatialBinPower( ...
                SH_mod, Params.SHSpatialBinning);

            obj.SH.parameters.SH = SH_binned;
            obj.SH.parameters.vector = fftfreq( ...
                batchSize, 1 / fs);

            obj.SH.parameters.spatial_binning = ...
                binInfo.spatial_binning;

            obj.SH.parameters.original_size = ...
                binInfo.original_size;

            obj.SH.parameters.crop_size = ...
                binInfo.crop_size;

            obj.SH.parameters.binned_size = ...
                binInfo.binned_size;

            obj.SH.parameters.reduction = ...
                binInfo.reduction;

            % Aperçu 2D : moyenne dans la bande Doppler utile
            frequencyVector = obj.SH.parameters.vector;

            spectralMask = abs(frequencyVector) >= f1 ...
                & abs(frequencyVector) <= f2;

            if any(spectralMask)
                obj.SH.image = mean( ...
                    SH_binned(:, :, spectralMask), ...
                    3, "omitnan");
            else
                obj.SH.image = mean( ...
                    SH_binned, 3, "omitnan");
            end

        end

        % --- Spectral moments ------------------------------------------
        if obj.moment_0.is_selected
            obj.moment_0.image = moment0(SH_mod, f1, f2, fs, batchSize);
        end

        if obj.moment_1.is_selected
            obj.moment_1.image = moment1(SH_mod, f1, f2, fs, batchSize);
        end

        if obj.moment_2.is_selected
            obj.moment_2.image = moment2(SH_mod, f1, f2, fs, batchSize);
        end

        if obj.arg_0.is_selected
            obj.arg_0.image = moment0(SH_arg, f1, f2, fs, batchSize);
        end

        if obj.f_RMS.is_selected
            M0 = moment0(SH_mod, f1, f2, fs, batchSize);
            M2 = moment2(SH_mod, f1, f2, fs, batchSize);
            denominator = M0;
            denominator(~isfinite(denominator) | denominator <= 0) = NaN;
            obj.f_RMS.image = sqrt(M2 ./ denominator);
        end

        if obj.HF_M0.is_selected
            obj.HF_M0.image = moment0(SH_mod, fr2, f2, fs, batchSize);
        end

        if obj.LF_M0.is_selected
            obj.LF_M0.image = moment0(SH_mod, fr1, fr2, fs, batchSize);
        end

        % --- Spectral statistics ---------------------------------------
        if obj.cumulative_distribution.is_selected
            obj.cumulative_distribution.image = cdf(SH_mod, f1, f2, fs, 0.5, batchSize);
        end

        if obj.band_ratio.is_selected
            obj.band_ratio.image = energy_ratio(SH_mod, f1, f2, fr1, fr2, fs, batchSize);
        end

        if obj.color_band_ratio.is_selected
            obj.color_band_ratio.image = color_energy_ratio(SH_mod, f1, f2, fr1, fr2, fs, batchSize, gw);
        end

        if obj.entropy.is_selected
            obj.entropy.image = spectral_entropy(SH_mod, f1, f2, fs, batchSize);
        end

        % --- Frequency buckets -----------------------------------------
        if obj.buckets.is_selected
            obj.computeBuckets(SH_mod, Params, fs, batchSize, gw);
        end

        if obj.full_buckets.is_selected
            obj.computeFullBuckets(SH_mod);
        end

    end

    % ------------------------------------------------------------------
    function construct_image_from_FH(obj, Params, FHin)
        % Populate FH_modulus_mean and FH_arg_mean from the Fourier-domain field.

        if isempty(FHin), return, end

        isAngular = strcmp(Params.spatialTransform, 'angular spectrum');

        if obj.FH_modulus_mean.is_selected
            m = mean(abs(FHin), 3);

            if isAngular
                m = log10(fftshift(m));
            end

            obj.FH_modulus_mean.image = squeeze(m);
        end

        if obj.FH_arg_mean.is_selected
            m = mean(angle(FHin), 3);

            if isAngular
                m = fftshift(m);
            end

            obj.FH_arg_mean.image = squeeze(m);
        end

    end

    % ------------------------------------------------------------------
    function construct_image_from_SVD(obj, ~, covin, Uin, szin)
        % Populate SVD_cov and SVD_U.
        % szin – size of the H batch [Nx Ny Nt] for reshaping Uin.

        if isempty(covin)
            obj.SVD_cov.image = [];
            obj.SVD_U.image = [];
            return
        end

        if obj.SVD_cov.is_selected
            obj.SVD_cov.image = abs(covin);
        end

        if obj.SVD_U.is_selected
            obj.SVD_U.image = obj.renderSvdMontage(Uin, szin);
        end

    end

end % public methods

% -----------------------------------------------------------------------
methods (Access = private)

    function clearAll(obj)
        fields = fieldnames(obj);

        for k = 1:numel(fields)
            obj.(fields{k}).clear();
        end

    end

    % ------------------------------------------------------------------
    function targets = resolveTargets(obj, args)
        % Return the list of field names to act on.
        if isempty(args)
            targets = fieldnames(obj);
        else
            targets = args;
        end

    end

    % ------------------------------------------------------------------
    function [out, info] = spatialBinPower(~, in, factor)
        % Average non-overlapping factor-by-factor spatial blocks.
        % SH_mod is a power spectrum, so a block mean preserves the power
        % scale; a block sum would multiply it by factor^2.

        validateattributes(factor, {'numeric'}, ...
            {'scalar', 'real', 'finite', 'integer', 'positive'}, ...
            mfilename, 'Params.SHSpatialBinning');
        factor = double(factor);

        originalSize = size(in);
        nRows = originalSize(1);
        nCols = originalSize(2);
        nFreq = originalSize(3);

        if factor == 1
            out = in;
            cropSize = [nRows nCols];
        else
            nRowsOut = floor(nRows / factor);
            nColsOut = floor(nCols / factor);

            if nRowsOut < 1 || nColsOut < 1
                error('ImageTypeList:SHBinningTooLarge', ...
                    ['SHSpatialBinning=%d exceeds the SH spatial ', ...
                 'size [%d %d].'], factor, nRows, nCols);
            end

            % Retain complete blocks only. This avoids unequal block areas
            % when a dimension is not divisible by the binning factor.
            cropSize = [nRowsOut * factor, nColsOut * factor];
            work = in(1:cropSize(1), 1:cropSize(2), :);
            work = reshape(work, ...
                factor, nRowsOut, factor, nColsOut, nFreq);

            valid = isfinite(work);
            work(~valid) = 0;
            numerator = sum(sum(work, 1), 3);
            denominator = sum(sum(valid, 1), 3);
            numerator = reshape(permute(numerator, ...
                [2 4 5 1 3]), nRowsOut, nColsOut, nFreq);
            denominator = reshape(permute(denominator, ...
                [2 4 5 1 3]), nRowsOut, nColsOut, nFreq);

            out = numerator ./ denominator;
            out(denominator == 0) = NaN;
            out = cast(out, 'like', in);
        end

        info = struct( ...
            'spatial_binning', [factor factor], ...
            'original_size', originalSize, ...
            'binned_size', size(out), ...
            'crop_size', cropSize, ...
            'reduction', 'block_mean_power');
    end

    % ------------------------------------------------------------------
    function parameters = attachBinningInfo(~, parameters, info)
        names = fieldnames(info);

        for k = 1:numel(names)
            parameters.(names{k}) = info.(names{k});
        end

    end

    % ------------------------------------------------------------------
    function img = renderBroadeningPlot(~, SH_mod, Params, fs)
        % Render the spectral broadening plot into a raster image.
        img = [];

        try
            fi = figure('Visible', 'off');
            disk = diskMask(size(SH_mod, 1), size(SH_mod, 2), Params.registrationDiskRatio)';
            spectrum_ploting(SH_mod, disk, fs, Params.frequencyRange1, Params.frequencyRange2);
            frame = getframe(fi);
            img = frame.cdata;
            close(fi);
        catch E
            MEdisp(E);
        end

    end

    % ------------------------------------------------------------------
    function img = renderSvdMontage(~, Uin, szin)
        % Render the SVD spatial modes as a montage and return raster data.
        img = [];

        try
            fi = figure('Visible', 'off');
            U3 = reshape(Uin, szin(1), szin(2), []);
            U3 = abs(U3);
            U3 = rescale(U3, 'InputMax', max(U3, [], [1, 2]), ...
                'InputMin', min(U3, [], [1, 2]));
            C = arrayfun(@(k) U3(:, :, k)', 1:size(U3, 3), 'UniformOutput', false);
            montage(C, 'BorderSize', [0 0]);
            set(gca, 'Position', [0 0 1 1]);
            frame = getframe(fi);
            img = frame.cdata;
            close(fi);
        catch E
            MEdisp(E);
        end

    end

    % ------------------------------------------------------------------
    function computeBuckets(obj, SH_mod, Params, fs, batchSize, gw)
        [numX, numY, ~] = size(SH_mod);
        buckranges = reshape(Params.bucketsRanges, [], 2);

        if buckranges(1, 1) == -1
            % Auto-define 32 equal buckets up to Nyquist
            edges = linspace(0, fs / 2, 33);
            buckranges = [edges(1:end - 1)', edges(2:end)'];
        end

        numRanges = size(buckranges, 1);

        obj.buckets.parameters.intervals_0 = zeros(numX, numY, 1, numRanges, 'single');
        obj.buckets.parameters.intervals_1 = zeros(numX, numY, 1, numRanges, 'single');
        obj.buckets.parameters.intervals_2 = zeros(numX, numY, 1, numRanges, 'single');
        obj.buckets.parameters.M0 = zeros(numX, numY, 1, numRanges, 'single');

        for rIdx = 1:numRanges
            r1 = buckranges(rIdx, 1);
            r2 = buckranges(rIdx, 2);
            obj.buckets.parameters.intervals_0(:, :, :, rIdx) = moment0(SH_mod, r1, r2, fs, batchSize);
            obj.buckets.parameters.intervals_1(:, :, :, rIdx) = moment1(SH_mod, r1, r2, fs, batchSize);
            obj.buckets.parameters.intervals_2(:, :, :, rIdx) = moment2(SH_mod, r1, r2, fs, batchSize);
            obj.buckets.parameters.M0(:, :, :, rIdx) = moment0(SH_mod, r1, r2, fs, batchSize, gw);
        end

        obj.buckets.image = mean(obj.buckets.parameters.M0, [3 4]);
    end

    % ------------------------------------------------------------------
    function computeFullBuckets(obj, SH_mod)
        [numX, numY, nFreq] = size(SH_mod);
        nBuckets = 32;
        edges = round(linspace(1, nFreq + 1, nBuckets + 1));

        SH_full = zeros(numX, numY, nBuckets, 'single');

        for bIdx = 1:nBuckets
            i1 = edges(bIdx);
            i2 = edges(bIdx + 1) - 1;
            bucketMean = mean(SH_mod(:, :, i1:i2), 3);
            bucketMean = max(bucketMean, realmin('single'));
            SH_full(:, :, bIdx) = single(log(bucketMean));
        end

        obj.full_buckets.parameters.SH_full = SH_full;
    end

end % private methods

end % classdef
