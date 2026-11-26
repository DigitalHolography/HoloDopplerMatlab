function [H, cov, U] = svd_filter(H, thresh, f1, fs, stride_param, true_mean_correction)
% SVD filtering
%
% H: an frame batch already propagated to the distance of reconstruction
% threshold : number of firsts components of the svd decomposition removed
% f1 fs : thresh frequency and sampling frequency for default behavior

arguments
    H 
    thresh 
    f1 
    fs 
    stride_param = 1
    true_mean_correction = false
end

if isempty(stride_param)
    stride_param = 1;
end

[iwidth, iheight, batchSize] = size(H); % 'i' for initial

Hi = reshape(H, iwidth * iheight, batchSize);

if ~thresh
    % thresh parameter does not exist, so default it to something
    thresh = ceil(f1 * batchSize / fs * 2);
end

thresh = max(min(thresh, batchSize), 1);

if true_mean_correction
    % remove the mean value to compute a real covariance matrix slightly
    % slower and not much difference so deactivated by default
    meanH = mean(H, 3);
    H = (H - meanH);
end

xrange = unique(round(1:stride_param:iwidth));
yrange = unique(round(1:stride_param:iheight));
H = H(xrange, yrange, :); % sub sample H for faster computations

[width, height, ~] = size(H);
H = reshape(H, width * height, batchSize);

% SVD of spatio-temporal features
cov = H' * H;
[V, S] = eig(cov);

[~, sort_idx] = sort(diag(S), 'descend');
V = V(:, sort_idx);
H_tissue = Hi * V(:, 1:thresh) * V(:, 1:thresh)';
U = Hi * V(:, 1:thresh); % U is also divided by S^2 but normalization of each U image removes this factor
H = reshape(Hi - H_tissue, iwidth, iheight, batchSize);
H = reshape(H, iwidth, iheight, batchSize);

if true_mean_correction
    % re add the mean of H
    H = (H + meanH);
end

end
