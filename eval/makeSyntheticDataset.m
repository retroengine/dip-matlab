function makeSyntheticDataset(cfg)
% MAKESYNTHETICDATASET Generate the synthetic watermark benchmark.
%
% Clean sources: data/clean/* if present, otherwise the RGB sample photos
% shipped with the Image Processing Toolbox (>= 300x300, charts / medical /
% microscopy images excluded). Each source is resized so its long side is
% cfg.syn.longSide and a random crop of cfg.syn.cropSize is taken.
%
% Four watermark types, cycled over the images (a0 ~ U[0.2, 0.5], white):
%   'tiledText'  - rotated text on a (staggered) lattice      (like w1, w2)
%   'boldText'   - one band of bold text near the bottom       (like w3)
%   'logoSparse' - 5-8 non-overlapping logo instances          (like w4)
%   'cornerLogo' - one logo in the bottom-right corner         (like w5)
%
% Composition: I = (1 - a0*m).*J + a0*m.*W, then JPEG quality 90.
% Writes data/synthetic/{clean,marked,gt_mask,gt_alpha}/ and meta.mat.

if nargin < 1
    cfg = config();
end
rng(cfg.seed);

sub = {'clean', 'marked', 'gt_mask', 'gt_alpha'};
for i = 1:numel(sub)
    d = fullfile(cfg.paths.syn, sub{i});
    if exist(d, 'dir')
        delete(fullfile(d, '*'));
    else
        mkdir(d);
    end
end

sources = loadSources(cfg);
fprintf('Using %d clean source photos.\n', numel(sources));

types = {'tiledText', 'boldText', 'logoSparse', 'cornerLogo'};
texts = {'SAMPLE TEXT', 'CONFIDENTIAL', 'PREVIEW', 'COPYRIGHT'};
captions = {'STUDIO', 'PHOTO CO', 'LOGO'};
nTarget = cfg.eval.nImages;
metaList = [];

for i = 1:nTarget
    src = sources{mod(i - 1, numel(sources)) + 1};
    J = randomCrop(src, cfg.syn.cropSize);
    if rand() > 0.5
        J = fliplr(J);
    end
    [H, W, ~] = size(J);
    type = types{mod(i - 1, numel(types)) + 1};
    a0 = 0.20 + 0.30 * rand();
    rec = struct('index', i, 'type', type, 'a0', a0, 'W', cfg.alpha.W, ...
                 'lattice', [], 'boxes', []);

    m = zeros(H, W);
    switch type
        case 'tiledText'
            str = texts{randi(numel(texts))};
            ang = (20 + 15 * rand()) * sign(rand() - 0.5);
            stamp = renderTextMask(str, [], ang, round(H * (0.045 + 0.02 * rand())));
            [sh, sw] = size(stamp);
            a1 = [sw + round(sw * (0.15 + 0.3 * rand())), 0];
            stagger = rand() > 0.5;
            a2 = [stagger * round(a1(1) / 2), sh + round(sh * (0.2 + 0.4 * rand()))];
            origin = [randi(a1(1)), randi(a2(2))] - [a1(1), a2(2)];
            for v = -2:ceil(H / a2(2)) + 2
                for u = -2:ceil(W / a1(1)) + 2
                    pos = round(origin + u * a1 + v * a2);
                    m = pasteMax(m, stamp, pos(1), pos(2));
                end
            end
            rec.lattice = [a1; a2];

        case 'boldText'
            fs = round(H * (0.09 + 0.04 * rand()));
            band = renderTextMask('PROOF PROOF PROOF', [], 0, fs);
            band = fitWidth(band, 0.9 * W);
            x = round((W - size(band, 2)) / 2) + randi([-10 10]);
            y = round(H * (0.70 + 0.12 * rand())) - size(band, 1);
            m = pasteMax(m, band, x, y);
            rec.boxes = [x, y, size(band, 2), size(band, 1)];

        case 'logoSparse'
            lh = round(H * (0.10 + 0.04 * rand()));
            logo = renderLogoMask([lh, round(lh * 1.9)], captions{randi(numel(captions))});
            n = randi([5, 8]);
            boxes = zeros(0, 4);
            tries = 0;
            while size(boxes, 1) < n && tries < 500
                tries = tries + 1;
                x = randi([1, W - size(logo, 2)]);
                y = randi([1, H - size(logo, 1)]);
                b = [x, y, size(logo, 2), size(logo, 1)];
                if ~any(boxOverlap(boxes, b, 6))
                    boxes = [boxes; b]; %#ok<AGROW>
                    m = pasteMax(m, logo, x, y);
                end
            end
            rec.boxes = boxes;

        case 'cornerLogo'
            lh = round(H * (0.13 + 0.05 * rand()));
            logo = renderLogoMask([lh, round(lh * 2.2)], 'STUDIO X');
            x = W - size(logo, 2) - round(W * (0.02 + 0.04 * rand()));
            y = H - size(logo, 1) - round(H * (0.03 + 0.05 * rand()));
            m = pasteMax(m, logo, x, y);
            rec.boxes = [x, y, size(logo, 2), size(logo, 1)];
    end

    m = min(max(m, 0), 1);
    alpha = a0 * m;
    W3 = reshape(cfg.alpha.W, 1, 1, 3);
    marked = min(max((1 - alpha) .* J + alpha .* W3, 0), 1);

    name = sprintf('syn_%03d_%s', i, type);
    imwrite(J, fullfile(cfg.paths.syn, 'clean', [name '.png']));
    imwrite(marked, fullfile(cfg.paths.syn, 'marked', [name '.jpg']), 'Quality', 90);
    imwrite(m > cfg.eval.maskAlphaMin, fullfile(cfg.paths.syn, 'gt_mask', [name '.png']));
    imwrite(uint16(round(alpha * 65535)), fullfile(cfg.paths.syn, 'gt_alpha', [name '.png']));

    rec.name = name;
    metaList = [metaList; rec]; %#ok<AGROW>
    fprintf('  %s  a0=%.2f\n', name, a0);
end

save(fullfile(cfg.paths.syn, 'meta.mat'), 'metaList');
fprintf('Saved %d synthetic images to %s\n', nTarget, cfg.paths.syn);
end

function sources = loadSources(cfg)
files = [dir(fullfile(cfg.paths.clean, '*.jpg')); dir(fullfile(cfg.paths.clean, '*.png'))];
if isempty(files)
    files = dir(fullfile(matlabroot, 'toolbox', 'images', 'imdata'));
end
sources = {};
for k = 1:numel(files)
    [~, base, ext] = fileparts(files(k).name);
    if ~any(strcmpi(ext, {'.jpg', '.png', '.tif'})) || ...
            any(contains(lower(base), cfg.syn.blocklist))
        continue;
    end
    try
        I = imread(fullfile(files(k).folder, files(k).name));
    catch
        continue;
    end
    if size(I, 3) ~= 3 || min(size(I, 1), size(I, 2)) < 300
        continue;
    end
    I = im2double(I);
    sources{end+1} = imresize(I, cfg.syn.longSide / max(size(I, 1), size(I, 2))); %#ok<AGROW>
end
if isempty(sources)
    error('makeSyntheticDataset:noSources', 'No clean RGB source photos found.');
end
sources = sources(randperm(numel(sources)));   % avoid runs of near-identical photos
end

function C = randomCrop(I, cropSize)
[h, w, ~] = size(I);
ch = min(h, cropSize(1));
cw = min(w, cropSize(2));
y = randi([0, h - ch]);
x = randi([0, w - cw]);
C = I(y + (1:ch), x + (1:cw), :);
end

function band = fitWidth(band, maxW)
if size(band, 2) > maxW
    band = min(max(imresize(band, maxW / size(band, 2)), 0), 1);
end
end

function m = pasteMax(m, stamp, x, y)
% Paste stamp with its top-left corner at (x, y), clipped to m, taking max.
[H, W] = size(m);
[sh, sw] = size(stamp);
x1 = max(1, x); y1 = max(1, y);
x2 = min(W, x + sw - 1); y2 = min(H, y + sh - 1);
if x1 > x2 || y1 > y2
    return;
end
m(y1:y2, x1:x2) = max(m(y1:y2, x1:x2), stamp(y1 - y + 1:y2 - y + 1, x1 - x + 1:x2 - x + 1));
end

function hit = boxOverlap(boxes, b, gap)
if isempty(boxes)
    hit = false;
    return;
end
hit = boxes(:, 1) < b(1) + b(3) + gap & b(1) < boxes(:, 1) + boxes(:, 3) + gap & ...
      boxes(:, 2) < b(2) + b(4) + gap & b(2) < boxes(:, 2) + boxes(:, 4) + gap;
end
