function results = make_band_figures(dataPath, masks, varargin)
%MAKE_BAND_FIGURES Produce the spectral-band-ratio figures for the article.
%
% RESULTS = MAKE_BAND_FIGURES(DATAPATH, MASKS) reads the HoloDopplerMatlab
% HDF5 dataset /SH_power without loading the complete cube into memory.
%
% DATAPATH can be:
%   - the path of a HoloDoppler *_output.h5 file;
%   - a folder containing exactly one *_output.h5 file.
%
% MASKS can be:
%   - [] (only the spatial maps are generated);
%   - a struct whose fields are ROI names and whose values are logical masks
%     or paths to mask images, for example:
%       masks.retinal   = "RetinalArteryMask.png";
%       masks.choroidal = "ChoroidalArteryMask.png";
%   - the path of a MAT file containing such a struct or mask variables;
%   - the path of a single mask image (the ROI is named "roi").
%
% Example:
%   dataPath = "D:\data\eye_HD\h5\eye_HD_output.h5";
%   masks.retinal = "D:\masks\retinal_artery.png";
%   masks.choroidal = "D:\masks\choroidal_artery.png";
%   results = make_band_figures(dataPath, masks, ...
%       'OutputDirectory', "D:\article\figures", ...
%       'LowBand', [3 9], 'HighBand', [9 18], ...
%       'DisplayFlatFieldSigma', 0);
%
% Important conventions:
%   - Frequencies are expressed in kHz in this function.
%   - /SH_power is already |FFT_t(H)|^2; it must not be squared again.
%   - Bands are selected from |f|, hence both FFT sides are included.
%   - The value at the common boundary belongs to the high band:
%         low:  fLow <= |f| < fSplit
%         high: fSplit <= |f| <= fHigh
%   - The article ratio uses the mean over selected bins, not a mean over
%     all FFT bins after setting unselected bins to zero.
%
% Outputs:
%   01_band_maps.png/.pdf
%   02_<roi>_spectral_redistribution.png/.pdf for every ROI
%   band_ratio_analysis.mat
%   <roi>_waveforms.csv for every ROI
%
% No HoloDoppler function is required at run time. The FFT frequency order,
% two-sided |f| selection, moment-0 reductions, and optional flat-field
% display correction reproduce the corresponding HoloDoppler conventions.

if nargin < 2
    masks = [];
end

ip = inputParser;
ip.FunctionName = mfilename;
addRequired(ip, 'dataPath', @(x) ischar(x) || isstring(x));
addRequired(ip, 'masks');
addParameter(ip, 'OutputDirectory', "", @(x) ischar(x) || isstring(x));
addParameter(ip, 'Dataset', "/SH_power", @(x) ischar(x) || isstring(x));
addParameter(ip, 'LowBand', [3 9], @validBand);
addParameter(ip, 'HighBand', [9 18], @validBand);
addParameter(ip, 'Fs', [], @(x) isempty(x) || (isscalar(x) && isfinite(x) && x > 0));
addParameter(ip, 'FsUnit', "auto", @(x) any(strcmpi(string(x), ["auto","Hz","kHz"])));
addParameter(ip, 'BatchSize', [], @(x) isempty(x) || validPositiveInteger(x));
addParameter(ip, 'BatchStride', [], @(x) isempty(x) || validPositiveInteger(x));
addParameter(ip, 'FirstFrame', 1, @validPositiveInteger);
addParameter(ip, 'DisplayFlatFieldSigma', 0, @(x) isscalar(x) && isfinite(x) && x >= 0);
addParameter(ip, 'DenominatorFloorFraction', 1e-6, ...
    @(x) isscalar(x) && isfinite(x) && x >= 0);
addParameter(ip, 'TimeLimits', [], ...
    @(x) isempty(x) || (isnumeric(x) && numel(x)==2 && x(2)>x(1)));
