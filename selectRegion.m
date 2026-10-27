function maskFile = selectRegion(imagePath)
% SELECTREGION Mark where the watermark is by drawing on the image.
%
% Opens the image; draw one or more regions around the watermark(s), then
% answer the prompt. The union of the regions is saved to
% data/real/masks_user/<name>.png and used automatically by main as the
% search region for that image (no coordinates to type).
%
%   selectRegion('images/img-9.png')      % then:  main('images','only','img-9')
%
% Controls: pick a tool in the dialog (polygon / freehand circle / ellipse),
% draw it, double-click (polygon) or release (freehand) to finish.
%
% Input:  imagePath - path to the image
% Output: maskFile  - path of the saved mask PNG

root = fileparts(mfilename('fullpath'));
I = imread(imagePath);
[~, name] = fileparts(imagePath);
outDir = fullfile(root, 'data', 'real', 'masks_user');
if ~exist(outDir, 'dir'), mkdir(outDir); end
maskFile = fullfile(outDir, [name '.png']);

f = figure('Name', ['Mark the watermark: ' name], 'NumberTitle', 'off');
imshow(I);
ax = gca;
mask = false(size(I, 1), size(I, 2));
if exist(maskFile, 'file')   % continue from an existing selection
    old = imread(maskFile) > 0;
    if isequal(size(old), size(mask)), mask = old; end
end

while true
    shown = labeloverlay(I, mask, 'Colormap', [1 0 0], 'Transparency', 0.6);
    imshow(shown, 'Parent', ax);
    tool = questdlg('Choose a drawing tool (or finish):', 'selectRegion', ...
        'Polygon', 'Freehand circle', 'Done', 'Polygon');
    switch tool
        case 'Polygon'
            roi = drawpolygon(ax, 'Color', 'y');
        case 'Freehand circle'
            roi = drawfreehand(ax, 'Color', 'y');
        otherwise
            break;
    end
    if isempty(roi) || ~isvalid(roi) || isempty(roi.Position)
        break;
    end
    mask = mask | createMask(roi);
    delete(roi);
end
close(f);

if ~any(mask(:))
    warning('selectRegion:empty', 'Nothing selected; no mask saved.');
    maskFile = '';
    return;
end
imwrite(mask, maskFile);
fprintf('Saved %s (%.1f%% of the image)\n', maskFile, 100 * mean(mask(:)));
end
