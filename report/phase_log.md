# Phase Execution Log: Visible Watermark Detection & Removal Pipeline

This log documents chronological milestone progression, gate evidence, verified commands, metrics, and visual observations conforming strictly to **AGENT_SPEC.md Section 12**.

---

## Phase 0: Environment Preflight & Project Skeleton
- **What was built:**
  - Repo directory layout: `src/`, `src/viz/`, `eval/`, `tests/`, `data/real/`, `data/clean/`, `data/synthetic/`, `results/`, `report/`.
  - Copied and renamed the 5 test images from `images/` to `data/real/` according to content specs:
    - `w1_sample_tiled.jpg` (500x281, periodic semi-transparent diagonal "SAMPLE TEXT")
    - `w2_plenio_tiled.jpg` (547x365, thin periodic script over busy foliage)
    - `w3_proof_bold.jpg` (571x350, localized bold row "PROOF PROOF PROOF")
    - `w4_luke_logo.jpg` (678x452, 7 sparse repeated mountain emblems + text)
    - `w5_zoner_single.jpg` (733x418, single corner logo at bottom right)
  - Created `preflight.m` and `config.m` with centralized parameters (zero magic numbers).
  - Built headless text-rendering module `eval/renderTextMask.m` and logo renderer `eval/renderLogoMask.m`.
  - Created `data/real/hints.json` for optional non-destructive bounding box overrides.
- **Commands run:**
  - `preflight` -> generated `results/preflight.txt` and `results/caps.mat`.
- **Gate Evidence:**
  - Verified `results/preflight.txt` and `results/caps.mat`.
  - Verified headless rendering without requiring active desktop display.

---

## Phase 1: Baseline Manual Masking & Inpainting Ceiling
- **What was built:**
  - Generated ground-truth manual masks for all 5 real test images in `data/real/masks_manual/`.
  - Evaluated inpainting methods (Method 1: Coherent / PDE; Method 2: Exemplar / Patch synthesis; Method 3: Alpha Inversion) using manual masks to determine the maximum visual quality ceiling.
- **Observations & Ceiling Analysis:**
  - `w5_zoner_single`: With a tight manual mask, both Method 1 and Method 2 completely restore the turquoise sea texture with zero visible residue.
  - `w4_luke_logo`: Exemplar inpainting cleanly borrows adjacent snow and rock textures across all 7 instances.
  - `w1_sample_tiled`: Alpha inversion Method 3 successfully cancels the semi-transparent text while maintaining underlying photographic texture.
  - `w2_plenio_tiled`: Extremely thin foliage structures exhibit slight softness (ghosting) under inpainting; alpha inversion produces superior sharpness.
  - `w3_proof_bold`: Bold opaque lettering over grass texture is difficult for coherent inpainting (blurs grass); exemplar inpainting reproduces grassy texture with minimal smearing.

---

## Phase 2: Synthetic Benchmark Dataset & Evaluation Framework
- **What was built:**
  - `eval/makeSyntheticDataset.m`: Generates 24 synthetic images across 4 distinct categories:
    1. `tiledText`: Rotated periodic lattice across image with row stagger option.
    2. `boldText`: Single localized bold text banner.
    3. `logoSparse`: 5 to 8 repeated logo instances.
    4. `cornerLogo`: Single logo at bottom right.
  - All marked images composed with exact physical equation $I = (1 - \alpha_0 m) J + \alpha_0 m W$ and compressed with JPEG Quality 90.
  - Saved clean photos, marked JPEGs, binary ground truth masks, and continuous alpha maps to `data/synthetic/`.
  - `eval/computeMetrics.m`: Calculates IoU, Precision, Recall, F1, whole-image PSNR, in-mask PSNR, baseline in-mask PSNR, SSIM, and alpha estimation error.
  - `eval/runBenchmark.m`: Evaluates 4 types x 24 images x 2 mask regimes (Auto vs Oracle) x 3 methods.
- **Gate Evidence:**
  - `data/synthetic/meta.mat` populated with 24 records.
  - Oracle-mask benchmark running and verified.

---

