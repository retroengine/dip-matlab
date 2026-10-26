function [tpl, tplBox, repeatsInfo] = mineRepeats(T, valid, cfg)
% MINEREPEATS Find repeated structures (e.g. logo instances) in the evidence map.
%
% Thresholds T (Otsu inside the ROI), closes with a disk so the parts of one
% logo merge, and keeps components within the area / size bounds. Every pair
% of similar-sized candidates is compared by the peak of normxcorr2 between
% the (resized) crops, which tolerates small misalignment. A candidate with
% >= cfg.cls.minRepeats-1 partners above cfg.tpl.pairCorr is a repeat; the
% best-supported one becomes the template.
%
% Inputs:
%   T     - 2-D evidence map in [0, 1]
%   valid - 2-D logical ROI
%   cfg   - Configuration struct (cfg.gen, cfg.cls, cfg.tpl)
%
% Outputs:
%   tpl         - Template crop of T (empty if no repeats)
%   tplBin      - (in repeatsInfo.tplBin) binary glyph mask of the template
%   tplBox      - [x y w h] of the template in the image
%   repeatsInfo - count, boxes, partner counts, matched boxes

[H, W] = size(T);
tpl = [];
tplBox = [];
repeatsInfo = struct('count', 0, 'boxes', zeros(0, 4), 'partnerCounts', [], ...
                     'matchedBoxes', zeros(0, 4), 'tplBin', []);

vals = T(valid);
if isempty(vals) || max(vals) <= 0
    return;
end
lvl = graythresh(vals);
bw = T > lvl & valid;
bwClosed = imclose(bw, strel('disk', cfg.tpl.mergeR));

cc = bwconncomp(bwClosed, 8);
props = regionprops(cc, 'BoundingBox', 'Area');
boxes = zeros(0, 4);
for k = 1:numel(props)
    bb = props(k).BoundingBox;
    if props(k).Area >= cfg.gen.minArea * 4 && props(k).Area <= cfg.gen.maxAreaFrac * H * W && ...
            min(bb(3:4)) >= cfg.tpl.minSide && bb(3) < 0.5 * W && bb(4) < 0.5 * H
        x1 = ceil(bb(1)); y1 = ceil(bb(2));
        boxes(end+1, :) = [x1, y1, bb(3), bb(4)]; %#ok<AGROW>
    end
end
repeatsInfo.boxes = boxes;
n = size(boxes, 1);
if n < cfg.cls.minRepeats
    return;
end

crops = cell(n, 1);
for k = 1:n
    crops{k} = T(boxes(k, 2):boxes(k, 2) + boxes(k, 4) - 1, boxes(k, 1):boxes(k, 1) + boxes(k, 3) - 1);
end

partners = zeros(n, 1);
for i = 1:n
    for j = i+1:n
        ri = boxes(i, 3:4) ./ boxes(j, 3:4);
        if any(ri < 1 / cfg.tpl.sizeRatio | ri > cfg.tpl.sizeRatio)
            continue;
        end
        % Shrink crop i by 10% per side and slide it over (resized) crop j
        a = crops{i};
        mi = max(1, round(0.1 * size(a)));
        a = a(mi(1):end - mi(1) + 1, mi(2):end - mi(2) + 1);
        b = imresize(crops{j}, size(crops{i}));
        if std(a(:)) < eps || std(b(:)) < eps
            continue;
        end
        s = max(max(normxcorr2(a, b)));
        if s >= cfg.tpl.pairCorr
            partners(i) = partners(i) + 1;
            partners(j) = partners(j) + 1;
        end
    end
end
repeatsInfo.partnerCounts = partners;

[best, bi] = max(partners);
if best < cfg.cls.minRepeats - 1
    return;
end
tplBox = boxes(bi, :);
tpl = crops{bi};
repeatsInfo.tplBin = tpl > lvl;
matched = partners >= 1;
repeatsInfo.count = nnz(matched);
repeatsInfo.matchedBoxes = boxes(matched, :);
end
