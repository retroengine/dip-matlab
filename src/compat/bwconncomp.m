function cc = bwconncomp(BW, conn)
% BWCONNCOMP Find connected components in binary image with zero toolbox dependencies.

if nargin < 2, conn = 8; end
BW = logical(BW);
[H, W] = size(BW);

cc = struct();
cc.Connectivity = conn;
cc.ImageSize = [H, W];
cc.NumObjects = 0;
cc.PixelIdxList = {};

if ~any(BW(:))
    return;
end

labeled = zeros(H, W);
currentLabel = 0;
pixelLists = {};

for r = 1:H
    for c = 1:W
        if BW(r, c) && labeled(r, c) == 0
            currentLabel = currentLabel + 1;
            
            queue = zeros(300, 2);
            queue(1, :) = [r, c];
            qHead = 1;
            qTail = 1;
            labeled(r, c) = currentLabel;
            
            while qHead <= qTail
                cr = queue(qHead, 1);
                ccol = queue(qHead, 2);
                qHead = qHead + 1;
                
                if conn == 8
                    drList = [-1 -1 -1  0 0  1 1 1];
                    dcList = [-1  0  1 -1 1 -1 0 1];
                else
                    drList = [-1 0 0 1];
                    dcList = [0 -1 1 0];
                end
                
                for n = 1:numel(drList)
                    nr = cr + drList(n);
                    nc = ccol + dcList(n);
                    if nr >= 1 && nr <= H && nc >= 1 && nc <= W
                        if BW(nr, nc) && labeled(nr, nc) == 0
                            labeled(nr, nc) = currentLabel;
                            qTail = qTail + 1;
                            if qTail > size(queue, 1)
                                queue = [queue; zeros(size(queue, 1), 2)]; %#ok<AGROW>
                            end
                            queue(qTail, :) = [nr, nc];
                        end
                    end
                end
            end
            
            % Convert (row, col) to linear indices
            pixels = queue(1:qTail, :);
            linIdx = sub2ind([H, W], pixels(:, 1), pixels(:, 2));
            pixelLists{currentLabel} = linIdx; %#ok<AGROW>
        end
    end
end

cc.NumObjects = currentLabel;
cc.PixelIdxList = pixelLists;

end
