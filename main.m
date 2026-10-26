function exitCode = main(inputDir, varargin)
% MAIN Entry point for visible watermark detection and removal pipeline.
%
% Usage:
%   main('data/real')
%   main('data/real', 'only', 'w4_luke_logo')
%
% Pipeline per image:
%   1. Read & Preprocess (ROI exclusion, high-pass filtering)
%   2. Classify ('periodic', 'sparse', 'single')
%   3. Detect (detectPeriodic, detectTemplate, or detectGeneric)
%   4. Refine (maskTight, maskDil, soft coverage m)
%   5. Removal:
%      - Method 1: Coherent inpainting
%      - Method 2: Exemplar inpainting
%      - Method 3: Alpha inversion
%   6. Blend & Auto-select recommended method
%   7. Export mask.png, overlay.png, m1.png, m2.png, m3.png, recommended.png,
%      info.json, and results/comparison_<name>.png
%
% Returns:
%   exitCode - 0 if all images succeeded, 1 if any image threw an unhandled error.

if nargin < 1 || isempty(inputDir)
    inputDir = fullfile('data', 'real');
end

% Parse optional parameters
p = inputParser;
addParameter(p, 'only', '', @(x) ischar(x) || isstring(x));
parse(p, varargin{:});
onlyFilter = char(p.Results.only);

setupPaths();
cfg = config();
rng(cfg.seed);

if ~exist(cfg.paths.out, 'dir')
    mkdir(cfg.paths.out);
end

% Collect input image files
fileList = dir(fullfile(inputDir, '*.jpg'));
fileList = [fileList; dir(fullfile(inputDir, '*.png'))];
fileList = [fileList; dir(fullfile(inputDir, '*.jpeg'))];

if ~isempty(onlyFilter)
    matched = [];
    for k = 1:numel(fileList)
        [~, bName, ~] = fileparts(fileList(k).name);
        if contains(bName, onlyFilter)
            matched = [matched; fileList(k)]; %#ok<AGROW>
        end
    end
    fileList = matched;
end

if isempty(fileList)
    fprintf('No images found in "%s" matching filter "%s".\n', inputDir, onlyFilter);
    exitCode = 0;
    return;
end

fprintf('=== Running Watermark Detection & Removal Pipeline ===\n');
fprintf('Input folder: %s (%d images)\n', inputDir, numel(fileList));

errorLogPath = fullfile(cfg.paths.out, 'errors.log');
fclose(fopen(errorLogPath, 'w'));   % truncate: log only this run's errors
numErrors = 0;

