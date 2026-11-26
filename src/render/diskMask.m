function [mask, R] = diskMask(numX, numY, D1, D2, opt)

% numX, numY : size of the mask
% If nargin = 3:
% D1: upper bound of the diameter
% If nargin = 4:
% D1: lower bound of the diameter
% D2: upper bound of the diameter

arguments
    numX
    numY
    D1
    D2 = sqrt(2)
    opt.center = [1/2, 1/2]
end

if D1 > D2
    error("D1 must be lower than D2")
end

x_center = opt.center(1);
y_center = opt.center(2);

x = linspace(0, 1, numX);
y = linspace(0, 1, numY);

[X, Y] = meshgrid(x, y);
R = (((X - x_center)) .^ 2 + ((Y - y_center)) .^ 2) .* 4;

if nargin == 3
    % Sup & Equal so that r2 = 0.5 includes the radius
    mask = R <= D1 ^ 2;
elseif nargin == 4
    % Inf & Equal so that r1 = 0 excludes the whole image
    % Sup & Equal so that r2 = 0.5 includes the radius
    mask = (R > D1 ^ 2) & (R <= D2 ^ 2);
end

end
