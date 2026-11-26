classdef HoloDopplerClass < handle
% HoloDopplerClass  GPU-accelerated holographic Doppler video renderer.
%   HD.params : rendering parameters only (validated by HDParamSchema).
%   HD.file   : file-bound metadata (Nx, Ny, num_frames, fs, lambda, ppx, ppy, ...).
%   params.square == false  ->  NO image is resized (preview, PNG, video).

properties
    file
    drawer_list cell
    reader
    render
    params
    video
    running_averages
    registration
    autofocusResult = struct()
    poolManager
end

properties (Constant, Access = private)
    FILE_BOUND = {'Nx', 'Ny', 'num_frames', 'fs', 'lambda', 'ppx', 'ppy'}
    NO_REGISTRATION = {'broadening', 'fRMS', 'FH_modulus_mean', 'FH_arg_mean', 'SVD_cov', 'SVD_U'}
end

methods

    function obj = HoloDopplerClass()

        if ~isdeployed
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            addpath(genpath(fullfile(root, 'src')));
        end

        obj.render = RenderingClass();
        obj.params = HDParamSchema.getDefaults();
        set(0, 'defaultfigurecolor', [1 1 1]);
    end

    % ------------------------------------------------------------------
    function LoadFile(obj, file_path, opt)

        arguments
            obj
            file_path
            opt.params = []
            opt.interactive = true
        end

        obj.reader = []; obj.video = []; obj.registration = [];
        obj.render = RenderingClass();
        obj.running_averages = RunningAveragesHolder();

        [d, n, ext] = fileparts(file_path);
        obj.file = struct('path', file_path, 'dir', d, 'name', n, 'ext', ext);

        try

            switch ext
                case '.holo', readHoloMeta(obj, file_path);
                case '.cine', readCineMeta(obj, file_path);
                otherwise
                    error('HoloDopplerClass:LoadFile:unsupported', ...
                        'Unsupported file extension: %s', ext);
            end

        catch ME
            obj.file = []; obj.reader = [];
            rethrow(ME);
        end

        if isempty(opt.params)
            fileInfo = rmfield(obj.file, intersect(fieldnames(obj.file), ...
                {'path', 'dir', 'name', 'info', 'record_time_stamps_us'}));

            try
                fileInfo.propagation_distance = ...
                    obj.reader.footer.compute_settings.image_rendering.propagation_distance;
            catch
            end

            obj.params = getFileParameters(file_path, fileInfo);
        else
            obj.params = HDParamSchema.validate(opt.params);
        end

    end

    % ------------------------------------------------------------------
    function setParams(obj, params)

        if ~isstruct(params)
            warning('HoloDopplerClass:setParams:notAStruct', 'Non-struct input ignored.');
            return
        end

        params = rmfieldIfPresent(params, obj.FILE_BOUND);
        merged = obj.params;

        for f = fieldnames(params)'
            merged.(f{1}) = params.(f{1});
        end

        obj.params = HDParamSchema.validate(merged);
    end

    function loadParams(obj, path)
        fid = fopen(path, 'r');

        if fid == -1
            error('HoloDopplerClass:loadParams:cannotOpenFile', 'Cannot open: %s', path);
        end

        c = onCleanup(@() fclose(fid));
        decoded = jsondecode(fread(fid, inf, '*char')');

        if isstruct(decoded)
            obj.setParams(decoded);
        else
            warning('HoloDopplerClass:loadParams:notAStruct', ...
                '"%s" is not a JSON object - ignored.', path);
        end

    end

    function outputPath = saveParams(obj, filename, save_z)

        if nargin < 2 || isempty(filename)
            d = obj.file.dir; n = obj.file.name;
        else
            [d, n] = fileparts(filename);
        end

        if nargin < 3, save_z = true; end

        parms = rmfieldIfPresent(obj.params, [obj.FILE_BOUND, {'info'}]);

        if ~save_z && isfield(obj.file, 'record_time_stamps_us')
            parms = rmfieldIfPresent(parms, {'spatialPropagation'});
        end

        outputPath = fullfile(ensureDir(fullfile(d, n)), sprintf('%s_input_HD_params.json', n));
        writeJson(outputPath, parms);
    end

    function clearParams(obj)

        if isempty(obj.file)
            warning('clearParams:noFile', 'No file loaded.'); return
        end

        base = fullfile(obj.file.dir, obj.file.name);
        n = obj.file.name;
        paths = {fullfile(base, sprintf('%s_input_HD_params.json', n)), ...
                     fullfile(base, sprintf('%s_HD', n), sprintf('%s_HD_input_HD_params.json', n))};
        existing = paths(cellfun(@isfile, paths));
        if isempty(existing), fprintf('No parameter files found.\n'); return, end

        for k = 1:numel(existing)
            delete(existing{k});
            fprintf('Deleted: %s\n', existing{k});
        end

    end

    % ------------------------------------------------------------------
    function images = PreviewRendering(obj)
        obj.requireFile();
        p = obj.params;

        first = single(obj.reader.read_frame_batch(1, p.framePosition));
        stale = isempty(obj.render.Frames) || size(obj.render.Frames, 3) ~= p.batchSize ...
            || ~isequal(obj.render.Frames(:, :, 1), first);

        if stale
            obj.render.setFrames(obj.reader.read_frame_batch(p.batchSize, p.framePosition));
        end

        obj.render.Render(obj.buildRenderParams(), p.imageTypes);
        images = obj.render.getImages(p.imageTypes);

        % Display-only squaring, ONLY when the Square checkbox is ticked.
        if p.square

            for i = 1:numel(images)

                if ~isempty(images{i}) && ~strcmp(p.imageTypes{i}, 'broadening')
                    images{i} = squareImage(images{i});
                end

            end

        end

    end

    function images = showPreviewImages(obj, types)
        if nargin < 2, types = obj.params.imageTypes; end
        images = obj.render.getImages(types);
        out = cell(size(images));

        for i = 1:numel(images)

            if isempty(images{i})
                m = max(cellfun(@(x) max(size(x)), images));
                out{i} = zeros(max(m, 1));
                continue
            end

            out{i} = rescale(images{i});

            if obj.params.square
                out{i} = squareImage(out{i});
            end

        end

        figure(18); montage(out);
    end

    function savePreview(obj, types)
        if nargin < 2, types = obj.params.imageTypes; end
        folder = ensureDir(fullfile(obj.file.dir, obj.file.name, ...
            sprintf('%s_HDPreview', obj.file.name)));
        keepAspect = {'moment_0', 'moment_1', 'moment_2', 'SVD_cov', 'SVD_U', ...
                          'FH_modulus_mean', 'FH_arg_mean', 'broadening'};

        images = obj.render.getImages(types);

        for i = 1:numel(images)
            if isempty(images{i}), continue, end
            img = toImageSource(images{i});

            if obj.params.square && ~ismember(types{i}, keepAspect)
                img = squareImage(img);
            end

            imwrite(img, fullfile(folder, sprintf('%s_%s.png', obj.file.name, types{i})));
        end

        writeJson(fullfile(folder, sprintf('%s_HDPreview_input_HD_params.json', obj.file.name)), ...
            obj.params);
    end

    % ------------------------------------------------------------------
    function result_folder_path = VideoRendering(obj)
        obj.requireFile();
        p = obj.params;
        [first, last, nBatches] = obj.frameRange();

        if nBatches <= 0
            fprintf('No complete batch (%d frames, batchSize=%d).\n', last - first + 1, p.batchSize);
            result_folder_path = '';
            return
        end

        fprintf('Rendering %s: frames %d-%d, %d batches (size %d, stride %d)\n', ...
            obj.file.path, first, last, nBatches, p.batchSize, p.batchStride);

        rp = obj.buildRenderParams();
        kernel = generate_spatial_kernel(obj.file.Nx, obj.file.Ny, p.PaddingNum, ...
            p.spatialTransform, p.spatialPropagation, obj.file.lambda, obj.file.ppx, obj.file.ppy);

        numWorkers = obj.acquirePool(p.parforArg);

        if numWorkers > 0
            poolCleanup = onCleanup(@() obj.poolManager.release());
        end

        fprintf('Using %d worker(s).\n', numWorkers);

        h = waitbar(0, 'Rendering video...'); styleWaitbar(h);
        wbCleanup = onCleanup(@() closeWaitbarSafe(h));
        done = 0;
        step = max(1, floor(nBatches / 100));

        function tick(~)
            done = done + 1;

            if isgraphics(h) && (mod(done, step) == 0 || done == nBatches)
                waitbar(done / nBatches, h, sprintf('Rendering %d/%d', done, nBatches));
            end

        end

        results = cell(1, nBatches);
        local_reader = obj.reader;
        tRender = tic;

        if numWorkers == 0

            for i = 1:nBatches
                results{i} = processBatchFromReader(local_reader, i, first, rp, kernel);
                tick();
            end

        else
            cK = parallel.pool.Constant(kernel);
            D = parallel.pool.DataQueue;
            afterEach(D, @tick);

            parfor (i = 1:nBatches, numWorkers)
                results{i} = processBatchFromReader(local_reader, i, first, rp, cK.Value);
                send(D, 1);
            end

        end

        fprintf('Rendering took %.2f s\n', toc(tRender));

        obj.storeResults(results);

        if p.imageRegistration && ismember('power_Doppler', p.imageTypes)
            obj.CalculateRegistration();
            obj.ApplyRegistration();
        end

        obj.accumulateSHavg();

        result_folder_path = obj.SaveVideo();
    end

    % ------------------------------------------------------------------
    function CalculateRegistration(obj)

        if isempty(obj.video)
            error('HoloDopplerClass:CalculateRegistration:noVideo', 'No video rendered');
        end

        if ~ismember('power_Doppler', obj.params.imageTypes)
            error('HoloDopplerClass:CalculateRegistration:noPowerDoppler', ...
            'power_Doppler is required for registration.');
        end

        nB = numel(obj.video);
        radius = getRegistrationSetting(obj.params, 'registration_radius', 0.8);
        sigma = getRegistrationSetting(obj.params, 'registration_gaussian_sigma', 3);
        flatSig = getRegistrationSetting(obj.params, 'registration_flatfield_gw', 1.0);

        ref = obj.video(1).power_Doppler.image;

        if isempty(ref) || ~ismatrix(ref)
            error('HoloDopplerClass:CalculateRegistration:badReference', ...
            'Batch-1 power_Doppler must be a non-empty 2-D array.');
        end

        mask = pythonEllipticalMask(size(ref, 1), size(ref, 2), radius);
        prep = @(M) preprocessRegistrationImage(gaussianFlatfieldPython(M, flatSig), mask, sigma);

        refSpectrumConj = conj(fft2(prep(ref)));
        shifts = zeros(2, nB);

        for b = 2:nB
            M = obj.video(b).power_Doppler.image;

            if isempty(M) || ~isequal(size(M), size(ref))
                error('HoloDopplerClass:CalculateRegistration:badBatch', ...
                    'Batch %d: power_Doppler empty or size differs from batch 1.', b);
            end

            shifts(:, b) = intensityCorrelationFromSpectrum(refSpectrumConj, prep(M));
        end

        obj.registration = struct('shifts', shifts, 'rotation', [], 'scale', []);
    end

    function ApplyRegistration(obj)
        refSize = size(obj.video(1).power_Doppler.image);

        for itype = obj.params.imageTypes(:)'
            t = itype{1};
            if ismember(t, obj.NO_REGISTRATION), continue, end

            for i = 1:numel(obj.video)
                s = obj.registration.shifts(:, i);
                if ~any(s), continue, end

                switch t
                    case {'SH', 'SH_avg'}
                        obj.video(i).(t).parameters.SH = shiftXY( ...
                            obj.video(i).(t).parameters.SH, s, refSize);
                    otherwise
                        obj.video(i).(t).image = shiftXY(obj.video(i).(t).image, s, refSize);
                end

            end

        end

    end

    % ------------------------------------------------------------------
    function folder = SaveVideo(obj, imageTypes, params)
        if nargin < 2, imageTypes = obj.params.imageTypes; end
        if nargin < 3, params = obj.params; end

        tSave = tic;
        h = waitbar(0, 'Saving video...'); styleWaitbar(h);
        wbCleanup = onCleanup(@() closeWaitbarSafe(h));

        folder = ensureDir(fullfile(obj.file.dir, obj.file.name, ...
            sprintf('%s_HD_MATLAB', obj.file.name)));
        for s = {'avi', 'h5', 'png', 'json'}, ensureDir(fullfile(folder, s{1})); end
        generateParametersJson(params, obj.file, folder);

        [~, dirName] = fileparts(folder);
        h5path = fullfile(folder, 'h5', sprintf('%s_output.h5', dirName));
        config = getConfigs();
        N = max(numel(imageTypes), 1);

        for i = 1:numel(imageTypes)
            type = imageTypes{i};
            waitbar((i - 1) / N, h, sprintf('Saving %s', strrep(type, '_', ' ')));
            batches = {obj.video.(type)};

            switch type
                case 'SH', obj.saveSH(batches, h5path, params);
                case 'SH_avg', obj.saveSHavg(h5path, folder, params);
                otherwise
                    mat = stackImages(batches);

                    if isempty(mat)
                        fprintf('%s was not found - skipping.\n', type);
                    elseif isfield(config, type)
                        opts = config.(type).opts;
                        opts.square = params.square; % GUI checkbox always wins
                        nv = namedargs2cell(opts);
                        generate_video(mat, folder, config.(type).name, nv{:});
                    else
                        generate_video(mat, folder, type, 'square', params.square);
                    end

            end

        end

        waitbar(1, h, 'Saving complete');

        if obj.params.imageRegistration && ~isempty(obj.registration)
            tryDo(@() export_h5_video(h5path, "registration", single(obj.registration.shifts)), ...
            'Error while saving the registration.');
        end

        tryDo(@() export_h5_string(h5path, "HD_parameters", jsonencode(params)), ...
        'Error while saving the parameters.');

        writeJson(fullfile(folder, sprintf('%s_HD_input_HD_params.json', obj.file.name)), params);
        root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
        writeVersionInfo(folder, root);

        fprintf('Video saving took %.2f s - results in %s\n', toc(tSave), folder);
    end

end

% =========================================================================
methods (Access = private)

    function requireFile(obj)

        if isempty(obj.reader)
            error('HoloDopplerClass:noFile', 'No file loaded.');
        end

    end

    function rp = buildRenderParams(obj)
        rp = obj.params;

        for f = obj.FILE_BOUND
            rp.(f{1}) = obj.file.(f{1});
        end

    end

    function [first, last, nBatches] = frameRange(obj)
        p = obj.params;
        n = obj.file.num_frames;
        first = 1;

        if isscalar(p.first_frame) && isfinite(p.first_frame) && p.first_frame >= 1
            first = round(p.first_frame);
        end

        last = n;

        if isscalar(p.end_frame) && isfinite(p.end_frame) && p.end_frame > 0
            last = min(round(p.end_frame), n);
        end

        if first > last
            error('HoloDopplerClass:invalidFrameRange', ...
                'first_frame (%d) must not exceed end_frame (%d).', first, last);
        end

        if p.batchSize < 1 || p.batchStride < 1
            error('HoloDopplerClass:invalidBatchParameters', ...
            'batchSize and batchStride must be positive.');
        end

        avail = last - first + 1;
        nBatches = floor((avail - p.batchSize) / p.batchStride) + 1;

        if nBatches > 0
            last = first + (nBatches - 1) * p.batchStride + p.batchSize - 1;
        end

    end

    function n = acquirePool(obj, requested)
        n = 0;
        if requested <= 0, return, end
        maxW = parcluster().NumWorkers;

        if requested > maxW
            warning('HoloDopplerClass:maxWorkers', 'Using %d workers instead of %d.', maxW, requested);
            requested = maxW;
        end

        if isempty(obj.poolManager)
            obj.poolManager = ParallelPoolManager(requested);
        end

        obj.poolManager.acquire();
        n = obj.poolManager.Pool.NumWorkers;
    end

    function storeResults(obj, results)
        obj.video = ImageTypeList.empty(numel(results), 0);

        for b = 1:numel(results)
            obj.video(b) = ImageTypeList();

            for t = fieldnames(results{b})'
                r = results{b}.(t{1});
                obj.video(b).(t{1}).image = r.image;
                obj.video(b).(t{1}).parameters = r.parameters;
                obj.video(b).(t{1}).is_selected = true;
            end

        end

    end

    function accumulateSHavg(obj)
        obj.running_averages = RunningAveragesHolder();
        if ~ismember('SH_avg', obj.params.imageTypes), return, end

        for b = 1:numel(obj.video)
            cube = obj.video(b).SH_avg.parameters.SH;

            if isempty(cube)
                error('HoloDoppler:MissingSHAvgCube', 'Batch %d: SH_avg cube is empty.', b);
            end

            obj.running_averages.update(cube, b, obj.params);
        end

        fprintf('SH_avg: %d cubes summed.\n', obj.running_averages.numUpdates);
    end

    function saveSH(obj, batches, h5path, params)
        cubes = cellfun(@(b) b.parameters.SH, batches, 'UniformOutput', false);
        mat = single(cat(3, cubes{:}));
        export_h5_video(h5path, "SH_power", mat);
        export_h5_string(h5path, "SH_axis_convention", ...
            "SH_power(y_bin, x_bin, frequency_bin); spatial bins are non-overlapping " + ...
        "block means; frequency_bin is the FFT bin within each batch");
        m = batches{1}.parameters;
        export_h5_string(h5path, "SH_processing", jsonencode(struct( ...
            'fs_kHz', obj.file.fs, 'batchSize', params.batchSize, ...
            'batchStride', params.batchStride, ...
            'spatialPropagation_m', params.spatialPropagation, ...
            'spatialTransform', params.spatialTransform, ...
            'SVD_enabled', params.svd_filter, 'SVD_threshold', params.svdThreshold, ...
            'registration_enabled', params.imageRegistration, ...
            'SH_spatial_binning', m.spatial_binning, 'SH_original_size', m.original_size, ...
            'SH_binned_size', m.binned_size, 'SH_crop_size', m.crop_size, ...
            'SH_spatial_reduction', m.reduction)));
    end

    function saveSHavg(obj, h5path, folder, params)

        if obj.running_averages.numUpdates == 0
            error('HoloDoppler:EmptySHAvg', 'No spectral power cube was accumulated.');
        end

        mat = gather(obj.running_averages.running_averages.SH);
        export_h5_video(h5path, "SH_avg", single(mat));
        generate_video(SHavgToFrequencySweep(mat, "all"), folder, 'SH_avg', ...
            'temporalFilter', [], 'square', params.square, 'export_raw', false, ...
            'substractFlash', false, 'enhance_contrast', false);
    end

end

end

% =========================================================================
% Local helpers
% =========================================================================
function readHoloMeta(obj, path)
f = obj.file;

try
    obj.reader = HoloReader(path);
catch ME
    MEdisp(ME);
    error('HoloDopplerClass:LoadFile:holoReadFailed', ...
        "Couldn't read the holo file: %s", ME.message);
end

r = obj.reader;
f.info = readerInfo(r, {'filename'});
f.Nx = r.frame_width;
f.Ny = r.frame_height;
f.num_frames = double(r.num_frames);

if r.version >= 5
    f.lambda = r.footer.compute_settings.image_rendering.lambda;
    f.ppx = r.footer.info.pixel_pitch.x * 1e-6;
    f.ppy = r.footer.info.pixel_pitch.y * 1e-6;
else
    fprintf('Old Holovibes version - using schema defaults for lambda/ppx/ppy.\n');
    d = HDParamSchema.getDefaults();
    f.lambda = d.lambda_file_default;
    f.ppx = d.ppx_file_default;
    f.ppy = d.ppy_file_default;
end

try
    f.fs = r.footer.info.camera_fps / 1000;
catch

    try
        f.fs = r.footer.info.input_fps / 1000;
    catch
        f.fs = 1;
        fprintf('No fps info in holo file - fs = 1 kHz.\n');
    end

end

try
    f.record_time_stamps_us.first = r.footer.info.timestamps_us.unix_first;
    f.record_time_stamps_us.last = r.footer.info.timestamps_us.unix_last;
catch
end

obj.file = f;
end

function readCineMeta(obj, path)
f = obj.file;

try
    obj.reader = CineReader(path);
catch ME
    MEdisp(ME);
    error('HoloDopplerClass:LoadFile:cineReadFailed', ...
        'The file is not a valid cine file: %s', ME.message);
end

r = obj.reader;
f.info = readerInfo(r, {'filename', 'rephasing_data'});
f.lambda = 852e-9;
f.Nx = double(r.frame_width);
f.Ny = double(r.frame_height);
f.ppx = 1 / double(r.horizontal_pix_per_meter);
f.ppy = 1 / double(r.vertical_pix_per_meter);
f.fs = double(r.frame_rate) / 1000;
f.num_frames = double(r.num_frames);
obj.file = f;
end

function info = readerInfo(reader, exclude)
info = struct();

for p = setdiff(properties(reader), exclude)'
    info.(p{1}) = reader.(p{1});
end

end

function s = rmfieldIfPresent(s, names)
s = rmfield(s, intersect(fieldnames(s), names));
end

function d = ensureDir(d)
if ~isfolder(d), mkdir(d); end
end

function writeJson(path, data)
fid = fopen(path, 'w');

if fid == -1
    warning('HoloDopplerClass:cannotWrite', 'Could not write %s', path);
    return
end

c = onCleanup(@() fclose(fid));
fwrite(fid, jsonencode(data, 'PrettyPrint', true), 'char');
end

function tryDo(fcn, msg)

try
    fcn();
catch ME
    MEdisp(ME);
    disp(msg);
end

end

function img = squareImage(img)
m = max(size(img, 1), size(img, 2));

if size(img, 1) ~= size(img, 2)
    img = imresize(img, [m m]);
end

end

function mat = stackImages(batches)
mat = [];
if isempty(batches) || isempty(batches{1}.image), return, end
sz = size(batches{1}.image);
sz(end + 1:3) = 1;
mat = zeros([sz(1:3) numel(batches)], 'single');

for j = 1:numel(batches)
    if ~isempty(batches{j}.image), mat(:, :, :, j) = batches{j}.image; end
end

if size(mat, 4) == 1, mat = repmat(mat, [1 1 1 2]); end
end

function A = shiftXY(A, shift, refSize)
ratio = [size(A, 1) size(A, 2)] ./ refSize;
A = circshift(A, round(shift(:)' .* ratio));
end

function writeVersionInfo(folder, appRoot)
copyfile(fullfile(appRoot, 'version.txt'), folder);

try
    [~, hash] = system('git rev-parse HEAD');
    [~, branch] = system('git rev-parse --abbrev-ref HEAD');
    [~, last] = system('git log -1 --pretty=oneline');
    txt = sprintf('Commit hash: %s\nBranch: %s\nLast commit: %s', ...
        strtrim(hash), strtrim(branch), strtrim(last));
    fid = fopen(fullfile(folder, 'git.txt'), 'w');

    if fid ~= -1
        fwrite(fid, txt, 'char');
        fclose(fid);
    end

catch ME
    MEdisp(ME);
    disp('No git info.');
end

end

function outImages = processBatchFromReader(reader, batchIdx, first_frame, rp, kernel)
frames = reader.read_frame_batch(rp.batchSize, first_frame + (batchIdx - 1) * rp.batchStride);
lr = RenderingClass('precomputeSpatialKernel', kernel);
lr.setFrames(frames);
lr.Render(rp, rp.imageTypes, 'cache_intermediate_results', false);

outImages = struct();

for t = rp.imageTypes(:)'
    o = lr.Output.(t{1});
    outImages.(t{1}) = struct('image', o.image, 'parameters', o.parameters);
end

if ismember('SH_avg', rp.imageTypes)

    if isempty(lr.SH)
        error('HoloDoppler:MissingBatchSpectrum', 'Batch %d: RenderingClass.SH is empty.', batchIdx);
    end

    outImages.SH_avg.parameters.SH = single(gather(abs(lr.SH) .^ 2));
end

end

function closeWaitbarSafe(h)
if ~isempty(h) && isgraphics(h), close(h); end
end

function spatialKernel = generate_spatial_kernel( ...
    Nx, Ny, paddingNum, transformation, z, lambda, ppx, ppy)
% Kernel at the same padded size as RenderingClass (min size per axis).
transform = lower(strtrim(string(transformation)));
if isempty(paddingNum) || ~isfinite(paddingNum), paddingNum = 0; end
paddingNum = round(double(paddingNum));

if paddingNum < 0
    error('HoloDopplerClass:generateSpatialKernel:invalidPadding', ...
    'PaddingNum must be non-negative.');
end

NxP = max(double(Nx), paddingNum);
NyP = max(double(Ny), paddingNum);

switch transform
    case "angular spectrum"
        spatialKernel = propagation_kernelAngularSpectrum(NxP, NyP, z, lambda, ppx, ppy, false);
    case "fresnel"
        [spatialKernel, ~] = propagation_kernelFresnel(NyP, NxP, z, lambda, ppx, ppy, false);
    case {"none", "twin image removal"}
        spatialKernel = single.empty;
    otherwise
        error('HoloDopplerClass:generateSpatialKernel:unknownTransform', ...
            'Unknown spatial transformation "%s".', string(transformation));
end

spatialKernel = single(spatialKernel);
end

function [config, defaultUnknown] = getConfigs()
% 'square' is overridden by params.square in SaveVideo.
config = struct();
defaultOpts = struct( ...
    'export_raw', true, 'temporalFilter', [], 'square', true, ...
    'substractFlash', true, 'enhance_contrast', true, ...
    'contrast_inversion', false, 'cornerNorm', false, 'export_avg_img', true);

config.moment_0 = struct('name', 'moment0', 'opts', defaultOpts);
config.moment_1 = struct('name', 'moment1', 'opts', defaultOpts);
config.moment_2 = struct('name', 'moment2', 'opts', defaultOpts);
config.LF_M0 = struct('name', 'LF_M0', 'opts', defaultOpts);
config.HF_M0 = struct('name', 'HF_M0', 'opts', defaultOpts);
config.gaussian_w = struct('name', 'gaussian_w', 'opts', defaultOpts);

opts_pd = defaultOpts;
opts_pd.export_raw = false;
config.power_Doppler = struct('name', 'M0', 'opts', opts_pd);
config.band_ratio = struct('name', 'band_ratio', 'opts', opts_pd);

simpleOpts = struct('temporalFilter', [], 'square', true, 'export_raw', false, ...
    'substractFlash', true, 'enhance_contrast', false);
config.broadening = struct('name', 'broadening', 'opts', simpleOpts);
config.f_RMS = struct('name', 'f_RMS', 'opts', simpleOpts);
config.FH_modulus_mean = struct('name', 'FH_modulus_mean', 'opts', simpleOpts);
config.FH_arg_mean = struct('name', 'FH_arg_mean', 'opts', simpleOpts);

config.arg_0 = struct('name', 'arg_0', 'opts', struct('square', true));
config.SVD_cov = struct('name', 'SVD_cov', 'opts', struct());
config.SVD_U = struct('name', 'SVD_U', 'opts', struct());
config.color_Doppler = struct('name', 'color_Doppler', ...
    'opts', struct('square', true, 'enhance_contrast', true));

defaultUnknown = struct('temporalFilter', 2, 'square', true);
end

function out = gaussianFlatfieldPython(M0, sigma)
M0 = single(M0);

if sigma <= 0
    out = M0;
    return
end

blurred = gaussianFilterScipyLike(M0, sigma);
out = M0 ./ max(blurred, eps('single'));
end

function out = preprocessRegistrationImage(img, mask, sigma)
out = single(img);

if sigma > 0
    out = gaussianFilterScipyLike(out, sigma);
end

maskF = single(mask);
maskSum = max(sum(maskF, 'all'), single(1));
meanValue = sum(out .* maskF, 'all') ./ maskSum;
out = (out - meanValue) .* maskF;
end

function out = gaussianFilterScipyLike(img, sigma)
radius = floor(4 * sigma + 0.5);
out = imgaussfilt(single(img), sigma, 'FilterSize', 2 * radius + 1, 'Padding', 'symmetric');
end

function mask = pythonEllipticalMask(ny, nx, radius)
cy = (ny - 1) / 2;
cx = (nx - 1) / 2;
[X, Y] = meshgrid(1:nx, 1:ny);
mask = ((Y - 1 - cy) ./ (radius * ny / 2)) .^ 2 + ...
    ((X - 1 - cx) ./ (radius * nx / 2)) .^ 2 <= 1;
end

function value = getRegistrationSetting(params, name, defaultValue)

if isfield(params, name) && ~isempty(params.(name)) && isfinite(params.(name))
    value = double(params.(name));
else
    value = defaultValue;
end

end

function shift = intensityCorrelationFromSpectrum(fixedSpectrumConj, moving)
moving = single(moving);

if ~isequal(size(fixedSpectrumConj), size(moving))
    error('HoloDoppler:RegistrationSizeMismatch', ...
    'Registration inputs must be 2-D arrays of identical size.');
end

ny = size(moving, 1);
nx = size(moving, 2);
corrMagnitude = abs(ifft2(fft2(moving) .* fixedSpectrumConj));

transposedMagnitude = corrMagnitude.';
[~, index] = max(transposedMagnitude(:));
[kx, ky] = ind2sub([nx, ny], index);

peakY = ky - 1;
peakX = kx - 1;
if peakY > floor(ny / 2), peakY = peakY - ny; end
if peakX > floor(nx / 2), peakX = peakX - nx; end

shift =- [peakY; peakX];
end

function [sweep, freqBins] = SHavgToFrequencySweep(cube, mode, isFFTShifted, diameterRatio)
% SH_avg cube (Ny, Nx, nFreq) -> video (Ny, Nx, 1, nFreqOut).
arguments
    cube {mustBeNumeric}
    mode (1, 1) string {mustBeMember(mode, ["positive", "sum", "all"])} = "positive"
    isFFTShifted (1, 1) logical = false
    diameterRatio (1, 1) double {mustBePositive, mustBeFinite} = 0.9
end

if ndims(cube) ~= 3
    error('HoloDoppler:SHavgSweepBadCube', 'SH_avg must be a 3-D (Ny, Nx, nFreq) cube.');
end

cube = max(single(cube), 0);
[Ny, Nx, nFreq] = size(cube);

insideMask = pythonEllipticalMask(Nx, Ny, diameterRatio);

if ~any(insideMask, 'all')
    error('HoloDoppler:SHavgSweepEmptyMask', ...
        'The analysis circle contains no pixel (diameterRatio = %.3g).', diameterRatio);
end

if isFFTShifted
    cube = ifftshift(cube, 3);
end

nPos = floor(nFreq / 2);

switch mode
    case "all"
        freqBins = (0:nFreq - 1) - nFreq * ((0:nFreq - 1) > nPos);
        [freqBins, order] = sort(freqBins);
        out = cube(:, :, order);

    case "positive"
        freqBins = 0:nPos;
        out = cube(:, :, freqBins + 1);

    case "sum"
        freqBins = 0:nPos;
        out = cube(:, :, freqBins + 1);
        last = nPos;
        if mod(nFreq, 2) == 0, last = nPos - 1; end

        for k = 1:last
            out(:, :, k + 1) = out(:, :, k + 1) + cube(:, :, nFreq - k + 1);
        end

end

nOut = size(out, 3);
sweep = zeros(Ny, Nx, 1, nOut, 'single');

for f = 1:nOut
    frame = out(:, :, f);
    logFrame = log10(frame + eps('single') * max(frame, [], 'all') + realmin('single'));

    values = sort(logFrame(insideMask));
    n = numel(values);
    lo = values(max(1, round(0.01 * n)));
    hi = values(min(n, max(1, round(0.995 * n))));

    if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
        continue
    end

    sweep(:, :, 1, f) = min(max((logFrame - lo) ./ (hi - lo), 0), 1);
end

if nOut == 1
    sweep = repmat(sweep, [1 1 1 2]);
end

end
