function D = detectPeriodic(P, cfg, info)
% DETECTPERIODIC Detect a tiled watermark by folding the evidence map on its lattice.
%
% The median across tiles (foldTiles) keeps only structure that repeats at
% every lattice position, i.e. the watermark. The consensus map is Otsu-
% thresholded and intersected with a local-evidence gate so that pixels are
% only kept where the image itself also shows watermark evidence.
%
% Inputs:
%   P    - Preprocessed struct from preprocess.m
%   cfg  - Configuration struct
%   info - (Optional) classification info with lattice a1, a2 and T
%
% Output:
%   D    - Detection struct with maskTight, maskDil, m, type, info

if nargin < 3 || isempty(info) || ~isfield(info, 'a1') || isempty(info.a1)
    [~, info] = classifyWatermark(P, cfg);
    if isempty(info.a1)
        error('detectPeriodic:noLattice', 'No periodic lattice found.');
    end
end
if isfield(info, 'T')
    T = info.T;
else
    T = evidenceMap(P, cfg);
end

[~, evid] = foldTiles(T, P.valid, info.a1, info.a2);
e = evid / max(max(evid(:)), eps);
consensus = e > graythresh(e(P.valid));

gate = imdilate(T > cfg.per.localGate * graythresh(T(P.valid)), strel('disk', 2));
rawMask = consensus & gate & P.valid;

info.detector = 'periodic';
fprintf('  [periodic] a1=[%.1f %.1f] a2=[%.1f %.1f]\n', info.a1, info.a2);
D = refineMask(rawMask, P, cfg, 'periodic', info);
end
