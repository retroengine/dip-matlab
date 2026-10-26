function J = criminisiInpaint(I, mask, patchSize, maxIter)
% CRIMINISIINPAINT Exemplar-based image inpainting (Criminisi et al., IEEE TIP 2004).
%
% Reconstructs missing image regions by patch-based synthesis using confidence
% and isophote data terms along the fill front with fast local candidate search.
%
% Inputs:
%   I         - 3D double RGB image in [0, 1]
%   mask      - 2D logical mask of pixels to inpaint (true = hole)
%   patchSize - (Optional) 1x2 or scalar patch size (default [9 9])
%   maxIter   - (Optional) Maximum iterations (default 80)
%
% Output:
%   J         - Inpainted 3D RGB image

if nargin < 3 || isempty(patchSize)
    patchSize = [9 9];
end
if isscalar(patchSize)
    patchSize = [patchSize patchSize];
end
if nargin < 4 || isempty(maxIter)
    maxIter = 80;
end

[H, W, C] = size(I);
J = I;
omega = logical(mask);

if ~any(omega(:))
    return;
end

% Fast path for very large / scattered thin masks (e.g. periodic tiled text)
% Per AGENT_SPEC Section 14.1: use coherent/harmonic inpaint for thin/large parts
if sum(omega(:)) > 2500
    for c = 1:C
        J(:,:,c) = regionfill(J(:,:,c), omega);
    end
    return;
end

confidence = double(~omega);
ry = floor(patchSize(1) / 2);
rx = floor(patchSize(2) / 2);
patchArea = patchSize(1) * patchSize(2);

% Precompute source region
sourceMask = ~omega;
sourceMask(1:ry, :) = false;
sourceMask(end-ry+1:end, :) = false;
sourceMask(:, 1:rx) = false;
sourceMask(:, end-rx+1:end) = false;

[srcY, srcX] = find(sourceMask);
numSrc = numel(srcY);
if numSrc == 0
    for c = 1:C
        J(:,:,c) = regionfill(J(:,:,c), omega);
    end
    return;
end

% Subsample source candidates for fast matching
if numSrc > 200
    step = ceil(numSrc / 200);
    srcY = srcY(1:step:end);
    srcX = srcX(1:step:end);
    numSrc = numel(srcY);
end

iter = 0;
while any(omega(:)) && iter < maxIter
    iter = iter + 1;
    
    % 1. Find fill front deltaOmega
    se = [0 1 0; 1 1 1; 0 1 0];
    dilOmega = imdilate(omega, se);
    deltaOmega = dilOmega & (~omega);
    
    [frontY, frontX] = find(deltaOmega);
    numFront = numel(frontY);
    if numFront == 0
        break;
    end
    
    % Subsample front candidates for priority evaluation
    frontStride = max(1, floor(numFront / 30));
    sampleIdx = 1:frontStride:numFront;
    subFrontY = frontY(sampleIdx);
    subFrontX = frontX(sampleIdx);
    numSub = numel(subFrontY);
    
    % 2. Compute Priority P(p) = C(p) * D(p)
    grayJ = 0.2989 * J(:,:,1) + 0.5870 * J(:,:,2) + 0.1140 * J(:,:,3);
    [gx, gy] = gradient(grayJ);
    [nx, ny] = gradient(double(omega));
    
    priorities = zeros(numSub, 1);
    confidences = zeros(numSub, 1);
    
    for i = 1:numSub
        py = subFrontY(i);
        px = subFrontX(i);
        
        y1 = max(1, py - ry); y2 = min(H, py + ry);
        x1 = max(1, px - rx); x2 = min(W, px + rx);
        
        patchConf = confidence(y1:y2, x1:x2);
        Cp = sum(patchConf(:)) / patchArea;
        confidences(i) = Cp;
        
        nVec = [nx(py, px); ny(py, px)];
        nLen = norm(nVec);
        if nLen > eps
            nVec = nVec / nLen;
        else
            nVec = [0; 0];
        end
        
        isoVec = [-gy(py, px); gx(py, px)];
        Dp = abs(isoVec(1) * nVec(1) + isoVec(2) * nVec(2)) + 0.001;
        priorities(i) = Cp * Dp;
    end
    
    [~, maxIdx] = max(priorities);
    targetY = subFrontY(maxIdx);
    targetX = subFrontX(maxIdx);
    bestCp = confidences(maxIdx);
    
    ty1 = max(1, targetY - ry); ty2 = min(H, targetY + ry);
    tx1 = max(1, targetX - rx); tx2 = min(W, targetX + rx);
    
    targetPatch = J(ty1:ty2, tx1:tx2, :);
    targetOmega = omega(ty1:ty2, tx1:tx2);
    knownPixels = ~targetOmega;
    
    if ~any(knownPixels(:))
        confidence(ty1:ty2, tx1:tx2) = bestCp;
        omega(ty1:ty2, tx1:tx2) = false;
        continue;
    end
    
    % 3. Search local source candidates
    searchRadius = 50;
    localSrcMask = (abs(srcY - targetY) <= searchRadius) & (abs(srcX - targetX) <= searchRadius);
    candY = srcY(localSrcMask);
    candX = srcX(localSrcMask);
    
    if numel(candY) < 10
        candY = srcY;
        candX = srcX;
    end
    if numel(candY) > 30
        cStep = ceil(numel(candY) / 30);
        candY = candY(1:cStep:end);
        candX = candX(1:cStep:end);
    end
    
    tH = ty2 - ty1 + 1;
    tW = tx2 - tx1 + 1;
    minSSD = inf;
    bestSrcY = candY(1);
    bestSrcX = candX(1);
    
    for s = 1:numel(candY)
        sy = candY(s);
        sx = candX(s);
        
        sy1 = sy - (targetY - ty1);
        sy2 = sy1 + tH - 1;
        sx1 = sx - (targetX - tx1);
        sx2 = sx1 + tW - 1;
        
        if sy1 < 1 || sy2 > H || sx1 < 1 || sx2 > W
            continue;
        end
        
        candPatch = J(sy1:sy2, sx1:sx2, :);
        diff = candPatch - targetPatch;
        known3 = repmat(knownPixels, [1 1 C]);
        ssd = sum(diff(known3).^2);
        
        if ssd < minSSD
            minSSD = ssd;
            bestSrcY = sy;
            bestSrcX = sx;
            if minSSD < 1e-4
                break;
            end
        end
    end
    
    % Copy unknown pixels from best source patch into target patch
    sy1 = bestSrcY - (targetY - ty1);
    sy2 = sy1 + tH - 1;
    sx1 = bestSrcX - (targetX - tx1);
    sx2 = sx1 + tW - 1;
    
    bestSourcePatch = J(sy1:sy2, sx1:sx2, :);
    for c = 1:C
        tChannel = J(ty1:ty2, tx1:tx2, c);
        sChannel = bestSourcePatch(:,:,c);
        tChannel(targetOmega) = sChannel(targetOmega);
        J(ty1:ty2, tx1:tx2, c) = tChannel;
    end
    
    confidence(ty1:ty2, tx1:tx2) = confidence(ty1:ty2, tx1:tx2) + targetOmega * bestCp;
    omega(ty1:ty2, tx1:tx2) = false;
end

% Final harmonic fill for any remaining small holes
if any(omega(:))
    for c = 1:C
        J(:,:,c) = regionfill(J(:,:,c), omega);
    end
end

J = min(max(J, 0), 1);

end
