classdef holodoppler < matlab.apps.AppBase

% =========================================================================
% UI component handles — required public by App Designer / registerApp
% =========================================================================
properties (Access = private)
    HoloDopplerUIFigure matlab.ui.Figure

    % ---- top-level layout ----
    RootGrid matlab.ui.container.GridLayout
    Image matlab.ui.control.Image
    ImageDisplayPanel matlab.ui.container.Panel
    ImageTypeAnnotation matlab.ui.control.Label

    % ---- file selection panel (left column) ----
    FileselectionPanel matlab.ui.container.Panel
    FileNameLabel matlab.ui.control.Label
    FileNameField matlab.ui.control.EditField

    % ---- top grid menu ----
    mainParametersGrid matlab.ui.container.GridLayout
    LoadfileButton matlab.ui.control.Button
    fileLoadedLamp matlab.ui.control.Lamp
    fsLabel matlab.ui.control.Label
    fs matlab.ui.control.NumericEditField
    lambdaLabel matlab.ui.control.Label
    lambda matlab.ui.control.NumericEditField
    pixelPitchLabel matlab.ui.control.Label
    ppx matlab.ui.control.NumericEditField
    ppy matlab.ui.control.NumericEditField
    imageSizeLabel matlab.ui.control.Label
    Nx matlab.ui.control.NumericEditField
    Ny matlab.ui.control.NumericEditField
    numworkersSpinnerLabel matlab.ui.control.Label
    parforArg matlab.ui.control.Spinner
    AdvancedButton matlab.ui.control.Button
    RefreshAppButton matlab.ui.control.Button
    positioninfileSlider matlab.ui.control.Slider
    positioninfileSliderLabel matlab.ui.control.Label
    batchIndexField matlab.ui.control.NumericEditField
    batchIndexLabel matlab.ui.control.Label
    framePosition matlab.ui.control.NumericEditField

    % ---- batch / video rendering sub-panel ----
    batchPanel matlab.ui.container.Panel
    batchGrid matlab.ui.container.GridLayout
    imageTypesListBox matlab.ui.control.ListBox
    LoadConfigButton matlab.ui.control.Button
    SaveConfigButton matlab.ui.control.Button
    ClearConfigsButton matlab.ui.control.Button
    FolderManagerButton matlab.ui.control.Button
    VideoRenderingButton matlab.ui.control.Button
    VideoRenderingLamp matlab.ui.control.Lamp
    batchSizeLabel matlab.ui.control.Label
    batchSize matlab.ui.control.NumericEditField
    batchStrideLabel matlab.ui.control.Label
    batchStride matlab.ui.control.NumericEditField
    refBatchSizeLabel matlab.ui.control.Label
    refBatchSize matlab.ui.control.NumericEditField
    imageRegistration matlab.ui.control.CheckBox
    registrationDiskLabel matlab.ui.control.Label
    registrationDiskRatio matlab.ui.control.NumericEditField

    % ---- rendering parameters panel ----
    renderingParametersPanel matlab.ui.container.Panel
    renderingParametersGrid matlab.ui.container.GridLayout
    spatialFilter matlab.ui.control.CheckBox
    spatialFilterRange1 matlab.ui.control.NumericEditField
    spatialFilterRange2 matlab.ui.control.NumericEditField
    PaddingLabel matlab.ui.control.Label
    PaddingNum matlab.ui.control.NumericEditField
    spatialTransformLabel matlab.ui.control.Label
    spatialTransform matlab.ui.control.DropDown
    spatialPropagationLabel matlab.ui.control.Label
    spatialPropagation matlab.ui.control.NumericEditField
    AutofocusButton matlab.ui.control.Button
    svd_filter matlab.ui.control.CheckBox
    svdThresholdResetButton matlab.ui.control.Button
    svdThreshold matlab.ui.control.NumericEditField
    svdStrideLabel matlab.ui.control.Label
    svdStride matlab.ui.control.NumericEditField
    timeTransformLabel matlab.ui.control.Label
    timeTransform matlab.ui.control.DropDown
    frequencyRangeLabel matlab.ui.control.Label
    frequencyRange1 matlab.ui.control.NumericEditField
    frequencyRange2 matlab.ui.control.NumericEditField
    frequencyRangeBandRatioLabel matlab.ui.control.Label
    frequencyRangeBandRatio1 matlab.ui.control.NumericEditField
    frequencyRangeBandRatio2 matlab.ui.control.NumericEditField
    indexRangeLabel matlab.ui.control.Label
    indexRange1 matlab.ui.control.NumericEditField
    indexRange2 matlab.ui.control.NumericEditField
    flat_field_gwLabel matlab.ui.control.Label
    flat_field_gw matlab.ui.control.NumericEditField
    square matlab.ui.control.CheckBox
    flip_x matlab.ui.control.CheckBox
    flip_y matlab.ui.control.CheckBox
    RenderPreviewLamp matlab.ui.control.Lamp
    RenderPreviewButton matlab.ui.control.Button
    SavePreviewButton matlab.ui.control.Button
    ImproveContrast matlab.ui.control.CheckBox
    CornerCompensation matlab.ui.control.CheckBox

    % ---- context menu ----
    RightClickImageContextMenu matlab.ui.container.ContextMenu
    NextMenu matlab.ui.container.Menu
    ViewAllMenu matlab.ui.container.Menu
end

% =========================================================================
% Application state (readable by external code, e.g. classtogui / guitoclass)
% =========================================================================
properties (Access = public)
    HD % HoloDopplerClass instance
    drawer_list = {}
end

properties (Access = private)
    OriginalPath char % path before startupFcn adds Tools folder
    MenuIndex double = 1; % which image type is currently shown in the main view
end

