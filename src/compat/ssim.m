function [score, ssim_map] = ssim(A, ref)
% SSIM Structural Similarity Index with zero toolbox dependencies.

if size(A, 3) > 1
    gA = 0.2989 * double(A(:,:,1)) + 0.5870 * double(A(:,:,2)) + 0.1140 * double(A(:,:,3));
else
    gA = double(A);
end

if size(ref, 3) > 1
    gRef = 0.2989 * double(ref(:,:,1)) + 0.5870 * double(ref(:,:,2)) + 0.1140 * double(ref(:,:,3));
else
    gRef = double(ref);
end

if isfloat(ref)
    L = 1.0;
else
    L = 255.0;
end

c1 = (0.01 * L)^2;
c2 = (0.03 * L)^2;

muA = imgaussfilt(gA, 1.5);
muRef = imgaussfilt(gRef, 1.5);

muA_sq = muA.^2;
muRef_sq = muRef.^2;
muA_muRef = muA .* muRef;

sigmaA_sq = imgaussfilt(gA.^2, 1.5) - muA_sq;
sigmaRef_sq = imgaussfilt(gRef.^2, 1.5) - muRef_sq;
sigmaA_Ref = imgaussfilt(gA .* gRef, 1.5) - muA_muRef;

num = (2 * muA_muRef + c1) .* (2 * sigmaA_Ref + c2);
den = (muA_sq + muRef_sq + c1) .* (sigmaA_sq + sigmaRef_sq + c2);

ssim_map = num ./ max(den, eps);
score = mean(ssim_map(:));

end
