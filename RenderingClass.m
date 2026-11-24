classdef RenderingClass < handle
% Holographic renderer.
%
%   r = RenderingClass()
%   r = RenderingClass('precomputeSpatialKernel', kernel)
%
% Pipeline:
%   Frames -> spatial filtering -> spatial propagation -> H_raw
%          -> clutter filtering -> H -> time transform -> SH
%          -> image construction
%
% Clutter filtering always starts from H_raw, never from a previously
% filtered H.

properties
    LastParams struct
    Frames single
    FramesChanged logical = false

    SpatialFilterMask logical
    SpatialKernel single
    PhaseFactor single

    FH single
    H_raw single
    H single
    SH single

    cov single
    U single

    Output ImageTypeList
end

properties (Access = private)
    lastLambda single = []
    lastPpx single = []
    lastPpy single = []
end

% -------------------------------------------------------------------------
% Public interface
% -------------------------------------------------------------------------
methods

    function obj = RenderingClass(options)

        arguments
            options.precomputeSpatialKernel = []
        end

        obj.Output = ImageTypeList();
        obj.setInitParams();

        if ~isempty(options.precomputeSpatialKernel)
            obj.SpatialKernel = single(options.precomputeSpatialKernel);
        end

    end

    function setInitParams(obj)

        obj.LastParams = HDParamSchema.getDefaults();

        % Permit use before the schema has been extended.
        if ~isfield(obj.LastParams, 'filterType')
            obj.LastParams.filterType = ...
                char(ClutterFilter.resolveType(obj.LastParams));
        end

        if ~isfield(obj.LastParams, 'polynomialDegree')
            obj.LastParams.polynomialDegree = 1;
        end

    end

    function setFrames(obj, frames)

        obj.Frames = single(frames);
        obj.FramesChanged = true;

    end

    function Render(obj, p, imageTypes, options)

        arguments
            obj
            p struct
            imageTypes cell = {}
            options.cache_intermediate_results logical = true
        end

        if isempty(obj.Frames)
            error('RenderingClass:NoFrames', ...
            'Call setFrames before rendering.');
        end

        obj.validateImageTypes(imageTypes);
        obj.Output.select(imageTypes{:});

        [p, changed] = obj.mergeAndDiff(p);

        [Nx, Ny, batchSize] = size(obj.Frames);

        % -----------------------------------------------------------------
        % Spatial filtering
        % -----------------------------------------------------------------
        obj.applySpatialFilter(p, changed, Nx, Ny);

        % -----------------------------------------------------------------
        % Spatial propagation
        % -----------------------------------------------------------------
        doFH = obj.FramesChanged || ...
            isempty(obj.H_raw) || ...
            changed.PaddingNum || ...
            changed.spatialTransform || ...
            changed.spatialPropagation || ...
            ~options.cache_intermediate_results;

        obj.applySpatialTransform(p, changed, doFH, Nx, Ny);

        obj.Output.construct_image_from_FH(p, obj.FH);

        if ~options.cache_intermediate_results
            obj.FH = [];
        end

        % -----------------------------------------------------------------
        % Clutter filtering
        % -----------------------------------------------------------------
        filterFields = { ...
                            'filterType', ...
                            'svd_filter', ...
                            'svdThreshold', ...
                            'svdStride', ...
                            'polynomialDegree', ...
                            'frequencyRange1', ...
                            'frequencyRange2', ...
                            'fs', ...
                            'filterCutoffHz', ...
                            'filterOrder', ...
                            'filterZeroPhase', ...
                            'filterLowHz', ...
                            'filterHighHz', ...
                            'filterTransitionHz' ...
                        };

        filterChanged = false;

        for k = 1:numel(filterFields)
            name = filterFields{k};

            if isfield(changed, name)
                filterChanged = filterChanged || changed.(name);
            end

        end

        doFilter = doFH || ...
            filterChanged || ...
            isempty(obj.H) || ...
            ~options.cache_intermediate_results;

        obj.applyClutterFilter(p, doFilter);

        % Non-SVD filters return empty SVD diagnostics.
        obj.Output.construct_image_from_SVD( ...
            p, obj.cov, obj.U, size(obj.H));

        % -----------------------------------------------------------------
        % Time transform
        % -----------------------------------------------------------------
        doSH = doFilter || ...
            isempty(obj.SH) || ...
            changed.timeTransform || ...
            changed.flip_y || ...
            changed.flip_x || ...
            ~options.cache_intermediate_results;

        obj.applyTimeTransform(p, doSH, batchSize);

        if ~options.cache_intermediate_results
            obj.H = [];
            obj.H_raw = [];
        end

        if doSH
            obj.orientOutput(p);
        end

        % -----------------------------------------------------------------
        % Image construction
        % -----------------------------------------------------------------
        obj.Output.construct_image(p, obj.SH);

        obj.FramesChanged = false;
        obj.LastParams = p;

    end

    function r = getImages(obj, imageTypes)
        % Return normalised images without recomputing the pipeline.

        obj.validateImageTypes(imageTypes);
        r = obj.collectImages(imageTypes);

    end

