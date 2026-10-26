function [T, E] = evidenceMap(P, cfg)
% EVIDENCEMAP Evidence that a pixel is covered by a semi-transparent WHITE overlay.
%
% For each disk radius r the local background B is estimated by a grayscale
% opening, and the overlay residual is R = I - B. An overlay of white at
% opacity a adds R = a*(1 - B), so R is parallel to (1 - B):
%   a    = <R, 1-B> / |1-B|^2          (estimated opacity, clipped to [0,1])
%   kappa = cos angle(R, 1-B)          (whiteness consistency, raised to cfg.gen.whitePow)
%   c    = local-contrast attenuation  (overlays flatten texture beneath them)
% T = max over radii of a * kappa^p * c, normalised to [0, 1] in the ROI.
% Natural edges (wood, foliage, snow) have a residual that is not aligned with
% white, so kappa suppresses them; this is the single-image analogue of the
% photometric cues in Dekel et al., CVPR 2017.
%
% Inputs:  P (preprocess output), cfg (cfg.gen)
% Outputs: T - evidence map in [0,1];  E - Canny edge map of the gray image

I = P.I;
T = zeros(size(P.gray));
for r = cfg.gen.radii
    B = imopen(I, strel('disk', r));
    R = I - B;
    D = 1 - B;
    dot = sum(R .* D, 3);
    a = min(max(dot ./ max(sum(D.^2, 3), 1e-3), 0), 1);
    kappa = max(dot ./ max(sqrt(sum(R.^2, 3) .* sum(D.^2, 3)), 1e-6), 0);
    T = max(T, a .* kappa .^ cfg.gen.whitePow);
end

% Contrast attenuation: local std relative to a wide neighbourhood
g = P.gray;
sd = stdfilt(g, true(cfg.gen.contrastWin));
sdBg = imgaussfilt(sd, cfg.gen.contrastBgSigma);
c = 1 - min(sd ./ max(sdBg, 1e-3), 1);
T = T .* (cfg.gen.contrastMix + (1 - cfg.gen.contrastMix) * c);

T = imgaussfilt(T, cfg.gen.smoothSigma);
T(~P.valid) = 0;
T = T / max(max(T(:)), eps);
E = edge(g, 'canny');
end
