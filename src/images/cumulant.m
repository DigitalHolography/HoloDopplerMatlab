function [moment] = cumulant(A, n1, n2)
% integration interval
% A : 3D array x,y,omega
% idxspan1 = index vector (positive freqs)
% idxspan2 = index vector (negative freqs)

moment = squeeze(sum(A(:, :, n1:n2), 3));

end
