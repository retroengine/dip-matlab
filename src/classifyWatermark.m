function [type, info] = classifyWatermark(P, cfg)
% CLASSIFYWATERMARK Classify watermark into 'periodic', 'sparse', or 'single'.
%
% Algorithm:
%   1. Computes unbiased 2D normalized autocorrelation on high-pass luminance.
%   2. Calculates z-score map outside exclusion radius cfg.cls.minLag.
%   3. Detects significant regional maxima (z > cfg.cls.zThresh).
%   4. Checks for non-collinear 2D periodic lattice with sufficient tile count.
%   5. If not periodic, executes mineRepeats to detect repeated logo structures.
%   6. Defaults to 'single' if neither periodic nor sparse repeats are verified.
%
% Outputs:
%   type - 'periodic' | 'sparse' | 'single'
%   info - Struct containing z-score map, detected peaks, lattice, template, logs

info = struct();
info.reasons = {};
info.type = 'single';
info.peaks = [];
info.a1 = [];
info.a2 = [];
info.tpl = [];
info.tplBox = [];

[H, W] = size(P.gray);

% 1. Hann windowing on high-pass signal to suppress border discontinuities
hannH = hann(H);
hannW = hann(W);
window2d = (hannH * hannW');
h_win = P.hp .* window2d;

% 2. Normalized autocorrelation unbiased by ROI geometry
ac = autocorrNorm(h_win, P.valid);

% Center coordinates of autocorrelation map
cy = H + 1;
cx = W + 1;

% Mask out center lag region (minLag exclusion disk)
[xx, yy] = meshgrid(1:(2*W), 1:(2*H));
distFromCenter = hypot(xx - cx, yy - cy);
lagMask = distFromCenter >= cfg.cls.minLag;

% Compute background mean and standard deviation outside minLag
acValid = ac(lagMask & (ac > -0.9));
bgMean = mean(acValid);
bgStd  = std(acValid);

% Z-score map
zMap = (ac - bgMean) / max(bgStd, eps);
zMap(~lagMask) = 0;
info.zMap = zMap;

% 3. Find regional maxima with z > cfg.cls.zThresh
if exist('imregionalmax', 'file') || exist('imregionalmax', 'builtin')
    regMax = imregionalmax(zMap);
else
    % Fallback regional max
    dil = imdilate(zMap, strel('disk', 2));
    regMax = (zMap == dil) & (zMap > 0);
end

sigMax = regMax & (zMap >= cfg.cls.zThresh);
[peakY, peakX] = find(sigMax);

% Calculate displacements relative to center
dx = peakX - cx;
dy = peakY - cy;

% Autocorrelation is symmetric: ac(dx, dy) == ac(-dx, -dy).
% Keep only unique half-plane peaks (e.g., dy > 0 or (dy == 0 and dx > 0))
uniqueHalf = (dy > 0) | (dy == 0 & dx > 0);
dx = dx(uniqueHalf);
dy = dy(uniqueHalf);
peakZ = zMap(sub2ind(size(zMap), peakY(uniqueHalf), peakX(uniqueHalf)));

% Sort by peak z-score descending
[~, sortZ] = sort(peakZ, 'descend');
maxPeaks = min(cfg.cls.maxPeaks, numel(sortZ));
dx = dx(sortZ(1:maxPeaks));
dy = dy(sortZ(1:maxPeaks));
peakZ = peakZ(sortZ(1:maxPeaks));

peaksXY = [dx, dy];
info.peaks = peaksXY;
info.peakZ = peakZ;

% 4. Check for 'periodic' classification
hasLattice = false;
if size(peaksXY, 1) >= cfg.cls.minOffPeaks
    try
        [T, ~] = evidenceMap(P, cfg);
        [a1, a2] = findLattice(peaksXY, T, P.valid, cfg);
        
        % Calculate how many full unit cells fit within image dimensions
        areaCell = abs(a1(1)*a2(2) - a1(2)*a2(1));
        validArea = sum(P.valid(:));
        numTiles = validArea / max(areaCell, 1);
        
        info.a1 = a1;
        info.a2 = a2;
        info.numTiles = numTiles;
        
        if numTiles >= cfg.per.minTiles
            hasLattice = true;
            type = 'periodic';
            info.type = 'periodic';
            info.reasons{end+1} = sprintf('Lattice found with %d peaks, norm(a1)=%.1f, norm(a2)=%.1f, ~%.1f tiles in ROI', ...
                size(peaksXY, 1), norm(a1), norm(a2), numTiles);
            return;
        else
            info.reasons{end+1} = sprintf('Lattice found but tiles (%.1f) < minTiles (%d)', numTiles, cfg.per.minTiles);
        end
    catch ME
        info.reasons{end+1} = sprintf('findLattice failed: %s', ME.message);
    end
else
    info.reasons{end+1} = sprintf('Peaks found (%d) < minOffPeaks (%d)', size(peaksXY, 1), cfg.cls.minOffPeaks);
end

% 5. Check for 'sparse' classification (repeated structures/logos)
[T, ~] = evidenceMap(P, cfg);
[tpl, tplBox, repeatsInfo] = mineRepeats(T, cfg);

if ~isempty(tpl) && repeatsInfo.count >= cfg.cls.minRepeats
    type = 'sparse';
    info.type = 'sparse';
    info.tpl = tpl;
    info.tplBox = tplBox;
    info.repeatsInfo = repeatsInfo;
    info.reasons{end+1} = sprintf('Repeated template mined with %d matching instances', repeatsInfo.count);
    return;
end

% 6. Otherwise 'single'
type = 'single';
info.type = 'single';
info.reasons{end+1} = 'Neither sufficient lattice periodicity nor repeated template instances found';

end
