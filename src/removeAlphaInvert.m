function [J, ainfo] = removeAlphaInvert(I, D, Jinp, cfg)
% REMOVEALPHAINVERT Watermark removal via physical opacity inversion and edge cancellation.
%
% Math Formulation:
%   Observed: I = (1 - a)*J + a*W
%   Inversion: J = (I - a*W) / (1 - a)
%   Estimates scalar alpha a0 via Total Variation minimization on glyph boundary band.
%   Preserves true background texture under semi-transparent overlays.
%
% Inputs:
%   I     - 3D double RGB observed image in [0, 1]
%   D     - Detection struct with D.m (soft opacity), D.maskTight, D.maskDil
%   Jinp  - 3D double inpainted reference image (initial guess of clean photo)
%   cfg   - Configuration struct (cfg.alpha)
%
% Outputs:
%   J     - Inverted and blended clean image in [0, 1]
%   ainfo - Struct with estimated a0, initial guess a_init, cost curve, and reliability flag

W = reshape(cfg.alpha.W, 1, 1, 3);
m = D.m;

% Ensure mask boundary band is constructed
if exist('edge', 'file') || exist('edge', 'builtin')
    edg = edge(m > 0.5, 'sobel');
else
    [emx, emy] = gradient(double(m > 0.5));
    edg = hypot(emx, emy) > 0.1;
end
band = imdilate(edg, strel('disk', 2));

% 1. Robust initial estimate from inpainting difference
den = W - Jinp;
num = I - Jinp;
ok = repmat(D.maskTight, [1 1 3]) & (abs(den) > cfg.alpha.minDen);

if any(ok(:))
    vals = num(ok) ./ den(ok);
    vals = vals(isfinite(vals) & vals >= 0 & vals <= 1);
    if ~isempty(vals)
        a_init = median(vals);
    else
        a_init = 0.35;
    end
else
    a_init = 0.35;
end

% 2. Line search by edge cancellation (minimizing TV along mask boundary band)
searchVals = cfg.alpha.search;
cost = zeros(size(searchVals));

for k = 1:numel(searchVals)
    a = searchVals(k);
    denom = max(1 - a * m, 1e-4);
    Ja = (I - a * m .* W) ./ denom;
    Ja = min(max(Ja, 0), 1);
    
    % Luminance gradient
    L = 0.2989 * Ja(:,:,1) + 0.5870 * Ja(:,:,2) + 0.1140 * Ja(:,:,3);
    if exist('imgradientxy', 'file') || exist('imgradientxy', 'builtin')
        [gx, gy] = imgradientxy(L);
    else
        [gx, gy] = gradient(L);
    end
    tv = hypot(gx, gy);
    cost(k) = sum(tv(band));
end

% 3-tap smoothing on cost curve
kernel = [1 1 1] / 3;
cs = conv(cost, kernel, 'same');

if numel(cs) >= 3
    [cmin, kmin] = min(cs(2:end-1));
    kmin = kmin + 1;
else
    [cmin, kmin] = min(cs);
end

a0 = searchVals(kmin);

% Reliability check: minimum not at boundary and TV reduced by >= 10% vs a=0
costAtZero = cost(1);
reliable = (kmin > 1) && (kmin < numel(searchVals)) && (cmin < 0.95 * costAtZero);

% 3. Invert where opacity is safe; fall back to inpainting where alpha is too opaque
aMap = a0 * m;
denom = max(1 - aMap, 1e-3);
J = (I - aMap .* W) ./ denom;
J = min(max(J, 0), 1);

useInp = (aMap > cfg.alpha.maxA) | (~reliable);
useInp3 = repmat(useInp & D.maskDil, [1 1 3]);
J(useInp3) = Jinp(useInp3);

ainfo = struct();
ainfo.a0 = a0;
ainfo.a_init = a_init;
ainfo.cost = cost;
ainfo.reliable = reliable;

end
