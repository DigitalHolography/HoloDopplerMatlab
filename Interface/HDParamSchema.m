classdef HDParamSchema
% HDParamSchema  Single source of truth for HD rendering parameters.
%
%   All parameter access goes through this class:
%     - HDParamSchema.getDefaults()      → struct with all default values
%     - HDParamSchema.validate(params)   → sanitized struct (corrupt fields
%                                          replaced by their default)
%     - HDParamSchema.classtogui(HD,app) → push HD.params + HD.file → GUI
%     - HDParamSchema.guitoclass(HD,app) → push GUI → HD.params
%
%   NOTE: file-bound fields (Nx, Ny, num_frames, fs, lambda, ppx, ppy)
%   live in HD.file and are NOT part of the schema / HD.params.

methods (Static)

    function defaults = getDefaults()
        % Return a struct populated with every parameter default value.
        defaults = struct();
        schema = HDParamSchema.getFullSchema();

        for k = 1:numel(schema)
            defaults.(schema(k).param) = schema(k).default;
        end

    end

    % -----------------------------------------------------------------
    function [clean, warnings] = validate(params)
        % Validate and sanitise a params struct.
        %
        %   [clean, warnings] = HDParamSchema.validate(params)
        %
        %   Every field present in the schema is checked for type and
        %   range. Invalid or missing values are silently replaced by
        %   their schema default. Extra fields (unknown to the schema)
        %   are forwarded unchanged so callers never lose data.
        %
        %   warnings – cellstr, one entry per corrected field.

        warnings = {};

        if ~isstruct(params)
            warning('HDParamSchema:validate:notAStruct', ...
            'validate() called with a non-struct – returning defaults.');
            clean = HDParamSchema.getDefaults();
            return
        end

        % Start from a full-defaults base so missing fields are filled.
        clean = HDParamSchema.getDefaults();

        % Copy unknown fields through untouched.
        schemaKeys = {HDParamSchema.getFullSchema().param};
        allFields = fieldnames(params);

        for k = 1:numel(allFields)

            if ~ismember(allFields{k}, schemaKeys)
                clean.(allFields{k}) = params.(allFields{k});
            end

        end

        % Validate each schema field.
        schema = HDParamSchema.getFullSchema();
        % schemaMap = containers.Map({schema.param}, num2cell(schema));

        for k = 1:numel(schema)
            entry = schema(k);
            fname = entry.param;

            % Use incoming value if present, otherwise keep default.
            if ~isfield(params, fname) || isempty(params.(fname))
                % Already set to default above – nothing to do.
                continue
            end

            value = params.(fname);
            [ok, reason] = HDParamSchema.isValid(value, entry);

            if ok
                % Special post-processing for imageTypes.
                if strcmp(fname, 'imageTypes')
                    possible = fieldnames(ImageTypeList);
                    clean.(fname) = intersect(value, possible, 'stable');
                else
                    clean.(fname) = value;
                end

            else
                % Keep default (already in clean), log a warning.
                msg = sprintf('Parameter "%s" has an invalid value (%s) – using default.', ...
                    fname, reason);
                warnings{end + 1} = msg; %#ok<AGROW>
                warning('HDParamSchema:validate:invalidValue', '%s', msg);
            end

        end

    end

    % -----------------------------------------------------------------
    function s = getFullSchema()
        % Return the full schema array (cached after first build).
        persistent schemaCache

        if isempty(schemaCache)
            schemaCache = HDParamSchema.buildSchema();
        end

        s = schemaCache;
    end

    % -----------------------------------------------------------------
    function classtogui(HD, app)
        % Push HD.params (rendering params) and HD.file (file params)
        % into the app UI widgets.
        if isempty(HD) || isempty(HD.params)
            return
        end

        schema = HDParamSchema.getFullSchema();

        for k = 1:numel(schema)
            e = schema(k);

            if isempty(e.widget) || ~isprop(app, e.widget)
                continue
            end

            value = HDParamSchema.getParam(HD.params, e.param, e.default);
            app.setWidgetValue(e.widget, value);
        end

        % ---- File-bound fields (read from HD.file, not HD.params) ----
        if ~isempty(HD.file)
            app.setWidgetValue('Nx', double(HD.file.Nx));
            app.setWidgetValue('Ny', double(HD.file.Ny));

            if isfield(HD.file, 'num_frames') && isfield(HD.params, 'batchSize')
                newLimits = double([1, HD.file.num_frames - HD.params.batchSize + 1]);

                if newLimits(2) < newLimits(1)
                    newLimits(2) = newLimits(1);
                end

                app.setSliderLimits('positioninfileSlider', newLimits);
                app.setWidgetValue('positioninfileSlider', ...
                    double(HD.params.framePosition));
            end

            % Reflect file-level hardware params in their display fields.
            if isfield(HD.file, 'fs')
                app.setWidgetValue('fs', double(HD.file.fs));
            end

            if isfield(HD.file, 'lambda')
                app.setWidgetValue('lambda', double(HD.file.lambda));
            end

            if isfield(HD.file, 'ppx')
                app.setWidgetValue('ppx', double(HD.file.ppx));
            end

            if isfield(HD.file, 'ppy')
                app.setWidgetValue('ppy', double(HD.file.ppy));
            end

        end

    end

    % -----------------------------------------------------------------
    function guitoclass(HD, app)
        % Push app UI widgets → HD.params (rendering params only).
        % File-bound fields (fs, lambda, ppx, ppy) are NOT written back
        % to HD.params here; they live in HD.file.
        if isempty(HD)
            return
        end

        fileBound = {'fs', 'lambda', 'ppx', 'ppy', 'Nx', 'Ny', 'num_frames'};

        schema = HDParamSchema.getFullSchema();
        raw = struct();

        for k = 1:numel(schema)
            e = schema(k);

            if isempty(e.widget) || ~isprop(app, e.widget)
                continue
            end

            if ismember(e.param, fileBound)
                continue % never overwrite file-bound params from GUI
            end

            value = app.getWidgetValue(e.widget);

            if isempty(value) || (isnumeric(value) && ~all(isfinite(value(:))))
                value = e.default;
            end

            raw.(e.param) = value;
        end

        if isprop(app, 'positioninfileSlider')
            raw.framePosition = round(app.getWidgetValue('positioninfileSlider'));
        end

        % Merge with current params so unwidgeted fields survive,
        % then validate the whole thing.
        merged = HD.params;
        fields = fieldnames(raw);

        for k = 1:numel(fields)
            merged.(fields{k}) = raw.(fields{k});
        end

        HD.params = HDParamSchema.validate(merged);
    end

