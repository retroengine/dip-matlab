function J = criminisiInpaint(I, mask, patchSize, maxIter)
% CRIMINISIINPAINT Exemplar-based image inpainting (Criminisi et al., IEEE TIP 2004).
%
% Reconstructs missing image regions by patch-based synthesis using confidence
% and isophote data terms along the fill front.
%
% Inputs:
%   I         - 3D double RGB image in [0, 1]
%   mask      - 2D logical mask of pixels to inpaint (true = hole)
%   patchSize - (Optional) 1x2 or scalar patch size (default [9 9])
%   maxIter   - (Optional) Maximum iterations (default 5000)
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
    maxIter = 5000;
end

[H, W, C] = size(I);
J = I;
omega = logical(mask); % Target hole region

if ~any(omega(:))
    return;
end

% Confidence term C(p): 0 in hole, 1 outside
confidence = double(~omega);

% Patch radius
ry = floor(patchSize(1) / 2);
rx = floor(patchSize(2) / 2);
patchArea = patchSize(1) * patchSize(2);

% Precompute source region (at least patch radius away from image borders)
sourceMask = ~omega;
sourceMask(1:ry, :) = false;
sourceMask(end-ry+1:end, :) = false;
sourceMask(:, 1:rx) = false;
sourceMask(:, end-rx+1:end) = false;

[srcY, srcX] = find(sourceMask);
numSrc = numel(srcY);
if numSrc == 0
    % Degenerate source region fallback
    for c = 1:C
        J(:,:,c) = regionfill(J(:,:,c), omega);
    end
    return;
end

% Subsample source candidates if too large for speed
if numSrc > 4000
    step = ceil(numSrc / 4000);
    srcY = srcY(1:step:end);
    srcX = srcX(1:step:end);
    numSrc = numel(srcY);
end

iter = 0;
while any(omega(:)) && iter < maxIter
    iter = iter + 1;
    
    % 1. Find fill front deltaOmega (boundary of omega)
    se = strel('square', 3);
    dilOmega = imdilate(omega, se);
    deltaOmega = dilOmega & (~omega);
    
    [frontY, frontX] = find(deltaOmega);
    numFront = numel(frontY);
    if numFront == 0
        break;
    end
    
    % 2. Compute Priority P(p) = C(p) * D(p) for boundary pixels
    % Convert current J to grayscale for gradient estimation
    grayJ = 0.2989 * J(:,:,1) + 0.5870 * J(:,:,2) + 0.1140 * J(:,:,3);
    [gx, gy] = gradient(grayJ);
    
    % Normal vector to front (gradient of omega)
    [nx, ny] = gradient(double(omega));
    
    priorities = zeros(numFront, 1);
    confidences = zeros(numFront, 1);
    
    for i = 1:numFront
        py = frontY(i);
        px = frontX(i);
        
        y1 = max(1, py - ry); y2 = min(H, py + ry);
        x1 = max(1, px - rx); x2 = min(W, px + rx);
        
        % Confidence term
        patchConf = confidence(y1:y2, x1:x2);
        Cp = sum(patchConf(:)) / patchArea;
        confidences(i) = Cp;
        
        % Data term: |isophote . normal|
        % Isophote is orthogonal to gradient: [-gy, gx]
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
    
    % 3. Find patch with highest priority
    [~, maxIdx] = max(priorities);
    targetY = frontY(maxIdx);
    targetX = frontX(maxIdx);
    bestCp = confidences(maxIdx);
    
    ty1 = max(1, targetY - ry); ty2 = min(H, targetY + ry);
    tx1 = max(1, targetX - rx); tx2 = min(W, targetX + rx);
    
    targetPatch = J(ty1:ty2, tx1:tx2, :);
    targetOmega = omega(ty1:ty2, tx1:tx2);
    knownPixels = ~targetOmega;
    
    % If target patch is completely unknown or on edge
    if ~any(knownPixels(:))
        confidence(ty1:ty2, tx1:tx2) = bestCp;
        omega(ty1:ty2, tx1:tx2) = false;
        continue;
    end
    
    % 4. Search source region for closest matching patch
    % Local search window centered at target for efficiency
    searchRadius = 70;
    localSrcMask = (abs(srcY - targetY) <= searchRadius) & (abs(srcX - targetX) <= searchRadius);
    candY = srcY(localSrcMask);
    candX = srcX(localSrcMask);
    
    if numel(candY) < 20
        candY = srcY;
        candX = srcX;
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
        
        % Ensure candidate patch does not overlap omega
        if any(reshape(omega(sy1:sy2, sx1:sx2), [], 1))
            continue;
        end
        
        candPatch = J(sy1:sy2, sx1:sx2, :);
        diff = candPatch - targetPatch;
        
        % SSD over known pixels only
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
    
    % 5. Copy unknown pixels from best source patch into target patch
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
    
    % 6. Update confidence and omega
    confidence(ty1:ty2, tx1:tx2) = confidence(ty1:ty2, tx1:tx2) + targetOmega * bestCp;
    omega(ty1:ty2, tx1:tx2) = false;
end

% Final pass: any remaining small pixels filled with regionfill
if any(omega(:))
    for c = 1:C
        J(:,:,c) = regionfill(J(:,:,c), omega);
    end
end

J = min(max(J, 0), 1);

end
