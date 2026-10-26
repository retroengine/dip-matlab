function out = imdilate(A, se)
% IMDILATE Morphological dilation with zero toolbox dependencies.

if isobject(se) && isprop(se, 'Neighborhood')
    B = se.Neighborhood;
elseif isstruct(se) && isfield(se, 'Neighborhood')
    B = se.Neighborhood;
elseif islogical(se) || isnumeric(se)
    B = se > 0;
else
    B = true(3, 3);
end

isBin = islogical(A);
if isBin
    % Fast binary dilation via 2D convolution
    c = conv2(double(A), double(B), 'same');
    out = (c > 0);
    return;
end

% Grayscale dilation via local neighborhood maximum
[bh, bw] = size(B);
cy = floor((bh + 1) / 2);
cx = floor((bw + 1) / 2);

[H, W, C] = size(A);
out = -inf(H, W, C, 'like', A);

[rOffsets, cOffsets] = find(B);
rOffsets = rOffsets - cy;
cOffsets = cOffsets - cx;

for k = 1:numel(rOffsets)
    dr = rOffsets(k);
    dc = cOffsets(k);
    
    % Source and destination index ranges with border clamping/padding
    srcR1 = max(1, 1 - dr); srcR2 = min(H, H - dr);
    dstR1 = max(1, 1 + dr); dstR2 = min(H, H + dr);
    
    srcC1 = max(1, 1 - dc); srcC2 = min(W, W - dc);
    dstC1 = max(1, 1 + dc); dstC2 = min(W, W + dc);
    
    shifted = A(srcR1:srcR2, srcC1:srcC2, :);
    out(dstR1:dstR2, dstC1:dstC2, :) = max(out(dstR1:dstR2, dstC1:dstC2, :), shifted);
end

% Replace any remaining -inf with original values
uncovered = isinf(out);
if any(uncovered(:))
    out(uncovered) = A(uncovered);
end

end
