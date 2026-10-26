# Visible Watermark Detection & Removal in MATLAB (Classical DIP)
### Full project plan and agent implementation spec

> **Audience:** an autonomous coding agent (Antigravity) that will build this from an empty folder.
> **Human owner:** SAI. **Language/tooling:** MATLAB + Image Processing Toolbox. **No deep learning.**
> Read this whole file before writing any code. Follow Section 14 (Operating Protocol) exactly.

---

## 0. TL;DR

Build a MATLAB pipeline that, given a photo with a visible watermark, (1) **detects** the watermark and outputs a binary mask, (2) **removes** it using inpainting and an alpha-inversion method, (3) writes a before/after comparison, and (4) is **evaluated** on a synthetic benchmark with known ground truth plus qualitatively on 5 real test images.

Deliverables: working code in the repo layout of Section 5, results for all 5 real images, `results/metrics.csv` from a synthetic benchmark, unit tests, and `report/README.md` with honest failure analysis.

---

## 1. Scope

**In scope**
- Visible, overlaid watermarks: tiled text, single bold text, repeated logos, single logo.
- Automatic detection (mask), three removal methods, comparison and metrics.
- Classical DIP only: filtering, morphology, FFT/autocorrelation, template matching, inpainting, alpha matting math.

**Out of scope (list as future work in the report):** CNN/GAN removal (WDNet, SplitNet etc.), invisible/frequency-domain watermarks, video.

**Ethics line to keep in the README:** this is an academic demo. Only use on images you own or have rights to.

---

## 2. Test image inventory

> **Filename warning:** the upload order is reversed relative to how the images were first described. The starter folder renames them by content. If you only have `watermarkN.jpg`, use this mapping and **open each file to confirm**.

| Repo name (`data/real/`) | Original file | Size | Watermark | Type | Notes |
|---|---|---|---|---|---|
| `w1_sample_tiled.jpg` | watermark5.jpg | 500x281 | "SAMPLE TEXT", diagonal, tiled, semi-transparent white | periodic | Has a **white frame with drop shadow** around the photo. Must be excluded via ROI. |
| `w2_plenio_tiled.jpg` | watermark4.jpg | 547x365 | "(c) Johannes Plenio", thin script, tiled in rows, slight tilt | periodic | Thin strokes over busy foliage. Hardest for ghosting. |
| `w3_proof_bold.jpg` | watermark3.jpg | 571x350 | "PROOF PROOF PROOF", bold, one row near bottom | localized (single band) | **Dark border** around photo. Large strokes over grass texture. Hardest removal. |
| `w4_luke_logo.jpg` | watermark2.jpg | 678x452 | Mountain logo + "LUKE COLLINS PHOTOGRAPHY", 7 instances | sparse repeats | Instances differ slightly in background only; template matching is ideal. |
| `w5_zoner_single.jpg` | watermark1.jpg | 733x418 | "Zoner Photo Studio X" logo, bottom right | single instance | Soft edges over smooth turquoise water: inpainting should work well. |

Do **not** modify the originals. Never overwrite files in `data/real/`.

---

## 3. Environment & preflight

### 3.1 Requirements
- MATLAB R2021a or newer (R2023+ preferred), **Image Processing Toolbox** (required).
- Optional: Computer Vision Toolbox (`detectMSERFeatures`, `insertText`), Statistics and Machine Learning Toolbox (`niqe` / `brisque` live in IPT in recent releases; check).
- Run everything headless: `matlab -batch "<command>"`. A non-zero exit code means an error.

### 3.2 If MATLAB is not available
**Stop and tell the user.** Do not silently rewrite the project in Python/OpenCV. Offer it only as an explicit option the user must approve.

### 3.3 `preflight.m` (create first, run first)
It must print and save to `results/preflight.txt`:
1. `version` and `ver` toolbox list.
2. For each function below, `exist(fn)` result (2 or 6 = file/p-file, 5 = built-in; 0 = missing):
   `inpaintCoherent, inpaintExemplar, regionfill, normxcorr2, imgaussfilt, imtophat, imregionalmax, activecontour, graythresh, adaptthresh, niqe, brisque, ssim, psnr, detectMSERFeatures, insertText, exportgraphics, rgb2lab, tiledlayout`
3. Write a capability struct to `results/caps.mat` that `config.m` loads, so every module can pick fallbacks:

```matlab
caps.hasExemplar = exist('inpaintExemplar') > 0;
caps.hasCoherent = exist('inpaintCoherent') > 0;
caps.hasMSER     = exist('detectMSERFeatures') > 0;
caps.hasInsertText = exist('insertText') > 0;
caps.hasNIQE     = exist('niqe') > 0;
```

