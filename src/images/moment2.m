function moment2 = moment2(SH, f1, f2, fs, batchSize, gw)

arguments
    SH
    f1
    f2
    fs
    batchSize
    gw = 0
end

% Calculate the second moment of the spectrum
SH = abs(SH);

% Create frequency weights for the second moment calculation
f = fftfreq(batchSize, 1 / fs);
weights = f .^ 2;
weights(abs(weights) > f2 ^ 2) = 0;
weights(abs(weights) < f1 ^ 2) = 0;

% Compute the second moment by summing the weighted spectrum across frequencies
moment2 = sum(SH .* reshape(weights, 1, 1, []), 3);

if gw ~= 0
    moment2 = flat_field_correction(moment2, gw);
end

end
