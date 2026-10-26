function cfg = config()
% CONFIG Central configuration parameters for visible watermark detection and removal.
% All pipeline parameters and thresholds are declared here. No magic numbers elsewhere.

cfg = struct();
cfg.seed = 0;

% Capabilities struct written by preflight.m
if exist(fullfile('results', 'caps.mat'), 'file')
    S = load(fullfile('results', 'caps.mat'));
    cfg.caps = S.caps;
else
    % Sensible defaults if preflight hasn't run yet
    cfg.caps = struct();
    cfg.caps.hasExemplar = (exist('inpaintExemplar') > 0); %#ok<EXIST>
    cfg.caps.hasCoherent = (exist('inpaintCoherent') > 0); %#ok<EXIST>
    cfg.caps.hasRegionfill = (exist('regionfill') > 0); %#ok<EXIST>
    cfg.caps.hasMSER     = (exist('detectMSERFeatures') > 0); %#ok<EXIST>
    cfg.caps.hasInsertText = (exist('insertText') > 0); %#ok<EXIST>
    cfg.caps.hasNIQE     = (exist('niqe') > 0); %#ok<EXIST>
    cfg.caps.hasBRISQUE  = (exist('brisque') > 0); %#ok<EXIST>
    cfg.caps.hasSSIM     = (exist('ssim') > 0); %#ok<EXIST>
    cfg.caps.hasPSNR     = (exist('psnr') > 0); %#ok<EXIST>
    cfg.caps.hasExportGraphics = (exist('exportgraphics') > 0); %#ok<EXIST>
    cfg.caps.hasTiledLayout = (exist('tiledlayout') > 0); %#ok<EXIST>
end

% Paths
cfg.paths = struct();
cfg.paths.real  = fullfile('data', 'real');
cfg.paths.clean = fullfile('data', 'clean');
cfg.paths.syn   = fullfile('data', 'synthetic');
cfg.paths.out   = fullfile('results');

% Preprocess & ROI
cfg.pre = struct();
cfg.pre.sigmaHP     = 3;        % high-pass gaussian sigma (px)

cfg.roi = struct();
cfg.roi.stdThresh   = 0.012;    % rows/cols with std below this at edge = frame
cfg.roi.maxFramePx  = 40;       % never strip more than this per side automatically
cfg.roi.shadowPx    = 6;        % extra safety margin after frame strip

% Classification (Autocorrelation)
cfg.cls = struct();
cfg.cls.minLag      = 12;       % ignore peaks closer than this to origin (px)
cfg.cls.zThresh     = 6;        % peak z-score vs autocorr background
cfg.cls.maxPeaks    = 12;       % maximum number of peaks to track
cfg.cls.minOffPeaks = 2;        % >= this many significant peaks => periodic candidate
cfg.cls.minRepeats  = 2;        % repeated-structure count to call 'sparse'

% Generic Evidence (multi-scale white top-hat + edge density)
cfg.gen = struct();
cfg.gen.radii       = [2 3 5 8 12 18];
cfg.gen.edgeSigma   = 6;
cfg.gen.minArea     = 30;
cfg.gen.maxAreaFrac = 0.35;
cfg.gen.minSolidity = 0.15;     % text is not solid; keep low

% Periodic Watermark Detector
cfg.per = struct();
cfg.per.refineIter  = 60;       % fminsearch iterations for lattice refinement
cfg.per.minTiles    = 4;        % need at least this many tile repeats
cfg.per.localGate   = 0.25;     % fraction of local evidence required to keep pixel

% Template / Sparse Watermark Detector
cfg.tpl = struct();
cfg.tpl.scales      = [0.85 0.92 1.0 1.08 1.15];
cfg.tpl.nccThresh   = 0.45;
cfg.tpl.nmsFrac     = 0.6;      % non-max suppression radius as fraction of template size

% Mask Refinement
cfg.mask = struct();
cfg.mask.closeR     = 2;
cfg.mask.minComp    = 20;
cfg.mask.dilateR    = 2;
cfg.mask.useActiveContour = false;

% Removal Methods
cfg.inp = struct();
cfg.inp.coherentSmooth = 3;
cfg.inp.coherentRadius = 5;
cfg.inp.exemplarPatch  = [9 9];

cfg.alpha = struct();
cfg.alpha.W         = [1 1 1];
cfg.alpha.softSigma = 0.7;
cfg.alpha.search    = linspace(0.05, 0.8, 40);
cfg.alpha.maxA      = 0.6;
cfg.alpha.minDen    = 0.15;

cfg.blend = struct();
cfg.blend.featherSigma = 1.5;

% Evaluation Benchmark
cfg.eval = struct();
cfg.eval.nImages     = 24;
cfg.eval.maskAlphaMin = 0.05;
end
