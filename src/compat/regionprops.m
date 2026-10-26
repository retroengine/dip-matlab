function stats = regionprops(cc, varargin)
% REGIONPROPS Measure image region properties with zero toolbox dependencies.

if islogical(cc) || isnumeric(cc)
    cc = bwconncomp(cc);
end

numObjs = cc.NumObjects;
stats = repmat(struct('Area', 0, 'BoundingBox', [0 0 0 0], 'Centroid', [0 0], ...
                      'Solidity', 1.0, 'PixelIdxList', []), numObjs, 1);

H = cc.ImageSize(1);
W = cc.ImageSize(2);

for k = 1:numObjs
    pix = cc.PixelIdxList{k};
    area = numel(pix);
    stats(k).Area = area;
    stats(k).PixelIdxList = pix;
    
    if area > 0
        [rows, cols] = ind2sub([H, W], pix);
        minR = min(rows); maxR = max(rows);
        minC = min(cols); maxC = max(cols);
        
        boxW = maxC - minC + 1;
        boxH = maxR - minR + 1;
        
        stats(k).BoundingBox = [minC - 0.5, minR - 0.5, boxW, boxH];
        stats(k).Centroid = [mean(cols), mean(rows)];
        
        bboxArea = boxW * boxH;
        stats(k).Solidity = area / max(bboxArea, 1);
    end
end

end