end % public static methods

% =====================================================================
methods (Static, Access = private)

    function s = buildSchema()
        % Each entry: param, widget, type, default, min, max
        % File-bound fields (fs, lambda, ppx, ppy, Nx, Ny, num_frames)
        % are intentionally ABSENT from this schema.
        s = struct('param', {}, 'widget', {}, 'type', {}, ...
            'default', {}, 'min', {}, 'max', {});

        % ---- parallel ------------------------------------------------
        s(end + 1) = HDParamSchema.entry('parforArg', 'parforArg', 'numeric', 10, -1, []);

        % ---- batch ---------------------------------------------------
        s(end + 1) = HDParamSchema.entry('batchSize', 'batchSize', 'numeric', 256, 1, []);
        s(end + 1) = HDParamSchema.entry('batchStride', 'batchStride', 'numeric', 256, 1, []);
        s(end + 1) = HDParamSchema.entry('refBatchSize', 'refBatchSize', 'numeric', 512, 1, []);
        s(end + 1) = HDParamSchema.entry('framePosition', 'framePosition', 'numeric', 1, 1, []);
        s(end + 1) = HDParamSchema.entry('first_frame', '', 'numeric', 1, 1, []);
        s(end + 1) = HDParamSchema.entry('end_frame', '', 'numeric', Inf, 1, []);

        % ---- image types ---------------------------------------------
        s(end + 1) = HDParamSchema.entry('imageTypes', 'imageTypesListBox', 'listbox', ...
            {{'power_Doppler', 'moment_0', 'moment_1', 'moment_2', 'HF_M0', 'LF_M0'}});
        % Block-mean factor used only for SH and SH_avg storage/export.
        s(end + 1) = HDParamSchema.entry('SHSpatialBinning', '', 'numeric', 16, 1, []);

        % ---- registration --------------------------------------------
        s(end + 1) = HDParamSchema.entry('imageRegistration', 'imageRegistration', 'checkbox', true);
        s(end + 1) = HDParamSchema.entry('registrationDiskRatio', 'registrationDiskRatio', 'numeric', 0.8, 0, 1000);
        s(end + 1) = HDParamSchema.entry('autofocusRange1', 'autofocusRange1', 'numeric', 0, 0, []);
        s(end + 1) = HDParamSchema.entry('autofocusRange2', 'autofocusRange2', 'numeric', 1, 0, []);

        % ---- spatial -------------------------------------------------
        s(end + 1) = HDParamSchema.entry('spatialFilter', 'spatialFilter', 'checkbox', false);
        s(end + 1) = HDParamSchema.entry('spatialFilterRange1', 'spatialFilterRange1', 'numeric', 0, 0, 1);
        s(end + 1) = HDParamSchema.entry('spatialFilterRange2', 'spatialFilterRange2', 'numeric', 1, 0, 1);
        s(end + 1) = HDParamSchema.entry('spatialTransform', 'spatialTransform', 'dropdown', 'Fresnel');
        s(end + 1) = HDParamSchema.entry('spatialPropagation', 'spatialPropagation', 'numeric', 0, 0, []);
        s(end + 1) = HDParamSchema.entry('defocusCorrection', '', 'checkbox', false);
        s(end + 1) = HDParamSchema.entry('defocusCoefficientRad', '', 'numeric', 0, [], []);
        s(end + 1) = HDParamSchema.entry('defocusPupilRadius', '', 'numeric', 2, 0, []);
        s(end + 1) = HDParamSchema.entry('PaddingNum', 'PaddingNum', 'numeric', 0, 0, []);

        % ---- SVD -----------------------------------------------------
        s(end + 1) = HDParamSchema.entry('svd_filter', 'svd_filter', 'checkbox', true);
        s(end + 1) = HDParamSchema.entry('svdThreshold', 'svdThreshold', 'numeric', 32, 0, []);
        s(end + 1) = HDParamSchema.entry('svdStride', 'svdStride', 'numeric', 1, 1, []);

        % ---- time transform ------------------------------------------
        s(end + 1) = HDParamSchema.entry('timeTransform', 'timeTransform', 'dropdown', 'FFT');
        s(end + 1) = HDParamSchema.entry('frequencyRange1', 'frequencyRange1', 'numeric', 6, 0, []);
        s(end + 1) = HDParamSchema.entry('frequencyRange2', 'frequencyRange2', 'numeric', 18, 0, []);
        s(end + 1) = HDParamSchema.entry('indexRange1', 'indexRange1', 'numeric', 1, 1, []);
        s(end + 1) = HDParamSchema.entry('indexRange2', 'indexRange2', 'numeric', 100, 1, []);

        % ---- extra ---------------------------------------------------
        s(end + 1) = HDParamSchema.entry('frequencyRange_extra', '', 'numeric', -1, [], []);
        s(end + 1) = HDParamSchema.entry('frequencyRangeBandRatio1', 'frequencyRangeBandRatio1', 'numeric', 3, 0, []);
        s(end + 1) = HDParamSchema.entry('frequencyRangeBandRatio2', 'frequencyRangeBandRatio2', 'numeric', 9, 0, []);

        % ---- post-processing -----------------------------------------
        s(end + 1) = HDParamSchema.entry('flatfield_gw', 'flat_field_gw', 'numeric', 35, 0, []);
        s(end + 1) = HDParamSchema.entry('flip_y', 'flip_y', 'checkbox', false);
        s(end + 1) = HDParamSchema.entry('flip_x', 'flip_x', 'checkbox', true);
        s(end + 1) = HDParamSchema.entry('square', 'square', 'checkbox', true);
        s(end + 1) = HDParamSchema.entry('ImproveContrast', 'ImproveContrast', 'checkbox', false);
        s(end + 1) = HDParamSchema.entry('CornerCompensation', 'CornerCompensation', 'checkbox', true);

        % ---- advanced ------------------------------------------------
        s(end + 1) = HDParamSchema.entry('phase_registration', 'phaseregistrationCheckBox', 'checkbox', false);
        s(end + 1) = HDParamSchema.entry('iterative_registration', 'iterativeregistrationCheckBox', 'checkbox', false);
        s(end + 1) = HDParamSchema.entry('show_ref', 'showrefCheckBox', 'checkbox', false);
        s(end + 1) = HDParamSchema.entry('bucketsRanges', '', 'numeric', []);
        s(end + 1) = HDParamSchema.entry('buckets_raw', 'bucketsraw', 'checkbox', false);
    end

    % -----------------------------------------------------------------
    function e = entry(param, widget, type, default, minVal, maxVal)
        if nargin < 5, minVal = []; end
        if nargin < 6, maxVal = []; end
        e = struct('param', param, 'widget', widget, 'type', type, ...
            'default', default, 'min', minVal, 'max', maxVal);
    end

    % -----------------------------------------------------------------
    function [ok, reason] = isValid(value, entry)
        % Returns true/false + a short human-readable reason on failure.
        ok = true;
        reason = '';

        switch entry.type
            case 'numeric'

                if ~isnumeric(value) || isempty(value)
                    ok = false; reason = 'not numeric or empty'; return
                end

                % NaN check (Inf is intentionally allowed for end_frame).
                if any(isnan(value(:)))
                    ok = false; reason = 'contains NaN'; return
                end

                if ~isempty(entry.min) && any(value(:) < entry.min)
                    ok = false;
                    reason = sprintf('value %g < min %g', min(value(:)), entry.min);
                    return
                end

                if ~isempty(entry.max) && any(value(:) > entry.max)
                    ok = false;
                    reason = sprintf('value %g > max %g', max(value(:)), entry.max);
                    return
                end

            case 'checkbox'

                if ~(islogical(value) || ...
                        (isnumeric(value) && isscalar(value) && any(value == [0 1])))
                    ok = false; reason = 'not a boolean scalar'; return
                end

            case 'listbox'

                if ~(iscell(value) && all(cellfun(@ischar, value)))
                    ok = false; reason = 'not a cell array of char'; return
                end

            case 'dropdown'

                if ~(ischar(value) || (isstring(value) && isscalar(value)))
                    ok = false; reason = 'not a char/string scalar'; return
                end

        end

    end

    % -----------------------------------------------------------------
    function value = getParam(params, name, default)

        if isfield(params, name) && ~isempty(params.(name))
            value = params.(name);
        else
            value = default;
        end

    end

end % private static methods

end % classdef
