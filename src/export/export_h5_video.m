function export_h5_video(filename, name, video)
dataset_path = sprintf('/%s', name);

% Default: assume we need to create the dataset
create_needed = true;

if isfile(filename)
    info = h5info(filename);
    dataset_idx = find(strcmp({info.Datasets.Name}, name), 1);

    if ~isempty(dataset_idx)
        % Dataset exists – check its size (and optionally datatype)
        existing_size = info.Datasets(dataset_idx).Dataspace.Size;

        if isequal(existing_size, size(video))
            create_needed = false;
        else
            % Size mismatch: delete the old dataset
            % Low-level HDF5 deletion (works on all MATLAB versions with HDF5 support)
            file_id = H5F.open(filename, 'H5F_ACC_RDWR', 'H5P_DEFAULT'); % open file for read/write
            H5L.delete(file_id, dataset_path, 'H5P_DEFAULT'); % delete the link (= dataset)
            H5F.close(file_id); % close the file
        end

    end

end

if create_needed
    % Create a fresh dataset with the required dimensions
    h5create(filename, dataset_path, size(video), 'Datatype', 'single');
end

% Write the data
h5write(filename, dataset_path, video);
end
