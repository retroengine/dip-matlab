function compImg = makeComparison(I, overlay, M1, M2, M3, outPath, metaInfo)
% MAKECOMPARISON Create 5-panel side-by-side comparison figure:
%   Original | Mask Overlay | M1 (Coherent) | M2 (Exemplar) | M3 (Alpha Invert)
%
% Inputs:
%   I        - Original watermarked image
%   overlay  - Mask overlay on original image
%   M1       - Result from Method 1 (Coherent inpainting)
%   M2       - Result from Method 2 (Exemplar inpainting)
%   M3       - Result from Method 3 (Alpha inversion)
%   outPath  - Destination PNG file path
%   metaInfo - (Optional) Struct or string with image title / detection info
%
% Output:
%   compImg  - Composed RGB image

if nargin < 7
    metaInfo = '';
end

imgs = {I, overlay, M1, M2, M3};
titles = {'Original', 'Mask Overlay', 'M1: Coherent', 'M2: Exemplar', 'M3: Alpha Invert'};

% Method recommendation banner if provided
subHead = '';
if isstruct(metaInfo)
    if isfield(metaInfo, 'recommended')
        subHead = sprintf('Type: %s | Recommended: %s', metaInfo.type, metaInfo.recommended);
    end
elseif ischar(metaInfo) || isstring(metaInfo)
    subHead = char(metaInfo);
end

hasFig = (exist('tiledlayout', 'file') || exist('tiledlayout', 'builtin')) && ...
         (exist('exportgraphics', 'file') || exist('exportgraphics', 'builtin'));

if hasFig
    try
        f = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1600 360]);
        t = tiledlayout(f, 1, 5, 'TileSpacing', 'compact', 'Padding', 'compact');
        if ~isempty(subHead)
            title(t, subHead, 'FontSize', 12, 'FontWeight', 'bold');
        end
        
        for k = 1:5
            nexttile(t);
            imshow(imgs{k});
            title(titles{k}, 'FontSize', 10, 'FontWeight', 'bold');
        end
        
        [outDir, ~, ~] = fileparts(outPath);
        if ~isempty(outDir) && ~exist(outDir, 'dir')
            mkdir(outDir);
        end
        
        exportgraphics(f, outPath, 'Resolution', 150);
        close(f);
        compImg = imread(outPath);
        return;
    catch
        % Fall back to manual montage below if figure rendering fails
    end
end

% Manual canvas montage fallback (pure array operations, works headless without display)
[H, W, ~] = size(I);
bannerH = 30;
pad = 8;
totalW = 5 * W + 6 * pad;
totalH = H + bannerH + 2 * pad;

canvas = ones(totalH, totalW, 3); % White background

for k = 1:5
    curImg = imgs{k};
    if size(curImg, 1) ~= H || size(curImg, 2) ~= W
        curImg = imresize(curImg, [H, W]);
    end
    xStart = pad + (k - 1) * (W + pad);
    yStart = bannerH + pad;
    canvas(yStart:yStart + H - 1, xStart:xStart + W - 1, :) = curImg;
end

compImg = canvas;

[outDir, ~, ~] = fileparts(outPath);
if ~isempty(outDir) && ~exist(outDir, 'dir')
    mkdir(outDir);
end

imwrite(min(max(compImg, 0), 1), outPath);

end