**Fallbacks if missing:** `inpaintCoherent` missing -> `regionfill` per channel. `inpaintExemplar` missing -> implement a minimal Criminisi patch inpainter in `src/criminisiInpaint.m` (patch 9x9, priority = confidence x data term) or fall back to `inpaintCoherent` and say so in the README. No MSER -> skip MSER cue. No `insertText` -> render text via figure (Section 9.2).

> Verify exact name-value options of `inpaintCoherent` / `inpaintExemplar` with `help` in the installed release; the option names below are the R2022-era ones.

---

## 4. Math model

```
I = (1 - a) .* J + a .* W        (per pixel, per channel)
```
- `I` observed watermarked image, `J` clean image (unknown), `W` watermark colour (default white `[1 1 1]`; allow estimate), `a` opacity map in [0,1], zero outside the watermark.
- Inversion when `a` and `W` are known: `J = (I - a.*W) ./ (1 - a)`. This **preserves real image texture** under semi-transparent marks, unlike inpainting, which invents texture. Noise is amplified by `1/(1-a)`, so use it only for `a < a_max` (default 0.6).
- Typical overlays: `a` is roughly **constant inside the glyph** (e.g. 0.3) with anti-aliased edges. So model `a(x) = a0 * m(x)` where `m` is soft glyph coverage in [0,1] and `a0` is one scalar per watermark. Estimating one scalar `a0` robustly is far easier than a full map.

### 4.1 Estimating `a0` (core trick, implement exactly)
1. Get `J_inp` by inpainting under the **tight** mask (rough guess of the clean image).
2. Initial guess: `a0_init = median over mask pixels and channels of (I - J_inp) ./ (W - J_inp)`, using only pixels where `abs(W - J_inp) > 0.15` (avoid division blow-up on bright backgrounds).
3. **Line search by edge cancellation:** for `a` in `linspace(0.05, 0.8, 40)`, compute `J_a = (I - a*m.*W) ./ (1 - a*m)`. Cost = total variation (sum of gradient magnitude of luminance) of `J_a` inside a thin **band around the mask boundary** (`imdilate(edge(m),disk(2))`). When `a` is right, the glyph edges vanish and TV is minimal. Under-subtracting leaves edges; over-subtracting creates inverted edges.
4. `a0 = argmin cost` (smooth the cost curve with a 3-tap filter first). Sanity check: if the minimum sits at the search boundary or `cost_min > 0.9*cost_at_a=0`, declare "alpha-inversion unreliable" and fall back to inpainting for this image.

---

## 5. Repo layout (create exactly)

```
watermark_removal/
├── AGENTS.md                 % copy of this file (agent rules)
├── preflight.m
├── main.m                    % main(inputDir) runs the whole pipeline
├── config.m                  % ALL parameters; no magic numbers elsewhere
├── src/
│   ├── preprocess.m
│   ├── findROI.m             % exclude frames/borders
│   ├── classifyWatermark.m   % 'periodic' | 'sparse' | 'single'
│   ├── autocorrNorm.m
│   ├── findLattice.m
│   ├── foldTiles.m
│   ├── detectPeriodic.m
│   ├── detectGeneric.m
│   ├── mineRepeats.m         % find repeated structures -> template
│   ├── detectTemplate.m
│   ├── refineMask.m
│   ├── removeInpaint.m       % Methods 1 and 2
│   ├── removeAlphaInvert.m   % Method 3
│   ├── blendResult.m
│   └── viz/ (makeComparison.m, overlayMask.m)
├── eval/
│   ├── renderTextMask.m
│   ├── renderLogoMask.m
│   ├── makeSyntheticDataset.m
│   ├── computeMetrics.m
│   └── runBenchmark.m
├── tests/                    % matlab.unittest tests, Section 11
├── data/real/                % the 5 test images (+ optional hints.json)
├── data/clean/               % optional user-supplied clean photos
├── data/synthetic/           % generated: clean/, marked/, gt_mask/, gt_alpha/, meta.mat
├── results/                  % <name>/{mask.png, overlay.png, m1.png, m2.png, m3.png}, comparison_<name>.png, metrics.csv
└── report/                   % README.md, phase_log.md, figures
```

### 5.1 Data contracts (use these struct fields everywhere)

