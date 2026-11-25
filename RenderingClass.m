classdef RenderingClass < handle
% Holographic rendering pipeline:
% Frames -> spatial filtering -> H_raw -> clutter filter -> H -> SH -> images

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
    KernelParams struct = struct()
end

methods

    function obj = RenderingClass(options)

        arguments
            options.precomputeSpatialKernel = []
        end

        obj.Output = ImageTypeList();
        obj.setInitParams();

        if ~isempty(options.precomputeSpatialKernel)
            obj.SpatialKernel = single( ...
                options.precomputeSpatialKernel);
        end

    end

    function setInitParams(obj)
        p = HDParamSchema.getDefaults();

        if ~isfield(p, 'filterType')
            p.filterType = char(ClutterFilter.resolveType(p));
        end

        if ~isfield(p, 'polynomialDegree')
            p.polynomialDegree = 1;
        end

        obj.LastParams = p;
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

        [p, changed] = obj.mergeParams(p);
        force = ~options.cache_intermediate_results;

        % Spatial reconstruction.
        spatialFields = {
                         'spatialFilter'
                         'spatialFilterRange1'
                         'spatialFilterRange2'
                         'PaddingNum'
                         'spatialTransform'
                         'spatialPropagation'
                         'lambda'
                         'ppx'
                         'ppy'
                         };

        doSpatial = force || ...
            obj.FramesChanged || ...
            isempty(obj.H_raw) || ...
            obj.anyChanged(changed, spatialFields);

        obj.checkFinite(obj.Frames, 'Frames');

        if doSpatial
            obj.reconstruct(p, changed);
        end

        obj.checkFinite(obj.H_raw, 'H_raw after spatial reconstruction');
        obj.Output.construct_image_from_FH(p, obj.FH);

        % Clutter filtering.
        filterFields = {
                        'filterType'
                        'svd_filter'
                        'svdThreshold'
                        'svdStride'
                        'polynomialDegree'
                        'frequencyRange1'
                        'frequencyRange2'
                        'fs'
                        'filterCutoffHz'
                        'filterOrder'
                        'filterZeroPhase'
                        'filterLowHz'
                        'filterHighHz'
                        'filterTransitionHz'
                        };

        doFilter = force || ...
            doSpatial || ...
            isempty(obj.H) || ...
            obj.anyChanged(changed, filterFields);

        if doFilter
            [obj.H, diagnostics] = ...
                ClutterFilter.apply(obj.H_raw, p);

            obj.cov = diagnostics.cov;
            obj.U = diagnostics.U;
        end

        obj.checkFinite(obj.H, 'H after clutter filtering');

        obj.Output.construct_image_from_SVD( ...
            p, obj.cov, obj.U, size(obj.H));

        % Temporal transformation.
        timeFields = {'timeTransform', 'flip_y', 'flip_x'};

        doTime = force || ...
            doFilter || ...
            isempty(obj.SH) || ...
            obj.anyChanged(changed, timeFields);

        if doTime
            obj.transformTime(p);
            obj.checkFinite(obj.SH, 'SH after time transform');
            obj.orientOutput(p);
        else
            obj.checkFinite(obj.SH, 'SH from cache');
        end

        % Image construction.
        obj.Output.construct_image(p, obj.SH);

        % Commit cache state only after successful rendering.
        obj.FramesChanged = false;
        obj.LastParams = p;

        if force
            obj.FH = [];
            obj.H_raw = [];
            obj.H = [];
        end

    end

    function images = getImages(obj, imageTypes)
        obj.validateImageTypes(imageTypes);

        silent = {'SH', 'SH_avg'};
        images = cell(size(imageTypes));

        for k = 1:numel(imageTypes)
            name = imageTypes{k};
            image = obj.Output.(name).image;

            if isempty(image)

                if ~ismember(name, silent)
                    fprintf("Warning: '%s' produced no image.\n", name);
                end

            else
                images{k} = mat2gray(image);
            end

        end

    end

end

