function video_avg = generate_image(video, output_path, name)

% Destination.
png_dir = fullfile(output_path, 'png');

if ~isfolder(png_dir)
    [ok, msg] = mkdir(png_dir);

    if ~ok
        error('HoloDoppler:generate_image:CreateDirectoryFailed', ...
            'Cannot create directory "%s": %s', png_dir, msg);
    end

end

[~, folder_name] = fileparts(output_path);

% Average first
output_file = fullfile(png_dir, ...
    sprintf('%s_%s.png', folder_name, name));

if isfile(output_file)
    delete(output_file)
end

video_avg = double(mean(video, 4));

fprintf('Saving PNG: %s\n', output_file);
imwrite(rescale(video_avg), output_file);

% STD second
output_file = fullfile(png_dir, ...
    sprintf('%s_%s_std.png', folder_name, name));

if isfile(output_file)
    delete(output_file)
end

video_std = double(std(video, 0, 4));

fprintf('Saving STD PNG: %s\n', output_file);
imwrite(rescale(video_std), output_file);

end
