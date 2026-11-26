function Hout = fft_clutter_filter( ...
    Hin, lowHz, highHz, fsHz, transitionHz)
%FFT_CLUTTER_FILTER Two-sided temporal FFT band-pass filtering.
%
% Hout = fft_clutter_filter( ...
%     Hin, lowHz, highHz, fsHz, transitionHz)
%
% Inputs:
%   Hin          : real or complex single/double array [Nx, Ny, Nt].
%                  CPU array or gpuArray.
%   lowHz        : lower unity-gain passband edge in Hz.
%                  Set to 0 to disable lower-frequency rejection.
%   highHz       : upper unity-gain passband edge in Hz.
%                  Set to Inf, or fsHz/2, to disable upper rejection.
%   fsHz         : sampling frequency in Hz.
%   transitionHz : nonnegative raised-cosine transition width in Hz.
%                  Set to 0 for a rectangular frequency mask.
%
% Output:
%   Hout         : same size, precision and device placement as Hin.
%
% Mask:
%   Gain depends on absolute frequency, preserving both Doppler signs.
%   The passband has unity gain for lowHz <= abs(f) <= highHz.
%   Positive-width transitions lie outside this passband.
%
% Notes:
%   - The FFT length equals the number of input frames.
%   - Filtering is circular within each batch.
%   - No temporal window, padding or overlap processing is applied.
%   - Nonfinite input samples are rejected.
%   - GPU validation requires a scalar synchronization with the CPU.

arguments
    Hin
    lowHz (1, 1) double ...
        {mustBeReal, mustBeFinite, mustBeNonnegative}
    highHz (1, 1) double ...
        {mustBeReal, mustBePositive}
    fsHz (1, 1) double ...
        {mustBeReal, mustBeFinite, mustBePositive}
    transitionHz (1, 1) double ...
        {mustBeReal, mustBeFinite, mustBeNonnegative} = 0
end

% -------------------------------------------------------------------------
% Validate input
% -------------------------------------------------------------------------
onGPU = isa(Hin, 'gpuArray');

if onGPU
    inputClass = classUnderlying(Hin);
else
    inputClass = class(Hin);
end

if ~ismember(inputClass, {'single', 'double'})
    error('fft_clutter_filter:InvalidType', ...
        'Hin must contain single- or double-precision data.');
end

if isempty(Hin) || ndims(Hin) > 3 || issparse(Hin)
    error('fft_clutter_filter:InvalidSize', ...
        ['Hin must be a nonempty, full array ', ...
         'with time along dimension 3.']);
end

nt = size(Hin, 3);

if nt < 2
    error('fft_clutter_filter:InsufficientFrames', ...
        'At least two frames are required.');
end

if isnan(highHz)
    error('fft_clutter_filter:InvalidUpperEdge', ...
        'highHz must be a positive finite value or Inf.');
end

nyquistHz = fsHz / 2;

if lowHz >= nyquistHz
    error('fft_clutter_filter:InvalidLowerEdge', ...
        'lowHz must be strictly below fsHz/2 (%g Hz).', nyquistHz);
end

if isinf(highHz)
    upperEdgeHz = nyquistHz;
else
    if highHz > nyquistHz
        error('fft_clutter_filter:InvalidUpperEdge', ...
            'Finite highHz must not exceed fsHz/2 (%g Hz).', nyquistHz);
    end

    upperEdgeHz = highHz;
end

if lowHz >= upperEdgeHz
    error('fft_clutter_filter:InvalidBand', ...
        'lowHz must be strictly smaller than the upper passband edge.');
end

lowerEnabled = lowHz > 0;
upperEnabled = upperEdgeHz < nyquistHz;

if transitionHz > 0

    if lowerEnabled && transitionHz > lowHz
        error('fft_clutter_filter:InvalidLowerTransition', ...
            'transitionHz must not exceed lowHz.');
    end

    if upperEnabled && ...
            transitionHz > nyquistHz - upperEdgeHz
        error('fft_clutter_filter:InvalidUpperTransition', ...
            ['transitionHz must not exceed the distance ', ...
             'from highHz to Nyquist.']);
    end

end

% Scan time planes rather than allocating a full-volume logical array.
for frameIndex = 1:nt

    frame = Hin(:, :, frameIndex);
    invalid = any(~isfinite(frame(:)));

    if onGPU
        invalid = gather(invalid);
    end

    if invalid
        error('fft_clutter_filter:NonfiniteInput', ...
            'Hin contains NaN or Inf samples.');
    end

end

% Exact bypass when neither side rejects any frequency.
if ~lowerEnabled && ~upperEnabled
    Hout = Hin;
    return
end

% -------------------------------------------------------------------------
% Frequency coordinates in native, unshifted FFT order.
%
% Even Nt:
%   0, ..., Nt/2-1, -Nt/2, ..., -1
%
% Odd Nt:
%   0, ..., (Nt-1)/2, -(Nt-1)/2, ..., -1
% -------------------------------------------------------------------------
frequencyBins = 0:(nt - 1);

negativeBins = frequencyBins > floor((nt - 1) / 2);
frequencyBins(negativeBins) = ...
    frequencyBins(negativeBins) - nt;

absoluteHz = abs(frequencyBins * (fsHz / nt));

% -------------------------------------------------------------------------
% Construct a real, even frequency mask.
% -------------------------------------------------------------------------
gain = ones(1, nt);

if transitionHz == 0

    if lowerEnabled
        gain(absoluteHz < lowHz) = 0;
    end

    if upperEnabled
        gain(absoluteHz > upperEdgeHz) = 0;
    end

else

    if lowerEnabled
        lowerStopHz = lowHz - transitionHz;

        lowerGain = ones(1, nt);
        lowerGain(absoluteHz <= lowerStopHz) = 0;

        inLowerTransition = ...
            absoluteHz > lowerStopHz & absoluteHz < lowHz;

        position = ...
            (absoluteHz(inLowerTransition) - lowerStopHz) ...
            / transitionHz;

        lowerGain(inLowerTransition) = ...
            0.5 * (1 - cos(pi * position));

        gain = gain .* lowerGain;
    end

    if upperEnabled
        upperStopHz = upperEdgeHz + transitionHz;

        upperGain = ones(1, nt);
        upperGain(absoluteHz >= upperStopHz) = 0;

        inUpperTransition = ...
            absoluteHz > upperEdgeHz & absoluteHz < upperStopHz;

        position = ...
            (absoluteHz(inUpperTransition) - upperEdgeHz) ...
            / transitionHz;

        upperGain(inUpperTransition) = ...
            0.5 * (1 + cos(pi * position));

        gain = gain .* upperGain;
    end

end

if ~any(gain > 0)
    error('fft_clutter_filter:EmptySampledBand', ...
        ['The selected mask rejects every FFT bin. ', ...
         'Increase the batch length or widen the passband.']);
end

% Match the precision and device of the field.
mask = cast(reshape(gain, 1, 1, nt), inputClass);

if onGPU
    mask = gpuArray(mask);
end

% -------------------------------------------------------------------------
% Apply the mask along the temporal dimension.
% -------------------------------------------------------------------------
spectrum = fft(Hin, [], 3);
spectrum = spectrum .* mask;

Hout = ifft(spectrum, [], 3);

% Remove roundoff imaginary parts only when the input itself was real.
if isreal(Hin)
    Hout = real(Hout);
end

end