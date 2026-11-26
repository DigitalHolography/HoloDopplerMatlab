classdef CineReader

properties
    filename
    compression
    version
    num_frames
    frame_width
    frame_height
    frame_rate
    first_image_no
    image_offsets
    bits_per_pix
    bytes_per_frame
    horizontal_pix_per_meter
    vertical_pix_per_meter
    is_packed
    real_bpp
    bi_compression % New

    true_frame_width
    true_frame_height
end

methods

    function obj = CineReader(filename)
        obj.filename = filename;

        % parse header
        % discard trigger time
        header_mmap = memmapfile(filename, 'Format', ...
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
             'uint32', 1, 'off_image_offsets'; ...
         }, 'Repeat', 1);

        obj.num_frames = header_mmap.Data.image_count;
        obj.compression = header_mmap.Data.compression;
        obj.version = header_mmap.Data.version;
        obj.first_image_no = header_mmap.Data.first_image_no;

        % jump to bitmap info header
        bitmap_mmap = memmapfile(filename, ...
            'Offset', header_mmap.Data.off_image_header, 'Format', ...
            {'uint32', 1, 'bi_size'; ...
             'int32', 1, 'bi_width'; ...
             'int32', 1, 'bi_height'; ...
             'uint16', 1, 'bi_planes'; ...
             'uint16', 1, 'bi_bit_count'; ...
             'uint32', 1, 'bi_compression'; ...
             'uint32', 1, 'bi_size_image'; ...
             'int32', 1, 'bi_x_pels_per_meter'; ...
             'int32', 1, 'bi_y_pels_per_meter'; ...
             'uint32', 1, 'bi_clr_used'; ...
             'uint32', 1, 'bi_clr_important'; ...
         }, 'Repeat', 1);

        obj.bits_per_pix = bitmap_mmap.Data.bi_bit_count;
        obj.bi_compression = bitmap_mmap.Data.bi_compression; % New
        obj.bytes_per_frame = bitmap_mmap.Data.bi_size_image;
        obj.horizontal_pix_per_meter = bitmap_mmap.Data.bi_x_pels_per_meter;
        obj.vertical_pix_per_meter = bitmap_mmap.Data.bi_y_pels_per_meter;
        obj.frame_width = bitmap_mmap.Data.bi_width;
        obj.frame_height = bitmap_mmap.Data.bi_height;

        if bitmap_mmap.Data.bi_compression == 256 || bitmap_mmap.Data.bi_compression == 1024 % u10 || u12
            % packed binary format
            obj.is_packed = true;
        else
            obj.is_packed = false;
        end

        % read image ptr
        fd = fopen(filename, 'r');
        fseek(fd, header_mmap.Data.off_image_offsets, 'bof');
        obj.image_offsets = fread(fd, obj.num_frames, 'int64');
        fclose(fd);

        % jump to camera setup structure to read frame rate
        % Skip additional 768 bytes to access FrameRate in the struct,
        % instead of FrameRate16
        setup_mmap = memmapfile(filename, ...
            'Offset', header_mmap.Data.off_setup + 768, 'Format', ...
            {'uint32', 1, 'frame_rate'; ...
        % discard the rest of the struct, we don't need it
         }, 'Repeat', 1);
        obj.frame_rate = setup_mmap.Data.frame_rate;

        % skip a bunch of fields to access the number of bits per pixel
        % bytes to skip from the begining of the Setup struct:
        % (MAXLENDESCRIPTION_OLD = 121)
        % (OLDMAXFILENAME = 65)
        % uint16 x 19
        % int16 x 11
        % uint8 x 11
        % char x (121 + 8 * 11 + 8*6 + 8*11 + 4*65 = 605)
        % float x 8
        % double x 2
        % uint32 x 16
        % int32 x 10
        % bool32 x 3
        % RECT(size=4x32bits) x 1
        % WBGAIN(size=64bits) x 5
        % total bytes to skip = 896
        fd = fopen(filename, 'r');
        fseek(fd, header_mmap.Data.off_setup + 896, 'bof');
        obj.real_bpp = fread(fd, 1, 'uint32=>uint32');
        fclose(fd);

        final_frame_size = max(obj.frame_width, obj.frame_height);
        obj.true_frame_width = obj.frame_width;
        obj.true_frame_height = obj.frame_height;
        obj.frame_width = final_frame_size;
        obj.frame_height = final_frame_size;
    end

    function frame_batch = read_frame_batch(obj, batchSize, frame_offset)
        final_frame_size = max(obj.true_frame_width, obj.true_frame_height);

        if obj.true_frame_width <= obj.true_frame_height
            width_skip = floor(0.5 * (final_frame_size - obj.true_frame_width));
            widthRange = 1 + width_skip:width_skip + obj.true_frame_width;
            heightRange = 1:obj.true_frame_height;
        else
            height_skip = floor(0.5 * (final_frame_size - obj.true_frame_height));
            heightRange = 1 + height_skip:height_skip + obj.true_frame_height;
            widthRange = 1:obj.true_frame_width;
        end

        if obj.is_packed
            % assume it is 12 bits packed for now
            fd = fopen(obj.filename, 'r');
            frame_batch = zeros(final_frame_size, final_frame_size, batchSize, 'double');

            for i = 1:batchSize
                fseek(fd, obj.image_offsets(frame_offset + i), 'bof');
                % read annotation size
                annotation_size = fread(fd, 1, 'uint32', 'l');
                fseek(fd, obj.image_offsets(frame_offset + i) + annotation_size, 'bof');

                if obj.bi_compression == 256 % packed frame contains Nx*Ny u10 or Nx*Ny*5/4 Bytes
                    packed_frame_size = ceil(obj.true_frame_width * obj.true_frame_height / 4) * 5;
                elseif obj.bi_compression == 1024 % packed frame contains Nx*Ny u12 or Nx*Ny*3/2 Bytes
                    packed_frame_size = ceil(obj.true_frame_width * obj.true_frame_height / 2) * 3;
                end

                packed_frame = fread(fd, packed_frame_size, 'uint8', 'l');
                unpacked_frame_zeros = zeros(obj.true_frame_width * obj.true_frame_height, 1, 'double');
                unpacked_frame = unpack_u12_u10(obj.bi_compression, packed_frame, unpacked_frame_zeros);
                %                  frame_batch(widthRange,heightRange,i) = rot90(flipud(reshape(unpacked_frame, obj.frame_width, obj.frame_height)), 2);
                frame_batch(widthRange, heightRange, i) = rot90(flipud(reshape(unpacked_frame, obj.true_frame_width, obj.true_frame_height)), 2);
            end

            frame_batch = CineReader.replace_dropped_frames(frame_batch, 0.2);
            fclose(fd);
        else %not 12bit packed
            fd = fopen(obj.filename, 'r');
            % skip additional 17 bytes to skip useless struct before pix array
            frame_batch = zeros(final_frame_size, final_frame_size, batchSize, 'single');

            for i = 1:batchSize
                fseek(fd, obj.image_offsets(frame_offset + i), 'bof');
                % read annotation size
                annotation_size = fread(fd, 1, 'uint32', 'l');
                fseek(fd, obj.image_offsets(frame_offset + i) + annotation_size, 'bof');
                %
                if obj.bits_per_pix == 8 % read 8-bit interferograms
                    frame_batch(widthRange, heightRange, i) = reshape(fread(fd, obj.true_frame_width * obj.true_frame_height, 'uint8=>single', 'l'), obj.true_frame_width, obj.true_frame_height);
                else % read 16-bit interferograms
                    frame_batch(widthRange, heightRange, i) = reshape(fread(fd, obj.true_frame_width * obj.true_frame_height, 'uint16=>single', 'l'), obj.true_frame_width, obj.true_frame_height);
                end

            end

            frame_batch = CineReader.replace_dropped_frames(frame_batch, 0.2);
            fclose(fd);
        end

    end

    function fs = sampling_frequency(obj)
        fs = 1 / obj.frame_rate;
    end

    function width = get_frame_width(obj)
        width = obj.frame_width;
    end

    function height = get_frame_height(obj)
        height = obj.frame_height;
    end

end

methods (Static)

    function batch = replace_dropped_frames(batch, threshold)
        % Replaces dropped frames with neighbor frames
        %   batch = replace_dropped_frames(batch, threshold) returns
        %   the new image batch with replaced dropped frames.
        %
        % batch: input 3-dimensional image array
        % threshold: mean value to average value ratio under which a
        %            frame is considered dropped

        % construct image average values and total average value
        batch_avgs = squeeze(mean(mean(batch, 1), 2));
        batch_avg = mean(batch_avgs);

        % setup images filter
        to_delete = abs(batch_avgs - batch_avg) > batch_avg * threshold;
        to_delete = to_delete + circshift(to_delete, 1) + circshift(to_delete, 2);
        to_delete = to_delete > 0;

        % replace the frames
        batch(:, :, to_delete) = batch(:, :, circshift(to_delete, 3));
    end

end

end
