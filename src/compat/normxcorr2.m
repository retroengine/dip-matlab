function C = normxcorr2(T, A)
% NORMXCORR2 2D normalized cross-correlation with zero toolbox dependencies.

T = double(T);
A = double(A);
[th, tw] = size(T);

tMean = mean(T(:));
tZeroMean = T - tMean;
tNorm = norm(tZeroMean(:));
if tNorm < eps
    tNorm = 1;
end

num = conv2(A, rot90(tZeroMean, 2), 'full');

onesT = ones(th, tw);
localSum = conv2(A, onesT, 'full');
localSumSq = conv2(A.^2, onesT, 'full');

numPixels = th * tw;
localVariance = max(localSumSq - (localSum.^2) / numPixels, 0);
denom = sqrt(localVariance) * tNorm;

C = num ./ max(denom, 1e-6);
C = min(max(C, -1.0), 1.0);

end
