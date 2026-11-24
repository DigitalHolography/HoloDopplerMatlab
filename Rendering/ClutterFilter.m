classdef ClutterFilter
    %CLUTTERFILTER Select and apply a clutter filter.
    %
    % Input:
    %   Hin : unfiltered field [Nx, Ny, Nt].
    %   p   : rendering parameter structure.
    %
    % Outputs:
    %   Hout        : filtered field, same dimensions as Hin.
    %   diagnostics : structure containing type, cov and U.
    %
    % Frequency convention:
    %   p.fs is in kHz in the current HoloDoppler pipeline.
    %   New frequency-filter parameters are explicitly in Hz.
    %
    % This class does not cache fields or retain filter state.

    methods (Static)

        function types = supportedTypes()

            types = [ ...
                "None", ...
                "SVD", ...
                "Mean subtraction", ...
                "Polynomial detrending", ...
                "Butterworth high-pass", ...
                "FIR high-pass", ...
                "FFT band-pass" ...
            ];

        end

        function [Hout, diagnostics] = apply(Hin, p)

            arguments
                Hin
                p (1, 1) struct
            end

            if isempty(Hin) || ndims(Hin) > 3
                error('ClutterFilter:InvalidInput', ...
                    ['Expected a nonempty field ', ...
                     'with time along dimension 3.']);
            end

            filterType = ClutterFilter.resolveType(p);

            if ~ismember(filterType, ClutterFilter.supportedTypes())
                error('ClutterFilter:UnknownType', ...
                    'Unknown clutter filter: "%s".', filterType);
            end

            diagnostics = struct( ...
                'type', filterType, ...
                'cov', [], ...
                'U', []);

            switch filterType

                case "None"
                    Hout = Hin;

                case "SVD"
                    % Preserve the existing pipeline frequency units.
                    [Hout, diagnostics.cov, diagnostics.U] = ...
                        svd_filter( ...
                            Hin, ...
                            p.svdThreshold, ...
                            p.frequencyRange1, ...
                            p.fs, ...
                            p.svdStride);

                case "Mean subtraction"
                    Hout = Hin - mean(Hin, 3);

                case "Polynomial detrending"
                    Hout = polynomial_clutter_filter( ...
                        Hin, ...
                        p.polynomialDegree);

                case "Butterworth high-pass"
                    fsHz = 1000 * double(p.fs);

                    Hout = butterworth_clutter_filter( ...
                        Hin, ...
                        p.filterCutoffHz, ...
                        fsHz, ...
                        p.filterOrder, ...
                        p.filterZeroPhase);

                case "FIR high-pass"
                    fsHz = 1000 * double(p.fs);

                    Hout = fir_clutter_filter( ...
                        Hin, ...
                        p.filterCutoffHz, ...
                        fsHz, ...
                        p.filterOrder, ...
                        p.filterZeroPhase);

                case "FFT band-pass"
                    fsHz = 1000 * double(p.fs);

                    Hout = fft_clutter_filter( ...
                        Hin, ...
                        p.filterLowHz, ...
                        p.filterHighHz, ...
                        fsHz, ...
                        p.filterTransitionHz);

            end

            if ~isequal(size(Hout), size(Hin))
                error('ClutterFilter:InvalidOutputSize', ...
                    'The clutter filter must preserve input dimensions.');
            end

        end

        function filterType = resolveType(p)

            arguments
                p (1, 1) struct
            end

            % Explicit selection takes precedence over the legacy flag.
            if isfield(p, 'filterType')

                value = p.filterType;

                validText = ...
                    (ischar(value) && isrow(value) && ~isempty(value)) || ...
                    (isstring(value) && isscalar(value));

                if ~validText
                    error('ClutterFilter:InvalidType', ...
                        ['filterType must be a nonempty char row ', ...
                         'or scalar string.']);
                end

                filterType = string(value);

                if ismissing(filterType) || strlength(filterType) == 0
                    error('ClutterFilter:InvalidType', ...
                        'filterType must not be empty or missing.');
                end

                return
            end

            % Compatibility with legacy parameter structures.
            if isfield(p, 'svd_filter')

                validateattributes( ...
                    p.svd_filter, ...
                    {'logical', 'numeric'}, ...
                    {'scalar', 'real', 'finite', 'binary'}, ...
                    'ClutterFilter.resolveType', ...
                    'svd_filter');

                if p.svd_filter
                    filterType = "SVD";
                else
                    filterType = "None";
                end

                return
            end

            filterType = "SVD";

        end

    end
end