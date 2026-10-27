# Visible Watermark Detection & Removal (MATLAB, classical image processing)

An academic MATLAB project that finds a **visible watermark** (text or logo overlaid on a photo),
builds a mask of it, and removes it using classical image processing only. There is no deep learning.

> Only use this on images you own or have the rights to. This is an educational demo.

## What it does
1. **Detects** the watermark and outputs a binary mask.
2. **Removes** it three ways and saves all three:
   - **M1** coherence inpainting (`inpaintCoherent`)
   - **M2** exemplar / patch inpainting (`inpaintExemplar`)
   - **M3** alpha inversion, which recovers the real texture under a semi-transparent mark
3. Writes a side-by-side comparison per image: original | mask | M1 | M2 | M3.
4. Scores itself on a **synthetic benchmark** with known ground truth.

The watermark model is `I = (1 - a)·J + a·W` (J = clean image, W = white, a = opacity).

## Current status (honest)
- **Removal works** when the mask is right: with exact masks, M3 lifts in-mask PSNR from about 18 dB to about 35 dB.
- **Automatic detection does not meet its targets**: mask F1 is 0.08-0.27 on the synthetic set (target 0.85 for tiled text).
  Tiled text (w1, w2) is not detected, and single logos need a rough `search_box` hint.
- Details, numbers and failure analysis: [report/README.md](report/README.md).

## Requirements
MATLAB R2021a or newer (developed on R2026b) with the **Image Processing Toolbox**. Nothing else.

## Run it
Your own images go in `images/` (the default). To mark where the watermark is, run `selectRegion('images/yourfile.png')`,
draw a polygon or freehand circle around it, then run `main`.
```
matlab -batch "run_all"                      % everything: preflight, synthetic data, benchmark, real images, tests
matlab -batch "setupPaths; main(fullfile('data','real'))"                     % real images only
matlab -batch "setupPaths; main(fullfile('data','real'),'only','w4_luke_logo')" % one image
matlab -batch "setupPaths; r=runtests('tests'); exit(any([r.Failed]))"        % unit tests
```
Outputs go to `results/` (git-ignored, regenerated): `results/<name>/{mask,overlay,m1,m2,m3,recommended}.png`,
`results/comparison_<name>.png`, and `results/metrics.csv`.

## Layout
| Path | Purpose |
|---|---|
| `src/` | pipeline: preprocess, evidence map, classify, detectors, refine, removal, blend |
| `eval/` | synthetic dataset, metrics, benchmark |
| `tests/` | `matlab.unittest` tests (10) |
| `data/real/` | the test photos and optional `hints.json` (never modified) |
| `config.m` | every parameter in one place |
| `report/` | full write-up and phase log |
| `AGENTS.md` | the original project spec |

## Test images
`w1`-`w5` are the five spec images (tiled text, thin script, bold band, 7 repeated logos, one corner logo).
`wm1`-`wm8` are extra images with no ground truth.
