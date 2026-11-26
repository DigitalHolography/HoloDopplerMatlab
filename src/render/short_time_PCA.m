function H_PCA = short_time_PCA(H)
% PCA of short time spatio-temporal features
% H: frame batch already propagated to the distance of reconstruction

[width, height, batchSize] = size(H);
H = reshape(H, width * height, batchSize);

% SVD of spatio-temporal features
cov = H' * H;
[V, S] = eig(cov);
[~, sort_idx] = sort(diag(S), 'descend');
V = V(:, sort_idx);

% selection of eigenvalues
%     X = ones(size(V));
%     X(:, x) = 0;
%     V = V.*X;

% projection of H
H_PCA = H * V;
H_PCA = reshape(H_PCA, width, height, batchSize);
end
