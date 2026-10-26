classdef testLattice < matlab.unittest.TestCase
    % TESTLATTICE Test recovery of known 2D lattice basis vectors.

    methods (Test)
        function testLatticeRecovery(testCase)
            cfg = config();
            
            % Known lattice displacement vectors
            a1_true = [45.0, 10.0];
            a2_true = [-15.0, 40.0];
            
            % Generate peak list around true lattice displacements
            peaksXY = [
                a1_true;
                a2_true;
                a1_true + a2_true;
                2 * a1_true;
                2 * a2_true
            ];
            
            % Identify basis vectors
            [a1_est, a2_est] = findLattice(peaksXY);
            
            % Compare estimated vs ground truth basis vectors
            err1 = norm(a1_est - a1_true);
            err2 = norm(a2_est - a2_true);
            
            testCase.verifyLessThan(err1, 1.0, 'a1 error exceeds 1 pixel tolerance');
            testCase.verifyLessThan(err2, 1.0, 'a2 error exceeds 1 pixel tolerance');
        end
    end
end
