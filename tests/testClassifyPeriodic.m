classdef testClassifyPeriodic < matlab.unittest.TestCase
    % TESTCLASSIFYPERIODIC Test autocorrelation classification for periodic vs non-periodic images.

    methods (TestClassSetup)
        function setupPaths(testCase)
            thisDir = fileparts(mfilename('fullpath'));
            rootDir = fileparts(thisDir);
            addpath(rootDir);
            addpath(genpath(fullfile(rootDir, 'src')));
            addpath(genpath(fullfile(rootDir, 'eval')));
        end
    end

    methods (Test)
        function testPeriodicVsPlain(testCase)
            cfg = config();
            H = 250; W = 350;
            
            % 1. Plain natural image (smooth gradient + fine noise)
            rng(0);
            [X, Y] = meshgrid(linspace(0, 1, W), linspace(0, 1, H));
            plain = cat(3, 0.4 + 0.3*Y + 0.05*rand(H, W), ...
                           0.5 + 0.2*X + 0.05*rand(H, W), ...
                           0.3 + 0.4*Y + 0.05*rand(H, W));
            plain = min(max(plain, 0), 1);
            
            P_plain = preprocess(plain, cfg);
            [typePlain, ~] = classifyWatermark(P_plain, cfg);
            testCase.verifyNotEqual(typePlain, 'periodic', 'Plain natural image falsely classified as periodic');
            
            % 2. Periodic watermark overlay
            a1_true = [50, 0];
            a2_true = [0, 50];
            pattern = zeros(H, W);
            for y = 10:a2_true(2):H
                for x = 10:a1_true(1):W
                    x2 = min(W, x + 15);
                    y2 = min(H, y + 15);
                    pattern(y:y2, x:x2) = 1.0;
                end
            end
            
            watermarked = (1 - 0.35 * pattern) .* plain + 0.35 * pattern;
            watermarked = min(max(watermarked, 0), 1);
            
            P_wm = preprocess(watermarked, cfg);
            [typeWM, infoWM] = classifyWatermark(P_wm, cfg);
            testCase.verifyEqual(typeWM, 'periodic', 'Periodic pattern failed periodic classification');
        end
    end
end
