function [img] = construct_colored_image(M0, M_freq_low, M_freq_high, ...
                                      hueAngle, chromaMax)
% CONSTRUCT_COLORED_IMAGE Color composite along a fixed CIELAB axis.
%
% L* is obtained from M0, rescaled to [0, 100].
% The relative high/low-frequency dominance controls the signed
% position along an axis through the origin of the a*b* plane.
%
% Optional parameters:
%   hueAngle  : positive-axis hue angle in degrees (default: 340)
%   chromaMax : maximum requested CIELAB chroma (default: 40)
%
% Positive dominance -> hueAngle
% Negative dominance -> hueAngle + 180 degrees
% Zero dominance     -> neutral gray
%
% Output:
%   img : double sRGB image in [0, 1]

if nargin < 4 || isempty(hueAngle)
    hueAngle = 20;
end
if nargin < 5 || isempty(chromaMax)
    chromaMax = 60;
end

M0 = double(M0);
low = double(M_freq_low);
high = double(M_freq_high);

% Invalid pixels are displayed as black.
valid = isfinite(M0) & isfinite(low) & isfinite(high);
M0(~valid) = 0;
low(~valid) = 0;
high(~valid) = 0;

% Frequency-band intensities are assumed to be nonnegative.
low = max(low, 0);
high = max(high, 0);

% Preserve the original min-max lightness mapping.
Lstar = zeros(size(M0));
if any(valid(:))
    values = M0(valid);
    lower = min(values);
    upper = max(values);

    if upper > lower
        Lstar(valid) = 100 * (values - lower) / (upper - lower);
    end
end

% Common scaling preserves the ratio and avoids overflow in high + low.
bandScale = max(max(low(:)), max(high(:)));
dominance = zeros(size(M0));

if bandScale > 0
    low = low / bandScale;
    high = high / bandScale;

    total = high + low;
    nonzero = total > 0;
    dominance(nonzero) = ...
        (high(nonzero) - low(nonzero)) ./ total(nonzero);
end

% Amplify chromatic contrast while preserving the neutral point.
colorGain = 8;
colorGamma = 0.7;

d = tanh(colorGain * dominance);
d = sign(d) .* abs(d).^colorGamma;

% Signed coordinate along the fixed a*b* axis.
axisPosition = double(chromaMax) * d;
hueAngle = mod(double(hueAngle), 360);

Lab = cat(3, Lstar, ...
    axisPosition .* cosd(hueAngle), ...
    axisPosition .* sind(hueAngle));

% Convert to display RGB and clip out-of-gamut values.
img = lab2rgb(Lab);
img = min(max(img, 0), 1);

end