function [gx, gy] = imgradientxy(I)
% IMGRADIENTXY Spatial image gradients along X and Y axes.
[gx, gy] = gradient(double(I));
end
