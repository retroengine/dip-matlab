function D = detectTemplate(P, cfg, info)
% DETECTTEMPLATE Multi-scale template matching to detect repeated logos/watermarks.
%
% Performs normalized cross-correlation across multiple scales using a mined
% or provided template, non-maximum suppression, and binary template pasting.
%
% Inputs:
%   P    - Preprocessed struct from preprocess.m
%   cfg  - Configuration struct (cfg.tpl, cfg.per)
%   info - (Optional) classification info struct with mined template
%
% Output:
%   D    - Detection struct with maskTight, maskDil, m, type, info

if nargin < 3 || isempty(info) || ~isfield(info, 'tpl') || isempty(info.tpl)
    [T, ~] = evidenceMap(P, cfg);
    [tpl, tplBox, repeatsInfo] = mineRepeats(T, cfg);
    info.tpl = tpl;
    info.tplBox = tplBox;
    info.repeatsInfo = repeatsInfo;
else
    [T, ~] = evidenceMap(P, cfg);
    tpl = info.tpl;
end

[H, W] = size(T);

if isempty(tpl)
    % Fall back to generic detector if no template could be mined
    D = detectGeneric(P, cfg, info);
    return;
end

% Binarize the template itself to get canonical glyph silhouette
tplNonzero = tpl(tpl > 0.05);
if ~isempty(tplNonzero)
    tplBin = tpl > (0.6 * graythresh(tplNonzero) * max(tpl(:)));
else
    tplBin = tpl > 0.2;
end
[th, tw] = size(tpl);

% Multi-scale cross-correlation search
scales = cfg.tpl.scales;
allPeaks = []; % [score, scale, centerX, centerY, w, h]

for s = scales
    if s == 1.0
        tplS = tpl;
        binS = tplBin;
    else
        tplS = imresize(tpl, s);
        binS = imresize(tplBin, s, 'nearest');
    end
    [curH, curW] = size(tplS);
    if curH >= H || curW >= W || curH < 10 || curW < 10
        continue;
    end
    
    % Normalized cross-correlation
    ncc = normxcorr2(tplS, T);
    
    % Crop out padding introduced by normxcorr2 (center aligned)
    padY = floor(curH / 2);
    padX = floor(curW / 2);
    nccCrop = ncc(curH:H+curH-1, curW:W+curW-1);
    
    % Find local maxima above threshold
    if exist('imregionalmax', 'file') || exist('imregionalmax', 'builtin')
        regMax = imregionalmax(nccCrop);
    else
        dil = imdilate(nccCrop, strel('disk', 3));
        regMax = (nccCrop == dil);
    end
    
    peaks = regMax & (nccCrop >= cfg.tpl.nccThresh) & P.valid;
    [pY, pX] = find(peaks);
    
    for i = 1:numel(pY)
        score = nccCrop(pY(i), pX(i));
        allPeaks = [allPeaks; [score, s, pX(i), pY(i), curW, curH]]; %#ok<AGROW>
    end
end

% Non-maximum suppression across all detections and scales
detectedBoxes = [];
if ~isempty(allPeaks)
    % Sort by correlation score descending
    [~, sortOrder] = sort(allPeaks(:, 1), 'descend');
    sortedPeaks = allPeaks(sortOrder, :);
    
    nmsDist = cfg.tpl.nmsFrac * max(th, tw);
    keep = true(size(sortedPeaks, 1), 1);
    
    for i = 1:size(sortedPeaks, 1)
        if ~keep(i), continue; end
        xi = sortedPeaks(i, 3);
        yi = sortedPeaks(i, 4);
        
        for j = (i+1):size(sortedPeaks, 1)
            if ~keep(j), continue; end
            xj = sortedPeaks(j, 3);
            yj = sortedPeaks(j, 4);
            if hypot(xi - xj, yi - yj) < nmsDist
                keep(j) = false;
            end
        end
    end
    
    keptPeaks = sortedPeaks(keep, :);
    for k = 1:size(keptPeaks, 1)
        wBox = keptPeaks(k, 5);
        hBox = keptPeaks(k, 6);
        xBox = keptPeaks(k, 3) - floor(wBox / 2);
        yBox = keptPeaks(k, 4) - floor(hBox / 2);
        detectedBoxes = [detectedBoxes; [xBox, yBox, wBox, hBox, keptPeaks(k, 1), keptPeaks(k, 2)]]; %#ok<AGROW>
    end
end

% Construct pasted mask from detected instances
pastedMask = false(H, W);
for k = 1:size(detectedBoxes, 1)
    bx = detectedBoxes(k, 1);
    by = detectedBoxes(k, 2);
    bw = detectedBoxes(k, 3);
    bh = detectedBoxes(k, 4);
    s  = detectedBoxes(k, 6);
    
    if s == 1.0
        binS = tplBin;
    else
        binS = imresize(tplBin, [bh, bw], 'nearest');
    end
    
    % Paste within image bounds
    for r = 1:bh
        for c = 1:bw
            imgY = by + r - 1;
            imgX = bx + c - 1;
            if imgY >= 1 && imgY <= H && imgX >= 1 && imgX <= W
                if binS(r, c)
                    pastedMask(imgY, imgX) = true;
                end
            end
        end
    end
end

% Local evidence gate (same as periodic)
Tvalid = T(P.valid & T > 0);
if ~isempty(Tvalid)
    lvlT = graythresh(Tvalid);
    gateSeed = T > (cfg.per.localGate * lvlT * max(T(:)));
else
    gateSeed = T > 0.1;
end
gate = imdilate(gateSeed, strel('disk', 2));

rawMask = pastedMask & gate & P.valid;

% If pasted mask missed details, incorporate evidence within detected bounding boxes
for k = 1:size(detectedBoxes, 1)
    bx = max(1, detectedBoxes(k, 1));
    by = max(1, detectedBoxes(k, 2));
    bw = detectedBoxes(k, 3);
    bh = detectedBoxes(k, 4);
    x2 = min(W, bx + bw - 1);
    y2 = min(H, by + bh - 1);
    
    boxT = T(by:y2, bx:x2);
    rawMask(by:y2, bx:x2) = rawMask(by:y2, bx:x2) | (boxT > 0.25);
end

rawMask = rawMask & P.valid;

info.detector = 'template';
info.instanceCount = size(detectedBoxes, 1);
info.detectedBoxes = detectedBoxes;

D = refineMask(rawMask, P, cfg, 'sparse', info);

end
