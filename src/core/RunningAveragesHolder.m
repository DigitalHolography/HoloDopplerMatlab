classdef RunningAveragesHolder < handle

properties
    running_averages = [];
    numUpdates = 0;
end

methods

    function obj = RunningAveragesHolder()
        obj.reset();
    end

    function reset(obj)
        obj.running_averages = [];
        obj.numUpdates = 0;
    end

    function update(obj, SH_PSD, ~, params)

        if ~any(strcmp(params.imageTypes, 'SH_avg'))
            return
        end

        if isempty(SH_PSD)
            return
        end

        if ~isreal(SH_PSD)
            error('RunningAveragesHolder:ComplexPSD', ...
            'SH_PSD must contain real spectral power.');
        end

        if isempty(obj.running_averages)
            obj.running_averages = struct('SH', SH_PSD);
            obj.numUpdates = 1;
            return
        end

        currentSum = obj.running_averages.SH;

        if ~isequal(size(currentSum), size(SH_PSD))
            error('RunningAveragesHolder:SizeMismatch', ...
            'SH_PSD size changed during accumulation.');
        end

        if ~strcmp(class(currentSum), class(SH_PSD)) || ...
                isa(currentSum, 'gpuArray') ~= isa(SH_PSD, 'gpuArray')
            error('RunningAveragesHolder:TypeMismatch', ...
            'SH_PSD type or CPU/GPU location changed.');
        end

        obj.running_averages.SH = currentSum + SH_PSD;
        obj.numUpdates = obj.numUpdates + 1;
    end

end

end
