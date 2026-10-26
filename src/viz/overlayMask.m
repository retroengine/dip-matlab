function overlay = overlayMask(I, mask, color, alpha)
% OVERLAYMASK Render semi-transparent color overlay of mask onto image.
%
% Inputs:
%   I     - 3D double or uint8 RGB image
%   mask  - 2D logical or binary mask
%   color - (Optional) 1x3 RGB overlay color (default red: [1 0 0])
%   alpha - (Optional) Opacity of overlay (default 0.55)
%
% Output:
%   overlay - 3D double RGB image in [0, 1]

if nargin < 3 || isempty(color)
    color = [1 0 0]; % Red overlay
end
if nargin < 4 || isempty(alpha)
    alpha = 0.55;
end

if ~isfloat(I)
    I = im2double(I);
else
    I = min(max(I, 0), 1);
end

mask = logical(mask);
overlay = I;

for c = 1:3
    channel = overlay(:, :, c);
    channel(mask) = (1 - alpha) * channel(mask) + alpha * color(c);
    overlay(:, :, c) = channel;
end

% Draw outline around mask boundary for visual clarity
se = strel('disk', 1);
dil = imdilate(mask, se);
boundary = dil & (~mask);

for c = 1:3
    channel = overlay(:, :, c);
    channel(boundary) = color(c);
    overlay(:, :, c) = channel;
end

overlay = min(max(overlay, 0), 1);

end