addParameter(ip, 'SystolicIndex', [], @(x) isempty(x) || validPositiveInteger(x));
addParameter(ip, 'DiastolicIndex', [], @(x) isempty(x) || validPositiveInteger(x));
addParameter(ip, 'SmoothBatches', 3, @validPositiveInteger);
addParameter(ip, 'Visible', "on", @(x) any(strcmpi(string(x), ["on","off"])));
addParameter(ip, 'SaveFIG', false, @(x) islogical(x) && isscalar(x));
addParameter(ip, 'Resolution', 300, @(x) isscalar(x) && isfinite(x) && x >= 72);
parse(ip, dataPath, masks, varargin{:});
o = ip.Results;

dataPath = resolveH5Path(o.dataPath);
dataset = char(o.Dataset);
meta = readHoloDopplerMetadata(dataPath);
info = h5info(dataPath, dataset);
dims = double(info.Dataspace.Size);
if numel(dims) ~= 3
    error('make_band_figures:InvalidDataset', ...
        '%s must have exactly three dimensions; found %s.', ...
        dataset, mat2str(dims));
end
Ny = dims(1);
Nx = dims(2);
Nflat = dims(3);

[fsKHz, fsHz, batchSize, batchStride] = resolveSampling(o, meta);
if mod(Nflat, batchSize) ~= 0
    error('make_band_figures:IncompatibleBatchSize', ...
        ['The third dataset dimension (%d) is not divisible by batchSize ', ...
         '(%d). Supply the correct ''BatchSize''.'], Nflat, batchSize);
end
nBatches = Nflat / batchSize;

fKHz = holoFftFreq(batchSize, 1/fsKHz);
absFKHz = abs(fKHz);
lowMask = absFKHz >= o.LowBand(1) & absFKHz < o.LowBand(2);
highMask = absFKHz >= o.HighBand(1) & absFKHz <= o.HighBand(2);
broadMask = absFKHz >= o.LowBand(1) & absFKHz <= o.HighBand(2);
if ~any(lowMask) || ~any(highMask)
    error('make_band_figures:EmptyBand', ...
        ['At least one selected frequency band contains no FFT bin. ', ...
         'Resolution is %.6g kHz/bin and Nyquist is %.6g kHz.'], ...
        fsKHz/batchSize, fsKHz/2);
end
if any(lowMask & highMask)
    error('make_band_figures:OverlappingBands', ...
        'LowBand and HighBand select overlapping FFT bins.');
end

roiMasks = loadMasks(o.masks, [Ny Nx]);
roiNames = fieldnames(roiMasks);
nRoi = numel(roiNames);

if strlength(string(o.OutputDirectory)) == 0
    [parent, stem] = fileparts(dataPath);
    outDir = fullfile(parent, char(string(stem) + "_article_figures"));
else
    outDir = char(o.OutputDirectory);
end
if ~isfolder(outDir)
    mkdir(outDir);
end

timeSeconds = ((double(o.FirstFrame)-1) + ...
    (0:nBatches-1)*batchStride + (batchSize-1)/2) / fsHz;

mapLFsum = zeros(Ny, Nx, 'double');
mapHFsum = zeros(Ny, Nx, 'double');
mapBroadSum = zeros(Ny, Nx, 'double');
mapRatioSum = zeros(Ny, Nx, 'double');
mapRatioCount = zeros(Ny, Nx, 'double');

roi = struct;
for r = 1:nRoi
    name = roiNames{r};
    roi.(name).spectrumTwoSided = NaN(batchSize, nBatches);
    roi.(name).PL = NaN(1, nBatches);
    roi.(name).PH = NaN(1, nBatches);
    roi.(name).ratioOfBands = NaN(1, nBatches);
    roi.(name).meanPixelRatio = NaN(1, nBatches);
    roi.(name).pixelCount = nnz(roiMasks.(name));
end

fprintf('Reading %d HoloDoppler spectral batches from:\n  %s\n', ...
    nBatches, dataPath);
progressStep = max(1, floor(nBatches/20));

