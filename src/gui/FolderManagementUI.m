classdef FolderManagementUI < handle
% FolderManagementUI   User interface for batch rendering multiple files
%
%   FM = FolderManagementUI(APP) creates a non-modal figure that allows
%   managing a list of .cine/.holo files and their rendering configurations.
%   APP is the main HoloDoppler application object.
%
%   Each file in the list has exactly one associated configuration.

properties (Access = private)
    MainApp          % Reference to the main HoloDoppler app
    Figure           % uifigure handle
    TextArea         % uitextarea displaying the file list
    KeepZCheckbox    % uicheckbox for 'Keep z distance' option
    drawerList       % Local reference to the drawer list for easy access
    MaxWidth         % Maximum allowed width (pixels)
    MaxHeight        % Maximum allowed height (pixels)
end

methods

    function obj = FolderManagementUI(mainApp)
        % Constructor – builds and displays the UI.
        arguments
            mainApp
        end

        obj.MainApp = mainApp;
        obj.drawerList = mainApp.HD.drawer_list;
        obj.createUI();
    end

end

methods (Access = private)

    function createUI(obj)
        % Create the figure and all UI components.

        % Calculate initial height based on number of files
        initialHeight = 260 + length(obj.drawerList) * 14;

        mainApp = obj.MainApp;

        % Get main figure and screen sizes
        if isvalid(mainApp) && ismethod(mainApp, 'getMainFigure')
            mainFig = mainApp.getMainFigure();
            if isvalid(mainFig)
                mainPos = mainFig.Position;
            else
                mainPos = [100, 100, 800, 600];  % fallback
            end
        else
            mainPos = [100, 100, 800, 600];
        end

        screenSize = get(groot, 'ScreenSize');  % [left, bottom, width, height]

        % Position the window to the right of the main figure
        xPos = mainPos(1) + mainPos(3) + 20;
        yPos = mainPos(2);

        % Compute maximum width/height based on main window and screen
        availableWidth  = screenSize(3) - xPos;
        availableHeight = screenSize(4) - yPos;

        maxWidth = min(mainPos(3), availableWidth);
        maxHeight = min(mainPos(4), availableHeight);

        % Ensure a reasonable minimum
        maxWidth = max(maxWidth, 200);
        maxHeight = max(maxHeight, 200);

        obj.MaxWidth = maxWidth;
        obj.MaxHeight = maxHeight;

        % Set initial size, respecting limits
        initialWidth = min(700, maxWidth);
        initialHeight = min(initialHeight, maxHeight);
        initialHeight = max(initialHeight, 200);

        % Create figure
        obj.Figure = uifigure('Position', [xPos, yPos, initialWidth, initialHeight], ...
            'Color', [0.2, 0.2, 0.2], ...
            'Name', 'Folder management', ...
            'Resize', 'on', ...
            'WindowStyle', 'normal', ...
            'CloseRequestFcn', @(~, ~) obj.closeFigure(), ...
            'AutoResizeChildren', 'off');

        obj.Figure.SizeChangedFcn = @(~, ~) obj.clampFigureSize();

        drawnow;

        % Main grid: list area (top) + button grid (bottom)
        mainGrid = uigridlayout(obj.Figure, [2, 1], ...
            'ColumnWidth', {'1x'}, ...
            'RowHeight', {'1x', 'fit'}, ...
            'Padding', [10, 10, 10, 10], ...
            'BackgroundColor', [0.2, 0.2, 0.2], ...
            'RowSpacing', 10, ...
            'ColumnSpacing', 10);

        % Text area for file list
        if isempty(obj.drawerList)
            displayValue = {''};
        else
            displayValue = obj.drawerList;
        end

        obj.TextArea = uitextarea('Parent', mainGrid, ...
            'BackgroundColor', [0.2, 0.2, 0.2], ...
            'FontColor', [0.8, 0.8, 0.8], ...
            'Value', displayValue, ...
            'Editable', 'off');
        obj.TextArea.Layout.Row = 1;
        obj.TextArea.Layout.Column = 1;

        % Button grid: 4 rows × 3 columns
        buttonGrid = uigridlayout(mainGrid, [4, 3], ...
            'ColumnWidth', {200, 200, 200}, ...
            'RowHeight', {'fit', 'fit', 'fit', 'fit'}, ...
            'Padding', [5, 5, 5, 5], ...
            'BackgroundColor', [0.2, 0.2, 0.2]);
        buttonGrid.Layout.Row = 2;
        buttonGrid.Layout.Column = 1;

        % Checkbox
        obj.KeepZCheckbox = uicheckbox('Parent', buttonGrid, ...
            'FontColor', [1 1 1], ...
            'Text', 'Keep z distance', ...
            'Value', 1);
        obj.KeepZCheckbox.Layout.Row = 2;
        obj.KeepZCheckbox.Layout.Column = 3;

        % Common button colors
        bkgColor = [0.5, 0.5, 0.5];
        fontColor = [1, 1, 1];
        renderColor = [0.2, 0.6, 0.2];

        % Column 1 buttons
        obj.makeButton(buttonGrid, [1, 1], 'Select file', ...
            @(~, ~) obj.selectFile(), bkgColor, fontColor);
        obj.makeButton(buttonGrid, [2, 1], 'Select folder', ...
            @(~, ~) obj.selectFolder(), bkgColor, fontColor);
        obj.makeButton(buttonGrid, [3, 1], 'Select current', ...
            @(~, ~) obj.selectCurrent(), bkgColor, fontColor);
        obj.makeButton(buttonGrid, [4, 1], 'Select current Folder', ...
            @(~, ~) obj.selectCurrentFolder(), bkgColor, fontColor);

        % Column 2 buttons
        obj.makeButton(buttonGrid, [1, 2], 'Clear list', ...
            @(~, ~) obj.clearList(), bkgColor, fontColor);
        obj.makeButton(buttonGrid, [3, 2], 'Save to txt', ...
            @(~, ~) obj.saveToTxt(), bkgColor, fontColor);
        obj.makeButton(buttonGrid, [4, 2], 'Load from txt', ...
            @(~, ~) obj.loadFromTxt(), bkgColor, fontColor);

        % Column 3 buttons
        obj.makeButton(buttonGrid, [3, 3], 'Save configs', ...
            @(~, ~) obj.saveConfigs(), bkgColor, fontColor);
        obj.makeButton(buttonGrid, [4, 3], 'Delete all configs', ...
            @(~, ~) obj.deleteAllConfigs(), bkgColor, fontColor);
        obj.makeButton(buttonGrid, [1, 3], 'Render Videos', ...
            @(~, ~) obj.renderVideos(), renderColor, fontColor);

        % Set consistent font
        availableFonts = string(listfonts);
        preferredFonts = ["Open Sans", "Helvetica Neue", "Arial"];
        uiFont = preferredFonts(find( ...
            ismember(preferredFonts, availableFonts), 1));

        if isempty(uiFont)
            uiFont = "Arial";
        end

        fontname(app.HoloDopplerUIFigure, uiFont);
        fontsize(app.HoloDopplerUIFigure, 11, "points");
    end

    function btn = makeButton(~, parent, pos, label, cb, bgColor, fontColor)
        btn = uibutton(parent, 'push', ...
            'BackgroundColor', bgColor, ...
            'FontColor', fontColor, ...
            'Text', label, ...
            'ButtonPushedFcn', cb);
        btn.Layout.Row = pos(1);
        btn.Layout.Column = pos(2);
    end

    function updateDisplay(obj)
        % Refresh the text area and adjust window height, respecting limits.

        if isempty(obj.drawerList)
            displayValue = {''};
        else
            displayValue = obj.drawerList;
        end

        obj.TextArea.Value = displayValue;

        newHeight = 188 + length(obj.drawerList) * 18;
        newHeight = max(newHeight, 206);
        newHeight = min(newHeight, obj.MaxHeight);

        % Ensure width also stays within limit
        currentWidth = obj.Figure.Position(3);
        if currentWidth > obj.MaxWidth
            currentWidth = obj.MaxWidth;
        end

        obj.Figure.Position = [obj.Figure.Position(1), obj.Figure.Position(2), ...
                               currentWidth, newHeight];
    end

    function clampFigureSize(obj)
        % Enforce maximum width/height when the user resizes the figure.
        % Guard against invalid figure (e.g., during creation/deletion)
        if ~isvalid(obj.Figure)
            return;
        end
        pos = obj.Figure.Position;
        changed = false;
        if pos(3) > obj.MaxWidth
            pos(3) = obj.MaxWidth;
            changed = true;
        end
        if pos(4) > obj.MaxHeight
            pos(4) = obj.MaxHeight;
            changed = true;
        end
        if changed
            obj.Figure.Position = pos;
        end
    end

    function closeFigure(obj)
        % Clean up and delete the figure.
        delete(obj.Figure);
        delete(obj); % object will be destroyed
    end

    % -----------------------------------------------------------------
    % Callback methods
    % -----------------------------------------------------------------

    function selectFile(obj)
        % Select a single .cine or .holo file.
        filters = { ...
                       '*.cine;*.holo', 'Supported Video Files (*.cine, *.holo)'; ...
                       '*.cine', 'Cine Files (*.cine)'; ...
                       '*.holo', 'Holo Files (*.holo)'; ...
                   };

        % Bring the FolderManagement figure to focus
        figure(obj.Figure);

        if ~isempty(obj.drawerList)
            startFolder = fileparts(obj.drawerList{end});
            [file, path] = uigetfile(filters, 'Select File', startFolder);
        else
            [file, path] = uigetfile(filters, 'Select File');
        end

        figure(obj.Figure);

        if isequal(file, 0), return; end

        [~, ~, ext] = fileparts(file);

        if ismember(ext, {'.cine', '.holo', '.h5'})
            obj.addUniqueFile(fullfile(path, file));
        else
            uialert(obj.Figure, 'File must be .cine, .holo, .raw or .h5', 'Invalid File Type');
        end

        obj.MainApp.HD.drawer_list = obj.drawerList;
        obj.updateDisplay();
    end

    function selectCurrent(obj)
        % Add the currently loaded file in the main application.
        app = obj.MainApp;

        if isempty(app.HD.file)
            uialert(obj.Figure, 'No current file loaded', 'No File');
            return;
        end

        filePath = app.HD.file.path;
        [~, ~, ext] = fileparts(filePath);

        if ismember(ext, {'.cine', '.holo'})
            obj.addUniqueFile(filePath);
        else
            uialert(obj.Figure, 'File must be .cine or .holo', 'Invalid File Type');
        end

        app.HD.drawer_list = obj.drawerList;
        obj.updateDisplay();
    end

    function selectCurrentFolder(obj)
        % Add all supported files from the folder of the currently loaded file.
        app = obj.MainApp;

        if isempty(app.HD.file)
            uialert(obj.Figure, 'No current file loaded', 'No File');
            return;
        end

        obj.addFilesFromFolder(app.HD.file.dir);
        app.HD.drawer_list = obj.drawerList;
        obj.updateDisplay();
    end

    function selectFolder(obj)
        % Let the user pick a folder and add all supported files.
        figureHandle = obj.Figure;
        figure(figureHandle);

        if ~isempty(obj.drawerList)
            lastFolder = fileparts(obj.drawerList{end});
        else
            lastFolder = '';
        end

        folder = uigetdir(lastFolder);

        figure(figureHandle);

        if folder == 0, return; end
        obj.addFilesFromFolder(folder);

        obj.MainApp.HD.drawer_list = obj.drawerList;
        obj.updateDisplay();
    end

    function addFilesFromFolder(obj, folder)
        % Append all .cine / .holo files from a folder, avoiding duplicates.
        entries = dir(folder);

        for i = 1:numel(entries)

            if ~entries(i).isdir
                [~, ~, ext] = fileparts(entries(i).name);

                if ismember(ext, {'.cine', '.holo'})
                    obj.addUniqueFile(fullfile(folder, entries(i).name));
                end

            end

        end

    end

    function addUniqueFile(obj, fullFilePath)
        % Add the file only if it is not already in the list.
        if ~any(strcmp(obj.drawerList, fullFilePath))
            obj.drawerList{end + 1} = fullFilePath;
        end

    end

    function clearList(obj)
        obj.drawerList = {};
        obj.updateDisplay();
    end

    function saveToTxt(obj)
        figureHandle = obj.Figure;
        figure(figureHandle);

        [file, path] = uiputfile('*.txt', 'Save list as text file');

        figure(figureHandle);

        if isequal(file, 0), return; end
        writelines(obj.drawerList, fullfile(path, file));
    end

    function loadFromTxt(obj)
        app = obj.MainApp;

        figureHandle = obj.Figure;
        figure(figureHandle);

        [file, path] = uigetfile('*.txt', 'Select File');

        figure(figureHandle);

        if isequal(file, 0), return; end
        lines = readlines(fullfile(path, file));

        for i = 1:numel(lines)

            if ~isempty(lines(i))

                try
                    [~, ~, ext] = fileparts(lines(i));

                    if ismember(ext, {'.cine', '.holo'})
                        obj.addUniqueFile(lines{i}); % avoid duplicates
                    end

                catch e
                    disp(e);
                end

            end

        end

        app.HD.drawer_list = obj.drawerList;
        obj.updateDisplay();
    end

    function saveConfigs(obj)
        % Save a selected parameter configuration to ALL files in the drawer list.
        % If 'Keep Z distance' is checked, the original propagation distance
        % from each file's metadata is preserved (overriding the config's value).

        app = obj.MainApp;
        keepZ = obj.KeepZCheckbox.Value;

        % --- Backup current UI parameters ---
        originalParams = app.HD.params;

        % --- Select config file ---
        figureHandle = obj.Figure;
        figure(figureHandle);
        [filename, pathname] = uigetfile('*.json', 'Select config file to apply');
        figure(figureHandle);

        if isequal(filename, 0)
            return;
        end

        chosenConfigPath = fullfile(pathname, filename);

        % --- Load the chosen config ---
        try
            chosenParams = jsondecode(fileread(chosenConfigPath));
        catch ME
            uialert(obj.Figure, ...
                sprintf('Failed to read the config file:\n%s', ME.message), ...
            'Invalid Config File');
            return;
        end

        % --- Apply to each file ---
        for i = 1:length(obj.drawerList)
            filePath = obj.drawerList{i};

            % Start from a copy of the chosen parameters
            paramsToSave = chosenParams;

            % If keepZ is checked, override spatialPropagation with the file's own distance
            if keepZ
                originalZ = getOriginalPropagationDistance(filePath);

                if ~isnan(originalZ)
                    paramsToSave.spatialPropagation = originalZ;
                end

            end

            % Temporarily set the app's params for saveParams to work with
            app.HD.params = paramsToSave;
            app.HD.saveParams(filePath, keepZ);
            fprintf('Config saved for: %s\n', filePath);
        end

        % --- Restore original UI state ---
        app.HD.params = originalParams;
    end

    function renderVideos(obj)
        app = obj.MainApp;

        % ----- Gestion de la pool (inchangée) -----
        numWorkers = 0;
        cluster = parcluster;
        maxWorkers = cluster.NumWorkers;

        if ~isempty(app.HD.params) && isfield(app.HD.params, 'parforArg')
            numWorkers = app.HD.params.parforArg;
        end

        if numWorkers <= 0
            numWorkers = max(1, maxWorkers - 2);
        else

            if numWorkers > maxWorkers
                warning('Ajustement workers...');
                numWorkers = maxWorkers;
            end

        end

        if isempty(app.HD.poolManager)
            app.HD.poolManager = ParallelPoolManager(numWorkers);
        end

        app.HD.poolManager.acquire();
        cleanupPool = onCleanup(@() app.HD.poolManager.release());

        fprintf("Traitement de %d fichiers...\n", length(obj.drawerList));

        for i = 1:length(obj.drawerList)
            filePath = obj.drawerList{i};

            try
                % 1) Charger le fichier (paramètres déterminés par getFileParameters via LoadFile)
                app.HD.LoadFile(filePath);

                % 2) Lancer le rendu
                app.HD.VideoRendering();
                fprintf("Terminé : %s\n", filePath);
            catch ME
                warning('Échec pour %s : %s', filePath, ME.message);
            end

        end

    end

    function deleteAllConfigs(obj)
        n = 0;

        for i = 1:length(obj.drawerList)
            filePath = obj.drawerList{i};
            [dirName, name] = fileparts(filePath);
            baseOutputDir = fullfile(dirName, name);

            % First config file (the main one)
            configFile1 = fullfile(baseOutputDir, sprintf('%s_input_HD_params.json', name));

            if isfile(configFile1)
                delete(configFile1);
                n = n + 1;
            end

            % Second config file (inside the <name>_HD subfolder)
            configFile2 = fullfile(baseOutputDir, sprintf('%s_HD', name), ...
                sprintf('%s_HD_input_HD_params.json', name));

            if isfile(configFile2)
                delete(configFile2);
                n = n + 1;
            end

        end

        fprintf('Deleted %d config files for %d entries\n', n, length(obj.drawerList));
    end

end

end

% -------------------------------------------------------------------------
% Helper: read the propagation distance directly from the raw file metadata
% -------------------------------------------------------------------------
function z = getOriginalPropagationDistance(filePath)
[~, ~, ext] = fileparts(filePath);
z = NaN;

switch lower(ext)
    case '.holo'

        try
            reader = HoloReader(filePath);
            % Same threshold as in getFileParameters
            if reader.version >= 5
                z = reader.footer.compute_settings.image_rendering.propagation_distance;
            end

            clear reader;
        catch
            % Leave as NaN if anything fails
        end

    case '.cine'
        % .cine files usually have no built-in propagation distance;
        % we leave it as NaN so the config's value is kept.
    otherwise
        % Unsupported extension – do nothing
end

end