% =========================================================================
% Callbacks
% =========================================================================
methods (Access = private)

    % --- Startup / lifecycle -----------------------------------------------

    function startupFcn(app)
        appRoot = fileparts(mfilename('fullpath'));
        addpath(appRoot, genpath(fullfile(appRoot, 'src')), fullfile(appRoot, 'tools'));

        versionFile = fullfile(appRoot, 'version.txt');

        if isfile(versionFile)
            v = readlines(versionFile);
            version = char(v(1));
        else
            version = 'unknown';
            warning('holodoppler:noVersionFile', 'version.txt not found.');
        end

        versionStr = ['HoloDoppler ' version];

        gitInfo = '';

        if exist(fullfile(appRoot, '.git'), 'dir')
            [~, branch] = system('git rev-parse --abbrev-ref HEAD');
            [~, hash] = system('git rev-parse --short HEAD');
            gitInfo = sprintf('Branch: %s | Commit: %s', strtrim(branch), strtrim(hash));
        end

        app.HoloDopplerUIFigure.Name = versionStr;

        app.HD = HoloDopplerClass();
        app.syncGuiFromClass();
        app.updateButtonStates();
        app.HoloDopplerUIFigure.Visible = 'on';

        % The splash screen must never prevent application startup.
        try
            displaySplashScreen(versionStr, gitInfo);
        catch ME
            warning('holodoppler:SplashScreenFailed', ...
                'Splash screen skipped: %s', ME.message);
        end

    end

    function ready = hasFile(app)
        ready = ~isempty(app.HD) && ~isempty(app.HD.file);
    end

    % Private callback
    function HoloDopplerUIFigureCloseRequest(app, ~)
        delete(app);
    end

    function HoloDopplerUIFigureWindowKeyPress(app, event)

        if ~app.hasFile()
            return;
        end

        switch event.Key
            case 'return'
                app.RenderPreviewButtonPushed();

            case 'space'
                app.ViewAllMenuSelected();

            case 'leftarrow'
                app.changeMenu('previous');

            case 'rightarrow'
                app.changeMenu('next');
        end

    end

    % --- File I/O callbacks ------------------------------------------------

    function LoadfileButtonPushed(app, ~)
        filters = {
                   '*.cine;*.holo', 'Supported video files (*.cine, *.holo)'
                   '*.cine', 'Cine files (*.cine)'
                   '*.holo', 'Holo files (*.holo)'
                   };

        initialFolder = pwd;

        if app.hasFile()
            initialFolder = fileparts(app.HD.file.path);
        end

        [name, folder] = uigetfile( ...
            filters, 'Select a video file', ...
            fullfile(initialFolder, '*.*'));

        if isequal(name, 0)
            return;
        end

        app.fileLoadedLamp.Color = [1 0.5 0];
        drawnow;

        try
            app.HD.LoadFile(fullfile(folder, name));
            app.syncGuiFromClass();

            app.FileNameField.Value = app.HD.file.name;
            app.fileLoadedLamp.Color = [0 1 0];

        catch ME
            app.fileLoadedLamp.Color = [1 0 0];
            app.updateButtonStates();
            MEdisp(ME);
            return;
        end

        app.updateButtonStates();
        app.positioninfileSliderValueChanged();
        app.RenderPreviewButtonPushed();
    end

    function LoadConfigButtonPushed(app, ~)
        [selected_file, path] = uigetfile('*.json', 'Select Config File');

        if isequal(selected_file, 0)
            return
        end

        try
            app.HD.loadParams(fullfile(path, selected_file));
            app.syncGuiFromClass();
            fprintf('Config loaded from %s\n', fullfile(path, selected_file));
        catch ME
            MEdisp(ME);
        end

    end

    function SaveConfigButtonPushed(app, ~)

        try
            outputPath = app.HD.saveParams();
            fprintf("Config saved successfully to %s\n", outputPath);
        catch ME
            MEdisp(ME);
        end

    end

    function ClearConfigsButtonPushed(app, ~)

        try
            app.HD.clearParams();
            fprintf("Config cleared successfully.\n");
        catch ME
            MEdisp(ME);
        end

    end

    % --- Render callbacks --------------------------------------------------

    function RenderPreviewButtonPushed(app, ~)

        app.RenderPreviewLamp.Color = [1 0.5 0];
        app.refreshClass();
        drawnow;

        Images = [];

        try
            Images = app.HD.PreviewRendering();
            app.RenderPreviewLamp.Color = [0 1 0];
        catch ME
            MEdisp(ME);
            app.RenderPreviewLamp.Color = [1 0 0];
            drawnow;
        end

        if ~isempty(Images)
            app.Image.ImageSource = toImageSource(Images{1}, app);
            app.MenuIndex = 1;
            app.updateImageTypeAnnotation(1);
        else
            app.Image.ImageSource = '';
            app.updateImageTypeAnnotation([]);
        end

        % A successful render means we can now save the preview
        app.updateButtonStates();
    end

    function VideoRenderingButtonPushed(app, ~)
        app.VideoRenderingLamp.Color = [1 0.5 0]; drawnow;

        try
            app.HD.VideoRendering();
            app.VideoRenderingLamp.Color = [0 1 0];
        catch ME
            MEdisp(ME);
            app.VideoRenderingLamp.Color = [1 0 0];
        end

    end

    function SavePreviewButtonPushed(app, ~)
        app.HD.savePreview();
    end

    % --- UI state sync / refresh -------------------------------------------

    % Sync every widget value into the HD class, then update enable states.
    % Connected to ~50 component ValueChanged callbacks.
    function refreshClass(app, ~)
        app.syncClassFromGui();
        app.updateButtonStates();
    end

    function registrationCheckBoxValueChanged(app, ~)
        app.refreshClass();
    end

    function spatialFilterCheckBoxValueChanged(app, ~)
        app.refreshClass();
    end

    function svdFilterCheckBoxValueChanged(app, ~)
        app.refreshClass();
    end

    function RefreshAppButtonPushed(app, ~)
        app.syncGuiFromClass();

        if isempty(app.HD.params.imageTypes)
            return
        end

        imgs = app.HD.render.getImages(app.HD.params.imageTypes(1));

        if ~isempty(imgs)
            app.Image.ImageSource = toImageSource(imgs{randi(numel(imgs))}, app);
            app.MenuIndex = 1;
            app.updateImageTypeAnnotation(1);
        else
            app.Image.ImageSource = '';
            app.updateImageTypeAnnotation([]);
        end

    end

    function AutofocusButtonPushed(app, ~)
        % Remplace le balayage de spatialPropagation par l'estimation du defocus
        % Shack-Hartmann / Zernike Noll 4, puis relance l'aperçu corrigé.

        app.AutofocusButton.Enable = 'off';
        buttonCleanup = onCleanup( ...
            @() set(app.AutofocusButton, 'Enable', 'on'));
        app.RenderPreviewLamp.Color = [1 0.5 0];
        drawnow;

        try
            app.refreshClass();

            if ~strcmpi(strtrim(app.HD.params.spatialTransform), ...
                'Angular spectrum')
                error('holodoppler:AutofocusRequiresAngularSpectrum', ...
                    ['Select "Angular spectrum" before running the ', ...
                 'Zernike autofocus.']);
            end

            % Charge/rend le batch de reference courant dans app.HD.render.
            app.HD.PreviewRendering();

            [c4, diagnostic] = autofocusDefocus( ...
                app.HD.render, ...
                app.HD.params, ...
                app.HD.file, ...
                NumSubapertures = [5 5], ...
                ZernikeModes = 4, ...
                ShowDiagnostic = true);

            % Passage obligatoire par setParams : HDParamSchema reste la source
            % unique de validation des parametres de rendu.
            app.HD.setParams(struct( ...
                'defocusCorrection', true, ...
                'defocusCoefficientRad', c4, ...
                'defocusPupilRadius', 2));

            % Diagnostic hors des parametres de rendu.
            app.HD.autofocusResult = diagnostic;

            app.syncGuiFromClass();
            app.RenderPreviewButtonPushed();
            app.RenderPreviewLamp.Color = [0 1 0];

        catch ME
            app.RenderPreviewLamp.Color = [1 0 0];
            MEdisp(ME);
        end

    end

    % --- Context menu / image navigation -----------------------------------

    function changeMenu(app, direction)
        count = numel(app.HD.params.imageTypes);

        if count == 0
            return;
        end

        switch string(direction)
            case "next"
                step = 1;
            case "previous"
                step = -1;
            otherwise
                return;
        end

        index = mod(app.MenuIndex - 1 + step, count) + 1;
        app.SelectMenu(index);
    end

    function SelectMenu(app, num, ~)
        imgs = app.HD.render.getImages(app.HD.params.imageTypes);

        if isempty(imgs) || num > numel(imgs) || isempty(imgs{num})
            app.Image.ImageSource = '';
            app.updateImageTypeAnnotation([]);
            return
        end

        image = imgs{num};

        % Convert a display copy; preserve the scientific image in imgs.
        [displayImage] = toImageSource(image, app);

        plotTypes = {'broadening', 'harmonic_spectrum'};

        if ~ismember(app.HD.params.imageTypes{num}, plotTypes) && ...
                size(image, 1) ~= size(image, 2)

            maxSize = max(size(image, 1), size(image, 2));
            outputSize = [maxSize maxSize];

            % Nearest-neighbor prevents invalid-pixel colors from blending
            % into neighboring valid pixels.
            displayImage = imresize(displayImage, outputSize, 'nearest');
        end

        app.Image.ImageSource = displayImage;
        app.MenuIndex = num;
        app.updateImageTypeAnnotation(num);
    end

    function ViewAllMenuSelected(app, ~)
        app.HD.showPreviewImages();
    end

    % --- Misc callbacks ----------------------------------------------------
    function svdThresholdResetButtonPushed(app, ~)

        if app.svdThreshold.Value == 0
            val = ceil(app.frequencyRange1.Value * 2 * app.batchSize.Value / app.fs.Value);

            if isfinite(val) % catches both NaN and Inf
                app.svdThreshold.Value = val;
            end

        else
            app.svdThreshold.Value = 0;
        end

        app.refreshClass();
    end

    function frequencyRange2ValueChanged(app, ~)

        if strcmp(app.timeTransform.Value, 'FFT') && app.frequencyRange2.Value > app.fs.Value / 2
            app.frequencyRange2.Value = app.fs.Value / 2;
        end

        app.refreshClass();
    end

    function AdvancedButtonPushed(app, ~)
        AdvancedPanel(app);
    end

    function registrationDiskRatioValueChanged(app, ~)
        app.refreshClass();
        show_ref_disk(app, app.imageRegistration.Value);
    end

    function positioninfileSliderValueChanged(app, ~)

        if ~isempty(app.HD.file)
            lastFrame = max(1, double(app.HD.file.num_frames) - ...
                double(app.HD.params.batchSize) + 1);
            app.framePosition.Value = min(lastFrame, ...
                max(1, round(app.positioninfileSlider.Value)));
        else
            app.framePosition.Value = 1;
        end

        frame = app.framePosition.Value;
        stride = max(app.batchStride.Value, 1); % avoid division by zero
        batchIndex = ceil(frame / stride);
        % Clamp to field limits
        maxIdx = app.batchIndexField.Limits(2);
        batchIndex = max(1, min(batchIndex, maxIdx));
        app.batchIndexField.Value = batchIndex;

        app.refreshClass();
    end

    function framePositionValueChanged(app, ~)

        if ~isempty(app.HD.file)
            app.positioninfileSlider.Value = app.framePosition.Value;
        else
            app.positioninfileSlider.Value = 0;
        end

        % Reuse the same safe update
        app.positioninfileSliderValueChanged();
    end

    % --- Folder management -------------------------------------------------

    function FolderManagerButtonPushed(app, ~)
        FolderManagementUI(app);
    end

end % callbacks methods block

