function [tpl, tplBox, repeatsInfo] = mineRepeats(T, cfg)
% MINEREPEATS Discover repeated watermark structures (e.g., logo instances).
%
% Binarizes evidence map, merges nearby components, crops candidate patches,
% computes pairwise normalized cross-correlation, and extracts the most
% self-consistent repeated watermark template.
%
% Inputs:
%   T           - 2D double evidence map in [0, 1]
%   cfg         - Configuration struct (cfg.gen, cfg.cls)
%
% Outputs:
%   tpl         - 2D double cropped template patch from T (empty if none found)
%   tplBox      - 1x4 [x, y, w, h] bounding box of best template
%   repeatsInfo - Struct with detected candidate boxes, repeat count, correlation scores

[H, W] = size(T);
tpl = [];
tplBox = [];
repeatsInfo = struct('count', 0, 'boxes', [], 'partnerCounts', []);

% 1. Threshold evidence map
nonzeroT = T(T > 0.05);
if isempty(nonzeroT)
    return;
end
lvl = graythresh(nonzeroT);
bw = T > max(0.1, lvl * 0.7);

% 2. Morphological closing to merge adjacent glyphs/elements in logos
seClose = strel('disk', 6);
bwClosed = imclose(bw, seClose);

% 3. Extract connected components within area bounds
cc = bwconncomp(bwClosed, 8);
props = regionprops(cc, 'BoundingBox', 'Area', 'Centroid');

validBoxes = [];
validPatches = {};
minArea = cfg.gen.minArea;
maxArea = cfg.gen.maxAreaFrac * (H * W);

for k = 1:numel(props)
    bb = props(k).BoundingBox;
    a = props(k).Area;
    if a >= minArea && a <= maxArea && bb(3) >= 15 && bb(4) >= 15 && bb(3) < W*0.8 && bb(4) < H*0.8
        % Ensure integer bounds inside image
        x1 = max(1, floor(bb(1)));
        y1 = max(1, floor(bb(2)));
        x2 = min(W, ceil(bb(1) + bb(3) - 1));
        y2 = min(H, ceil(bb(2) + bb(4) - 1));
        
        patch = T(y1:y2, x1:x2);
        validBoxes = [validBoxes; [x1, y1, x2 - x1 + 1, y2 - y1 + 1]]; %#ok<AGROW>
        validPatches{end+1} = patch; %#ok<AGROW>
    end
end

numCands = size(validBoxes, 1);
if numCands < cfg.cls.minRepeats
    return;
end

% 4. Pairwise normalized cross-correlation
% Resize patches to a canonical size for correlation comparison
targetSz = [48, 64];
normPatches = zeros(targetSz(1), targetSz(2), numCands);
for k = 1:numCands
    p = validPatches{k};
    pRes = imresize(p, targetSz);
    pRes = pRes - mean(pRes(:));
    pNorm = norm(pRes(:));
    if pNorm > eps
        pRes = pRes / pNorm;
    end
    normPatches(:, :, k) = pRes;
end

partnerCount = zeros(numCands, 1);
corrThresh = 0.55;

for i = 1:numCands
    for j = (i+1):numCands
        pi = normPatches(:, :, i);
        pj = normPatches(:, :, j);
        score = sum(pi(:) .* pj(:));
        if score > corrThresh
            partnerCount(i) = partnerCount(i) + 1;
            partnerCount(j) = partnerCount(j) + 1;
        end
    end
end

[maxPartners, bestIdx] = max(partnerCount);
repeatsInfo.partnerCounts = partnerCount;
repeatsInfo.boxes = validBoxes;

% Check if at least minRepeats components match
if maxPartners >= (cfg.cls.minRepeats - 1)
    tplBox = validBoxes(bestIdx, :);
    tpl = validPatches{bestIdx};
    
    % Retain candidate boxes that matched the template
    matchIdx = find(partnerCount >= 1);
    repeatsInfo.count = numel(matchIdx);
    repeatsInfo.matchedBoxes = validBoxes(matchIdx, :);
else
    repeatsInfo.count = 0;
end

end
