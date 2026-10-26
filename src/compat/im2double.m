function out = im2double(in)
% IM2DOUBLE Convert image to double precision in [0, 1] without toolboxes.
if isfloat(in)
    out = double(in);
elseif isa(in, 'uint8')
    out = double(in) / 255.0;
elseif isa(in, 'uint16')
    out = double(in) / 65535.0;
elseif islogical(in)
    out = double(in);
else
    out = double(in);
end
end