methods (Access = private)

    function [p, changed] = mergeParams(obj, p)
        % Explicit filterType takes precedence over legacy svd_filter.
        if ~isfield(p, 'filterType') && isfield(p, 'svd_filter')
            p.filterType = char(ClutterFilter.resolveType(p));
        end

        previous = obj.LastParams;
        names = union(fieldnames(previous), fieldnames(p));
        changed = struct();

        for k = 1:numel(names)
            name = names{k};

            if ~isfield(p, name)
                p.(name) = previous.(name);
                changed.(name) = false;
            else
                changed.(name) = ~isfield(previous, name) || ...
                    ~isequaln(p.(name), previous.(name));
            end

        end

    end

    function result = anyChanged(~, changed, names)
        result = false;

        for k = 1:numel(names)
            name = names{k};

            if isfield(changed, name) && changed.(name)
                result = true;
                return
            end

        end

    end

    function reconstruct(obj, p, changed)
        [Nx, Ny, ~] = size(obj.Frames);

        % Filter a working copy; preserve source frames.
        frames = obj.Frames;

        if p.spatialFilter
            obj.SpatialFilterMask = fftshift( ...
                diskMask(Nx, Ny, ...
                p.spatialFilterRange1, ...
                p.spatialFilterRange2))';

            if ~isequal(size(obj.SpatialFilterMask), [Nx Ny])
                error('RenderingClass:InvalidSpatialMask', ...
                'Spatial filter mask must match the frame dimensions.');
            end

            frames = ifft2(fft2(frames) .* obj.SpatialFilterMask);
            obj.checkFinite(frames, 'Frames after spatial filter');
        end

        obj.updateKernel(p, Nx, Ny);

        switch string(p.spatialTransform)

            case "angular spectrum"
                ND = max([p.PaddingNum, Nx, Ny]);

                padded = single(pad3DToSquare(frames, ND));
                obj.FH = fft2(padded) .* fftshift(obj.SpatialKernel);

                obj.H_raw = ifft2(obj.FH) .* sqrt(Nx * Ny);

            case "Fresnel"
                NxP = max(p.PaddingNum, Nx);
                NyP = max(p.PaddingNum, Ny);

                if p.PaddingNum > 0
                    frames = single( ...
                        pad3DToSquare(frames, p.PaddingNum));
                end

                obj.FH = frames .* obj.SpatialKernel;

                field = fft2(obj.FH);
                field = fftshift(fftshift(field, 1), 2);

                obj.H_raw = field ./ sqrt(NxP * NyP);

            case "None"
                obj.FH = [];
                obj.H_raw = frames;

            case "twin image removal"
                obj.FH = [];
                obj.H_raw = twin_image_removal_( ...
                    frames, [], changed, p);

            otherwise
                error('RenderingClass:UnknownSpatialTransform', ...
                    'Unknown spatial transform: "%s".', ...
                    string(p.spatialTransform));
        end

    end

    function updateKernel(obj, p, Nx, Ny)
        transform = string(p.spatialTransform);

        if ~ismember(transform, ["angular spectrum", "Fresnel"])
            return
        end

        current = struct( ...
            'transform', transform, ...
            'padding', p.PaddingNum, ...
            'propagation', p.spatialPropagation, ...
            'lambda', p.lambda, ...
            'ppx', p.ppx, ...
            'ppy', p.ppy, ...
            'frameSize', [Nx Ny]);

        if isempty(obj.SpatialKernel) || ...
                ~isequaln(current, obj.KernelParams)

            switch transform

                case "angular spectrum"
                    ND = max([p.PaddingNum, Nx, Ny]);

                    obj.SpatialKernel = ...
                        propagation_kernelAngularSpectrum( ...
                        ND, ND, ...
                        p.spatialPropagation, ...
                        p.lambda, p.ppx, p.ppy, 0);

                    obj.PhaseFactor = [];

                case "Fresnel"
                    NxP = max(p.PaddingNum, Nx);
                    NyP = max(p.PaddingNum, Ny);

                    [obj.SpatialKernel, obj.PhaseFactor] = ...
                        propagation_kernelFresnel( ...
                        NyP, NxP, ...
                        p.spatialPropagation, ...
                        p.lambda, p.ppx, p.ppy, 0);
            end

            obj.KernelParams = current;
        end

        obj.checkFinite(obj.SpatialKernel, 'Spatial propagation kernel');
    end

    function transformTime(obj, p)
        [Nx, Ny, N] = size(obj.H);

        switch string(p.timeTransform)

            case "FFT"
                obj.SH = fft(obj.H, [], 3) ./ sqrt(N);

            case "PCA"
                obj.SH = short_time_PCA(obj.H);

            case "ICA"
                obj.SH = short_time_ICA(obj.H);

            case "Wavelet_Morlet"
                obj.SH = morlet1D_transform_3rdDim(obj.H, [], 3);

            case "autocorrelation"
                signals = reshape(obj.H, Nx * Ny, N);

                correlations = arrayfun( ...
                    @(k) xcorr(signals(k, :), 'normalized'), ...
                    1:Nx * Ny, ...
                    'UniformOutput', false);

                obj.SH = permute( ...
                    reshape(cell2mat(correlations), [], Nx, Ny), ...
                    [2 3 1]);

            case "intercorrelation"
                obj.SH = intercorrel(obj.H, 3);

            case "phase difference"
                obj.SH = angle(obj.H);

            case "None"
                obj.SH = obj.H;

            otherwise
                error('RenderingClass:UnknownTimeTransform', ...
                    'Unknown time transform: "%s".', ...
                    string(p.timeTransform));
        end

    end

    function orientOutput(obj, p)
        % Lens orientation: x <-> -y.
        obj.SH = flip(permute(obj.SH, [2 1 3]), 2);

        if p.flip_y
            obj.SH = flip(obj.SH, 1);
        end

        if p.flip_x
            obj.SH = flip(obj.SH, 2);
        end

    end

    function validateImageTypes(obj, names)

        for k = 1:numel(names)

            if ~isprop(obj.Output, names{k})
                known = strjoin(fieldnames(obj.Output), ', ');

                error('RenderingClass:UnknownImageType', ...
                    'Unknown image type "%s". Available: %s.', ...
                    names{k}, known);
            end

        end

    end

    function checkFinite(~, A, stage)

        if isempty(A)
            error('RenderingClass:EmptyStage', ...
                'Empty array at stage "%s".', stage);
        end

        nNaN = nnz(isnan(A));
        nInf = nnz(isinf(A));

        if nNaN > 0 || nInf > 0
            error('RenderingClass:NonfiniteStage', ...
                ['Nonfinite data at stage "%s": ' ...
             '%d NaN, %d Inf / %d samples.'], ...
                stage, nNaN, nInf, numel(A));
        end

    end

end

end
