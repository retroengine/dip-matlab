function [J, ainfo] = removeAlphaInvert(I, D, Jinp, cfg)
% REMOVEALPHAINVERT Watermark removal via opacity-inversion and edge-cancellation.
%
% Physics model:  I = (1-a)*J + a*W  =>  J = (I - a*W) / (1 - a)
%
% Estimates scalar alpha a0 via Total-Variation minimisation on the glyph
% boundary band (edge-cancellation criterion, Section 4.1 of spec).
%
% Inputs:
%   I    - 3D double RGB observed image in [0,1]
%   D    - Detection struct: D.m (soft coverage), D.maskTight, D.maskDil
%   Jinp - 3D double inpainted reference (initial clean-image guess)
%   cfg  - Config struct: cfg.alpha.*
%
% Outputs:
%   J     - Restored 3D RGB image in [0,1]
%   ainfo - Struct: a0, a_init, cost, reliable

W_wm = reshape(cfg.alpha.W, 1, 1, 3);   % watermark colour (usually white)
m    = D.m;                              % soft coverage mask in [0,1]

% -----------------------------------------------------------------------
% Guard: if mask is trivially empty, skip everything
% -----------------------------------------------------------------------
if ~any(D.maskTight(:))
    J = Jinp;
    ainfo = struct('a0', 0, 'a_init', 0, 'cost', zeros(1, numel(cfg.alpha.search)), ...
                   'reliable', false);
    return;
end

% -----------------------------------------------------------------------
% 1. Boundary band: dilated edge of the soft mask thresholded at 0.5
% -----------------------------------------------------------------------
mBin = m > 0.3;
edg = edge(mBin, 'sobel');
band = imdilate(edg, strel('disk', 3));

% Extend band with inside mask boundary to get more signal
bandInner  = imerode(mBin, strel('disk', 2));
bandOuter  = imdilate(mBin, strel('disk', 4));
band       = (bandOuter & ~bandInner) | band;

% Emergency fallback: if band is tiny use full tight mask
if sum(band(:)) < 50
    band = D.maskTight;
end

% -----------------------------------------------------------------------
% 2. Robust initial estimate from inpainting difference
%    alpha_init = median of (I - Jinp) / (W - Jinp) inside mask
%    where denominator is large enough to avoid division blow-up
% -----------------------------------------------------------------------
den = W_wm - Jinp;   % 3-channel
num = I    - Jinp;

ok = repmat(D.maskTight, [1 1 3]) & (abs(den) > cfg.alpha.minDen);
if any(ok(:))
    ratios = num(ok) ./ den(ok);
    ratios = ratios(isfinite(ratios) & ratios >= 0 & ratios <= 1);
end

if ~any(ok(:)) || isempty(ratios)
    a_init = 0.30;
else
    a_init = median(ratios);
    a_init = min(max(a_init, 0.05), 0.75);
end

% -----------------------------------------------------------------------
% 3. Line search by edge cancellation
%    For each candidate alpha, compute J_a and measure Total Variation
%    of luminance along the boundary band.
%    Correct alpha makes watermark edges vanish => TV minimum.
% -----------------------------------------------------------------------
searchVals = cfg.alpha.search;
cost       = zeros(1, numel(searchVals));

for k = 1:numel(searchVals)
    a      = searchVals(k);
    denom  = max(1 - a * m, 1e-4);
    Ja     = (I - a * m .* W_wm) ./ denom;
    Ja     = min(max(Ja, 0), 1);

    % Luminance (weighted RGB -> Y)
    L      = 0.2989 * Ja(:,:,1) + 0.5870 * Ja(:,:,2) + 0.1140 * Ja(:,:,3);

    [gx, gy] = imgradientxy(L);
    tv = hypot(gx, gy);

    cost(k) = mean(tv(band));   % mean (not sum) → scale-invariant
end

% 3-tap smoothing to suppress single-point noise
cs = conv(cost, [1 1 1]/3, 'same');

% Find minimum excluding boundary points (indices 2..end-1)
[cmin, kmin] = min(cs(2:end-1));
kmin = kmin + 1;   % re-index into full array

a0 = searchVals(kmin);

% -----------------------------------------------------------------------
% 4. Reliability: minimum is not at boundary AND TV reduced >= 5% vs a=0
% -----------------------------------------------------------------------
costAtZero = cost(1);
tvReduction = (costAtZero - cmin) / max(costAtZero, eps);
reliable    = (kmin > 2) && (kmin < numel(searchVals)-1) && (tvReduction > 0.05);

fprintf('  [alpha] a_init=%.3f  a0=%.3f  TV_reduction=%.1f%%  reliable=%d\n', ...
        a_init, a0, tvReduction*100, reliable);

% -----------------------------------------------------------------------
% 5. Invert where opacity is safe; paste inpainting result elsewhere
% -----------------------------------------------------------------------
aMap  = a0 * m;
denom = max(1 - aMap, 1e-3);
J     = (I - aMap .* W_wm) ./ denom;
J     = min(max(J, 0), 1);

% Pixels where alpha too high OR method unreliable: use inpainting instead
useInp  = (aMap > cfg.alpha.maxA) | ~reliable;
useInp3 = repmat(useInp & D.maskDil, [1 1 3]);
J(useInp3) = Jinp(useInp3);

ainfo = struct('a0', a0, 'a_init', a_init, 'cost', cost, 'reliable', reliable);
end
