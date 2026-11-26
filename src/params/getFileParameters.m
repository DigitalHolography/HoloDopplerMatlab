function params = getFileParameters(filePath, fileInfo)
% GETFILEPARAMETERS Load rendering parameters (full cascade).
%
%   PARAMS = GETFILEPARAMETERS(FILEPATH)
%   PARAMS = GETFILEPARAMETERS(FILEPATH, FILEINFO)
%
%   FILEINFO is a struct containing metadata already read:
%       Nx, Ny, num_frames, lambda, ppx, ppy, fs,
%       propagation_distance (optional), ext (extension)
%   If absent, the function reads the file itself.

if nargin < 2
    fileInfo = [];
end

appRoot = fileparts(mfilename('fullpath'));
[fileDir, fileName, ext] = fileparts(filePath);
holo_versionThreshold = 5;

% ----- 1) Metadata -----
if isempty(fileInfo)

    switch lower(ext)
        case '.holo'
            reader = HoloReader(filePath);
            fileInfo.Nx = reader.frame_width;
            fileInfo.Ny = reader.frame_height;
            fileInfo.num_frames = double(reader.num_frames);

            if reader.version >= holo_versionThreshold
                fileInfo.lambda = reader.footer.compute_settings.image_rendering.lambda;
                fileInfo.ppx = reader.footer.info.pixel_pitch.x * 1e-6;
                fileInfo.ppy = reader.footer.info.pixel_pitch.y * 1e-6;
            else
                defs = HDParamSchema.getDefaults();
                fileInfo.lambda = defs.lambda_file_default;
                fileInfo.ppx = defs.ppx_file_default;
                fileInfo.ppy = defs.ppy_file_default;
            end

            try
                fileInfo.fs = reader.footer.info.camera_fps / 1000;
            catch

                try
                    fileInfo.fs = reader.footer.info.input_fps / 1000;
                catch
                    fileInfo.fs = 1;
                end

            end

            if reader.version >= holo_versionThreshold
                fileInfo.propagation_distance = reader.footer.compute_settings.image_rendering.propagation_distance;
            end

            clear reader

        case '.cine'
            reader = CineReader(filePath);
            fileInfo.Nx = double(reader.frame_width);
            fileInfo.Ny = double(reader.frame_height);
            fileInfo.num_frames = double(reader.num_frames);
            fileInfo.lambda = 852e-9;
            fileInfo.ppx = 1 / double(reader.horizontal_pix_per_meter);
            fileInfo.ppy = 1 / double(reader.vertical_pix_per_meter);
            fileInfo.fs = double(reader.frame_rate) / 1000;
            clear reader

        otherwise
            error('Unsupported extension: %s', ext);
    end

    fileInfo.ext = ext;
end

% ----- 2) Schema defaults -----
params = HDParamSchema.getDefaults();
params.lambda = fileInfo.lambda;
params.ppx = fileInfo.ppx;
params.ppy = fileInfo.ppy;
params.fs = fileInfo.fs;
params.Nx = fileInfo.Nx;
params.Ny = fileInfo.Ny;
params.num_frames = fileInfo.num_frames;

switch fileInfo.ext
    case '.holo'
        params.spatialTransform = 'Fresnel';

        if isfield(fileInfo, 'propagation_distance')
            params.spatialPropagation = fileInfo.propagation_distance;
        end

    case '.cine'
        params.spatialTransform = 'Fresnel';
        params.spatialPropagation = 1.13;
end

% ----- 3) Global standard configuration -----
stdConfigFile = fullfile(appRoot, 'StandardConfigs', 'CurrentDefault.txt');

if isfile(stdConfigFile)
    DefConfName = strtrim(readlines(stdConfigFile));

    if ~isempty(DefConfName) && strlength(DefConfName(1)) > 0
        configPath = fullfile(appRoot, 'StandardConfigs', sprintf('%s.json', DefConfName(1)));

        if isfile(configPath)
            params = mergeConfig(params, configPath);
        end

    end

end

% ----- 4) Configurations sauvegardées pour ce fichier -----
baseOutputDir = fullfile(fileDir, fileName);
perFileConfigs = {
                  fullfile(baseOutputDir, sprintf('%s_input_HD_params.json', fileName)), ...
                      fullfile(baseOutputDir, sprintf('%s_HD', fileName), sprintf('%s_HD_input_HD_params.json', fileName))
                  };

for k = 1:numel(perFileConfigs)

    if isfile(perFileConfigs{k})
        params = mergeConfig(params, perFileConfigs{k});
    end

end

% ----- 5) Validation -----
params = HDParamSchema.validate(params);
end

% ----- Helper function -----
function params = mergeConfig(params, jsonPath)
fid = fopen(jsonPath, 'r');
if fid == -1, return; end
closeObj = onCleanup(@() fclose(fid));
raw = fread(fid, inf, '*char')';
decoded = jsondecode(raw);
if ~isstruct(decoded), return; end
fileBound = {'Nx', 'Ny', 'num_frames', 'fs', 'lambda', 'ppx', 'ppy'};
fields = fieldnames(decoded);

for i = 1:numel(fields)

    if ~ismember(fields{i}, fileBound)
        params.(fields{i}) = decoded.(fields{i});
    end

end

end
