function D = refineMask(rawMask, P, cfg, type, info)
% REFINEMASK Refine raw watermark mask to produce tight and dilated masks with soft coverage.
%
% Generates:
%   D.maskTight - pixel-accurate mask without dilation for alpha estimation
%   D.maskDil   - dilated mask to completely cover anti-aliased fringes during inpainting
%   D.m         - continuous soft opacity profile in [0, 1]
%   D.type      - classification type ('periodic', 'sparse', 'single')
%   D.info      - detector metadata struct
%
% Inputs:
%   rawMask - Initial binary detection mask
%   P       - Preprocessed struct (P.valid, P.gray)
%   cfg     - Configuration struct (cfg.mask, cfg.alpha)
%   type    - Detection type string
%   info    - Metadata struct

if nargin < 4, type = 'unknown'; end
if nargin < 5, info = struct(); end

rawMask = logical(rawMask) & P.valid;

% 1. Morphological closing to bridge small stroke breaks
seClose = strel('disk', cfg.mask.closeR);
maskClosed = imclose(rawMask, seClose);

% 2. Remove isolated noise specks
maskTight = bwareaopen(maskClosed, cfg.mask.minComp);

% 3. Optional active contour refinement
if isfield(cfg.mask, 'useActiveContour') && cfg.mask.useActiveContour && any(maskTight(:))
    maskTight = activecontour(P.gray, maskTight, 30, 'Chan-Vese');
end

maskTight = maskTight & P.valid;

% 4. Dilation to encompass blurry anti-aliasing edges
seDil = strel('disk', cfg.mask.dilateR);
maskDil = imdilate(maskTight, seDil) & P.valid;

% 5. Continuous soft coverage profile for alpha matting
m = imgaussfilt(double(maskTight), cfg.alpha.softSigma);
m = min(max(m, 0), 1);
m(~P.valid) = 0;

% Construct standard output contract
D = struct();
D.maskTight = maskTight;
D.maskDil   = maskDil;
D.m         = m;
D.type      = type;
D.info      = info;

end
