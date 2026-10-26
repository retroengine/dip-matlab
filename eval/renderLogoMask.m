function m = renderLogoMask(sz, caption)
% RENDERLOGOMASK Synthesizes an antialiased logo mask (mountain emblem + text).
%
% Inputs:
%   sz      - [height, width] of output mask
%   caption - (Optional) text caption string (default 'LUKE COLLINS')
%
% Output:
%   m       - 2D double array in [0, 1] containing soft logo mask

if nargin < 2 || isempty(caption)
    caption = 'LUKE COLLINS';
end

H = sz(1);
W = sz(2);
m = zeros(H, W);

% 1. Render geometric mountain peaks
[X, Y] = meshgrid(1:W, 1:H);

% Mountain peak 1 (center-left)
m1_cx = W * 0.4;
m1_cy = H * 0.25;
m1_base = H * 0.65;
m1_w = W * 0.35;

inM1 = (Y >= m1_cy) & (Y <= m1_base) & ...
       (abs(X - m1_cx) <= (m1_w / (m1_base - m1_cy)) * (Y - m1_cy));

% Mountain peak 2 (center-right, slightly lower)
m2_cx = W * 0.65;
m2_cy = H * 0.35;
m2_base = H * 0.65;
m2_w = W * 0.3;

inM2 = (Y >= m2_cy) & (Y <= m2_base) & ...
       (abs(X - m2_cx) <= (m2_w / (m2_base - m2_cy)) * (Y - m2_cy));

% Outline style: hollow inside
m1_inner = (Y >= m1_cy + 4) & (Y <= m1_base - 2) & ...
           (abs(X - m1_cx) <= (m1_w / (m1_base - m1_cy)) * (Y - m1_cy - 4));
m2_inner = (Y >= m2_cy + 4) & (Y <= m2_base - 2) & ...
           (abs(X - m2_cx) <= (m2_w / (m2_base - m2_cy)) * (Y - m2_cy - 4));

m( (inM1 & ~m1_inner) | (inM2 & ~m2_inner) ) = 1.0;

% 2. Render caption bar underneath mountain peaks
textH = max(8, floor(H * 0.25));
textW = floor(W * 0.85);
textMask = renderTextMask(caption, [textH, textW], 0, max(8, floor(textH * 0.7)));

yStart = floor(H * 0.7);
yEnd = min(H, yStart + textH - 1);
xStart = floor((W - textW) / 2) + 1;
xEnd = min(W, xStart + textW - 1);

tH_actual = yEnd - yStart + 1;
tW_actual = xEnd - xStart + 1;

m(yStart:yEnd, xStart:xEnd) = max(m(yStart:yEnd, xStart:xEnd), textMask(1:tH_actual, 1:tW_actual));

% 3. Soft antialiasing
m = imgaussfilt(m, 0.6);
m = min(max(m, 0), 1);

end
