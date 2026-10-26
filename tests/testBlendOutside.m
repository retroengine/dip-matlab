classdef testBlendOutside < matlab.unittest.TestCase
    % TESTBLENDOUTSIDE Test that blendResult preserves bit-identical original pixels outside mask.

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
        function testBitExactPreservation(testCase)
            cfg = config();
            H = 100; W = 100;
            rng(10);
            I = rand(H, W, 3);
            J = rand(H, W, 3); % Distorted / modified image
            
            % Small mask in center
            maskDil = false(H, W);
            maskDil(40:60, 40:60) = true;
            
            Jout = blendResult(I, J, maskDil, cfg);
            
            % Support envelope outside 3 * sigma
            se = strel('disk', ceil(3 * cfg.blend.featherSigma));
            support = imdilate(maskDil, se);
            outside = ~support;
            
            % Verify bit-exact equivalence
            diffOutside = abs(Jout(repmat(outside, [1 1 3])) - I(repmat(outside, [1 1 3])));
            maxDiff = max(diffOutside(:));
            
            testCase.verifyEqual(maxDiff, 0.0, 'Pixels outside feathered mask are not bit-identical to original image');
        end
    end
end
