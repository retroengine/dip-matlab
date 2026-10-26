function [Tmed, evid, idx] = foldTiles(T, valid, a1, a2)
% FOLDTILES Fold evidence map along periodic 2D lattice and compute tile median.
%
% Computes consensus watermark evidence by mapping image coordinates onto the
% unit cell defined by lattice basis vectors a1 and a2, taking the median across
% corresponding tile points to eliminate non-periodic background content.
%
% Inputs:
%   T     - 2D double evidence map in [0, 1]
%   valid - 2D logical mask of valid image area
%   a1    - 1x2 double [dx, dy] first lattice vector in pixels
%   a2    - 1x2 double [dx, dy] second lattice vector in pixels
%
% Outputs:
%   Tmed  - Vector of median values per tile bin
%   evid  - Tile-consensus evidence map in original image space
%   idx   - 1D linear bin index for each pixel

[H, W] = size(T);
[x, y] = meshgrid(0:W-1, 0:H-1);

A = [a1(:), a2(:)];
if rcond(A) < 1e-6
    % Degenerate lattice vectors fallback
    evid = T .* double(valid);
    Tmed = evid(:);
    idx = (1:numel(T))';
    return;
end

% Project pixel coordinates onto lattice basis
uv = A \ [x(:)'; y(:)'];

% Fractional tile coordinate in [0, 1)
f = uv - floor(uv);

% Tile bin grid resolution
nb = [max(8, min(80, round(norm(a1)))), max(8, min(80, round(norm(a2))))];

bi = min(nb(1), max(1, floor(f(1, :) * nb(1)) + 1));
bj = min(nb(2), max(1, floor(f(2, :) * nb(2)) + 1));

idx = sub2ind(nb, bi, bj);
idx = idx(:);

v = valid(:);

% Compute tile consensus via median across all repetitions
numBins = prod(nb);
if any(v)
    Tmed = accumarray(idx(v), T(v), [numBins, 1], @median, 0);
else
    Tmed = zeros(numBins, 1);
end

evid = reshape(Tmed(idx), H, W);
evid(~valid) = 0;

end
