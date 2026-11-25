classdef HDParamSchema
% Rendering parameters only.
% File metadata (fs, lambda, ppx, ppy, Nx, Ny) remains in HD.file.

methods (Static)

    function defaults = getDefaults()
        defaults = struct();
        schema = HDParamSchema.getFullSchema();

        for k = 1:numel(schema)
            defaults.(schema(k).param) = schema(k).default;
        end

    end

    function schema = getFullSchema()
        % No persistent cache: edits are reflected on the next call.
        schema = HDParamSchema.buildSchema();
    end

    function [clean, messages] = validate(params)
        clean = HDParamSchema.getDefaults();
        messages = {};

        if ~isstruct(params) || ~isscalar(params)
            warning('HDParamSchema:InvalidStruct', ...
            'Expected a scalar struct; using defaults.');
            return
        end

        % Migrate old configurations before inserting defaults.
        if ~isfield(params, 'filterType')
            params.filterType = 'SVD';

            if isfield(params, 'svd_filter')
                value = params.svd_filter;

                if HDParamSchema.isBoolean(value) && ~logical(value)
                    params.filterType = 'None';
                end

            end

        end

        schema = HDParamSchema.getFullSchema();
        known = {schema.param};
        names = fieldnames(params);

        % Preserve parameters added elsewhere in the project.
        for k = 1:numel(names)
            name = names{k};

            if ~ismember(name, known)
                clean.(name) = params.(name);
            end

        end

        for k = 1:numel(schema)
            entry = schema(k);
            name = entry.param;

            if ~isfield(params, name) || isempty(params.(name))
                continue
            end

            value = params.(name);
            [ok, reason] = HDParamSchema.isValid(value, entry);

            if ~ok
                message = sprintf( ...
                    'Invalid parameter "%s" (%s); using default.', ...
                    name, reason);

                messages{end + 1} = message;
                warning('HDParamSchema:InvalidValue', '%s', message);
                continue
            end

            switch entry.type
                case 'checkbox'
                    value = logical(value);
                case 'dropdown'
                    value = char(value);
            end

            if strcmp(name, 'imageTypes')
                value = intersect( ...
                    value, properties(ImageTypeList), 'stable');
            end

            clean.(name) = value;
        end

    end

    function classtogui(HD, app)

        if isempty(HD) || isempty(HD.params)
            return
        end

        schema = HDParamSchema.getFullSchema();

        for k = 1:numel(schema)
            entry = schema(k);

            if isempty(entry.widget) || ~isprop(app, entry.widget)
                continue
            end

            value = HDParamSchema.getParam( ...
                HD.params, entry.param, entry.default);

            app.setWidgetValue(entry.widget, value);
        end

        if isempty(HD.file)
            return
        end

        names = {'Nx', 'Ny', 'fs', 'lambda', 'ppx', 'ppy'};

        for k = 1:numel(names)
            name = names{k};

            if isfield(HD.file, name) && isprop(app, name)
                app.setWidgetValue(name, double(HD.file.(name)));
            end

        end

        if isfield(HD.file, 'num_frames') && ...
                isfield(HD.params, 'batchSize') && ...
                isprop(app, 'positioninfileSlider')

            lastPosition = max( ...
                1, double(HD.file.num_frames - HD.params.batchSize + 1));

            % A slider requires distinct limits.
            app.setSliderLimits( ...
                'positioninfileSlider', [1 max(2, lastPosition)]);

            position = min(lastPosition, max(1, ...
                double(HD.params.framePosition)));

            app.setWidgetValue('positioninfileSlider', position);
        end

    end

    function guitoclass(HD, app)

        if isempty(HD)
            return
        end

        schema = HDParamSchema.getFullSchema();
        merged = HD.params;

        for k = 1:numel(schema)
            entry = schema(k);

            if isempty(entry.widget) || ~isprop(app, entry.widget)
                continue
            end

            value = app.getWidgetValue(entry.widget);

            % Missing controls must not overwrite existing parameters.
            if isempty(value)
                continue
            end

            merged.(entry.param) = value;
        end

        if isprop(app, 'positioninfileSlider')
            position = app.getWidgetValue('positioninfileSlider');

            if ~isempty(position) && isscalar(position) && isfinite(position)
                position = max(1, round(position));

                if ~isempty(HD.file) && ...
                        isfield(HD.file, 'num_frames')

                    lastPosition = max( ...
                        1, HD.file.num_frames - merged.batchSize + 1);

                    position = min(position, lastPosition);
                end

                merged.framePosition = position;
            end

        end

        HD.params = HDParamSchema.validate(merged);
    end

