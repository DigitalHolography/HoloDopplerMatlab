function [reg_image, shift] = registerImagesCrossCorrelation(MOVING, FIXED)
%registerImagesCrossCorrelation  Register images taken as matrices centered
% around zero
% Simple translation only registration (no rotation, scale, shear)
% Computation intensive
% MOVING, FIXED : input 2D matrices of same size

MOVING = imgaussfilt(MOVING, 1.5); % blurring to avoid sharp mouvements
FIXED = imgaussfilt(FIXED, 1.5); % blurring to avoid sharp mouvements

corr = xcorr2(MOVING, FIXED); % calculate the cross correlation matrix % todo  version corr = conv2(MOVING, rot90(conj(FIXED),2),'same');
[~, index] = max(corr, [], 'all'); % find the argmax
[i, j] = ind2sub(size(corr), index);

shift = [-i; -j];
reg_image = circshift(MOVING, [-i, -j]);

end
