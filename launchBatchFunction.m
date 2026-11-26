function launchBatchFunction(listFile, paramFile)
% launchBatchFunction Processes a batch of holofiles with optional parameter file
%   listFile  : path to .txt file containing holofile paths
%   paramFile : path to parameter .json file (optional). If empty, uses default

fprintf("=== HOLOPROCESS START ===\n");

appRoot = fileparts(mfilename('fullpath'));
addpath(appRoot, genpath(fullfile(appRoot, 'src')));
defaultConfigFile = fullfile(appRoot, 'src', 'configs', 'CurrentDefault.txt');
version_tag = readlines(fullfile(appRoot, "version.txt"));
fprintf("HoloDoppler version : %s\n", version_tag);

% Load list of holofiles
if nargin < 1 || isempty(listFile)
    fprintf('Select input list (.txt) containing file paths\n');
    [txt_name, txt_path] = uigetfile('*.txt', 'Select input list (.txt) containing file paths');

    if isequal(txt_name, 0)
        error("No input .txt file selected. Exiting process.");
    end

    listFile = fullfile(txt_path, txt_name);
end

try
    paths = strtrim(readlines(listFile));
    paths = paths(paths ~= ""); % remove empty lines
catch ME
    error("Error reading the input .txt file: %s", ME.message);
end

if isempty(paths)
    error("The input list is empty. Please provide a valid list of holofiles.");
end

fprintf("Loaded %d paths from input list.\n", numel(paths));

% Determine parameter file
paramspath = [];

% Use provided paramFile if given
if nargin >= 2 && ~isempty(paramFile)

    if ~isfile(paramFile)
        error("Provided parameter file does not exist: %s", paramFile);
    end

    paramspath = paramFile;
    fprintf("Using provided parameter file: %s\n", paramspath);
else
    % Load default config if available
    if isfile(defaultConfigFile)
        DefConfName = strtrim(readlines(defaultConfigFile));

        if ~isempty(DefConfName)
            defaultParamPath = fullfile("StandardConfigs", sprintf("%s.json", DefConfName(1)));

            if isfile(defaultParamPath)
                paramspath = defaultParamPath;
                fprintf("Default parameter file found: %s\n", paramspath);
            else
                fprintf("Default parameter JSON not found: %s\n", defaultParamPath);
            end

        end

    end

    % Allow user to override
    if isempty(paramspath)
        fprintf('Select parameter file (.json) or Cancel to use default\n');
        [json_name, json_path] = uigetfile('*.json', 'Select parameter file (.json) or Cancel to use default');

        if ~isequal(json_name, 0)
            paramspath = fullfile(json_path, json_name);
            fprintf("Using user-selected parameter file: %s\n", paramspath);
        elseif isempty(paramspath)
            error("No parameter file selected and no default available.");
        end

    end

end

% Launch HoloDoppler processing
HD = HoloDopplerClass;

fprintf("\n=== STARTING HOLOFILE PROCESSING ===\n");

for ind = 1:numel(paths)
    currentPath = strtrim(paths(ind));

    if ~isfile(currentPath)
        fprintf("Skipping missing file: %s\n", currentPath);
        continue;
    end

    fprintf("Processing file %d of %d: %s\n", ind, numel(paths), currentPath);

    try
        HD.LoadFile(currentPath); % Load holo file
        HD.loadParams(paramspath); % Load parameter settings
        HD.VideoRendering(); % Render the video
    catch ME
        fprintf("Error processing %s: %s\n", currentPath, ME.message);
    end

end

fprintf("\n=== PROCESSING COMPLETE ===\n");

end
