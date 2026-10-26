function exitCode = run_all()
% RUN_ALL Master entry point for the Visible Watermark Removal project.
%
% Running this single script executes the entire pipeline end-to-end:
%   1. Preflight environment & capability inspection
%   2. Synthetic benchmark dataset generation (24 test cases across 4 types)
%   3. Quantitative evaluation benchmark (Auto vs Oracle masks x M1/M2/M3) -> results/metrics.csv
%   4. Pipeline execution on all 5 real test images (data/real/) -> results/<name>/... & comparison PNGs
%   5. Comprehensive unit test suite execution (9 test suites)
%
% Can be run from MATLAB GUI:
%   >> run_all
% Or headless from terminal:
%   matlab -batch "run_all"

clc;
startTime = tic;
fprintf('======================================================================\n');
fprintf('   VISIBLE WATERMARK DETECTION & REMOVAL (CLASSICAL DIP PIPELINE)     \n');
fprintf('======================================================================\n\n');

% Ensure src, eval, and tests folders are in MATLAB path
baseDir = fileparts(mfilename('fullpath'));
if isempty(baseDir), baseDir = pwd; end
addpath(genpath(fullfile(baseDir, 'src')));
addpath(genpath(fullfile(baseDir, 'eval')));
addpath(fullfile(baseDir, 'tests'));

if ~exist(fullfile(baseDir, 'results'), 'dir')
    mkdir(fullfile(baseDir, 'results'));
end

overallErrors = 0;

%% STEP 1: PREFLIGHT CHECK
fprintf('\n>>> STEP 1/5: Running Environment Preflight Check...\n');
try
    caps = preflight();
    fprintf('  [OK] Preflight complete. Capabilities saved to results/caps.mat\n');
catch ME
    warning('Preflight check failed: %s', ME.message);
    overallErrors = overallErrors + 1;
end

%% STEP 2: SYNTHETIC DATASET GENERATION
fprintf('\n>>> STEP 2/5: Generating Synthetic Benchmark Dataset (24 cases)...\n');
try
    cfg = config();
    makeSyntheticDataset(cfg);
    fprintf('  [OK] Synthetic dataset generated in data/synthetic/\n');
catch ME
    warning('Synthetic dataset generation failed: %s', ME.message);
    overallErrors = overallErrors + 1;
end

%% STEP 3: SYNTHETIC BENCHMARK EVALUATION
fprintf('\n>>> STEP 3/5: Running Quantitative Benchmark & Exporting results/metrics.csv...\n');
try
    cfg = config();
    summaryTable = runBenchmark(cfg);
    fprintf('  [OK] Quantitative benchmark complete. Table saved to results/metrics.csv\n');
catch ME
    warning('Benchmark execution failed: %s', ME.message);
    overallErrors = overallErrors + 1;
end

%% STEP 4: REAL IMAGES PIPELINE EXECUTION
fprintf('\n>>> STEP 4/5: Running Watermark Pipeline on Real Test Images (data/real/)...\n');
try
    realInputDir = fullfile(baseDir, 'data', 'real');
    code = main(realInputDir);
    if code == 0
        fprintf('  [OK] Real images processed. Output artifacts saved in results/\n');
    else
        warning('One or more real images encountered errors during main() execution.');
        overallErrors = overallErrors + 1;
    end
catch ME
    warning('main() execution failed: %s', ME.message);
    overallErrors = overallErrors + 1;
end

%% STEP 5: UNIT TEST SUITE
fprintf('\n>>> STEP 5/5: Running matlab.unittest Suite (9 tests)...\n');
numFailedTests = 0;
try
    testResults = runtests('tests');
    disp(testResults);
    numFailedTests = sum([testResults.Failed]);
    if numFailedTests == 0
        fprintf('  [OK] All %d unit tests PASSED successfully!\n', numel(testResults));
    else
        warning('%d out of %d unit tests FAILED.', numFailedTests, numel(testResults));
        overallErrors = overallErrors + numFailedTests;
    end
catch ME
    warning('Unit test suite execution failed: %s', ME.message);
    overallErrors = overallErrors + 1;
end

%% SUMMARY
elapsedTime = toc(startTime);
fprintf('\n======================================================================\n');
fprintf('                       EXECUTION SUMMARY                              \n');
fprintf('======================================================================\n');
fprintf('Total Elapsed Time: %.1f seconds\n', elapsedTime);
fprintf('Key Artifacts Generated:\n');
fprintf('  1. Preflight Report:     results/preflight.txt & results/caps.mat\n');
fprintf('  2. Benchmark Metrics:    results/metrics.csv\n');
fprintf('  3. Real Image Results:   results/w1_sample_tiled/ ... results/w5_zoner_single/\n');
fprintf('  4. Comparisons:          results/comparison_w1_sample_tiled.png ...\n');
fprintf('  5. Full Report:          report/README.md & report/phase_log.md\n');

if overallErrors == 0
    fprintf('\n>>> ALL PHASES & TESTS PASSED WITH ZERO ERRORS! <<<\n');
    exitCode = 0;
else
    fprintf('\n>>> COMPLETED WITH %d ERRORS/FAILURES. Check logs for details. <<<\n', overallErrors);
    exitCode = 1;
end
fprintf('======================================================================\n');

end
