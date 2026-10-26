classdef testRoi < matlab.unittest.TestCase
    % TESTROI Test automatic frame and border detection.
    % Assertion: A synthetic image with a 15 px flat white frame gets
    % valid == false in the frame and true inside.

    methods (Test)
        function testFrameExclusion(testCase)
            cfg = config();
            H = 200; W = 300;
            frameWidth = 15;
            
            % Create natural textured interior with random noise
            rng(0);
            interior = 0.5 + 0.2 * rand(H - 2*frameWidth, W - 2*frameWidth);
            
            % Add flat white frame (value 1.0) around border
            img = ones(H, W);
            img(frameWidth+1:end-frameWidth, frameWidth+1:end-frameWidth) = interior;
            
            valid = findROI(img, cfg);
            
            % Test that outer frame borders are marked invalid (false)
            testCase.verifyFalse(any(valid(1:frameWidth, :), 'all'), 'Top frame not excluded');
            testCase.verifyFalse(any(valid(end-frameWidth+1:end, :), 'all'), 'Bottom frame not excluded');
            testCase.verifyFalse(any(valid(:, 1:frameWidth), 'all'), 'Left frame not excluded');
            testCase.verifyFalse(any(valid(:, end-frameWidth+1:end), 'all'), 'Right frame not excluded');
            
            % Test that central region is valid (true)
            centerR = round(H/2);
            centerC = round(W/2);
            testCase.verifyTrue(valid(centerR, centerC), 'Interior center marked invalid');
        end
    end
end
