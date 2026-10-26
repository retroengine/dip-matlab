function out = imresize(img, targetSz, method)
% IMRESIZE 2D/3D image resizing using interp2 with zero toolbox dependencies.

if nargin < 3 || isempty(method)
    method = 'bilinear';
end

[H, W, C] = size(img);

if isscalar(targetSz)
    scale = targetSz;
    targetH = max(1, round(H * scale));
    targetW = max(1, round(W * scale));
else
    targetH = round(targetSz(1));
    targetW = round(targetSz(2));
end

if targetH == H && targetW == W
    out = img;
    return;
end

[X, Y] = meshgrid(linspace(1, W, targetW), linspace(1, H, targetH));

out = zeros(targetH, targetW, C, 'like', img);

for c = 1:C
    ch = double(img(:, :, c));
    if strcmpi(method, 'nearest')
        res = interp2(1:W, 1:H, ch, X, Y, 'nearest');
    else
        res = interp2(1:W, 1:H, ch, X, Y, 'linear');
    end
    
    % Fill any edge NaNs with nearest border
    if any(isnan(res(:)))
        res(isnan(res)) = ch(1, 1);
    end
    
    if isfloat(img)
        out(:, :, c) = res;
    else
        out(:, :, c) = cast(min(max(round(res), 0), 255), class(img));
    end
end

end
