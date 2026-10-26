function m = renderTextMask(str, sz, angleDeg, fontSize, fontName)
% RENDERTEXTMASK Render antialiased binary text mask m in [0, 1] for synthetic watermarking.
%
% Inputs:
%   str      - Text string to render
%   sz       - [height, width] of output mask
%   angleDeg - (Optional) rotation angle in degrees (default 0)
%   fontSize - (Optional) font size in points (default 24)
%   fontName - (Optional) font family name (default 'Helvetica')
%
% Output:
%   m        - 2D double array in [0, 1] of size sz with soft antialiased coverage

if nargin < 3, angleDeg = 0; end
if nargin < 4 || isempty(fontSize), fontSize = 24; end
if nargin < 5 || isempty(fontName), fontName = 'Helvetica'; end

H = sz(1);
W = sz(2);

% Method A: insertText if available
if exist('insertText', 'file') || exist('insertText', 'builtin')
    try
        canvas = zeros(H, W, 3, 'uint8');
        textPos = [floor(W / 2), floor(H / 2)];
        rgb = insertText(canvas, textPos, str, ...
            'FontSize', fontSize, ...
            'Font', fontName, ...
            'TextColor', 'white', ...
            'BoxOpacity', 0, ...
            'AnchorPoint', 'Center');
        grayImg = rgb2gray(im2double(rgb));
        if angleDeg ~= 0
            grayImg = imrotate(grayImg, angleDeg, 'bilinear', 'crop');
        end
        m = min(max(grayImg, 0), 1);
        return;
    catch
        % Fall through to headless figure rendering
    end
end

% Method B: Headless figure rendering via exportgraphics or print
try
    f = figure('Visible', 'off', 'Color', 'white', 'Position', [100 100 W H], 'MenuBar', 'none', 'ToolBar', 'none');
    ax = axes('Parent', f, 'Position', [0 0 1 1], 'Visible', 'off', 'Color', 'white');
    xlim(ax, [0 W]);
    ylim(ax, [0 H]);
    text(ax, W/2, H/2, str, ...
        'FontSize', fontSize, ...
        'FontName', fontName, ...
        'FontWeight', 'bold', ...
        'Color', 'black', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'Rotation', angleDeg);
    
    tmpFile = fullfile(tempdir, sprintf('text_render_%d.png', randi(1000000)));
    if exist('exportgraphics', 'file') || exist('exportgraphics', 'builtin')
        exportgraphics(ax, tmpFile, 'Resolution', 72);
    else
        print(f, tmpFile, '-dpng', '-r72');
    end
    close(f);
    
    if exist(tmpFile, 'file')
        rendered = imread(tmpFile);
        delete(tmpFile);
        if size(rendered, 3) == 3
            grayRender = rgb2gray(im2double(rendered));
        else
            grayRender = im2double(rendered);
        end
        % Text is black on white canvas -> invert so text = 1
        rawM = 1.0 - grayRender;
        if size(rawM, 1) ~= H || size(rawM, 2) ~= W
            rawM = imresize(rawM, [H, W], 'bilinear');
        end
        m = min(max(rawM, 0), 1);
        return;
    end
catch
    % Fall through to procedural raster font if headless figure fails
end

% Method C: Fallback geometric stroke rendering for headless environments
m = zeros(H, W);
cx = W / 2;
cy = H / 2;
rad = angleDeg * pi / 180;
u = [cos(rad), sin(rad)];
v = [-sin(rad), cos(rad)];

% Procedural stroke grid based on string length
numChars = numel(str);
charW = max(8, fontSize * 0.6);
charH = max(12, fontSize * 0.9);
totalLen = numChars * charW;

[X, Y] = meshgrid(1:W, 1:H);
relX = X - cx;
relY = Y - cy;

projU = relX * u(1) + relY * u(2);
projV = relX * v(1) + relY * v(2);

inText = abs(projU) <= (totalLen / 2) & abs(projV) <= (charH / 2);
m(inText) = 1.0;
m = imgaussfilt(m, 0.8);
m = min(max(m, 0), 1);

end
