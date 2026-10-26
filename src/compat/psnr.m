function [peaksnr, snr] = psnr(A, ref)
% PSNR Peak Signal-to-Noise Ratio with zero toolbox dependencies.

diff = double(A) - double(ref);
mse = mean(diff(:).^2);

if isfloat(ref)
    maxVal = 1.0;
else
    maxVal = 255.0;
end

peaksnr = 10 * log10((maxVal^2) / max(mse, 1e-12));
snr = peaksnr;

end
