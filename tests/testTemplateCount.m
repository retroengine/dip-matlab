classdef testTemplateCount < matlab.unittest.TestCase
    % TESTTEMPLATECOUNT Test template instance discovery and localization.

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
        function testRepeatedLogoDetection(testCase)
            cfg = config();
            H = 300; W = 400;
            
            % Synthesize template
            tplH = 25; tplW = 40;
            tpl = zeros(tplH, tplW);
            tpl(5:20, 10:30) = 1.0;
            
            % Paste N = 5 instances at known distinct positions
            positions = [
                [40, 50];
                [40, 200];
                [180, 80];
                [180, 260];
                [110, 150]
            ];
            N = size(positions, 1);
            
            T = zeros(H, W);
            for k = 1:N
                py = positions(k, 1);
                px = positions(k, 2);
                T(py:py+tplH-1, px:px+tplW-1) = tpl;
            end
            
            info = struct();
            info.tpl = tpl;
            info.tplBox = [positions(1, 2), positions(1, 1), tplW, tplH];
            
            P = struct();
            P.I = repmat(T, [1 1 3]);
            P.gray = T;
            P.valid = true(H, W);
            P.hp = T;
            
            D = detectTemplate(P, cfg, info);
            
            testCase.verifyEqual(D.info.instanceCount, N, 'Detected template count does not match pasted instance count N');
        end
    end
end