```matlab
P = preprocess(I, cfg)
%  P.I (double RGB 0..1), P.gray, P.lab, P.hp (high-pass of gray), P.valid (logical ROI, true = real photo content)

[type, info] = classifyWatermark(P, cfg)      % type in {'periodic','sparse','single'}

D = detect*(P, cfg, ...)
%  D.maskTight  logical  best pixel-accurate watermark mask (no dilation)
%  D.m          double   soft coverage in [0,1] = imgaussfilt(double(maskTight), cfg.alpha.softSigma)
%  D.maskDil    logical  maskTight dilated for inpainting
%  D.type, D.info (struct: lattice vectors, template boxes, scores, ...)

J = removeInpaint(I, maskDil, method, cfg)        % method: 'coherent'|'exemplar'|'regionfill'
[J, ainfo] = removeAlphaInvert(I, D, Jinp, cfg)   % ainfo.a0, ainfo.cost, ainfo.reliable
Jout = blendResult(I, J, D.maskDil, cfg)          % pixels outside feathered mask are bit-exact copies of I
```

All functions: header comment (purpose, inputs, outputs), `arguments` block or `validateattributes`, pure (no globals), deterministic (`rng(cfg.seed)` set once in `main`).

---

## 6. `config.m` (complete parameter set; start with these values, tune on the synthetic set)

```matlab
function cfg = config()
cfg.seed = 0;
S = load('results/caps.mat'); cfg.caps = S.caps;     % written by preflight.m

% paths
cfg.paths.real = 'data/real'; cfg.paths.clean = 'data/clean';
cfg.paths.syn  = 'data/synthetic'; cfg.paths.out = 'results';

% preprocess / ROI
cfg.pre.sigmaHP     = 3;        % high-pass gaussian sigma (px)
cfg.roi.stdThresh   = 0.012;    % rows/cols with std below this at the edge = frame
cfg.roi.maxFramePx  = 40;       % never strip more than this per side automatically
cfg.roi.shadowPx    = 6;        % extra safety margin after frame strip

% classification (autocorrelation)
cfg.cls.minLag      = 12;       % ignore peaks closer than this to the origin (px)
cfg.cls.zThresh     = 6;        % peak z-score vs autocorr background
cfg.cls.maxPeaks    = 12;
cfg.cls.minOffPeaks = 2;        % >= this many significant peaks => periodic candidate
cfg.cls.minRepeats  = 2;        % repeated-structure count to call 'sparse'

% generic evidence (multi-scale white top-hat + edge density)
cfg.gen.radii       = [2 3 5 8 12 18];
cfg.gen.edgeSigma   = 6;
cfg.gen.minArea     = 30;
cfg.gen.maxAreaFrac = 0.35;
cfg.gen.minSolidity = 0.15;     % text is not solid; keep low

% periodic
cfg.per.refineIter  = 60;       % fminsearch iterations for lattice refinement
cfg.per.minTiles    = 4;        % need at least this many tile repeats
cfg.per.localGate   = 0.25;     % fraction of local evidence required to keep a pixel

% template / sparse
cfg.tpl.scales      = [0.85 0.92 1 1.08 1.15];
cfg.tpl.nccThresh   = 0.45;
cfg.tpl.nmsFrac     = 0.6;      % non-max suppression radius as fraction of template size

% mask refinement
cfg.mask.closeR     = 2; cfg.mask.minComp = 20; cfg.mask.dilateR = 2;
cfg.mask.useActiveContour = false;

% removal
cfg.inp.coherentSmooth = 3; cfg.inp.coherentRadius = 5;
cfg.inp.exemplarPatch  = [9 9];
cfg.alpha.W         = [1 1 1];
cfg.alpha.softSigma = 0.7;
cfg.alpha.search    = linspace(0.05, 0.8, 40);
cfg.alpha.maxA      = 0.6;
cfg.alpha.minDen    = 0.15;
cfg.blend.featherSigma = 1.5;

% evaluation
cfg.eval.nImages = 24; cfg.eval.maskAlphaMin = 0.05;
end
```

---

## 7. Detection modules (algorithms + reference code)

### 7.1 `findROI` + `preprocess`
Real images 1 and 3 have frames. Detect rows/cols from each side whose luminance **std** is below `cfg.roi.stdThresh` (a flat frame) or whose mean is near-white/near-black and flat; strip contiguous rows/cols (max `cfg.roi.maxFramePx`) plus `shadowPx`. Output `P.valid`. Allow manual override via `data/real/hints.json` (`{"w1_sample_tiled": {"roi": [x y w h]}}`). All detection statistics are computed only where `P.valid` is true; the mask is always `& P.valid`.

```matlab
function P = preprocess(I, cfg)
I = im2double(I);
P.I = I; P.gray = rgb2gray(I); P.lab = rgb2lab(I);
P.valid = findROI(P.gray, cfg);
P.hp = P.gray - imgaussfilt(P.gray, cfg.pre.sigmaHP);
P.hp(~P.valid) = 0;
end
```

