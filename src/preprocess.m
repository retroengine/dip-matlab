function P = preprocess(I, cfg, imgName)
% PREPROCESS Convert image to double, compute color spaces, ROI, and high-pass.
%
% Data Contract:
%   P.I     - double RGB in [0, 1]
%   P.gray  - 2D grayscale in [0, 1]
%   P.lab   - 3D CIELAB representation
%   P.valid - logical ROI mask (true for valid image content)
%   P.hp    - high-pass filtered luminance (zeroed outside valid ROI)

if nargin < 3
    imgName = '';
end

% Ensure double in [0, 1]
if ~isfloat(I)
    I = im2double(I);
else
    I = min(max(I, 0), 1);
end

% If single channel, replicate to RGB
if size(I, 3) == 1
    I = repmat(I, [1 1 3]);
end

P = struct();
P.I = I;

% Luminance
P.gray = rgb2gray(I);

% CIELAB
if exist('rgb2lab', 'file') || exist('rgb2lab', 'builtin')
    P.lab = rgb2lab(I);
else
    % Fallback if rgb2lab is missing
    P.lab = zeros(size(I));
    P.lab(:,:,1) = P.gray * 100;
end

% Valid content ROI excluding solid borders/frames
P.valid = findROI(P.gray, cfg, imgName);

% High-pass filtering
lp = imgaussfilt(P.gray, cfg.pre.sigmaHP);
P.hp = P.gray - lp;
P.hp(~P.valid) = 0;

end
