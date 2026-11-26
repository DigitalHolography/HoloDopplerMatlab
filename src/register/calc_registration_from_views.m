function [SH_PSD] = calc_registration_from_views(view, view_ref, params)
SH_PSD = [];

for i = 1:numel(params.imageTypes)

    if ismember(params.imageTypes{i}, {'SH_avg'})
        % view.SH contains the complex temporal Fourier transform.
        SH_PSD = abs(view.SH) .^ 2;

        M0 = view.Output.power_Doppler.image;
        M0_ref = view_ref.Output.power_Doppler.image;
        [Ny, Nx] = size(M0);
        disk = diskMask(Nx, Ny, params.registrationDiskRatio / 2);
        mask = logical(disk);

        if ~any(mask(:))
            error('HoloDoppler:EmptyRegistrationMask', ...
            'Registration mask is empty.');
        end

        M0_tmp = (M0 - mean(M0(mask))) .* single(mask);
        M0ref_tmp = (M0_ref - mean(M0_ref(mask))) .* single(mask);
        [~, shift] = registerImagesCrossCorrelation(M0_tmp, M0ref_tmp);

        for j = 1:size(SH_PSD, 3) % each frequency
            SH_PSD(:, :, j) = circshift(SH_PSD(:, :, j), floor(shift));
        end

    end

end

end
