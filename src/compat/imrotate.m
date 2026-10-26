function out = imrotate(img, angleDeg, method, bbox)
% IMROTATE 2D image rotation using interp2 with zero toolbox dependencies.

if nargin < 3 || isempty(method), method = 'bilinear'; end
if nargin < 4 || isempty(bbox), bbox = 'crop'; end

if abs(angleDeg) < 1e-4
    out = img;
    return;
end

[H, W, C] = size(img);
rad = angleDeg * pi / 180;
R = [cos(rad), sin(rad); -sin(rad), cos(rad)];

cx = (W + 1) / 2;
cy = (H + 1) / 2;

[X, Y] = meshgrid(1:W, 1:H);
relX = X - cx;
relY = Y - cy;

% Inverse rotation mapping
origCoord = [relX(:), relY(:)] * R;
origX = reshape(origCoord(:, 1) + cx, H, W);
origY = reshape(origCoord(:, 2) + cy, H, W);

out = zeros(H, W, C, 'like', img);

for c = 1:C
    ch = double(img(:, :, c));
    if strcmpi(method, 'nearest')
        res = interp2(1:W, 1:H, ch, origX, origY, 'nearest', 0);
    else
        res = interp2(1:W, 1:H, ch, origX, origY, 'linear', 0);
    end
    
    if isfloat(img)
        out(:, :, c) = res;
    else
        out(:, :, c) = cast(min(max(round(res), 0), 255), class(img));
    end
end

end
