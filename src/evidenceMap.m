function [T, E] = evidenceMap(P, cfg)
% EVIDENCEMAP Compute multi-scale evidence map for watermark structures.
%
% Integrates multi-scale top-hat filtering, edge density, and saturation
% drop cues to isolate bright, crisp watermark overlays while rejecting
% natural highlights and smooth textures.
%
% Inputs:
%   P   - Preprocessed struct from preprocess.m
%   cfg - Configuration struct (cfg.gen)
%
% Outputs:
%   T   - Normalized evidence map in [0, 1]
%   E   - Canny binary edge map

G = P.gray;
[H, W] = size(G);
T = zeros(H, W);

% 1. Multi-scale white top-hat filtering across specified disk radii
for r = cfg.gen.radii
    se = strel('disk', r);
    th = imtophat(G, se);
    T = max(T, th);
end

% 2. Edge density map (Canny edge detection blurred with Gaussian)
if exist('edge', 'file') || exist('edge', 'builtin')
    E = edge(G, 'canny');
else
    [gx, gy] = gradient(G);
    E = hypot(gx, gy) > 0.1;
end
Ed = imgaussfilt(double(E), cfg.gen.edgeSigma);
maxEd = max(Ed(:));
if maxEd > 0
    Ed = Ed ./ maxEd;
end

% 3. Saturation drop cue (watermarks often de-saturate colored backgrounds)
hsvImg = rgb2hsv(P.I);
S = hsvImg(:, :, 2);
satBlur = imgaussfilt(S, 8);
satDrop = max(0, satBlur - S);

% 4. Combine cues: top-hat boosted by edge density and saturation drop
T = T .* (0.5 + 0.5 * Ed) .* (1 + satDrop);

% Mask out invalid boundary regions
T(~P.valid) = 0;

% Normalize to [0, 1]
maxT = max(T(:));
if maxT > 0
    T = T ./ maxT;
end

end
