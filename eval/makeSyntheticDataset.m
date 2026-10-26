function makeSyntheticDataset(cfg)
% MAKESYNTHETICDATASET Generate synthetic watermark benchmark dataset.
%
% Synthesizes four watermark categories across clean source images:
%   1. 'tiledText'  - Rotated periodic text lattice across the entire image
%   2. 'boldText'   - Single bold text banner
%   3. 'logoSparse' - 5 to 8 repeated logo instances
%   4. 'cornerLogo' - Single logo positioned at bottom-right corner
%
% Saves:
%   data/synthetic/clean/    - Original clean photos
%   data/synthetic/marked/   - Watermarked images (JPEG Q90)
%   data/synthetic/gt_mask/  - Ground truth binary masks
%   data/synthetic/gt_alpha/ - Ground truth continuous alpha opacity maps
%   data/synthetic/meta.mat  - Ground truth metadata (a0, type, W, filenames)

if nargin < 1
    cfg = config();
end

rng(cfg.seed);

dirs = {
    fullfile(cfg.paths.syn, 'clean'), ...
    fullfile(cfg.paths.syn, 'marked'), ...
    fullfile(cfg.paths.syn, 'gt_mask'), ...
    fullfile(cfg.paths.syn, 'gt_alpha')
};
for i = 1:numel(dirs)
    if ~exist(dirs{i}, 'dir')
        mkdir(dirs{i});
    end
end

% 1. Gather clean source images
cleanImages = {};
userCleanDir = cfg.paths.clean;
if exist(userCleanDir, 'dir')
    cleanFiles = dir(fullfile(userCleanDir, '*.jpg'));
    cleanFiles = [cleanFiles; dir(fullfile(userCleanDir, '*.png'))];
    for k = 1:numel(cleanFiles)
        cleanImages{end+1} = im2double(imread(fullfile(userCleanDir, cleanFiles(k).name))); %#ok<AGROW>
    end
end

% If no user clean images, query MATLAB sample images
if isempty(cleanImages)
    imdataDir = fullfile(matlabroot, 'toolbox', 'images', 'imdata');
    if exist(imdataDir, 'dir')
        candidates = {'peppers.png', 'fabric.png', 'greens.jpg', 'flowers.tif', 'canoe.tif', 'autumn.tif'};
        for k = 1:numel(candidates)
            cPath = fullfile(imdataDir, candidates{k});
            if exist(cPath, 'file')
                try
                    im = im2double(imread(cPath));
                    if size(im, 3) == 3 && size(im, 1) >= 250 && size(im, 2) >= 250
                        cleanImages{end+1} = im; %#ok<AGROW>
                    end
                catch
                end
            end
        end
    end
end

% If still empty, synthesize realistic photographic texture canvases
if isempty(cleanImages)
    cleanImages = synthesizeCleanCanvases(6);
end

% Expand to target dataset count via crops and transforms
nTarget = cfg.eval.nImages;
sources = {};
idx = 1;
while numel(sources) < nTarget
    srcImg = cleanImages{mod(idx - 1, numel(cleanImages)) + 1};
    [sH, sW, ~] = size(srcImg);
    
    % Crop standard 400x400 patches with jitter
    cropH = min(sH, 380);
    cropW = min(sW, 480);
    
    rOffset = randi([0, max(0, sH - cropH)]);
    cOffset = randi([0, max(0, sW - cropW)]);
    
    crop = srcImg(rOffset+1:rOffset+cropH, cOffset+1:cOffset+cropW, :);
    if rand() > 0.5
        crop = fliplr(crop);
    end
    sources{end+1} = crop; %#ok<AGROW>
    idx = idx + 1;
end

% 2. Synthesize watermarked images
types = {'tiledText', 'boldText', 'logoSparse', 'cornerLogo'};
metaList = [];

fprintf('Generating %d synthetic benchmark images...\n', nTarget);

