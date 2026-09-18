classdef RenderingClass < handle
% RenderingClass
% Holographic renderer for HoloDoppler.
%
% Internal array convention:
%   Frames(x, y, t)
%
% Angular Spectrum output:
%   H(x, y, t), same spatial size as Frames before orientOutput().
%
% The orientation to MATLAB image convention [y, x, t] is applied only
% later by orientOutput().

properties
    LastParams struct
    Frames single = single.empty
    RawFrames single = single.empty
    FramesChanged logical = false

    SpatialFilterMask = []
    SpatialKernel single = single.empty
    PhaseFactor single = single.empty

    FH single = single.empty
    H single = single.empty
    H_raw single = single.empty
    SH single = single.empty
    cov single = single.empty
    U single = single.empty

    Output ImageTypeList
end

properties (Access = private)
    % Cache key for the spatial propagation kernel.
    lastLambda double = NaN
    lastPpx double = NaN
    lastPpy double = NaN
    lastPropagationDistance double = NaN
    lastTransform string = ""
    lastKernelNx double = NaN
    lastKernelNy double = NaN
end

methods

    % =====================================================================
    function obj = RenderingClass(options)

        arguments
            options.precomputeSpatialKernel = []
        end

        obj.Output = ImageTypeList();
        obj.setInitParams();

        % A precomputed kernel may be accepted, but it is intentionally
        % not marked as valid until its physical metadata and dimensions
        % are checked during the first Render() call.
        if ~isempty(options.precomputeSpatialKernel)
            obj.SpatialKernel = single(options.precomputeSpatialKernel);
        end

    end

    % =====================================================================
    function setInitParams(obj)
        obj.LastParams = HDParamSchema.getDefaults();
    end

    % =====================================================================
    function setFrames(obj, frames)

        if isempty(frames)
            error('RenderingClass:setFrames:emptyFrames', ...
            'Input frame array must not be empty.');
        end

        obj.RawFrames = single(frames);
        obj.Frames = obj.RawFrames;
        obj.FramesChanged = true;
    end

    % =====================================================================
    function Render(obj, p, imageTypes, options)

        arguments
            obj
            p struct
            imageTypes cell = {}
            options.cache_intermediate_results logical = true
        end

        if isempty(obj.Frames)
            error('RenderingClass:Render:noFrames', ...
            'Call setFrames() before Render().');
        end

        obj.Output.select(imageTypes{:});

        [p, changed] = obj.mergeAndDiff(p);
        [Nx, Ny, batchSize] = size(obj.Frames);

        % -----------------------------------------------------------------
        % 1) Spatial filtering
        % -----------------------------------------------------------------
        obj.applySpatialFilter(p, changed, Nx, Ny);

        % A new propagation must occur whenever the frames, the filter, the
        % propagation parameters, or the cache policy changed.
        doFH = obj.FramesChanged || ...
            changed.spatialFilter || ...
            changed.spatialFilterRange1 || ...
            changed.spatialFilterRange2 || ...
            changed.PaddingNum || ...
            changed.spatialTransform || ...
            changed.spatialPropagation || ...
            ~options.cache_intermediate_results;

        obj.applySpatialTransform(p, changed, doFH, Nx, Ny);

        obj.Output.construct_image_from_FH(p, obj.FH);

        if ~options.cache_intermediate_results
            obj.FH = single.empty;
        end

        % -----------------------------------------------------------------
        % 2) SVD filtering
        % -----------------------------------------------------------------
        doSVD = doFH || ...
            changed.svd_filter || ...
            changed.svdThreshold || ...
            changed.svdStride || ...
            changed.frequencyRange1 || ...
            changed.frequencyRange2 || ...
            ~options.cache_intermediate_results;

        obj.applySvdFilter(p, doSVD);

        obj.Output.construct_image_from_SVD( ...
            p, obj.cov, obj.U, size(obj.H));

        % -----------------------------------------------------------------
        % 3) Time transform
        % -----------------------------------------------------------------
        doSH = doSVD || ...
            changed.timeTransform || ...
            changed.flip_y || ...
            changed.flip_x || ...
            ~options.cache_intermediate_results;

        obj.applyTimeTransform(p, doSH, batchSize);

        if ~options.cache_intermediate_results
            obj.H = single.empty;
            obj.H_raw = single.empty;
        end

        % -----------------------------------------------------------------
        % 4) Output image orientation
        % -----------------------------------------------------------------
        if doSH
            obj.orientOutput(p);
        end

        obj.Output.construct_image(p, obj.SH);

        obj.FramesChanged = false;
        obj.LastParams = p;
    end

    % =====================================================================
    function r = getImages(obj, imageTypes)

        obj.validateImageTypes(imageTypes);
        r = obj.collectImages(imageTypes);
    end

