classdef ExploreAp < handle

properties
    fig % Main figure handle
    I % Original 3D matrix
    avgImage % Average image (first 2 dimensions)
    axImage % Axis for the image display
    axPlot % Axis for the spectrum plot
    roi % Region of Interest handle
    mask % Current mask from ROI
    panel
    btnGroup % Button group for display options
    Params % from parent contains rendering params used for propag
end

methods

    function obj = ExploreAp(I, Params)
        % Constructor - initialize the application
        obj.I = I;

        obj.Params = Params;

        % Calculate initial average image
        obj.updateAverageImage();

        % Create the figure
        obj.createUI();

    end

    function createUI(obj)
        % Create the main figure with fixed size
        obj.fig = figure('Name', 'Explore Ap', 'NumberTitle', 'off', ...
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
        obj.updateImageDisplay();

        % Create plot axis (right side)
        obj.axPlot = axes('Parent', obj.fig, ...
            'Position', [margin + imageWidth + gap, margin + gap, plotWidth, 0.8], ...
            'Units', 'normalized');
        title(obj.axPlot, 'Signal Spectrum');
        xlabel(obj.axPlot, 'Dimension 3 Index');
        ylabel(obj.axPlot, 'Magnitude');
        grid(obj.axPlot, 'on');

        % Create display options panel (bottom left)
        obj.panel = uipanel('Parent', obj.fig, ...
            'Title', 'Display Options', ...
            'Position', [margin, margin, imageWidth, panelHeight], ...
            'BackgroundColor', [1, 1, 1], ...
            'BorderType', 'etchedin');

        % Create button group for display options
        obj.btnGroup = uibuttongroup('Parent', obj.panel, ...
            'Position', [0.02, 0.45, 0.43, 0.5], ...
            'BackgroundColor', [1, 1, 1]);

        % Add radio buttons and checkboxes dynamically
        options = {
                   'abs', 'Magnitude';
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

        % Add checkboxes for magnitude and phase toggles
        uicontrol('Parent', obj.panel, ...
            'Style', 'checkbox', ...
            'String', 'Show Magnitude', ...
            'Tag', 'mag', ...
            'Units', 'normalized', ...
            'Position', [0.05, 0.2, 0.9, 0.15], ...
            'Callback', @(src, evt)obj.plotting(), ...
            'BackgroundColor', [1, 1, 1], 'Value', 1);

        uicontrol('Parent', obj.panel, ...
            'Style', 'checkbox', ...
            'String', 'Show Phase', ...
            'Tag', 'phase', ...
            'Units', 'normalized', ...
            'Position', [0.05, 0.05, 0.9, 0.15], ...
            'Callback', @(src, evt)obj.plotting(), ...
            'BackgroundColor', [1, 1, 1]);

        % Add pushbutton for creating a new ROI
        uicontrol('Parent', obj.panel, ...
            'Style', 'pushbutton', ...
            'String', 'Select ROI', ...
            'Units', 'normalized', ...
            'Position', [0.5, 0.2, 0.45, 0.2], ...
            'Callback', @(src, evt)obj.roiNew());

        % Set default selection
        set(obj.btnGroup, 'SelectedObject', findobj(obj.btnGroup, 'Tag', 'abs'));

        % Initial plot
        obj.plotting();
    end

    function updateAverageImage(obj)
        % Calculate average image based on current processing
        obj.avgImage = mean(abs(obj.I), 3);
    end

    function updateImageDisplay(obj)
        % Update the image display with real values
        axes(obj.axImage);
        imagesc(obj.avgImage);
        colormap(obj.axImage, 'gray');
        title('Average Image');
        colorbar;
    end

    function roiNew(obj, manual)

        if nargin < 2
            manual = false;
        end

        % Delete the previous ROI if it exists
        if ~isempty(obj.roi)
            delete(obj.roi);
        end

        if manual
            obj.roi = drawfreehand(obj.axImage, 'Color', 'r', ...
                'DrawingArea', 'unlimited', ...
                'FaceAlpha', 0.2, ...
                'InteractionsAllowed', 'translate');
        else
            obj.roi = drawrectangle(obj.axImage, 'Color', 'r', ...
                'DrawingArea', 'unlimited', ...
                'FaceAlpha', 0.2, ...
                'InteractionsAllowed', 'translate');
        end

        % Add listener to ROI for position changes
        addlistener(obj.roi, 'MovingROI', @(src, evt)obj.plotting());
        % Callback for when ROI is moved
        obj.plotting();
    end

    function updateMask(obj)
        % Update the mask based on current ROI position
        if isempty(obj.roi) || ~isvalid(obj.roi)
            return;
        end

        roiPos = obj.roi.Position; % [x, y, width, height]

        % Create a binary mask
        [ny, nx, ~] = size(obj.I);
        [X, Y] = meshgrid(1:nx, 1:ny);

        obj.mask = (X >= roiPos(1)) & (X <= roiPos(1) + roiPos(3)) & ...
            (Y >= roiPos(2)) & (Y <= roiPos(2) + roiPos(4));
    end

    function plotting(obj)
        % Plot the spectrum for the selected region
        obj.updateMask();

        if isempty(obj.mask)
            return;
        end

        hei = size(obj.I, 1);
        wid = size(obj.I, 2);

        pos = obj.roi.Position;
        pos = arrayfun(@floor, pos);
        x1 = pos(1);
        y1 = pos(2);
        w1 = pos(3);
        h1 = pos(4);

        y2 = max(min((y1 + h1), hei), 1);
        x2 = max(min((x1 + w1), wid), 1);
        y1 = max(min((y1), hei), 1);
        x1 = max(min((x1), wid), 1); % matlab....

        SubapI = obj.I(y1:y2, x1:x2, :);

        switch obj.Params.spatialTransform
            case "angular spectrum"
                [NY, NX, ~] = size(SubapI);
                SpatialKernel = propagation_kernelAngularSpectrum(NX, NY, obj.Params.spatialPropagation, obj.Params.lambda, obj.Params.ppx, obj.Params.ppy, 0);
                FH = fft2(single(SubapI)) .* fftshift(SpatialKernel);
            case "Fresnel"
                [NY, NX, ~] = size(SubapI);
                [SpatialKernel] = propagation_kernelFresnel(NX, NY, obj.Params.spatialPropagation, obj.Params.lambda, obj.Params.ppx, obj.Params.ppy, 0);
                FH = single(SubapI) .* SpatialKernel;
            case "None"
                FH = [];
        end

        switch obj.Params.spatialTransform
            case "angular spectrum"
                H = ifft2(FH);
            case "Fresnel"
                H = fftshift(fftshift(fft2(FH), 1), 2); %.*obj.PhaseFactor;
            case "None"
                H = single(SubapI);
        end

        if obj.Params.svd_filter
            [H] = svd_filter(H, obj.Params.svdThreshold, obj.Params.frequencyRange1, obj.Params.fs, obj.Params.svdStride);
        end

        switch obj.Params.timeTransform
            case 'FFT'
                SH = fft(H, [], 3);
            case 'PCA'
                SH = abs(short_time_PCA(H));
            case 'None'
                SH = H;
        end

        if strcmp(obj.Params.timeTransform, 'PCA')
            img = cumulant(SH, obj.Params.indexRange1, obj.Params.indexRange2);
        else
            img = moment0(SH, obj.Params.frequencyRange1, obj.Params.frequencyRange2, obj.Params.fs, size(obj.I, 3), obj.Params.flatfield_gw);
        end

        % Plot
        axes(obj.axPlot);
        cla(obj.axPlot);

        imagesc(img);
        colormap(obj.axPlot, 'gray');
        colorbar;

    end

    function closeFigure(obj)
        % Clean up when figure is closed
        delete(obj.fig);
    end

end

end
