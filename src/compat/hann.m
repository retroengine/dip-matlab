function w = hann(N)
% HANN Hann (Hanning) window with zero toolbox dependencies.
if N <= 1
    w = 1;
else
    n = (0:N-1)';
    w = 0.5 * (1 - cos(2 * pi * n / (N - 1)));
end
end