% =========================================================================
% Private helper methods (GUI sync, UI enable logic, drawer operations)
% =========================================================================
methods (Access = private)

    % --- Display-only image type overlay ---------------------------------

    function updateImageTypeAnnotation(app, index)

        if isempty(app.ImageTypeAnnotation) || ...
                ~isvalid(app.ImageTypeAnnotation)
            return;
        end

        app.ImageTypeAnnotation.Visible = 'off';
        app.ImageTypeAnnotation.Text = '';

        if isempty(index) || isempty(app.HD) || ...
                isempty(app.Image.ImageSource)
            return;
        end

        imageTypes = app.HD.params.imageTypes;

        if index < 1 || index > numel(imageTypes)
            return;
        end

        if iscell(imageTypes)
            imageType = imageTypes{index};
        else
            imageType = imageTypes(index);
        end

        % No TeX interpretation: underscores are displayed literally.
        app.ImageTypeAnnotation.Text = char(string(imageType));
        app.layoutImageDisplay();
        app.ImageTypeAnnotation.Visible = 'on';
    end

    function layoutImageDisplay(app, ~)

        if isempty(app.ImageDisplayPanel) || ...
                ~isvalid(app.ImageDisplayPanel) || ...
                isempty(app.Image) || ~isvalid(app.Image)
            return;
        end

        panelPosition = app.ImageDisplayPanel.InnerPosition;
        panelWidth = max(1, panelPosition(3));
        panelHeight = max(1, panelPosition(4));

        app.Image.Position = [1 1 panelWidth panelHeight];

        if isempty(app.ImageTypeAnnotation) || ...
                ~isvalid(app.ImageTypeAnnotation)
            return;
        end

        % Anchor to the visible image, accounting for fit/letterboxing.
        imageLeft = 1;
        imageBottom = 1;
        imageWidth = panelWidth;
        imageHeight = panelHeight;
        imageSource = app.Image.ImageSource;

        if (isnumeric(imageSource) || islogical(imageSource)) && ...
                ~isempty(imageSource)
            sourceHeight = size(imageSource, 1);
            sourceWidth = size(imageSource, 2);
            scale = min(panelWidth / sourceWidth, ...
                panelHeight / sourceHeight);
            imageWidth = sourceWidth * scale;
            imageHeight = sourceHeight * scale;
            imageLeft = 1 + (panelWidth - imageWidth) / 2;
            imageBottom = 1 + (panelHeight - imageHeight) / 2;
        end

        margin = min(10, max(0, (min(imageWidth, imageHeight) - 1) / 4));
        labelHeight = min(26, max(1, imageHeight - 2 * margin));
        labelWidth = min(max(1, imageWidth - 2 * margin), ...
            max(80, 16 + 9 * numel(app.ImageTypeAnnotation.Text)));

        app.ImageTypeAnnotation.Position = [ ...
                                                imageLeft + margin, imageBottom + margin, ...
                                                labelWidth, labelHeight];
    end

    % --- GUI <-> class sync (replaces external classtogui / guitoclass) ----

    % Push all widget values into HD (was external guitoclass)
    function syncClassFromGui(app)
        HDParamSchema.guitoclass(app.HD, app);
        % Legacy SVD checkbox is authoritative; discard an old selector value.
        if isfield(app.HD.params, 'filterType')
            app.HD.params = rmfield(app.HD.params, 'filterType');
        end

    end

    function syncGuiFromClass(app)
        % Ignore filterType stored by earlier versions of this interface.
        if isfield(app.HD.params, 'filterType')
            app.HD.params = rmfield(app.HD.params, 'filterType');
        end

        HDParamSchema.classtogui(app.HD, app);
        app.updateButtonStates();
    end

    function updateButtonStates(app)
        fileReady = app.hasFile();

        previewReady = fileReady && ...
            ~isempty(app.HD.render) && ...
            ~isempty(app.HD.render.Output);

        % Controls that require a loaded file.
        app.setControlsEnabled({
                                'SaveConfigButton', 'ClearConfigsButton', ...
                                    'VideoRenderingButton', 'RefreshAppButton', ...
                                    'RenderPreviewButton', 'AutofocusButton', ...
                                    'imageTypesListBox', 'imageRegistration', ...
                                    'positioninfileSlider', 'framePosition', ...
                                    'batchSize', 'batchStride', 'refBatchSize', ...
                                    'fs', 'lambda', 'ppx', 'ppy', ...
                                    'spatialFilter', 'PaddingNum', ...
                                    'spatialTransform', 'spatialPropagation', ...
                                    'svd_filter', 'timeTransform', ...
                                    'flat_field_gw', 'square', 'flip_x', 'flip_y', ...
                                    'parforArg', 'AdvancedButton', 'LoadConfigButton', ...
                                    'ImproveContrast', 'CornerCompensation', 'FileNameField'
                                }, fileReady);

        % Controls that require rendered output.
        app.setControlsEnabled({
                                'SavePreviewButton', 'NextMenu', 'ViewAllMenu'
                                }, previewReady);

        % Registration.
        app.setControlsEnabled({
                                'registrationDiskRatio', 'registrationDiskLabel'
                                }, fileReady && app.imageRegistration.Value);

        % Spatial filtering.
        app.setControlsEnabled({
                                'spatialFilterRange1', 'spatialFilterRange2'
                                }, fileReady && app.spatialFilter.Value);

        % SVD filtering.
        app.setControlsEnabled({
                                'svdThreshold', 'svdThresholdResetButton', ...
                                    'svdStride', 'svdStrideLabel'
                                }, fileReady && app.svd_filter.Value);

        % Temporal transform.
        frequencyMode = ismember(app.timeTransform.Value, ...
            {'FFT', 'autocorrelation', 'intercorrelation'});

        app.setControlsEnabled({
                                'frequencyRangeLabel', 'frequencyRange1', ...
                                    'frequencyRange2', 'frequencyRangeBandRatioLabel', ...
                                    'frequencyRangeBandRatio1', 'frequencyRangeBandRatio2'
                                }, fileReady && frequencyMode);

        app.setControlsEnabled({
                                'indexRangeLabel', 'indexRange1', 'indexRange2'
                                }, fileReady && ~frequencyMode);
    end

    function setControlsEnabled(app, names, enabled)

        for k = 1:numel(names)
            app.(names{k}).Enable = matlab.lang.OnOffSwitchState(enabled);
        end

    end

    % --- refreshClass sub-routines ----------------------------------------

    function updateTimeTransformControls(app)
        app.updateButtonStates();
    end

    function applyMaterialTheme(app)
        % Native MATLAB controls, Material-inspired dark tonal palette.
        c.bg = [16 18 23] / 255;
        c.card = [25 28 35] / 255;
        c.field = [35 39 49] / 255;
        c.text = [234 237 245] / 255;
        c.muted = [174 183 201] / 255;
        c.primary = [191 172 255] / 255;
        c.onPrimary = [38 22 77] / 255;
        c.tonal = [49 56 74] / 255;
        c.onTonal = [220 228 248] / 255;
        fig = app.HoloDopplerUIFigure;
        fig.Color = c.bg;

        available = string(listfonts);
        preferred = ["Open Sans", "Helvetica Neue", "Roboto", "Segoe UI", "Arial"];
        chosen = preferred(find(ismember(preferred, available), 1));
        if isempty(chosen), chosen = "Arial"; end
        fontname(fig, char(chosen));
        fontsize(fig, 11, "points");

        objects = findall(fig);

        for k = 1:numel(objects)
            o = objects(k);

            if isa(o, 'matlab.ui.container.GridLayout')
                o.BackgroundColor = c.card;
                o.RowSpacing = 6;
                o.ColumnSpacing = 8;
                o.Padding = [14 14 14 14];
            elseif isa(o, 'matlab.ui.container.Panel')
                o.BackgroundColor = c.card;
                o.ForegroundColor = c.text;
                o.FontWeight = 'bold';
                o.FontSize = 12;
                o.BorderType = 'none';
            elseif isa(o, 'matlab.ui.control.Button')
                o.BackgroundColor = c.tonal;
                o.FontColor = c.onTonal;
                o.FontWeight = 'normal';
            elseif isa(o, 'matlab.ui.control.NumericEditField') || ...
                    isa(o, 'matlab.ui.control.EditField') || ...
                    isa(o, 'matlab.ui.control.DropDown') || ...
                    isa(o, 'matlab.ui.control.Spinner') || ...
                    isa(o, 'matlab.ui.control.ListBox')
                o.BackgroundColor = c.field;
                o.FontColor = c.text;
            elseif isa(o, 'matlab.ui.control.CheckBox')
                o.FontColor = c.text;
            elseif isa(o, 'matlab.ui.control.Label') || ...
                    isa(o, 'matlab.ui.control.Slider')
                o.FontColor = c.muted;
            end

        end

        primaryActions = {app.RenderPreviewButton, app.VideoRenderingButton};

        for k = 1:numel(primaryActions)
            primaryActions{k}.BackgroundColor = c.primary;
            primaryActions{k}.FontColor = c.onPrimary;
            primaryActions{k}.FontWeight = 'bold';
        end

        app.LoadfileButton.BackgroundColor = [65 83 111] / 255;
        app.LoadfileButton.FontColor = [234 241 255] / 255;
        app.ClearConfigsButton.FontColor = [255 180 171] / 255;

        app.RootGrid.BackgroundColor = c.bg;
        app.RootGrid.Padding = [16 16 16 16];
        app.RootGrid.RowSpacing = 14;
        app.RootGrid.ColumnSpacing = 14;
        app.ImageDisplayPanel.BackgroundColor = c.bg;
        app.batchPanel.BackgroundColor = c.field;
        app.batchGrid.BackgroundColor = c.field;
        app.ImageTypeAnnotation.BackgroundColor = c.field;
        app.ImageTypeAnnotation.FontColor = c.text;
        app.ImageTypeAnnotation.FontSize = 11;

        app.configureMaterialLayout();
    end

    function configureMaterialLayout(app)
        % Explicit row heights keep inputs usable; small windows can scroll.
        app.FileselectionPanel.Title = 'File & acquisition';
        app.batchPanel.Title = 'Batch & video';
        app.renderingParametersPanel.Title = 'Reconstruction & rendering';
        app.mainParametersGrid.ColumnWidth = {150, '1x', '1x'};
        app.mainParametersGrid.RowHeight = ...
            {32, 32, 30, 30, 30, 30, 30, 30, 32, 30, 360, 32};
        app.mainParametersGrid.Scrollable = 'on';

        % Compact the previously unused rows of the batch section.
        app.batchGrid.ColumnWidth = {156, '1x', 28};
        app.batchGrid.RowHeight = {132, 34, 30, 30, 30, 28, 30};
        app.imageRegistration.Layout.Row = 6;
        app.registrationDiskLabel.Layout.Row = 7;
        app.registrationDiskRatio.Layout.Row = 7;
        app.VideoRenderingButton.Layout.Column = [1 2];
        app.VideoRenderingLamp.Layout.Column = 3;
        app.VideoRenderingButton.Text = 'Render video';
        app.VideoRenderingLamp.Tooltip = 'Video rendering status';

        app.renderingParametersGrid.ColumnWidth = {164, '1x', '1x'};
        % Reserve a flexible spacer above the bottom action bar.
        app.renderingParametersGrid.RowHeight = ...
            [repmat({32}, 1, 13), {'1x', 38}];
        app.RenderPreviewLamp.Layout.Row = 15;
        app.RenderPreviewButton.Layout.Row = 15;
        app.SavePreviewButton.Layout.Row = 15;
        app.renderingParametersGrid.Scrollable = 'on';
        app.svd_filter.Text = 'SVD filter';
        app.frequencyRangeLabel.Text = 'Frequency (kHz)';
        app.spatialPropagationLabel.Text = 'Propagation (m)';
        app.PaddingLabel.Text = 'Padding size';
        app.numworkersSpinnerLabel.Text = 'Workers';
        app.RootGrid.Scrollable = 'on';
        app.HoloDopplerUIFigure.AutoResizeChildren = 'off';
        app.HoloDopplerUIFigure.SizeChangedFcn = ...
            @(~, ~) app.updateResponsiveLayout();

        % Placer les derniers contrôles avant de fixer le nombre de lignes.
        app.imageRegistration.Layout.Row = 6;
        app.registrationDiskLabel.Layout.Row = 7;
        app.registrationDiskRatio.Layout.Row = 7;

        % Sept lignes explicites : aucune ligne vide résiduelle.
        app.batchGrid.RowHeight = {132, 34, 30, 30, 30, 28, 30};
        app.batchGrid.RowSpacing = 6;
        app.batchGrid.Padding = [14 14 14 14];
        app.batchGrid.Scrollable = 'on';

        % Réserver assez de place au panneau batch, titre compris.
        mainRows = app.mainParametersGrid.RowHeight;
        mainRows{11} = 430;
        app.mainParametersGrid.RowHeight = mainRows;

        % Si la fenêtre est trop basse, faire défiler la colonne de gauche.
        app.mainParametersGrid.Scrollable = 'on';

        app.updateResponsiveLayout();
    end

    function updateResponsiveLayout(app)

        if isempty(app.ImageDisplayPanel) || ~isvalid(app.ImageDisplayPanel)
            return;
        end

        width = app.HoloDopplerUIFigure.Position(3);

        if width >= 1280
            % Desktop: acquisition | reconstruction | large preview.
            app.RootGrid.ColumnWidth = {390, 440, '1x'};
            app.FileselectionPanel.Layout.Row = 1;
            app.FileselectionPanel.Layout.Column = 1;
            app.renderingParametersPanel.Layout.Row = 1;
            app.renderingParametersPanel.Layout.Column = 2;
            app.ImageDisplayPanel.Layout.Row = 1;
            app.ImageDisplayPanel.Layout.Column = 3;
            app.RootGrid.RowHeight = {'1x'};
        else
            % Compact: preview above reconstruction; no compressed controls.
            app.RootGrid.RowHeight = {300, 650};
            app.FileselectionPanel.Layout.Row = [1 2];
            app.FileselectionPanel.Layout.Column = 1;
            app.renderingParametersPanel.Layout.Row = 2;
            app.renderingParametersPanel.Layout.Column = 2;
            app.ImageDisplayPanel.Layout.Row = 1;
            app.ImageDisplayPanel.Layout.Column = 2;
            app.RootGrid.ColumnWidth = {390, 440};
        end

        app.layoutImageDisplay();
    end

