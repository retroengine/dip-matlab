function D = detectPeriodic(P, cfg, info)
% DETECTPERIODIC Detect periodic tiled watermark via tile-folding and consensus filtering.
%
% Reconstructs consensus watermark pattern from 2D periodic tile repetitions,
% gating by local evidence to suppress background structures.
%
% Inputs:
%   P    - Preprocessed struct from preprocess.m
%   cfg  - Configuration struct
%   info - (Optional) classification info struct with lattice vectors
%
% Output:
%   D    - Detection struct with maskTight, maskDil, m, type, info

if nargin < 3 || isempty(info) || ~isfield(info, 'a1') || isempty(info.a1)
    [~, info] = classifyWatermark(P, cfg);
end

[T, ~] = evidenceMap(P, cfg);

% 1. Retrieve or re-estimate lattice vectors
if isfield(info, 'a1') && ~isempty(info.a1) && isfield(info, 'a2') && ~isempty(info.a2)
    a1 = info.a1;
    a2 = info.a2;
else
    if isfield(info, 'peaks') && size(info.peaks, 1) >= 2
        [a1, a2] = findLattice(info.peaks, T, P.valid, cfg);
    else
        error('detectPeriodic:noLattice', 'Cannot detect periodic watermark without valid lattice.');
    end
end

% 2. Fold tiles along lattice to get consensus evidence
[~, evid, ~] = foldTiles(T, P.valid, a1, a2);

% 3. Consensus thresholding
evidValid = evid(P.valid & evid > 0);
if ~isempty(evidValid)
    lvlEvid = graythresh(evidValid);
    tight0 = evid > (lvlEvid * max(evid(:)));
else
    tight0 = false(size(evid));
end

% 4. Local evidence agreement gate
Tvalid = T(P.valid & T > 0);
if ~isempty(Tvalid)
    lvlT = graythresh(Tvalid);
    gateSeed = T > (cfg.per.localGate * lvlT * max(T(:)));
else
    gateSeed = T > 0.1;
end
gate = imdilate(gateSeed, strel('disk', 2));

% 5. Intersect consensus with local gate and valid ROI
rawMask = tight0 & gate & P.valid;

% 6. Refine mask
info.detector = 'periodic';
info.a1 = a1;
info.a2 = a2;
D = refineMask(rawMask, P, cfg, 'periodic', info);

end
