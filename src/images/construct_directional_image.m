function img = construct_directional_image(M0_pos, M0_neg)
% Constructs a a directional Doppler image from pos/negatitive Doppler maps
% M0_pos: positive Doppler freq map
% M0_neg: negative Doppler freq map

[Nx, Ny, ~, ~] = size(M0_pos);

min_M0 = min(min(M0_pos(:)), min(M0_neg(:)));
max_M0 = max(max(M0_pos(:)), max(M0_neg(:)));

M0_pos = mat2gray(M0_pos, double([min_M0, max_M0]));
M0_neg = mat2gray(M0_neg, double([min_M0, max_M0]));

M0_diff = M0_pos - M0_neg;
sat = abs(M0_diff);
tol = [0.6, 0.999];
sat = 0.7 * imadjustn(sat, stretchlim(sat(:), tol));

M0 = (M0_pos + M0_neg) / 2;
M0 = M0 - mean(mean(M0, 1), 2);
M0 = mat2gray(M0);
M0 = imadjustn(M0, stretchlim(M0(:), [0.02, 0.998]));

img = zeros(Nx, Ny, 3, 'single');

img1 = hsv2rgb(1 * ones(Nx, Ny), sat(:, :), M0(:, :));
img2 = hsv2rgb(0.66 * ones(Nx, Ny), sat(:, :), M0(:, :));
img(:, :, :) = img1 .* (M0_diff(:, :) > 0) + img2 .* (M0_diff(:, :) < 0);

%FIXME : create adequate img for display with holo/show_hologram (line 260)
img = mat2gray(img);
% img = im2uint8(img);
% img = rgb2ind(img,256);

end
