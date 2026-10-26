function out = bwareaopen(BW, P, conn)
% BWAREAOPEN Remove small objects from binary image with zero toolbox dependencies.

if nargin < 3, conn = 8; end
BW = logical(BW);
[H, W] = size(BW);
out = false(H, W);
if ~any(BW(:)) || P <= 1
    out = BW;
    return;
end

labeled = zeros(H, W);
currentLabel = 0;
sizes = [];

for r = 1:H
    for c = 1:W
        if BW(r, c) && labeled(r, c) == 0
            currentLabel = currentLabel + 1;
            
            % Breadth-first search queue
            queue = zeros(500, 2);
            queue(1, :) = [r, c];
            qHead = 1;
            qTail = 1;
            labeled(r, c) = currentLabel;
            
            while qHead <= qTail
                cr = queue(qHead, 1);
                cc = queue(qHead, 2);
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
                    nc = cc + dcList(n);
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
            sizes(currentLabel) = qTail; %#ok<AGROW>
        end
    end
end

validLabels = find(sizes >= P);
if ~isempty(validLabels)
    out = ismember(labeled, validLabels);
end

end
