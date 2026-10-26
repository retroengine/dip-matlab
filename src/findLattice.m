function [a1, a2] = findLattice(peaksXY, T, valid, cfg)
% FINDLATTICE Identify and refine 2D periodic lattice basis vectors.
%
% Selects the two shortest non-collinear displacement vectors from the
% autocorrelation peak list, then optionally refines them by minimising
% tile-folding inconsistency with fminsearch.
%
% Inputs:
%   peaksXY - Nx2 double [dx, dy] peak displacements relative to AC origin
%   T       - (Optional) 2D double evidence map for sub-pixel refinement
%   valid   - (Optional) 2D logical ROI mask
%   cfg     - (Optional) config struct (cfg.per.refineIter)
%
% Outputs:
%   a1  - 1x2 double primary lattice vector [dx, dy]
%   a2  - 1x2 double secondary non-collinear lattice vector [dx, dy]

if isempty(peaksXY) || size(peaksXY, 1) < 2
    error('findLattice:insufficientPeaks', 'At least two peaks required.');
end

% Sort by distance to origin (ascending), take shortest first
dists = hypot(peaksXY(:,1), peaksXY(:,2));
[~, sidx] = sort(dists);
peaksXY = peaksXY(sidx, :);

% Pick a1 = shortest peak
a1 = peaksXY(1, :);
a2 = [];

% Pick a2 = shortest peak not collinear with a1
% sin(angle) = |cross| / (|a1||a2|)  >  sin(20 deg) ≈ 0.34
for k = 2:size(peaksXY, 1)
    cand = peaksXY(k, :);
    n1 = norm(a1);  nc = norm(cand);
    if n1 < eps || nc < eps, continue; end
    sinAngle = abs(a1(1)*cand(2) - a1(2)*cand(1)) / (n1 * nc);
    if sinAngle > 0.34
        a2 = cand;
        break;
    end
end

if isempty(a2)
    error('findLattice:none', 'No non-collinear second lattice vector found.');
end

% -----------------------------------------------------------------------
% Sub-pixel refinement: minimise median absolute deviation of folded tiles
% Only run if fminsearch is available and T/valid are supplied.
% -----------------------------------------------------------------------
doRefine = nargin >= 4 && ~isempty(T) && ~isempty(valid) && ...
           isfield(cfg, 'per') && cfg.per.refineIter > 0;

if doRefine
    try
        [H, W] = size(T);

        % Downsample heavy images so optimisation is fast
        dsScale = max(1, round(max(H, W) / 200));
        if dsScale > 1
            Ts = T(1:dsScale:end, 1:dsScale:end);
            Vs = valid(1:dsScale:end, 1:dsScale:end);
            scale = 1 / dsScale;
        else
            Ts = T; Vs = valid; scale = 1;
        end

        x0 = [a1 * scale, a2 * scale];   % scale vectors into downsampled space

        opts = optimset('Display','off', ...
                        'MaxIter', cfg.per.refineIter, ...
                        'TolX', 1e-3, 'TolFun', 1e-4);

        costFn = @(p) latticeCostFn(p, Ts, Vs);
        xOpt   = fminsearch(costFn, x0, opts);

        % Convert back to full-resolution and sanity-check
        a1c = xOpt(1:2) / scale;
        a2c = xOpt(3:4) / scale;

        drift1 = norm(a1c - a1);
        drift2 = norm(a2c - a2);

        if drift1 < 0.3 * norm(a1) && drift2 < 0.3 * norm(a2)
            % Also ensure vectors are still non-collinear
            sinNew = abs(a1c(1)*a2c(2) - a1c(2)*a2c(1)) / ...
                     (norm(a1c) * norm(a2c) + eps);
            if sinNew > 0.2
                a1 = a1c;
                a2 = a2c;
            end
        end
    catch
        % fminsearch unavailable or failed: keep initial estimate
    end
end

end

% -----------------------------------------------------------------------
% Local helper: tile-fold cost (lower = vectors explain the evidence better)
% -----------------------------------------------------------------------
function cost = latticeCostFn(p, T, valid)
a1 = p(1:2);
a2 = p(3:4);

A = [a1(:), a2(:)];
if abs(det(A)) < 4 || rcond(A) < 1e-5
    cost = 1e6;
    return;
end

[~, evid, ~] = foldTiles(T, valid, a1, a2);

% MAD of (observed - consensus) inside valid region
diff = abs(T(valid) - evid(valid));
cost = median(diff);
end
