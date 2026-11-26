function W = morlet1D_transform_3rdDim(A, scales, omega0)
% MORLET1D_TRANSFORM_3RDDIM
% Performs a 1D Morlet wavelet transform along the 3rd dimension of a 3D array.
%
%   W = morlet1D_transform_3rdDim(A, scales, omega0)
%
%   Inputs:
%       A        - 3D input array (X × Y × Z)
%       scales   - vector of scales (e.g. logspace(0, 2, 32))
%       omega0   - central frequency of the Morlet wavelet (e.g. 6)
%
%   Output:
%       W        - 4D array of wavelet coefficients (X × Y × length(scales) × Z)
%
%   Example:
%       A = randn(32, 32, 128);
%       scales = logspace(0, 2, 32);
%       W = morlet1D_transform_3rdDim(A, scales, 6);

if nargin < 2 || isempty(scales)
    scales = 1;
end

if nargin < 3
    omega0 = 6; % default central frequency
end

[nx, ny, nz] = size(A);
ns = numel(scales);
W = zeros(nx, ny, ns, nz, "single");

% Frequency vector
freqs = ifftshift((-floor(nz / 2):ceil(nz / 2) - 1) / nz * 2 * pi);

% FFT along 3rd dimension
A_fft = fft(A, [], 3);

for si = 1:ns
    s = scales(si);
    % Morlet wavelet in frequency domain
    psi_hat = (pi ^ (-0.25)) * exp(-0.5 * (s * freqs - omega0) .^ 2);
    psi_hat = reshape(psi_hat, [1 1 nz]); % match dimensions
    % Apply convolution in frequency domain
    W(:, :, si, :) = ifft(A_fft .* psi_hat, [], 3);
end

W = squeeze(W);
end