### 7.2 Evidence map `T` (shared by every detector)
White overlays are **brighter, less saturated, thin-to-medium structures with crisp edges**. Compute:

```matlab
function [T, E] = evidenceMap(P, cfg)
G = P.gray; T = zeros(size(G));
for r = cfg.gen.radii
    T = max(T, imtophat(G, strel('disk', r)));      % bright structures narrower than the disk
end
S = rgb2hsv(P.I); S = S(:,:,2);
Edges = edge(G, 'canny');
Ed = imgaussfilt(double(Edges), cfg.gen.edgeSigma);  % edge density
Ed = Ed ./ max(Ed(:) + eps);
satDrop = max(0, imgaussfilt(S, 8) - S);              % overlay lowers saturation locally
T = T .* (0.5 + 0.5*Ed) .* (1 + satDrop);
T(~P.valid) = 0;
T = T ./ max(T(:) + eps);
E = Edges;
end
```
Rationale: the top-hat finds bright strokes; edge density suppresses smooth natural highlights (sun, sky); saturation drop reinforces white overlays. For very thin script (image `w2`) use the smaller radii; for bold text (`w3`, strokes ~20 px) the larger radii matter.

### 7.3 `classifyWatermark`
1. Normalised autocorrelation of `P.hp` (Hann-windowed, zero-padded to 2x) **divided by the overlap count** of `P.valid` so large lags are not biased:

```matlab
function ac = autocorrNorm(h, valid)
[H,W] = size(h);
h = h .* valid;
F  = fft2(h, 2*H, 2*W);   ac  = real(ifft2(abs(F).^2));
Fv = fft2(double(valid), 2*H, 2*W); cnt = real(ifft2(abs(Fv).^2));
ac = ac ./ max(cnt, 1);   ac = fftshift(ac);   ac = ac ./ ac(H+1, W+1);   % centre = 1
end
```
2. Convert to z-scores outside `minLag`, find regional maxima with `z > cfg.cls.zThresh`. If `>= minOffPeaks` peaks (counting +/- pairs once) **and** a valid non-collinear lattice exists with at least `cfg.per.minTiles` repeats fitting in the ROI -> `'periodic'`.
3. Else run `mineRepeats` (7.6). If it finds `>= cfg.cls.minRepeats` near-identical structures -> `'sparse'`.
4. Else `'single'`.
Return `info` containing `z` map, peak list, and decision reasons (log them: debugging classification is half the work).

### 7.4 `findLattice` and `foldTiles`
```matlab
function [a1, a2] = findLattice(peaksXY)   % peaks relative to origin, one of each +/- pair
d = vecnorm(peaksXY, 2, 2);  [~, o] = sort(d);  peaksXY = peaksXY(o, :);
a1 = peaksXY(1, :);
for k = 2:size(peaksXY,1)
    c = abs(a1(1)*peaksXY(k,2) - a1(2)*peaksXY(k,1)) / (norm(a1)*norm(peaksXY(k,:)));
    if c > 0.35, a2 = peaksXY(k,:); return; end     % shortest non-collinear
end
error('findLattice:none', 'No second lattice vector');
end
```
Refine each peak to sub-pixel (parabolic fit around the max). Then **refine the lattice** with `fminsearch` over `[a1 a2]` (4 numbers), minimising the mean within-bin median-absolute-deviation of `T` after folding (a correct lattice makes all tiles agree). Without refinement, a 0.3 px period error becomes a 15 px misalignment across 50 tiles.

```matlab
function [Tmed, evid, idx] = foldTiles(T, valid, a1, a2)
[H,W] = size(T); [x,y] = meshgrid(0:W-1, 0:H-1);
uv = [a1(:) a2(:)] \ [x(:)'; y(:)'];
f  = uv - floor(uv);
nb = [max(8, round(norm(a1))), max(8, round(norm(a2)))];
bi = min(nb(1), floor(f(1,:)*nb(1)) + 1);
bj = min(nb(2), floor(f(2,:)*nb(2)) + 1);
idx = sub2ind(nb, bi, bj); idx = idx(:);
v = valid(:);
Tmed = accumarray(idx(v), T(v), [prod(nb) 1], @median, 0);
evid = reshape(Tmed(idx), H, W);                    % tile-consensus evidence in image space
end
```
The **median across tiles** keeps only structure that repeats at every lattice position, i.e. the watermark, and rejects the photo content. This is the single-image version of Dekel et al. (CVPR 2017), who do it across many images; treat that citation as from memory and verify it before it goes in the report.

