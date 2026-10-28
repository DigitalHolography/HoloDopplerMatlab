function generateParametersJson(params, fileinfo, result_folder_path)

% Ensure the result folder exists
if ~exist(result_folder_path, 'dir')
    mkdir(result_folder_path);
end

% Update the parameters to match DopplerView requirements
params.batch_stride = params.batchStride; % Rename batchStride to batch_stride
params.batch_size = params.batchSize; % Rename batchSize to batch_size

% File info parameters
params.sampling_freq = fileinfo.fs * 1000; % Convert sampling frequency from kHz to Hz
params.num_frames = fileinfo.num_frames; % Add num_frames from fileinfo
params.name = fileinfo.name; % Add name from fileinfo
params.duration_sec = fileinfo.num_frames / (fileinfo.fs * 1000); % Calculate duration in seconds
params.ppx = fileinfo.ppx; % Add ppx from fileinfo
params.ppy = fileinfo.ppy; % Add ppy from fileinfo
params.lambda = fileinfo.lambda; % Add lambda from fileinfo
params.path = fileinfo.path; % Add path from fileinfo
params.dir = fileinfo.dir; % Add dir from fileinfo
params.extension = fileinfo.ext; % Add extension from fileinfo
% Recording timestamps are optional (e.g. for .cine input).
if isfield(fileinfo, 'record_time_stamps_us') && ...
        ~isempty(fileinfo.record_time_stamps_us)
    params.record_time_stamps_us = fileinfo.record_time_stamps_us;
elseif isfield(params, 'record_time_stamps_us')
    params = rmfield(params, 'record_time_stamps_us');
end

% --- JSON parameters folder -----------------------------------------
jsonDir = fullfile(result_folder_path, 'json');
jsonFilePath = fullfile(jsonDir, 'parameters.json');
fidJson = fopen(jsonFilePath, 'w');

if fidJson ~= -1 % Check if the file was opened successfully
    fwrite(fidJson, jsonencode(params, 'PrettyPrint', true), 'char');
    fclose(fidJson);
else
    warning('HoloDopplerClass:SaveVideo:cannotWriteJson', ...
        'Could not write parameters.json to %s', jsonFilePath);
end

end
