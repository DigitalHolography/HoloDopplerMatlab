function A_padded = pad3DToSquare(A, ND)

[NY, NX, ~] = size(A);
% Determine the target size
if nargin < 2
    ND = max(NX, NY);
end

targetSize = ND;

% Get size of the 3D array
[rows, cols, ~] = size(A);

if rows == cols && rows == ND
    A_padded = A;
    return
end

% Compute padding for rows and columns
rowPadTotal = targetSize - rows;
colPadTotal = targetSize - cols;

rowPadPre = floor(rowPadTotal / 2);
rowPadPost = ceil(rowPadTotal / 2);

colPadPre = floor(colPadTotal / 2);
colPadPost = ceil(colPadTotal / 2);

% Pad the array
A_padded = padarray(A, [rowPadPre, colPadPre, 0], 0, 'pre');
A_padded = padarray(A_padded, [rowPadPost, colPadPost, 0], 0, 'post');
end