end % private helpers methods block

% =========================================================================
% Component initialization — split by panel
% =========================================================================
methods (Access = private)

    function createComponents(app)
        pathToMLAPP = fileparts(mfilename('fullpath'));

        app.createFigureAndRootGrid(pathToMLAPP);
        app.createFileSelectionPanel();
        app.createBatchVideoPanel();
        app.createrenderingParametersPanel();
        app.createImageViewsAndMenus();

        fontsize(app.HoloDopplerUIFigure, 12, "points");
        app.applyMaterialTheme();

    end

    % -----------------------------------------------------------------------
    function createFigureAndRootGrid(app, pathToMLAPP)

        screenSize = get(groot, 'ScreenSize');

        % Fenêtre paysage, adaptée à la taille de l'écran.
        scale = min([1, ...
                         0.95 * screenSize(3) / 1500, ...
                         0.90 * screenSize(4) / 940]);

        appWidth = round(1500 * scale);
        appHeight = round(940 * scale);
        appX = screenSize(1) + (screenSize(3) - appWidth) / 2;
        appY = screenSize(2) + (screenSize(4) - appHeight) / 2;

        app.HoloDopplerUIFigure = uifigure('Visible', 'off', ...
            'Position', [appX appY appWidth appHeight], ...
            'Name', 'HoloDoppler', ...
            'Icon', fullfile(pathToMLAPP, 'src', 'gui', 'holoDopplerLogo.png'), ...
            'CloseRequestFcn', createCallbackFcn(app, @HoloDopplerUIFigureCloseRequest, true), ...
            'WindowKeyPressFcn', createCallbackFcn(app, @HoloDopplerUIFigureWindowKeyPress, true), ...
            'WindowStyle', 'normal'); % allows maximizing on Windows

        app.RootGrid = uigridlayout(app.HoloDopplerUIFigure, [2 3], ...
            'ColumnWidth', {370, 440, '1x'}, ...
            'RowHeight', {'1x', 'fit'}, ...
            'RowSpacing', 10, ...
            'ColumnSpacing', 12, ...
            'Padding', [14 14 14 14], ...
            'BackgroundColor', [0.2 0.2 0.2]);

    end

    % -----------------------------------------------------------------------
    function createFileSelectionPanel(app)

        backgroundColor = [0.2 0.2 0.2];
        darkBackgroundColor = [0.15 0.15 0.15];
        fontColor = [1 1 1];
        grayButtonColor = [0.5 0.5 0.5];

        app.FileselectionPanel = uipanel(app.RootGrid, ...
            'Title', 'File selection', ...
            'BackgroundColor', backgroundColor, ...
            'ForegroundColor', fontColor, ...
            'BorderType', 'line', ...
            'FontWeight', 'bold');

        app.FileselectionPanel.Layout.Row = [1 2];
        app.FileselectionPanel.Layout.Column = 1;

        app.mainParametersGrid = uigridlayout(app.FileselectionPanel, [12 3], ...
            'RowHeight', {'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit', '1x', 'fit'}, ...
            'ColumnWidth', {'fit', 'fit', 'fit'}, ...
            'Padding', [10 10 10 10], ...
            'RowSpacing', 5, ...
            'ColumnSpacing', 5, ...
            'BackgroundColor', backgroundColor);

        app.FolderManagerButton = uibutton(app.mainParametersGrid, 'push', ...
            'Text', 'Folder manager', ...
            'ButtonPushedFcn', createCallbackFcn(app, @FolderManagerButtonPushed, true), ...
            'Tooltip', {'Open a window to render all files from different folders with their config files'}, ...
            'BackgroundColor', grayButtonColor, ...
            'FontColor', fontColor);
        app.FolderManagerButton.Layout.Row = 1;
        app.FolderManagerButton.Layout.Column = 1;

        app.LoadfileButton = uibutton(app.mainParametersGrid, 'push', ...
            'Text', 'Load file', ...
            'ButtonPushedFcn', createCallbackFcn(app, @LoadfileButtonPushed, true), ...
            'Tooltip', {'Load a raw video file (formats : .raw, .cine, .holo)'}, ...
            'BackgroundColor', grayButtonColor, ...
            'FontColor', fontColor);
        app.LoadfileButton.Layout.Row = 1;
        app.LoadfileButton.Layout.Column = 2;

        app.fileLoadedLamp = uilamp(app.mainParametersGrid);
        app.fileLoadedLamp.Layout.Row = 1;
        app.fileLoadedLamp.Layout.Column = 3;
        app.fileLoadedLamp.Color = [0.5 0.5 0.5]; % gray = no file, orange = loading, green = loaded, red = error
        app.fileLoadedLamp.Tooltip = {'Indicates the file loading status: gray = no file, orange = loading, green = loaded, red = error'};

        % buttons row 2
        app.LoadConfigButton = uibutton(app.mainParametersGrid, 'push', ...
            'Text', 'Load config', ...
            'ButtonPushedFcn', createCallbackFcn(app, @LoadConfigButtonPushed, true), ...
            'Tooltip', {'Load a configuration for the video rendering of a file'}, ...
            'BackgroundColor', grayButtonColor, ...
            'FontColor', fontColor);
        app.LoadConfigButton.Layout.Row = 2;
        app.LoadConfigButton.Layout.Column = 1;

        app.SaveConfigButton = uibutton(app.mainParametersGrid, 'push', ...
            'Text', 'Save config', ...
            'ButtonPushedFcn', createCallbackFcn(app, @SaveConfigButtonPushed, true), ...
            'Tooltip', {'Save a configuration for the video rendering of a file'}, ...
            'BackgroundColor', grayButtonColor, ...
            'FontColor', fontColor);
        app.SaveConfigButton.Layout.Row = 2;
        app.SaveConfigButton.Layout.Column = 2;

        % Clear configs button (under the lamp, row 2, col 3)
        app.ClearConfigsButton = uibutton(app.mainParametersGrid, 'push', ...
            'Text', 'Clear configs', ...
            'ButtonPushedFcn', createCallbackFcn(app, @ClearConfigsButtonPushed, true), ...
            'Tooltip', {'Delete all saved parameter files for this file'}, ...
            'BackgroundColor', grayButtonColor, ...
            'FontColor', fontColor);
        app.ClearConfigsButton.Layout.Row = 2;
        app.ClearConfigsButton.Layout.Column = 3;

        app.lambdaLabel = uilabel(app.mainParametersGrid);
        app.lambdaLabel.FontColor = fontColor;
        app.lambdaLabel.Tooltip = {'Laser''s wavelength for light propagation calculations in (m)'};
        app.lambdaLabel.Text = 'λ (m)';
        app.lambdaLabel.Layout.Row = 4;
        app.lambdaLabel.Layout.Column = 1;
        app.lambdaLabel.HorizontalAlignment = 'right';

        app.lambda = uieditfield(app.mainParametersGrid, 'numeric', ...
            'Limits', [0 Inf], ...
            'ValueChangedFcn', createCallbackFcn(app, @refreshClass, true), ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor, ...
            'Tooltip', {'Laser wavelength in nanometers'});
        app.lambda.Layout.Row = 4;
        app.lambda.Layout.Column = 2;

        app.fsLabel = uilabel(app.mainParametersGrid);
        app.fsLabel.FontColor = fontColor;
        app.fsLabel.Tooltip = {'Sampling frequency in (kHz)'};
        app.fsLabel.Text = 'fs (kHz)';
        app.fsLabel.Layout.Row = 5;
        app.fsLabel.Layout.Column = 1;
        app.fsLabel.HorizontalAlignment = 'right';

        app.fs = uieditfield(app.mainParametersGrid, 'numeric', ...
            'Limits', [0 Inf], ...
            'ValueChangedFcn', createCallbackFcn(app, @refreshClass, true), ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor, ...
            'Tooltip', {'Sampling frequency in (kHz)'});
        app.fs.Layout.Row = 5;
        app.fs.Layout.Column = 2;

        app.pixelPitchLabel = uilabel(app.mainParametersGrid);
        app.pixelPitchLabel.FontColor = fontColor;
        app.pixelPitchLabel.Tooltip = {'Camera pixel pitch (distance between spatial sampling points) in (m)'};
        app.pixelPitchLabel.Text = 'Pixel pitch (m)';
        app.pixelPitchLabel.Layout.Row = 6;
        app.pixelPitchLabel.Layout.Column = 1;
        app.pixelPitchLabel.HorizontalAlignment = 'right';

        app.ppx = uieditfield(app.mainParametersGrid, 'numeric', ...
            'Limits', [0 10], ...
            'ValueChangedFcn', createCallbackFcn(app, @refreshClass, true), ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor);
        app.ppx.Layout.Row = 6;
        app.ppx.Layout.Column = 2;

        app.ppy = uieditfield(app.mainParametersGrid, 'numeric', ...
            'Limits', [0 10], ...
            'ValueChangedFcn', createCallbackFcn(app, @refreshClass, true), ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor);
        app.ppy.Layout.Row = 6;
        app.ppy.Layout.Column = 3;

        app.imageSizeLabel = uilabel(app.mainParametersGrid);
        app.imageSizeLabel.FontColor = fontColor;
        app.imageSizeLabel.Tooltip = {'Size of the recorded interferograms in pixels (width x height)'};
        app.imageSizeLabel.Text = 'Image size (px)';
        app.imageSizeLabel.Layout.Row = 7;
        app.imageSizeLabel.Layout.Column = 1;
        app.imageSizeLabel.HorizontalAlignment = 'right';

        app.Nx = uieditfield(app.mainParametersGrid, 'numeric', ...
            'Limits', [0 Inf], ...
            'Editable', 'off', ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor, ...
            'Tooltip', {'Width of the recorded interferograms'});
        app.Nx.Layout.Row = 7;
        app.Nx.Layout.Column = 2;

        app.Ny = uieditfield(app.mainParametersGrid, 'numeric', ...
            'Limits', [0 Inf], ...
            'Editable', 'off', ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor, ...
            'Tooltip', {'Height of the recorded interferograms'});
        app.Ny.Layout.Row = 7;
        app.Ny.Layout.Column = 3;

        app.numworkersSpinnerLabel = uilabel(app.mainParametersGrid);
        app.numworkersSpinnerLabel.FontColor = fontColor;
        app.numworkersSpinnerLabel.Tooltip = {'Number of worker used for the video rendering (depends of the working station)'};
        app.numworkersSpinnerLabel.Text = '# Workers';
        app.numworkersSpinnerLabel.Layout.Row = 8;
        app.numworkersSpinnerLabel.Layout.Column = 1;
        app.numworkersSpinnerLabel.HorizontalAlignment = 'right';

        app.parforArg = uispinner(app.mainParametersGrid);
        app.parforArg.ValueChangingFcn = createCallbackFcn(app, @refreshClass, true);

        try
            maxWorkers = parcluster('local').NumWorkers;
        catch
            maxWorkers = 0;
        end

        app.parforArg.Limits = [-1 maxWorkers];
        app.parforArg.ValueChangedFcn = createCallbackFcn(app, @refreshClass, true);
        app.parforArg.FontColor = fontColor;
        app.parforArg.BackgroundColor = darkBackgroundColor;
        app.parforArg.Tooltip = {'Number of worker used for the video rendering (depends of the working station)'};
        app.parforArg.Value = min(10, maxWorkers);
        app.parforArg.Layout.Row = 8;
        app.parforArg.Layout.Column = 2;

        app.positioninfileSliderLabel = uilabel(app.mainParametersGrid);
        app.positioninfileSliderLabel.FontColor = fontColor;
        app.positioninfileSliderLabel.Text = {'Position in file'};
        app.positioninfileSliderLabel.Layout.Row = 9;
        app.positioninfileSliderLabel.Layout.Column = 1;
        app.positioninfileSliderLabel.HorizontalAlignment = 'right';

        app.positioninfileSlider = uislider(app.mainParametersGrid);
        app.positioninfileSlider.Limits = [0 1];
        app.positioninfileSlider.MajorTicks = [];
        app.positioninfileSlider.ValueChangedFcn = createCallbackFcn(app, @positioninfileSliderValueChanged, true);
        app.positioninfileSlider.MinorTicks = [0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.65 0.7 0.75 0.8 0.85 0.9 0.95 1];
        app.positioninfileSlider.Tooltip = {'Change value to display a different video timestamp in the gui.'};
        app.positioninfileSlider.Layout.Row = 9;
        app.positioninfileSlider.Layout.Column = [2 3];

        app.batchIndexLabel = uilabel(app.mainParametersGrid);
        app.batchIndexLabel.FontColor = fontColor;
        app.batchIndexLabel.Text = {'Batch index'};
        app.batchIndexLabel.Layout.Row = 10;
        app.batchIndexLabel.Layout.Column = 1;
        app.batchIndexLabel.HorizontalAlignment = 'right';

        app.batchIndexField = uieditfield(app.mainParametersGrid, 'numeric', ...
            'Editable', 'off', ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor, ...
            'ValueDisplayFormat', '%.0f', ...
            'Limits', [1 Inf], ...
            'Tooltip', {'Current batch index based on the position in file and the batch stride (read-only)'});
        app.batchIndexField.Layout.Row = 10;
        app.batchIndexField.Layout.Column = 2;

        app.framePosition = uieditfield(app.mainParametersGrid, 'numeric', ...
            'Limits', [0 Inf], ...
            'RoundFractionalValues', 'on', ...
            'ValueDisplayFormat', '%.0f', ...
            'ValueChangedFcn', createCallbackFcn(app, @framePositionValueChanged, true), ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor, ...
            'Tooltip', {''});
        app.framePosition.Layout.Row = 10;
        app.framePosition.Layout.Column = 3;

        % Column 11

        app.AdvancedButton = uibutton(app.mainParametersGrid, 'push', ...
            'Text', 'Advanced', ...
            'ButtonPushedFcn', createCallbackFcn(app, @AdvancedButtonPushed, true), ...
            'Tooltip', {'Advanced settings'}, ...
            'BackgroundColor', grayButtonColor, ...
            'FontColor', fontColor);
        app.AdvancedButton.Layout.Row = 12;
        app.AdvancedButton.Layout.Column = 1;

        app.RefreshAppButton = uibutton(app.mainParametersGrid, 'push', ...
            'Text', 'Refresh app', ...
            'ButtonPushedFcn', createCallbackFcn(app, @RefreshAppButtonPushed, true), ...
            'Tooltip', {'Refresh the app'}, ...
            'BackgroundColor', grayButtonColor, ...
            'FontColor', fontColor);
        app.RefreshAppButton.Layout.Row = 12;
        app.RefreshAppButton.Layout.Column = 2;

        app.FileNameLabel = uilabel(app.mainParametersGrid, ...
            'Text', 'File name:', ...
            'FontColor', fontColor, ...
            'HorizontalAlignment', 'right');
        app.FileNameLabel.Layout.Row = 3;
        app.FileNameLabel.Layout.Column = 1;

        app.FileNameField = uieditfield(app.mainParametersGrid, 'text', ...
            'Editable', 'off', ...
            'Value', '', ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor, ...
            'Tooltip', {'Name of the currently loaded file'});
        app.FileNameField.Layout.Row = 3;
        app.FileNameField.Layout.Column = [2 3];
    end

    % -----------------------------------------------------------------------
    function createBatchVideoPanel(app)

        backgroundColor = [0.2 0.2 0.2];
        darkBackgroundColor = [0.15 0.15 0.15];
        fontColor = [1 1 1];
        renderButtonColor = [0.2, 0.6, 0.2];

        app.batchPanel = uipanel(app.mainParametersGrid, ...
            'Title', 'Batch parameters', ...
            'BackgroundColor', backgroundColor, ...
            'ForegroundColor', fontColor, ...
            'BorderType', 'line', ...
            'FontWeight', 'bold');
        app.batchPanel.Layout.Row = 11;
        app.batchPanel.Layout.Column = [1 3];

        app.batchGrid = uigridlayout(app.batchPanel, [10 3]);
        app.batchGrid.RowHeight = {'1x', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit', 'fit'};
        app.batchGrid.ColumnWidth = {'fit', 'fit', '1x'};
        app.batchGrid.Padding = [10 10 10 10];
        app.batchGrid.RowSpacing = 5;
        app.batchGrid.ColumnSpacing = 5;
        app.batchGrid.BackgroundColor = backgroundColor;

        p = app.batchGrid;

        % listBox row 1
        app.imageTypesListBox = uilistbox(p);
        app.imageTypesListBox.Items = {};
        app.imageTypesListBox.Multiselect = 'on';
        app.imageTypesListBox.ValueChangedFcn = createCallbackFcn(app, @refreshClass, true);
        app.imageTypesListBox.Tooltip = {'Image types output giving extracting different informations from a batch of frames'};
        app.imageTypesListBox.FontColor = [1 1 1];
        app.imageTypesListBox.BackgroundColor = darkBackgroundColor;
        app.imageTypesListBox.Layout.Row = 1;
        app.imageTypesListBox.Layout.Column = [1 3];
        app.imageTypesListBox.Value = {};

        % buttons row 3
        app.VideoRenderingButton = uibutton(p, 'push', ...
            'Text', 'Video Rendering', ...
            'ButtonPushedFcn', createCallbackFcn(app, @VideoRenderingButtonPushed, true), ...
            'BackgroundColor', renderButtonColor, ...
            'FontColor', fontColor, ...
            'Tooltip', {'Render ''batchSize'' frame batchs spaced by ''batchStride'' and output a video of different image types'});
        app.VideoRenderingButton.Layout.Row = 2;
        app.VideoRenderingButton.Layout.Column = 1;

        app.VideoRenderingLamp = uilamp(p);
        app.VideoRenderingLamp.Layout.Row = 2;
        app.VideoRenderingLamp.Layout.Column = 2;
        app.VideoRenderingLamp.Color = [0.5 0.5 0.5]; % gray = no file, orange = loading, green = loaded, red = error
        app.VideoRenderingLamp.Tooltip = {'Indicates the video rendering status: gray = not rendered, orange = rendering in progress, green = rendered, red = error'};

        % sizes row 4 5 6
        app.batchSizeLabel = uilabel(p);
        app.batchSizeLabel.FontColor = fontColor;
        app.batchSizeLabel.Layout.Row = 3;
        app.batchSizeLabel.Layout.Column = 1;
        app.batchSizeLabel.Text = 'Batch size';
        app.batchSizeLabel.HorizontalAlignment = 'right';

        app.batchSize = uieditfield(p, 'numeric', ...
            'Limits', [0 Inf], ...
            'ValueDisplayFormat', '%.0f', ...
            'ValueChangedFcn', createCallbackFcn(app, @refreshClass, true), ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor, ...
            'Tooltip', {'Number of interferograms used to compute the image'});
        app.batchSize.Layout.Row = 3;
        app.batchSize.Layout.Column = 2;

        app.batchStrideLabel = uilabel(p);
        app.batchStrideLabel.FontColor = fontColor;
        app.batchStrideLabel.Layout.Row = 4;
        app.batchStrideLabel.Layout.Column = 1;
        app.batchStrideLabel.Text = 'Batch stride';
        app.batchStrideLabel.HorizontalAlignment = 'right';

        app.batchStride = uieditfield(p, 'numeric', ...
            'Limits', [0 Inf], ...
            'ValueDisplayFormat', '%.0f', ...
            'ValueChangedFcn', createCallbackFcn(app, @refreshClass, true), ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor, ...
            'Tooltip', {'Number of interferograms to skip between two images'});
        app.batchStride.Layout.Row = 4;
        app.batchStride.Layout.Column = 2;

        app.refBatchSizeLabel = uilabel(p);
        app.refBatchSizeLabel.FontColor = fontColor;
        app.refBatchSizeLabel.Layout.Row = 5;
        app.refBatchSizeLabel.Layout.Column = 1;
        app.refBatchSizeLabel.Text = 'Reference batch size';
        app.refBatchSizeLabel.HorizontalAlignment = 'right';

        app.refBatchSize = uieditfield(p, 'numeric', ...
            'Limits', [0 Inf], ...
            'ValueChangedFcn', createCallbackFcn(app, @refreshClass, true), ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor, ...
            'Tooltip', {'Number of interferograms used to compute the image used as reference in registration'});
        app.refBatchSize.Layout.Row = 5;
        app.refBatchSize.Layout.Column = 2;

        % Registration row 7 8 9 10
        app.imageRegistration = uicheckbox(p, ...
            'ValueChangedFcn', createCallbackFcn(app, @registrationCheckBoxValueChanged, true), ...
            'FontColor', fontColor, ...
            'Tooltip', {'Activate frame to frame translation registration of images'}, ...
            'Text', 'Image registration');
        app.imageRegistration.Layout.Row = 7;
        app.imageRegistration.Layout.Column = [1 2];

        app.registrationDiskLabel = uilabel(p);
        app.registrationDiskLabel.FontColor = fontColor;
        app.registrationDiskLabel.Layout.Row = 8;
        app.registrationDiskLabel.Layout.Column = 1;
        app.registrationDiskLabel.Text = 'Registration disk ratio';
        app.registrationDiskLabel.HorizontalAlignment = 'right';

        app.registrationDiskRatio = uieditfield(p, 'numeric', ...
            'Limits', [0 1000], ...
            'ValueChangedFcn', createCallbackFcn(app, @registrationDiskRatioValueChanged, true), ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor, ...
            'Tooltip', {'Size of a disk centered on the images used to compute the registration shifts (0 is empty and 1 is a disk of the maximum dimension).'});
        app.registrationDiskRatio.Layout.Row = 8;
        app.registrationDiskRatio.Layout.Column = 2;

    end

    % -----------------------------------------------------------------------
    function createrenderingParametersPanel(app)

        backgroundColor = [0.2 0.2 0.2];
        darkBackgroundColor = [0.15 0.15 0.15];
        fontColor = [1 1 1];
        grayButtonColor = [0.5 0.5 0.5];
        renderButtonColor = [0.2, 0.6, 0.2];

        app.renderingParametersPanel = uipanel(app.RootGrid, ...
            'Title', 'Rendering parameters', ...
            'BackgroundColor', backgroundColor, ...
            'ForegroundColor', fontColor, ...
            'BorderType', 'line', ...
            'FontWeight', 'bold');
        app.renderingParametersPanel.Layout.Row = 2;
        app.renderingParametersPanel.Layout.Column = 2;

        app.renderingParametersGrid = uigridlayout(app.renderingParametersPanel, [14 3]);
        app.renderingParametersGrid.RowHeight = repmat({'fit'}, 1, 14);
        app.renderingParametersGrid.ColumnWidth = {'fit', 'fit', 'fit'};
        app.renderingParametersGrid.Padding = [10 10 10 10];
        app.renderingParametersGrid.RowSpacing = 5;
        app.renderingParametersGrid.ColumnSpacing = 5;
        app.renderingParametersGrid.BackgroundColor = backgroundColor;

        p = app.renderingParametersGrid;

        % Spatial filtering parameters row 1

        app.spatialFilter = uicheckbox(p, ...
            'ValueChangedFcn', createCallbackFcn(app, @spatialFilterCheckBoxValueChanged, true), ...
            'FontColor', fontColor, ...
            'Tooltip', {'Filter the spatial frequencies of the interferograms keeping only those between spatial filter range1 and 2 (between 0 and 1-> highest dimension)'}, ...
            'Text', 'Spatial filter');
        app.spatialFilter.Layout.Column = 1;
        app.spatialFilter.Layout.Row = 1;

        app.spatialFilterRange1 = uieditfield(p, 'numeric', ...
            'Limits', [0 1], ...
            'ValueChangedFcn', createCallbackFcn(app, @refreshClass, true), ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor, ...
            'Tooltip', {'Lower bound of the spatial filter range (0 to 1)'});
        app.spatialFilterRange1.Layout.Column = 2;
        app.spatialFilterRange1.Layout.Row = 1;

        app.spatialFilterRange2 = uieditfield(p, 'numeric', ...
            'Limits', [0 1], ...
            'ValueChangedFcn', createCallbackFcn(app, @refreshClass, true), ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor, ...
            'Tooltip', {'Upper bound of the spatial filter range (0 to 1)'});
        app.spatialFilterRange2.Layout.Column = 3;
        app.spatialFilterRange2.Layout.Row = 1;

        % Local spatial transform row 2

        app.spatialTransformLabel = uilabel(p);
        app.spatialTransformLabel.HorizontalAlignment = 'right';
        app.spatialTransformLabel.FontColor = fontColor;
        app.spatialTransformLabel.Layout.Column = 1;
        app.spatialTransformLabel.Layout.Row = 2;
        app.spatialTransformLabel.Text = 'Spatial transform';

        app.spatialTransform = uidropdown(p);
        app.spatialTransform.ValueChangedFcn = createCallbackFcn(app, @refreshClass, true);
        app.spatialTransform.Tooltip = {'Type of light propagation calculation to perform (depends of the experimental setup)'};
        app.spatialTransform.FontColor = fontColor;
        app.spatialTransform.BackgroundColor = grayButtonColor;
        app.spatialTransform.Layout.Column = [2 3];
        app.spatialTransform.Layout.Row = 2;
        app.spatialTransform.Items = {'Angular spectrum', 'Fresnel', 'None'};

        % Spatial propagation row 3
        app.spatialPropagationLabel = uilabel(p);
        app.spatialPropagationLabel.HorizontalAlignment = 'right';
        app.spatialPropagationLabel.FontColor = fontColor;
        app.spatialPropagationLabel.Layout.Column = 1;
        app.spatialPropagationLabel.Layout.Row = 3;
        app.spatialPropagationLabel.Text = 'Spatial propagation';

        app.spatialPropagation = uieditfield(p, 'numeric', ...
            'Limits', [0 Inf], ...
            'ValueChangedFcn', createCallbackFcn(app, @refreshClass, true), ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor, ...
            'Tooltip', {'Distance of spatial reconstruction using the preceding calculation scheme in (m) '});
        app.spatialPropagation.Layout.Column = 2;
        app.spatialPropagation.Layout.Row = 3;

        app.AutofocusButton = uibutton(p, 'push', ...
            'Text', 'Autofocus', ...
            'Tooltip', {['Estimate Noll-Zernike defocus from Doppler ', ...
                'Shack-Hartmann sub-apertures and apply phase correction ', ...
            'before Angular Spectrum propagation.']}, ...
            'ButtonPushedFcn', createCallbackFcn(app, @AutofocusButtonPushed, true), ...
            'BackgroundColor', grayButtonColor, ...
            'FontColor', fontColor);
        app.AutofocusButton.Layout.Column = 3;
        app.AutofocusButton.Layout.Row = 3;

        % Padding row 4
        app.PaddingLabel = uilabel(p);
        app.PaddingLabel.HorizontalAlignment = 'right';
        app.PaddingLabel.FontColor = fontColor;
        app.PaddingLabel.Layout.Column = 1;
        app.PaddingLabel.Layout.Row = 4;
        app.PaddingLabel.Text = 'Padding N';

        app.PaddingNum = uieditfield(p, 'numeric', ...
            'Limits', [0 Inf], ...
            'ValueChangedFcn', createCallbackFcn(app, @refreshClass, true), ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor, ...
            'Tooltip', {'Distance of spatial reconstruction using the preceding calculation scheme in (m) '});
        app.PaddingNum.Layout.Column = 2;
        app.PaddingNum.Layout.Row = 4;

        % SVD filtering row 5 6

        app.svd_filter = uicheckbox(p, ...
            'ValueChangedFcn', createCallbackFcn(app, @svdFilterCheckBoxValueChanged, true), ...
            'FontColor', fontColor, ...
            'Tooltip', {'Filter to remove intense time correlated feature images of the output fluctuation hologram using eigenvalue decomposition of the correlation matrix of frames.'}, ...
            'Text', 'SVD Filter');
        app.svd_filter.Layout.Column = 1;
        app.svd_filter.Layout.Row = 5;

        app.svdThresholdResetButton = uibutton(p, 'push', ...
            'Text', 'Reset', ...
            'ButtonPushedFcn', createCallbackFcn(app, @svdThresholdResetButtonPushed, true), ...
            'BackgroundColor', grayButtonColor, ...
            'FontColor', fontColor);
        app.svdThresholdResetButton.Layout.Column = 2;
        app.svdThresholdResetButton.Layout.Row = 5;

        app.svdThreshold = uieditfield(p, 'numeric', ...
            'Limits', [0 Inf], ...
            'ValueChangedFcn', createCallbackFcn(app, @refreshClass, true), ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor, ...
            'Tooltip', {'number of first eigenvectors to remove from the fluctuation holograms (zero means default => frequencyRange1/fs * batchSize * 2)'});
        app.svdThreshold.Layout.Column = 3;
        app.svdThreshold.Layout.Row = 5;

        app.svdStrideLabel = uilabel(p);
        app.svdStrideLabel.HorizontalAlignment = 'right';
        app.svdStrideLabel.FontColor = fontColor;
        app.svdStrideLabel.Layout.Column = 1;
        app.svdStrideLabel.Layout.Row = 6;
        app.svdStrideLabel.Text = 'SVD stride';

        app.svdStride = uieditfield(p, 'numeric', ...
            'Limits', [0 Inf], ...
            'ValueChangedFcn', createCallbackFcn(app, @refreshClass, true), ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor, ...
            'Value', 1, ...
            'Tooltip', {'Sub sampling parameter for faster SVD calculations. Defaults to 1 -> full image, 2 -> one pixel on two, ...'});
        app.svdStride.Layout.Row = 6;
        app.svdStride.Layout.Column = 2;

        % Time transform row 7
        app.timeTransformLabel = uilabel(p);
        app.timeTransformLabel.FontColor = fontColor;
        app.timeTransformLabel.Layout.Column = 1;
        app.timeTransformLabel.Layout.Row = 7;
        app.timeTransformLabel.Text = 'Time transform';
        app.timeTransformLabel.HorizontalAlignment = 'right';

        app.timeTransform = uidropdown(p);
        app.timeTransform.ValueChangedFcn = createCallbackFcn(app, @refreshClass, true);
        app.timeTransform.Tooltip = {'Time tranformation to aggregate the fluctuation hologram. FFT is a frequency domain tranform and pass bad filter, PCA is a projection on intensity ordered eigen vectors, ICA is experimental.'};
        app.timeTransform.FontColor = fontColor;
        app.timeTransform.BackgroundColor = grayButtonColor;
        app.timeTransform.Layout.Column = [2 3];
        app.timeTransform.Layout.Row = 7;
        app.timeTransform.Items = {'FFT', 'PCA', 'ICA'};

        % Frequency range row 8 9 10
        app.frequencyRangeLabel = uilabel(p);
        app.frequencyRangeLabel.FontColor = fontColor;
        app.frequencyRangeLabel.Text = 'Frequency Range';
        app.frequencyRangeLabel.Layout.Column = 1;
        app.frequencyRangeLabel.Layout.Row = 8;
        app.frequencyRangeLabel.HorizontalAlignment = 'right';

        app.frequencyRange1 = uieditfield(p, 'numeric', ...
            'Limits', [0 Inf], ...
            'ValueChangedFcn', createCallbackFcn(app, @refreshClass, true), ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor, ...
            'Placeholder', 'f1', ...
            'Tooltip', {'Frequency range to apply the time transform (if different from time range)'});
        app.frequencyRange1.Layout.Column = 2;
        app.frequencyRange1.Layout.Row = 8;

        app.frequencyRange2 = uieditfield(p, 'numeric', ...
            'Limits', [0 Inf], ...
            'ValueChangedFcn', createCallbackFcn(app, @frequencyRange2ValueChanged, true), ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor, ...
            'Placeholder', 'f2', ...
            'Tooltip', {'Frequency range to apply the time transform (if different from time range)'});
        app.frequencyRange2.Layout.Column = 3;
        app.frequencyRange2.Layout.Row = 8;

        app.frequencyRangeBandRatioLabel = uilabel(p);
        app.frequencyRangeBandRatioLabel.FontColor = fontColor;
        app.frequencyRangeBandRatioLabel.Text = 'Band ratio range';
        app.frequencyRangeBandRatioLabel.Layout.Row = 9;
        app.frequencyRangeBandRatioLabel.Layout.Column = 1;
        app.frequencyRangeBandRatioLabel.HorizontalAlignment = 'right';

        app.frequencyRangeBandRatio1 = uieditfield(p, 'numeric', ...
            'Limits', [0 Inf], ...
            'ValueChangedFcn', createCallbackFcn(app, @refreshClass, true), ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor, ...
            'Placeholder', 'fr1', ...
            'Tooltip', {'Frequency range to apply the intermediary time transform (if different from time range)'});
        app.frequencyRangeBandRatio1.Layout.Column = 2;
        app.frequencyRangeBandRatio1.Layout.Row = 9;

        app.frequencyRangeBandRatio2 = uieditfield(p, 'numeric', ...
            'Limits', [0 Inf], ...
            'ValueChangedFcn', createCallbackFcn(app, @refreshClass, true), ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor, ...
            'Placeholder', 'fr2', ...
            'Tooltip', {'Frequency range to apply the intermediary time transform (if different from time range)'});
        app.frequencyRangeBandRatio2.Layout.Column = 3;
        app.frequencyRangeBandRatio2.Layout.Row = 9;

        app.indexRangeLabel = uilabel(p);
        app.indexRangeLabel.FontColor = fontColor;
        app.indexRangeLabel.Text = 'Index range';
        app.indexRangeLabel.Layout.Column = 1;
        app.indexRangeLabel.Layout.Row = 10;
        app.indexRangeLabel.HorizontalAlignment = 'right';

        app.indexRange1 = uieditfield(p, 'numeric', ...
            'Limits', [0 Inf], ...
            'ValueChangedFcn', createCallbackFcn(app, @refreshClass, true), ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor, ...
            'Placeholder', 'i1', ...
            'Tooltip', {'Index range to apply the transform (if different from time range)'});
        app.indexRange1.Layout.Column = 2;
        app.indexRange1.Layout.Row = 10;

        app.indexRange2 = uieditfield(p, 'numeric', ...
            'Limits', [0 Inf], ...
            'ValueChangedFcn', createCallbackFcn(app, @refreshClass, true), ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor, ...
            'Placeholder', 'i2', ...
            'Tooltip', {'Index range to apply the transform (if different from time range)'});
        app.indexRange2.Layout.Column = 3;
        app.indexRange2.Layout.Row = 10;

        % Other parameters row 11 12 13
        app.flat_field_gwLabel = uilabel(p);
        app.flat_field_gwLabel.HorizontalAlignment = 'right';
        app.flat_field_gwLabel.FontColor = fontColor;
        app.flat_field_gwLabel.Text = 'Flatfield';
        app.flat_field_gwLabel.Layout.Column = 1;
        app.flat_field_gwLabel.Layout.Row = 11;

        app.flat_field_gw = uieditfield(p, 'numeric', ...
            'Limits', [0 Inf], ...
            'ValueChangedFcn', createCallbackFcn(app, @refreshClass, true), ...
            'FontColor', fontColor, ...
            'BackgroundColor', darkBackgroundColor, ...
            'Placeholder', 'fw', ...
            'Tooltip', {'flat_filed parameter to apply to some of the output images (gaussian width in pixels to divide the image to correct uneven illumination of images).'});
        app.flat_field_gw.Layout.Column = 2;
        app.flat_field_gw.Layout.Row = 11;

        app.flip_y = uicheckbox(p, ...
            'ValueChangedFcn', createCallbackFcn(app, @refreshClass, true), ...
            'FontColor', fontColor, ...
            'Tooltip', {'Flip the output image vertically'}, ...
            'Text', 'Flip y');
        app.flip_y.Layout.Column = 3;
        app.flip_y.Layout.Row = 12;

        app.flip_x = uicheckbox(p, ...
            'ValueChangedFcn', createCallbackFcn(app, @refreshClass, true), ...
            'FontColor', fontColor, ...
            'Tooltip', {'Flip the output image horizontally'}, ...
            'Text', 'Flip x');
        app.flip_x.Layout.Column = 2;
        app.flip_x.Layout.Row = 12;

        app.square = uicheckbox(p, ...
            'ValueChangedFcn', createCallbackFcn(app, @refreshClass, true), ...
            'FontColor', fontColor, ...
            'Tooltip', {'Crop the output image to a square aspect ratio'}, ...
            'Text', 'Square');
        app.square.Layout.Column = 1;
        app.square.Layout.Row = 12;

        app.ImproveContrast = uicheckbox(p, ...
            'ValueChangedFcn', createCallbackFcn(app, @refreshClass, true), ...
            'FontColor', fontColor, ...
            'Tooltip', {'Improve the contrast by rescaling the previewed frame'}, ...
            'Text', 'Improve contrast');
        app.ImproveContrast.Layout.Column = 1;
        app.ImproveContrast.Layout.Row = 13;

        app.CornerCompensation = uicheckbox(p, ...
            'ValueChangedFcn', createCallbackFcn(app, @refreshClass, true), ...
            'FontColor', fontColor, ...
            'Tooltip', {'Substract the signal from the corner'}, ...
            'Text', 'Corner compensation', ...
            'Value', true);
        app.CornerCompensation.Layout.Column = [2 3];
        app.CornerCompensation.Layout.Row = 13;

        app.RenderPreviewLamp = uilamp(p);
        app.RenderPreviewLamp.Color = [0.5 0.5 0.5];
        app.RenderPreviewLamp.Layout.Column = 1;
        app.RenderPreviewLamp.Layout.Row = 14;

        app.RenderPreviewButton = uibutton(p, 'push', ...
            'Text', 'Render preview', ...
            'ButtonPushedFcn', createCallbackFcn(app, @RenderPreviewButtonPushed, true), ...
            'Tooltip', {'Render the preview frame with the current parameters settings'}, ...
            'BackgroundColor', renderButtonColor, ...
            'FontColor', fontColor);
        app.RenderPreviewButton.Layout.Column = 2;
        app.RenderPreviewButton.Layout.Row = 14;

        app.SavePreviewButton = uibutton(p, 'push', ...
            'Text', 'Save preview', ...
            'ButtonPushedFcn', createCallbackFcn(app, @SavePreviewButtonPushed, true), ...
            'Tooltip', {'Save the preview frame with the current parameters settings'}, ...
            'BackgroundColor', grayButtonColor, ...
            'FontColor', fontColor);
        app.SavePreviewButton.Layout.Column = 3;
        app.SavePreviewButton.Layout.Row = 14;

    end

    % -----------------------------------------------------------------------
    function createImageViewsAndMenus(app)
        % Image and annotation share a borderless, resizable container.
        app.ImageDisplayPanel = uipanel(app.RootGrid, ...
            'BorderType', 'none', ...
            'BackgroundColor', [0.2 0.2 0.2], ...
            'AutoResizeChildren', 'off');
        app.ImageDisplayPanel.Layout.Row = 1;
        app.ImageDisplayPanel.Layout.Column = [2 3];

        app.Image = uiimage(app.ImageDisplayPanel, ...
            'ScaleMethod', 'fit');

        % Created after the image so that the label overlays it.
        app.ImageTypeAnnotation = uilabel(app.ImageDisplayPanel, ...
            'Text', '', ...
            'Interpreter', 'none', ...
            'FontColor', [1 1 1], ...
            'BackgroundColor', [0 0 0], ...
            'FontWeight', 'bold', ...
            'FontSize', 12, ...
            'HorizontalAlignment', 'left', ...
            'VerticalAlignment', 'center', ...
            'Visible', 'off');

        app.ImageDisplayPanel.SizeChangedFcn = ...
            @(~, ~) app.layoutImageDisplay();
        app.layoutImageDisplay();

        app.RightClickImageContextMenu = uicontextmenu(app.HoloDopplerUIFigure);

        app.NextMenu = uimenu(app.RightClickImageContextMenu);
        app.NextMenu.MenuSelectedFcn = @(~, ~) app.changeMenu('next');
        app.NextMenu.Text = 'Next';

        app.ViewAllMenu = uimenu(app.RightClickImageContextMenu);
        app.ViewAllMenu.MenuSelectedFcn = createCallbackFcn(app, @ViewAllMenuSelected, true);
        app.ViewAllMenu.Text = 'View all images';

        app.Image.ContextMenu = app.RightClickImageContextMenu;
        app.ImageTypeAnnotation.ContextMenu = app.RightClickImageContextMenu;
    end

end % createComponents methods block

% =========================================================================
% App construction and deletion
% =========================================================================
methods (Access = public)

    function app = holodoppler
        createComponents(app)
        registerApp(app, app.HoloDopplerUIFigure)
        runStartupFcn(app, @startupFcn)

        if nargout == 0
            clear app
        end

    end

    function fig = getMainFigure(app)
        % Return the main UIFigure handle (needed by auxiliary UIs).
        fig = app.HoloDopplerUIFigure;
    end

    function value = getWidgetValue(app, widgetName)
        % Return the current value of the UI widget named widgetName.
        % Handles NumericEditField, CheckBox, DropDown, ListBox, Spinner.
        w = app.(widgetName);

        if isempty(w) || ~isvalid(w)
            value = [];
        elseif isa(w, 'matlab.ui.control.CheckBox')
            value = logical(w.Value);
        elseif isa(w, 'matlab.ui.control.DropDown')
            value = w.Value; % char vector
        elseif isa(w, 'matlab.ui.control.ListBox')
            value = w.Value; % cell array of char
        elseif isa(w, 'matlab.ui.control.NumericEditField') || isa(w, 'matlab.ui.control.Spinner')
            value = double(w.Value);
        else
            value = w.Value;
        end

    end

    function setWidgetValue(app, widgetName, value)
        % Set the value of the UI widget named widgetName.
        w = app.(widgetName);

        if isempty(w) || ~isvalid(w)
            return
        end

        if isa(w, 'matlab.ui.control.CheckBox')
            w.Value = logical(value);
        elseif isa(w, 'matlab.ui.control.DropDown')

            if ismember(value, w.Items)
                w.Value = value;
            else
                w.Value = w.Items{1};
            end

        elseif isa(w, 'matlab.ui.control.ListBox')
            allItems = properties(ImageTypeList);
            w.Items = allItems;

            if iscell(value)
                w.Value = intersect(value, allItems, 'stable');
            else
                w.Value = {};
            end

        elseif isa(w, 'matlab.ui.control.NumericEditField') || isa(w, 'matlab.ui.control.Spinner')
            v = double(value(1));
            w.Value = min(max(v, w.Limits(1)), w.Limits(2));
        else
            w.Value = value;
        end

    end

    function setSliderLimits(app, widgetName, limits)
        % Set the Limits property of a slider widget.
        % limits = [min max]
        s = app.(widgetName);

        if isa(s, 'matlab.ui.control.Slider')
            limits = double(limits);

            if limits(2) <= limits(1)
                limits(2) = limits(1) + 1;
            end

            s.Limits = limits;
        end

    end

    % Public destructor
    function delete(app)
        diary off;

        if ~isempty(app.OriginalPath)
            path(app.OriginalPath);
        end

        if ~isempty(app.HoloDopplerUIFigure) && ...
                isgraphics(app.HoloDopplerUIFigure)
            delete(app.HoloDopplerUIFigure);
        end

    end

end

end
