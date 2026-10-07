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
output_file = fullfile(png_dir, ...
    sprintf('%s_%s.png', folder_name, name));

% Average first, then interpolate each channel once.
avg = double(mean(video, 4));

video_avg = zeros( ...
    2 * size(avg, 1) - 1, ...
    2 * size(avg, 2) - 1, ...
    size(avg, 3));

for channel = 1:size(avg, 3)
    video_avg(:, :, channel) = interp2(avg(:, :, channel), 1);
end

video_avg = mat2gray(video_avg);

fprintf('Saving PNG: %s\n', output_file);
imwrite(video_avg, output_file);

end