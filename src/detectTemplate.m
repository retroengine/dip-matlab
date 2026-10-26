function D = detectTemplate(P, cfg, info)
% DETECTTEMPLATE Detect repeated logos by multi-scale template matching.
%
% The template (mined by mineRepeats, or passed in info.tpl) is matched
% against the evidence map T with normxcorr2 at every scale in
% cfg.tpl.scales. Peaks above cfg.tpl.nccThresh are non-max suppressed
% (radius cfg.tpl.nmsFrac * template size), the template's binary glyph mask
% is pasted at each instance, and the result is gated by local evidence.
%
% Inputs:
%   P    - Preprocessed struct from preprocess.m
%   cfg  - Configuration struct (cfg.tpl, cfg.per)
%   info - (Optional) struct with tpl / tplBox (and repeatsInfo.tplBin)
%
% Output:
%   D    - Detection struct; D.info.instanceCount, D.info.detectedBoxes

if nargin < 3 || isempty(info)
    info = struct();
end
if isfield(info, 'T')
    T = info.T;
else
    T = evidenceMap(P, cfg);
end
[H, W] = size(T);

if ~isfield(info, 'tpl') || isempty(info.tpl)
    [tpl, tplBox, rep] = mineRepeats(T, P.valid, cfg);
    info.tpl = tpl;
    info.tplBox = tplBox;
    info.repeatsInfo = rep;
end
tpl = info.tpl;
if isempty(tpl)
    D = detectGeneric(P, cfg, info);
    return;
end

lvl = graythresh(T(P.valid));
if isfield(info, 'repeatsInfo') && ~isempty(info.repeatsInfo.tplBin)
    tplBin = info.repeatsInfo.tplBin;
else
    tplBin = tpl > lvl;
end

% Multi-scale normalised cross-correlation; peaks as [score s x y w h]
% where (x, y) is the instance's top-left corner.
cand = zeros(0, 6);
for s = cfg.tpl.scales
    tplS = imresize(tpl, s);
    [th, tw] = size(tplS);
    if th >= H || tw >= W || min(th, tw) < cfg.tpl.minSide || std(tplS(:)) < eps
        continue;
    end
    ncc = normxcorr2(tplS, T);
    ncc = ncc(th:H, tw:W);            % entry (y, x) = template top-left at (y, x)
    pk = imregionalmax(ncc) & ncc >= cfg.tpl.nccThresh;
    [py, px] = find(pk);
    cand = [cand; [ncc(pk), repmat(s, numel(py), 1), px, py, ...
                   repmat([tw th], numel(py), 1)]]; %#ok<AGROW>
end

% Non-maximum suppression across scales on instance centres
boxes = zeros(0, 6);
if ~isempty(cand)
    cand = sortrows(cand, -1);
    ctr = cand(:, 3:4) + cand(:, 5:6) / 2;
    keep = true(size(cand, 1), 1);
    rad = cfg.tpl.nmsFrac * max(size(tpl));
    for i = 1:size(cand, 1)
        if ~keep(i), continue; end
        d = hypot(ctr(:, 1) - ctr(i, 1), ctr(:, 2) - ctr(i, 2));
        keep((1:end)' > i & d < rad) = false;
    end
    boxes = cand(keep, [3 4 5 6 1 2]);    % [x y w h score scale]
end

% Paste the binary template at every instance, plus in-box evidence
pasted = false(H, W);
inBox = false(H, W);
for k = 1:size(boxes, 1)
    x = boxes(k, 1); y = boxes(k, 2); w = boxes(k, 3); h = boxes(k, 4);
    b = imresize(tplBin, [h w], 'nearest');
    pasted(y:y+h-1, x:x+w-1) = pasted(y:y+h-1, x:x+w-1) | b;
    inBox(y:y+h-1, x:x+w-1) = true;
end
gate = imdilate(T > cfg.per.localGate * lvl, strel('disk', 2));
rawMask = ((pasted & gate) | (inBox & T > lvl)) & P.valid;

info.detector = 'template';
info.instanceCount = size(boxes, 1);
info.detectedBoxes = boxes;
fprintf('  [template] %d instances\n', info.instanceCount);
D = refineMask(rawMask, P, cfg, 'sparse', info);
end
