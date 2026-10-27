function cfg = config()
% CONFIG Central configuration parameters for visible watermark detection and removal.
% All pipeline parameters and thresholds are declared here. No magic numbers elsewhere.

cfg = struct();
cfg.seed = 0;

root = fileparts(mfilename('fullpath'));

% Optional capabilities (Computer Vision Toolbox / no-reference quality)
cfg.caps = struct();
cfg.caps.hasMSER     = exist('detectMSERFeatures', 'file') > 0;
cfg.caps.hasInsertText = exist('insertText', 'file') > 0;
cfg.caps.hasNIQE     = exist('niqe', 'file') > 0;
cfg.caps.hasBRISQUE  = exist('brisque', 'file') > 0;

% Paths (absolute, so the pipeline works from any working directory)
cfg.paths = struct();
cfg.paths.root  = root;
cfg.paths.real  = fullfile(root, 'data', 'real');
cfg.paths.clean = fullfile(root, 'data', 'clean');
cfg.paths.syn   = fullfile(root, 'data', 'synthetic');
cfg.paths.out   = fullfile(root, 'results');

% Preprocess & ROI
cfg.pre = struct();
cfg.pre.sigmaHP     = 3;        % high-pass gaussian sigma (px)

cfg.roi = struct();
cfg.roi.stdThresh   = 0.012;    % rows/cols with std below this at edge = frame
cfg.roi.maxFramePx  = 40;       % never strip more than this per side automatically
cfg.roi.shadowPx    = 6;        % extra safety margin after frame strip

% Classification (Autocorrelation of the evidence map)
cfg.cls = struct();
cfg.cls.gradSigma   = 1.0;      % smoothing before the gradient feature (px)
cfg.cls.hpSigma     = 30;       % high-pass sigma removing low-frequency background (px)
cfg.cls.minLag      = 20;       % ignore peaks closer than this to origin (px)
cfg.cls.maxLagFrac  = 0.6;      % only lags up to this fraction of the image size
cfg.cls.axisBand    = 8;        % suppress lags within this many px of the vertical axis
cfg.cls.zThresh     = 6;        % peak robust z-score vs autocorr background
cfg.cls.maxPeaks    = 30;       % strongest peaks passed to findLattice
cfg.cls.minOffPeaks = 2;        % >= this many significant peaks => periodic candidate
cfg.cls.minFoldCorr = 0.35;     % folded consensus must correlate with the evidence
cfg.cls.minRepeats  = 3;        % repeated-structure count to call 'sparse'

% Generic Evidence (multi-scale white top-hat + edge density) and single detector
cfg.gen = struct();
cfg.gen.radii       = [2 3 5 8 12 18];
cfg.gen.edgeSigma   = 6;
cfg.gen.whitePow    = 4;        % exponent on whiteness consistency (kappa)
cfg.gen.contrastWin = 7;        % local-std window for contrast attenuation (px)
cfg.gen.contrastBgSigma = 12;   % wide-neighbourhood sigma for the std baseline
cfg.gen.contrastMix = 0.5;      % 0 = full contrast gating, 1 = off
cfg.gen.smoothSigma = 0.8;      % final evidence smoothing (px)
cfg.gen.minArea     = 30;
cfg.gen.maxAreaFrac = 0.35;     % of the search area
cfg.gen.minSolidity = 0.15;     % text is not solid; keep low
cfg.gen.groupLenFrac = 0.04;    % horizontal grouping line length / image height
cfg.gen.groupDiskR  = 3;        % disk closing that joins logo parts (px)
cfg.gen.maxAspectBonus = 6;     % aspect ratio (w/h) at which the text bonus saturates
cfg.gen.minFill     = 0.3;      % blobs with fewer stroke pixels than this are penalised
cfg.gen.priorCornerFrac = 0.3;  % corner boxes (fraction of width/height) searched when no hint
cfg.gen.priorBandFrac = 0.3;    % bottom band (fraction of height) searched when no hint
cfg.gen.devScale    = 0.25;     % downscale for the background-deviation median filter
cfg.gen.devWin      = 9;        % median window on the downscaled image (~36 px at full size)
cfg.gen.keepFrac    = 0.5;      % keep blobs scoring >= this fraction of the best
cfg.gen.clusterDist = 0.25;     % ... and within this fraction of the image size of it

% Periodic Watermark Detector
cfg.per = struct();
cfg.per.refineIter  = 60;       % fminsearch iterations for lattice refinement
cfg.per.minTiles    = 6;        % need at least this many lattice cells in the ROI
cfg.per.localGate   = 0.5;      % fraction of the Otsu level local evidence must reach

% Template / Sparse Watermark Detector
cfg.tpl = struct();
cfg.tpl.scales      = [0.85 0.92 1.0 1.08 1.15];
cfg.tpl.nccThresh   = 0.45;
cfg.tpl.nmsFrac     = 0.6;      % non-max suppression radius as fraction of template size
cfg.tpl.mergeR      = 6;        % disk closing that merges one logo's parts (px)
cfg.tpl.minSide     = 12;       % smallest template side (px)
cfg.tpl.sizeRatio   = 1.3;      % candidates compared only if sizes agree within this
cfg.tpl.pairCorr    = 0.6;      % peak normxcorr2 for two candidates to count as repeats

% Mask Refinement
cfg.mask = struct();
cfg.mask.closeR     = 2;
cfg.mask.minComp    = 20;
cfg.mask.dilateR    = 3;        % larger dilation covers anti-aliased fringe
cfg.mask.useActiveContour = false;

% Removal Methods
cfg.inp = struct();
cfg.inp.coherentSmooth = 3;
cfg.inp.coherentRadius = 5;
cfg.inp.exemplarPatch  = [9 9];
cfg.inp.exemplarSearch = 40;    % crop margin around each hole group for inpaintExemplar (px)

cfg.alpha = struct();
cfg.alpha.W         = [1 1 1];
cfg.alpha.softSigma = 1.0;      % wider soft mask for more stable alpha estimation
cfg.alpha.search    = linspace(0.05, 0.8, 40);
cfg.alpha.maxA      = 0.6;
cfg.alpha.minDen    = 0.12;     % slightly more lenient denominator gate

cfg.blend = struct();
cfg.blend.featherSigma = 2.0;   % smoother blend at mask boundary

% Evaluation Benchmark
cfg.eval = struct();
cfg.eval.nImages     = 24;
cfg.eval.maskAlphaMin = 0.05;

% Synthetic dataset sources
cfg.syn = struct();
cfg.syn.longSide  = 720;        % sources resized to this long side (px), like the real images
cfg.syn.cropSize  = [420 620];  % [h w] random crop per synthetic image
cfg.syn.blocklist = {'distorted', 'colorchecker', 'coloredchips', 'saturn', 'tissue', ...
                     'pillsetc', 'tape', 'board', 'lowlight', 'westconcord', 'hestain'};
end
