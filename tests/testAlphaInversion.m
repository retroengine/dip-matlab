classdef testAlphaInversion < matlab.unittest.TestCase
    % TESTALPHAINVERSION Test algebraic inversion fidelity with oracle parameters.

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
        function testExactReconstruction(testCase)
            H = 100; W = 100;
            rng(7);
            clean = rand(H, W, 3);
            
            mask = false(H, W);
            mask(20:80, 20:80) = true;
            m = double(mask);
            
            a0 = 0.35;
            W_color = reshape([1 1 1], 1, 1, 3);
            
            % Generate marked image
            marked = (1 - a0 * m) .* clean + a0 * m .* W_color;
            
            % Exact inversion
            denom = 1 - a0 * m;
            restored = (marked - a0 * m .* W_color) ./ denom;
            
            % PSNR inside mask
            diffMask = (restored(repmat(mask, [1 1 3])) - clean(repmat(mask, [1 1 3]))).^2;
            mse = mean(diffMask(:));
            psnrVal = 10 * log10(1.0 / max(mse, 1e-12));
            
            testCase.verifyGreaterThan(psnrVal, 40.0, ...
                sprintf('Inversion PSNR %.2f dB is below required 40 dB', psnrVal));
        end
    end
end
