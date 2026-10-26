function out = imclose(A, se)
% IMCLOSE Morphological closing (dilation followed by erosion).
out = imerode(imdilate(A, se), se);
end
