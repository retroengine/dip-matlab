function hint = loadHint(cfg, imgName)
% LOADHINT Read the optional per-image hint from data/real/hints.json.
%
% Inputs:
%   cfg     - Configuration struct (cfg.paths.real)
%   imgName - Image base name (extension is ignored)
%
% Output:
%   hint    - Struct with optional fields 'roi', 'search_box' ([x y w h] rows,
%             1-based) and 'mask' (region drawn with selectRegion); empty struct
%             when there is no hint for this image.

hint = struct();
if nargin < 2 || isempty(imgName)
    return;
end
[~, baseName] = fileparts(imgName);

% Region drawn with selectRegion.m: data/real/masks_user/<name>.png
userMask = fullfile(cfg.paths.real, 'masks_user', [baseName '.png']);
if exist(userMask, 'file')
    hint.mask = imread(userMask) > 0;
end

hintsFile = fullfile(cfg.paths.real, 'hints.json');
if exist(hintsFile, 'file')
    try
        hints = jsondecode(fileread(hintsFile));
        key = matlab.lang.makeValidName(baseName);   % jsondecode renames e.g. 'img-4' to 'img_4'
        if isfield(hints, key)
            f = fieldnames(hints.(key));
            for k = 1:numel(f)
                hint.(f{k}) = hints.(key).(f{k});
            end
        end
    catch ME
        warning('loadHint:parse', 'hints.json could not be parsed: %s', ME.message);
    end
end
end
