classdef ExploreSHbroadening < handle

properties

    % Figure and axes
    fig
    axImage
    axPlot
    axFits

    % Input and processed data
    SH
    SH_processed
    avgImage

    % Frequencies: all expressed in kHz
    fs
    f1
    f2

    % Optional LF/HF boundaries, also in kHz
    fi1 = []
    fi2 = []

    % ROIs and imported masks
    rois = {}
    masks = {}
    colors = {}
    maskOverlays = {}
    roiListeners = {}

    % UI controls
    panel
    btnGroup
    imageSelector
    loglogCheckbox

    % Background images
    imageMaps = struct()
    imageMapNames = {}
    hImage

    % Reference spectrum and fit results
    outerReference
    fitResults = {}
    fitGoodness = {}

end

properties (Access = private)

    isUpdatingSpectrum = false
    isClosing = false

    spectrumAxesLink = []

end

methods

    function obj = ExploreSHbroadening( ...
            SH, fs, f1, f2, imageMaps, fi1, fi2)

        if nargin < 5 || isempty(imageMaps)
            imageMaps = struct();
        end

        if nargin < 6
            fi1 = [];
        end

        if nargin < 7
            fi2 = [];
        end

        validateattributes(SH, {'numeric'}, ...
            {'nonempty'}, mfilename, 'SH');

        assert(ndims(SH) <= 3 && size(SH, 3) >= 6, ...
        'SH must contain at least six spectral samples.');

        validateattributes(fs, {'numeric'}, ...
            {'scalar', 'real', 'finite', 'positive'}, ...
            mfilename, 'fs');

        validateattributes(f1, {'numeric'}, ...
            {'scalar', 'real', 'finite', 'positive'}, ...
            mfilename, 'f1');

        validateattributes(f2, {'numeric'}, ...
            {'scalar', 'real', 'finite', 'positive'}, ...
            mfilename, 'f2');

        assert(f1 < f2 && f2 <= fs / 2, ...
        'Expected 0 < f1 < f2 <= fs/2.');

        obj.SH = SH;
        obj.SH_processed = abs(SH);

        obj.fs = double(fs);
        obj.f1 = double(f1);
        obj.f2 = double(f2);

        obj.validateFrequencyBands(fi1, fi2);

        obj.fi1 = fi1;
        obj.fi2 = fi2;

        obj.imageMaps = obj.filterImageMaps(imageMaps);

        obj.updateAverageImage();
        obj.createUI();

    end

    function createUI(obj)

        obj.fig = figure( ...
            'Name', 'Explore SH Broadening', ...
            'NumberTitle', 'off', ...
            'Color', 'white', ...
            'Position', [100, 100, 1400, 850], ...
            'CloseRequestFcn', @obj.closeFigure);

        % Background image
        obj.axImage = axes( ...
            'Parent', obj.fig, ...
            'Units', 'normalized', ...
            'Position', [0.05, 0.44, 0.43, 0.50]);

        % Upper spectrum panel
        obj.axPlot = axes( ...
            'Parent', obj.fig, ...
            'Units', 'normalized', ...
            'Position', [0.57, 0.57, 0.40, 0.35]);

        % Lower fit panel
        obj.axFits = axes( ...
            'Parent', obj.fig, ...
            'Units', 'normalized', ...
            'Position', [0.57, 0.12, 0.40, 0.32]);

        % Control panel
        obj.panel = uipanel( ...
            'Parent', obj.fig, ...
            'Title', 'Display options', ...
            'Units', 'normalized', ...
            'Position', [0.04, 0.05, 0.45, 0.32]);

        obj.btnGroup = uibuttongroup( ...
            'Parent', obj.panel, ...
            'Units', 'normalized', ...
            'Position', [0.02, 0.43, 0.44, 0.54], ...
            'SelectionChangedFcn', ...
            @(~, ~) obj.changeDisplayOption());

        options = { ...
                       'abs', 'Magnitude'; ...
                       'abs2', 'Magnitude Squared'; ...
                       'real', 'Real Part'; ...
                       'imag', 'Imaginary Part'; ...
                       'angle', 'Argument (rad)'};

        for k = 1:size(options, 1)

            uicontrol( ...
                'Parent', obj.btnGroup, ...
                'Style', 'radiobutton', ...
                'String', options{k, 2}, ...
                'Tag', options{k, 1}, ...
                'Units', 'normalized', ...
                'Position', ...
                [0.04, 0.81 - 0.18 * (k - 1), 0.94, 0.16]);

        end

        obj.btnGroup.SelectedObject = ...
            findobj(obj.btnGroup, 'Tag', 'abs');

        % Background image selection
        uicontrol( ...
            'Parent', obj.panel, ...
            'Style', 'text', ...
            'String', 'Displayed image', ...
            'Units', 'normalized', ...
            'Position', [0.03, 0.31, 0.42, 0.08], ...
            'HorizontalAlignment', 'left');

        obj.imageMapNames = [ ...
                                 {'Moment 0 - current display mode'}; ...
                                 fieldnames(obj.imageMaps)];

        obj.imageSelector = uicontrol( ...
            'Parent', obj.panel, ...
            'Style', 'popupmenu', ...
            'String', obj.imageMapNames, ...
            'Value', 1, ...
            'Units', 'normalized', ...
            'Position', [0.03, 0.18, 0.42, 0.12], ...
            'Callback', @(~, ~) obj.updateImageDisplay());

        % Log-log display
        obj.loglogCheckbox = uicontrol( ...
            'Parent', obj.panel, ...
            'Style', 'checkbox', ...
            'String', 'Log-log (positive frequencies)', ...
            'Value', false, ...
            'Units', 'normalized', ...
            'Position', [0.03, 0.04, 0.44, 0.10], ...
            'Callback', @(~, ~) obj.spectrum_plotting());

        % Action buttons
        buttonNames = { ...
                           'Select ROI', ...
                           'Load PNG Mask', ...
                           'Save Spectra', ...
                       'Clear ROIs'};

        callbacks = { ...
                         @(~, ~) obj.roiNew(), ...
                         @(~, ~) obj.loadPNGMask(), ...
                         @(~, ~) obj.saveSpectra(), ...
                         @(~, ~) obj.clearROIs()};

        for k = 1:numel(buttonNames)

            uicontrol( ...
                'Parent', obj.panel, ...
                'Style', 'pushbutton', ...
                'String', buttonNames{k}, ...
                'Units', 'normalized', ...
                'Position', ...
                [0.51, 0.76 - 0.23 * (k - 1), 0.45, 0.20], ...
                'Callback', callbacks{k});

        end

        obj.updateImageDisplay();
        obj.spectrum_plotting();

    end

    function changeDisplayOption(obj)

        if obj.isClosing
            return;
        end

        selectedOption = obj.btnGroup.SelectedObject.Tag;

        switch selectedOption

            case 'abs'
                obj.SH_processed = abs(obj.SH);

            case 'abs2'
                obj.SH_processed = abs(obj.SH) .^ 2;

            case 'real'
                obj.SH_processed = real(obj.SH);

            case 'imag'
                obj.SH_processed = imag(obj.SH);

            case 'angle'
                obj.SH_processed = angle(obj.SH);

        end

        obj.updateAverageImage();
        obj.updateImageDisplay();
        obj.spectrum_plotting();

    end

    function updateAverageImage(obj)

        obj.avgImage = moment0( ...
            obj.SH_processed, ...
            obj.f1, obj.f2, obj.fs, ...
            size(obj.SH_processed, 3), 0);

    end

    function validateFrequencyBands(obj, fi1, fi2)

        if ~isempty(fi1)

            validateattributes(fi1, {'numeric'}, ...
                {'scalar', 'real', 'finite'});

            assert(obj.f1 <= fi1 && fi1 <= obj.f2, ...
            'Expected f1 <= fi1 <= f2.');

        end

        if ~isempty(fi2)

            validateattributes(fi2, {'numeric'}, ...
                {'scalar', 'real', 'finite'});

            assert(obj.f1 <= fi2 && fi2 <= obj.f2, ...
            'Expected f1 <= fi2 <= f2.');

        end

        if ~isempty(fi1) && ~isempty(fi2)

            assert(fi1 <= fi2, ...
            'Expected fi1 <= fi2.');

        end

    end

    function setFrequencyBands(obj, fi1, fi2)

        obj.validateFrequencyBands(fi1, fi2);

        obj.fi1 = fi1;
        obj.fi2 = fi2;

        obj.spectrum_plotting();

    end

    function maps = filterImageMaps(obj, maps)

        assert(isstruct(maps) && isscalar(maps), ...
            ['imageMaps must be a scalar structure. ' ...
         'Convert the getImages cell array in AdvancedPanel.']);

        excludedNames = {'broadening'};

        expectedSize = [ ...
                            size(obj.SH, 1), size(obj.SH, 2)];

        names = fieldnames(maps);

        for k = 1:numel(names)

            name = names{k};

            if any(strcmpi(name, excludedNames))

                maps = rmfield(maps, name);
                continue;

            end

            img = maps.(name);

            isCompatible = ...
                (isnumeric(img) || islogical(img)) ...
                && isreal(img) ...
                && ismatrix(img) ...
                && ~isempty(img) ...
                && isequal(size(img), expectedSize);

            if ~isCompatible

                warning('ExploreSHbroadening:SkippedImage', ...
                    ['Image "%s" ignored: expected a real matrix ' ...
                 'of size [%d %d]; received class "%s", size %s.'], ...
                    name, expectedSize(1), expectedSize(2), ...
                    class(img), mat2str(size(img)));

                maps = rmfield(maps, name);

            end

        end

    end

    function setImageMaps(obj, maps)

        maps = obj.filterImageMaps(maps);

        previousName = '';

        if ~isempty(obj.imageSelector) ...
                && isgraphics(obj.imageSelector)

            index = obj.imageSelector.Value;

            if index > 1 && index <= numel(obj.imageMapNames)
                previousName = obj.imageMapNames{index};
            end

        end

        obj.imageMaps = maps;

        obj.imageMapNames = [ ...
                                 {'Moment 0 - current display mode'}; ...
                                 fieldnames(maps)];

        selectedIndex = 1;

        if ~isempty(previousName)

            index = find(strcmp( ...
                obj.imageMapNames, previousName), 1);

            if ~isempty(index)
                selectedIndex = index;
            end

        end

        if ~isempty(obj.imageSelector) ...
                && isgraphics(obj.imageSelector)

            set(obj.imageSelector, ...
                'Value', 1, ...
                'String', obj.imageMapNames);

            obj.imageSelector.Value = selectedIndex;

        end

        obj.updateImageDisplay();

    end

    function updateImageDisplay(obj)

        if obj.isClosing ...
                || isempty(obj.axImage) ...
                || ~isgraphics(obj.axImage)

            return;

        end

        selectedIndex = obj.imageSelector.Value;

        if selectedIndex == 1

            img = obj.avgImage;
            imageTitle = 'Moment 0 - current display mode';

        else

            name = obj.imageMapNames{selectedIndex};

            img = obj.imageMaps.(name);
            imageTitle = name;

        end

        % Preserve the square display geometry used by ROI masks.
        M = max(size(obj.SH, 1), size(obj.SH, 2));

        displayImage = imresize(double(img), [M, M]);

        if isempty(obj.hImage) || ~isgraphics(obj.hImage)

            wasHeld = ishold(obj.axImage);
            hold(obj.axImage, 'on');

            obj.hImage = imagesc(obj.axImage, displayImage);

            if ~wasHeld
                hold(obj.axImage, 'off');
            end

        else

            set(obj.hImage, ...
                'CData', displayImage, ...
                'XData', [1, M], ...
                'YData', [1, M]);

        end

        uistack(obj.hImage, 'bottom');

        set(obj.axImage, ...
            'YDir', 'reverse', ...
            'CLimMode', 'auto');

        axis(obj.axImage, 'image');

        xlim(obj.axImage, [0.5, M + 0.5]);
        ylim(obj.axImage, [0.5, M + 0.5]);

        colormap(obj.axImage, 'gray');

        title(obj.axImage, imageTitle, ...
            'Interpreter', 'none');

    end

    function color = getROIColor(obj, index)

        if index <= numel(obj.colors) ...
                && ~isempty(obj.colors{index})

            color = obj.colors{index};
            return;

        end

        palette = lines(7);

        color = palette( ...
            mod(index - 1, size(palette, 1)) + 1, :);

    end

    function roiNew(obj, manual)

        if obj.isClosing
            return;
        end

        if nargin < 2
            manual = false;
        end

        index = numel(obj.rois) + 1;
        roiColor = obj.getROIColor(index);

        if manual

            roi = drawfreehand(obj.axImage, ...
                'Color', roiColor, ...
                'FaceAlpha', 0.2, ...
                'DrawingArea', 'unlimited', ...
                'InteractionsAllowed', 'translate');

        else

            roi = drawrectangle(obj.axImage, ...
                'Color', roiColor, ...
                'FaceAlpha', 0.2, ...
                'DrawingArea', 'unlimited', ...
                'InteractionsAllowed', 'translate');

        end

        if obj.isClosing || isempty(roi) || ~isvalid(roi)
            return;
        end

        obj.rois{index} = roi;
        obj.colors{index} = roiColor;
        obj.masks{index} = [];
        obj.maskOverlays{index} = [];

        obj.roiListeners{index} = { ...
                                       addlistener(roi, 'MovingROI', ...
                                       @(~, ~) obj.spectrum_plotting()), ...
                                       addlistener(roi, 'ROIMoved', ...
                                       @(~, ~) obj.spectrum_plotting())};

        obj.spectrum_plotting();

    end

    function updateMasks(obj)

        nROI = numel(obj.rois);

        Ny = size(obj.SH_processed, 1);
        Nx = size(obj.SH_processed, 2);

        M = max(Ny, Nx);

        if numel(obj.masks) < nROI
            obj.masks{nROI} = [];
        end

        for k = 1:nROI

            roi = obj.rois{k};

            % Imported mask: no interactive ROI to update.
            if isnumeric(roi) && isscalar(roi) && roi == 1
                continue;
            end

            obj.masks{k} = [];

            if isempty(roi) || ~isvalid(roi)
                continue;
            end

            displayMask = createMask(roi, M, M);

            obj.masks{k} = imresize( ...
                displayMask, [Ny, Nx], 'nearest') > 0;

        end

    end

    function loadPNGMask(obj)

        if obj.isClosing
            return;
        end

        [filename, pathname] = uigetfile( ...
            {'*.png;*.bmp;*.jpg;*.tif', 'Image files'; ...
             '*.*', 'All files'}, ...
        'Select a mask image');

        if isequal(filename, 0) || obj.isClosing
            return;
        end

        try

            [maskImage, map] = imread( ...
                fullfile(pathname, filename));

            if ~isempty(map)

                maskImage = ind2gray(maskImage, map);

            elseif size(maskImage, 3) == 3

                maskImage = rgb2gray(maskImage);

            end

            if islogical(maskImage)
                maskBinary = maskImage;
            else
                maskBinary = imbinarize(maskImage);
            end

            Ny = size(obj.SH_processed, 1);
            Nx = size(obj.SH_processed, 2);
            M = max(Ny, Nx);

            maskBinary = imresize( ...
                maskBinary, [Ny, Nx], 'nearest') > 0;

            assert(any(maskBinary(:)), ...
            'The imported mask is empty.');

            index = numel(obj.rois) + 1;
            roiColor = obj.getROIColor(index);

            displayMask = imresize( ...
                maskBinary, [M, M], 'nearest');

            overlay = repmat( ...
                reshape(roiColor, 1, 1, 3), M, M);

            wasHeld = ishold(obj.axImage);
            hold(obj.axImage, 'on');

            h = image(obj.axImage, ...
                'CData', overlay, ...
                'AlphaData', 0.3 * double(displayMask), ...
                'HitTest', 'off');

            if ~wasHeld
                hold(obj.axImage, 'off');
            end

            obj.rois{index} = 1;
            obj.masks{index} = maskBinary;
            obj.colors{index} = roiColor;
            obj.roiListeners{index} = {};
            obj.maskOverlays{index} = h;

            obj.spectrum_plotting();

        catch ME

            errordlg(ME.message, 'Mask import error');

        end

    end

    function deleteROIListeners(obj)

        for k = 1:numel(obj.roiListeners)

            listeners = obj.roiListeners{k};

            for j = 1:numel(listeners)

                listener = listeners{j};

                if ~isempty(listener) && isvalid(listener)
                    delete(listener);
                end

            end

        end

        obj.roiListeners = {};

    end

    function clearROIs(obj)

        if obj.isClosing
            return;
        end

        obj.deleteROIListeners();

        for k = 1:numel(obj.rois)

            roi = obj.rois{k};

            if isnumeric(roi)
                continue;
            end

            if ~isempty(roi) && isvalid(roi)
                delete(roi);
            end

        end

        for k = 1:numel(obj.maskOverlays)

            h = obj.maskOverlays{k};

            if ~isempty(h) && isgraphics(h)
                delete(h);
            end

        end

        obj.rois = {};
        obj.masks = {};
        obj.colors = {};
        obj.maskOverlays = {};

        obj.fitResults = {};
        obj.fitGoodness = {};

        obj.spectrum_plotting();

    end

    function spectrum_plotting(obj)

        % Prevent nested redraws.
        if obj.isClosing || obj.isUpdatingSpectrum
            return;
        end

        axTop = obj.axPlot;
        axBottom = obj.axFits;

        if isempty(axTop) || isempty(axBottom) ...
                || ~isgraphics(axTop) || ~isgraphics(axBottom)

            return;

        end

        obj.isUpdatingSpectrum = true;

        updateCleanup = onCleanup( ...
            @() obj.finishSpectrumUpdate());

        % Delete our own link before resetting the axes.
        obj.unlinkSpectrumAxes();

        legend(axTop, 'off');
        legend(axBottom, 'off');

        cla(axTop, 'reset');
        cla(axBottom, 'reset');

        hold(axTop, 'on');
        hold(axBottom, 'on');

        obj.fitResults = cell(1, numel(obj.rois));
        obj.fitGoodness = cell(1, numel(obj.rois));

        nFreq = size(obj.SH_processed, 3);

        % Display mode
        selectedOption = obj.btnGroup.SelectedObject.Tag;

        isMagnitude = ismember(selectedOption, {'abs', 'abs2'});
        isAngle = strcmp(selectedOption, 'angle');

        if isMagnitude

            obj.loglogCheckbox.Enable = 'on';

        else

            obj.loglogCheckbox.Value = false;
            obj.loglogCheckbox.Enable = 'off';

        end

        useLogLog = ...
            isMagnitude && logical(obj.loglogCheckbox.Value);

        if useLogLog

            plotOrdinate = @(v) 10 .^ v;
            labelText = 'S';

        elseif isMagnitude

            plotOrdinate = @(v) v;
            labelText = 'log_{10} S';

        elseif isAngle

            plotOrdinate = @(v) v;
            labelText = 'Phase (rad)';

        else

            plotOrdinate = @(v) v;
            labelText = 'S';

        end

        % Axes appearance
        title(axTop, 'Signal Spectrum');
        title(axBottom, 'Aliased pseudo-Voigt fits');

        xlabel(axTop, 'Frequency (kHz)');
        xlabel(axBottom, 'Frequency (kHz)');

        ylabel(axTop, labelText);
        ylabel(axBottom, labelText);

        set([axTop, axBottom], ...
            'FontSize', 11, ...
            'LineWidth', 1, ...
            'TickDir', 'out', ...
            'Box', 'on', ...
            'Layer', 'top', ...
            'SortMethod', 'childorder', ...
            'GridAlpha', 0.18, ...
            'GridColor', [0.35, 0.35, 0.35]);

        grid(axTop, 'on');
        grid(axBottom, 'on');

        if useLogLog

            minimumFrequency = obj.fs / nFreq;

            set([axTop, axBottom], ...
                'XScale', 'log', ...
                'YScale', 'log', ...
                'XTickMode', 'auto', ...
                'YTickMode', 'auto', ...
                'XMinorGrid', 'on', ...
                'YMinorGrid', 'on', ...
                'MinorGridAlpha', 0.08);

            set([axTop, axBottom], ...
                'XLim', [minimumFrequency, obj.fs / 2]);

        else

            set([axTop, axBottom], ...
                'XScale', 'linear', ...
                'YScale', 'linear', ...
                'XMinorGrid', 'off', ...
                'YMinorGrid', 'off');

            set([axTop, axBottom], ...
                'XLim', [-obj.fs / 2, obj.fs / 2]);

            ticks = unique([ ...
                                -obj.f2, -obj.f1, 0, obj.f1, obj.f2]);

            xticks(axTop, ticks);
            xticks(axBottom, ticks);

        end

        if isempty(obj.rois)

            linkaxes([axTop, axBottom], 'xy');

            obj.shadeFrequencyBands(axTop);
            obj.shadeFrequencyBands(axBottom);

            return;

        end

        % Masks and reference
        obj.updateMasks();

        if isMagnitude

            obj.makeOuterDiaphragmReference();
            reference = obj.outerReference(:);

            assert(numel(reference) == nFreq, ...
            'The reference spectrum has an incompatible size.');

        else

            reference = [];

        end

        % Frequency coordinates, in kHz
        axisFrequency = ...
            (-floor(nFreq / 2):ceil(nFreq / 2) - 1).' ...
            * obj.fs / nFreq;

        bandMask = ...
            abs(axisFrequency) >= obj.f1 ...
            & abs(axisFrequency) <= obj.f2;

        if useLogLog

            xFit = logspace( ...
                log10(obj.fs / nFreq), ...
                log10(obj.fs / 2), ...
                3000).';

        else

            xFit = linspace( ...
                -obj.fs / 2, obj.fs / 2, 3000).';

        end

        fitDisplayMask = ...
            abs(xFit) >= obj.f1 ...
            & abs(xFit) <= obj.f2;

        spatialSpectra = reshape( ...
            obj.SH_processed, [], nFreq);

        spectrumHandles = gobjects(0, 1);
        fitHandles = gobjects(0, 1);

        topFitHandles = gobjects(0, 1);
        topFitHaloHandles = gobjects(0, 1);

        % Process ROIs
        for k = 1:numel(obj.rois)

            if k > numel(obj.masks)
                continue;
            end

            mask = obj.masks{k};

            if isempty(mask) || ~any(mask(:))
                continue;
            end

            roiColor = obj.getROIColor(k);

            roi = obj.rois{k};

            if ~isnumeric(roi) ...
                    && ~isempty(roi) && isvalid(roi)

                roi.Color = roiColor;

            end

            spectrum = double(mean( ...
                spatialSpectra(mask(:), :), 1).');

            % Normalize and prepare fitting ordinates.
            if isMagnitude

                normalizedSpectrum = NaN(nFreq, 1);

                validReference = ...
                    isfinite(reference) & reference > 0;

                normalizedSpectrum(validReference) = ...
                    spectrum(validReference) ...
                    ./ reference(validReference);

                spectrumCentered = fftshift(normalizedSpectrum);

                % Fit input remains log10(S) in both display modes.
                displayedSpectrum = NaN(nFreq, 1);

                validDisplay = ...
                    isfinite(spectrumCentered) ...
                    & spectrumCentered > 0;

                displayedSpectrum(validDisplay) = ...
                    log10(spectrumCentered(validDisplay));

            else

                spectrumCentered = fftshift(spectrum);
                displayedSpectrum = spectrumCentered;

            end

            % Plot noisy samples.
            plottedSpectrum = plotOrdinate(displayedSpectrum);

            if useLogLog

                invalid = ...
                    axisFrequency <= 0 ...
                    | ~isfinite(plottedSpectrum) ...
                    | plottedSpectrum <= 0;

                plottedSpectrum(invalid) = NaN;

            end

            spectrumHandles(end + 1, 1) = plot( ...
                axTop, axisFrequency, plottedSpectrum, ...
                'LineStyle', '-', ...
                'Marker', 'none', ...
                'LineWidth', 0.5, ...
                'Color', roiColor, ...
                'DisplayName', sprintf('ROI %d', k));

            if ~isMagnitude
                continue;
            end

            % Fit log10(S), independently of the display mode.
            validFit = ...
                bandMask & isfinite(displayedSpectrum);

            if nnz(validFit) < 6

                warning( ...
                    'ExploreSHbroadening:InsufficientFitData', ...
                    'ROI %d: fewer than six finite fitting samples.', ...
                    k);

                continue;

            end

            try

                % No automatic plotting from the fitting function.
                [fitObj, gof] = fit_spectrum_gaussian( ...
                    axisFrequency, displayedSpectrum, obj.f1, obj.f2, ...
                    Fs = obj.fs, ...
                    plot = true, ...
                    verbose = true);

                obj.fitResults{k} = fitObj;
                obj.fitGoodness{k} = gof;

                fitY = fitObj.evaluate(xFit);
                fitYBottom = plotOrdinate(fitY);

                % Remove invalid displayed ordinates.
                invalid = ~isfinite(fitYBottom);

                if useLogLog

                    invalid = invalid ...
                        | xFit <= 0 ...
                        | fitYBottom <= 0;

                end

                fitYBottom(invalid) = NaN;

                % Upper panel: fitted frequency bands only.
                fitYTop = fitYBottom;
                fitYTop(~fitDisplayMask) = NaN;

                % White outline behind the colored fit.
                topFitHaloHandles(end + 1, 1) = plot( ...
                    axTop, xFit, fitYTop, ...
                    'Color', [1, 1, 1], ...
                    'LineStyle', '-', ...
                    'LineWidth', 5, ...
                    'HandleVisibility', 'off', ...
                    'HitTest', 'off');

                % Colored fit, matching the ROI.
                topFitHandles(end + 1, 1) = plot( ...
                    axTop, xFit, fitYTop, ...
                    'Color', roiColor, ...
                    'LineStyle', '-', ...
                    'LineWidth', 2.8, ...
                    'HandleVisibility', 'off', ...
                    'HitTest', 'off');

                % Lower panel: full model, including excluded bands.
                fitHandles(end + 1, 1) = plot( ...
                    axBottom, xFit, fitYBottom, ...
                    'Color', roiColor, ...
                    'LineStyle', '-', ...
                    'LineWidth', 2, ...
                    'DisplayName', sprintf( ...
                    'ROI %d | w = %.2f kHz | R^2 = %.3f', ...
                    k, fitObj.w, gof.rsquare));

            catch ME

                warning('ExploreSHbroadening:FitFailed', ...
                    'ROI %d: %s', k, ME.message);

            end

        end

        % Update graphics without processing queued callbacks.
        drawnow nocallbacks;

        if obj.isClosing ...
                || ~isgraphics(axTop) ...
                || ~isgraphics(axBottom)

            return;

        end

        % Synchronize completed plots before adding shading.
        linkaxes([axTop, axBottom], 'xy');

        % Background bands.
        obj.shadeFrequencyBands(axTop);
        obj.shadeFrequencyBands(axBottom);

        % Bring all upper-panel fits above all noisy samples.
        validHalos = topFitHaloHandles( ...
            isgraphics(topFitHaloHandles, 'line'));

        validFits = topFitHandles( ...
            isgraphics(topFitHandles, 'line'));

        if ~isempty(validHalos)
            uistack(validHalos, 'top');
        end

        if ~isempty(validFits)
            uistack(validFits, 'top');
        end

        % Legends: only retain valid plotted objects.
        spectrumHandles = spectrumHandles( ...
            isgraphics(spectrumHandles, 'line'));

        fitHandles = fitHandles( ...
            isgraphics(fitHandles, 'line'));

        if ~isempty(spectrumHandles)

            lgd = legend(axTop, spectrumHandles, ...
                'Location', 'best', ...
                'Box', 'off');

            lgd.AutoUpdate = 'off';

        end

        if ~isempty(fitHandles)

            lgd = legend(axBottom, fitHandles, ...
                'Location', 'best', ...
                'Box', 'off', ...
                'FontSize', 9);

            lgd.AutoUpdate = 'off';

        else

            if isMagnitude
                message = 'No available fit';
            else
                message = 'Fits available in magnitude modes only';
            end

            text(axBottom, 0.5, 0.5, message, ...
                'Units', 'normalized', ...
                'HorizontalAlignment', 'center', ...
                'Color', [0.4, 0.4, 0.4]);

        end

    end

    function shadeFrequencyBands(obj, ax)

        if isempty(ax) || ~isgraphics(ax)
            return;
        end

        yLimits = ylim(ax);
        xLimits = xlim(ax);

        xlim(ax, xLimits);
        ylim(ax, yLimits);

        gray = [0.78, 0.78, 0.78];
        orange = [1.00, 0.55, 0.12];
        blue = [0.15, 0.50, 0.95];

        % Gray: excluded frequencies.
        intervals = [ ...
                         -obj.fs / 2, -obj.f2; ...
                         -obj.f1, obj.f1; ...
                         obj.f2, obj.fs / 2];

        shade_color = repmat(gray, 3, 1);
        alphas = repmat(0.32, 3, 1);

        % Orange: LF bands.
        if ~isempty(obj.fi1)

            intervals = [intervals; ...
                             -obj.fi1, -obj.f1; ...
                             obj.f1, obj.fi1];

            shade_color = [shade_color; orange; orange];
            alphas = [alphas; 0.20; 0.20];

        end

        % Blue: HF bands.
        if ~isempty(obj.fi2)

            intervals = [intervals; ...
                             -obj.f2, -obj.fi2; ...
                             obj.fi2, obj.f2];

            shade_color = [shade_color; blue; blue];
            alphas = [alphas; 0.16; 0.16];

        end

        wasHeld = ishold(ax);
        hold(ax, 'on');

        for j = 1:size(intervals, 1)

            left = max(intervals(j, 1), xLimits(1));
            right = min(intervals(j, 2), xLimits(2));

            if right <= left
                continue;
            end

            h = patch(ax, ...
                [left, right, right, left], ...
                [yLimits(1), yLimits(1), ...
                 yLimits(2), yLimits(2)], ...
                shade_color(j, :), ...
                'FaceAlpha', alphas(j), ...
                'EdgeColor', 'none', ...
                'HandleVisibility', 'off', ...
                'HitTest', 'off');

            if isgraphics(h)
                uistack(h, 'bottom');
            end

        end

        set(ax, 'Layer', 'top');

        if ~wasHeld
            hold(ax, 'off');
        end

    end

    function releaseSpectrumAxes(obj)

        if ~isempty(obj.axPlot) && isgraphics(obj.axPlot)
            hold(obj.axPlot, 'off');
        end

        if ~isempty(obj.axFits) && isgraphics(obj.axFits)
            hold(obj.axFits, 'off');
        end

    end

    function makeOuterDiaphragmReference(obj)

        Ny = size(obj.SH_processed, 1);
        Nx = size(obj.SH_processed, 2);
        nFreq = size(obj.SH_processed, 3);

        % Keep the diskMask convention used by the existing project.
        outerMask = ~diskMask(Nx, Ny, 1.1);

        assert(isequal(size(outerMask), [Ny, Nx]), ...
            ['diskMask must return a matrix of size [%d %d], ' ...
         'matching the spatial dimensions of SH.'], Ny, Nx);

        outerMask = logical(outerMask);

        assert(any(outerMask(:)), ...
        'The outer reference mask is empty.');

        spatialSpectra = reshape( ...
            obj.SH_processed, [], nFreq);

        obj.outerReference = double(mean( ...
            spatialSpectra(outerMask(:), :), 1).');

    end

    function saveSpectra(obj)

        if obj.isClosing ...
                || isempty(obj.axPlot) ...
                || isempty(obj.axFits) ...
                || ~isgraphics(obj.axPlot) ...
                || ~isgraphics(obj.axFits)

            return;

        end

        [filename, pathname] = uiputfile( ...
            {'*.png', 'PNG image'}, ...
            'Save spectra and fits', ...
        'spectra.png');

        if isequal(filename, 0) || obj.isClosing
            return;
        end

        [~, name, ~] = fileparts(filename);
        outputPath = fullfile(pathname, [name, '.png']);

        exportFigure = figure( ...
            'Visible', 'off', ...
            'Color', 'white', ...
            'Position', [100, 100, 1000, 850]);

        cleanup = onCleanup( ...
            @() delete(exportFigure)); %#ok<NASGU>

        % Copy both axes together with their associated legends.
        sourceObjects = [obj.axPlot, obj.axFits];

        if ~isempty(obj.axPlot.Legend) ...
                && isgraphics(obj.axPlot.Legend)

            sourceObjects = [ ...
                                 sourceObjects, obj.axPlot.Legend];

        end

        if ~isempty(obj.axFits.Legend) ...
                && isgraphics(obj.axFits.Legend)

            sourceObjects = [ ...
                                 sourceObjects, obj.axFits.Legend];

        end

        copiedObjects = copyobj(sourceObjects, exportFigure);

        set(copiedObjects(1), ...
            'Units', 'normalized', ...
            'Position', [0.10, 0.57, 0.86, 0.36]);

        set(copiedObjects(2), ...
            'Units', 'normalized', ...
            'Position', [0.10, 0.11, 0.86, 0.34]);

        % Restore interactive linking in the exported figure.
        linkaxes(copiedObjects(1:2), 'xy');

        exportgraphics(exportFigure, outputPath, ...
            'Resolution', 300);

        fprintf('Figure saved to:\n%s\n', outputPath);

    end

    function closeFigure(obj, src, ~)

        if obj.isClosing
            return;
        end

        obj.isClosing = true;

        obj.deleteROIListeners();

        if ~isempty(src) && isgraphics(src)
            delete(src);
        end

        obj.fig = [];

    end

end

methods (Access = private)

    function finishSpectrumUpdate(obj)

        % Release the lock even if restoring the axes raises an error.
        lockCleanup = onCleanup( ...
            @() obj.unlockSpectrumUpdate()); %#ok<NASGU>

        obj.releaseSpectrumAxes();

    end

    function unlockSpectrumUpdate(obj)

        obj.isUpdatingSpectrum = false;

    end

    function unlinkSpectrumAxes(obj)

        if ~isempty(obj.spectrumAxesLink)

            if isvalid(obj.spectrumAxesLink)
                delete(obj.spectrumAxesLink);
            end

            obj.spectrumAxesLink = [];

        end

    end

    function synchronizeSpectrumAxes(obj)

        axTop = obj.axPlot;
        axBottom = obj.axFits;

        if isempty(axTop) || isempty(axBottom) ...
                || ~isgraphics(axTop) || ~isgraphics(axBottom)

            return;

        end

        % Remove the previous explicitly managed link.
        obj.unlinkSpectrumAxes();

        % Both panels use the frequency range configured on the upper axis.
        commonXLimits = xlim(axTop);

        % Include the vertical extents of both panels.
        topYLimits = ylim(axTop);
        bottomYLimits = ylim(axBottom);

        commonYLimits = [ ...
                             min(topYLimits(1), bottomYLimits(1)), ...
                             max(topYLimits(2), bottomYLimits(2))];

        set([axTop, axBottom], ...
            'XLim', commonXLimits, ...
            'YLim', commonYLimits);

        % Keep this object alive in the class property.
        obj.spectrumAxesLink = linkprop( ...
            [axTop, axBottom], {'XLim', 'YLim'});

    end

end

end
