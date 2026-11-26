function moment0 = moment0(SH, f1, f2, fs, batchSize, gw)

arguments
    SH
    f1
    f2
    fs
    batchSize
    gw = 0
end

% Calculate the zeroth moment of the spectrum
SH = abs(SH);

% Create frequency weights for the zeroth moment calculation
f = fftfreq(batchSize, 1 / fs);
abs_f = abs(f);

% Boolean mask for the visible window [f1, f2]
mask = (abs_f >= f1) & (abs_f <= f2);

% Compute the zeroth moment by summing the weighted spectrum across frequencies
moment0 = sum(SH .* reshape(mask, 1, 1, []), 3);

if gw ~= 0
    moment0 = flat_field_correction(moment0, gw);
end

end
