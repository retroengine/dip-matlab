function J = regionfill(I, mask)
% REGIONFILL Harmonic boundary interpolation (Laplace PDE solver) with zero toolboxes.

wasUint8 = isa(I, 'uint8');
if wasUint8
    J = double(I);
else
    J = I;
end

mask = logical(mask);
if ~any(mask(:))
    return;
end

% Initialize mask interior with mean of immediately adjacent boundary pixels
se = [0 1 0; 1 1 1; 0 1 0];
c = conv2(double(mask), double(se), 'same');
boundary = (c > 0) & (~mask);

if any(boundary(:))
    initVal = mean(J(boundary));
else
    initVal = mean(J(:));
end
J(mask) = initVal;

% Jacobi relaxation for Laplace equation \nabla^2 u = 0 on mask interior
maxIter = 120;
tol = 1e-4;

for iter = 1:maxIter
    prev = J(mask);
    
    up    = [J(2:end, :); J(end, :)];
    down  = [J(1, :); J(1:end-1, :)];
    left  = [J(:, 2:end), J(:, end)];
    right = [J(:, 1), J(:, 1:end-1)];
    
    avg = 0.25 * (up + down + left + right);
    J(mask) = avg(mask);
    
    if max(abs(J(mask) - prev)) < tol
        break;
    end
end

if wasUint8
    J = uint8(min(max(round(J), 0), 255));
end

end