for i = 1:nTarget
    cleanImg = sources{i};
    [H, W, ~] = size(cleanImg);
    
    type = types{mod(i - 1, numel(types)) + 1};
    a0 = 0.20 + 0.30 * rand(); % Randomized opacity in [0.20, 0.50]
    W_color = cfg.alpha.W;      % Default white [1 1 1]
    
    switch type
        case 'tiledText'
            % Rotated periodic lattice
            textStr = 'CONFIDENTIAL';
            angle = -25 + 10 * (rand() - 0.5);
            glyphH = 28; glyphW = 120;
            patchM = renderTextMask(textStr, [glyphH, glyphW], angle, 16);
            
            % Lattice step
            stepX = glyphW + 40;
            stepY = glyphH + 50;
            m = zeros(H, W);
            
            row = 0;
            for y = 10:stepY:H
                stagger = mod(row, 2) * (stepX / 2);
                for x = (10 - stepX):stepX:W
                    px = round(x + stagger);
                    py = round(y);
                    
                    x1 = max(1, px); y1 = max(1, py);
                    x2 = min(W, px + glyphW - 1); y2 = min(H, py + glyphH - 1);
                    
                    if x1 <= x2 && y1 <= y2
                        pX1 = x1 - px + 1; pY1 = y1 - py + 1;
                        pX2 = pX1 + (x2 - x1); pY2 = pY1 + (y2 - y1);
                        m(y1:y2, x1:x2) = max(m(y1:y2, x1:x2), patchM(pY1:pY2, pX1:pX2));
                    end
                end
                row = row + 1;
            end
            
        case 'boldText'
            % Single bold text banner
            str = 'PROOF PROOF PROOF';
            bannerH = 45;
            bannerW = min(W - 20, 400);
            bannerM = renderTextMask(str, [bannerH, bannerW], 0, 32);
            
            m = zeros(H, W);
            yStart = round(H * 0.75);
            xStart = max(1, round((W - bannerW) / 2));
            
            yEnd = min(H, yStart + bannerH - 1);
            xEnd = min(W, xStart + bannerW - 1);
            
            m(yStart:yEnd, xStart:xEnd) = bannerM(1:(yEnd-yStart+1), 1:(xEnd-xStart+1));
            
        case 'logoSparse'
            % 5 to 7 repeated logo instances
            numInstances = randi([5, 7]);
            m = zeros(H, W);
            logoH = 40; logoW = 75;
            logoM = renderLogoMask([logoH, logoW], 'LOGO');
            
            for k = 1:numInstances
                lx = randi([15, max(16, W - logoW - 15)]);
                ly = randi([15, max(16, H - logoH - 15)]);
                
                x1 = lx; y1 = ly;
                x2 = lx + logoW - 1; y2 = ly + logoH - 1;
                m(y1:y2, x1:x2) = max(m(y1:y2, x1:x2), logoM);
            end
            
        case 'cornerLogo'
            % Single logo at bottom right corner
            logoH = 50; logoW = 110;
            logoM = renderLogoMask([logoH, logoW], 'STUDIO X');
            
            m = zeros(H, W);
            yStart = max(1, H - logoH - 20);
            xStart = max(1, W - logoW - 20);
            yEnd = yStart + logoH - 1;
            xEnd = xStart + logoW - 1;
            
            m(yStart:yEnd, xStart:xEnd) = logoM;
    end
    
    m = min(max(m, 0), 1);
    gt_mask = m > cfg.eval.maskAlphaMin;
    gt_alpha = a0 * m;
    
    % Optical overlay composition: I = (1 - a0*m).*J + a0*m.*W
    W3 = reshape(W_color, 1, 1, 3);
    marked = (1 - gt_alpha) .* cleanImg + gt_alpha .* W3;
    marked = min(max(marked, 0), 1);
    
    % Save clean image
    baseName = sprintf('syn_%03d_%s', i, type);
    cleanPath = fullfile(cfg.paths.syn, 'clean', [baseName '.png']);
    imwrite(cleanImg, cleanPath);
    
    % Save marked image as JPEG with Quality 90 to mimic real-world compression
    markedJpgPath = fullfile(cfg.paths.syn, 'marked', [baseName '.jpg']);
    imwrite(marked, markedJpgPath, 'Quality', 90);
    marked = im2double(imread(markedJpgPath)); % Read back to retain JPEG compression artifacts
    
    % Save GT masks
    imwrite(gt_mask, fullfile(cfg.paths.syn, 'gt_mask', [baseName '.png']));
    imwrite(gt_alpha, fullfile(cfg.paths.syn, 'gt_alpha', [baseName '.png']));
    
    % Append metadata
    rec = struct();
    rec.index = i;
    rec.name = baseName;
    rec.type = type;
    rec.a0 = a0;
    rec.W = W_color;
    rec.H = H;
    rec.W_px = W;
    metaList = [metaList; rec]; %#ok<AGROW>
end

metaFile = fullfile(cfg.paths.syn, 'meta.mat');
save(metaFile, 'metaList');
fprintf('Saved synthetic dataset and metadata to %s\n', metaFile);

end

function imgs = synthesizeCleanCanvases(n)
imgs = cell(n, 1);
for k = 1:n
    H = 380; W = 480;
    [X, Y] = meshgrid(linspace(0, 1, W), linspace(0, 1, H));
    
    % Multi-frequency harmonic background textures simulating scenery/sky/landscape
    switch mod(k, 3)
        case 0 % Smooth sky/ocean gradient with fine ripples
            R = 0.2 + 0.6 * Y + 0.05 * sin(12 * X);
            G = 0.4 + 0.4 * Y + 0.05 * cos(8 * Y);
            B = 0.6 + 0.3 * (1 - Y);
        case 1 % Foliage texture with high spatial frequencies
            noise = sin(25 * X) .* cos(30 * Y) + 0.5 * sin(50 * X + 40 * Y);
            R = 0.25 + 0.15 * noise;
            G = 0.55 + 0.25 * noise;
            B = 0.20 + 0.10 * noise;
        case 2 % Urban/architectural geometric textures
            stripes = 0.5 + 0.4 * sign(sin(2 * pi * 8 * X));
            R = 0.65 * stripes + 0.2 * Y;
            G = 0.55 * stripes + 0.2 * (1 - X);
            B = 0.50 * stripes + 0.3 * Y;
    end
    
    canvas = cat(3, R, G, B);
    imgs{k} = min(max(canvas, 0), 1);
end
end
