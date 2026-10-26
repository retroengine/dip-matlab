function J = removeInpaint(I, maskDil, method, cfg)
% REMOVEINPAINT Watermark removal via coherent, exemplar, or boundary inpainting.
%
% Methods:
%   'coherent'   - Inpaints using structural coherence (inpaintCoherent with regionfill fallback)
%   'exemplar'   - Texture synthesis inpainting (inpaintExemplar with criminisiInpaint fallback)
%   'regionfill' - Harmonic boundary PDE interpolation per channel
%
% Inputs:
%   I       - 3D double RGB image in [0, 1]
%   maskDil - 2D logical dilated watermark mask
%   method  - 'coherent' | 'exemplar' | 'regionfill'
%   cfg     - Configuration struct (cfg.inp, cfg.caps)
%
% Output:
%   J       - Inpainted 3D double RGB image in [0, 1]

if nargin < 3 || isempty(method)
    method = 'coherent';
end

maskDil = logical(maskDil);
if ~any(maskDil(:))
    J = I;
    return;
end

% Ensure floating point [0, 1]
if ~isfloat(I)
    I = im2double(I);
else
    I = min(max(I, 0), 1);
end

switch lower(method)
    case 'coherent'
        if isfield(cfg, 'caps') && isfield(cfg.caps, 'hasCoherent') && cfg.caps.hasCoherent && exist('inpaintCoherent', 'file')
            try
                J = inpaintCoherent(I, maskDil, ...
                    'SmoothingFactor', cfg.inp.coherentSmooth, ...
                    'Radius', cfg.inp.coherentRadius);
            catch
                % Fallback to regionfill if inpaintCoherent fails
                J = I;
                for c = 1:size(I, 3)
                    J(:,:,c) = regionfill(I(:,:,c), maskDil);
                end
            end
        else
            % Coherent fallback: regionfill per color channel
            J = I;
            for c = 1:size(I, 3)
                J(:,:,c) = regionfill(I(:,:,c), maskDil);
            end
        end
        
    case 'exemplar'
        if isfield(cfg, 'caps') && isfield(cfg.caps, 'hasExemplar') && cfg.caps.hasExemplar && exist('inpaintExemplar', 'file')
            try
                J = inpaintExemplar(I, maskDil, 'PatchSize', cfg.inp.exemplarPatch);
            catch
                % Fallback to criminisiInpaint
                J = criminisiInpaint(I, maskDil, cfg.inp.exemplarPatch);
            end
        else
            % Exemplar fallback: Criminisi exemplar patch inpainter
            J = criminisiInpaint(I, maskDil, cfg.inp.exemplarPatch);
        end
        
    case 'regionfill'
        J = I;
        for c = 1:size(I, 3)
            J(:,:,c) = regionfill(I(:,:,c), maskDil);
        end
        
    otherwise
        error('removeInpaint:unknownMethod', 'Unknown inpainting method: %s', method);
end

J = min(max(J, 0), 1);

end