### 7.5 `detectPeriodic`
```
[a1,a2] = lattice (refined)
evid    = foldTiles(T, valid, a1, a2)
tight0  = evid > graythresh(evid)*max(evid(:))          % consensus mask
gate    = imdilate(T > cfg.per.localGate*graythresh(T), disk(2))   % local evidence must agree
maskTight = tight0 & gate & P.valid
```
Then `refineMask`. Log `a1, a2, nTiles`.

### 7.6 `mineRepeats` + `detectTemplate` (for image `w4`)
`mineRepeats`: threshold `T` (Otsu), close with a disk about the logo gap (so mountain + text merge into one component), keep components in the area bounds. For every pair of components, crop `T` patches, resize to a common size, compute max `normxcorr2`. A component with `>= minRepeats - 1` partners above 0.6 is a **repeat**. The best-supported component's crop is the template. Store all component boxes.

`detectTemplate`: for each scale in `cfg.tpl.scales`, `c = normxcorr2(tplScaled, T)`; keep peaks above `cfg.tpl.nccThresh`, non-max suppress with radius `nmsFrac * max(size(tpl))`, then keep the best scale per location. Build the mask by pasting the template's own binary (thresholded `T` crop) at each peak, then `maskTight = pasted & gate`, with the same local-evidence gate as 7.5. Always return the number of instances found and their boxes (expected for `w4`: 7; accept 6-7 and document).

### 7.7 `detectGeneric` (for `single`: images `w3`, `w5`)
1. `T` from 7.2; threshold (Otsu on nonzero values, or `adaptthresh`).
2. **Line grouping for text:** close with a horizontal line element (length ~ 3x glyph height) so "PROOF PROOF PROOF" becomes one blob; keep blobs with aspect ratio > 3 and high edge density.
3. Connected-component filter: area in `[minArea, maxAreaFrac*numel]`, solidity > `minSolidity`, plus rank by (mean `T` x edge density). Keep the top cluster(s) that are spatially close.
4. Optional MSER (`detectMSERFeatures`) as an additional text-likeness vote if `caps.hasMSER`.
5. Mask = union of kept components `& P.valid`.

Honest expectation: automatic single-watermark detection is the least reliable part. Support an **optional hint** in `data/real/hints.json` (a rough ROI box, e.g. bottom-right quadrant for `w5`) which restricts search; clearly mark in results which images used hints. Never hard-code per-image logic in `src/`.

### 7.8 `refineMask`
Produce **two** masks: `maskTight` (for alpha estimation) and `maskDil` (for inpainting).
```
maskTight = imclose(raw, disk(closeR)); maskTight = bwareaopen(maskTight, minComp);
maskDil   = imdilate(maskTight, disk(dilateR));        % covers anti-aliased fringe
D.m       = imgaussfilt(double(maskTight), cfg.alpha.softSigma);
```
Optional `activecontour(P.gray, maskTight, 30, 'Chan-Vese')` when `cfg.mask.useActiveContour`.

---

## 8. Removal modules

### 8.1 Method 1: coherent inpainting (thin text; `w1`, `w2`)
```matlab
function J = removeInpaint(I, maskDil, method, cfg)
switch method
  case 'coherent'
    J = inpaintCoherent(I, maskDil, 'SmoothingFactor', cfg.inp.coherentSmooth, 'Radius', cfg.inp.coherentRadius);
  case 'exemplar'
    J = inpaintExemplar(I, maskDil, 'PatchSize', cfg.inp.exemplarPatch);
  case 'regionfill'
    J = I; for c = 1:3, J(:,:,c) = regionfill(I(:,:,c), maskDil); end   % regionfill is 2-D only
end
end
```
### 8.2 Method 2: exemplar inpainting (large/bold or logo areas; `w3`, `w4`, `w5`)
Same function, `'exemplar'`. If the toolbox lacks it, use `src/criminisiInpaint.m` fallback.