for b = 1:nBatches
    start = [1 1 (b-1)*batchSize + 1];
    count = [Ny Nx batchSize];
    sh = double(h5read(dataPath, dataset, start, count));
    sh(~isfinite(sh) | sh < 0) = NaN;

    PL = meanFinite(sh(:,:,lowMask), 3);
    PH = meanFinite(sh(:,:,highMask), 3);
    PB = meanFinite(sh(:,:,broadMask), 3);

    floorValue = denominatorFloor(PL, o.DenominatorFloorFraction);
    R = PH ./ PL;
    R(~isfinite(R) | PL <= floorValue) = NaN;

    mapLFsum = mapLFsum + replaceNaN(PL, 0);
    mapHFsum = mapHFsum + replaceNaN(PH, 0);
    mapBroadSum = mapBroadSum + replaceNaN(PB, 0);
    goodR = isfinite(R);
    mapRatioSum(goodR) = mapRatioSum(goodR) + R(goodR);
    mapRatioCount(goodR) = mapRatioCount(goodR) + 1;

    for r = 1:nRoi
        name = roiNames{r};
        mask = roiMasks.(name);
        spectrum = spatialMaskMean(sh, mask);
        roi.(name).spectrumTwoSided(:,b) = spectrum(:);
        roi.(name).PL(b) = meanFinite(PL(mask), 1);
        roi.(name).PH(b) = meanFinite(PH(mask), 1);
        roi.(name).ratioOfBands(b) = ...
            roi.(name).PH(b) / roi.(name).PL(b);
        roi.(name).meanPixelRatio(b) = meanFinite(R(mask), 1);
    end

    if mod(b, progressStep)==0 || b==nBatches
        fprintf('  %d/%d batches\n', b, nBatches);
    end
end

maps.broadband = mapBroadSum / nBatches;
maps.low = mapLFsum / nBatches;
maps.high = mapHFsum / nBatches;
maps.ratio = mapRatioSum ./ mapRatioCount;
maps.ratio(mapRatioCount == 0) = NaN;

[fAbsKHz, foldGroups] = absoluteFrequencyGroups(fKHz);
for r = 1:nRoi
    name = roiNames{r};
    roi.(name).spectrumAbsolute = foldSpectrum( ...
        roi.(name).spectrumTwoSided, foldGroups);
    roi.(name).frequencyAbsoluteKHz = fAbsKHz;
end

figMaps = makeMapFigure(maps, roiMasks, o, fsKHz);
exportArticleFigure(figMaps, fullfile(outDir, '01_band_maps'), o);

for r = 1:nRoi
    name = roiNames{r};
    [figRoi, selected] = makeRoiFigure( ...
        roi.(name), name, timeSeconds, o);
    roi.(name).selectedStates = selected;
    safeName = matlab.lang.makeValidName(lower(name));
    exportArticleFigure(figRoi, ...
        fullfile(outDir, sprintf('%02d_%s_spectral_redistribution', ...
        r+1, safeName)), o);

    tableOut = table(timeSeconds(:), roi.(name).PL(:), ...
        roi.(name).PH(:), roi.(name).ratioOfBands(:), ...
        roi.(name).meanPixelRatio(:), ...
        'VariableNames', {'time_s','P_L','P_H', ...
        'ratio_of_spatial_band_means','spatial_mean_pixelwise_ratio'});
    writetable(tableOut, fullfile(outDir, char(string(safeName) + "_waveforms.csv")));
end

results = struct;
results.sourceFile = dataPath;
results.dataset = dataset;
results.metadata = meta;
results.fsKHz = fsKHz;
results.fsHz = fsHz;
results.batchSize = batchSize;
results.batchStride = batchStride;
results.nBatches = nBatches;
results.timeSeconds = timeSeconds;
results.frequencyKHz = fKHz;
results.frequencyAbsoluteKHz = fAbsKHz;
results.lowBandKHz = o.LowBand;
results.highBandKHz = o.HighBand;
results.bandMasks = struct('low',lowMask,'high',highMask,'broad',broadMask);
results.maps = maps;
results.masks = roiMasks;
results.roi = roi;
results.options = o;
save(fullfile(outDir, 'band_ratio_analysis.mat'), 'results', '-v7.3');

