figPath = 'D:\matlab_project\Single User full PHY\Single User full PHY_MIMO\compare1000Glaze.fig';

% 打开fig（不覆盖原图）
fig = openfig(figPath, 'new', 'visible');

% 找到坐标轴
ax = findobj(fig, 'Type', 'axes');
ax = ax(1);

% 0-PER 的“地板值”：1000包时，0 errors 可用 0.5/1000 或 1/1000
perFloor = 0.5/1000;

% 把所有曲线的 YData 中的 0/负值替换成地板值
ln = findobj(ax, 'Type', 'line');
for k = 1:numel(ln)
    y = get(ln(k), 'YData');
    y(y <= 0) = perFloor;
    set(ln(k), 'YData', y);
end

% 设为log纵轴
set(ax, 'YScale', 'log');
ylim(ax, [perFloor 1]);    % 你也可改成 [1e-4 1] 等
grid(ax, 'on');

% 另存为新fig，避免覆盖原文件
[newDir, baseName, ~] = fileparts(figPath);
savefig(fig, fullfile(newDir, [baseName '_logY.fig']));