end

methods (Static, Access = private)

    function schema = buildSchema()
        % Columns: parameter, widget, type, default, minimum, maximum.
        rows = {
                'parforArg', 'parforArg', 'numeric', 10, -1, [];

                'batchSize', 'batchSize', 'numeric', 256, 1, [];
                'batchStride', 'batchStride', 'numeric', 256, 1, [];
                'refBatchSize', 'refBatchSize', 'numeric', 512, 1, [];
                'framePosition', 'framePosition', 'numeric', 1, 1, [];
                'first_frame', '', 'numeric', 1, 1, [];
                'end_frame', '', 'numeric', Inf, 1, [];

                'imageTypes', 'imageTypesListBox', 'listbox', ...
                    {'power_Doppler', 'moment_0', 'moment_1', ...
             'moment_2', 'HF_M0', 'LF_M0'}, [], [];

        'imageRegistration', 'imageRegistration', 'checkbox', true, [], [];
        'registrationDiskRatio', 'registrationDiskRatio', 'numeric', 0.8, 0, 1000;
        'autofocusRange1', 'autofocusRange1', 'numeric', 0, 0, [];
        'autofocusRange2', 'autofocusRange2', 'numeric', 1, 0, [];

        'spatialFilter', 'spatialFilter', 'checkbox', false, [], [];
        'spatialFilterRange1', 'spatialFilterRange1', 'numeric', 0, 0, 1;
        'spatialFilterRange2', 'spatialFilterRange2', 'numeric', 1, 0, 1;
        'spatialTransform', 'spatialTransform', 'dropdown', 'Fresnel', [], [];
        'spatialPropagation', 'spatialPropagation', 'numeric', 0, 0, [];
        'PaddingNum', 'PaddingNum', 'numeric', 0, 0, [];

        'filterType', 'filterType', 'dropdown', 'SVD', [], [];
        'svd_filter', '', 'checkbox', true, [], [];
        'svdThreshold', 'svdThreshold', 'numeric', 32, 0, [];
        'svdStride', 'svdStride', 'numeric', 1, 1, [];
        'polynomialDegree', '', 'numeric', 1, 0, [];

        'filterCutoffHz', '', 'numeric', 1000, 0, [];
        'filterOrder', '', 'numeric', 4, 1, [];
        'filterZeroPhase', '', 'checkbox', true, [], [];
        'filterLowHz', '', 'numeric', 1000, 0, [];
        'filterHighHz', '', 'numeric', Inf, 0, [];
        'filterTransitionHz', '', 'numeric', 0, 0, [];

        'timeTransform', 'timeTransform', 'dropdown', 'FFT', [], [];
        'frequencyRange1', 'frequencyRange1', 'numeric', 3, 0, [];
        'frequencyRange2', 'frequencyRange2', 'numeric', 18, 0, [];
        'indexRange1', 'indexRange1', 'numeric', 1, 1, [];
        'indexRange2', 'indexRange2', 'numeric', 100, 1, [];
        'frequencyRange_extra', '', 'numeric', -1, [], [];
        'frequencyRangeBandRatio1', 'frequencyRangeBandRatio1', 'numeric', 6, 0, [];
        'frequencyRangeBandRatio2', 'frequencyRangeBandRatio2', 'numeric', 9, 0, [];

        'flatfield_gw', 'flat_field_gw', 'numeric', 35, 0, [];
        'flip_y', 'flip_y', 'checkbox', false, [], [];
        'flip_x', 'flip_x', 'checkbox', true, [], [];
        'square', 'square', 'checkbox', true, [], [];
        'ImproveContrast', 'ImproveContrast', 'checkbox', false, [], [];
        'CornerCompensation', 'CornerCompensation', 'checkbox', true, [], [];

        'phase_registration', 'phaseregistrationCheckBox', 'checkbox', false, [], [];
        'iterative_registration', 'iterativeregistrationCheckBox', 'checkbox', false, [], [];
        'show_ref', 'showrefCheckBox', 'checkbox', false, [], [];
        };

        schema = struct( ...
            'param', {}, 'widget', {}, 'type', {}, ...
            'default', {}, 'min', {}, 'max', {});

        for k = 1:size(rows, 1)
            entry.param = rows{k, 1};
            entry.widget = rows{k, 2};
            entry.type = rows{k, 3};
            entry.default = rows{k, 4};
            entry.min = rows{k, 5};
            entry.max = rows{k, 6};
            schema(k) = entry;
        end

    end

    function [ok, reason] = isValid(value, entry)
        ok = false;
        reason = '';

        switch entry.type
            case 'numeric'

                if ~isnumeric(value) || isempty(value) || ...
                        ~isreal(value) || any(isnan(value(:)))
                    reason = 'expected real numeric data without NaN';
                    return
                end

                if ~isempty(entry.min) && any(value(:) < entry.min)
                    reason = 'below minimum';
                    return
                end

                if ~isempty(entry.max) && any(value(:) > entry.max)
                    reason = 'above maximum';
                    return
                end

            case 'checkbox'

                if ~HDParamSchema.isBoolean(value)
                    reason = 'expected a boolean scalar';
                    return
                end

            case 'dropdown'
                validText = ...
                    (ischar(value) && isrow(value) && ~isempty(value)) || ...
                    (isstring(value) && isscalar(value));

                if ~validText
                    reason = 'expected a char row or scalar string';
                    return
                end

                text = string(value);

                if ismissing(text) || strlength(text) == 0
                    reason = 'empty or missing selection';
                    return
                end

            case 'listbox'

                if ~iscell(value) || ...
                        ~all(cellfun(@ischar, value(:)))
                    reason = 'expected a cell array of char vectors';
                    return
                end

        end

        % Additional checks for filter parameters.
        try

            switch entry.param
                case 'filterType'

                    if ~ismember(string(value), ClutterFilter.supportedTypes())
                        reason = 'unknown clutter filter';
                        return
                    end

                case 'polynomialDegree'
                    validateattributes(value, {'numeric'}, ...
                        {'scalar', 'real', 'finite', 'integer', 'nonnegative'});

                case 'filterOrder'
                    validateattributes(value, {'numeric'}, ...
                        {'scalar', 'real', 'finite', 'integer', 'positive'});

                case 'filterCutoffHz'
                    validateattributes(value, {'numeric'}, ...
                        {'scalar', 'real', 'finite', 'positive'});

                case {'filterLowHz', 'filterTransitionHz'}
                    validateattributes(value, {'numeric'}, ...
                        {'scalar', 'real', 'finite', 'nonnegative'});

                case 'filterHighHz'
                    % Positive Inf disables upper-frequency rejection.
                    validateattributes(value, {'numeric'}, ...
                        {'scalar', 'real', 'nonnan', 'positive'});
            end

        catch ME
            reason = ME.message;
            return
        end

        ok = true;
    end

    function ok = isBoolean(value)
        ok = (islogical(value) || isnumeric(value)) && ...
            isscalar(value) && isreal(value) && isfinite(value) && ...
            (value == 0 || value == 1);
    end

    function value = getParam(params, name, default)
        value = default;

        if isfield(params, name) && ~isempty(params.(name))
            value = params.(name);
        end

    end

end

end
