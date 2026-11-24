function img = toImageSource(image, app)
% Convert scientific image data to RGB uint8.
% NaN/Inf are handled only in this display copy.

if nargin < 2
    app = [];
end

if isempty(image)
    img = zeros(100, 100, 3, 'uint8');
    return
end

if isa(image, 'gpuArray')
    image = gather(image);
end

% Preserve the scaling convention of integer images.
if isinteger(image) || islogical(image)
    image = im2double(image);
else
    image = double(image);
end

valid = isfinite(image);
values = image(valid);
out = zeros(size(image));

enhance = false;

if ~isempty(app) && isvalid(app) && ismethod(app, 'getWidgetValue')
    enhance = logical(app.getWidgetValue('ImproveContrast'));
end

if ~isempty(values)
    lo = min(values);
    hi = max(values);

    if enhance && hi > lo
        % Finite values only; exclude invalid pixels from the histogram.
        samples = (values - lo) ./ (hi - lo);
        limits = stretchlim(samples(:), [0.0001 0.9999]);
        limits = limits(:, 1);

        if limits(2) > limits(1)
            span = hi - lo;
            hi = lo + limits(2) * span;
            lo = lo + limits(1) * span;
        end

        out(valid) = (values - lo) ./ (hi - lo);

    elseif lo >= 0 && hi <= 1
        out(valid) = values;

    elseif hi > lo
        out(valid) = (values - lo) ./ (hi - lo);

    else
        % Constant finite scientific image: neutral gray.
        out(valid) = 0.5;
    end

end

out = min(max(out, 0), 1);
out(~valid) = 0;

% A partially invalid RGB pixel is displayed entirely black.
if size(out, 3) == 3
    badPixel = any(~valid, 3);
    out(repmat(badPixel, [1 1 3])) = 0;
else
    out = repmat(out, [1 1 3]);
end

img = im2uint8(out);
end
