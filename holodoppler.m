classdef holodoppler < matlab.apps.AppBase

% =========================================================================
% UI component handles — required public by App Designer / registerApp
% =========================================================================
properties (Access = private)
    HoloDopplerUIFigure matlab.ui.Figure

    % ---- top-level layout ----
    RootGrid matlab.ui.container.GridLayout
    Image matlab.ui.control.Image

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
    fileLoaded % was file_loaded
    OriginalPath char % path before startupFcn adds Tools folder
    MenuIndex double = 1; % which image type is currently shown in the main view
end

% =========================================================================
% Callbacks
% =========================================================================
methods (Access = private)

    % --- Startup / lifecycle -----------------------------------------------

    function startupFcn(app)
        logFile = fullfile(tempdir, ['matlab_log_' char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')) '.txt']);
        diary(logFile);
        app.OriginalPath = path;

        % Determine version
        version = 'unknown';

        if isfile(fullfile(fileparts(mfilename('fullpath')), 'version.txt'))
            v = readlines('version.txt');
            version = char(v(1));
        else
            warning('holodoppler:noVersionFile', 'version.txt not found — version will be shown as unknown.');
        end

        versionStr = ['HoloDoppler ' version];

        % Git info (branch + commit hash)
        gitInfo = '';

        appRoot = fileparts(mfilename('fullpath'));

        if exist(fullfile(appRoot, '.git'), 'dir')
            [~, branch] = system('git rev-parse --abbrev-ref HEAD');
            branch = strtrim(branch);
            [~, hash] = system('git rev-parse --short HEAD');
            hash = strtrim(hash);
            gitInfo = sprintf('Branch: %s | Commit: %s', branch, hash);
        end

        app.HoloDopplerUIFigure.Name = versionStr;

        % Add Tools folder
        addpath(fullfile(fileparts(mfilename('fullpath')), 'Tools'));

        % Show splash screen (via external function)
        if isempty(gitInfo)
            displaySplashScreen(versionStr);
        else
            displaySplashScreen(versionStr, gitInfo);
        end

        app.HD = HoloDopplerClass();
        app.updateButtonStates();
    end

    function HoloDopplerUIFigureCloseRequest(app, ~)
        diary off;
        delete(app.HoloDopplerUIFigure);
    end

    function HoloDopplerUIFigureWindowKeyPress(app, event)

        if app.fileLoaded

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

    end

    % --- File I/O callbacks ------------------------------------------------

    function LoadfileButtonPushed(app, ~)
        % Dummy off-screen figure prevents uigetfile from minimising the main GUI
        f = figure('Position', [-200 -200 1 1], 'Visible', 'off');
        cleanupObj = onCleanup(@() delete(f));

        % Define the file filter: description and extensions
        filters = { ...
                       '*.cine;*.holo', 'Supported Video Files (*.cine, *.holo)'; ...
                       '*.cine', 'Cine Files (*.cine)'; ...
                       '*.holo', 'Holo Files (*.holo)'; ...
                   };

        if isempty(app.HD.file)
            [fname, fpath] = uigetfile(filters, 'Select a video file');
        else
            % Get the directory from the full file path – safer than .dir
            currentDir = fileparts(app.HD.file.path);
            [fname, fpath] = uigetfile(filters, 'Select a video file', fullfile(currentDir, ''));
        end

        if isequal(fname, 0)
            return
        end

        try
            app.fileLoadedLamp.Color = [1 0.5 0];
            drawnow;
            app.HD.LoadFile(fullfile(fpath, fname));
            app.syncGuiFromClass();
            app.RenderPreviewButtonPushed();
            app.fileLoaded = 1;
            app.fileLoadedLamp.Color = [0 1 0];
            app.FileNameField.Value = app.HD.file.name;
        catch ME
            MEdisp(ME);
            app.fileLoaded = 0;
            app.fileLoadedLamp.Color = [1 0 0];
            drawnow;
            app.FileNameField.Value = '';
        end

        app.updateButtonStates();
        app.positioninfileSliderValueChanged();
        app.refreshClass();
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
        else
            app.Image.ImageSource = '';
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
        app.updateTimeTransformControls();
    end

    function RefreshAppButtonPushed(app, ~)
        app.syncGuiFromClass();

        if isempty(app.HD.params.imageTypes)
            return
        end

        imgs = app.HD.render.getImages(app.HD.params.imageTypes(1));

        if ~isempty(imgs)
            app.Image.ImageSource = toImageSource(imgs{randsample(numel(imgs), 1)}, app);
        else
            app.Image.ImageSource = '';
        end

    end

    function AutofocusButtonPushed(app, ~)
    % Remplace le balayage de spatialPropagation par l'estimation du defocus
    % Shack-Hartmann / Zernike Noll 4, puis relance l'aperçu corrigé.

    app.AutofocusButton.Enable = 'off';
    buttonCleanup = onCleanup( ...
        @() set(app.AutofocusButton, 'Enable', 'on')); %#ok<NASGU>
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
            NumSubapertures=[5 5], ...
            ZernikeModes=4, ...
            ShowDiagnostic=true);

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

        idx = app.MenuIndex;
        imagesTypes = app.HD.params.imageTypes;

        if direction == "next"
            num = mod(idx, length(imagesTypes)) + 1;
            app.SelectMenu(num);
        elseif direction == "previous"
            num = mod(idx - 2, length(imagesTypes)) + 1;
            app.SelectMenu(num);
        end

    end

    function SelectMenu(app, num, ~)
        imgs = app.HD.render.getImages(app.HD.params.imageTypes);

        if isempty(imgs) || isempty(imgs{num})
            app.Image.ImageSource = '';
            return
        end

        image = imgs{num};
        % Resize non-square images (except 'broadening') to square for display
        if ~ismember(app.HD.params.imageTypes{num}, {'broadening'}) && ...
                size(image, 1) ~= size(image, 2)
            maxSize = max(size(image));
            image = imresize(image, [maxSize, maxSize]);
        end

        app.Image.ImageSource = toImageSource(image, app);
        app.MenuIndex = num;
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
            app.framePosition.Value = round(app.positioninfileSlider.Value);
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

    function registrationCheckBoxValueChanged(app, ~)
        % Toggling registration enables/disables the disk ratio field
        app.registrationDiskRatio.Enable = app.imageRegistration.Value;
        app.registrationDiskLabel.Enable = app.imageRegistration.Value;
        app.refreshClass();
    end

    function spatialFilterCheckBoxValueChanged(app, ~)
        % Toggling spatial filter enables/disables its range fields
        app.spatialFilterRange1.Enable = app.spatialFilter.Value;
        app.spatialFilterRange2.Enable = app.spatialFilter.Value;
        app.refreshClass();
    end

    function svdFilterCheckBoxValueChanged(app, ~)
        % Toggling SVD filter enables/disables its threshold and stride fields
        app.svdThreshold.Enable = app.svd_filter.Value;
        app.svdThresholdResetButton.Enable = app.svd_filter.Value;
        app.svdStride.Enable = app.svd_filter.Value;
        app.svdStrideLabel.Enable = app.svd_filter.Value;
        app.refreshClass();
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

    % --- GUI <-> class sync (replaces external classtogui / guitoclass) ----

    % Push all widget values into HD (was external guitoclass)
    function syncClassFromGui(app)
        HDParamSchema.guitoclass(app.HD, app);
    end

    % Pull all HD values into widgets (was external classtogui)
    function syncGuiFromClass(app)
        HDParamSchema.classtogui(app.HD, app);
    end

    % --- Enable / disable controls based on application state -------------
    %
    % Three tiers of availability:
    %   (A) always available  — LoadfileButton, LoadConfigButton,
    %                           FolderManagerButton, AdvancedButton
    %   (B) file loaded       — everything that reads from obj.reader
    %   (C) preview rendered  — SavePreviewButton, image navigation

    function updateButtonStates(app)
        fileReady = ~isempty(app.HD) && ~isempty(app.HD.file);
        previewReady = fileReady && ~isempty(app.HD.render) && ...
            ~isempty(app.HD.render.Output);

        % ---- (B) require a loaded file ------------------------------------
        fileControls = { ...
                            app.SaveConfigButton, ...
                            app.ClearConfigsButton, ...
                            app.VideoRenderingButton, ...
                            app.RefreshAppButton, ...
                            app.RenderPreviewButton, ...
                            app.AutofocusButton, ...
                            app.imageRegistration, ...
                            app.registrationDiskRatio, ...
                            app.positioninfileSlider, ...
                            app.framePosition, ...
                            app.batchSize, ...
                            app.batchStride, ...
                            app.refBatchSize, ...
                            app.fs, ...
                            app.lambda, ...
                            app.ppx, ...
                            app.ppy, ...
                            app.spatialFilter, ...
                            app.spatialFilterRange1, ...
                            app.spatialFilterRange2, ...
                            app.PaddingNum, ...
                            app.spatialTransform, ...
                            app.spatialPropagation, ...
                            app.svd_filter, ...
                            app.svdThreshold, ...
                            app.svdThresholdResetButton, ...
                            app.svdStride, ...
                            app.timeTransform, ...
                            app.frequencyRange1, ...
                            app.frequencyRange2, ...
                            app.frequencyRangeBandRatio1, ...
                            app.frequencyRangeBandRatio2, ...
                            app.indexRange1, ...
                            app.indexRange2, ...
                            app.flat_field_gw, ...
                            app.square, ...
                            app.flip_x, ...
                            app.flip_y, ...
                            app.parforArg, ...
                            app.AdvancedButton, ...
                            app.LoadConfigButton, ...
                            app.ImproveContrast, ...
                            app.CornerCompensation, ...
                            app.FileNameField
                        };

        for k = 1:numel(fileControls)
            fileControls{k}.Enable = fileReady;
        end

        % ---- (C) require a rendered preview --------------------------------
        app.SavePreviewButton.Enable = previewReady;
        app.NextMenu.Enable = previewReady;
        app.ViewAllMenu.Enable = previewReady;

        % ---- frequency / index range: also respect the transform type ------
        % (only meaningful once a file is loaded; skip otherwise)
        if fileReady
            app.updateTimeTransformControls();
        end

        % ---- registration disk ratio: only when registration is on ---------
        if fileReady
            app.registrationDiskRatio.Enable = app.imageRegistration.Value;
            app.registrationDiskLabel.Enable = app.imageRegistration.Value;
        end

        % ---- SVD sub-controls: only when SVD filter is checked -------------
        if fileReady
            app.svdThreshold.Enable = app.svd_filter.Value;
            app.svdThresholdResetButton.Enable = app.svd_filter.Value;
            app.svdStride.Enable = app.svd_filter.Value;
            app.svdStrideLabel.Enable = app.svd_filter.Value;
        end

        % ---- Spatial filter ranges: only when spatial filter is checked ----
        if fileReady
            app.spatialFilterRange1.Enable = app.spatialFilter.Value;
            app.spatialFilterRange2.Enable = app.spatialFilter.Value;
        end

    end

    % --- refreshClass sub-routines ----------------------------------------

    function updateTimeTransformControls(app)
        useFreqRange = ismember(app.timeTransform.Value, {'FFT', 'autocorrelation', 'intercorrelation'});
        app.frequencyRangeLabel.Enable = useFreqRange;
        app.frequencyRange1.Enable = useFreqRange;
        app.frequencyRange2.Enable = useFreqRange;
        app.frequencyRangeBandRatioLabel.Enable = useFreqRange;
        app.frequencyRangeBandRatio1.Enable = useFreqRange;
        app.frequencyRangeBandRatio2.Enable = useFreqRange;
        app.indexRange1.Enable = ~useFreqRange;
        app.indexRange2.Enable = ~useFreqRange;
        app.indexRangeLabel.Enable = ~useFreqRange;
    end

end % private helpers methods block

% =========================================================================
% Component initialisation — split by panel
% =========================================================================
methods (Access = private)

    function createComponents(app)
        pathToMLAPP = fileparts(mfilename('fullpath'));

        app.createFigureAndRootGrid(pathToMLAPP);
        app.createFileSelectionPanel();
        app.createBatchVideoPanel();
        app.createrenderingParametersPanel();
        app.createImageViewsAndMenus();

        fontname(app.HoloDopplerUIFigure, 'Arial');
        fontsize(app.HoloDopplerUIFigure, 12, "points");

        app.HoloDopplerUIFigure.Visible = 'on';
    end

    % -----------------------------------------------------------------------
    function createFigureAndRootGrid(app, pathToMLAPP)

        % Computer screen Window Size
        screenSize = get(0, 'ScreenSize');
        % Set the app window position to be centered
        appWidth = 800;
        appHeight = 900;
        appX = (screenSize(3) - appWidth) / 2;
        appY = (screenSize(4) - appHeight) / 2;

        app.HoloDopplerUIFigure = uifigure('Visible', 'off', ...
            'Position', [appX appY appWidth appHeight], ...
            'Name', 'HoloDoppler', ...
            'Icon', fullfile(pathToMLAPP, 'holoDopplerLogo.png'), ...
            'CloseRequestFcn', createCallbackFcn(app, @HoloDopplerUIFigureCloseRequest, true), ...
            'WindowKeyPressFcn', createCallbackFcn(app, @HoloDopplerUIFigureWindowKeyPress, true), ...
            'WindowStyle', 'normal'); % allows maximizing on Windows

        app.RootGrid = uigridlayout(app.HoloDopplerUIFigure, [2 2], ...
            'ColumnWidth', {'fit', 'fit', '1x'}, ...
            'RowHeight', {'1x', 'fit'}, ...
            'RowSpacing', 5, ...
            'ColumnSpacing', 5, ...
            'Padding', [10 10 10 10], ...
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
        maxWorkers = parcluster('local').NumWorkers;
        app.parforArg.Limits = [-1 maxWorkers];
        app.parforArg.ValueChangedFcn = createCallbackFcn(app, @refreshClass, true);
        app.parforArg.FontColor = fontColor;
        app.parforArg.BackgroundColor = darkBackgroundColor;
        app.parforArg.Tooltip = {'Number of worker used for the video rendering (depends of the working station)'};
        app.parforArg.Value = 10;
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
            'Text', '📎 Advanced', ...
            'ButtonPushedFcn', createCallbackFcn(app, @AdvancedButtonPushed, true), ...
            'Tooltip', {'Advanced settings'}, ...
            'BackgroundColor', grayButtonColor, ...
            'FontColor', fontColor);
        app.AdvancedButton.Layout.Row = 12;
        app.AdvancedButton.Layout.Column = 1;

        app.RefreshAppButton = uibutton(app.mainParametersGrid, 'push', ...
            'Text', '👌 Refresh app', ...
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
        app.Image = uiimage(app.RootGrid);
        app.Image.Layout.Row = 1;
        app.Image.Layout.Column = [2 3];

        app.RightClickImageContextMenu = uicontextmenu(app.HoloDopplerUIFigure);

        app.NextMenu = uimenu(app.RightClickImageContextMenu);
        app.NextMenu.MenuSelectedFcn = createCallbackFcn(app, @NextMenuSelected, true);
        app.NextMenu.Text = 'Next';

        app.ViewAllMenu = uimenu(app.RightClickImageContextMenu);
        app.ViewAllMenu.MenuSelectedFcn = createCallbackFcn(app, @ViewAllMenuSelected, true);
        app.ViewAllMenu.Text = 'View all images';

        app.Image.ContextMenu = app.RightClickImageContextMenu;
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

        if isempty(w)
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

        if isempty(w)
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
            w.Value = double(value(1));
        else
            w.Value = value;
        end

    end

    function setSliderLimits(app, widgetName, limits)
        % Set the Limits property of a slider widget.
        % limits = [min max]
        s = app.(widgetName);

        if isa(s, 'matlab.ui.control.Slider')
            s.Limits = double(limits);
        end

    end

    function delete(app)
        % Restore original MATLAB path before shutting down
        if ~isempty(app.OriginalPath)
            path(app.OriginalPath);
        end

        % Turn off diary (already done in CloseRequestFcn, but safe to repeat)
        diary off;
        delete(app.HoloDopplerUIFigure);
    end

end

end
