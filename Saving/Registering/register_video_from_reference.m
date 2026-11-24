function [frames, shifts] = register_video_from_reference(frames, ref_img)
% registers a video
% frames: a video 4D-array width x height x 1 x num_frames

num_frames = size(frames, 4);

shifts = zeros(2, num_frames, 'single');

w = waitbar(0, 'Video registration in progress...');
styleWaitbar(w);
N_ = double(num_frames);
parforWaitbar(w, N_);
D = parallel.pool.DataQueue;
afterEach(D, @parforWaitbar);

parfor i = 1:num_frames
    send(D, i);
    [frames(:, :, :, i), shifts(:, i)] = registerImagesCrossCorrelation(frames(:, :, :, i), ref_img);
end

function parforWaitbar(waitbarHandle, iterations)
    persistent count h N

    if nargin == 2
        % Initialize

        count = 0;
        h = waitbarHandle;
        N = iterations;
    else
        % Update the waitbar

        % Check whether the handle is a reference to a deleted object
        if isvalid(h)
            count = count + 1;
            waitbar(count / N, h);
        end

    end

end

close(w);
end
