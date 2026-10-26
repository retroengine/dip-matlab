function out = imtophat(A, se)
% IMTOPHAT Morphological top-hat filter (original minus opening).
out = A - imopen(A, se);
if isfloat(out)
    out = max(out, 0);
end
end
