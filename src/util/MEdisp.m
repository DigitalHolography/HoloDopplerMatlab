function s = MEdisp(ME, path, keyword, message)
% keyword (optionnal): "WARN" or "ERROR" (defaults to ERROR)
% message (optionnal): An additional message

if nargin < 2
    path = "";
end

if nargin < 3
    keyword = "ERROR";
end

if nargin < 4
    message = "";
end

fd = 2;
keyword = string(keyword);
path = string(path);
message = string(message);

if keyword == "WARN" || keyword == "warn"
    fd = 1;
end

s = sprintf("==================================\n");
s = s + centerText(keyword, 34);
s = s + sprintf("\n==================================\n");

if ~(message == "")
    s = s + sprintf("%s\n", message);
end

if ~(path == "")
    s = s + sprintf('Error while processing : %s\n', path);
end

s = s + sprintf("%s\n", ME.identifier);
s = s + sprintf("%s\n", ME.message);

for stackIdx = 1:size(ME.stack, 1)
    s = s + sprintf("%s : %s, line : %d\n", ME.stack(stackIdx).file, ME.stack(stackIdx).name, ME.stack(stackIdx).line);
end

if ME.identifier == "MATLAB:audiovideo:VideoReader:FileNotFound"

    s = s + sprintf("\nNo Raw File was found\n");

end

s = s + sprintf("==================================\n");

if nargout == 0

    if fd == 1
        warning(message);
    end

    fprintf(fd, "%s", s);
end

end

function str = centerText(text, size)
leng = strlength(string(text));
pad = (size - leng) / 2;
str = sprintf("%*s%*s", fix(pad) + leng, text, ceil(pad), "");
end
