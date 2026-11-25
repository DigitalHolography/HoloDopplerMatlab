function generate_video(video, output_path, name, opt)

arguments
    video
    output_path
    name
    opt.temporalFilter = []
    opt.contrast_inversion = false
    opt.substractFlash = true
    opt.cornerNorm = false
    opt.export_raw = false
    opt.export_avg_img = true
    opt.enhance_contrast = false
    opt.square = false
end

[~, output_dirname] = fileparts(output_path);
output_filename = sprintf('%s_%s.%s', output_dirname, name, 'avi');

% If grayscale, ensure it's 3D+time
if size(video, 3) == 1
    video = reshape(video, size(video, 1), size(video, 2), 1, []);
end

% Optional square resizing (applies to raw export as well)
if opt.square
    sdim = max(size(video, 1), size(video, 2));
    video = imresize(video, [sdim, sdim]);
end

% --- Export raw data (before any intensity processing) ---
if opt.export_raw
    h5_dir = fullfile(output_path, 'h5');
    if ~exist(h5_dir, 'dir'), mkdir(h5_dir); end
    % Fixed: use 'name' instead of hardcoded 'output'
    output_filename_h5 = sprintf('%s_output.h5', output_dirname);
    export_h5_video(fullfile(h5_dir, output_filename_h5), name, single(video));

    output_filename_raw = sprintf('%s_%s_raw.%s', output_dirname, name, 'avi');
    w_raw = VideoWriter(fullfile(h5_dir, output_filename_raw));
    w_raw.Quality = 50;
    open(w_raw);

    for i = 1:size(video, 4)
        writeVideo(w_raw, mat2gray(video(:, :, :, i)));
    end

    close(w_raw);
end

% --- Temporal filter ---
if ~isempty(opt.temporalFilter)
    sigma_t = opt.temporalFilter;

    for c = 1:size(video, 3)
        video(:, :, c, :) = imgaussfilt(squeeze(video(:, :, c, :)), sigma_t, ...
            'FilterDomain', 'spatial');
    end

end

% --- Flash subtraction ---
if opt.substractFlash
    video(~isfinite(video)) = NaN;

    frameMean = mean(video, [1 2], 'omitnan');
    frameMean(~isfinite(frameMean)) = 0;

    video = video - frameMean;
end

% --- Corner normalisation ---
if opt.cornerNorm
    [numX, numY, ~] = size(video);
    disk_ratio = opt.cornerNorm;
    disk = diskMask(numX, numY, disk_ratio);
    video = video ./ mean(video .* ~disk, [1, 2]);
end

% --- Contrast inversion ---
if opt.contrast_inversion
    video = -1.0 * video;
end

% --- Normalize finite values only ---
valid = isfinite(video);

if opt.enhance_contrast

    for f = 1:size(video, 4)
        frame = video(:, :, :, f);
        frameValid = valid(:, :, :, f);
        values = frame(frameValid);
        out = zeros(size(frame), 'like', frame);

        if ~isempty(values)
            lo = min(values);
            hi = max(values);

            if hi > lo
                samples = double((values - lo) ./ (hi - lo));
                limits = stretchlim(samples(:), [0.0001 0.9999]);
                limits = limits(:, 1);

                if limits(2) > limits(1)
                    span = hi - lo;
                    hi = lo + limits(2) * span;
                    lo = lo + limits(1) * span;
                end

                out(frameValid) = (values - lo) ./ (hi - lo);
            end

        end

        out = min(max(out, 0), 1);
        out(~frameValid) = 0;
        video(:, :, :, f) = out;
    end

else
    % One common scale for the entire video.
    values = video(valid);
    out = zeros(size(video), 'like', video);

    if ~isempty(values)
        lo = min(values);
        hi = max(values);

        if hi > lo
            out(valid) = (values - lo) ./ (hi - lo);
        end

    end

    video = min(max(out, 0), 1);
end

video(~valid) = 0;

% Write final video
avi_dir = fullfile(output_path, 'avi');
if ~exist(avi_dir, 'dir'), mkdir(avi_dir); end
w = VideoWriter(fullfile(avi_dir, output_filename));
open(w);

for i = 1:size(video, 4)
    writeVideo(w, video(:, :, :, i));
end

close(w);

% --- Save temporal average and standard deviation images ---
if opt.export_avg_img
    generate_image(video, output_path, name);
end

end
