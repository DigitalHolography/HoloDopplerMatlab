function [c4, result] = autofocusDefocus(rend, p, fileInfo, options)
%AUTOFOCUSDEFOCUS Estime le defocus Zernike depuis le batch de reference.
%
% Cette fonction est le nouveau moteur du bouton Autofocus. Elle ne modifie
% pas spatialPropagation. Elle construit les sous-apertures Doppler comme le
% pipeline Python, mesure leurs deplacements, puis ajuste le mode Noll 4.

arguments
    rend RenderingClass
    p struct
    fileInfo struct
    options.NumSubapertures (1,2) double {mustBeInteger,mustBePositive} = [5 5]
    options.ZernikeModes double {mustBeInteger,mustBePositive} = 4
    options.PupilThreshold (1,1) double {mustBePositive} = 1
    options.DeviationThreshold (1,1) double {mustBePositive} = 3
    options.MaxShiftPixels (1,1) double {mustBePositive} = 20
    options.ShowDiagnostic (1,1) logical = true
end

if ~isequal(options.ZernikeModes,4)
    error('autofocusDefocus:DefocusOnly', ...
        'This button replacement currently fits Noll mode 4 only.');
end
if ~strcmpi(strtrim(p.spatialTransform), 'Angular spectrum')
    error('autofocusDefocus:AngularSpectrumOnly', ...
        'This autofocus supports Angular Spectrum only.');
end
if p.spatialPropagation == 0
    error('autofocusDefocus:ZeroPropagation', ...
        'spatialPropagation must be non-zero for the Angular Spectrum fit.');
end
required = {'lambda','ppx','ppy','fs'};
if ~all(isfield(fileInfo, required))
    error('autofocusDefocus:MissingMetadata', ...
        'fileInfo must contain lambda, ppx, ppy and fs.');
end

frames = rend.RawFrames;
if isempty(frames), frames = rend.Frames; end
if isempty(frames)
    error('autofocusDefocus:NoFrames', ...
        'Render a preview before running autofocus.');
end

h = waitbar(0, 'Autofocus: construction des sous-apertures...');
cleanup = onCleanup(@() closeWaitbar(h)); %#ok<NASGU>

subImages = constructSubImages(single(frames), p, fileInfo, ...
    options.NumSubapertures);
waitbar(0.65, h, 'Autofocus: correlation des sous-apertures...');

[shiftsX, shiftsY, validMask] = measureShifts(subImages, options);
waitbar(0.85, h, 'Autofocus: ajustement Zernike...');

[c4, phaseEstimate, fit] = estimateDefocusAngularSH( ...
    shiftsX, shiftsY, ...
    [size(frames,1), size(frames,2)], ...
    [fileInfo.ppx, fileInfo.ppy], ...
    fileInfo.lambda, p.spatialPropagation, ...
    PupilRadius=2);

% Le fit porte uniquement sur Noll 4 ; c4 reste un scalaire.
c4 = double(c4(1));
[~, phaseTerm, phaseInfo] = correctDefocusZernike( ...
    complex(ones(size(frames,1), size(frames,2), 'single')), ...
    c4, PixelPitch=[fileInfo.ppx fileInfo.ppy], ...
    PupilRadius=2, Convention="python-angular", ...
    OutsidePupil="preserve");

result = struct( ...
    'coefficientRad', c4, ...
    'phaseTerm', phaseTerm, ...
    'phaseEstimate', phaseEstimate, ...
    'shiftsX', shiftsX, ...
    'shiftsY', shiftsY, ...
    'validMask', validMask, ...
    'subImages', subImages, ...
    'fit', fit, ...
    'phaseInfo', phaseInfo);

waitbar(1, h, sprintf('Defocus c4 = %.6g rad', c4));
if options.ShowDiagnostic
    showDiagnostic(result);
end
end

function U = constructSubImages(frames, p, fileInfo, numSub)
[Nx, Ny, Nt] = size(frames);
nSubX = numSub(1); nSubY = numSub(2);
subNx = floor(Nx/nSubX); subNy = floor(Ny/nSubY);
if subNx < 3 || subNy < 3
    error('autofocusDefocus:SmallSubaperture', ...
        'Each sub-aperture must contain at least 3-by-3 pixels.');
end

kernel = propagation_kernelAngularSpectrum( ...
    Nx, Ny, p.spatialPropagation, fileInfo.lambda, ...
    fileInfo.ppx, fileInfo.ppy, false);