### 8.3 Method 3: alpha-inversion (semi-transparent marks)
Follows Section 4.1.
```matlab
function [J, ainfo] = removeAlphaInvert(I, D, Jinp, cfg)
W = reshape(cfg.alpha.W, 1, 1, 3);  m = D.m;
band = imdilate(edge(m > 0.5), strel('disk', 2));
% 1) robust init
den = W - Jinp;  num = I - Jinp;
ok  = repmat(D.maskTight, 1, 1, 3) & abs(den) > cfg.alpha.minDen;
a_init = median(num(ok) ./ den(ok), 'omitnan');
% 2) line search by edge cancellation
cost = zeros(size(cfg.alpha.search));
for k = 1:numel(cost)
    a  = cfg.alpha.search(k);
    Ja = (I - a*m.*W) ./ (1 - a*m);
    L  = rgb2gray(min(max(Ja,0),1));
    [gx, gy] = imgradientxy(L);  tv = hypot(gx, gy);
    cost(k) = sum(tv(band));
end
cs = conv(cost, [1 1 1]/3, 'same');  [cmin, kmin] = min(cs(2:end-1));  kmin = kmin + 1;
a0 = cfg.alpha.search(kmin);
reliable = kmin > 1 && kmin < numel(cost) && cmin < 0.9*cost(1);
% 3) invert where safe, inpaint elsewhere
aMap = a0 * m;
J = (I - aMap.*W) ./ max(1 - aMap, 1e-3);
J = min(max(J, 0), 1);
useInp = aMap > cfg.alpha.maxA | ~reliable;
useInp3 = repmat(useInp & D.maskDil, 1, 1, 3);
J(useInp3) = Jinp(useInp3);
ainfo = struct('a0', a0, 'a_init', a_init, 'cost', cost, 'reliable', reliable);
end
```
Report `a_init` vs `a0` vs the **true** alpha on the synthetic set (this validates the estimator).

### 8.4 `blendResult`
```matlab
function Jout = blendResult(I, J, maskDil, cfg)
F = imgaussfilt(double(maskDil), cfg.blend.featherSigma);
F = min(F * 1.0, 1);  F(maskDil) = 1;           % mask interior fully replaced
Jout = I .* (1 - F) + J .* F;
end
```
Contract: where `imdilate(maskDil, disk(ceil(3*featherSigma))) == 0`, `Jout == I` exactly.

### 8.5 Which method for which type (auto-selection in `main`)
Run **all three** on every image and save them. Pick the "recommended" output by rule: `periodic` and thin strokes -> Method 3 if `ainfo.reliable` else Method 1; `sparse` -> Method 3 if reliable else Method 2; `single`/bold -> Method 2. Record the rule and the reliability flag in `results/<name>/info.json`.

---

## 9. Evaluation

### 9.1 Why synthetic
The real images have no clean ground truth, so quantitative claims come from a synthetic benchmark with exact `J`, `a`, `W`, mask. Real images get qualitative side-by-sides plus `niqe`/`brisque` (lower = better), reported with the caveat that these are weak proxies.

### 9.2 `makeSyntheticDataset`
- Sources, in priority order: `data/clean/*` if present; otherwise MATLAB's built-in sample images: `imageDatastore(fullfile(matlabroot,'toolbox','images','imdata'))`, filtered to RGB images at least 300x300, excluding medical/microscopy and grayscale ones (check `size(I,3)==3` and a name blocklist); if fewer than `cfg.eval.nImages`, also use crops and flips of the same images (distinct crops, `rng(0)`).
- Four watermark types, each applied to every image, with randomised `a0 in [0.2, 0.5]`, position/angle jitter, font size relative to image size:
  1. `tiledText`: lattice of rotated text (like `w1`/`w2`), with row stagger option.
  2. `boldText`: one band of bold text (like `w3`).
  3. `logoSparse`: 5-8 instances of a synthetic logo + caption (like `w4`).
  4. `cornerLogo`: one logo bottom right (like `w5`).
- Rendering `renderTextMask(str, sz, angleDeg, fontName)` returns antialiased coverage `m in [0,1]`: draw black text on white in an **invisible figure** (`figure('Visible','off')`), `exportgraphics` or `print -r100` to a temp PNG, read back, `m = 1 - rgb2gray`. Logos: `fill` a triangle/mountain polygon plus text, same route. If `caps.hasInsertText`, `insertText` is an acceptable alternative. Test that rendering works under `matlab -batch` early (Phase 0), because headless graphics can be fragile.
- Compose `I = (1 - a0*m).*J + a0*m.*W`, then **JPEG-compress at quality 90** (`imwrite`/`imread`) to mimic real files.
- Save `data/synthetic/{clean,marked,gt_mask,gt_alpha}/` and `meta.mat` (type, a0, W, seed).

### 9.3 `computeMetrics`
- Mask: IoU, precision, recall, F1 against `gt_alpha > cfg.eval.maskAlphaMin`.
- Restoration: PSNR and SSIM vs clean **on the whole image** and **inside the dilated GT mask**; also report PSNR of the unprocessed marked image as the baseline.
- Alpha estimate: `|a0_est - a0_true|`.
- Real images: `niqe`/`brisque` if available.

