function [type, info] = classifyWatermark(P, cfg)
% CLASSIFYWATERMARK Classify the watermark as 'periodic', 'sparse' or 'single'.
%
% Algorithm:
%   1. Autocorrelation of the (mean-removed, Hann-windowed) watermark
%      evidence map T inside the ROI, unbiased by the overlap count.
%   2. z-score map outside cfg.cls.minLag; lags within cfg.cls.axisBand px of
%      the vertical axis are suppressed (they are windowing / JPEG ridges, not
%      repeats; the x axis stays open because tiled rows run along it).
%   3. Regional maxima with z > cfg.cls.zThresh. If a non-collinear lattice
%      exists with >= cfg.per.minTiles cells in the ROI and folding T on it
%      explains the evidence (consensus correlation >= cfg.cls.minFoldCorr)
%      -> 'periodic'.
%   4. Otherwise mineRepeats: >= cfg.cls.minRepeats near-identical
%      structures -> 'sparse'.
%   5. Otherwise 'single'.
%
% Outputs:
%   type - 'periodic' | 'sparse' | 'single'
%   info - struct with zMap, peaks, lattice, template and decision reasons

info = struct('reasons', {{}}, 'type', 'single', 'peaks', [], 'peakZ', [], ...
              'a1', [], 'a2', [], 'tpl', [], 'tplBox', []);
[H, W] = size(P.gray);
[T, ~] = evidenceMap(P, cfg);
info.T = T;

% 1. Autocorrelation of the windowed, mean-removed evidence
hann = @(n) 0.5 - 0.5 * cos(2 * pi * (0:n-1)' / max(n - 1, 1));
% Feature: gradient magnitude of the gray image, high-passed (removes horizon /
% illumination bias), mean-removed and windowed before autocorrelation.
Gm = imgradient(imgaussfilt(P.gray, cfg.cls.gradSigma));
Gm = Gm - imgaussfilt(Gm, cfg.cls.hpSigma);
t = (Gm - mean(Gm(P.valid))) .* (hann(H) * hann(W)') .* P.valid;
ac = autocorrNorm(t, P.valid);
cy = H + 1; cx = W + 1;

% 2. z-score map over the admissible lag region
[xx, yy] = meshgrid((1:2*W) - cx, (1:2*H) - cy);
lagMask = hypot(xx, yy) >= cfg.cls.minLag & ...
          abs(xx) <= cfg.cls.maxLagFrac * W & abs(yy) <= cfg.cls.maxLagFrac * H & ...
          abs(xx) > cfg.cls.axisBand;   % vertical ridge of the high-pass / JPEG artifact
bg = ac(lagMask);
bgMed = median(bg);
zMap = (ac - bgMed) / max(1.4826 * median(abs(bg - bgMed)), eps);   % robust z-score
zMap(~lagMask) = 0;
info.zMap = zMap;

% 3. Significant peaks, one per +/- pair
pk = imregionalmax(zMap) & zMap >= cfg.cls.zThresh;
[py, px] = find(pk);
dx = px - cx; dy = py - cy;
half = dy > 0 | (dy == 0 & dx > 0);
dx = dx(half); dy = dy(half);
peakZ = zMap(sub2ind(size(zMap), py(half), px(half)));
[peakZ, o] = sort(peakZ, 'descend');
o = o(1:min(cfg.cls.maxPeaks, numel(o)));
peakZ = peakZ(1:numel(o));
info.peaks = [dx(o), dy(o)];
info.peakZ = peakZ;
fprintf('  [classify] %d significant AC peaks (z>=%.1f)\n', numel(o), cfg.cls.zThresh);

if size(info.peaks, 1) >= cfg.cls.minOffPeaks
    try
        [a1, a2] = findLattice(info.peaks, T, P.valid, cfg);
        nTiles = nnz(P.valid) / max(abs(a1(1)*a2(2) - a1(2)*a2(1)), 1);
        [~, evid] = foldTiles(T, P.valid, a1, a2);
        cc = corrcoef(T(P.valid), evid(P.valid));
        foldCorr = cc(1, 2);
        info.a1 = a1; info.a2 = a2; info.numTiles = nTiles; info.foldCorr = foldCorr;
        fprintf('  [classify] lattice a1=[%.1f %.1f] a2=[%.1f %.1f], %.1f tiles, fold corr %.2f\n', ...
                a1, a2, nTiles, foldCorr);
        if nTiles >= cfg.per.minTiles && foldCorr >= cfg.cls.minFoldCorr
            type = 'periodic';
            info.type = type;
            info.reasons{end+1} = sprintf('lattice with %.0f tiles, fold corr %.2f', nTiles, foldCorr);
            return;
        end
        info.reasons{end+1} = sprintf('lattice rejected: %.1f tiles (min %d), fold corr %.2f (min %.2f)', ...
            nTiles, cfg.per.minTiles, foldCorr, cfg.cls.minFoldCorr);
    catch ME
        info.reasons{end+1} = sprintf('no lattice: %s', ME.message);
    end
else
    info.reasons{end+1} = sprintf('%d AC peaks < %d', size(info.peaks, 1), cfg.cls.minOffPeaks);
end

% 4. Repeated structures
[tpl, tplBox, rep] = mineRepeats(T, P.valid, cfg);
info.repeatsInfo = rep;
if ~isempty(tpl) && rep.count >= cfg.cls.minRepeats
    type = 'sparse';
    info.type = type;
    info.tpl = tpl;
    info.tplBox = tplBox;
    info.reasons{end+1} = sprintf('%d repeated structures', rep.count);
    fprintf('  [classify] -> sparse (%d repeats)\n', rep.count);
    return;
end
info.reasons{end+1} = sprintf('%d repeats < %d', rep.count, cfg.cls.minRepeats);

% 5. Single / localized
type = 'single';
info.type = type;
fprintf('  [classify] -> single (%s)\n', strjoin(info.reasons, '; '));
end
