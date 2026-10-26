function metrics = computeMetrics(cleanImg, markedImg, restoredImg, gtAlpha, predMask, cfg, a0Est, a0True)
% COMPUTEMETRICS Calculate quantitative evaluation metrics for detection and restoration.
%
% Computes:
%   - Mask Detection: IoU, Precision, Recall, F1 against ground truth
%   - Image Restoration: PSNR and SSIM (whole image and inside dilated mask)
%   - Baseline: PSNR of marked image (before removal)
%   - Alpha Estimation: Absolute error |a0_est - a0_true|
%   - Blind Image Quality: NIQE, BRISQUE (if toolboxes available)
%
% Inputs:
%   cleanImg    - Clean reference image in [0, 1] (can be empty for real images)
%   markedImg   - Observed watermarked image in [0, 1]
%   restoredImg - Restored output image in [0, 1]
%   gtAlpha     - Ground truth alpha map (or gt mask)
%   predMask    - Predicted detection mask (tight)
%   cfg         - Configuration struct
%   a0Est       - (Optional) Estimated alpha scalar
%   a0True      - (Optional) Ground truth alpha scalar
%
% Output:
%   metrics     - Struct containing all calculated metrics

if nargin < 6, cfg = config(); end
if nargin < 7, a0Est = NaN; end
if nargin < 8, a0True = NaN; end

metrics = struct();

% 1. Mask Detection Metrics
if ~isempty(gtAlpha) && ~isempty(predMask)
    if islogical(gtAlpha)
        gtBin = gtAlpha;
    else
        gtBin = gtAlpha > cfg.eval.maskAlphaMin;
    end
    predBin = logical(predMask);
    
    tp = sum(predBin(:) & gtBin(:));
    fp = sum(predBin(:) & ~gtBin(:));
    fn = sum(~predBin(:) & gtBin(:));
    
    metrics.precision = tp / max(tp + fp, eps);
    metrics.recall    = tp / max(tp + fn, eps);
    metrics.f1        = 2 * metrics.precision * metrics.recall / max(metrics.precision + metrics.recall, eps);
    metrics.iou       = tp / max(tp + fp + fn, eps);
else
    metrics.precision = NaN;
    metrics.recall    = NaN;
    metrics.f1        = NaN;
    metrics.iou       = NaN;
end

% 2. Image Restoration Metrics vs Clean Ground Truth
if ~isempty(cleanImg) && ~isempty(restoredImg)
    % Whole-image PSNR
    diffRest = (restoredImg - cleanImg).^2;
    mseRest = mean(diffRest(:));
    metrics.psnr_whole = 10 * log10(1.0 / max(mseRest, 1e-10));
    
    % Baseline marked PSNR
    diffMark = (markedImg - cleanImg).^2;
    mseMark = mean(diffMark(:));
    metrics.psnr_baseline = 10 * log10(1.0 / max(mseMark, 1e-10));
    
    % In-mask PSNR (evaluated on dilated ground-truth mask)
    if ~isempty(gtAlpha)
        if islogical(gtAlpha)
            gtDil = imdilate(gtAlpha, strel('disk', 3));
        else
            gtDil = imdilate(gtAlpha > cfg.eval.maskAlphaMin, strel('disk', 3));
        end
        gtDil3 = repmat(gtDil, [1 1 size(cleanImg, 3)]);
        
        if any(gtDil3(:))
            mseMask = mean(diffRest(gtDil3));
            mseMarkMask = mean(diffMark(gtDil3));
            metrics.psnr_in_mask = 10 * log10(1.0 / max(mseMask, 1e-10));
            metrics.psnr_baseline_in_mask = 10 * log10(1.0 / max(mseMarkMask, 1e-10));
        else
            metrics.psnr_in_mask = metrics.psnr_whole;
            metrics.psnr_baseline_in_mask = metrics.psnr_baseline;
        end
    else
        metrics.psnr_in_mask = NaN;
        metrics.psnr_baseline_in_mask = NaN;
    end
    
    % SSIM
    metrics.ssim_whole = ssim(restoredImg, cleanImg);
else
    metrics.psnr_whole = NaN;
    metrics.psnr_baseline = NaN;
    metrics.psnr_in_mask = NaN;
    metrics.psnr_baseline_in_mask = NaN;
    metrics.ssim_whole = NaN;
end

% 3. Alpha Estimation Error
if ~isnan(a0Est) && ~isnan(a0True)
    metrics.a0_est   = a0Est;
    metrics.a0_true  = a0True;
    metrics.a0_error = abs(a0Est - a0True);
else
    metrics.a0_est   = a0Est;
    metrics.a0_true  = a0True;
    metrics.a0_error = NaN;
end

% 4. No-reference Quality Metrics (NIQE / BRISQUE)
if cfg.caps.hasNIQE
    try
        metrics.niqe = niqe(restoredImg);
    catch
        metrics.niqe = NaN;
    end
else
    metrics.niqe = NaN;
end

if cfg.caps.hasBRISQUE
    try
        metrics.brisque = brisque(restoredImg);
    catch
        metrics.brisque = NaN;
    end
else
    metrics.brisque = NaN;
end

end
