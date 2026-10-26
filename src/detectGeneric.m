function D = detectGeneric(P, cfg, info, imgName)
% DETECTGENERIC Detect a single / localized watermark (logo, text band).
%
% 1. Evidence map T; search area = ROI, optionally restricted by the
%    'search_box' hint in data/real/hints.json.
% 2. Otsu threshold of T inside the search area.
% 3. Group glyphs: closing with a horizontal line (length relative to image
%    height) and a small disk, so a word / logo becomes one blob.
% 4. Score blobs by mean evidence x edge density x text-likeness; reject blobs
%    outside the area bounds. Keep the best blob and any blob scoring at
%    least cfg.gen.keepFrac of it that lies within cfg.gen.clusterDist of it.
% 5. Mask = above-threshold pixels inside the kept blobs.
%
% Inputs:
%   P       - Preprocessed struct from preprocess.m
%   cfg     - Configuration struct (cfg.gen)
%   info    - (Optional) classification info (may carry T)
%   imgName - (Optional) image base name for the hints lookup
%
% Output:
%   D       - Detection struct (maskTight, maskDil, m, type, info)

if nargin < 3 || isempty(info), info = struct(); end
if nargin < 4, imgName = ''; end

[H, W] = size(P.gray);
[T, E] = evidenceMap(P, cfg);

% 1. Search area
searchMask = P.valid;
info.usedHint = false;
hint = loadHint(cfg, imgName);
if isfield(hint, 'search_box')
    sb = round(hint.search_box);
    box = false(H, W);
    box(max(1, sb(2)):min(H, sb(2) + sb(4) - 1), max(1, sb(1)):min(W, sb(1) + sb(3) - 1)) = true;
    searchMask = searchMask & box;
    info.usedHint = true;
    fprintf('  [generic] search_box hint [%d %d %d %d]\n', sb);
end

% Location prior (no hint): single marks sit in a corner or a bottom band
if ~info.usedHint
    ym = round(cfg.gen.priorCornerFrac * H); xm = round(cfg.gen.priorCornerFrac * W);
    prior = false(H, W);
    prior([1:ym, H-ym+1:H], [1:xm, W-xm+1:W]) = true;
    prior(round((1 - cfg.gen.priorBandFrac) * H):H, :) = true;
    searchMask = searchMask & prior;
end

% 2. Threshold
lvl = graythresh(T(searchMask));
bw = T > lvl & searchMask;

% 3. Glyph grouping
lineLen = max(3, round(cfg.gen.groupLenFrac * H));
grouped = imclose(bw, strel('line', lineLen, 0));
grouped = imclose(grouped, strel('disk', cfg.gen.groupDiskR));

% 4. Blob scoring
Ed = imgaussfilt(double(E), cfg.gen.edgeSigma);
Ed = Ed / max(max(Ed(:)), eps);
cc = bwconncomp(grouped, 8);
props = regionprops(cc, 'Area', 'BoundingBox', 'Solidity', 'Centroid', 'PixelIdxList');
maxArea = cfg.gen.maxAreaFrac * nnz(searchMask);
scores = zeros(numel(props), 1);
for k = 1:numel(props)
    if props(k).Area < cfg.gen.minArea || props(k).Area > maxArea || ...
            props(k).Solidity < cfg.gen.minSolidity
        continue;
    end
    pix = props(k).PixelIdxList;
    fill = nnz(bw(pix)) / numel(pix);           % strokes inside the blob
    bb = props(k).BoundingBox;
    aspect = min(bb(3) / max(bb(4), 1), cfg.gen.maxAspectBonus);
    scores(k) = mean(T(pix)) * mean(Ed(pix)) * (1 + aspect / cfg.gen.maxAspectBonus) ...
                * min(1, fill / cfg.gen.minFill) * sqrt(props(k).Area);
end

rawMask = false(H, W);
if any(scores > 0)
    [top, ti] = max(scores);
    c0 = props(ti).Centroid;
    for k = find(scores >= cfg.gen.keepFrac * top)'
        if hypot(props(k).Centroid(1) - c0(1), props(k).Centroid(2) - c0(2)) <= cfg.gen.clusterDist * max(H, W)
            rawMask(props(k).PixelIdxList) = true;
        end
    end
    rawMask = rawMask & bw;
    fprintf('  [generic] kept %d px from %d candidate blobs\n', nnz(rawMask), nnz(scores > 0));
end

info.detector = 'generic';
info.threshold = lvl;
D = refineMask(rawMask, P, cfg, 'single', info);
end