end

% -------------------------------------------------------------------------
% Private methods
% -------------------------------------------------------------------------
methods (Access = private)

    function [p, changed] = mergeAndDiff(obj, p)
        % Resolve legacy selection before merging with previous parameters.
        %
        % An explicit filterType always takes precedence.
        % If neither filterType nor svd_filter is supplied, retain the
        % previous selection through the normal merge below.

        if ~isfield(p, 'filterType') && isfield(p, 'svd_filter')
            p.filterType = char(ClutterFilter.resolveType(p));
        end

        changed = struct();
        fields = fieldnames(obj.LastParams);

        for i = 1:numel(fields)
            name = fields{i};

            if isfield(p, name)
                changed.(name) = ...
                    ~isequal(p.(name), obj.LastParams.(name));
            else
                changed.(name) = false;
                p.(name) = obj.LastParams.(name);
            end

        end

        newFields = setdiff(fieldnames(p), fields);

        for i = 1:numel(newFields)
            changed.(newFields{i}) = true;
        end

    end

    function applySpatialFilter(obj, p, changed, Nx, Ny)

        filterParamsChanged = changed.spatialFilter || ...
            changed.spatialFilterRange1 || ...
            changed.spatialFilterRange2;

        if ~(filterParamsChanged || obj.FramesChanged) || ~p.spatialFilter
            return
        end

        if filterParamsChanged || ...
                obj.FramesChanged || ...
                isempty(obj.SpatialFilterMask)

            obj.SpatialFilterMask = fftshift( ...
                diskMask( ...
                Nx, Ny, ...
                p.spatialFilterRange1, ...
                p.spatialFilterRange2))';
        end

        obj.Frames = ifft2( ...
            fft2(obj.Frames) .* obj.SpatialFilterMask);

    end

    function applySpatialTransform(obj, p, changed, doFH, Nx, Ny)

        if ~doFH
            return
        end

        kernelChanged = changed.spatialPropagation || ...
            changed.PaddingNum || ...
            changed.spatialTransform;

        opticalChanged = ~isequal(p.lambda, obj.lastLambda) || ...
            ~isequal(p.ppx, obj.lastPpx) || ...
            ~isequal(p.ppy, obj.lastPpy);

        if kernelChanged || opticalChanged || isempty(obj.SpatialKernel)

            switch p.spatialTransform

                case "angular spectrum"
                    ND = max([p.PaddingNum, Nx, Ny]);

                    obj.SpatialKernel = ...
                        propagation_kernelAngularSpectrum( ...
                        ND, ND, ...
                        p.spatialPropagation, ...
                        p.lambda, ...
                        p.ppx, ...
                        p.ppy, ...
                        0);

                case "Fresnel"
                    NxP = max(p.PaddingNum, Nx);
                    NyP = max(p.PaddingNum, Ny);

                    [obj.SpatialKernel, obj.PhaseFactor] = ...
                        propagation_kernelFresnel( ...
                        NyP, NxP, ...
                        p.spatialPropagation, ...
                        p.lambda, ...
                        p.ppx, ...
                        p.ppy, ...
                        0);

                otherwise
                    % Other transforms do not use these kernels.
            end

            obj.lastLambda = p.lambda;
            obj.lastPpx = p.ppx;
            obj.lastPpy = p.ppy;

        end

        switch p.spatialTransform

            case "angular spectrum"
                ND = max([p.PaddingNum, Nx, Ny]);

                hologram_fft = fft2( ...
                    single(pad3DToSquare(obj.Frames, ND)));

                propagated_fft = ...
                    hologram_fft .* fftshift(obj.SpatialKernel);

                reconstructed_field = ...
                    ifft2(propagated_fft) .* sqrt(Nx * Ny);

                obj.FH = propagated_fft;
                obj.H_raw = reconstructed_field;

            case "Fresnel"
                NxP = max(p.PaddingNum, Nx);
                NyP = max(p.PaddingNum, Ny);

                if p.PaddingNum > 0
                    padded = single( ...
                        pad3DToSquare(obj.Frames, p.PaddingNum));
                else
                    padded = single(obj.Frames);
                end

                propagated_fft = padded .* obj.SpatialKernel;

                reconstructed_field = ...
                    fftshift( ...
                    fftshift(fft2(propagated_fft), 1), ...
                    2) ./ sqrt(NxP * NyP);

                obj.FH = propagated_fft;
                obj.H_raw = reconstructed_field;

            case "None"
                obj.FH = [];
                obj.H_raw = single(obj.Frames);

            case "twin image removal"
                obj.FH = [];

                reconstructed_field = twin_image_removal_( ...
                    single(obj.Frames), [], changed, p);

                obj.H_raw = reconstructed_field;

            otherwise
                error('RenderingClass:UnknownSpatialTransform', ...
                    'Unknown spatial transform: "%s".', ...
                    p.spatialTransform);
        end

    end

    function applyClutterFilter(obj, p, doFilter)

        if ~doFilter
            return
        end

        if isempty(obj.H_raw)
            error('RenderingClass:MissingRawField', ...
                ['The unfiltered reconstructed field must be ', ...
             'available before clutter filtering.']);
        end

        [obj.H, diagnostics] = ...
            ClutterFilter.apply(obj.H_raw, p);

        obj.cov = diagnostics.cov;
        obj.U = diagnostics.U;

    end

    function applyTimeTransform(obj, p, doSH, batchSize)

        if ~doSH
            return
        end

        [a, b, ~] = size(obj.H);

        switch p.timeTransform

            case 'PCA'
                obj.SH = short_time_PCA(obj.H);

            case 'ICA'
                obj.SH = short_time_ICA(obj.H);

            case 'FFT'
                obj.SH = fft(obj.H, [], 3) ./ sqrt(batchSize);

            case 'Wavelet_Morlet'
                obj.SH = morlet1D_transform_3rdDim(obj.H, [], 3);

            case 'autocorrelation'
                tmp = reshape(obj.H, a * b, []);

                out = arrayfun( ...
                    @(k) xcorr(tmp(k, :), 'normalized'), ...
                    1:a * b, ...
                    'UniformOutput', false);

                obj.SH = permute( ...
                    reshape(cell2mat(out), [], a, b), ...
                    [2 3 1]);

            case 'intercorrelation'
                obj.SH = intercorrel(obj.H, 3);

            case 'phase difference'
                obj.SH = angle(obj.H);

            case 'None'
                obj.SH = obj.H;

            otherwise
                error('RenderingClass:UnknownTimeTransform', ...
                    'Unknown time transform: "%s".', ...
                    p.timeTransform);
        end

    end

    function orientOutput(obj, p)
        % Lens transpose: x <-> -y.

        obj.SH = flip(permute(obj.SH, [2 1 3]), 2);

        if p.flip_y
            obj.SH = flip(obj.SH, 1);
        end

        if p.flip_x
            obj.SH = flip(obj.SH, 2);
        end

    end

    function validateImageTypes(obj, imageTypes)

        for i = 1:numel(imageTypes)

            if ~isprop(obj.Output, imageTypes{i})
                known = sprintf( ...
                    '%s, ', string(fieldnames(obj.Output)));

                error('RenderingClass:UnknownImageType', ...
                    ['"%s" is not a known image type. ', ...
                 'Available: [%s]'], ...
                    imageTypes{i}, known);
            end

        end

    end

    function r = collectImages(obj, imageTypes)

        silent = {'buckets', 'full_buckets', 'SH', 'SH_avg'};
        r = cell(1, numel(imageTypes));

        for i = 1:numel(imageTypes)
            im = obj.Output.(imageTypes{i}).image;

            if isempty(im)

                if ~ismember(imageTypes{i}, silent)
                    fprintf( ...
                        'Warning: ''%s'' produced no image.\n', ...
                        imageTypes{i});
                end

                r{i} = [];

            else
                r{i} = mat2gray(im);
            end

        end

    end

end

end