### 9.4 `runBenchmark`
Grid: 4 types x N images x {auto mask, oracle mask} x {M1, M2, M3}. The oracle-mask rows isolate **removal quality** from **detection error**, which is the most informative ablation. Output `results/metrics.csv` (one row per case), a summary table (mean +/- std per type x method), and bar charts (F1 per type; PSNR-in-mask per method). Also run the ablation "mask refinement on vs off".

---

## 10. `main.m` behaviour

```
main('data/real')            % all images in folder
main('data/real', 'only', 'w4_luke_logo')
```
Per image: read -> preprocess -> classify -> detect -> refine -> Methods 1/2/3 -> blend -> save `mask.png`, `overlay.png` (mask in red over the image), `m1.png m2.png m3.png`, `recommended.png`, `info.json`, and `results/comparison_<name>.png` laid out as **original | mask overlay | M1 | M2 | M3** with titles (use `tiledlayout`). Wrap each image in `try/catch` so one failure does not stop the batch; log errors to `results/errors.log` and exit non-zero if any image failed. Print a one-line summary per image (type, #instances, a0, reliable).

---

## 11. Testing (`tests/`, `matlab.unittest`)

Run: `matlab -batch "addpath(genpath('src'),genpath('eval')); r=runtests('tests'); disp(r); exit(any([r.Failed]))"`

| Test | Assertion |
|---|---|
| `testRoi` | A synthetic image with a 15 px white frame gets `valid` false in the frame, true inside. |
| `testClassifyPeriodic` | Tiled synthetic watermark -> `'periodic'`; plain natural image -> not periodic. |
| `testLattice` | Known lattice vectors recovered within 1 px (after refinement within 0.3 px). |
| `testFold` | Folded evidence of a perfectly periodic pattern equals the pattern (error < 1e-6). |
| `testTemplateCount` | N pasted copies of a logo are found: count == N, positions within 3 px. |
| `testAlphaRecovery` | Synthetic `a0 = 0.35` recovered within 0.05 (oracle mask). |
| `testAlphaInversion` | With oracle `a0` and `m`, reconstruction PSNR > 40 dB inside the mask. |
| `testBlendOutside` | Pixels outside the feathered mask are bit-identical to the input. |
| `testDeterminism` | Two runs of `main` give identical outputs (seeded). |

---

## 12. Milestones & phase gates

Complete phases **in order**. A gate is passed only when the listed evidence exists. At each gate append to `report/phase_log.md`: what was built, commands run, metrics, **screenshots viewed**, known issues.

| Phase | Work | Gate evidence |
|---|---|---|
| 0 | Repo skeleton, `preflight.m`, `config.m`, headless text-render smoke test, copy and rename the 5 images. | `results/preflight.txt`; a rendered text-mask PNG produced with `matlab -batch`. |
| 1 | **Baseline:** hand-drawn rough masks (`data/real/masks_manual/*.png`, draw with `roipoly`-style scripts or polygons in code), run Method 1/2 on all 5 images. | Side-by-side figures for all 5; written note on the best quality achievable with a *perfect* mask (the ceiling). |
| 2 | Synthetic dataset generator + metrics (build this **before** detection so you can tune against it). | `data/synthetic/` populated; oracle-mask benchmark for M1/M2 running. |
| 3 | Detection: evidence map -> classify -> periodic -> sparse/template -> generic -> refine. | Per-image masks and overlays; synthetic mask F1 table; classification confusion table. |
| 4 | Method 3 (alpha estimation + inversion), blending, auto-selection. | `testAlphaRecovery` passes; M3 vs M1/M2 table with oracle masks. |
| 5 | Full benchmark (auto and oracle), ablations, charts, `main.m` polish, tests green. | `results/metrics.csv`, charts, `runtests` all pass. |
| 6 | Report + optional App Designer GUI (load, detect, preview mask, choose method, save). | `report/README.md` complete; GUI optional and last. |

---

## 13. Acceptance criteria & expectations

**Hard criteria (must hold)**
1. `main('data/real')` exits 0, producing mask + 3 outputs + comparison for all 5 images.
2. All unit tests pass.
3. Synthetic, `tiledText`: mean mask F1 >= 0.85 (auto detection).
4. Synthetic, every type, **oracle mask**: PSNR inside the mask beats the watermarked baseline for the recommended method.
5. Synthetic, every type, auto mask: whole-image PSNR beats the watermarked baseline on average.
6. No file in `data/real/` modified; deterministic reruns.

**Visual targets (real images, judged by viewing PNGs)**
- `w1`, `w4`, `w5`: no readable watermark remains at 100% zoom.
- `w2`, `w3`: partial success acceptable (ghosting / smeared grass). **Document residue honestly** with crops; do not hide it.

**Targets, not requirements** (report actual values, whatever they are): `a0` error < 0.05 on synthetic; template instance count 7 on `w4`.

---

## 14. Agent operating protocol

1. **Plan first.** Create a task list from Sections 12 and 5, then a short implementation plan; keep both updated.
2. **Verify, never assume.** After every module, run it (`matlab -batch`) on a real input and on a synthetic input, then **open the output PNGs and look at them**. A plot that "should" be right is not evidence.
3. **Tune on synthetic data**, not by eyeballing a single real image. Per-image hacks in `src/` are forbidden; image-specific information may only enter through `data/real/hints.json`, and every use must be reported.
4. **No fabricated numbers.** Metrics in the report must come from `results/metrics.csv`. Report bad results as bad.
5. **If a toolbox function is missing or an option name errors**, check `help <fn>` for the installed release, adapt, and record the adaptation in the README. Don't loop on the same failing call more than twice; read the error, change approach.
6. **Keep functions small and tested.** All parameters live in `config.m`.
7. **Stop-and-ask triggers:** MATLAB missing; a required toolbox absent with no workable fallback; a phase gate that cannot be met after two genuine attempts (explain what you tried and the numbers).
8. **Never** delete user data, use network downloads of copyrighted images, or add dependencies outside MATLAB.
9. Commit (or checkpoint) at each gate.

### 14.1 Debugging playbook (symptom -> likely cause -> fix)

| Symptom | Likely cause | Fix |
|---|---|---|
| Periodic image classified `single` | z-threshold too high; hp sigma too large for thin text | Lower `zThresh` to 4; reduce `sigmaHP` to 1.5-2; inspect `info.z` image. |
| Lattice found but mask misaligned at image far side | Period error accumulating | Make sure sub-pixel refinement and `fminsearch` ran; fold on a downsampled copy first for speed, then refine at full res. |
| Mask covers sky/sun/water highlights | `T` picks natural highlights | Raise edge-density weight; add local-gate; drop largest radii; use MSER vote. |
| Mask misses thin script (`w2`) | Radii too large, hp too smooth | Use radii `[1 2 3]` for that class; lower threshold; lower `localGate`. |
| Frame or border treated as watermark | ROI not stripped | Check `P.valid`; adjust `roi.stdThresh`; use hint. |
| Halo remains around glyphs | Mask too tight | Increase `dilateR` to 3; inspect antialiasing fringe; raise `featherSigma`. |
| Alpha line search minimum at range edge | Mask poor or alpha > 0.8 / < 0.05 | Mark unreliable, use inpainting; check mask with overlay. |
| Dark smudges after inversion | `a0` over-estimated or `W` wrong | Check `a0` vs `a_init`; estimate `W` as the per-channel median of the brightest 10% of mask pixels. |
| `inpaintExemplar` very slow | Mask is large | Process per connected component; downscale search region; or use coherent for thin parts. |
| Text render fails under `-batch` | No display | Use `figure('Visible','off')` + `exportgraphics`; else `insertText`; else bitmap font fallback. |

---

## 15. Report template (`report/README.md`)

1. **Problem & model** (the equation, assumptions).
2. **Related work:** Dekel et al., *On the Effectiveness of Visible Watermarks* (CVPR 2017; verify details before citing); Criminisi et al. exemplar inpainting; Telea fast-marching inpainting; PDE/Laplace inpainting; learned methods (WDNet, SplitNet) as future work.
3. **Method:** block diagram (detect -> estimate -> remove), one subsection per module with the key equation.
4. **Experiments:** synthetic benchmark table (type x method x {auto, oracle}), ablations, `a0` estimation error, per-image real results with the comparison figures.
5. **Failure analysis, per real image** (what worked, what didn't, why; include zoomed crops).
6. **Limitations & future work.**
7. **Reproducibility:** exact commands, MATLAB version, toolboxes, seed.
8. **Ethics note** (Section 1).

---

## 16. Quick-start command sequence for the agent

```bash
cd watermark_removal
matlab -batch "preflight"
matlab -batch "addpath(genpath('src'),genpath('eval')); makeSyntheticDataset()"
matlab -batch "addpath(genpath('src'),genpath('eval')); runBenchmark()"
matlab -batch "addpath(genpath('src'),genpath('eval')); main('data/real')"
matlab -batch "addpath(genpath('src'),genpath('eval')); r=runtests('tests'); exit(any([r.Failed]))"
```

*End of spec.*
