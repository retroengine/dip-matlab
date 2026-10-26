function hint = loadHint(cfg, imgName)
% LOADHINT Read the optional per-image hint from data/real/hints.json.
%
% Inputs:
%   cfg     - Configuration struct (cfg.paths.real)
%   imgName - Image base name (extension is ignored)
%
% Output:
%   hint    - Struct with optional fields 'roi' and 'search_box' ([x y w h],
%             1-based); empty struct when there is no hint for this image.

hint = struct();
if nargin < 2 || isempty(imgName)
    return;
end
hintsFile = fullfile(cfg.paths.real, 'hints.json');
if ~exist(hintsFile, 'file')
    return;
end
try
    hints = jsondecode(fileread(hintsFile));
catch ME
    warning('loadHint:parse', 'hints.json could not be parsed: %s', ME.message);
    return;
end
[~, baseName] = fileparts(imgName);
if isfield(hints, baseName)
    hint = hints.(baseName);
end
end
