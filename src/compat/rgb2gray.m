function gray = rgb2gray(rgb)
% RGB2GRAY Convert RGB image to grayscale without toolbox dependencies.

if size(rgb, 3) == 1
    gray = rgb;
    return;
end

wasUint8 = isa(rgb, 'uint8');
if wasUint8
    rgb = double(rgb);
end

gray = 0.2989 * rgb(:,:,1) + 0.5870 * rgb(:,:,2) + 0.1140 * rgb(:,:,3);

if wasUint8
    gray = uint8(min(max(round(gray), 0), 255));
end

end
