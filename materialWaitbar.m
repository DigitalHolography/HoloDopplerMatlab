function materialWaitbar(h)
%MATERIALWAITBAR Apply the Material dark palette to a waitbar window.
bg = [33 31 38] / 255;      txt = [230 224 233] / 255;
primary = [208 188 255] / 255; track = [74 68 88] / 255;
if isempty(h) || ~isgraphics(h), return; end
safeSet(h, 'Color', bg);
safeSet(findall(h, 'Type', 'axes'), 'Color', track, 'XColor', track, 'YColor', track);
safeSet(findall(h, 'Type', 'patch'), 'FaceColor', primary, 'EdgeColor', 'none');
safeSet(findall(h, 'Type', 'text'), 'Color', txt, 'Interpreter', 'none');
safeSet(findall(h, 'Type', 'uilabel'), 'FontColor', txt);
safeSet(findall(h, 'Type', 'uigridlayout'), 'BackgroundColor', bg);
end

function safeSet(objs, varargin)
for k = 1:numel(objs)
    for j = 1:2:numel(varargin)
        try, objs(k).(varargin{j}) = varargin{j + 1}; catch, end
    end
end
end
