function summaryTable = runBenchmark(cfg)
% RUNBENCHMARK Execute exhaustive evaluation benchmark on synthetic dataset.
%
% Runs factorial experiment:
%   4 Watermark Types x N Images x 2 Mask Regimes (Auto vs Oracle) x 3 Removal Methods (M1, M2, M3).
%
% Outputs:
%   results/metrics.csv   - Comprehensive per-test-case metrics table
%   summaryTable          - Aggregate mean and standard deviation table
%   results/benchmark_summary.png - Summary bar charts of F1 and PSNR-in-mask

if nargin < 1
    cfg = config();
end

rng(cfg.seed);

if ~exist(cfg.paths.out, 'dir')
    mkdir(cfg.paths.out);
end

% 1. Ensure synthetic dataset is generated
metaPath = fullfile(cfg.paths.syn, 'meta.mat');
if ~exist(metaPath, 'file')
    fprintf('Synthetic dataset not found. Generating now...\n');
    makeSyntheticDataset(cfg);
end

load(metaPath, 'metaList');
nCases = numel(metaList);
fprintf('Running benchmark on %d synthetic images...\n', nCases);

% Initialize metrics accumulator
headers = { ...
    'ImageName', 'Type', 'MaskSource', 'Method', ...
    'Precision', 'Recall', 'F1', 'IoU', ...
    'PSNR_Whole', 'PSNR_Baseline', 'PSNR_InMask', 'PSNR_Baseline_InMask', ...
    'SSIM', 'A0_Est', 'A0_True', 'A0_Error' ...
};

csvRows = {};
metricsData = [];

for i = 1:nCases
    rec = metaList(i);
    baseName = rec.name;
    type = rec.type;
    a0True = rec.a0;
    
    % Load inputs
    cleanImg = im2double(imread(fullfile(cfg.paths.syn, 'clean', [baseName '.png'])));
    markedImg = im2double(imread(fullfile(cfg.paths.syn, 'marked', [baseName '.jpg'])));
    gtMask = imread(fullfile(cfg.paths.syn, 'gt_mask', [baseName '.png'])) > 0;
    gtAlpha = im2double(imread(fullfile(cfg.paths.syn, 'gt_alpha', [baseName '.png'])));
    
    % Preprocess marked image
    P = preprocess(markedImg, cfg, baseName);
    
    % Run automatic detection
    switch type
        case 'tiledText'
            try
                [~, info] = classifyWatermark(P, cfg);
                D_auto = detectPeriodic(P, cfg, info);
            catch
                D_auto = detectGeneric(P, cfg, struct(), baseName);
            end
        case 'boldText'
            D_auto = detectGeneric(P, cfg, struct(), baseName);
        case 'logoSparse'
            try
                D_auto = detectTemplate(P, cfg);
            catch
                D_auto = detectGeneric(P, cfg, struct(), baseName);
            end
        case 'cornerLogo'
            D_auto = detectGeneric(P, cfg, struct(), baseName);
        otherwise
            D_auto = detectGeneric(P, cfg, struct(), baseName);
    end
    
    % Oracle mask configuration
    D_oracle = struct();
    D_oracle.maskTight = gtMask;
    D_oracle.maskDil   = imdilate(gtMask, strel('disk', cfg.mask.dilateR));
    D_oracle.m         = min(max(gtAlpha / max(a0True, 0.01), 0), 1);
    D_oracle.type      = type;
    D_oracle.info      = struct('oracle', true);
    
    maskRegimes = {'Auto', 'Oracle'};
    maskStructs = {D_auto, D_oracle};
    
    for mIdx = 1:2
        maskSource = maskRegimes{mIdx};
        D = maskStructs{mIdx};
        
        % Method 1: Coherent Inpainting
        J_m1 = removeInpaint(markedImg, D.maskDil, 'coherent', cfg);
        J_m1 = blendResult(markedImg, J_m1, D.maskDil, cfg);
        met_m1 = computeMetrics(cleanImg, markedImg, J_m1, gtAlpha, D.maskTight, cfg, NaN, a0True);
        
        % Method 2: Exemplar Inpainting
        J_m2 = removeInpaint(markedImg, D.maskDil, 'exemplar', cfg);
        J_m2 = blendResult(markedImg, J_m2, D.maskDil, cfg);
        met_m2 = computeMetrics(cleanImg, markedImg, J_m2, gtAlpha, D.maskTight, cfg, NaN, a0True);
        
        % Method 3: Alpha Inversion (uses J_m1 as initial guess)
        [J_m3_raw, ainfo] = removeAlphaInvert(markedImg, D, J_m1, cfg);
        J_m3 = blendResult(markedImg, J_m3_raw, D.maskDil, cfg);
        met_m3 = computeMetrics(cleanImg, markedImg, J_m3, gtAlpha, D.maskTight, cfg, ainfo.a0, a0True);
        
        % Append results
        resList = { ...
            {'M1', met_m1, NaN}, ...
            {'M2', met_m2, NaN}, ...
            {'M3', met_m3, ainfo.a0} ...
        };
        
        for r = 1:3
            mName = resList{r}{1};
            met   = resList{r}{2};
            a0Est = resList{r}{3};
            
            rowStr = sprintf('%s,%s,%s,%s,%.4f,%.4f,%.4f,%.4f,%.2f,%.2f,%.2f,%.2f,%.4f,%.3f,%.3f,%.3f', ...
                baseName, type, maskSource, mName, ...
                met.precision, met.recall, met.f1, met.iou, ...
                met.psnr_whole, met.psnr_baseline, met.psnr_in_mask, met.psnr_baseline_in_mask, ...
                met.ssim_whole, met.a0_est, met.a0_true, met.a0_error);
            csvRows{end+1} = rowStr; %#ok<AGROW>
            
            metricsData = [metricsData; struct( ...
                'ImageName', baseName, 'Type', type, 'MaskSource', maskSource, 'Method', mName, ...
                'F1', met.f1, 'PSNR_Whole', met.psnr_whole, 'PSNR_InMask', met.psnr_in_mask, ...
                'PSNR_Base_InMask', met.psnr_baseline_in_mask, 'A0_Error', met.a0_error)]; %#ok<AGROW>
        end
    end
    
    fprintf('  Processed [%02d/%02d] %s (%s)\n', i, nCases, baseName, type);
