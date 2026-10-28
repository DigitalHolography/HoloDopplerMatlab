function AdvancedPanel(app)
% Creates an advanced control panel for the app with improved styling and organization.

% Create the UIFigure with improved styling
fig = uifigure('Position', [100 100 500 250], ...
    'Color', [0.2 0.2 0.2], ...
    'Name', 'Advanced Controls', ...
    'Resize', 'on', ...
    'WindowStyle', 'normal');

% Create a grid layout for better organization
mainGrid = uigridlayout(fig, [6, 3], ...
    'ColumnWidth', {'1x', '1x', '1x'}, ...
    'RowHeight', {'fit', 'fit', 'fit', 'fit', 'fit', 'fit'}, ...
    'Padding', [10 10 10 10], ...
    'BackgroundColor', [0.2 0.2 0.2], ...
    'RowSpacing', 10, ...
    'ColumnSpacing', 10);

% Style constants
bgColor = [0.2 0.2 0.2];
textColor = [0.9 0.9 0.9];
btnColor = [0.4 0.4 0.4];

% --- First frame position controls ---
label1 = uilabel(mainGrid);
label1.Text = 'First frame position:';
label1.FontColor = textColor;
label1.BackgroundColor = bgColor;
label1.Layout.Row = 1;
label1.Layout.Column = 1;

firstFrameEdit = uieditfield(mainGrid, 'numeric');
% Handle empty first_frame value
if isempty(app.HD.params.first_frame)
    firstFrameEdit.Value = 1; % fallback default
else
    firstFrameEdit.Value = app.HD.params.first_frame;
end

firstFrameEdit.BackgroundColor = bgColor;
firstFrameEdit.FontColor = textColor;
firstFrameEdit.Layout.Row = 2;
firstFrameEdit.Layout.Column = 1;

% --- Last frame position controls ---
label2 = uilabel(mainGrid);
label2.Text = 'Last frame position:';
label2.FontColor = textColor;
label2.BackgroundColor = bgColor;
label2.Layout.Row = 1;
label2.Layout.Column = 2;

lastFrameEdit = uieditfield(mainGrid, 'numeric');
% Handle empty end_frame value
if isempty(app.HD.params.end_frame)
    % Use total number of frames if available, otherwise a placeholder
    if isfield(app.HD.file, 'nFrames') && ~isempty(app.HD.file.nFrames)
        lastFrameEdit.Value = app.HD.file.nFrames;
    else
        lastFrameEdit.Value = 100; % fallback default
    end

else
    lastFrameEdit.Value = app.HD.params.end_frame;
end

lastFrameEdit.BackgroundColor = bgColor;
lastFrameEdit.FontColor = textColor;
lastFrameEdit.Layout.Row = 2;
lastFrameEdit.Layout.Column = 2;

% --- Color threshold controls ---
label3 = uilabel(mainGrid);
label3.Text = 'Color frequency threshold:';
label3.FontColor = textColor;
label3.BackgroundColor = bgColor;
label3.Layout.Row = 3;
label3.Layout.Column = 1;

colorThreshEdit = uieditfield(mainGrid, 'numeric');
% Handle empty frequencyRange_extra value
if isempty(app.HD.render.LastParams.frequencyRange_extra)
    colorThreshEdit.Value = 0; % fallback default
else
    colorThreshEdit.Value = app.HD.render.LastParams.frequencyRange_extra;
end

colorThreshEdit.BackgroundColor = bgColor;
colorThreshEdit.FontColor = textColor;
colorThreshEdit.Layout.Row = 4;
colorThreshEdit.Layout.Column = 1;

% --- Buckets number controls ---
label4 = uilabel(mainGrid);
label4.Text = 'Buckets number:';
label4.FontColor = textColor;
label4.BackgroundColor = bgColor;
label4.Layout.Row = 3;
label4.Layout.Column = 2;

bucketsEdit = uieditfield(mainGrid, 'text');
buckranges = app.HD.params.bucketsRanges;
bucketsEdit.Value = mat2str(buckranges);
bucketsEdit.BackgroundColor = bgColor;
bucketsEdit.FontColor = textColor;
bucketsEdit.Layout.Row = 4;
bucketsEdit.Layout.Column = 2;
bucketsEdit.ValueChangedFcn = @(src, event) buckEditCallBack(src);

bucketsraw = uicheckbox(mainGrid, ...
    'Text', 'save raw', ...
    'FontColor', 'white', ...
    'Value', app.HD.params.buckets_raw, ...
    'ValueChangedFcn', @(src, event) updateParam(app, src, 'buckets_raw'));
bucketsraw.Layout.Row = 3;
bucketsraw.Layout.Column = 3;

% --- Buttons (Row 5 and 6) ---
% Show SH button
showSHbtn = uibutton(mainGrid, 'push');
showSHbtn.Text = 'Show SH';
showSHbtn.BackgroundColor = btnColor;
showSHbtn.FontColor = textColor;
showSHbtn.Layout.Row = 5;
showSHbtn.Layout.Column = 1;
showSHbtn.ButtonPushedFcn = @(btn, event) showSH_Callback(app);

% Explore SH button
exploreSHbtn = uibutton(mainGrid, 'push');
exploreSHbtn.Text = 'Explore SH';
exploreSHbtn.BackgroundColor = btnColor;
exploreSHbtn.FontColor = textColor;
exploreSHbtn.Layout.Row = 5;
exploreSHbtn.Layout.Column = 2;
exploreSHbtn.ButtonPushedFcn = @(btn, event) ExploreSH(app);

