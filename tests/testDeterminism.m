classdef testDeterminism < matlab.unittest.TestCase
    % TESTDETERMINISM Test reproducible and deterministic output across multiple runs.

    methods (Test)
        function testSeededDeterminism(testCase)
            cfg = config();
            rng(cfg.seed);
            
            % Generate synthetic test image
            H = 80; W = 80;
            [X, Y] = meshgrid(linspace(0, 1, W), linspace(0, 1, H));
            clean = cat(3, X, Y, 0.5 * ones(H, W));
            
            mask = false(H, W);
            mask(25:55, 25:55) = true;
            marked = (1 - 0.3 * mask) .* clean + 0.3 * mask;
            
            % Run inpaint twice with same seed
            rng(cfg.seed);
            J1 = removeInpaint(marked, mask, 'coherent', cfg);
            J1 = blendResult(marked, J1, mask, cfg);
            
            rng(cfg.seed);
            J2 = removeInpaint(marked, mask, 'coherent', cfg);
            J2 = blendResult(marked, J2, mask, cfg);
            
            diffRuns = abs(J1(:) - J2(:));
            maxDiff = max(diffRuns);
            
            testCase.verifyEqual(maxDiff, 0.0, 'Pipeline outputs differ between seeded runs');
        end
    end
end
