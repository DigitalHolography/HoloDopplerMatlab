function Hout = butterworth_clutter_filter( ...
    Hin, cutoffHz, fsHz, filterOrder, zeroPhase)
%BUTTERWORTH_CLUTTER_FILTER Temporal Butterworth high-pass filtering.
%
% Hout = butterworth_clutter_filter( ...
%     Hin, cutoffHz, fsHz, filterOrder, zeroPhase)
%
% Inputs:
%   Hin         : real or complex CPU single/double array [Nx, Ny, Nt].
%   cutoffHz    : one-pass Butterworth cutoff frequency in Hz.
%                 Must satisfy 0 < cutoffHz < fsHz/2.
%   fsHz        : sampling frequency in Hz.
%   filterOrder : positive integer; order of the one-pass filter.
%   zeroPhase   : logical scalar.
%                 true  -> forward-backward filtering.
%                 false -> causal filtering with zero initial state.
%
% Output:
%   Hout        : same size and precision as Hin.
%
% Notes:
%   - Filtering is independent for each pixel along dimension 3.
%   - Internal filtering uses double precision.
%   - Filter state is not carried between batches.
%   - Nonfinite input samples are rejected.
%   - GPU input is explicitly unsupported by this implementation.
%   - Requires Signal Processing Toolbox.

arguments
    Hin
    cutoffHz (1, 1) double ...
        {mustBeReal, mustBeFinite, mustBePositive}
    fsHz (1, 1) double ...
        {mustBeReal, mustBeFinite, mustBePositive}
    filterOrder (1, 1) double ...
        {mustBeReal, mustBeFinite, mustBeInteger, mustBePositive} = 4
    zeroPhase (1, 1) logical = true
end

% -------------------------------------------------------------------------
% Validate input
% -------------------------------------------------------------------------
if isa(Hin, 'gpuArray')
    error('butterworth_clutter_filter:GPUNotSupported', ...
        ['This implementation accepts CPU arrays only. ', ...
         'Gather the field explicitly before filtering if required.']);
end

if ~(isa(Hin, 'single') || isa(Hin, 'double'))
    error('butterworth_clutter_filter:InvalidType', ...
        'Hin must contain single- or double-precision data.');
end

if isempty(Hin) || ndims(Hin) > 3 || issparse(Hin)
    error('butterworth_clutter_filter:InvalidSize', ...
        ['Hin must be a nonempty, full array ', ...
         'with time along dimension 3.']);
end

if cutoffHz >= fsHz / 2
    error('butterworth_clutter_filter:InvalidCutoff', ...
        'cutoffHz must be strictly below fsHz/2 (%g Hz).', fsHz / 2);
end

nt = size(Hin, 3);

if nt < 2
    error('butterworth_clutter_filter:InsufficientFrames', ...
        'At least two frames are required.');
end

% -------------------------------------------------------------------------
% Design in zero-pole-gain form, then convert to second-order sections.
% -------------------------------------------------------------------------
normalizedCutoff = cutoffHz / (fsHz / 2);

[z, poles, gain] = butter( ...
    filterOrder, normalizedCutoff, 'high');

[sos, scale] = zp2sos(z, poles, gain);

% filtfilt distinguishes SOS input from a numerator vector by its rows.
% For one-section designs, append an identity section.
if size(sos, 1) == 1
    sos = [sos; 1 0 0 1 0 0];
end

% Conservative length requirement accounting for all represented sections.
% MATLAB's filtfilt can impose additional release-specific constraints.
if zeroPhase
    representedOrder = 2 * size(sos, 1);
    minimumFrames = 3 * representedOrder + 1;

    if nt < minimumFrames
        error('butterworth_clutter_filter:BatchTooShort', ...
            ['Zero-phase filtering requires at least %d frames ', ...
             'for this SOS representation; received %d. ', ...
             'Use a longer batch, lower order, or causal filtering.'], ...
            minimumFrames, nt);
    end
end

% -------------------------------------------------------------------------
% Rows of X are pixels; columns are time.
% Each processing block is transposed so time becomes dimension 1.
% -------------------------------------------------------------------------
inputSize = size(Hin);
inputClass = class(Hin);

X = reshape(Hin, [], nt);
Y = zeros(size(X), 'like', Hin);

numPixels = size(X, 1);
pixelsPerBlock = 4096;

for firstPixel = 1:pixelsPerBlock:numPixels

    lastPixel = min(firstPixel + pixelsPerBlock - 1, numPixels);
    pixelIndices = firstPixel:lastPixel;

    % Nonconjugating transpose preserves complex time series.
    block = double(X(pixelIndices, :).');

    if any(~isfinite(block(:)))
        error('butterworth_clutter_filter:NonfiniteInput', ...
            'Hin contains NaN or Inf samples.');
    end

    if zeroPhase
        filteredBlock = filtfilt(sos, scale, block);
    else
        % sosfilt operates independently on each column.
        filteredBlock = scale .* sosfilt(sos, block);
    end

    Y(pixelIndices, :) = cast(filteredBlock.', inputClass);

end

Hout = reshape(Y, inputSize);

end