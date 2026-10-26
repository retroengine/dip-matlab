function ac = autocorrNorm(h, valid)
% AUTOCORRNORM Normalized 2D autocorrelation unbiased by spatial mask overlap.
%
% Computes 2D autocorrelation of the high-pass signal h masked by valid,
% dividing by the mask-overlap count at every spatial lag to prevent
% tapering at large displacements.
%
% Inputs:
%   h     - 2D high-pass luminance signal
%   valid - 2D logical mask of valid image pixels
%
% Output:
%   ac    - Normalized 2D autocorrelation with center peak = 1.0

if nargin < 2 || isempty(valid)
    valid = true(size(h));
end

[H, W] = size(h);
h = h .* double(valid);

% Zero-pad to 2x dimensions to avoid circular correlation wrap-around
F  = fft2(h, 2*H, 2*W);
ac = real(ifft2(abs(F).^2));

Fv  = fft2(double(valid), 2*H, 2*W);
cnt = real(ifft2(abs(Fv).^2));

% Unbiased division by spatial overlap count
ac = ac ./ max(cnt, 1);

% Shift center lag (0, 0) to array center [H+1, W+1]
ac = fftshift(ac);

% Normalize so center auto-correlation is 1.0
centerVal = ac(H + 1, W + 1);
if abs(centerVal) > eps
    ac = ac ./ centerVal;
end

end
