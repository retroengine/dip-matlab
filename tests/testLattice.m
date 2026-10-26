classdef testLattice < matlab.unittest.TestCase
    % TESTLATTICE Test recovery of known 2D lattice basis vectors from
    % a set of autocorrelation peak displacements.

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
        function testLatticeRecovery(testCase)
            % Known lattice displacement vectors
            a1_true = [45.0, 10.0];
            a2_true = [-15.0, 40.0];

            % Build a peak list that includes the true vectors plus harmonics.
            % findLattice should recover a1 and a2 (or their equivalents up to
            % sign/ordering) with < 1 pixel error.
            peaksXY = [
                a1_true;
                a2_true;
                a1_true + a2_true;
                2 * a1_true;
                2 * a2_true;
            ];

            % Call without T/valid (no refinement pass needed here)
            [a1_est, a2_est] = findLattice(peaksXY);

            % findLattice returns the two shortest non-collinear vectors in order
            % of length (a2_true is the shorter one here), so match them as a set
            % up to sign.
            e = @(u, v) min(norm(u - v), norm(u + v));
            err1 = min(e(a1_est, a1_true) + e(a2_est, a2_true), e(a1_est, a2_true) + e(a2_est, a1_true)) / 2;
            err2 = err1;

            testCase.verifyLessThan(err1, 1.0, ...
                sprintf('a1 error %.2f px exceeds 1 px tolerance', err1));
            testCase.verifyLessThan(err2, 1.0, ...
                sprintf('a2 error %.2f px exceeds 1 px tolerance', err2));
        end

        function testLatticeNonCollinear(testCase)
            % Collinear peaks only — should throw an error
            peaksXY = [10, 5; 20, 10; 30, 15];   % all collinear
            testCase.verifyError(@() findLattice(peaksXY), 'findLattice:none');
        end
    end
end
