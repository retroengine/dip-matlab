function caps = preflight()
% PREFLIGHT Inspect the MATLAB environment and function availability.
%
% Prints the MATLAB version, installed toolboxes and, for every function the
% pipeline uses, where it resolves from. Writes results/preflight.txt and
% results/caps.mat. Errors if the Image Processing Toolbox is missing.
%
% Output:
%   caps - Capability struct (same fields as config().caps)

root = setupPaths();
cfg = config();
outDir = cfg.paths.out;
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

lines = {};
lines{end+1} = sprintf('MATLAB Version: %s', version);
lines{end+1} = '';
lines{end+1} = 'Toolboxes:';
verInfo = ver;
for i = 1:numel(verInfo)
    lines{end+1} = sprintf('  %s (%s)', verInfo(i).Name, verInfo(i).Version); %#ok<AGROW>
end

fns = {'inpaintCoherent', 'inpaintExemplar', 'regionfill', 'normxcorr2', ...
       'imgaussfilt', 'imtophat', 'imregionalmax', 'activecontour', ...
       'graythresh', 'adaptthresh', 'edge', 'bwconncomp', 'regionprops', ...
       'niqe', 'brisque', 'ssim', 'psnr', 'detectMSERFeatures', 'insertText', ...
       'exportgraphics', 'rgb2lab', 'tiledlayout'};
lines{end+1} = '';
lines{end+1} = 'Function checks (exist code; resolved file):';
for i = 1:numel(fns)
    ex = exist(fns{i}); %#ok<EXIST>
    where = which(fns{i});
    if isempty(where)
        where = 'MISSING';
    end
    lines{end+1} = sprintf('  %-20s : %d  %s', fns{i}, ex, strrep(where, matlabroot, '<matlabroot>')); %#ok<AGROW>
end

caps = cfg.caps;
lines{end+1} = '';
lines{end+1} = 'Optional capabilities:';
fn = fieldnames(caps);
for i = 1:numel(fn)
    lines{end+1} = sprintf('  %-14s : %d', fn{i}, caps.(fn{i})); %#ok<AGROW>
end
lines{end+1} = '';
lines{end+1} = sprintf('Project root: %s', root);

txt = strjoin(lines, newline);
fprintf('%s\n', txt);
fid = fopen(fullfile(outDir, 'preflight.txt'), 'w');
fprintf(fid, '%s\n', txt);
fclose(fid);
save(fullfile(outDir, 'caps.mat'), 'caps');
end
