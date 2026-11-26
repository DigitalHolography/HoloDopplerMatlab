classdef HoloDatastore < matlab.io.Datastore & ...
    matlab.io.datastore.MiniBatchable

properties
    Filename
    Version
    NumFrames
    FrameWidth
    FrameHeight
    BitDepth
    Endianness
    DataSize
    Footer
end

properties (Access = private)
    CurrentFrame = 1
    MiniBatchSize = 1
    AllFrames = []
    BytesPerFrame
    EndianFlag
end

methods

    function ds = HoloDatastore(filename)

        ds.Filename = filename;
        ds.parseHeaderAndFooter();
        ds.BytesPerFrame = ...
            uint64(ds.FrameWidth) * ...
            uint64(ds.FrameHeight) * ...
            uint64(ds.BitDepth / 8);

        ds.EndianFlag = ternary(ds.Endianness == 0, 'l', 'b');

    end

    % Datastore API
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

    % MiniBatchable
    function setMiniBatchSize(ds, n)
        ds.MiniBatchSize = n;
    end

    function tf = supportsMiniBatching(~)
        tf = true;
    end

    function tf = supportsTall(~)
        tf = true;
    end

end

% Internal logic
methods (Access = private)

    function parseHeaderAndFooter(ds)
        h = memmapfile(ds.Filename, 'Format', ...
            {'uint8', 4, 'magic'; ...
             'uint16', 1, 'version'; ...
             'uint16', 1, 'bit_depth'; ...
             'uint32', 1, 'width'; ...
             'uint32', 1, 'height'; ...
             'uint32', 1, 'num_frames'; ...
             'uint64', 1, 'total_size'; ...
             'uint8', 1, 'endianness'}, ...
            'Repeat', 1);

        if ~isequal(h.Data.magic', uint8('HOLO'))
            error('Bad HOLO file');
        end

        ds.Version = h.Data.version;
        ds.BitDepth = h.Data.bit_depth;
        ds.FrameWidth = h.Data.width;
        ds.FrameHeight = h.Data.height;
        ds.NumFrames = h.Data.num_frames;
        ds.DataSize = h.Data.total_size;
        ds.Endianness = h.Data.endianness;

        % Footer
        headerSize = uint64(64);
        dataBytes = uint64(ds.FrameWidth) * ...
            uint64(ds.FrameHeight) * ...
            uint64(ds.NumFrames) * ...
            uint64(ds.BitDepth / 8);

        footerOffset = headerSize + dataBytes;
        fileInfo = dir(ds.Filename);

        if footerOffset >= fileInfo.bytes
            % Legacy default footer
            ds.Footer.compute_settings.image_rendering.lambda = 8.5200e-07;
            ds.Footer.info.pixel_pitch.x = 12;
            ds.Footer.info.pixel_pitch.y = 12;
            ds.Footer.compute_settings.image_rendering.propagation_distance = 0.4;
        else
            fid = fopen(ds.Filename, 'r');
            fseek(fid, footerOffset, 'bof');
            raw = fread(fid, fileInfo.bytes - footerOffset, '*char');
            fclose(fid);
            ds.Footer = jsondecode(string(raw'));
        end

    end

    function frames = readFrames(ds, startIdx, count)
        frames = zeros(ds.FrameWidth, ds.FrameHeight, count, 'single');

        if ~isempty(ds.AllFrames)
            frames = ds.AllFrames(:, :, startIdx:startIdx + count - 1);
            frames = HoloDatastore.replace_dropped_frames(frames, 0.2);
            return
        end

        fid = fopen(ds.Filename, 'r');

        for k = 1:count
            idx = startIdx + k - 1;
            offset = uint64(64) + uint64(idx - 1) * ds.BytesPerFrame;
            fseek(fid, offset, 'bof');

            if ds.BitDepth == 8
                raw = fread(fid, ...
                    ds.FrameWidth * ds.FrameHeight, ...
                    'uint8=>single', ds.EndianFlag);
            else
                raw = fread(fid, ...
                    ds.FrameWidth * ds.FrameHeight, ...
                    'uint16=>single', ds.EndianFlag);
            end

            frames(:, :, k) = reshape(raw, ds.FrameWidth, ds.FrameHeight);
        end

        fclose(fid);
        frames = HoloDatastore.replace_dropped_frames(frames, 0.2);
    end

end

% Static utilities
methods (Static)

    function batch = replace_dropped_frames(batch, threshold)
        avgs = squeeze(mean(mean(batch, 1), 2));
        avg = mean(avgs);

        bad = abs(avgs - avg) > avg * threshold;
        bad = bad | circshift(bad, 1) | circshift(bad, 2);
        batch(:, :, bad) = batch(:, :, circshift(bad, 3));
    end

end

end

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end
