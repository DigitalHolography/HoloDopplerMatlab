function export_h5_string(filename, name, str)
% Exports a string to an HDF5 file. If the dataset already exists, it will be overwritten.
% Parameters:
%   filename: The name of the HDF5 file to write to.
%   name: The name of the dataset to create or overwrite.
%   str: The string to write to the dataset.

dataset_path = sprintf('/%s', name);

str = string(str); % ensure string type

if isfile(filename)
    info = h5info(filename);
    dataset_exists = any(strcmp({info.Datasets.Name}, name));
else
    dataset_exists = false;
end

if ~dataset_exists
    h5create(filename, dataset_path, size(str), 'Datatype', 'string');
end

h5write(filename, dataset_path, str);
end
