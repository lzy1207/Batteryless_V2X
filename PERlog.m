figPath = 'D:\matlab_project\Single User full PHY\Single User full PHY_MIMO\compare1000PER.fig';

% 1) 打开fig（不改原文件）
fig = openfig(figPath, 'new', 'visible');

% 2) 找到坐标轴
ax = findobj(fig, 'Type', 'axes');
ax = ax(1);  % 通常第一个就是主axes

% 3) 处理 log 轴无法显示的 0/负值：给一个“PER地板值”
%    对于1000包，0 errors 通常可用 0.5/1000 或 1/1000 做地板
perFloor = 0.5/1000;

ln = findobj(ax, 'Type', 'line');
for k = 1:numel(ln)
    y = get(ln(k), 'YData');
    y(y <= 0) = perFloor;      % 把 0 替换为地板值
    set(ln(k), 'YData', y);
end

% 4) 设置纵轴为log
set(ax, 'YScale', 'log');
ylim(ax, [perFloor 1]);        % 你也可以改成 [1e-4 1] 等
grid(ax, 'on');

% 5) 另存为新fig（避免覆盖原文件）
[newDir, baseName, ~] = fileparts(figPath);
savefig(fig, fullfile(newDir, [baseName '_logY.fig']));
