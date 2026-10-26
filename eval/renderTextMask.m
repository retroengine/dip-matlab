function m = renderTextMask(str, sz, angleDeg, fontSize, fontName)
% RENDERTEXTMASK Render anti-aliased text coverage m in [0, 1].
%
% Text is drawn black-on-white in an invisible figure (works under
% matlab -batch), read back, rotated with imrotate('loose') so nothing is
% clipped, and cropped to its tight bounding box.
%
% Inputs:
%   str      - Text string
%   sz       - [] for a tight crop, or [h w]: the text is scaled down if
%              needed to fit and centred on an h x w canvas
%   angleDeg - Rotation in degrees, counter-clockwise (default 0)
%   fontSize - Font size in pixels (default 24)
%   fontName - Font family (default 'Arial')
%
% Output:
%   m        - 2-D double coverage map in [0, 1]

if nargin < 2, sz = []; end
if nargin < 3 || isempty(angleDeg), angleDeg = 0; end
if nargin < 4 || isempty(fontSize), fontSize = 24; end
if nargin < 5 || isempty(fontName), fontName = 'Arial'; end

% Canvas comfortably larger than the text
cw = ceil(fontSize * (numel(str) + 2));
ch = ceil(fontSize * 3);
f = figure('Visible', 'off', 'Color', 'white', 'Units', 'pixels', ...
           'Position', [50 50 cw ch], 'MenuBar', 'none', 'ToolBar', 'none');
cleanup = onCleanup(@() close(f));
ax = axes('Parent', f, 'Units', 'normalized', 'Position', [0 0 1 1], ...
          'XLim', [0 cw], 'YLim', [0 ch], 'Visible', 'off');
text(ax, cw / 2, ch / 2, str, 'FontUnits', 'pixels', 'FontSize', fontSize, ...
     'FontName', fontName, 'FontWeight', 'bold', 'Color', 'black', ...
     'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
frame = print(f, '-RGBImage', '-r96');

m = 1 - im2double(rgb2gray(frame));
if angleDeg ~= 0
    m = imrotate(m, angleDeg, 'bilinear', 'loose');
end
m = tightCrop(min(max(m, 0), 1));

if ~isempty(sz)
    scale = min([1, sz(1) / size(m, 1), sz(2) / size(m, 2)]);
    if scale < 1
        m = min(max(imresize(m, scale, 'bilinear'), 0), 1);
    end
    canvas = zeros(sz(1), sz(2));
    y0 = floor((sz(1) - size(m, 1)) / 2);
    x0 = floor((sz(2) - size(m, 2)) / 2);
    canvas(y0 + (1:size(m, 1)), x0 + (1:size(m, 2))) = m;
    m = canvas;
end
end

function m = tightCrop(m)
[r, c] = find(m > 0.02);
if isempty(r)
    m = zeros(1, 1);
    return;
end
m = m(min(r):max(r), min(c):max(c));
end
