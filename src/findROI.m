function valid = findROI(imgGray, cfg, imgName)
% FINDROI Detect and exclude flat frames, drop shadows, and solid borders.
%
% Inputs:
%   imgGray - 2D double grayscale image in [0, 1]
%   cfg     - Configuration struct (cfg.roi)
%   imgName - (Optional) base filename to check against data/real/hints.json
%
% Output:
%   valid   - 2D logical mask, true for real photo content, false for borders

if nargin < 3
    imgName = '';
end

[H, W] = size(imgGray);
valid = true(H, W);

% 1. Check for manual override hint in hints.json
hintsFile = fullfile('data', 'real', 'hints.json');
if ~isempty(imgName) && exist(hintsFile, 'file')
    try
        hintsText = fileread(hintsFile);
        hints = jsondecode(hintsText);
        [~, baseName, ~] = fileparts(imgName);
        if isfield(hints, baseName) && isfield(hints.(baseName), 'roi')
            roiBox = hints.(baseName).roi; % [x, y, width, height]
            x1 = max(1, round(roiBox(1)));
            y1 = max(1, round(roiBox(2)));
            x2 = min(W, round(roiBox(1) + roiBox(3) - 1));
            y2 = min(H, round(roiBox(2) + roiBox(4) - 1));
            
            valid = false(H, W);
            valid(y1:y2, x1:x2) = true;
            return;
        end
    catch ME
        warning('findROI:hintsError', 'Failed to read hints.json: %s', ME.message);
    end
end

% 2. Automatic frame detection
% Analyze standard deviation of border rows and columns
stdThresh  = cfg.roi.stdThresh;
maxFramePx = cfg.roi.maxFramePx;
shadowPx   = cfg.roi.shadowPx;

topStrip = 0;
for r = 1:min(maxFramePx, floor(H/4))
    lineStd = std(imgGray(r, :));
    lineMean = mean(imgGray(r, :));
    if lineStd < stdThresh || (lineMean > 0.96 && lineStd < 0.03) || (lineMean < 0.05 && lineStd < 0.03)
        topStrip = r;
    else
        break;
    end
end

bottomStrip = 0;
for r = 1:min(maxFramePx, floor(H/4))
    rowIdx = H - r + 1;
    lineStd = std(imgGray(rowIdx, :));
    lineMean = mean(imgGray(rowIdx, :));
    if lineStd < stdThresh || (lineMean > 0.96 && lineStd < 0.03) || (lineMean < 0.05 && lineStd < 0.03)
        bottomStrip = r;
    else
        break;
    end
end

leftStrip = 0;
for c = 1:min(maxFramePx, floor(W/4))
    lineStd = std(imgGray(:, c));
    lineMean = mean(imgGray(:, c));
    if lineStd < stdThresh || (lineMean > 0.96 && lineStd < 0.03) || (lineMean < 0.05 && lineStd < 0.03)
        leftStrip = c;
    else
        break;
    end
end

rightStrip = 0;
for c = 1:min(maxFramePx, floor(W/4))
    colIdx = W - c + 1;
    lineStd = std(imgGray(:, colIdx));
    lineMean = mean(imgGray(:, colIdx));
    if lineStd < stdThresh || (lineMean > 0.96 && lineStd < 0.03) || (lineMean < 0.05 && lineStd < 0.03)
        rightStrip = c;
    else
        break;
    end
end

% Apply shadow padding if a frame was detected on that side
if topStrip > 0,    topStrip    = min(floor(H/3), topStrip + shadowPx); end
if bottomStrip > 0, bottomStrip = min(floor(H/3), bottomStrip + shadowPx); end
if leftStrip > 0,   leftStrip   = min(floor(W/3), leftStrip + shadowPx); end
if rightStrip > 0,  rightStrip  = min(floor(W/3), rightStrip + shadowPx); end

y1 = topStrip + 1;
y2 = H - bottomStrip;
x1 = leftStrip + 1;
x2 = W - rightStrip;

if y1 <= y2 && x1 <= x2
    valid = false(H, W);
    valid(y1:y2, x1:x2) = true;
end

end