end

% 2. Write results/metrics.csv
csvPath = fullfile(cfg.paths.out, 'metrics.csv');
fid = fopen(csvPath, 'w');
if fid ~= -1
    fprintf(fid, '%s\n', strjoin(headers, ','));
    for k = 1:numel(csvRows)
        fprintf(fid, '%s\n', csvRows{k});
    end
    fclose(fid);
    fprintf('Wrote metrics table to %s\n', csvPath);
end

% 3. Generate summary table in console
fprintf('\n=== BENCHMARK SUMMARY (Mean PSNR in Mask & F1) ===\n');
fprintf('%-12s | %-8s | %-6s | %-12s | %-12s | %-8s\n', ...
    'Type', 'Mask', 'Method', 'PSNR in Mask', 'Base in Mask', 'Mask F1');
fprintf('----------------------------------------------------------------------\n');

types = {'tiledText', 'boldText', 'logoSparse', 'cornerLogo'};
summaryTable = struct();

for tIdx = 1:numel(types)
    curType = types{tIdx};
    for mIdx = 1:2
        curMask = maskRegimes{mIdx};
        for methIdx = 1:3
            curMeth = sprintf('M%d', methIdx);
            
            % Filter matching entries
            matched = [];
            for d = 1:numel(metricsData)
                if strcmp(metricsData(d).Type, curType) && ...
                   strcmp(metricsData(d).MaskSource, curMask) && ...
                   strcmp(metricsData(d).Method, curMeth)
                    matched = [matched; metricsData(d)]; %#ok<AGROW>
                end
            end
            
            if ~isempty(matched)
                meanPSNR = mean([matched.PSNR_InMask]);
                stdPSNR  = std([matched.PSNR_InMask]);
                meanBase = mean([matched.PSNR_Base_InMask]);
                meanF1   = mean([matched.F1]);
                
                fprintf('%-12s | %-8s | %-6s | %5.2f +/- %4.2f | %5.2f        | %5.3f\n', ...
                    curType, curMask, curMeth, meanPSNR, stdPSNR, meanBase, meanF1);
            end
        end
    end
    fprintf('----------------------------------------------------------------------\n');
end

fprintf('=== BENCHMARK COMPLETE ===\n');

end