fprintf('Figures and numerical results saved in:\n  %s\n', outDir);
end

function tf = validBand(x)
tf = isnumeric(x) && numel(x)==2 && all(isfinite(x)) && ...
    x(1)>=0 && x(2)>x(1);
end

function tf = validPositiveInteger(x)
tf = isnumeric(x) && isscalar(x) && isfinite(x) && x>=1 && x==round(x);
end

function pathOut = resolveH5Path(pathIn)
pathIn = char(pathIn);
if isfile(pathIn)
    pathOut = pathIn;
elseif isfolder(pathIn)
    d = dir(fullfile(pathIn, '**', '*_output.h5'));
    if isempty(d)
        d = dir(fullfile(pathIn, '**', '*.h5'));
    end
    if numel(d) ~= 1
        error('make_band_figures:H5Selection', ...
            'The folder must contain exactly one matching HDF5 file; found %d.', numel(d));
    end
    pathOut = fullfile(d(1).folder, d(1).name);
else
    error('make_band_figures:MissingData', 'Data path not found: %s', pathIn);
end
end

function meta = readHoloDopplerMetadata(h5file)
meta = struct;
try
    raw = h5read(h5file, '/SH_processing');
    if iscell(raw), raw = raw{1}; end
    raw = char(string(raw));
    meta = jsondecode(raw);
catch ME
    warning('make_band_figures:Metadata', ...
        'Could not read /SH_processing (%s). Explicit sampling options may be required.', ...
        ME.message);
end
try
    raw = h5read(h5file, '/SH_axis_convention');
    if iscell(raw), raw = raw{1}; end
    meta.SH_axis_convention = char(string(raw));
catch
end
end

function [fsKHz, fsHz, batchSize, batchStride] = resolveSampling(o, meta)
if isempty(o.Fs)
    if isfield(meta, 'fs_kHz')
        fsKHz = double(meta.fs_kHz);
        fsHz = fsKHz*1000;
    elseif isfield(meta, 'fs_Hz')
        fsHz = double(meta.fs_Hz);
        fsKHz = fsHz/1000;
    else
        error('make_band_figures:MissingFs', ...
            'Sampling frequency is absent. Supply ''Fs'' and optionally ''FsUnit''.');
    end
else
    unit = lower(string(o.FsUnit));
    if unit == "auto"
        if o.Fs > 1000
            unit = "hz";
        else
            unit = "khz";
        end
    end
    if unit == "hz"
        fsHz = double(o.Fs);
        fsKHz = fsHz/1000;
    else
        fsKHz = double(o.Fs);
        fsHz = fsKHz*1000;
    end
end

if isempty(o.BatchSize)
    if isfield(meta, 'batchSize')
        batchSize = double(meta.batchSize);
    else
        error('make_band_figures:MissingBatchSize', ...
            'batchSize is absent. Supply ''BatchSize''.');
    end
else
    batchSize = double(o.BatchSize);
end

if isempty(o.BatchStride)
    if isfield(meta, 'batchStride')
        batchStride = double(meta.batchStride);
    else
        warning('make_band_figures:MissingStride', ...
            'batchStride is absent; using batchSize.');
        batchStride = batchSize;
    end
else
    batchStride = double(o.BatchStride);
end
end

function f = holoFftFreq(n, d)
val = 1/(n*d);
N = floor((n-1)/2)+1;
f = [0:(N-1), -floor(n/2):-1]*val;
end

function masksOut = loadMasks(maskInput, spatialSize)
masksOut = struct;
if isempty(maskInput)
    return
end
if isstruct(maskInput)
    source = maskInput;
elseif ischar(maskInput) || isstring(maskInput)
    pathIn = char(maskInput);
    if ~isfile(pathIn)
        error('make_band_figures:MissingMask', 'Mask file not found: %s', pathIn);
    end
    [~,~,ext] = fileparts(pathIn);
    if strcmpi(ext, '.mat')
        loaded = load(pathIn);
        if isfield(loaded, 'masks') && isstruct(loaded.masks)
            source = loaded.masks;
        else
            source = loaded;
        end
    else
        source = struct('roi', pathIn);
    end
