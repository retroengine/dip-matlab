function caps = preflight()
% PREFLIGHT Inspect MATLAB environment, toolboxes, and function availability.
% Saves environment capability struct to results/caps.mat and preflight.txt.

fprintf('=== PREFLIGHT CHECK: Visible Watermark Removal ===\n');

if ~exist('results', 'dir')
    mkdir('results');
end

% 1. MATLAB Version & Toolboxes
verInfo = ver;
vStr = version;
fprintf('MATLAB Version: %s\n', vStr);
fprintf('Installed Toolboxes (%d):\n', numel(verInfo));
for i = 1:numel(verInfo)
    fprintf('  - %s (%s)\n', verInfo(i).Name, verInfo(i).Version);
end

% 2. Required & Optional Functions
fns = { ...
    'inpaintCoherent', 'inpaintExemplar', 'regionfill', 'normxcorr2', ...
    'imgaussfilt', 'imtophat', 'imregionalmax', 'activecontour', ...
    'graythresh', 'adaptthresh', 'niqe', 'brisque', 'ssim', 'psnr', ...
    'detectMSERFeatures', 'insertText', 'exportgraphics', 'rgb2lab', 'tiledlayout' ...
};

fprintf('\nFunction Availability:\n');
statusMap = struct();
for i = 1:numel(fns)
    fn = fns{i};
    ex = exist(fn); %#ok<EXIST>
    statusMap.(fn) = ex;
    isAvail = (ex == 2 || ex == 5 || ex == 6);
    fprintf('  %-20s : exist=%d (%s)\n', fn, ex, ternary(isAvail, 'FOUND', 'MISSING'));
end

% 3. Build capabilities struct
caps = struct();
caps.matlabVersion = vStr;
caps.hasExemplar   = (exist('inpaintExemplar') > 0); %#ok<EXIST>
caps.hasCoherent   = (exist('inpaintCoherent') > 0); %#ok<EXIST>
caps.hasRegionfill = (exist('regionfill') > 0); %#ok<EXIST>
caps.hasMSER       = (exist('detectMSERFeatures') > 0); %#ok<EXIST>
caps.hasInsertText = (exist('insertText') > 0); %#ok<EXIST>
caps.hasNIQE       = (exist('niqe') > 0); %#ok<EXIST>
caps.hasBRISQUE    = (exist('brisque') > 0); %#ok<EXIST>
caps.hasSSIM       = (exist('ssim') > 0); %#ok<EXIST>
caps.hasPSNR       = (exist('psnr') > 0); %#ok<EXIST>
caps.hasExportGraphics = (exist('exportgraphics') > 0); %#ok<EXIST>
caps.hasTiledLayout    = (exist('tiledlayout') > 0); %#ok<EXIST>

save('results/caps.mat', 'caps');
fprintf('\nSaved capability struct to results/caps.mat\n');

% 4. Write results/preflight.txt
txtPath = fullfile('results', 'preflight.txt');
fid = fopen(txtPath, 'w');
if fid ~= -1
    fprintf(fid, 'MATLAB Version: %s\n\nToolboxes:\n', vStr);
    for i = 1:numel(verInfo)
        fprintf(fid, '  %s (%s)\n', verInfo(i).Name, verInfo(i).Version);
    end
    fprintf(fid, '\nFunction checks:\n');
    for i = 1:numel(fns)
        fn = fns{i};
        ex = statusMap.(fn);
        isAvail = (ex == 2 || ex == 5 || ex == 6);
        fprintf(fid, '  %-20s : exist=%d (%s)\n', fn, ex, ternary(isAvail, 'FOUND', 'MISSING'));
    end
    fprintf(fid, '\nCapabilities:\n');
    fnames = fieldnames(caps);
    for i = 1:numel(fnames)
        val = caps.(fnames{i});
        if islogical(val) || isnumeric(val)
            fprintf(fid, '  %-18s : %d\n', fnames{i}, val);
        else
            fprintf(fid, '  %-18s : %s\n', fnames{i}, string(val));
        end
    end
    fclose(fid);
    fprintf('Wrote report to %s\n', txtPath);
end

fprintf('=== PREFLIGHT COMPLETE ===\n');
end

function val = ternary(cond, trueVal, falseVal)
if cond
    val = trueVal;
else
    val = falseVal;
end
end
