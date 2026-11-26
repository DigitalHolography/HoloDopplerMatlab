function [OF_obj, OF_obj1, OF_obj2, OF_objn, H1, A_cam, C_cam] = twin_image_removal_(H, Mp, ParamChanged, Params, SpatialKernel)
% cc maciej trusiak
% https://www.sciencedirect.com/science/article/pii/S0143816623004074
% https://doi.org/10.1016/j.optlaseng.2023.107878

%1) calculate fft2
F = fft2(H);

if isempty(Mp)
    Mp = rescale(log1p(abs(F(:, :, 1)))) > 0.45;

    Mp = imgaussfilt(single(Mp), 10) > 0.5;

    CC = bwconncomp(Mp);

    [h, w] = size(Mp);

    borderIdx = unique([1:h, ...
                            (w - 1) * h + 1:h * w, ...
                            1:h:h * w, ...
                            h:h:h * w]);

    touchesBorder = cellfun(@(x) any(ismember(x, borderIdx)), CC.PixelIdxList);
    areas = cellfun(@numel, CC.PixelIdxList);
    areas(touchesBorder) = 0;

    [~, idx] = max(areas);

    Mp_biggest = false(size(Mp));

    if idx > 0
        Mp_biggest(CC.PixelIdxList{idx}) = true;
    end

    Mp = Mp_biggest;

    SE = strel('disk', 3);
    Mp_dilated = imdilate(Mp, SE);

    Mp = Mp_dilated;
end

if class(Mp) == "string"
    Mp = imread(Mp) > 0;
end

[rows, cols] = find(Mp);
cy = floor(mean(rows));
cx = floor(mean(cols));

% figure(1), imagesc(log1p(abs(F(:,:,1))));

Ma = 1 - (Mp | rot90(Mp, 2));

C_cam = ifft2(circshift(F .* rot90(Mp, 0), - [cy, cx]));

% figure(), imshow(Mp);
% figure(), imagesc(fftshift(log1p(abs(circshift(F .* rot90(Mp,0),-[cy,cx])))));

A_cam = abs(ifft2(F .* Ma));

P_cam = angle(C_cam);

% [X,Y] = meshgrid(linspace(-1,1,size(H,2)),linspace(-1,1,size(H,1)));
%
% [p, fitPhase] = fitSphericPhase(exp(1j*P_cam), X, Y);

P_cam_unwrapped = unwrap_2d2(double(P_cam));

if min(P_cam_unwrapped(:)) < 0
    P_cam_unwrapped = P_cam_unwrapped - min(P_cam_unwrapped(:));
end

P_cam = P_cam_unwrapped - imgaussfilt(P_cam_unwrapped, 60);

H1 = A_cam .* exp(1j * P_cam);

if ParamChanged.spatialPropagation || ParamChanged.spatialTransform || isempty(SpatialKernel)
    [NY, NX, ~] = size(H);
    SpatialKernel = propagation_kernelAngularSpectrum(NX, NY, Params.spatialPropagation, Params.lambda, Params.ppx, Params.ppy, 0);
end

FH1 = fft2(H1);
FH1 = FH1 .* fftshift(SpatialKernel);
OF_obj1 = ifft2(FH1);

FH2 = fft2(A_cam);
FH2 = FH2 .* fftshift(SpatialKernel);
OF_obj2 = ifft2(FH2);

FH = fft2(H);
FH = FH .* fftshift(SpatialKernel);
OF_objn = ifft2(FH);

M_obj = circshift(Mp, - [cy, cx]);
OF_obj = ifft2(fft2(OF_obj1) .* M_obj + fft2(OF_obj2) .* (1 - M_obj));

figure(1)
sgtitle('Magnitude Comparison')
subplot(1, 4, 1); imagesc(abs(OF_obj1)); title('OF\_obj1 | Magnitude'); colormap gray; axis image; axis off
subplot(1, 4, 2); imagesc(abs(OF_obj2)); title('OF\_obj2 | Magnitude'); colormap gray; axis image; axis off
subplot(1, 4, 3); imagesc(abs(OF_obj)); title('OF\_obj | Magnitude'); colormap gray; axis image; axis off
subplot(1, 4, 4); imagesc(abs(OF_objn)); title('OF\_objn | Magnitude'); colormap gray; axis image; axis off

figure(2)
sgtitle('Phase Comparison')
subplot(1, 4, 1); imagesc(angle(OF_obj1)); title('OF\_obj1 | Phase'); colormap gray; axis image; axis off
subplot(1, 4, 2); imagesc(angle(OF_obj2)); title('OF\_obj2 | Phase'); colormap gray; axis image; axis off
subplot(1, 4, 3); imagesc(angle(OF_obj)); title('OF\_obj | Phase'); colormap gray; axis image; axis off
subplot(1, 4, 4); imagesc(angle(OF_objn)); title('OF\_objn | Phase'); colormap gray; axis image; axis off

figure(3)
sgtitle('Camera Parameters')
subplot(1, 3, 1); imagesc(P_cam); title('P\_cam'); colormap gray; axis image; axis off
subplot(1, 3, 2); imagesc(A_cam); title('A\_cam'); colormap gray; axis image; axis off
subplot(1, 3, 3); imagesc(abs(C_cam)); title('C\_cam | Magnitude'); colormap gray; axis image; axis off

end
