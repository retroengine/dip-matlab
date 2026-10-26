function [type, info] = classifyWatermark(P, cfg)
% CLASSIFYWATERMARK Classify watermark as 'periodic', 'sparse', or 'single'.
%
% Algorithm:
%   1. Hann-windowed 2D autocorrelation of high-pass luminance.
%   2. Z-score map outside minLag exclusion disk.
%   3. Regional maxima with z > z_thresh.
%   4. Check for a valid 2D periodic lattice with enough tiles.
%   5. If not periodic, run mineRepeats for repeated logo/text structures.
%   6. Default to 'single'.
%
% Outputs:
%   type - 'periodic' | 'sparse' | 'single'
%   info - struct with peaks, lattice, zMap, reasons, template info

info          = struct();
info.reasons  = {};
info.type     = 'single';
info.peaks    = [];
info.a1       = [];
info.a2       = [];
info.tpl      = [];
info.tplBox   = [];

[H, W] = size(P.gray);

% -----------------------------------------------------------------------
% 1. Hann-windowed high-pass; normalize so autocorr peaks are z-scored
% -----------------------------------------------------------------------
hannH  = hann(H);
hannW  = hann(W);
h_win  = P.hp .* (hannH * hannW') .* double(P.valid);

ac = autocorrNorm(h_win, P.valid);

% Autocorr is (2H) x (2W); center is at (H+1, W+1)
cy = H + 1;   cx = W + 1;

% -----------------------------------------------------------------------
% 2. Lag exclusion disk and z-score map
% -----------------------------------------------------------------------
[xx, yy] = meshgrid(1:2*W, 1:2*H);
distMap   = hypot(xx - cx, yy - cy);
lagMask   = distMap >= cfg.cls.minLag & distMap <= min(H, W) * 0.75;

acSamples = ac(lagMask);
acSamples = acSamples(acSamples > -0.8);   % drop extreme outliers
bgMean = mean(acSamples);
bgStd  = std(acSamples);

zMap          = (ac - bgMean) / max(bgStd, eps);
zMap(~lagMask) = 0;
info.zMap      = zMap;

% -----------------------------------------------------------------------
% 3. Find regional maxima above threshold
% -----------------------------------------------------------------------
if exist('imregionalmax','file') || exist('imregionalmax','builtin')
    regMax = imregionalmax(zMap);
else
    dil    = imdilate(zMap, strel('disk', 2));
    regMax = (zMap == dil) & (zMap > 0);
end

sigMax     = regMax & (zMap >= cfg.cls.zThresh);
[peakY, peakX] = find(sigMax);

% Displacements from AC centre
dx = peakX - cx;
dy = peakY - cy;

% Keep only unique half-plane (autocorr symmetric: peak(dx,dy)=peak(-dx,-dy))
halfPlane = (dy > 0) | (dy == 0 & dx > 0);
dx = dx(halfPlane);
dy = dy(halfPlane);
peakZ = zMap(sub2ind(size(zMap), peakY(halfPlane), peakX(halfPlane)));

% Sort descending and cap
[~, sortZ]  = sort(peakZ, 'descend');
nKeep       = min(cfg.cls.maxPeaks, numel(sortZ));
dx          = dx(sortZ(1:nKeep));
dy          = dy(sortZ(1:nKeep));
peakZ       = peakZ(sortZ(1:nKeep));

peaksXY     = [dx, dy];
info.peaks  = peaksXY;
info.peakZ  = peakZ;

fprintf('  [classify] %d significant AC peaks (z>%.1f)\n', size(peaksXY,1), cfg.cls.zThresh);

% -----------------------------------------------------------------------
% 4. Check for 'periodic' classification
% -----------------------------------------------------------------------
if size(peaksXY, 1) >= cfg.cls.minOffPeaks
    try
        [T, ~] = evidenceMap(P, cfg);
        [a1, a2] = findLattice(peaksXY, T, P.valid, cfg);

        % Estimate tile count: valid area / unit-cell area
        cellArea = abs(a1(1)*a2(2) - a1(2)*a2(1));
        numTiles = sum(P.valid(:)) / max(cellArea, 1);

        info.a1       = a1;
        info.a2       = a2;
        info.numTiles = numTiles;

        fprintf('  [classify] Lattice: a1=[%.1f %.1f] a2=[%.1f %.1f], ~%.1f tiles\n', ...
                a1(1), a1(2), a2(1), a2(2), numTiles);

        if numTiles >= cfg.cls.minTiles
            % Extra guard: require evidence that tiles actually repeat
            % i.e. the top AC peak z-score is high (>= 1.5x threshold)
            topZ = max(peakZ);
            if topZ >= 1.5 * cfg.cls.zThresh
                type         = 'periodic';
                info.type    = 'periodic';
                info.reasons{end+1} = sprintf( ...
                    'Lattice with %.0f tiles, top z=%.1f', numTiles, topZ);
                return;
            else
                info.reasons{end+1} = sprintf( ...
                    'Lattice OK but top z=%.1f < 1.5*thresh -> too weak for periodic', topZ);
            end
        else
            info.reasons{end+1} = sprintf( ...
                'Lattice found but tiles %.1f < minTiles %d', numTiles, cfg.cls.minTiles);
        end
    catch ME
        info.reasons{end+1} = sprintf('findLattice failed: %s', ME.message);
    end
else
    info.reasons{end+1} = sprintf('Peaks %d < minOffPeaks %d', ...
        size(peaksXY,1), cfg.cls.minOffPeaks);
end

% -----------------------------------------------------------------------
% 5. Check for 'sparse' (repeated logos / instances)
% -----------------------------------------------------------------------
[T, ~] = evidenceMap(P, cfg);
[tpl, tplBox, repeatsInfo] = mineRepeats(T, cfg);

if ~isempty(tpl) && repeatsInfo.count >= cfg.cls.minRepeats
    type              = 'sparse';
    info.type         = 'sparse';
    info.tpl          = tpl;
    info.tplBox       = tplBox;
    info.repeatsInfo  = repeatsInfo;
    info.reasons{end+1} = sprintf('Repeated template: %d instances', repeatsInfo.count);
    fprintf('  [classify] sparse: %d repeated instances found\n', repeatsInfo.count);
    return;
end

% -----------------------------------------------------------------------
% 6. Single / localized watermark
% -----------------------------------------------------------------------
type             = 'single';
info.type        = 'single';
info.reasons{end+1} = 'No reliable periodicity or repeated template found';
fprintf('  [classify] -> single\n');

end
