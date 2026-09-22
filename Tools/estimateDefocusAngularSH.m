function [c4, phase, info] = estimateDefocusAngularSH( ...
    shiftsX, shiftsY, frameSize, pixelPitch, wavelength, zPropagation, options)
%ESTIMATEDEFOCUSANGULARSH Fit Python-compatible Noll mode 4.
% Internal convention: dimension 1 = x, dimension 2 = y.

arguments
    shiftsX {mustBeNumeric}
    shiftsY {mustBeNumeric}
    frameSize (1,2) double {mustBeInteger,mustBePositive}
    pixelPitch (1,2) double {mustBePositive}
    wavelength (1,1) double {mustBePositive}
    zPropagation (1,1) double
    options.PupilRadius (1,1) double {mustBePositive} = 2
end
if ~isfinite(zPropagation) || zPropagation == 0
    error('estimateDefocusAngularSH:InvalidPropagation', ...
        'zPropagation must be finite and non-zero.');
end
if ~isequal(size(shiftsX),size(shiftsY))
    error('estimateDefocusAngularSH:SizeMismatch', ...
        'shiftsX and shiftsY must have the same size.');
end
Nx=frameSize(1); Ny=frameSize(2); ppx=pixelPitch(1); ppy=pixelPitch(2);
[nSubX,nSubY]=size(shiftsX);

% Same rectangular normalized coordinates as Python, transposed to [x,y].
if Nx>Ny
    x=linspace(-Nx/Ny,Nx/Ny,Nx); y=linspace(-1,1,Ny);
else
    x=linspace(-1,1,Nx); y=linspace(-Ny/Nx,Ny/Nx,Ny);
end
[X,Y]=ndgrid(x,y); R=hypot(X,Y);
Z4=NaN(Nx,Ny,'single'); inside=R<=options.PupilRadius;
Z4(inside)=single(sqrt(3).*(2.*R(inside).^2-1));

% Equivalent of Python:
% dZdx = np.gradient(Z, pixel_pitch_x, axis=1)
% dZdy = np.gradient(Z, pixel_pitch_y, axis=0)
% Here the MATLAB storage is transposed: dimension 1=x, dimension 2=y.
[dZdy,dZdx]=gradient(double(Z4),ppy,ppx);
subNx=floor(Nx/nSubX); subNy=floor(Ny/nSubY);
Gx=NaN(nSubX,nSubY); Gy=NaN(nSubX,nSubY);
for ix=1:nSubX
    xr=(ix-1)*subNx+(1:subNx);
    for iy=1:nSubY
        yr=(iy-1)*subNy+(1:subNy);
        tx=dZdx(xr,yr); ty=dZdy(xr,yr);
        Gx(ix,iy)=mean(tx(:),'omitnan');
        Gy(ix,iy)=mean(ty(:),'omitnan');
    end
end
Gx=Gx.*wavelength/(2*pi); Gy=Gy.*wavelength/(2*pi);

% Angular Spectrum displacement-to-slope conversion used in Python.
sx=double(shiftsX).*ppx.*nSubX./zPropagation;
sy=double(shiftsY).*ppy.*nSubY./zPropagation;
A=[Gx(:);Gy(:)]; b=[sx(:);sy(:)];
valid=isfinite(A)&isfinite(b);
if nnz(valid)<2 || norm(A(valid))<=eps
    error('estimateDefocusAngularSH:Underdetermined', ...
        'Not enough valid sub-apertures to estimate defocus.');
end
c4=A(valid)\b(valid);

% Python Angular Spectrum returns minus the reconstructed fitted phase.
phase=-single(c4).*Z4;
info=struct('validCount',nnz(valid),'residualNorm', ...
    norm(A(valid).*c4-b(valid)),'gradientX',Gx,'gradientY',Gy, ...
    'zernikeMode4',Z4,'convention','python-angular');
end
