classdef testFold < matlab.unittest.TestCase
    % TESTFOLD Test tile folding consensus for perfectly periodic patterns.

    methods (Test)
        function testPeriodicReconstruction(testCase)
            H = 120; W = 160;
            a1 = [40, 0];
            a2 = [0, 30];
            
            % Generate canonical tile
            [X, Y] = meshgrid(0:W-1, 0:H-1);
            fx = mod(X, a1(1)) / a1(1);
            fy = mod(Y, a2(2)) / a2(2);
            
            % Periodic pattern
            T = double(sin(2 * pi * fx) .* cos(2 * pi * fy) > 0);
            valid = true(H, W);
            
            [~, evid, ~] = foldTiles(T, valid, a1, a2);
            
            % Interior points should match consensus pattern
            interior = valid(5:end-5, 5:end-5);
            diffs = abs(T(interior) - evid(interior));
            maxErr = max(diffs(:));
            
            testCase.verifyLessThan(maxErr, 1e-4, 'Folded evidence diverges from periodic ground truth');
        end
    end
end
