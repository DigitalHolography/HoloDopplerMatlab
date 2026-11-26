function holodopplercli(varargin)
% Initialize Application
appRoot = fileparts(mfilename('fullpath'));
addpath(appRoot, genpath(fullfile(appRoot, 'src')));
defaultConfigFile = fullfile(appRoot, 'src', 'configs', 'CurrentDefault.txt');
% et fullfile(appRoot, 'src', 'configs', sprintf('%s.json', DefConfName(1)))

fprintf("Application root is %s\n", appRoot);

if isfile(versionFile)
    version_tag = readlines(versionFile);
    fprintf("HoloDoppler version : %s\n", version_tag);
else
    fprintf("HoloDoppler version : Unknown (version.txt not found)\n");
end

% --- ARGUMENT PARSING ---
mode = 'single';
inputPath = "";
paramspath = "";

idx = 1;

while idx <= nargin
    arg = string(varargin{idx});

    switch arg
        case "-batch"
            mode = 'batch';
        case "-b"
            mode = 'batch';
        case "-config"
            % Check if next argument exists and isn't another flag
            if idx < nargin && ~startsWith(string(varargin{idx + 1}), "-")
                paramspath = string(varargin{idx + 1});
                idx = idx + 1; % Skip next arg as it was the path
            else
                % Open file explorer for config if flag present but no path provided
                [json_name, json_path] = uigetfile('*.json', 'Select parameter file (.json)');

                if ~isequal(json_name, 0)
                    paramspath = fullfile(json_path, json_name);
                end

            end

        otherwise
            % Assume this is the input path (holo file or batch list)
            inputPath = arg;
    end

    idx = idx + 1;
end

% --- PATH SELECTION ---
try

    if strcmp(mode, 'batch')
        % Batch Mode: Expecting a .txt file list
        if inputPath == ""
            [txt_name, txt_path] = uigetfile('*.txt', 'Select the input list (.txt) of holofiles');
            if isequal(txt_name, 0); return; end
            fullInputPath = fullfile(txt_path, txt_name);
        else
            fullInputPath = strrep(inputPath, '"', '');

            if ~isfile(fullInputPath)
                error("Batch file not found: %s", fullInputPath);
            end

        end

        fprintf("Running in Batch Mode: %s\n", fullInputPath);
        paths = strtrim(readlines(fullInputPath));
        paths = paths(paths ~= ""); % remove empty lines

    else
        % Single Mode: Expecting a .holo file
        if inputPath == ""
            [holo_name, holo_path] = uigetfile('*.holo', 'Select the .holo file');
            if isequal(holo_name, 0); return; end
            fullInputPath = fullfile(holo_path, holo_name);
        else
            fullInputPath = inputPath;
        end

        fprintf("Running in Single Mode: %s\n", fullInputPath);
        paths = string(fullInputPath);
    end

catch ME
    fprintf("Error during path selection: %s\n", ME.message);
    return;
end

if isempty(paths)
    fprintf("No valid paths to process. Exiting.\n");
    return;
end

% --- PARAMETER SELECTION ---

% 1. Check if paramspath was provided via CLI (-config)
if paramspath ~= ""

    if ~isfile(paramspath)
        fprintf("[WARNING] Custom parameter file not found: %s\n", paramspath);
        paramspath = ""; % Reset to force fallback
    else
        fprintf("Using Custom Parameter file: %s\n", paramspath);
    end

end

% 2. Check for default config definition (if no custom provided)
if paramspath == ""

    if isfile(defaultConfigFile)
        DefConfName = strtrim(readlines(defaultConfigFile));

        if ~isempty(DefConfName)
            defaultParamPath = fullfile(appRoot, "StandardConfigs", sprintf("%s.json", DefConfName(1)));

            if isfile(defaultParamPath)
                paramspath = defaultParamPath;
                fprintf("Using Default Parameter file: %s\n", paramspath);
            end

        end

    end

end

% 3. If still empty, ask user
if paramspath == ""
    fprintf('Select parameter file (.json)\n');
    [json_name, json_path] = uigetfile('*.json', 'Select parameter file (.json)');

    if ~isequal(json_name, 0)
        paramspath = fullfile(json_path, json_name);
        fprintf("Using User-Selected Parameter file: %s\n", paramspath);
    else
        error("No parameter file selected. Exiting.");
    end

end

% --- EXECUTION LOOP ---
fprintf("Initializing HoloDoppler Engine...\n");
HD = HoloDopplerClass;

for ind = 1:length(paths)
    currentPath = paths(ind);

    if currentPath == "" || ismissing(currentPath); continue; end

    if ~isfile(currentPath)
        fprintf("  [WARNING] File not found: %s\n", currentPath);
        continue;
    end

    fprintf("Processing (%d/%d): %s\n", ind, length(paths), currentPath);

    try
        HD.LoadFile(currentPath); % Load holo file
        HD.loadParams(paramspath); % Load parameter settings
        HD.VideoRendering(); % Render the video
    catch ME
        fprintf("  [ERROR] Processing failed for %s\n  %s\n", currentPath, ME.message);
    end

end

fprintf("All tasks completed.\n");
end
