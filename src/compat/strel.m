classdef strel
    % STREL Structuring element for morphological image processing.
    % Zero toolbox dependencies implementation for disks, squares, and lines.

    properties
        Neighborhood
    end

    methods
        function obj = strel(shape, varargin)
            if nargin == 0
                obj.Neighborhood = true(3, 3);
                return;
            end
            
            switch lower(shape)
                case 'disk'
                    r = varargin{1};
                    [x, y] = meshgrid(-r:r, -r:r);
                    obj.Neighborhood = (x.^2 + y.^2) <= (r + 0.5)^2;
                    
                case 'square'
                    w = varargin{1};
                    obj.Neighborhood = true(w, w);
                    
                case 'line'
                    len = varargin{1};
                    ang = 0;
                    if numel(varargin) >= 2
                        ang = varargin{2};
                    end
                    if ang == 0
                        obj.Neighborhood = true(1, len);
                    elseif ang == 90
                        obj.Neighborhood = true(len, 1);
                    else
                        rad = ang * pi / 180;
                        dx = round((len/2) * cos(rad));
                        dy = round((len/2) * sin(rad));
                        w = 2 * max(abs(dx), abs(dy)) + 1;
                        canvas = false(w, w);
                        cx = floor(w/2) + 1;
                        for t = linspace(-len/2, len/2, 2*len+1)
                            px = round(cx + t * cos(rad));
                            py = round(cx - t * sin(rad));
                            if px >= 1 && px <= w && py >= 1 && py <= w
                                canvas(py, px) = true;
                            end
                        end
                        obj.Neighborhood = canvas;
                    end
                    
                otherwise
                    obj.Neighborhood = true(3, 3);
            end
        end
    end
end
