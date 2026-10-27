function exitCode = run_all()
% RUN_ALL  Master entry point for the Visible Watermark Removal project.
%
% Executes the entire pipeline end-to-end:
%   1. Preflight  – environment & capability inspection
%   2. Synthetic  – benchmark dataset generation (24 cases, 4 types)
%   3. Benchmark  – Auto vs Oracle masks x M1/M2/M3  ->  results/metrics.csv
%   4. Real imgs  – all images in data/real/  (original 5 + new wm* images)
%   5. Unit tests – 9 matlab.unittest suites
%
% Usage:
%   >> run_all           (from MATLAB GUI)
%   matlab -batch "run_all"   (headless)

clc;
startTime = tic;
fprintf('======================================================================\n');
fprintf('   VISIBLE WATERMARK DETECTION & REMOVAL (CLASSICAL DIP PIPELINE)     \n');
fprintf('======================================================================\n\n');

baseDir = fileparts(mfilename('fullpath'));
if isempty(baseDir), baseDir = pwd; end

addpath(baseDir);
addpath(genpath(fullfile(baseDir, 'src')));
addpath(genpath(fullfile(baseDir, 'eval')));
addpath(fullfile(baseDir, 'tests'));

if ~exist(fullfile(baseDir, 'results'), 'dir')
    mkdir(fullfile(baseDir, 'results'));
end

overallErrors = 0;

%% ── STEP 1: PREFLIGHT ──────────────────────────────────────────────────
fprintf('\n>>> STEP 1/5: Running Environment Preflight Check...\n');
try
    preflight();
    fprintf('  [OK] Preflight complete. Capabilities saved to results/caps.mat\n');
catch ME
    warning('Preflight check failed: %s', ME.message);
    overallErrors = overallErrors + 1;
end

%% ── STEP 2: SYNTHETIC DATASET ──────────────────────────────────────────
fprintf('\n>>> STEP 2/5: Generating Synthetic Benchmark Dataset (24 cases)...\n');
try
    cfg = config();
    makeSyntheticDataset(cfg);
    fprintf('  [OK] Synthetic dataset generated in data/synthetic/\n');
catch ME
    warning('Synthetic dataset generation failed: %s', ME.message);
    overallErrors = overallErrors + 1;
end

%% ── STEP 3: QUANTITATIVE BENCHMARK ─────────────────────────────────────
fprintf('\n>>> STEP 3/5: Running Quantitative Benchmark -> results/metrics.csv...\n');
try
    cfg = config();
    runBenchmark(cfg);
    fprintf('  [OK] Benchmark complete. Table saved to results/metrics.csv\n');
catch ME
    warning('Benchmark execution failed: %s', ME.message);
    overallErrors = overallErrors + 1;
end

%% ── STEP 4: REAL IMAGES ─────────────────────────────────────────────────
fprintf('\n>>> STEP 4/5: Running Pipeline on all images in data/real/...\n');
try
    code = main(fullfile(baseDir, 'images')) + main(fullfile(baseDir, 'data', 'real'));
    if code == 0
        fprintf('  [OK] All real images processed. Artifacts saved in results/\n');
    else
        warning('One or more real images encountered errors. See results/errors.log');
        overallErrors = overallErrors + 1;
    end
catch ME
    warning('main() execution failed: %s', ME.message);
    overallErrors = overallErrors + 1;
end

% ── List what was produced ──
outDir = fullfile(baseDir, 'results');
resultDirs = dir(outDir);
resultDirs = resultDirs([resultDirs.isdir] & ~startsWith({resultDirs.name},'.'));
fprintf('  Produced %d result folders in results/\n', numel(resultDirs));

%% ── STEP 5: UNIT TESTS ──────────────────────────────────────────────────
fprintf('\n>>> STEP 5/5: Running matlab.unittest Suite...\n');
numFailedTests = 0;
try
    testResults    = runtests(fullfile(baseDir,'tests'));
    numFailedTests = sum([testResults.Failed]);
    disp(testResults);
    if numFailedTests == 0
        fprintf('  [OK] All %d unit tests PASSED.\n', numel(testResults));
    else
        warning('%d/%d unit tests FAILED.', numFailedTests, numel(testResults));
        overallErrors = overallErrors + numFailedTests;
    end
catch ME
    warning('Unit test suite failed: %s', ME.message);
    overallErrors = overallErrors + 1;
end

%% ── SUMMARY ─────────────────────────────────────────────────────────────
elapsed = toc(startTime);
fprintf('\n======================================================================\n');
fprintf('                       EXECUTION SUMMARY                              \n');
fprintf('======================================================================\n');
fprintf('Total Elapsed Time : %.1f seconds\n', elapsed);
fprintf('Artifacts:\n');
fprintf('  Preflight     : results/preflight.txt, results/caps.mat\n');
fprintf('  Benchmark     : results/metrics.csv\n');
fprintf('  Real images   : results/<name>/{mask,overlay,m1,m2,m3,recommended}.png\n');
fprintf('  Comparisons   : results/comparison_<name>.png (one per image)\n');
fprintf('  Report        : report/README.md\n');

if overallErrors == 0
    fprintf('\n>>> ALL PHASES & TESTS PASSED WITH ZERO ERRORS! <<<\n');
    exitCode = 0;
else
    fprintf('\n>>> COMPLETED WITH %d ERRORS/FAILURES. Check results/errors.log <<<\n', overallErrors);
    exitCode = 1;
end
fprintf('======================================================================\n');
end
