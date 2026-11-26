function show_ref_disk(app, yesno)
% Shows the disk ref in true preview if it exists
image = app.HD.render.getImages(app.HD.params.imageTypes);
image = image{1};

if (size(image, 3) == 1)
    image = repmat(image, 1, 1, 3);
end

[numX, numY, ~] = size(image);
disk_ratio = app.HD.params.registrationDiskRatio;

circle = diskMask(numX, numY, disk_ratio -0.01, disk_ratio)';

if yesno
    image(:, :, 1) = 2 * circle .* image(:, :, 3) + ~circle .* image(:, :, 3);
    image(:, :, 2) = 2 * circle .* image(:, :, 3) + ~circle .* image(:, :, 3);
    image(:, :, 3) = 2 * circle .* image(:, :, 3) + ~circle .* image(:, :, 3);
else

end

% if strcmp(cache.spatialTransform, 'Fresnel') && (numX ~= numY)
%
% end
image = imresize3(image, [max(numX, numY) max(numX, numY), 3]);
app.Image.ImageSource = image;

end
