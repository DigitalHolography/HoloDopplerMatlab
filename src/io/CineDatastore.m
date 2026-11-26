classdef CineDatastore < matlab.io.Datastore & ...
    matlab.io.datastore.MiniBatchable

properties
    Filename
    NumFrames
    FrameWidth
    FrameHeight
    TrueWidth
    TrueHeight
    BitsPerPixel
    Compression
    BICompression
    ImageOffsets
    FrameRate
    IsPacked
end

properties (Access = private)
    CurrentFrame = 1
    MiniBatchSize = 1
end

methods

    function ds = CineDatastore(filename)
        ds.Filename = filename;
        ds.parseHeader();
    end

    function tf = hasdata(ds)
        tf = ds.CurrentFrame <= ds.NumFrames;
    end

    function [data, info] = read(ds)
        n = min(ds.MiniBatchSize, ...
            ds.NumFrames - ds.CurrentFrame + 1);

        data = ds.readFrames(ds.CurrentFrame, n);
        info.FrameIndices = ds.CurrentFrame:ds.CurrentFrame + n - 1;

        ds.CurrentFrame = ds.CurrentFrame + n;
    end

    function reset(ds)
        ds.CurrentFrame = 1;
    end

    function dsNew = partition(ds, ~, ~)
        dsNew = copy(ds);
    end

    function setMiniBatchSize(ds, n)
        ds.MiniBatchSize = n;
    end

end

% MiniBatchable interface
methods

    function tf = supportsMiniBatching(~)
        tf = true;
    end

    function tf = supportsTall(~)
        tf = true;
    end

end

% Internal logic
methods (Access = private)

    function parseHeader(ds)
        h = memmapfile(ds.Filename, 'Format', ...
            {'uint16', 1, 'type'; ...
             'uint16', 1, 'header_size'; ...
             'uint16', 1, 'compression'; ...
             'uint16', 1, 'version'; ...
             'int32', 1, 'first_movie_image'; ...
             'uint32', 1, 'total_image_count'; ...
             'int32', 1, 'first_image_no'; ...
             'uint32', 1, 'image_count'; ...
             'uint32', 1, 'off_image_header'; ...
             'uint32', 1, 'off_setup'; ...
             'uint32', 1, 'off_image_offsets'}, ...
            'Repeat', 1);

        ds.NumFrames = h.Data.image_count;
        ds.Compression = h.Data.compression;

        b = memmapfile(ds.Filename, 'Offset', h.Data.off_image_header, ...
            'Format', ...
            {'uint32', 1, 'bi_size'; ...
             'int32', 1, 'bi_width'; ...
             'int32', 1, 'bi_height'; ...
             'uint16', 1, 'bi_planes'; ...
             'uint16', 1, 'bi_bit_count'; ...
             'uint32', 1, 'bi_compression'; ...
             'uint32', 1, 'bi_size_image'}, ...
            'Repeat', 1);

        ds.TrueWidth = b.Data.bi_width;
        ds.TrueHeight = b.Data.bi_height;
        ds.FrameWidth = max(ds.TrueWidth, ds.TrueHeight);
        ds.FrameHeight = ds.FrameWidth;

        ds.BitsPerPixel = b.Data.bi_bit_count;
        ds.BICompression = b.Data.bi_compression;
        ds.IsPacked = any(ds.BICompression == [256 1024]);

        % Image offsets
        fid = fopen(ds.Filename, 'r');
        fseek(fid, h.Data.off_image_offsets, 'bof');
        ds.ImageOffsets = fread(fid, ds.NumFrames, 'int64');
        fclose(fid);

        % Frame rate
        s = memmapfile(ds.Filename, 'Offset', h.Data.off_setup + 768, ...
            'Format', {'uint32', 1, 'frame_rate'}, 'Repeat', 1);
        ds.FrameRate = s.Data.frame_rate;
    end

    function frames = readFrames(ds, startIdx, count)
        frames = zeros(ds.FrameWidth, ds.FrameHeight, count, 'single');

        fid = fopen(ds.Filename, 'r');

        for k = 1:count
            idx = startIdx + k - 1;
            fseek(fid, ds.ImageOffsets(idx), 'bof');

            annSize = fread(fid, 1, 'uint32', 'l');
            fseek(fid, ds.ImageOffsets(idx) + annSize, 'bof');

            if ds.BitsPerPixel == 8
                raw = fread(fid, ds.TrueWidth * ds.TrueHeight, 'uint8=>single', 'l');
            else
                raw = fread(fid, ds.TrueWidth * ds.TrueHeight, 'uint16=>single', 'l');
            end

            img = reshape(raw, ds.TrueWidth, ds.TrueHeight);
            frames(:, :, k) = padAndRotate(ds, img);
        end

        fclose(fid);
    end

end

end

% helpers
function out = padAndRotate(ds, img)
N = ds.FrameWidth;
out = zeros(N, N, 'single');

if ds.TrueWidth <= ds.TrueHeight
    s = floor((N - ds.TrueWidth) / 2);
    out(s + 1:s + ds.TrueWidth, 1:ds.TrueHeight) = img;
else
    s = floor((N - ds.TrueHeight) / 2);
    out(1:ds.TrueWidth, s + 1:s + ds.TrueHeight) = img;
end

out = rot90(flipud(out), 2);
end