else
    error('make_band_figures:MaskType', ...
        'masks must be empty, a struct, or a mask/MAT-file path.');
end

names = fieldnames(source);
for k = 1:numel(names)
    name = matlab.lang.makeValidName(names{k});
    value = source.(names{k});
    if ischar(value) || isstring(value)
        value = imread(char(value));
    end
    if ~(isnumeric(value) || islogical(value)) || isempty(value)
        warning('make_band_figures:SkippedMask', ...
            'Skipping nonnumeric mask field %s.', names{k});
        continue
    end
    if ndims(value)>2
        value = any(value~=0, 3);
    else
        value = value~=0;
    end
    if isequal(size(value), fliplr(spatialSize)) && ~isequal(spatialSize, fliplr(spatialSize))
        value = value.';
        warning('make_band_figures:TransposedMask', ...
            'Mask %s was transposed to match /SH_power.', names{k});
    end
    if ~isequal(size(value), spatialSize)
        error('make_band_figures:MaskSize', ...
            'Mask %s has size %s; expected %s.', ...
            names{k}, mat2str(size(value)), mat2str(spatialSize));
    end
    if nnz(value)==0
        warning('make_band_figures:EmptyMask', 'Skipping empty mask %s.', names{k});
        continue
    end
    masksOut.(name) = logical(value);
end
end

function out = meanFinite(x, dim)
valid = isfinite(x);
x(~valid) = 0;
n = sum(valid, dim);
out = sum(x, dim)./n;
out(n==0) = NaN;
end

function out = spatialMaskMean(cube, mask)
[n1,n2,n3] = size(cube);
flat = reshape(cube, n1*n2, n3);
out = meanFinite(flat(mask(:),:), 1).';
end

function y = replaceNaN(x, value)
y = x;
y(~isfinite(y)) = value;
end

function floorValue = denominatorFloor(PL, fraction)
v = PL(isfinite(PL) & PL>0);
if isempty(v) || fraction==0
    floorValue = 0;
else
    floorValue = fraction*median(v);
end
end

function [fAbs, groups] = absoluteFrequencyGroups(f)
fAbs = unique(abs(f));
fAbs = sort(fAbs(:));
groups = cell(numel(fAbs),1);
tol = max(eps(max(abs(f)))*8, eps);
for k = 1:numel(fAbs)
    groups{k} = find(abs(abs(f)-fAbs(k)) <= tol);
end
end

function folded = foldSpectrum(twoSided, groups)
folded = NaN(numel(groups), size(twoSided,2));
for k = 1:numel(groups)
    folded(k,:) = meanFinite(twoSided(groups{k},:), 1);
end
end

function fig = makeMapFigure(maps, masks, o, fsKHz)
fig = figure('Color','w','Visible',char(o.Visible), ...
    'Name','Band-ratio spatial maps','Position',[80 80 1500 420]);
tl = tiledlayout(fig,1,4,'TileSpacing','compact','Padding','compact');
items = {maps.broadband, maps.ratio, maps.low, maps.high};
titles = {sprintf('Broadband %.1f--%.1f kHz',o.LowBand(1),o.HighBand(2)), ...
    sprintf('Ratio %.1f--%.1f / %.1f--%.1f kHz', ...
    o.HighBand(1),o.HighBand(2),o.LowBand(1),o.LowBand(2)), ...
    sprintf('Low band %.1f--%.1f kHz',o.LowBand), ...
    sprintf('High band %.1f--%.1f kHz',o.HighBand)};
for k = 1:4
    ax = nexttile(tl,k);
    img = displayFlatField(items{k}, o.DisplayFlatFieldSigma);
    imagesc(ax,img); axis(ax,'image'); axis(ax,'off');
    colormap(ax,'gray'); applyRobustCLim(ax,img,[1 99]);
    title(ax,titles{k},'Interpreter','none');
    if k==2 && ~isempty(fieldnames(masks))
        hold(ax,'on');
        names = fieldnames(masks);
        colors = lines(numel(names));
        handles = gobjects(numel(names),1);
        for r=1:numel(names)
            [~, handles(r)] = contour(ax,masks.(names{r}),[0.5 0.5], ...
                'Color',colors(r,:),'LineWidth',1.2);
        end
        legend(ax,handles,strrep(names,'_','\_'),'Location','southoutside');
    end