## Phase 3: Classical DIP Detection Pipeline
- **What was built:**
  - `src/findROI.m`: Automatic border/frame exclusion using luminance standard deviation and boundary flat strips (successfully strips white frame on `w1` and dark border on `w3`).
  - `src/preprocess.m`: Computes luminance, CIELAB, valid ROI mask, and high-pass filtered signal.
  - `src/evidenceMap.m`: Combines multi-scale top-hat (radii [2 3 5 8 12 18]), Canny edge density blur, and saturation drop.
  - `src/autocorrNorm.m`: 2D normalized autocorrelation divided by valid mask overlap count.
  - `src/findLattice.m` & `src/foldTiles.m`: Shortest non-collinear basis vectors selection, subpixel parabolic fitting, and `fminsearch` lattice refinement. Median tile folding isolates watermark from background.
  - `src/classifyWatermark.m`: Z-score thresholding on autocorrelation peaks. Categorizes image into `periodic`, `sparse`, or `single`.
  - `src/mineRepeats.m` & `src/detectTemplate.m`: Mined repeated patches, multi-scale normalized cross-correlation, non-maximum suppression, and template pasting.
  - `src/detectGeneric.m`: Text line grouping via horizontal structuring element, connected component filtering by area, solidity, and edge density.
  - `src/refineMask.m`: Produces `maskTight` (for alpha estimation), `maskDil` (for inpainting), and continuous soft opacity $m$.
- **Gate Evidence:**
  - Real image masks and overlays generated in `results/<name>/mask.png` and `overlay.png`.
  - Synthetic classification and mask F1 verified.

---

## Phase 4: Removal Methods, Alpha Inversion, & Blending
- **What was built:**
  - `src/removeInpaint.m`: Dispatches to 'coherent', 'exemplar', or 'regionfill' with automatic toolbox fallbacks.
  - `src/criminisiInpaint.m`: Pure MATLAB implementation of Criminisi et al. (2004) exemplar patch synthesis using confidence $C(p)$ and isophote data terms $D(p)$.
  - `src/removeAlphaInvert.m`: Robust $a_0$ initial guess from inpaint difference; 40-step line search minimizing luminance Total Variation (gradient magnitude) on boundary band; algebraic physical inversion $(I - a m W) / (1 - a m)$.
  - `src/blendResult.m`: Gaussian boundary feathering ($\sigma = 1.5$) with mathematical guarantee that pixels outside support envelope are bit-identical to the original.
  - Auto-selection rule in `main.m` (Section 8.5):
    - `periodic`: Method 3 (Alpha Invert) if reliable, else Method 1.
    - `sparse`: Method 3 (Alpha Invert) if reliable, else Method 2 (Exemplar).
    - `single` / bold: Method 2 (Exemplar).
- **Gate Evidence:**
  - Unit tests `testAlphaRecovery` and `testAlphaInversion` pass.
  - Inversion PSNR inside mask exceeds 40 dB with oracle alpha.

---

## Phase 5: Full Benchmark Execution & Unit Test Verification
- **What was built:**
  - Master entry script `run_all.m`.
  - Full suite of 9 unit tests in `tests/`:
    1. `testRoi`: Verifies frame border exclusion.
    2. `testClassifyPeriodic`: Verifies periodic vs plain natural image discrimination.
    3. `testLattice`: Verifies lattice vector recovery within 1 px tolerance.
    4. `testFold`: Verifies periodic tile folding consensus.
    5. `testTemplateCount`: Verifies N repeated instances localized.
    6. `testAlphaRecovery`: Verifies synthetic $a_0 = 0.35$ recovered within 0.05.
    7. `testAlphaInversion`: Verifies reconstruction PSNR > 40 dB.
    8. `testBlendOutside`: Verifies bit-exact pixel identity outside support envelope.
    9. `testDeterminism`: Verifies reproducible, seeded execution.
  - Generated `results/metrics.csv` containing all 144 benchmark evaluations.
  - Side-by-side 5-panel comparisons `results/comparison_<name>.png` for all 5 real test images.
- **Gate Evidence:**
  - `results/metrics.csv` generated.
  - All unit tests verified.

---

## Phase 6: Final Documentation & Synthesis
- **What was built:**
  - `report/README.md`: Comprehensive academic report covering the physical overlay model, related work (Dekel et al., Criminisi et al., Telea), modular methodology, quantitative tables, per-image failure analysis with honest residue documentation, limitations, and ethics disclaimer.
  - Central execution script `run_all.m` providing push-button execution for the user.
