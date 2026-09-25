# 地图边界立体墙与定向内影（2026-09-25）

## 范围与规则

- 覆盖六种现有背景：蓝色、草方块、沙地、石砖、下界岩、末地石；覆盖普通大小地图与传送门多岛地图的实际暴露边。只改**地图的边界墙**，不改角色建造的障碍、技能墙、人物和投射物。
- 地图继续使用 Godot 2D 战场。`地图立体墙.gd` 在现有边缘上画 2.5D 墙顶、纹理侧面与细高光；五种 Minecraft 墙顶仍是现有的一格原版方块贴图，蓝色主题新增深蓝色墙顶。没有增加 3D 物理模型、碰撞体或新贴图。
- `World` 默认光源方向 `Vector2(1,-1)`（右上方），墙身和投影朝左下。Inspector 中可调 `map_wall_light_direction`、`map_wall_height_cells=0.65`、`map_wall_shadow_cells=2.4`；最后两项以当前地图的格子尺寸为单位。零光向回退到右上，不会产生无效向量。
- 阴影复用 `地图内沿阴影.gdshader` 的单次合成：按每段真墙扫出斜向阴影，仅在真实地面多边形内显示，阴影在远端渐隐；所有边取最大值，转角不双倍变黑。西墙、南墙保留淡的接触阴影而不会违反光向向场内投射主影。原 `configure(rect,...)` 保留旧版四向柔和内沿，用于兼容矩形采样调用。
- 墙身/墙顶画布为一节点、绝对 `z=99`，位于地图外遮罩 `90` 后、已有黑边与门 `100` 前；地面投影保持绝对 `z=-4`，不盖过 `z=-3` 状态信息框、人物或投射物。未改 `TileMapLayer`、安全墙、导航、物理图层、地图尺寸和相机取景。

## 门洞与多岛

- 立体侧面与投影使用 World 已扣除服务员门和传送门缺口的同一份 `TileGeometry.edges` 线段，门开时同步断开。贴图地图原有木/石墙顶也必须按真实开门缺口裁掉，不能只断开新侧面；`_map_shape_walls` 仅减去当前地图/岛的开门段，外侧棋盘随之补齐，黑色外边线不在缺口处封口。关门后恢复。
- 物理安全墙仍由既有代码负责，未改变它的缺口宽度或传送规则；蓝色背景及 PortalMap 的现有门洞仍可通行。阴影着色只铺在 `map_island_rects` 地面上，不会在多岛之间的空区制造另一片地面。

## 验证命令与结果

Windows PowerShell 可使用 `E:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`，项目路径 `E:\godot\polo-balls`，以 `Start-Process -FilePath $godot -ArgumentList @('--headless','--path',$project,'-s','res://tests/test_map_wall_3d.gd') -PassThru -Wait` 运行无头测试；真实 GPU 测试移除 `--headless` 并添加 `--rendering-driver d3d12`。检查子进程 ExitCode，不能只看测试脚本打印的通过数。

| 入口 | 结果 | 核查范围 |
| --- | --- | --- |
| `tests/test_map_wall_3d.gd`，无头 | 45/45、退出码 0 | 六背景、Map10x10/Map50x50/Map_Portal、光向/层级、真实墙射线与安全墙几何、开门时五种方块墙顶和投影均让出缺口。 |
| `tests/test_map_wall_3d_visual.gd`，D3D12 | 25/25、成功复跑退出码 0 | GPU 阴影北/东墙更深、门洞断影、改变光向反转；六主题真实 World 截图和开门截图；逐一隐藏/显示墙身的画面对照。成功复跑的有效采样像素变化：蓝 6271、草 1342、沙 1363、石 1121、下界 555、末地 1365。 |
| `tests/test_ground_visual_sampling.gd`，D3D12 | `failures=0`、退出码 0 | 旧矩形阴影仍保留无双倍转角、渐隐和门洞；对照外沿阴影的夹具改为使用生产的矩形并集配置，不再以空参数运行旧 shader。 |
| `scripts/training/test_mc_backgrounds.gd`，无头 | 126/126、退出码 0 | 六背景主题、纹理/取景/设置项和切换回归。 |
| `tests/test_portal_shared_wall.gd`，无头 | 19/19、退出码 0 | 多岛共享墙缝、传送门外影和视觉裁剪。 |
| `tests/test_mc13_revision.gd`，无头 | 21/21、退出码 0 | 蓝/草背景与真实墙碰撞、缩放和现有地图系统。 |

截图在 Godot `user://map_wall_3d/`：`shadow_default.png`、`shadow_door.png`、`world_blue.png`～`world_end.png`、`world_grass_door.png`；测试 stdout/stderr 与修改前备份在 `E:\godot\polo-balls-checkpoints\map_walls_3d_20260925\`。GPU 截图已检查六主题和开门后的真实视觉；未进行完整双客户端联机战斗或实战 FPS 压力基准。

一次 D3D12 运行在全部 25 条断言通过后、退出阶段返回 `-1073741819`；重复运行同一脚本退出码为 0。该次 stderr 同时含其他角色资源预热/缺失素材的报错，不将偶发进程异常归因于本修改，也不宣称已解决这些既存资源问题。

## 隔离与回退

开始前分支为 `main`，当时 HEAD `346cc56c4beed14e5d12c4c6b23dec65c2f21cc7`。已单独备份原 `scripts/world.gd`、原阴影脚本/着色器、当时未提交的上下文和原 Git 差异到上述 checkpoint；工作期间有别的任务推进了 HEAD。提交时只暂存本任务的精确代码片段、测试、UID、说明文档和 `MCP_CONTEXT.md` 本任务索引行，其他任务的未提交修改仍在工作区。原有六主题注册脚本 `地图背景主题.gd` 在本次任务开始前已是另一项工作的未跟踪依赖，本任务复用但不将其混入本次提交；因此局部提交不能冒充整个项目的独立、干净快照。回退前再次核对/备份当前文件，优先撤销本任务的精确补丁或提交，切勿整仓 `reset --hard` / `clean -fd`。
