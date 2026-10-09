function [SH_PSD] = calc_registration_from_views(view, view_ref, params)
SH_PSD = [];

for i = 1:numel(params.imageTypes)

    if ismember(params.imageTypes{i}, {'SH_avg'})
        % view.SH contains the complex temporal Fourier transform.
        SH_PSD = abs(view.SH) .^ 2;

        % The accumulator receives power, never the complex field.
        obj.running_averages.update(SH_PSD, i, params);

        M0 = view.Output.power_Doppler.image;
        M0_ref = view_ref.Output.power_Doppler.image;
        [Ny, Nx] = size(M0);
        disk = diskMask(Nx, Ny, params.registrationDiskRatio / 2);
        M0_tmp = (M0 .* disk - mean(M0(disk))) / max(abs(M0(disk)));
        M0ref_tmp = (M0_ref .* disk - mean(M0_ref(disk))) / max(abs(M0_ref(disk)));
        [~, shift] = registerImagesCrossCorrelation(M0_tmp, M0ref_tmp);

        for j = 1:size(SH_PSD, 3) % each frequency
            SH_PSD(:, :, j) = circshift(SH_PSD(:, :, j), floor(shift));
        end

    end

end

end
