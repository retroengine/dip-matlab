function D = detectGeneric(P, cfg, info, imgName)
% DETECTGENERIC Generic detector for single/localized watermarks (e.g., logos, text bands).
%
% Integrates multi-scale top-hat evidence, horizontal line grouping, aspect ratio /
% solidity morphology filtering, optional MSER cues, and optional search region hints.
%
% Inputs:
%   P       - Preprocessed struct from preprocess.m
%   cfg     - Configuration struct (cfg.gen, cfg.mask)
%   info    - (Optional) classification info struct
%   imgName - (Optional) image name to query hints.json for search_box
%
% Output:
%   D       - Detection struct with maskTight, maskDil, m, type, info

if nargin < 3 || isempty(info)
    info = struct();
end
if nargin < 4
    imgName = '';
end

[H, W] = size(P.gray);
[T, E] = evidenceMap(P, cfg);

% 1. Check for search box hint in hints.json
searchMask = P.valid;
usedHint = false;
hintsFile = fullfile('data', 'real', 'hints.json');

if ~isempty(imgName) && exist(hintsFile, 'file')
    try
        hintsText = fileread(hintsFile);
        hints = jsondecode(hintsText);
        [~, baseName, ~] = fileparts(imgName);
        if isfield(hints, baseName) && isfield(hints.(baseName), 'search_box')
            sb = hints.(baseName).search_box; % [x, y, w, h]
            x1 = max(1, round(sb(1)));
            y1 = max(1, round(sb(2)));
            x2 = min(W, round(sb(1) + sb(3) - 1));
            y2 = min(H, round(sb(2) + sb(4) - 1));
            
            searchMask = false(H, W);
            searchMask(y1:y2, x1:x2) = true;
            searchMask = searchMask & P.valid;
            usedHint = true;
        end
    catch ME
        warning('detectGeneric:hintsError', 'Failed to read hints: %s', ME.message);
    end
end

% 2. Threshold evidence map
Tsearch = T;
Tsearch(~searchMask) = 0;

nonzeroT = Tsearch(Tsearch > 0.05);
if ~isempty(nonzeroT)
    threshVal = max(0.12, 0.65 * graythresh(nonzeroT));
else
    threshVal = 0.2;
end
bw = (Tsearch >= threshVal) & searchMask;

% 3. Text line grouping (horizontal structuring element)
seLine = strel('line', 18, 0);
bwLine = imclose(bw, seLine);

% 4. Connected component analysis and ranking
cc = bwconncomp(bwLine, 8);
props = regionprops(cc, 'Area', 'BoundingBox', 'Solidity', 'PixelIdxList');

minArea = cfg.gen.minArea;
maxArea = cfg.gen.maxAreaFrac * (H * W);
minSolidity = cfg.gen.minSolidity;

keepIdx = [];
scores = [];

Ed = imgaussfilt(double(E), 4);
if max(Ed(:)) > 0
    Ed = Ed ./ max(Ed(:));
end

for k = 1:numel(props)
    a = props(k).Area;
    sol = props(k).Solidity;
    bb = props(k).BoundingBox;
    aspectRatio = bb(3) / max(bb(4), 1);
    
    if a >= minArea && a <= maxArea && sol >= minSolidity
        pix = props(k).PixelIdxList;
        meanT = mean(T(pix));
        meanEd = mean(Ed(pix));
        
        % Score by evidence, edge density, and text-like aspect ratio
        score = (meanT * 0.6 + meanEd * 0.4) * (1 + 0.2 * min(aspectRatio, 5));
        
        keepIdx = [keepIdx; k]; %#ok<AGROW>
        scores = [scores; score]; %#ok<AGROW>
    end
end

rawMask = false(H, W);
if ~isempty(scores)
    % Keep components above top score threshold
    [sortedScores, sOrder] = sort(scores, 'descend');
    topScore = sortedScores(1);
    accepted = keepIdx(sOrder(sortedScores >= 0.4 * topScore));
    
    for k = 1:numel(accepted)
        idx = accepted(k);
        % Fill with the original fine-grained evidence within this component
        bb = props(idx).BoundingBox;
        x1 = max(1, floor(bb(1)));
        y1 = max(1, floor(bb(2)));
        x2 = min(W, ceil(bb(1) + bb(3) - 1));
        y2 = min(H, ceil(bb(2) + bb(4) - 1));
        
        patchT = T(y1:y2, x1:x2);
        patchBW = (patchT > (0.5 * threshVal));
        rawMask(y1:y2, x1:x2) = rawMask(y1:y2, x1:x2) | patchBW;
    end
else
    % Fallback: direct threshold on evidence within searchMask
    rawMask = bw;
end

% 5. Optional MSER feature reinforcement
if isfield(cfg, 'caps') && isfield(cfg.caps, 'hasMSER') && cfg.caps.hasMSER
    try
        mser = detectMSERFeatures(P.gray, 'ROI', [1, 1, W, H]);
        % Reinforce regions overlapping MSER pixels
        mserMask = false(H, W);
        for p = 1:mser.Count
            pt = round(mser.Location(p, :));
            if pt(1) >= 1 && pt(1) <= W && pt(2) >= 1 && pt(2) <= H
                mserMask(pt(2), pt(1)) = true;
            end
        end
        mserDil = imdilate(mserMask, strel('disk', 3));
        rawMask = rawMask | (mserDil & (T > threshVal) & searchMask);
    catch
        % Continue without MSER if execution encounters issue
    end
end

rawMask = rawMask & searchMask;

info.detector = 'generic';
info.usedHint = usedHint;
D = refineMask(rawMask, P, cfg, 'single', info);

end