end
title(tl,sprintf('HoloDoppler spectral maps, f_s = %.3g kHz',fsKHz), ...
    'FontWeight','bold');
end

function img = displayFlatField(img, sigma)
if sigma<=0
    return
end
if exist('imgaussfilt','file')~=2
    warning('make_band_figures:NoImageToolbox', ...
        'imgaussfilt unavailable; display flat-field correction skipped.');
    return
end
finite = isfinite(img);
work = img;
fill = median(work(finite));
work(~finite)=fill;
background = imgaussfilt(work,sigma);
corrected = work./background;
scale = sum(work(finite))/sum(corrected(finite));
img = corrected*scale;
img(~finite)=NaN;
end

function [fig, selected] = makeRoiFigure(r, roiName, t, o)
f = r.frequencyAbsoluteKHz;
S = r.spectrumAbsolute;
validFreq = f>=o.LowBand(1) & f<=o.HighBand(2);
validTime = true(size(t));
if ~isempty(o.TimeLimits)
    validTime = t>=o.TimeLimits(1) & t<=o.TimeLimits(2);
end
indices = find(validTime & isfinite(r.meanPixelRatio));
if isempty(indices)
    error('make_band_figures:NoValidRoiTime', ...
        'ROI %s has no valid time point in the requested range.',roiName);
end
smoothed = movmean(r.meanPixelRatio,o.SmoothBatches,'omitnan');
if isempty(o.SystolicIndex)
    [~,ii] = max(smoothed(indices)); highIdx = indices(ii);
    highLabel = 'High-ratio state';
else
    highIdx = o.SystolicIndex;
    checkIndex(highIdx,numel(t),'SystolicIndex');
    highLabel = 'User systolic state';
end
if isempty(o.DiastolicIndex)
    [~,ii] = min(smoothed(indices)); lowIdx = indices(ii);
    lowLabel = 'Low-ratio state';
else
    lowIdx = o.DiastolicIndex;
    checkIndex(lowIdx,numel(t),'DiastolicIndex');
    lowLabel = 'User diastolic state';
end
selected = struct('highOrSystolicIndex',highIdx, ...
    'lowOrDiastolicIndex',lowIdx,'highTimeSeconds',t(highIdx), ...
    'lowTimeSeconds',t(lowIdx),'automatic', ...
    isempty(o.SystolicIndex)&&isempty(o.DiastolicIndex));

fig = figure('Color','w','Visible',char(o.Visible), ...
    'Name',[roiName ' spectral redistribution'], ...
    'Position',[80 80 1250 820]);
tl = tiledlayout(fig,2,2,'TileSpacing','compact','Padding','compact');

ax1=nexttile(tl,1);
SdB=10*log10(max(S,realmin('double')));
ref=percentileValue(SdB(validFreq,validTime),99);
imagesc(ax1,t(validTime),f(validFreq),SdB(validFreq,validTime)-ref);
axis(ax1,'xy'); colormap(ax1,turbo); colorbar(ax1);
caxis(ax1,[-35 0]); xlabel(ax1,'Time (s)'); ylabel(ax1,'|f| (kHz)');
title(ax1,'ROI Doppler spectrogram (dB)');
hold(ax1,'on'); yline(ax1,o.LowBand(1),'w:');
yline(ax1,o.LowBand(2),'w--'); yline(ax1,o.HighBand(2),'w:');