for k = 1:numel(fileList)
    imgFile = fileList(k);
    [~, baseName, ext] = fileparts(imgFile.name);
    imgPath = fullfile(inputDir, imgFile.name);
    
    outDir = fullfile(cfg.paths.out, baseName);
    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end
    
    try
        fprintf('\n[%d/%d] Processing %s...\n', k, numel(fileList), imgFile.name);
        
        % 1. Read & Preprocess
        rawImg = imread(imgPath);
        P = preprocess(rawImg, cfg, baseName);
        
        % 2. Classify
        [wmType, classInfo] = classifyWatermark(P, cfg);
        
        % 3. Detect according to classified type
        switch wmType
            case 'periodic'
                D = detectPeriodic(P, cfg, classInfo);
            case 'sparse'
                D = detectTemplate(P, cfg, classInfo);
            case 'single'
                D = detectGeneric(P, cfg, classInfo, baseName);
            otherwise
                D = detectGeneric(P, cfg, classInfo, baseName);
        end
        
        % 4. Removal: Method 1 (Coherent)
        J_m1_raw = removeInpaint(P.I, D.maskDil, 'coherent', cfg);
        J_m1 = blendResult(P.I, J_m1_raw, D.maskDil, cfg);
        
        % 5. Removal: Method 2 (Exemplar)
        J_m2_raw = removeInpaint(P.I, D.maskDil, 'exemplar', cfg);
        J_m2 = blendResult(P.I, J_m2_raw, D.maskDil, cfg);
        
        % 6. Removal: Method 3 (Alpha Inversion using M1 as initial clean guess)
        [J_m3_raw, ainfo] = removeAlphaInvert(P.I, D, J_m1_raw, cfg);
        J_m3 = blendResult(P.I, J_m3_raw, D.maskDil, cfg);
        
        % 7. Auto-selection rule (Section 8.5)
        switch wmType
            case 'periodic'
                if ainfo.reliable
                    recMethod = 'M3 (Alpha Inversion)';
                    recImg = J_m3;
                    rule = 'periodic with reliable edge-cancellation alpha inversion';
                else
                    recMethod = 'M1 (Coherent Inpaint)';
                    recImg = J_m1;
                    rule = 'periodic with unreliable alpha inversion -> coherent fallback';
                end
            case 'sparse'
                if ainfo.reliable
                    recMethod = 'M3 (Alpha Inversion)';
                    recImg = J_m3;
                    rule = 'sparse repeats with reliable alpha inversion';
                else
                    recMethod = 'M2 (Exemplar Inpaint)';
                    recImg = J_m2;
                    rule = 'sparse repeats with unreliable alpha -> exemplar fallback';
                end
            case 'single'
                recMethod = 'M2 (Exemplar Inpaint)';
                recImg = J_m2;
                rule = 'single/bold localized watermark -> exemplar inpainting';
        end
        
        % 8. Render Overlay & Comparison
        overlayImg = overlayMask(P.I, D.maskTight, [1 0 0], 0.55);
        compPath = fullfile(cfg.paths.out, sprintf('comparison_%s.png', baseName));
        metaInfo = struct('type', wmType, 'recommended', recMethod);
        makeComparison(P.I, overlayImg, J_m1, J_m2, J_m3, compPath, metaInfo);
        
        % 9. Export per-image artifacts
        imwrite(D.maskTight, fullfile(outDir, 'mask.png'));
        imwrite(overlayImg, fullfile(outDir, 'overlay.png'));
        imwrite(J_m1, fullfile(outDir, 'm1.png'));
        imwrite(J_m2, fullfile(outDir, 'm2.png'));
        imwrite(J_m3, fullfile(outDir, 'm3.png'));
        imwrite(recImg, fullfile(outDir, 'recommended.png'));
        
        % 10. Save metadata info.json
        infoStruct = struct();
        infoStruct.name = baseName;
        infoStruct.type = wmType;
        infoStruct.recommended_method = recMethod;
        infoStruct.selection_rule = rule;
        infoStruct.alpha_estimated = ainfo.a0;
        infoStruct.alpha_initial = ainfo.a_init;
        infoStruct.alpha_reliable = ainfo.reliable;
        infoStruct.mask_pixels = sum(D.maskTight(:));
        hint = loadHint(cfg, baseName);
        infoStruct.hint_used = ~isempty(fieldnames(hint)) && (isfield(hint, 'roi') || isfield(hint, 'search_box'));
        infoStruct.image_size = size(P.I);
        
        if isfield(D.info, 'instanceCount')
            infoStruct.instances_found = D.info.instanceCount;
        end
        
        infoJson = jsonencode(infoStruct);
        fid = fopen(fullfile(outDir, 'info.json'), 'w');
        if fid ~= -1
            fprintf(fid, '%s\n', infoJson);
            fclose(fid);
        end
        
        % One-line summary
        instStr = '';
        if isfield(D.info, 'instanceCount')
            instStr = sprintf(', instances=%d', D.info.instanceCount);
        end
        fprintf('  -> Summary: type=%s%s, a0=%.3f (reliable=%d) => %s\n', ...
            wmType, instStr, ainfo.a0, ainfo.reliable, recMethod);
        
    catch ME
        numErrors = numErrors + 1;
        errMsg = sprintf('[ERROR] %s: %s (in %s at line %d)', ...
            baseName, ME.message, ME.stack(1).name, ME.stack(1).line);
        fprintf(2, '  %s\n', errMsg);
        
        fidErr = fopen(errorLogPath, 'a');
        if fidErr ~= -1
            fprintf(fidErr, '%s\n', errMsg);
            fclose(fidErr);
        end
    end
end

if numErrors > 0
    fprintf('\nFinished with %d errors. See %s for details.\n', numErrors, errorLogPath);
    exitCode = 1;
else
    fprintf('\nAll images processed successfully.\n');
    exitCode = 0;
end

end
