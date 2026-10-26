classdef testAlphaRecovery < matlab.unittest.TestCase
    % TESTALPHARECOVERY Test accuracy of scalar alpha estimation via edge cancellation.

    methods (Test)
        function testAlphaEstimation(testCase)
            cfg = config();
            H = 150; W = 200;
            
            % Natural background with high-frequency gradient
            rng(42);
            [X, Y] = meshgrid(linspace(0, 1, W), linspace(0, 1, H));
            clean = cat(3, 0.3 + 0.4*X, 0.4 + 0.3*Y, 0.5 - 0.2*X);
            
            % Synthetic watermark mask
            mask = false(H, W);
            mask(40:110, 50:150) = true;
            m = imgaussfilt(double(mask), 0.7);
            
            a0_true = 0.35;
            W_color = reshape([1 1 1], 1, 1, 3);
            
            % Composite watermarked image: I = (1 - a0*m).*clean + a0*m.*W
            marked = (1 - a0_true * m) .* clean + a0_true * m .* W_color;
            
            % Oracle detection struct
            D = struct();
            D.maskTight = mask;
            D.maskDil   = imdilate(mask, strel('disk', 2));
            D.m         = m;
            D.type      = 'oracle';
            D.info      = struct();
            
            % Inpainted estimate (regionfill approximation)
            Jinp = marked;
            for c = 1:3
                Jinp(:,:,c) = regionfill(marked(:,:,c), D.maskDil);
            end
            
            [~, ainfo] = removeAlphaInvert(marked, D, Jinp, cfg);
            
            alphaError = abs(ainfo.a0 - a0_true);
            testCase.verifyLessThan(alphaError, 0.05, ...
                sprintf('Alpha recovery error %.4f exceeds 0.05 tolerance', alphaError));
        end
    end
end
