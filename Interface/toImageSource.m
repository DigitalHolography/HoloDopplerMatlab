function [img, validMask] = toImageSource(image, app)
% TOIMAGESOURCE Convert scientific image data to displayable RGB uint8.
%
% Invalid pixels are displayed in magenta.
% Input data are never modified outside this function.
%
% Outputs:
%   img       : RGB uint8 display image.
%   validMask : logical mask, true where all channels are finite.
%
% Scaling policy:
%   - Integer images: standard im2double conversion.
%   - Floating-point grayscale: finite min/max normalization.
%   - Floating-point RGB in [0,1]: preserve the original scale.
%   - Other floating-point RGB: global finite min/max normalization.
%   - Optional contrast: finite-pixel quantiles, applied per channel.

if nargin < 2
    app = [];
end

if isa(image, 'gpuArray')
    image = gather(image);
end

if isempty(image)
    img = zeros(100, 100, 3, 'uint8');
    validMask = false(100, 100);
    return;
end

validateattributes(image, {'numeric', 'logical'}, ...
    {'real', 'nonsparse'}, mfilename, 'image');

if ndims(image) > 3 || ~ismember(size(image, 3), [1 3])
    error('HoloDoppler:InvalidDisplayImage', ...
        'Expected a grayscale image or an M-by-N-by-3 RGB image.');
end

invalidColor = uint8([255 0 255]);
isRGB = size(image, 3) == 3;
isFloating = isfloat(image);

% An RGB pixel is invalid if any of its channels is invalid.
validMask = all(isfinite(image), 3);

if isFloating
    work = double(image);
else
    work = im2double(image);
end

if ~any(validMask(:))
    img = repmat(reshape(invalidColor, 1, 1, 3), ...
        size(image, 1), size(image, 2));
    return;
end

validChannels = repmat(validMask, 1, 1, size(work, 3));
values = work(validChannels);

% Normalize scientific floating-point maps.
if isFloating
    preserveRGB = isRGB && all(values >= 0 & values <= 1);

    if ~preserveRGB
        lo = min(values);
        hi = max(values);

        if hi > lo
            % Scale first to avoid overflow for extreme finite values.
            scale = max(abs([lo hi]));
            work = (work / scale - lo / scale) ...
                / (hi / scale - lo / scale);
        else
            % A constant map has no intrinsic display contrast.
            work(:) = 0.5;
        end
    end
end

improveContrast = false;

if ~isempty(app) && isvalid(app) && ...
        ismethod(app, 'getWidgetValue')
    improveContrast = logical(app.getWidgetValue('ImproveContrast'));
end

if improveContrast
    for channel = 1:size(work, 3)
        plane = work(:, :, channel);
        values = plane(validMask);

        limits = quantile(values, [0.0001 0.9999]);

        if limits(2) > limits(1)
            plane = (plane - limits(1)) ...
                / (limits(2) - limits(1));
        end

        work(:, :, channel) = plane;
    end
end

% Replace invalid display samples only after contrast estimation.
work(~validChannels) = 0;
work = min(max(work, 0), 1);

if ~isRGB
    work = repmat(work, 1, 1, 3);
end

img = im2uint8(work);

% Reapply the invalid-pixel color after conversion.
for channel = 1:3
    plane = img(:, :, channel);
    plane(~validMask) = invalidColor(channel);
    img(:, :, channel) = plane;
end

end