% Explore SH broadening button
exploreSHbroadBtn = uibutton(mainGrid, 'push');
exploreSHbroadBtn.Text = 'Explore SH broadening';
exploreSHbroadBtn.BackgroundColor = btnColor;
exploreSHbroadBtn.FontColor = textColor;
exploreSHbroadBtn.Layout.Row = 5;
exploreSHbroadBtn.Layout.Column = 3;
exploreSHbroadBtn.ButtonPushedFcn = @(~, ~) exploreSHBroadening_Callback(app);
% Explore Ap button
exploreApBtn = uibutton(mainGrid, 'push');
exploreApBtn.Text = 'Explore Ap';
exploreApBtn.BackgroundColor = btnColor;
exploreApBtn.FontColor = textColor;
exploreApBtn.Layout.Row = 6;
exploreApBtn.Layout.Column = 1;
exploreApBtn.ButtonPushedFcn = @(btn, event) ExploreAp(app.HD.render.Frames, app.HD.params);

% Explore Z button
exploreZBtn = uibutton(mainGrid, 'push');
exploreZBtn.Text = 'Explore Z';
exploreZBtn.BackgroundColor = btnColor;
exploreZBtn.FontColor = textColor;
exploreZBtn.Layout.Row = 6;
exploreZBtn.Layout.Column = 3;
exploreZBtn.ButtonPushedFcn = @(btn, event) ExploreZ(app.HD.render, app.HD.params);

% Set up value change callbacks
firstFrameEdit.ValueChangedFcn = @(src, event) updateFrameParams(app, src, lastFrameEdit);
lastFrameEdit.ValueChangedFcn = @(src, event) updateFrameParams(app, firstFrameEdit, src);
colorThreshEdit.ValueChangedFcn = @(src, event) updateParam(app, src, 'frequencyRange_extra');

fontname(fig, 'Arial');
fontsize(fig, 12, "points");

% --- Nested helper functions ---
function buckEditCallBack(src)

    try
        app.HD.params.bucketsRanges = eval(src.Value);
        assert(size(app.HD.params.bucketsRanges, 2) == 2);
    catch E
        disp("Couldn't get the ranges try to write input frequency ranges like '[[6,18]; [6,25]]' in kHz.")
    end

end

function showSH_Callback(app)
    app.HD.show_SH();
end

function updateFrameParams(app, edit1, edit2)
    app.HD.params.first_frame = edit1.Value;
    app.HD.params.end_frame = edit2.Value;
end

function updateParam(app, src, paramName)
    app.HD.params.(paramName) = src.Value;
end

% Add validation for frame values (these properties are set after creation)
firstFrameEdit.Limits = [0 Inf];
lastFrameEdit.Limits = [0 Inf];
firstFrameEdit.RoundFractionalValues = 'on';
lastFrameEdit.RoundFractionalValues = 'on';

function exploreSHBroadening_Callback(app)

    try

        % Retrieve images and their requested names

        imageTypes = app.HD.params.imageTypes;

        images = app.HD.render.getImages(imageTypes);

        % Convert the renderer output to a scalar structure

        if iscell(images)

            % Normalize image names to a column cell array of char vectors.
            imageNames = cellstr(string(imageTypes));
            imageNames = imageNames(:);

            assert(numel(images) == numel(imageNames), ...
                ['getImages returned %d images, but imageTypes ' ...
             'contains %d names.'], ...
                numel(images), numel(imageNames));

            % Structure field names must be valid and unique.
            fieldNames = matlab.lang.makeValidName(imageNames);

            fieldNames = matlab.lang.makeUniqueStrings( ...
                fieldNames, {}, namelengthmax);

            % Column orientation + dim=1 gives one scalar structure.
            imageMaps = cell2struct( ...
                images(:), fieldNames, 1);

        elseif isstruct(images) && isscalar(images)

            % Also support a renderer that already returns a structure.
            imageMaps = images;

        else

            error('ExploreSHbroadening:ImageFormat', ...
                ['Unsupported getImages output: class "%s", size %s. ' ...
             'Expected a cell array of images or a scalar structure.'], ...
                class(images), mat2str(size(images)));

        end

        % Filter images available for background display

        excludedNames = {'broadening'};

        expectedSize = [ ...
                            size(app.HD.render.SH, 1), ...
                            size(app.HD.render.SH, 2)];

        names = fieldnames(imageMaps);

        for k = 1:numel(names)

            name = names{k};

            % Explicitly excluded image types.
            if any(strcmpi(name, excludedNames))

                imageMaps = rmfield(imageMaps, name);
                continue;

            end

            img = imageMaps.(name);

            % Only real 2D spatial maps are supported here.
            isCompatible = ...
                (isnumeric(img) || islogical(img)) ...
                && isreal(img) ...
                && ismatrix(img) ...
                && ~isempty(img) ...
                && isequal(size(img), expectedSize);

            if ~isCompatible

                warning('ExploreSHbroadening:SkippedImage', ...
                    ['Image "%s" ignored: expected a real 2D matrix ' ...
                 'of size [%d %d]; received class "%s", size %s.'], ...
                    name, expectedSize(1), expectedSize(2), ...
                    class(img), mat2str(size(img)));

                imageMaps = rmfield(imageMaps, name);

            end

        end

        % Open the explorer

        ExploreSHbroadening( ...
            app.HD.render.SH, ...
            app.HD.file.fs, ...
            app.HD.params.frequencyRange1, ...
            app.HD.params.frequencyRange2, ...
            imageMaps, ...
            app.HD.params.frequencyRangeBandRatio1, ...
            app.HD.params.frequencyRangeBandRatio2);

    catch ME

        uialert(fig, ME.message, ...
        'Explore SH broadening');

    end

end

end