% RenderingClass stocke [x,y,t]. Passage au plan spectral puis centrage.
F = fft2(complex(frames)) .* kernel;
F = fftshift(fftshift(F,1),2);

cropNx = subNx*nSubX; cropNy = subNy*nSubY;
x0 = floor((Nx-cropNx)/2)+1; y0 = floor((Ny-cropNy)/2)+1;
F = F(x0:x0+cropNx-1, y0:y0+cropNy-1, :);

U = zeros(nSubX,nSubY,subNx,subNy,'single');
idx = frequencyIndices(p,fileInfo.fs,Nt);
for ix=1:nSubX
    xr=(ix-1)*subNx+(1:subNx);
    for iy=1:nSubY
        yr=(iy-1)*subNy+(1:subNy);
        Fs=ifftshift(ifftshift(F(xr,yr,:),1),2);
        H=ifft2(Fs);
        if p.svd_filter
            H=svd_filter(H,p.svdThreshold,p.frequencyRange1, ...
                fileInfo.fs,p.svdStride);
        end
        SH=fft(H,[],3)./sqrt(Nt);
        U(ix,iy,:,:)=single(mean(abs(SH(:,:,idx)).^2,3));
    end
end
end

function idx=frequencyIndices(p,fs,Nt)
f=(0:Nt-1)*fs/Nt;
lo=p.frequencyRange1; hi=p.frequencyRange2;
idx=find((f>=lo & f<=hi) | ((fs-f)>=lo & (fs-f)<=hi));
if isempty(idx)
    error('autofocusDefocus:EmptyBand', ...
        'The selected frequency range contains no FFT bin.');
end
end

function [sx,sy,valid]=measureShifts(U,options)
[nx,ny,Nx,Ny]=size(U);
ref=squeeze(U(ceil(nx/2),ceil(ny/2),:,:));
ref=ref-mean(ref(:)); R=fft2(ref);
sx=NaN(nx,ny,'single'); sy=NaN(nx,ny,'single');
for ix=1:nx
    for iy=1:ny
        im=squeeze(U(ix,iy,:,:)); im=im-mean(im(:));
        cps=fft2(im).*conj(R); cps=cps./(abs(cps)+eps('single'));
        c=abs(fftshift(ifft2(cps)));
        [~,k]=max(c(:)); [px,py]=ind2sub([Nx Ny],k);
        [dx,dy]=subpixelPeak(c,px,py);
        sx(ix,iy)=single(px+dx-(floor(Nx/2)+1));
        sy(ix,iy)=single(py+dy-(floor(Ny/2)+1));
    end
end
[x,y]=ndgrid(linspace(-1,1,nx),linspace(-1,1,ny));
valid=x.^2+y.^2<=options.PupilThreshold^2 & ...
    abs(sx)<=options.MaxShiftPixels & abs(sy)<=options.MaxShiftPixels;
for s={sx,sy}
    v=s{1}(valid); m=median(v,'omitnan');
    d=1.4826*median(abs(v-m),'omitnan');
    if isfinite(d)&&d>0
        valid=valid & abs(s{1}-m)<=options.DeviationThreshold*d;
    end
end
sx(~valid)=NaN; sy(~valid)=NaN;
end

function [dx,dy]=subpixelPeak(c,x,y)
dx=0;dy=0;
if x>1&&x<size(c,1)
    a=c(x-1,y);b=c(x,y);q=c(x+1,y);d=a-2*b+q;
    if abs(d)>eps,dx=.5*(a-q)/d;end
end
if y>1&&y<size(c,2)
    a=c(x,y-1);b=c(x,y);q=c(x,y+1);d=a-2*b+q;
    if abs(d)>eps,dy=.5*(a-q)/d;end
end
end

function showDiagnostic(r)
figure('Name','Autofocus defocus','Color','w');tiledlayout(2,2);
nexttile;imagesc(r.shiftsX');axis image;colorbar;title('shift X');
nexttile;imagesc(r.shiftsY');axis image;colorbar;title('shift Y');
nexttile;imagesc(r.validMask');axis image;colorbar;title('valid');
nexttile;imagesc(angle(r.phaseTerm'));axis image;colorbar;
title(sprintf('phase, c4=%.4g rad',r.coefficientRad));
end

function closeWaitbar(h)
if ~isempty(h)&&isgraphics(h),close(h);end
end
