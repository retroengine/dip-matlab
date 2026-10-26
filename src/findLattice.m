function [a1, a2] = findLattice(peaksXY, T, valid, cfg)
% FINDLATTICE Identify and refine 2D periodic lattice basis vectors from autocorrelation peaks.
%
% Inputs:
%   peaksXY - Nx2 double array of peak displacement vectors [dx, dy] from origin
%   T       - (Optional) 2D double evidence map for refinement
%   valid   - (Optional) 2D logical ROI mask
%   cfg     - (Optional) Configuration struct (cfg.per.refineIter)
%
% Outputs:
%   a1      - 1x2 double shortest primary lattice vector [dx, dy]
%   a2      - 1x2 double shortest non-collinear secondary lattice vector [dx, dy]

if isempty(peaksXY) || size(peaksXY, 1) < 2
    error('findLattice:insufficientPeaks', 'At least two peaks required to identify lattice.');
end

% Sort peaks by Euclidean distance to origin
dists = hypot(peaksXY(:, 1), peaksXY(:, 2));
[~, sortIdx] = sort(dists);
peaksXY = peaksXY(sortIdx, :);

a1 = peaksXY(1, :);
a2 = [];

for k = 2:size(peaksXY, 1)
    cand = peaksXY(k, :);
    crossProd = abs(a1(1) * cand(2) - a1(2) * cand(1));
    normProd = norm(a1) * norm(cand);
    c = crossProd / max(normProd, eps);
    
    if c > 0.35
        a2 = cand;
        break;
    end
end

if isempty(a2)
    error('findLattice:none', 'No second non-collinear lattice vector found.');
end

% Optional sub-pixel lattice refinement via fminsearch
if nargin >= 4 && ~isempty(T) && ~isempty(valid) && isfield(cfg, 'per') && cfg.per.refineIter > 0
    try
        initParams = [a1(:)', a2(:)'];
        opts = optimset('Display', 'off', 'MaxIter', cfg.per.refineIter, 'TolX', 1e-2, 'TolFun', 1e-3);
        
        % Downsample T and valid for fast optimization if large
        [H, W] = size(T);
        dsScale = max(1, round(max(H, W) / 250));
        if dsScale > 1
            Tsub = T(1:dsScale:end, 1:dsScale:end);
            Vsub = valid(1:dsScale:end, 1:dsScale:end);
            costFn = @(p) latticeCost(p / dsScale, Tsub, Vsub);
            refinedParams = fminsearch(costFn, initParams, opts);
        else
            costFn = @(p) latticeCost(p, T, valid);
            refinedParams = fminsearch(costFn, initParams, opts);
        end
        
        % Ensure sensible solution bounds (within 20% of initial estimate)
        if norm(refinedParams(1:2) - a1) < 0.25 * norm(a1) && ...
           norm(refinedParams(3:4) - a2) < 0.25 * norm(a2)
            a1 = refinedParams(1:2);
            a2 = refinedParams(3:4);
        end
    catch ME
        % If optimization toolbox is absent or fminsearch fails, keep initial estimates
    end
end

end

function cost = latticeCost(p, T, valid)
a1 = p(1:2);
a2 = p(3:4);

% Degeneracy check
A = [a1(:), a2(:)];
if abs(det(A)) < 20 || rcond(A) < 1e-4
    cost = 1e6;
    return;
end

[~, evid, ~] = foldTiles(T, valid, a1, a2);
diffs = abs(T(valid) - evid(valid));
cost = median(diffs);
end
