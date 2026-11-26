classdef ExploreSHbroadeningFromH5 < handle

properties
    fig % Main figure handle
    SH % Original 3D matrix (can be complex)
    SH_processed % Processed version of SH (based on display option)
    avgImage % Average image (first 2 dimensions)
    axImage % Axis for the image display
    axPlot % Axis for the spectrum plot
    rois % list of Region of Interest handle
    masks % list of masks from ROIs
    fitROIs % list of fit results for each ROI
    colors
    panel
    btnGroup % Button group for display options
    fs % Sampling frequency for spectrum calculation
    f1 % Frequency bounds for moment calculation
    f2 % Frequency bounds for moment calculation
    outerReference % Reference spectrum from outer diaphragm
end

methods

    function obj = ExploreSHbroadeningFromH5(options)

        arguments
            options.path = [];
            options.fs = 78
            options.f1 = 6
            options.f2 = 39
        end

        % Select a H5 file
        try

            if isempty(options.path)
                [h5_file, h5_path] = uigetfile('*.h5', 'Select a h5 file.');
                SH = h5read(fullfile(h5_path, h5_file), "/SH_Slices");
            else
                SH = h5read(options.path, "/SH_Slices");
            end

        catch ME

            MEdisp(ME);
            fprintf(2, 'Failed to load H5 file. Please check the file path and try again.');

        end

        % Constructor - initialize the application
        obj.SH = SH;
        obj.SH_processed = []; % Start with none
        obj.fs = options.fs;
        obj.f1 = options.f1;
        obj.f2 = options.f2;
        % Calculate initial average image
        obj.updateAverageImage();

        % Create the figure
        obj.createUI();

    end

    function createUI(obj)
        % Create the main figure with fixed size
        obj.fig = figure('Name', 'Explore SH Broadening', 'NumberTitle', 'off', ...
            'Position', [100, 100, 1000, 600], ...
            'CloseRequestFcn', @(src, evt)obj.closeFigure(), ...
            'Color', [1, 1, 1]);

        % Define layout parameters
        imageWidth = 0.45; % Width of image display area
        plotWidth = 0.4; % Width of spectrum plot area
        panelHeight = 0.35; % Height of control panel
        margin = 0.05; % Margin around components
        gap = 0.05; % Gap between components

        % Create image axis (left side)
        obj.axImage = axes('Parent', obj.fig, ...
            'Position', [margin, margin + panelHeight + gap, imageWidth, 1 - (panelHeight + 2 * margin + gap)], ...
            'Units', 'normalized');

        % Create plot axis (right side)
        obj.axPlot = axes('Parent', obj.fig, ...
            'Position', [margin + imageWidth + gap, margin + gap, plotWidth, 0.8], ...
            'Units', 'normalized');
        title(obj.axPlot, 'Signal Spectrum');
        xlabel(obj.axPlot, 'Dimension 3 Index');
        ylabel(obj.axPlot, 'Magnitude');

        % Create display options panel (bottom left)
        obj.panel = uipanel('Parent', obj.fig, ...
            'Title', 'Display Options', ...
            'Position', [margin, margin, imageWidth, panelHeight], ...
            'BackgroundColor', [1, 1, 1], ...
            'BorderType', 'etchedin');

        % Create button group for display options
        obj.btnGroup = uibuttongroup('Parent', obj.panel, ...
            'Position', [0.02, 0.45, 0.43, 0.5], ...
            'BackgroundColor', [1, 1, 1], ...
            'SelectionChangedFcn', @(src, evt)obj.changeDisplayOption());

        % Add radio buttons and checkboxes dynamically
        options = {
                   'abs', 'Magnitude';
                   'abs2', 'Magnitude Squared';
                   'real', 'Real Part';
                   'imag', 'Imaginary Part';
                   'angle', 'Argument (rad)'
                   };

        % Create radio buttons for display options
        for i = 1:size(options, 1)
            uicontrol('Parent', obj.btnGroup, ...
                'Style', 'radiobutton', ...
                'String', options{i, 2}, ...
                'Tag', options{i, 1}, ...
                'Units', 'normalized', ...
                'Position', [0.05, 0.8 - 0.15 * (i - 1), 1, 0.15], ...
                'BackgroundColor', [1, 1, 1]);
        end

        % Add pushbutton to make a grid of ROIs
        uicontrol('Parent', obj.panel, ...
            'Style', 'pushbutton', ...
            'String', 'Make ROI Grid', ...
            'Units', 'normalized', ...
            'Position', [0.5, 0, 0.45, 0.2], ...
            'Callback', @(src, evt)obj.makeROIGrid());

        % Add pushbutton for clearing all ROIs
        uicontrol('Parent', obj.panel, ...
            'Style', 'pushbutton', ...
            'String', 'Clear ROIs', ...
            'Units', 'normalized', ...
            'Position', [0.5, 0.2, 0.45, 0.2], ...
            'Callback', @(src, evt)obj.clearROIs());

        % Add pushbutton for saving spectra
        uicontrol('Parent', obj.panel, ...
            'Style', 'pushbutton', ...
            'String', 'Save Spectra', ...
            'Units', 'normalized', ...
            'Position', [0.5, 0.4, 0.45, 0.2], ...
            'Callback', @(src, evt)obj.saveSpectra());

        % Add pushbutton for loading PNG mask
        uicontrol('Parent', obj.panel, ...
            'Style', 'pushbutton', ...
            'String', 'Load PNG Mask', ...
            'Units', 'normalized', ...
            'Position', [0.5, 0.6, 0.45, 0.2], ...
            'Callback', @(src, evt)obj.loadPNGMask());

        % Add pushbutton for creating a new ROI
        uicontrol('Parent', obj.panel, ...
            'Style', 'pushbutton', ...
            'String', 'Select ROI', ...
            'Units', 'normalized', ...
            'Position', [0.5, 0.8, 0.45, 0.2], ...
            'Callback', @(src, evt)obj.roiNew());

        % Set default selection
        set(obj.btnGroup, 'SelectedObject', findobj(obj.btnGroup, 'Tag', 'abs'));
        obj.changeDisplayOption();
        %obj.updateImageDisplay();

        % Initial plot
        obj.spectrum_plotting();
    end

    function changeDisplayOption(obj)
        % Handle display option change
        selectedOption = get(obj.btnGroup, 'SelectedObject').Tag;

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

        obj.SH_processed = squeeze(mean(obj.SH_processed, 4));

        % Update display
        obj.updateAverageImage();
        obj.updateImageDisplay();
        obj.spectrum_plotting();
    end

    function updateAverageImage(obj)
        % Calculate average image based on current processing
        obj.avgImage = moment0(obj.SH_processed, obj.f1, obj.f2, obj.fs, size(obj.SH_processed, 3), 0);
    end

    function updateImageDisplay(obj)

        % Update the image display with real values
        axes(obj.axImage);
        [Nx, Ny] = size(obj.avgImage);
        Nd = max(Nx, Ny);
        imagesc(imresize(obj.avgImage, [Nd Nd]));
        axis image;
        colormap(obj.axImage, 'gray');
        title('Moment order 0 f1 f2 Image');
        colorbar;
    end

    function clearROIs(obj)
        % Clear all ROIs and reset the mask
        if ~isempty(obj.rois)

            for i = 1:length(obj.rois)

                if obj.rois{i} == 1
                    continue;
                end

                if isempty(obj.rois{i}) || ~isvalid(obj.rois{i})
                    continue;
                end

                delete(obj.rois{i});

            end

        end

        obj.rois = [];
        obj.fitROIs = [];
        obj.masks = [];
        obj.colors = [];
        obj.updateImageDisplay();
        obj.spectrum_plotting(); % Update the spectrum plot
    end

    function saveSpectra(obj)
        % Saves Spectra into the preview folder

        folderPath = uigetdir(pwd, 'Select a folder to save the figure');

        % Check if user selected a folder (didn't click Cancel)
        if folderPath ~= 0
            % Ask user for filename
            defaultName = 'spectra';
            prompt = {'Enter filename (without extension):'};
            dlgtitle = 'Save Figure';
            dims = [1 35];
            answer = inputdlg(prompt, dlgtitle, dims, {defaultName});

            % Check if user entered a filename
            if ~isempty(answer)
                fileName = answer{1};

                % Construct full file path
                fullFilePath = fullfile(folderPath, [fileName, '.png']);

                % Save the figure using exportgraphics
                exportgraphics(obj.axPlot, fullFilePath, 'Resolution', 300);

                % Display confirmation message
                fprintf('Figure saved successfully to:\n%s\n', fullFilePath);

            else
                disp('Save cancelled: No filename provided');
            end

        else
            disp('Save cancelled: No folder selected');
        end

    end

    function makeROIGrid(obj)

        % Clear existing ROIs and masks
        obj.clearROIs();

        % Create a grid of ROIs across the image
        numRows = 512; % Number of rows in the grid
        numCols = 512; % Number of columns in the grid

        % Get current axis limits
        xLimits = get(obj.axImage, 'XLim');
        yLimits = get(obj.axImage, 'YLim');

        % Calculate width and height of each ROI based on axis limits
        roiWidth = (xLimits(2) - xLimits(1)) / numCols;
        roiHeight = (yLimits(2) - yLimits(1)) / numRows;

        % Loop through rows and columns to create ROIs
        for row = 0:(numRows - 1)

            for col = 0:(numCols - 1)
                % Calculate position for the current ROI
                xPos = xLimits(1) + col * roiWidth;
                yPos = yLimits(1) + row * roiHeight;

                % Create a new ROI
                obj.rois{end + 1} = 1;

                % Create a binary mask for the current ROI
                [X, Y] = meshgrid(1:xLimits(2), 1:yLimits(2));
                obj.masks{end + 1} = (X >= xPos) & (X <= xPos + roiWidth) & ...
                    (Y >= yPos) & (Y <= yPos + roiHeight);
                obj.colors{end + 1} = rand(1, 3);
            end

        end

        % Update the spectrum plot after creating the grid of ROIs
        obj.fit_spectra();

        % fitParams as images
        obj.gridFigure(numRows, numCols);

    end

    function roiNew(obj, manual)

        if nargin < 2
            manual = false;
        end

        n = length(obj.rois);
        C = colororder('gem');
        randomColor = C(mod(n, 7) + 1, :); % Generate a random RGB color

        if manual
            obj.rois{end + 1} = drawfreehand(obj.axImage, 'Color', randomColor, ...
                'DrawingArea', 'unlimited', ...
                'FaceAlpha', 0.2, ...
                'InteractionsAllowed', 'translate');
        else
            obj.rois{end + 1} = drawrectangle(obj.axImage, 'Color', randomColor, ...
                'DrawingArea', 'unlimited', ...
                'FaceAlpha', 0.2, ...
                'InteractionsAllowed', 'translate');
        end

        obj.colors{end + 1} = randomColor;
        % Add listener to ROI for position changes
        addlistener(obj.rois{end}, 'MovingROI', @(src, evt)obj.spectrum_plotting());
        % Callback for when ROI is moved
        obj.spectrum_plotting();
    end

    function updateMasks(obj)
        % Update the mask based on current ROI position
        for i = 1:numel(obj.rois)
            roi = obj.rois{i};

            if roi == 1
                continue;
            end

            if isempty(roi) || ~isvalid(roi)
                continue;
            end

            roiPos = roi.Position; % [x, y, width, height]

            % Create a binary mask
            [Ny, Nx, ~] = size(obj.SH_processed);
            M = max(Nx, Ny);
            rx = Nx / M;
            ry = Ny / M;
            [X, Y] = meshgrid(1:Nx, 1:Ny);

            obj.masks{i} = (X >= roiPos(1) * rx) & (X <= roiPos(1) * rx + roiPos(3) * rx) & ...
                (Y >= roiPos(2) * ry) & (Y <= roiPos(2) * ry + roiPos(4) * ry);
        end

    end

    function loadPNGMask(obj)
        % Load a PNG file and use it as a mask
        [filename, pathname] = uigetfile({'*.png;*.bmp;*.jpg;*.tif', 'Image Files'; ...
                                              '*.*', 'All Files'}, ...
        'Select a mask image');

        if isequal(filename, 0) || isequal(pathname, 0)
            % User cancelled
            return;
        end

        fullpath = fullfile(pathname, filename);

        try
            % Read the image
            maskImage = imread(fullpath);

            % Convert to grayscale if RGB
            if size(maskImage, 3) > 1
                maskImage = rgb2gray(maskImage);
            end

            % Convert to binary mask (non-zero values become 1)
            maskBinary = imbinarize(maskImage);

            % Get the current image size
            [Ny, Nx, ~] = size(obj.SH_processed);
            M = max(Nx, Ny);

            % Resize the mask to match the current image display dimensions
            maskResized = imresize(maskBinary, [Ny, Nx]);

            obj.rois{end + 1} = 1;
            obj.masks{end + 1} = maskResized; % Store the image handle

            n = length(obj.rois) - 1;
            C = colororder('gem');
            randomColor = C(mod(n, 7) + 1, :); % Generate a random RGB color
            obj.colors{end + 1} = randomColor;

            % Create a visual representation of the mask
            % Since we can't create a drawrectangle/drawfreehand from existing mask,
            % we'll create a semitransparent overlay
            hold(obj.axImage, 'on');

            % Create an overlay image
            overlay = zeros(Ny, Nx, 3);

            for c = 1:3
                overlay(:, :, c) = maskResized * randomColor(c);
            end

            % Display the overlay
            h = imagesc(imresize(overlay, [M, M]), 'Parent', obj.axImage);
            set(h, 'AlphaData', imresize(maskResized, [M, M]) * 0.3); % 30 % transparency

            % Just update the spectrum plot
            obj.spectrum_plotting();

            fprintf('Loaded mask from: %s\n', filename);

        catch ME
            MEdisp(ME);
        end

    end

    function fitResults = spectrum_plotting(obj, rescale)

        if nargin < 2
            rescale = true;
        end

        % Extract parameters for easier access
        f_1 = obj.f1;
        f_2 = obj.f2;
        f_s = obj.fs;
        batchSize = size(obj.SH_processed, 3);

        axes(obj.axPlot);
        cla(obj.axPlot); % Clear the previous plot
        title(obj.axPlot, 'Signal Spectrum');
        xlabel(obj.axPlot, 'Dimension 3 Index');
        ylabel(obj.axPlot, 'Magnitude');

        if isempty(obj.rois)
            return
        end

        angleout = strcmp(get(obj.btnGroup.SelectedObject, 'Tag'), 'angle');

        if angleout
            scalingfn = @(a) a;
        else
            scalingfn = @(a) log10(a);
        end

        % Plot the spectrum for the selected region
        obj.updateMasks();

        if angleout
            ylabel('S', 'FontSize', 14);
        else
            ylabel('log10 S', 'FontSize', 14);
        end

        fitResults = cell(numel(obj.rois), 1);

        parfor i = 1:numel(obj.rois)

            mask = obj.masks{i};

            if isempty(mask)
                continue;
            end

            % Compute the average spectrum for the masked region
            SH_mask = obj.SH_processed .* mask;
            spectrumAVG_mask = squeeze(sum(SH_mask, [1 2])) / nnz(mask);
            momentM0 = moment0(obj.SH_processed, f_1, f_2, f_s, batchSize);
            momentM2 = moment2(obj.SH_processed, f_1, f_2, f_s, batchSize);
            M0_full = mean(momentM0, [1, 2]);
            M2 = mean(momentM2(mask));
            omegaRMS = sqrt(M2 / M0_full); % sqrt(M2/M0);
            omegaRMS_index = omegaRMS * batchSize / f_s;
            I_omega = scalingfn(spectrumAVG_mask(round(omegaRMS_index)));
            axis_x = linspace(-f_s / 2, f_s / 2, size(SH_mask, 3));

            % Get the color of the current ROI
            roiColor = obj.colors{i};

            p_mask = plot(axis_x, fftshift(scalingfn(spectrumAVG_mask)), 'Color', roiColor, 'LineWidth', 1, 'DisplayName', 'Arteries');
            xlim([-f_s / 2 f_s / 2])
            sclingrange = abs(fftshift(axis_x)) > f_1;

            if rescale
                yrange = [.99 * scalingfn(min(spectrumAVG_mask(sclingrange))) 1.01 * scalingfn(max(spectrumAVG_mask(sclingrange)))];
                ylim(yrange)
            else
                yrange = get(gca, 'YLim');
                ylim(yrange)
            end

            om_RMS_line = line([-omegaRMS omegaRMS], [I_omega I_omega]);
            om_RMS_line.Color = roiColor;
            om_RMS_line.LineStyle = '-';
            om_RMS_line.Marker = '|';
            om_RMS_line.MarkerSize = 12;
            om_RMS_line.LineWidth = 1;
            om_RMS_line.Tag = sprintf('f_{RMS %d} = %.2f kHz', i, omegaRMS);
            %fprintf('f_{RMS %d} = %.2f kHz\n', i, omegaRMS);
            text(10, I_omega, sprintf('f_{RMS %d} = %.2f kHz', i, omegaRMS), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom')
            set(gca, 'LineWidth', 1);
            uistack(p_mask, 'top');
            uistack(gca, 'top');

            hold on

            fitResults{i} = fit_spectrum_voigt(axis_x, log10(fftshift(spectrumAVG_mask)), f_1, f_2, annotation = false);

        end

        obj.fitROIs = fitResults;

        pbaspect([1.618 1 1]);
        box on,
        set(gca, 'FontSize', 12, 'LineWidth', 2);

        % Fill in gray the are between f1 and -f1, and between f2 or -f2 and outer boundaries
        % Store fill handles for later reordering
        fillHandles = gobjects(3, 1);

        fig_axis = axis;
        c_gray = [0.9 0.9 0.9];
        X = [fig_axis(1) -f_2 -f_2 fig_axis(1)];
        Y = [fig_axis(4) fig_axis(4) fig_axis(3) fig_axis(3)];
        fillHandles(1) = fill(X, Y, c_gray, 'EdgeColor', 'black', 'LineWidth', 1, 'DisplayName', 'Arteries');

        X = [-f_1 f_1 f_1 -f_1];
        Y = [fig_axis(4) fig_axis(4) fig_axis(3) fig_axis(3)];
        fillHandles(2) = fill(X, Y, c_gray, 'EdgeColor', 'black', 'LineWidth', 1, 'DisplayName', 'Arteries');

        X = [f_2 fig_axis(2) fig_axis(2) f_2];
        Y = [fig_axis(4) fig_axis(4) fig_axis(3) fig_axis(3)];
        fillHandles(3) = fill(X, Y, c_gray, 'EdgeColor', 'black', 'LineWidth', 1, 'DisplayName', 'Arteries');

        % Move all fills to the background
        for j = 1:length(fillHandles)
            uistack(fillHandles(j), 'bottom');
        end

        xticks([-f_2 -f_1 0 f_1 f_2])
        xticklabels({num2str(round(-f_2, 1)), num2str(round(-f_1, 1)), '0', num2str(round(f_1, 1)), num2str(round(f_2, 1))})
        fontsize(gca, 12, "points");
        xlabel('frequency (kHz)', 'FontSize', 14);

        yline(0, 'LineWidth', 2)

    end

    function fitResults = fit_spectra(obj)

        % Extract parameters for easier access
        f_1 = obj.f1;
        f_2 = obj.f2;
        f_s = obj.fs;

        if isempty(obj.rois)
            return
        end

        % Plot the spectrum for the selected region
        obj.updateMasks();

        fitResults = cell(numel(obj.rois), 1);

        tic

        parfor i = 1:numel(obj.rois)

            mask = obj.masks{i};

            if isempty(mask)
                continue;
            end

            % Compute the average spectrum for the masked region
            SH_mask = obj.SH_processed .* mask;
            spectrumAVG_mask = squeeze(sum(SH_mask, [1 2])) / nnz(mask);
            axis_x = linspace(-f_s / 2, f_s / 2, size(SH_mask, 3));
            fitResults{i} = fit_spectrum(axis_x, log10(fftshift(spectrumAVG_mask)), f_1, f_2, annotation = false, verbose = false);

        end

        toc

        obj.fitROIs = fitResults;

    end

    function gridFigure(obj, numRows, numCols)

        % Create a grid of ROIs and plot the fit parameters as images
        a = zeros(numRows, numCols);
        b = zeros(numRows, numCols);
        g = zeros(numRows, numCols);
        x0 = zeros(numRows, numCols);

        for row = 0:(numRows - 1)

            for col = 0:(numCols - 1)

                if isempty(obj.fitROIs{row * numCols + col + 1})
                    continue;
                end

                a(row + 1, col + 1) = obj.fitROIs{row * numCols + col + 1}.a;
                b(row + 1, col + 1) = obj.fitROIs{row * numCols + col + 1}.b;
                g(row + 1, col + 1) = obj.fitROIs{row * numCols + col + 1}.g;
                x0(row + 1, col + 1) = obj.fitROIs{row * numCols + col + 1}.x0;

            end

        end

        figure,
        imagesc(a);
        colorbar;
        title('a');

        figure,
        imagesc(b);
        colorbar;
        title('b');

        figure,
        imagesc(g);
        colorbar;
        title('g');

        figure,
        imagesc(x0);
        colorbar;
        title('x0');
    end

    function makeOuterDiaphragmReference(obj)
        % This function can be implemented to create a reference spectrum from an outer diaphragm region
        % It can be called when the user clicks a button to set the reference spectrum for fitting

        [Nx, Ny, batchSize] = size(obj.SH_processed);
        outerMask = ~diskMask(Ny, Nx, 1.2);
        largeMask = repmat(outerMask, [1 1 batchSize]);
        SH_mask = obj.SH_processed .* largeMask;
        obj.outerReference = squeeze(sum(SH_mask, [1 2])) / nnz(outerMask);

    end

    function closeFigure(obj)
        % Clean up when figure is closed
        delete(obj.fig);
    end

end

end
