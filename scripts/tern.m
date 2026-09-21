function out = tern(cond, a, b)
%TERN Small ternary-style helper used for PASSED/FAILED print strings.
    if cond
        out = a;
    else
        out = b;
    end
end
