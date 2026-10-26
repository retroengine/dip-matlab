function out = imgaussfilt(img, sigma)
% IMGAUSSFILT 2D Gaussian filtering with zero toolbox dependencies.
%
% Implements separable 2D Gaussian convolution with boundary replication.
% Supports both 2D grayscale and 3D multi-channel images (uint8 or double/single).

if nargin < 2 || isempty(sigma)
    sigma = 1;
end
if sigma <= 1e-4
    out = img;
    return;
end

radius = max(1, ceil(3 * sigma));
x = -radius:radius;
k = exp(-x.^2 / (2 * sigma^2));
k = k / sum(k);

wasUint8 = isa(img, 'uint8');
if wasUint8
    img = double(img);
end

[H, W, C] = size(img);
out = zeros(H, W, C, 'like', img);

for c = 1:C
    ch = img(:, :, c);
    
    % Replicate horizontal boundaries
    chH = [repmat(ch(:, 1), 1, radius), ch, repmat(ch(:, end), 1, radius)];
    convH = conv2(chH, k, 'valid');
    
    % Replicate vertical boundaries
    chV = [repmat(convH(1, :), radius, 1); convH; repmat(convH(end, :), radius, 1)];
    out(:, :, c) = conv2(chV, k', 'valid');
end

if wasUint8
    out = uint8(min(max(round(out), 0), 255));
end

end
