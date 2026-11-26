function H_ICA = short_time_ICA(H)
%ICA

[iwidth, iheight, batchSize] = size(H); % 'i' for initial

stride_param = 5;

xrange = unique(round(1:stride_param:iwidth));
yrange = unique(round(1:stride_param:iheight));
H = H(xrange, yrange, :); % sub sample H for faster computations

% H = (H - mean(H,3))./std(H,0,3); % normalize in one way

[width, height, ~] = size(H);
H = abs(H); %ICA only works on real data
H = reshape(H, width * height, batchSize);
H = (H - mean(H, 1)) ./ std(H, 0, 1); % normalize in the other
q = 2; % batchSize;
Mdl = rica(H, q, 'NonGaussianityIndicator', ones(q, 1), "IterationLimit", 100);
H_ICA = transform(Mdl, H);

H_ICA = reshape(H_ICA, width, height, q);
end
