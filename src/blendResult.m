function Jout = blendResult(I, J, maskDil, cfg)
% BLENDRESULT Feathering and blending restored regions into original image.
%
% Guarantees seamless transition at inpainting boundaries while preserving
% bit-exact original image pixels outside the feathered support envelope.
%
% Inputs:
%   I       - 3D double original RGB image
%   J       - 3D double restored RGB image
%   maskDil - 2D logical dilated watermark mask
%   cfg     - Configuration struct (cfg.blend.featherSigma)
%
% Output:
%   Jout    - 3D double blended RGB image

maskDil = logical(maskDil);
if ~any(maskDil(:))
    Jout = I;
    return;
end

% 1. Create continuous feathering weights via Gaussian filtering
sigma = cfg.blend.featherSigma;
F = imgaussfilt(double(maskDil), sigma);
F = min(F, 1.0);

% Mask interior is strictly replaced by restored image
F(maskDil) = 1.0;

% 2. Strict support envelope check: outside ceil(3*sigma), F is strictly 0
seSupport = strel('disk', ceil(3 * sigma));
supportMask = imdilate(maskDil, seSupport);
F(~supportMask) = 0.0;

% Replicate 2D blending weight to 3 channels
F3 = repmat(F, [1 1 size(I, 3)]);

% 3. Linear alpha blending
Jout = I .* (1 - F3) + J .* F3;

% Enforce bit-exact identity outside support envelope
notSupport3 = repmat(~supportMask, [1 1 size(I, 3)]);
Jout(notSupport3) = I(notSupport3);

Jout = min(max(Jout, 0), 1);

end
