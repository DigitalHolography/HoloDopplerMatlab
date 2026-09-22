function [fieldCorrected, phaseTerm, info] = ...
    correctDefocusZernike(field, c4, options)
%CORRECTDEFOCUSZERNIKE Apply Python-compatible Noll-mode-4 correction.
% Input convention is RenderingClass [x,y,t].

arguments
    field {mustBeNumeric}
    c4 (1,1) double {mustBeFinite}
    options.PixelPitch (1,2) double {mustBePositive} = [1 1]
    options.PupilRadius (1,1) double {mustBePositive} = 2
    options.Convention (1,1) string = "python-angular"
    options.OutsidePupil (1,1) string = "zero"
end
Nx=size(field,1); Ny=size(field,2);
if Nx>Ny
    x=linspace(-Nx/Ny,Nx/Ny,Nx); y=linspace(-1,1,Ny);
else
    x=linspace(-1,1,Nx); y=linspace(-Ny/Nx,Ny/Nx,Ny);
end
[X,Y]=ndgrid(x,y); R=hypot(X,Y); inside=R<=options.PupilRadius;
Z4=zeros(Nx,Ny,'single');
Z4(inside)=single(sqrt(3).*(2.*R(inside).^2-1));

switch lower(options.Convention)
    case "python-angular"
        % Python: phase=-c4*Z4, phaseTerm=exp(-1i*phase).
        signedPhase=single(c4).*Z4;
    case "physical-phase"
        signedPhase=-single(c4).*Z4;
    otherwise
        error('correctDefocusZernike:Convention', ...
            'Convention must be python-angular or physical-phase.');
end
phaseTerm=exp(1i*signedPhase);
switch lower(options.OutsidePupil)
    case "zero"
        phaseTerm(~inside)=0;
    case "preserve"
        phaseTerm(~inside)=1;
    otherwise
        error('correctDefocusZernike:OutsidePupil', ...
            'OutsidePupil must be zero or preserve.');
end
phaseTerm=single(phaseTerm);
shape=ones(1,max(ndims(field),2)); shape(1:2)=[Nx Ny];
fieldCorrected=field.*reshape(phaseTerm,shape);
info=struct('coefficientRad',c4,'zernikeMode4',Z4, ...
    'insidePupil',inside,'convention',options.Convention, ...
    'pixelPitch',options.PixelPitch);
end
