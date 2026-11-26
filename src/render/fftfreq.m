function f = fftfreq(n, d)
%FFTFREQ Return the Discrete Fourier Transform sample frequencies
%
%   f = fftfreq(n)
%   f = fftfreq(n, d)
%
% Parameters
% ----------
% n : integer
%     Window length
% d : scalar (optional)
%     Sample spacing (default = 1)
%
% Returns
% -------
% f : array of length n containing the sample frequencies

if nargin < 2
    d = 1.0;
end

val = 1.0 / (n * d);

N = floor((n - 1) / 2) + 1;

p1 = 0:(N - 1);
p2 = -floor(n / 2):-1;

f = [p1 p2] * val;
end
