function out = imregionalmax(A)
% IMREGIONALMAX Identify regional maxima using local neighborhood dilation.
se = [1 1 1; 1 0 1; 1 1 1];
dil = imdilate(A, se);
out = (A > dil) | ((A == dil) & (A > 0));
end
