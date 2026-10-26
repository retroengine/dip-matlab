function level = graythresh(I)
% GRAYTHRESH Global image threshold using Otsu's method with zero toolbox dependencies.

if isempty(I)
    level = 0.5;
    return;
end

I = double(I(:));
minV = min(I);
maxV = max(I);

if maxV - minV < eps
    level = min(max(minV, 0), 1);
    return;
end

% Normalize to [0, 1]
I_norm = (I - minV) / (maxV - minV);

% 256-bin histogram
numBins = 256;
counts = histcounts(I_norm, linspace(0, 1, numBins + 1));
p = counts / sum(counts);

omega = cumsum(p);
mu = cumsum(p .* (1:numBins));
mu_t = mu(end);

sigma_b_squared = (mu_t * omega - mu).^2 ./ max(omega .* (1 - omega), eps);

[~, maxIdx] = max(sigma_b_squared);
normLevel = (maxIdx - 1) / (numBins - 1);

% Scale back to original domain
level = minV + normLevel * (maxV - minV);
level = min(max(level, 0), 1);

end
