function out = imopen(A, se)
% IMOPEN Morphological opening (erosion followed by dilation).
out = imdilate(imerode(A, se), se);
end
