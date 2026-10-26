function root = setupPaths()
% SETUPPATHS Add project folders to the MATLAB path (works from any cwd) and
% check that the Image Processing Toolbox is installed.
%
% Output:
%   root - absolute path of the project root

root = fileparts(mfilename('fullpath'));
addpath(root, fullfile(root, 'src'), fullfile(root, 'src', 'viz'), fullfile(root, 'eval'));

if isempty(ver('images'))
    error('setupPaths:noIPT', ...
        'The Image Processing Toolbox is required (Home > Add-Ons > Get Add-Ons).');
end
end
