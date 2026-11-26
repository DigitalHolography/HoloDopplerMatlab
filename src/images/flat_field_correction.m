function corrected_image = flat_field_correction(image, gw)

if gw ~= 0
    ms = sum(image, [1 2]);
    image = image ./ imgaussfilt(image, gw);
    ms2 = sum(image, [1 2]);
    corrected_image = (ms / ms2) .* image;
else
    corrected_image = image;
end

end
