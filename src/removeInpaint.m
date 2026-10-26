function J = removeInpaint(I, maskDil, method, cfg)
% REMOVEINPAINT Watermark removal by inpainting the dilated mask.
%
% Methods:
%   'coherent'   - Method 1: coherence-transport inpainting (inpaintCoherent)
%   'exemplar'   - Method 2: exemplar/patch inpainting (inpaintExemplar), run
%                  per group of nearby holes on a cropped region for speed
%   'regionfill' - Harmonic (Laplace) fill per colour channel
%
% Inputs:
%   I       - RGB double image in [0, 1]
%   maskDil - 2-D logical mask of pixels to replace
%   method  - 'coherent' | 'exemplar' | 'regionfill'
%   cfg     - Configuration struct (cfg.inp)
%
% Output:
%   J       - Inpainted RGB double image in [0, 1]

if nargin < 3 || isempty(method)
    method = 'coherent';
end

maskDil = logical(maskDil);
I = min(max(im2double(I), 0), 1);
if ~any(maskDil(:))
    J = I;
    return;
end

switch lower(method)
    case 'coherent'
        J = inpaintCoherent(I, maskDil, ...
            'SmoothingFactor', cfg.inp.coherentSmooth, ...
            'Radius', cfg.inp.coherentRadius);

    case 'exemplar'
        J = exemplarPerRegion(I, maskDil, cfg);

    case 'regionfill'
        J = I;
        for c = 1:size(I, 3)
            J(:, :, c) = regionfill(I(:, :, c), maskDil);   % regionfill is 2-D only
        end

    otherwise
        error('removeInpaint:unknownMethod', 'Unknown inpainting method: %s', method);
end

J = min(max(J, 0), 1);
end

function J = exemplarPerRegion(I, mask, cfg)
% inpaintExemplar searches the whole image for every patch, so it is slow on
% large images. Holes closer than one search margin are grouped and each group
% is inpainted on a crop that extends cfg.inp.exemplarSearch px around it.
[H, W, ~] = size(I);
J = I;
pad = cfg.inp.exemplarSearch;
groups = bwconncomp(imdilate(mask, strel('square', 2 * cfg.inp.exemplarPatch(1) + 1)));
for g = 1:groups.NumObjects
    [gr, gc] = ind2sub([H, W], groups.PixelIdxList{g});
    y1 = max(1, min(gr) - pad); y2 = min(H, max(gr) + pad);
    x1 = max(1, min(gc) - pad); x2 = min(W, max(gc) + pad);
    sub = mask(y1:y2, x1:x2);
    J(y1:y2, x1:x2, :) = inpaintExemplar(J(y1:y2, x1:x2, :), sub, ...
        'PatchSize', cfg.inp.exemplarPatch);
end
end