ax2=nexttile(tl,2);
sHigh=normalizeSpectrum(S(:,highIdx),f,o);
sLow=normalizeSpectrum(S(:,lowIdx),f,o);
plot(ax2,f(validFreq),sHigh(validFreq),'r-','LineWidth',1.8); hold(ax2,'on');
plot(ax2,f(validFreq),sLow(validFreq),'b-','LineWidth',1.8);
xline(ax2,o.LowBand(2),'k--'); grid(ax2,'on');
xlabel(ax2,'|f| (kHz)'); ylabel(ax2,'Normalized spectral density');
title(ax2,'Spectral redistribution');
legend(ax2,{sprintf('%s, t=%.3f s',highLabel,t(highIdx)), ...
    sprintf('%s, t=%.3f s',lowLabel,t(lowIdx)), ...
    sprintf('Split %.1f kHz',o.LowBand(2))},'Location','best');

ax3=nexttile(tl,3);
plot(ax3,t,normalizeMean(r.PL),'b-','LineWidth',1.4); hold(ax3,'on');
plot(ax3,t,normalizeMean(r.PH),'r-','LineWidth',1.4);
xline(ax3,t(highIdx),'r:'); xline(ax3,t(lowIdx),'b:'); grid(ax3,'on');
xlabel(ax3,'Time (s)'); ylabel(ax3,'Band power / temporal mean');
title(ax3,'Opposite band modulations');
legend(ax3,{sprintf('P_L %.1f--%.1f kHz',o.LowBand), ...
    sprintf('P_H %.1f--%.1f kHz',o.HighBand)},'Location','best');

ax4=nexttile(tl,4);
plot(ax4,t,r.meanPixelRatio,'k-','LineWidth',1.4); hold(ax4,'on');
plot(ax4,t(highIdx),r.meanPixelRatio(highIdx),'ro','MarkerFaceColor','r');
plot(ax4,t(lowIdx),r.meanPixelRatio(lowIdx),'bo','MarkerFaceColor','b');
grid(ax4,'on'); xlabel(ax4,'Time (s)'); ylabel(ax4,'<P_H/P_L>_{ROI}');
title(ax4,'Spatially averaged pixelwise ratio');
if ~isempty(o.TimeLimits)
    xlim(ax3,o.TimeLimits); xlim(ax4,o.TimeLimits);
end
title(tl,sprintf('%s (%d pixels)',strrep(roiName,'_',' '),r.pixelCount), ...
    'FontWeight','bold');
end

function y = normalizeSpectrum(y, f, o)
mask = f>=o.LowBand(1) & f<=o.HighBand(2) & isfinite(y);
area = trapz(f(mask),y(mask));
if isfinite(area) && area>0
    y=y/area;
end
end

function y = normalizeMean(x)
m=meanFinite(x(isfinite(x)),2);
if isempty(m) || ~isfinite(m) || m==0
    y=x;
else
    y=x/m;
end
end

function checkIndex(idx,n,label)
if idx<1 || idx>n
    error('make_band_figures:StateIndex', '%s=%d is outside 1:%d.',label,idx,n);
end
end

function applyRobustCLim(ax,img,p)
v=img(isfinite(img));
if isempty(v), return, end
lo=percentileValue(v,p(1)); hi=percentileValue(v,p(2));
if isfinite(lo)&&isfinite(hi)&&hi>lo
    caxis(ax,[lo hi]);
end
end

function q = percentileValue(x,p)
x=sort(x(isfinite(x)));
if isempty(x), q=NaN; return, end
position=1+(numel(x)-1)*p/100;
lo=floor(position); hi=ceil(position);
if lo==hi
    q=x(lo);
else
    q=x(lo)+(position-lo)*(x(hi)-x(lo));
end
end

function exportArticleFigure(fig, basePath, o)
pngPath=[basePath '.png']; pdfPath=[basePath '.pdf'];
try
    exportgraphics(fig,pngPath,'Resolution',o.Resolution);
    exportgraphics(fig,pdfPath,'ContentType','image','Resolution',o.Resolution);
catch
    print(fig,pngPath,'-dpng',sprintf('-r%d',round(o.Resolution)));
    print(fig,pdfPath,'-dpdf',sprintf('-r%d',round(o.Resolution)));
end
if o.SaveFIG
    savefig(fig,[basePath '.fig']);
end
end
