classdef HoloDopplerClass < handle
    % HoloDopplerClass  GPU-accelerated holographic Doppler video renderer.
    %
    %   HD = HoloDopplerClass() creates an instance.
    %
    %   Design rules
    %   ------------
    %   • HD.params   – rendering parameters ONLY (validated via HDParamSchema).
    %                   Single source of truth for all rendering decisions.
    %   • HD.file     – file-bound metadata (Nx, Ny, num_frames, fs, lambda,
    %                   ppx, ppy, path, dir, name, ext, info).
    %                   Never duplicated in HD.params.
    %   • All writes to HD.params go through setParams(), which calls
    %     HDParamSchema.validate() and replaces any corrupt field with its
    %     schema default.

    properties
        file % file metadata struct  (Nx, Ny, num_frames, fs, …)
        drawer_list cell
        reader
        render % RenderingClass
        params % rendering parameters struct (schema-validated)
        video % ImageTypeList array (one per batch)
        running_averages
        registration
        autofocusResult = struct()
        poolManager
    end

    methods

        % =====================================================================
        function obj = HoloDopplerClass()

            if ~isdeployed
                root = fileparts(mfilename('fullpath'));
                addpath( ...
                    fullfile(root, 'FolderManagement'), ...
                    fullfile(root, 'Imaging'), ...
                    fullfile(root, 'Interface'), ...
                    fullfile(root, 'ReaderClasses'), ...
                    fullfile(root, 'Rendering'), ...
                    fullfile(root, 'Saving'), ...
                    fullfile(root, 'Saving', 'Registering'), ...
                    fullfile(root, 'Tools'), ...
                    fullfile(root, 'StandardConfigs'));
            end

            obj.render = RenderingClass();
            obj.params = HDParamSchema.getDefaults(); % always start clean
            set(0, 'defaultfigurecolor', [1 1 1]);
        end

        % =====================================================================
        function LoadFile(obj, file_path, opt)

            arguments
                obj
                file_path
                opt.params = []
                opt.interactive = true % seul flag restant
            end

            % 0) Reset state
            obj.reader = [];
            obj.file = [];
            obj.render = RenderingClass();
            obj.video = [];
            obj.running_averages = RunningAveragesHolder();
            obj.registration = [];

            [dir_, name, ext] = fileparts(file_path);
            obj.file.path = file_path;
            obj.file.dir = dir_;
            obj.file.name = name;
            obj.file.ext = ext;

            % ------------------------------------------------------------------
            % 1) Lecture des métadonnées (remplit obj.file)
            % ------------------------------------------------------------------
            holo_versionThreshold = 5;

            switch ext
                case '.holo'

                    try
                        obj.reader = HoloReader(obj.file.path);
                    catch ME
                        obj.file = []; obj.reader = [];
                        MEdisp(ME);
                        error('HoloDopplerClass:LoadFile:holoReadFailed', ...
                            "Couldn't read the holo file: %s", ME.message)
                    end

                    for f = properties(obj.reader)'
                        fn = f{1};

                        if ~strcmp(fn, 'filename')
                            obj.file.info.(fn) = obj.reader.(fn);
                        end

                    end

                    obj.file.Nx = obj.reader.frame_width;
                    obj.file.Ny = obj.reader.frame_height;

                    if obj.reader.version >= holo_versionThreshold
                        obj.file.lambda = obj.reader.footer.compute_settings.image_rendering.lambda;
                        obj.file.ppx = obj.reader.footer.info.pixel_pitch.x * 1e-6;
                        obj.file.ppy = obj.reader.footer.info.pixel_pitch.y * 1e-6;
                    else
                        fprintf("Old Holovibes version – using schema defaults for lambda/ppx/ppy.\n")
                        defs = HDParamSchema.getDefaults();
                        obj.file.lambda = defs.lambda_file_default;
                        obj.file.ppx = defs.ppx_file_default;
                        obj.file.ppy = defs.ppy_file_default;
                    end

                    try
                        obj.file.fs = obj.reader.footer.info.camera_fps / 1000;
                    catch

                        try
                            obj.file.fs = obj.reader.footer.info.input_fps / 1000;
                        catch
                            obj.file.fs = 1;
                            fprintf("No fps info found in holo file – defaulting fs to 1 kHz.\n")
                        end

                    end

                    obj.file.num_frames = double(obj.reader.num_frames);

                    try
                        obj.file.record_time_stamps_us.first = obj.reader.footer.info.timestamps_us.unix_first;
                        obj.file.record_time_stamps_us.last = obj.reader.footer.info.timestamps_us.unix_last;
                    catch
                        % ignore
                    end

                case '.cine'

                    try
                        obj.reader = CineReader(obj.file.path);
                    catch ME
                        obj.file = []; obj.reader = [];
                        MEdisp(ME);
                        error('HoloDopplerClass:LoadFile:cineReadFailed', ...
                            "The file is not a valid cine file: %s", ME.message)
                    end

                    for f = properties(obj.reader)'
                        fn = f{1};

                        if ~strcmp(fn, 'filename') && ~strcmp(fn, 'rephasing_data')
                            obj.file.info.(fn) = obj.reader.(fn);
                        end

                    end

                    obj.file.lambda = 852e-9;
                    obj.file.Nx = double(obj.reader.frame_width);
                    obj.file.Ny = double(obj.reader.frame_height);
                    obj.file.ppx = 1 / double(obj.reader.horizontal_pix_per_meter);
                    obj.file.ppy = 1 / double(obj.reader.vertical_pix_per_meter);
                    obj.file.fs = double(obj.reader.frame_rate) / 1000;
                    obj.file.num_frames = double(obj.reader.num_frames);

                otherwise
                    obj.file = []; obj.reader = [];
                    fprintf(2, "Unsupported file extension: %s\n", ext)
                    return
            end

            % ------------------------------------------------------------------
            % 2) Obtention des paramètres de rendu (UNIQUE SOURCE)
            % ------------------------------------------------------------------
            if isempty(opt.params)
                % Construire le struct fileInfo avec les métadonnées déjà lues
                fileInfo.Nx = obj.file.Nx;
                fileInfo.Ny = obj.file.Ny;
                fileInfo.num_frames = obj.file.num_frames;
                fileInfo.lambda = obj.file.lambda;
                fileInfo.ppx = obj.file.ppx;
                fileInfo.ppy = obj.file.ppy;
                fileInfo.fs = obj.file.fs;
                fileInfo.ext = ext;

                if isfield(obj.file, 'record_time_stamps_us')
                    % propagation distance peut être stockée dans le footer .holo
                    try
                        fileInfo.propagation_distance = obj.reader.footer.compute_settings.image_rendering.propagation_distance;
                    catch
                    end

                end

                obj.params = getFileParameters(file_path, fileInfo);
            else
                % Paramètres fournis de l'extérieur (ex: batch après getFileParameters)
                obj.params = HDParamSchema.validate(opt.params);
            end

        end

        % =====================================================================
        function setParams(obj, params)
            % Merge params into obj.params and validate the result.
            % Any field whose value is corrupt is silently replaced by the
            % schema default. Logs a warning per corrected field.
            %
            % File-bound fields (Nx, Ny, num_frames, fs, lambda, ppx, ppy) are
            % silently ignored here – they must be set through HD.file.

            if ~isstruct(params)
                warning('HoloDopplerClass:setParams:notAStruct', ...
                    'setParams called with non-struct input – ignoring.');
                return
            end

            fileBound = {'Nx', 'Ny', 'num_frames', 'fs', 'lambda', 'ppx', 'ppy'};

            % Merge incoming fields over current params.
            merged = obj.params;
            fields = fieldnames(params);

            for k = 1:numel(fields)

                if ~ismember(fields{k}, fileBound)
                    merged.(fields{k}) = params.(fields{k});
                end

            end

            % Validate the merged struct — corrupt fields fall back to defaults.
            obj.params = HDParamSchema.validate(merged);
        end

        % =====================================================================
        function loadParams(obj, path)
            % Load params from a JSON file and merge-validate into obj.params.
            fid = fopen(path, 'r');

            if fid == -1
                error('HoloDopplerClass:loadParams:cannotOpenFile', ...
                    'Cannot open file: %s', path);
            end

            closeFile = onCleanup(@() fclose(fid));

            raw = fread(fid, inf, '*char')';
            decoded = jsondecode(raw);

            if ~isstruct(decoded)
                warning('HoloDopplerClass:loadParams:notAStruct', ...
                    'Config file "%s" does not contain a JSON object – ignoring.', path);
                return
            end

            obj.setParams(decoded);
        end

        % =====================================================================
        function outputPath = saveParams(obj, filename, save_z)
            % Save rendering params as a JSON config file.
            % File-bound fields are never saved (they come from the file itself).

            if nargin < 2 || isempty(filename)
                name = obj.file.name;
                dir_ = obj.file.dir;
            else
                [dir_, name, ~] = fileparts(filename);
            end

            if nargin < 3
                save_z = true;
            end

            baseOutputDir = fullfile(dir_, name);

            if ~isfolder(baseOutputDir)
                mkdir(baseOutputDir);
            end

            parms = obj.params;

            % Strip file-bound fields that should never be persisted.
            stripFields = {'Nx', 'Ny', 'num_frames', 'fs', 'lambda', 'ppx', 'ppy', 'info'};

            for k = 1:numel(stripFields)

                if isfield(parms, stripFields{k})
                    parms = rmfield(parms, stripFields{k});
                end

            end

            % Optionally strip spatialPropagation so it is re-derived on load.
            if ~save_z && isfield(obj.file, 'record_time_stamps_us')

                if isfield(parms, 'spatialPropagation')
                    parms = rmfield(parms, 'spatialPropagation');
                end

            end

            outputPath = fullfile(baseOutputDir, ...
                sprintf('%s_input_HD_params.json', name));
            fid = fopen(outputPath, 'w');

            if fid == -1
                error('HoloDopplerClass:saveParams:cannotOpenFile', ...
                    'Cannot open file for writing: %s', outputPath);
            end

            closeFile = onCleanup(@() fclose(fid));
            fwrite(fid, jsonencode(parms, 'PrettyPrint', true), 'char');
        end

        function clearParams(obj)
            % CLEARPARAMS Delete per‑file JSON parameter files for the current file.

            if isempty(obj) || isempty(obj.file)
                warning('clearParams:noFile', 'No file loaded.');
                return;
            end

            filePath = obj.file.path;
            [fileDir, fileName, ~] = fileparts(filePath);
            baseOutputDir = fullfile(fileDir, fileName);

            % The two per‑file config paths (same logic as getFileParameters)
            configPaths = {
                fullfile(baseOutputDir, sprintf('%s_input_HD_params.json', fileName)), ...
                fullfile(baseOutputDir, sprintf('%s_HD', fileName), sprintf('%s_HD_input_HD_params.json', fileName))
                };

            existing = configPaths(cellfun(@isfile, configPaths));

            if isempty(existing)
                fprintf('No parameter files found to delete.\n');
                return;
            end

            for k = 1:numel(existing)
                delete(existing{k});
                fprintf('Deleted: %s\n', existing{k});
            end

        end

        % =====================================================================
        function images = PreviewRendering(obj)

            if isempty(obj.reader)
                error('HoloDopplerClass:PreviewRendering:noFile', ...
                    'No file loaded.');
            end

            p = obj.params;

            firstFrame = obj.reader.read_frame_batch(1, p.framePosition);

            framesNeedReload = isempty(obj.render.Frames) || ...
                size(obj.render.Frames, 3) ~= p.batchSize || ...
                ~isequal(obj.render.Frames(:, :, 1), single(firstFrame));

            if framesNeedReload
                frames = obj.reader.read_frame_batch( ...
                    p.batchSize, p.framePosition);

                obj.render.setFrames(frames);
            end

            renderParams = obj.buildRenderParams();

            obj.render.Render(renderParams, p.imageTypes);

            images = obj.render.getImages(p.imageTypes);

            % This resizing is display-only. It must never modify render.H,
            % render.SH, obj.video, or data sent to SaveVideo.
            for i = 1:numel(p.imageTypes)

                image = images{i};

                if isempty(image) || ismember(p.imageTypes{i}, {'broadening'})
                    continue
                end

                if size(image, 1) ~= size(image, 2)
                    maxDim = max(size(image, 1), size(image, 2));
                    images{i} = imresize(image, [maxDim, maxDim]);
                end

            end

        end

        % =====================================================================
        function images = showPreviewImages(obj, images_types)

            if nargin < 2
                images_types = obj.params.imageTypes;
            end

            images = obj.render.getImages(images_types);
            images_res = cell(1, length(images));

            for i = 1:length(images)
                maxDim = max(size(images{i}));

                if isnumeric(images{i}) && ~isempty(images{i})
                    images_res{i} = imresize(rescale(images{i}), [maxDim maxDim]);
                elseif isempty(images{i})
                    images_res{i} = zeros(maxDim);
                else
                    images_res{i} = imresize( ...
                        rescale(obj.render.Output.(images_types{i}).image), ...
                        [maxDim maxDim]);
                end

            end

            figure(18); montage(images_res);
        end

        % =====================================================================
        function savePreview(obj, imageTypes)

            if nargin < 2
                imageTypes = obj.params.imageTypes;
            end

            baseOutputDir = fullfile(obj.file.dir, obj.file.name);
            if ~isfolder(baseOutputDir), mkdir(baseOutputDir); end

            result_folder_path = fullfile(baseOutputDir, ...
                sprintf('%s_HDPreview', obj.file.name));
            if ~isfolder(result_folder_path), mkdir(result_folder_path); end

            images = obj.render.getImages(imageTypes);

            for i = 1:numel(images)
                if isempty(images{i}), continue; end

                if ~ismember(imageTypes{i}, ...
                        {'moment_0', 'moment_1', 'moment_2', 'SVD_cov', 'SVD_U', ...
                        'FH_modulus_mean', 'FH_arg_mean', 'broadening'})
                    max_dim = max(size(images{i}, 1), size(images{i}, 2));
                    imwrite(toImageSource(imresize(images{i}, [max_dim, max_dim])), ...
                        fullfile(result_folder_path, ...
                        strcat(obj.file.name, '_', imageTypes{i}, '.png')));
                else
                    imwrite(toImageSource(images{i}), ...
                        fullfile(result_folder_path, ...
                        strcat(obj.file.name, '_', imageTypes{i}, '.png')));
                end

            end

            % Save params snapshot alongside the preview.
            previewParamsPath = fullfile(result_folder_path, ...
                sprintf('%s_HDPreview_input_HD_params.json', obj.file.name));
            fid = fopen(previewParamsPath, 'w');

            if fid ~= -1
                closeFile = onCleanup(@() fclose(fid));
                fwrite(fid, jsonencode(obj.params, 'PrettyPrint', true), 'char');
            else
                warning('HoloDopplerClass:savePreview:cannotWrite', ...
                    'Could not write params to %s', previewParamsPath);
            end

        end

        % =====================================================================
        function result_folder_path = VideoRendering(obj)
            p = obj.params;

            if isempty(obj.reader)
                error('HoloDopplerClass:VideoRendering:noFile', 'No file loaded.');
            end

            if isempty(p.first_frame) || ~isfinite(p.first_frame) || p.first_frame < 1
                first_frame = 1;
            else
                first_frame = round(p.first_frame);
            end

            if isempty(p.end_frame) || p.end_frame <= 0 || ~isfinite(p.end_frame)
                end_frame = obj.file.num_frames;
            else
                end_frame = min(round(p.end_frame), obj.file.num_frames);
            end

            if first_frame > end_frame
                error('HoloDopplerClass:VideoRendering:invalidFrameRange', ...
                    'first_frame (%d) must not exceed end_frame (%d).', ...
                    first_frame, end_frame);
            end

            if p.batchSize < 1 || p.batchStride < 1
                error('HoloDopplerClass:VideoRendering:invalidBatchParameters', ...
                    'batchSize and batchStride must both be positive.');
            end

            availableFrames = end_frame - first_frame + 1;
            num_batches = floor((availableFrames - p.batchSize) / p.batchStride) + 1;

            if num_batches <= 0
                fprintf('No complete batch: %d frames available, batchSize=%d.\n', ...
                    availableFrames, p.batchSize);
                result_folder_path = '';
                return
            end

            lastFrameUsed = first_frame + (num_batches - 1) * p.batchStride + p.batchSize - 1;

            fprintf("==============================\n");
            fprintf("Starting Video Rendering\n");
            fprintf("File: %s\n", obj.file.path);
            fprintf("Requested frames: %d to %d\n", first_frame, end_frame);
            fprintf("Frames effectively read: %d to %d\n", first_frame, lastFrameUsed);
            fprintf("Batch size: %d | stride: %d | batches: %d\n", ...
                p.batchSize, p.batchStride, num_batches);
            fprintf("==============================\n");

            % Kernel is precomputed at the SAME padded size RenderingClass uses.
            kernel = generate_spatial_kernel(obj.file.Nx, obj.file.Ny, p.PaddingNum, ...
                p.spatialTransform, p.spatialPropagation, obj.file.lambda, ...
                obj.file.ppx, obj.file.ppy);

            if p.parforArg > 0
                cluster = parcluster;
                maxWorkers = cluster.NumWorkers;

                if p.parforArg > maxWorkers
                    warning('HoloDopplerClass:VideoRendering:maxWorkers', ...
                        'Using max workers %d instead of requested %d.', ...
                        maxWorkers, p.parforArg);
                    p.parforArg = maxWorkers;
                end

                if isempty(obj.poolManager)
                    obj.poolManager = ParallelPoolManager(p.parforArg);
                end

                obj.poolManager.acquire();
                cleanupPool = onCleanup(@() obj.poolManager.release());
                numWorkers = obj.poolManager.Pool.NumWorkers;
            else
                numWorkers = 0;
            end

            fprintf("Using %d worker(s).\n", numWorkers);

            h = waitbar(0, 'Initializing video rendering...');
            closeWaitbar = onCleanup(@() closeWaitbarSafe(h));

            progress = 0;
            WAITBAR_STEP = max(1, floor(num_batches / 100));

            function update_waitbar(increment)
                progress = progress + increment;

                if ~isgraphics(h)
                    return
                end

                if mod(progress, WAITBAR_STEP) == 0 || progress == num_batches
                    waitbar(progress / num_batches, h, ...
                        sprintf('Video rendering %d/%d (%d%%)', ...
                        progress, num_batches, ...
                        round(100 * progress / num_batches)));
                end

            end

            renderParams = obj.buildRenderParams();

            batchResults = cell(1, num_batches);
            tRendering = tic;

            reader = obj.reader;
            if numWorkers == 0

                for i = 1:num_batches
                    batchResults{i} = processBatchFromReader( ...
                        reader, i, first_frame, renderParams, kernel);

                    update_waitbar(1);
                end

            else

                cKernel = parallel.pool.Constant(kernel);
                D = parallel.pool.DataQueue;
                afterEach(D, @(~) update_waitbar(1));

                parfor (i = 1:num_batches, numWorkers)
                    batchResults{i} = processBatchFromReader( ...
                        reader, i, first_frame, renderParams, cKernel.Value);

                    send(D, 1);
                end

            end

            fprintf('Rendering took %.2f s\n', toc(tRendering));

            obj.video = ImageTypeList.empty(num_batches, 0);

            for b = 1:numel(batchResults)
                obj.video(b) = ImageTypeList();

                types = fieldnames(batchResults{b});

                for f = 1:numel(types)
                    type = types{f};
                    result = batchResults{b}.(type);

                    obj.video(b).(type).image = result.image;
                    obj.video(b).(type).parameters = result.parameters;
                    obj.video(b).(type).is_selected = true;
                end

            end

            if p.imageRegistration && any(strcmp(p.imageTypes, 'power_Doppler'))
                obj.CalculateRegistration();
                obj.ApplyRegistration();
            end

            result_folder_path = obj.SaveVideo();
        end

        % =====================================================================
        function [outImages] = processBatch(obj, batchIdx, first_frame, renderParams, kernel)
            frameIdx = first_frame + (batchIdx - 1) * renderParams.batchStride;
            frames = obj.reader.read_frame_batch(renderParams.batchSize, frameIdx);

            lr = RenderingClass('precomputeSpatialKernel', kernel);
            lr.setFrames(frames);
            lr.Render(renderParams, renderParams.imageTypes, ...
                'cache_intermediate_results', false);

            outImages = struct();

            for j = 1:numel(renderParams.imageTypes)
                type = renderParams.imageTypes{j};
                output = lr.Output.(type);

                outImages.(type) = struct( ...
                    'image', output.image, ...
                    'parameters', output.parameters);
            end

        end

        % =====================================================================
        function CalculateRegistration(obj)

            if isempty(obj.video)
                error('HoloDopplerClass:CalculateRegistration:noVideo', ...
                    'No video rendered')
            end

            num_batches = numel(obj.video);
            obj.registration = struct('shifts', [], 'rotation', [], 'scale', []);

            videoM0 = zeros(obj.file.Ny, obj.file.Nx, 1, num_batches);

            for i = 1:num_batches

                if ~isempty(obj.video(i).power_Doppler.image)
                    videoM0(:, :, 1, i) = obj.video(i).power_Doppler.image;
                end

            end

            numY = size(videoM0, 1);
            numX = size(videoM0, 2);

            if obj.params.registrationDiskRatio > 0
                disk = diskMask(numY, numX, obj.params.registrationDiskRatio);
                if size(disk, 1) ~= numY, disk = disk'; end
            else
                disk = ones([numY, numX]);
            end

            video_M0_reg = videoM0 .* disk - disk .* ...
                sum(videoM0 .* disk, [1, 2]) / nnz(disk);
            video_M0_reg = video_M0_reg ./ max(abs(video_M0_reg), [], [1, 2]);

            renderParams = obj.buildRenderParams();
            obj.render.setFrames(obj.reader.read_frame_batch( ...
                obj.params.refBatchSize, obj.params.framePosition));
            obj.render.Render(renderParams, obj.params.imageTypes);
            ref_img = obj.render.Output.power_Doppler.image;

            ref_img = ref_img .* disk - disk .* ...
                sum(ref_img .* disk, [1, 2]) / nnz(disk);
            ref_img = ref_img ./ max(abs(ref_img(:)));

            [~, obj.registration.shifts] = ...
                register_video_from_reference(video_M0_reg, ref_img);
        end

        % =====================================================================
        function result_folder_path = SaveVideo(obj, imageTypes, params)

            p = obj.params;

            if nargin < 2, imageTypes = p.imageTypes; end
            if nargin < 3, params = p; end

            VideoSavingTime = tic;
            disp('Saving video...');
            h = waitbar(0, 'Saving video...');
            N = max(double(numel(imageTypes)), 1);

            baseOutputDir = fullfile(obj.file.dir, obj.file.name);
            if ~isfolder(baseOutputDir), mkdir(baseOutputDir); end

            result_folder_path = fullfile(baseOutputDir, ...
                sprintf('%s_HD', obj.file.name));
            if ~isfolder(result_folder_path), mkdir(result_folder_path); end

            for sub = {'avi', 'h5', 'png', 'json'}
                subdir = fullfile(result_folder_path, sub{1});
                if ~isfolder(subdir), mkdir(subdir); end
            end

            generateParametersJson(params, obj.file, result_folder_path)

            config = getConfigs();
            [~, output_dirname] = fileparts(result_folder_path);
            output_filename_h5 = sprintf('%s_output.h5', output_dirname);
            h5path = fullfile(result_folder_path, 'h5', output_filename_h5);

            for i = 1:numel(imageTypes)
                tmp = {obj.video.(imageTypes{i})};
                waitbar((i - 1) / N, h, ...
                    sprintf("Saving %s", strrep(imageTypes{i}, '_', ' ')));

                if strcmp(imageTypes{i}, 'SH')
                    sz = size(tmp{1}.parameters.SH);
                    bs = sz(3);
                    sz(3) = bs * length(tmp);
                    mat = zeros(sz, 'single');

                    for j = 1:length(tmp)
                        mat(:, :, (j - 1) * bs + 1:j * bs) = tmp{j}.parameters.SH;
                    end

                    [~, output_dirname] = fileparts(result_folder_path);
                    output_filename_h5 = sprintf('%s_output.h5', output_dirname);
                    h5path = fullfile(result_folder_path, 'h5', output_filename_h5);

                    export_h5_video(h5path, "SH_power", single(mat));

                    axisConvention = ...
                        "SH_power(y_bin, x_bin, frequency_bin); " + ...
                        "spatial bins are non-overlapping block means; " + ...
                        "frequency_bin is the FFT bin within each batch";
                    export_h5_string(h5path, "SH_axis_convention", ...
                        axisConvention);

                    shMeta = tmp{1}.parameters;
                    export_h5_string(h5path, "SH_processing", jsonencode(struct( ...
                        'fs_kHz', obj.file.fs, ...
                        'batchSize', params.batchSize, ...
                        'batchStride', params.batchStride, ...
                        'spatialPropagation_m', params.spatialPropagation, ...
                        'spatialTransform', params.spatialTransform, ...
                        'SVD_enabled', params.svd_filter, ...
                        'SVD_threshold', params.svdThreshold, ...
                        'registration_enabled', params.imageRegistration, ...
                        'SH_spatial_binning', shMeta.spatial_binning, ...
                        'SH_original_size', shMeta.original_size, ...
                        'SH_binned_size', shMeta.binned_size, ...
                        'SH_crop_size', shMeta.crop_size, ...
                        'SH_spatial_reduction', shMeta.reduction)));

                    continue

                elseif strcmp(imageTypes{i}, 'buckets')
                    sz = size(tmp{1}.parameters.intervals_0);
                    sz(3) = length(tmp);
                    buckranges = reshape(params.bucketsRanges, [], 2);
                    numranges = size(buckranges, 1);
                    mat0 = zeros(sz, 'single');
                    mat1 = zeros(sz, 'single');
                    mat2 = zeros(sz, 'single');
                    mat_0 = zeros(sz, 'single');

                    for j = 1:length(tmp)

                        for k = 1:numranges
                            mat0 (:, :, j, k) = tmp{j}.parameters.intervals_0(:, :, :, k);
                            mat1 (:, :, j, k) = tmp{j}.parameters.intervals_1(:, :, :, k);
                            mat2 (:, :, j, k) = tmp{j}.parameters.intervals_2(:, :, :, k);
                            mat_0(:, :, j, k) = tmp{j}.parameters.M0(:, :, :, k);
                        end

                    end

                    export_h5_video(h5path, "bucket_intervals_0", single(mat0));
                    export_h5_video(h5path, "bucket_intervals_1", single(mat1));
                    export_h5_video(h5path, "bucket_intervals_2", single(mat2));
                    export_h5_video(h5path, "bucket_M0", single(mat_0));

                    continue

                elseif strcmp(imageTypes{i}, 'full_buckets')
                    sz = size(tmp{1}.parameters.SH_full);
                    numSl = sz(3);
                    sz(4) = length(tmp);
                    mat_ = zeros(sz, 'single');

                    for j = 1:length(tmp)

                        for k = 1:numSl
                            mat_(:, :, k, j) = tmp{j}.parameters.SH_full(:, :, k);
                        end

                    end

                    [~, output_dirname] = fileparts(result_folder_path);
                    output_filename_h5 = sprintf('%s_%s.h5', output_dirname, 'output');
                    export_h5_video( ...
                        fullfile(result_folder_path, 'h5', output_filename_h5), ...
                        "SH_Slices", single(mat_));
                    continue

                elseif strcmp(imageTypes{i}, 'SH_avg')
                    first = tmp{1}.parameters.SH;
                    mat = zeros(size(first, 1), size(first, 2), 1, length(tmp), 'single');

                    for j = 1:length(tmp)
                        mat(:, :, 1, j) = tmp{j}.parameters.SH;
                    end

                    export_h5_video(h5path, "SH_avg", mat);
                    continue

                else
                    sz = size(tmp{1}.image);
                    if length(sz) == 2, sz = [sz 1]; end
                    sz(end + 1) = length(tmp); %#ok<AGROW>
                    mat = zeros(sz, 'single');

                    for j = 1:length(tmp)

                        if ~isempty(tmp{j}.image)
                            mat(:, :, :, j) = tmp{j}.image;
                        end

                    end

                end

                if size(mat, 4) == 1
                    mat = repmat(mat, [1 1 1 2]);
                end

                if ~isempty(mat)
                    type = imageTypes{i};

                    if isfield(config, type)
                        cfg = config.(type);
                        nvPairs = namedargs2cell(cfg.opts);
                        generate_video(mat, result_folder_path, cfg.name, nvPairs{:});
                    else
                        generate_video(mat, result_folder_path, type, ...
                            'square', params.square);
                    end

                else
                    fprintf("%s was not found – skipping.\n", imageTypes{i});
                end

            end

            waitbar(1, h, 'Saving complete');
            close(h);

            % ---- Registration ------------------------------------------------
            if p.imageRegistration
                disp('Saving registration...');

                try
                    [~, output_dirname] = fileparts(result_folder_path);
                    output_filename_h5 = sprintf('%s_%s.h5', output_dirname, 'output');
                    export_h5_video( ...
                        fullfile(result_folder_path, 'h5', output_filename_h5), ...
                        "registration", single(obj.registration.shifts));
                catch ME
                    MEdisp(ME);
                    disp("Error while saving the registration.")
                end

            end

            % ---- Parameters --------------------------------------------------
            disp('Saving parameters...');

            try
                [~, output_dirname] = fileparts(result_folder_path);
                output_filename_h5 = sprintf('%s_%s.h5', output_dirname, 'output');
                export_h5_string( ...
                    fullfile(result_folder_path, 'h5', output_filename_h5), ...
                    "HD_parameters", jsonencode(params));
            catch ME
                MEdisp(ME);
                disp("Error while saving the parameters.")
            end

            videoParamsPath = fullfile(result_folder_path, ...
                sprintf('%s_HD_input_HD_params.json', obj.file.name));
            fid = fopen(videoParamsPath, 'w');

            if fid ~= -1
                closeFile2 = onCleanup(@() fclose(fid));
                fwrite(fid, jsonencode(params, 'PrettyPrint', true), 'char');
            else
                warning('HoloDopplerClass:SaveVideo:cannotOpenFile', ...
                    'Could not write params to %s', videoParamsPath);
            end

            % ---- Version / git -----------------------------------------------
            appRoot = fileparts(mfilename('fullpath'));
            copyfile(fullfile(appRoot, 'version.txt'), result_folder_path);

            try
                [~, git_hash] = system('git rev-parse HEAD');
                [~, git_branch] = system('git rev-parse --abbrev-ref HEAD');
                [~, git_log] = system('git log -1 --pretty=oneline');
                git_info = sprintf('Commit hash: %s\nBranch: %s\nLast commit: %s', ...
                    strtrim(git_hash), strtrim(git_branch), strtrim(git_log));
                fid_git = fopen(fullfile(result_folder_path, 'git.txt'), 'w');

                if fid_git ~= -1
                    closeGit = onCleanup(@() fclose(fid_git));
                    fwrite(fid_git, git_info, 'char');
                end

            catch ME
                MEdisp(ME);
                disp('No git info.');
            end

            fprintf("Video Saving took : %f s\n", toc(VideoSavingTime));
            fprintf("All done! Results saved in %s\n", result_folder_path);
        end

        % =====================================================================
        function ApplyRegistration(obj)
            num_batches = numel(obj.video);

            for j = 1:length(obj.params.imageTypes)

                itype = obj.params.imageTypes{j};

                if ismember(itype, {'broadening', 'fRMS', 'FH_modulus_mean', 'FH_arg_mean', 'SVD_cov', 'SVD_U'})
                    continue
                end

                pdImage = obj.video(1).('power_Doppler').image;

                if strcmp(itype, 'SH')
                    sz = size(obj.video(1).SH.parameters.SH);
                    bs = sz(3);
                    ratio = [sz(1) sz(2)] ./ size(pdImage);

                    for i = 1:num_batches

                        for m = 1:bs
                            obj.video(i).('SH').parameters.SH(:, :, m) = ...
                                circshift( ...
                                obj.video(i).('SH').parameters.SH(:, :, m), ...
                                floor(obj.registration.shifts(:, i) .* ratio'));
                        end

                    end

                    continue

                elseif strcmp(itype, 'buckets')
                    sz = size(obj.video(1).buckets.parameters.intervals_0);

                    if numel(sz) > 3
                        numF = sz(4);
                    else
                        numF = 1;
                    end

                    ratio = [sz(1) sz(2)] ./ size(pdImage);

                    for i = 1:num_batches

                        for k = 1:numF
                            shift = floor(obj.registration.shifts(:, i) .* ratio');
                            obj.video(i).('buckets').parameters.intervals_0(:, :, :, k) = ...
                                circshift(obj.video(i).('buckets').parameters.intervals_0(:, :, :, k), shift);
                            obj.video(i).('buckets').parameters.intervals_1(:, :, :, k) = ...
                                circshift(obj.video(i).('buckets').parameters.intervals_1(:, :, :, k), shift);
                            obj.video(i).('buckets').parameters.intervals_2(:, :, :, k) = ...
                                circshift(obj.video(i).('buckets').parameters.intervals_2(:, :, :, k), shift);
                            obj.video(i).('buckets').parameters.M0(:, :, :, k) = ...
                                circshift(obj.video(i).('buckets').parameters.M0(:, :, :, k), shift);
                        end

                    end

                    continue

                elseif strcmp(itype, 'full_buckets')
                    sz = size(obj.video(1).full_buckets.parameters.SH_full);
                    ratio = [sz(1) sz(2)] ./ size(pdImage);

                    for i = 1:num_batches

                        for k = 1:sz(3)
                            obj.video(i).('full_buckets').parameters.SH_full(:, :, k) = ...
                                circshift( ...
                                obj.video(i).('full_buckets').parameters.SH_full(:, :, k), ...
                                floor(obj.registration.shifts(:, i) .* ratio'));
                        end

                    end

                    continue
                end

                try
                    ratio = [size(obj.video(1).(itype).image, 1) ...
                        size(obj.video(1).(itype).image, 2)] ./ size(pdImage);
                catch
                    ratio = [1 1];
                end

                for i = 1:num_batches
                    obj.video(i).(itype).image = circshift( ...
                        obj.video(i).(itype).image, ...
                        floor(obj.registration.shifts(:, i) .* ratio'));
                end

            end

        end

    end % public methods

    % =========================================================================
    methods (Access = private)

        function rp = buildRenderParams(obj)
            % Merge rendering params with the file-bound metadata that
            % RenderingClass needs (lambda, ppx, ppy, fs, Nx, Ny).
            % This is the ONE place where HD.file values are injected into a
            % params struct passed to the renderer — they are never stored
            % back into HD.params.
            rp = obj.params;
            rp.lambda = obj.file.lambda;
            rp.ppx = obj.file.ppx;
            rp.ppy = obj.file.ppy;
            rp.fs = obj.file.fs;
            rp.Nx = obj.file.Nx;
            rp.Ny = obj.file.Ny;
            rp.num_frames = obj.file.num_frames;
        end

    end % private methods

end % classdef

% =========================================================================
% Module-level helpers
% =========================================================================

function spatialKernel = generate_spatial_kernel( ...
    Nx, Ny, paddingNum, transformation, z, lambda, ppx, ppy)
% GENERATE_SPATIAL_KERNEL Precompute a kernel consistent with RenderingClass.
%
% Input frame convention: Frames(Nx, Ny, Nt).
% PaddingNum is interpreted as a minimum size PER AXIS (not a forced
% square domain):
%   NxP = max(Nx, PaddingNum)
%   NyP = max(Ny, PaddingNum)

transform = lower(strtrim(string(transformation)));

if isempty(paddingNum) || ~isfinite(paddingNum)
    paddingNum = 0;
end

paddingNum = round(double(paddingNum));

if paddingNum < 0
    error('HoloDopplerClass:generateSpatialKernel:invalidPadding', ...
        'PaddingNum must be non-negative.');
end

NxP = max(double(Nx), paddingNum);
NyP = max(double(Ny), paddingNum);

switch transform
    case "angular spectrum"
        spatialKernel = propagation_kernelAngularSpectrum( ...
            NxP, NyP, z, lambda, ppx, ppy, false);

    case "fresnel"
        % Historical Fresnel kernel API order: Ny then Nx.
        [spatialKernel, ~] = propagation_kernelFresnel( ...
            NyP, NxP, z, lambda, ppx, ppy, false);

    case {"none", "twin image removal"}
        spatialKernel = single.empty;

    otherwise
        error('HoloDopplerClass:generateSpatialKernel:unknownTransform', ...
            'Unknown spatial transformation "%s".', string(transformation));
end

spatialKernel = single(spatialKernel);
end

function shift = scaledShift(baseShift, dataSize, referenceSize)
% SCALEDSHIFT Rescale a [row; col] shift computed at power_Doppler
% resolution to the spatial resolution of another array (e.g. SH bins,
% buckets, or a smaller/larger export).

if numel(dataSize) < 2 || numel(referenceSize) < 2
    error('HoloDopplerClass:scaledShift:invalidSize', ...
        'Both sizes must have at least two spatial dimensions.');
end

ratio = double(dataSize(1:2)) ./ double(referenceSize(1:2));
shift = round(double(baseShift(:)) .* ratio(:));
end

function out = translateNoWrap(in, shift)
% TRANSLATENOWRAP Integer translation with zero-filled exposed borders.
%
% Unlike circshift, no pixel wraps around to the opposite border.
% shift is [shiftRow shiftCol] in MATLAB matrix coordinates.

shift = round(double(shift(:)'));

if numel(shift) ~= 2
    error('HoloDopplerClass:translateNoWrap:invalidShift', ...
        'Shift must contain exactly [row col].');
end

shiftY = shift(1);
shiftX = shift(2);

numY = size(in, 1);
numX = size(in, 2);

out = zeros(size(in), 'like', in);

srcY = max(1, 1 - shiftY):min(numY, numY - shiftY);
srcX = max(1, 1 - shiftX):min(numX, numX - shiftX);

if isempty(srcY) || isempty(srcX)
    return
end

dstY = srcY + shiftY;
dstX = srcX + shiftX;

index = repmat({':'}, 1, ndims(in));

sourceIndex = index;
sourceIndex{1} = srcY;
sourceIndex{2} = srcX;

destinationIndex = index;
destinationIndex{1} = dstY;
destinationIndex{2} = dstX;

out(destinationIndex{:}) = in(sourceIndex{:});
end

function closeWaitbarSafe(h)

if ~isempty(h) && isgraphics(h)
    close(h);
end

end

function [config, defaultUnknown] = getConfigs()
config = struct();
defaultOpts = struct('temporalFilter', [], 'square', true, 'export_raw', true, ...
    'substractFlash', true, 'enhance_contrast', true, ...
    'contrast_inversion', false, 'cornerNorm', false, 'export_avg_img', true);

config.moment_0 = struct('name', 'moment0', 'opts', defaultOpts);
config.moment_1 = struct('name', 'moment1', 'opts', defaultOpts);
config.moment_2 = struct('name', 'moment2', 'opts', defaultOpts);
config.LF_M0 = struct('name', 'LF_M0', 'opts', defaultOpts);
config.HF_M0 = struct('name', 'HF_M0', 'opts', defaultOpts);

opts_pd = defaultOpts;
opts_pd.export_raw = false;
config.power_Doppler = struct('name', 'M0', 'opts', opts_pd);
config.band_ratio = struct('name', 'band_ratio', 'opts', opts_pd);

simpleOpts = struct('temporalFilter', [], 'square', false, 'export_raw', false, ... % no square no raw
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
config.color_band_ratio = struct('name', 'color_band_ratio', ...
    'opts', struct('substractFlash', false, 'square', true, 'enhance_contrast', false));

defaultUnknown = struct('temporalFilter', 2, 'square', true);
end

function outImages = processBatchFromReader( ...
                reader, batchIdx, first_frame, renderParams, kernel)

            frameIdx = first_frame + ...
                (batchIdx - 1) * renderParams.batchStride;

            frames = reader.read_frame_batch( ...
                renderParams.batchSize, frameIdx);

            lr = RenderingClass('precomputeSpatialKernel', kernel);
            lr.setFrames(frames);

            lr.Render(renderParams, renderParams.imageTypes, ...
                'cache_intermediate_results', false);

            outImages = struct();

            for j = 1:numel(renderParams.imageTypes)
                type = renderParams.imageTypes{j};
                output = lr.Output.(type);

                outImages.(type) = struct( ...
                    'image', output.image, ...
                    'parameters', output.parameters);
            end

        end