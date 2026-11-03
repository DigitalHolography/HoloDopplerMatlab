classdef ImageType < handle
% A single typed output slot in the rendering pipeline.
%
% Lifecycle:
%   select()  – mark this slot for computation
%   clear()   – deselect and wipe computed data (schema preserved)
%   reset()   – restore to post-constructor state (keeps schema)

properties
    short_name (1, :) char
    is_selected (1, 1) logical = false
    image % Computed raster (may be [] if not yet run)
    graph % Optional figure handle
    parameters % Struct of auxiliary outputs (schema set at construction)
end

% -----------------------------------------------------------------------
methods

    function obj = ImageType(short_name, parameters)
        % ImageType  Constructor.
        %   ImageType(short_name)             – no auxiliary parameters
        %   ImageType(short_name, parameters) – struct defines the schema
        arguments
            short_name (1, :) char
            parameters struct = struct()
        end

        obj.short_name = short_name;
        obj.is_selected = false;
        obj.image = [];
        obj.graph = [];
        obj.parameters = parameters;
    end

    % ------------------------------------------------------------------
    function select(obj)
        % Mark this image type for computation on the next Render call.
        obj.is_selected = true;
    end

    % ------------------------------------------------------------------
    function clear(obj)
        % Deselect and wipe computed data; parameter schema is preserved.
        obj.is_selected = false;
        obj.image = [];
        obj.graph = [];
        obj.resetParameters();
    end

    % ------------------------------------------------------------------
    function copy_from(obj, src)
        % Shallow-copy all properties from src into obj.
        arguments
            obj ImageType
            src ImageType
        end

        props = properties(src);

        for k = 1:numel(props)
            obj.(props{k}) = src.(props{k});
        end

    end

    % ------------------------------------------------------------------
    function image2png(obj, preview_folder_name, folder_path)
        if isempty(obj.image)
            warning('HoloDoppler:EmptyImage', ...
                'ImageType "%s" is empty; export skipped.', obj.short_name);
            return;
        end

        if ~isfolder(folder_path)
            mkdir(folder_path);
        end

        % Preserve the existing vertical-flip convention.
        imageData = flip(obj.image, 1);

        [rgb, validMask] = toImageSource(imageData);

        filename = sprintf('%s_%s.png', ...
            preview_folder_name, obj.short_name);

        imwrite(rgb, fullfile(folder_path, filename), ...
            'Alpha', double(validMask));
    end

end % public methods

% -----------------------------------------------------------------------
methods (Access = private)

    function resetParameters(obj)
        % Set all parameter fields back to [] while keeping the field names.
        fields = fieldnames(obj.parameters);

        for k = 1:numel(fields)
            obj.parameters.(fields{k}) = [];
        end

    end

end

end % classdef