end

methods (Access = private)

    % =====================================================================
    function [p, changed] = mergeAndDiff(obj, p)

        fields = fieldnames(obj.LastParams);

        for i = 1:numel(fields)
            f = fields{i};

            if isfield(p, f)
                changed.(f) = ~isequal(p.(f), obj.LastParams.(f));
            else
                changed.(f) = false;
                p.(f) = obj.LastParams.(f);
            end

        end

        newFields = setdiff(fieldnames(p), fields);

        for i = 1:numel(newFields)
            changed.(newFields{i}) = true;
        end

    end

    % =====================================================================
    function applySpatialFilter(obj, p, changed, Nx, Ny)

        filterParamsChanged = changed.spatialFilter || ...
            changed.spatialFilterRange1 || ...
            changed.spatialFilterRange2;

        % If nothing changed, preserve the previously filtered Frames.
        if ~(filterParamsChanged || obj.FramesChanged)
            return
        end

        % Always restart from original frames. This prevents a filter
        % change from applying another Fourier mask to already filtered data.
        obj.Frames = obj.RawFrames;

        if ~p.spatialFilter
            obj.SpatialFilterMask = [];
            return
        end

        obj.SpatialFilterMask = fftshift( ...
            diskMask(Nx, Ny, ...
            p.spatialFilterRange1, ...
            p.spatialFilterRange2))';

        obj.Frames = ifft2( ...
            fft2(obj.RawFrames) .* obj.SpatialFilterMask);
    end

    % =====================================================================
    function applySpatialTransform(obj, p, changed, doFH, Nx, Ny)

        if ~doFH
            return
        end

        transform = lower(strtrim(string(p.spatialTransform)));

        switch transform
            case "angular spectrum"

                [NxP, NyP] = obj.getPaddedSize(p, Nx, Ny);

                obj.ensureAngularSpectrumKernel( ...
                    p, changed, NxP, NyP);

                paddedFrames = pad3DToSize(obj.Frames, NxP, NyP);

                % SpatialKernel is stored in the ordering directly expected
                % by fft2(). No fftshift() is required here.
                propagatedFFT = fft2(paddedFrames) .* obj.SpatialKernel;

                reconstructedPadded = ifft2(propagatedFFT);

                % Return to the original physical camera geometry before
                % SVD filtering, FFT temporal, masks and registration.
                reconstructedField = centerCrop3D( ...
                    reconstructedPadded, Nx, Ny);

                obj.FH = propagatedFFT;
                obj.H = reconstructedField;

                if p.svd_filter
                    obj.H_raw = reconstructedField;
                else
                    obj.H_raw = single.empty;
                end

            case "fresnel"

                [NxP, NyP] = obj.getPaddedSize(p, Nx, Ny);

                kernelChanged = changed.spatialPropagation || ...
                    changed.PaddingNum || ...
                    changed.spatialTransform || ...
                    isempty(obj.SpatialKernel) || ...
                    ~isequal(double(p.lambda), obj.lastLambda) || ...
                    ~isequal(double(p.ppx), obj.lastPpx) || ...
                    ~isequal(double(p.ppy), obj.lastPpy) || ...
                    ~isequal(double(p.spatialPropagation), ...
                    obj.lastPropagationDistance) || ...
                    obj.lastTransform ~= transform || ...
                    ~isequal(NxP, obj.lastKernelNx) || ...
                    ~isequal(NyP, obj.lastKernelNy);

                if kernelChanged
                    % Fresnel's historical kernel API expects Ny then Nx.
                    [obj.SpatialKernel, obj.PhaseFactor] = ...
                        propagation_kernelFresnel( ...
                        NyP, NxP, ...
                        p.spatialPropagation, ...
                        p.lambda, p.ppx, p.ppy, false);

                    obj.updateKernelCache( ...
                        p, transform, NxP, NyP);
                end

                paddedFrames = pad3DToSize(obj.Frames, NxP, NyP);

                propagatedFFT = paddedFrames .* obj.SpatialKernel;

                reconstructedPadded = fftshift( ...
                    fftshift(fft2(propagatedFFT), 1), 2) ...
                    ./ sqrt(NxP * NyP);

                reconstructedField = centerCrop3D( ...
                    reconstructedPadded, Nx, Ny);

                obj.FH = propagatedFFT;
                obj.H = reconstructedField;

                if p.svd_filter
                    obj.H_raw = reconstructedField;
                else
                    obj.H_raw = single.empty;
                end

            case "none"

                obj.FH = single.empty;
                obj.H = single(obj.Frames);

                if p.svd_filter
                    obj.H_raw = obj.H;
                else
                    obj.H_raw = single.empty;
                end

            case "twin image removal"

                obj.FH = single.empty;

                reconstructedField = twin_image_removal_( ...
                    single(obj.Frames), [], changed, p);

                obj.H = reconstructedField;

                if p.svd_filter
                    obj.H_raw = reconstructedField;
                else
                    obj.H_raw = single.empty;
                end

            otherwise
                error('RenderingClass:unknownSpatialTransform', ...
                    'Unknown spatialTransform "%s".', ...
                    string(p.spatialTransform));
        end

    end

    % =====================================================================
    function ensureAngularSpectrumKernel(obj, p, changed, NxP, NyP)

        transform = "angular spectrum";

        kernelChanged = changed.spatialPropagation || ...
            changed.PaddingNum || ...
            changed.spatialTransform || ...
            isempty(obj.SpatialKernel) || ...
            ~isequal(size(obj.SpatialKernel), [NxP NyP]) || ...
            ~isequal(double(p.lambda), obj.lastLambda) || ...
            ~isequal(double(p.ppx), obj.lastPpx) || ...
            ~isequal(double(p.ppy), obj.lastPpy) || ...
            ~isequal(double(p.spatialPropagation), ...
            obj.lastPropagationDistance) || ...
            obj.lastTransform ~= transform || ...
            ~isequal(NxP, obj.lastKernelNx) || ...
            ~isequal(NyP, obj.lastKernelNy);

        if ~kernelChanged
            return
        end

        obj.SpatialKernel = propagation_kernelAngularSpectrum( ...
            NxP, NyP, ...
            p.spatialPropagation, ...
            p.lambda, ...
            p.ppx, ...
            p.ppy, ...
            false);

        obj.updateKernelCache(p, transform, NxP, NyP);
    end

    % =====================================================================
    function updateKernelCache(obj, p, transform, NxP, NyP)

        obj.lastLambda = double(p.lambda);
        obj.lastPpx = double(p.ppx);
        obj.lastPpy = double(p.ppy);
        obj.lastPropagationDistance = double(p.spatialPropagation);
        obj.lastTransform = string(transform);
        obj.lastKernelNx = double(NxP);
        obj.lastKernelNy = double(NyP);
    end

    % =====================================================================
    function [NxP, NyP] = getPaddedSize(~, p, Nx, Ny)

        if ~isfield(p, 'PaddingNum') || isempty(p.PaddingNum)
            paddingNum = 0;
        else
            paddingNum = double(p.PaddingNum);
        end

        if ~isfinite(paddingNum) || paddingNum < 0
            error('RenderingClass:invalidPaddingNum', ...
            'PaddingNum must be a finite non-negative value.');
        end

        paddingNum = round(paddingNum);

        % PaddingNum is a minimum side length, not a compulsory square
        % output size. The two axes remain independent.
        NxP = max(Nx, paddingNum);
        NyP = max(Ny, paddingNum);
    end

    % =====================================================================
    function applySvdFilter(obj, p, doSVD)

        if ~doSVD
            return
        end

        if p.svd_filter

            if isempty(obj.H_raw)
                warning('RenderingClass:noRawField', ...
                    ['H_raw is empty while svd_filter is enabled. ', ...
                 'Using H as the SVD input.']);
                src = obj.H;
            else
                src = obj.H_raw;
            end

            [obj.H, obj.cov, obj.U] = svd_filter( ...
                src, ...
                p.svdThreshold, ...
                p.frequencyRange1, ...
                p.fs, ...
                p.svdStride);
        else
            obj.cov = single.empty;
            obj.U = single.empty;
        end

    end

    % =====================================================================
    function applyTimeTransform(obj, p, doSH, batchSize)

        if ~doSH
            return
        end

        [a, b, ~] = size(obj.H);

        transform = lower(strtrim(string(p.timeTransform)));

        switch transform
            case "pca"
                obj.SH = short_time_PCA(obj.H);

            case "ica"
                obj.SH = short_time_ICA(obj.H);

            case "fft"
                obj.SH = fft(obj.H, [], 3) ./ sqrt(batchSize);

            case "wavelet_morlet"
                obj.SH = morlet1D_transform_3rdDim(obj.H, [], 3);

            case "autocorrelation"
                tmp = reshape(obj.H, a * b, []);

                out = arrayfun( ...
                    @(k) xcorr(tmp(k, :), 'normalized'), ...
                    1:a * b, ...
                    'UniformOutput', false);

                obj.SH = permute( ...
                    reshape(cell2mat(out), [], a, b), ...
                    [2 3 1]);

            case "intercorrelation"
                obj.SH = intercorrel(obj.H, 3);

            case "phase difference"
                obj.SH = angle(obj.H);

            case "none"
                obj.SH = obj.H;

            otherwise
                error('RenderingClass:unknownTimeTransform', ...
                    'Unknown timeTransform "%s".', ...
                    string(p.timeTransform));
        end

    end

    % =====================================================================
    function orientOutput(obj, p)

        % Internal convention: H(x, y, t).
        % Image convention after orientation: SH(y, x, t).
        obj.SH = flip(permute(obj.SH, [2 1 3]), 2);

        if p.flip_y
            obj.SH = flip(obj.SH, 1);
        end

        if p.flip_x
            obj.SH = flip(obj.SH, 2);
        end

    end

    % =====================================================================
    function validateImageTypes(obj, imageTypes)

        for i = 1:numel(imageTypes)

            if ~isprop(obj.Output, imageTypes{i})
                known = sprintf('%s, ', ...
                    string(fieldnames(obj.Output)));

                error("'%s' is not a known image type. Available: [%s]", ...
                    imageTypes{i}, known);
            end

        end

    end

    % =====================================================================
    function r = collectImages(obj, imageTypes)

        silent = {'buckets', 'full_buckets', 'SH', 'SH_avg'};
        r = cell(1, numel(imageTypes));

        for i = 1:numel(imageTypes)

            im = obj.Output.(imageTypes{i}).image;

            if isempty(im)

                if ~ismember(imageTypes{i}, silent)
                    fprintf("Warning: '%s' produced no image.\n", ...
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

% =========================================================================
% Module-level helpers
% =========================================================================

function out = centerCrop3D(in, targetNx, targetNy)
% CENTERCROP3D Center-crop [NxP,NyP,Nt] to [targetNx,targetNy,Nt].

inputNx = size(in, 1);
inputNy = size(in, 2);

if targetNx > inputNx || targetNy > inputNy
    error('centerCrop3D:targetTooLarge', ...
    'Target dimensions must not exceed input dimensions.');
end

startX = floor((inputNx - targetNx) / 2) + 1;
startY = floor((inputNy - targetNy) / 2) + 1;

out = in( ...
    startX:startX + targetNx - 1, ...
    startY:startY + targetNy - 1, ...
    :);
end

function out = pad3DToSize(in, targetNx, targetNy)
% PAD3DTOSIZE Zero-pad [Nx,Ny,Nt] symmetrically to [targetNx,targetNy,Nt].

inputNx = size(in, 1);
inputNy = size(in, 2);

padX = targetNx - inputNx;
padY = targetNy - inputNy;

if padX < 0 || padY < 0
    error('pad3DToSize:targetTooSmall', ...
        ['Target dimensions must be greater than or equal to ', ...
     'input dimensions.']);
end

preX = floor(padX / 2);
postX = ceil(padX / 2);

preY = floor(padY / 2);
postY = ceil(padY / 2);

out = padarray(in, [preX preY 0], 0, 'pre');
out = padarray(out, [postX postY 0], 0, 'post');
end
