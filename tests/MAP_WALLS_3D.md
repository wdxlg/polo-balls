# 地图边界的原版 Minecraft 方块真 3D（2026-09-26）

## 范围、材质与蓝色例外

- **草地、沙地、石地、下界、末地**的地图边界以及地图形状造成的内侧边界使用真实 3D 方块：每段墙按地图格拆成封闭的六面网格（`MeshInstance3D` / `ArrayMesh`），经透明的独立 `SubViewport`、正交 `Camera3D`、环境补光和带阴影的 `DirectionalLight3D` 渲染。不是 2D 多边形、画布假侧面或预烘焙 3D 图片。
- 每个方块顶面 / 四侧 / 底面分材质：草地为**橡木原木**顶纹 + 橡木树皮；沙地为**砂岩**顶纹 + 原版砂岩侧面 + 原版底面；石地为**深板岩砖**六面；下界为**下界砖**六面；末地为**紫珀柱**顶纹 + 原版紫珀柱侧面。纹理按一格一格重复、最近邻采样，不把一格侧面拉成整条墙。块间有不到一屏幕像素的 3D 棱缝；偏暗主题用同一张原版纹理作少量自发光填充，砂岩和紫珀各自降低补光以保留原色。
- **蓝色背景完全不建 3D 墙**：保持原本平面蓝色地图及黑色边框。初始蓝色不分配墙体 3D Viewport；由方块主题切回蓝色时隐藏网格并停止该 Viewport 更新。蓝色墙的地面暗边仅作 2D 接触阴影，不再假装有高墙投下长影。
- 战场、人物和碰撞仍是原先的 Godot 2D。正交相机的地面投影做逆变换，3D 方块的基底与既有 2D 地图格在不同地图大小上对齐；相机俯角不会逐格累积位置误差。`World.map_wall_height_cells` 默认为 **1.80** 格（可调），灯光方向沿用 `map_wall_light_direction`，3D 画布只在地图/主题/门改变时重绘并限制单边像素不超过 4096。

## 地图形状、开门与现有行为

- 方块脚印直接采用 `_map_shape_walls()` 的墙矩形；其生成已减去真实地面、传送门空区和服务员开门缺口。服务员门打开时同时裁掉立体网格及原 2D 墙顶，门的端面也是立体方块面，关闭后重建。覆盖普通尺寸地图、50×50 地图及传送门多岛地图；不会把外接矩形填成假墙。
- 地面仍由原有 2D 主题绘制；**地面上的斜向投影仍是现有 2D 地表着色器**，只在真实地面多边形内按扣门后的边缘投影。这一点不冒充 3D 地面接影；3D 方块本体及其受光、侧面和相互遮挡是真实 3D。2D 地面阴影位于人物/状态框下方，立体墙体位于地图外遮罩之后、现有边框和门扇之前。
- 没有修改 TileMapLayer、`_map_safety_frame`、2D 物理形状、碰撞层、导航、地图尺寸、角色建造的障碍墙或技能墙。

## 原版资源及依赖

- 新引入的 `sandstone.png`、`sandstone_bottom.png`、`purpur_pillar_side.png` 原样摘自 **Minecraft Java Edition 26.2** 官方 client.jar；JAR SHA-1、Mojang 下载地址及每个 PNG 的 JAR 条目、大小、SHA-1 均记录在 `Images/effects/我的世界/草方块背景/wall_side_sources.json`。橡木树皮复用项目已有 `Images/characters/我的世界/sulfur_cube/source/oak_log.png`，其来源见同角色 `sources.json`。资源属于 Minecraft 原版，不表示可自由再分发。
- 顶面和其他主题纹理来自项目现有 `地图背景主题.gd`；本任务开始前，多主题定义及多张顶面 PNG 已是另一工作项的**未跟踪依赖**。本任务不将那些工作项文件混入本次局部提交。因此只检出本次提交、而没有原多主题资源的全新克隆**不能**当作完整项目快照；当前工作区具备这些依赖并已完成真实 GPU 验证。

## 验证（Godot 4.7.2 / Windows / D3D12）

用 `E:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe` 在 `E:\godot\polo-balls` 运行。GPU 用 `--rendering-driver d3d12 --path <项目目录> -s <脚本>`，无头测试加 `--headless`；Windows PowerShell 建议 `Start-Process -PassThru -Wait -RedirectStandardOutput ... -RedirectStandardError ...` 获取子进程真正的 ExitCode，而不是只看打印的通过数。

| 入口 | 实际结果 | 重点 |
| --- | --- | --- |
| `tests/test_map_wall_3d.gd`，无头 | **77/77，退出码 0** | 六主题、3D 模型三个材质面和 6 面顶点、相机跨格对齐、光源、碰撞射线/安全墙不变、50×50/多岛、服务员门五主题裁墙、切回蓝色关闭 3D。 |
| `tests/test_map_wall_3d_visual.gd`，D3D12 | **37/37，退出码 0** | 真 GPU 3D 纹理可见且与平面画面对照；反转光照改变实际 3D 受光；门中心真实 3D 像素清空；50×50 / PortalMap 单独的 3D 画面；五主题与蓝色主场景截图。 |
| `tests/test_ground_visual_sampling.gd`，D3D12 | **failures=0，退出码 0** | 地表阴影连续、拐角不叠黑、门洞断影及旧地表取样。 |
| `scripts/training/test_mc_backgrounds.gd`，无头 | **126/126，退出码 0** | 六主题底图/取景/设置切换。 |
| `tests/test_portal_shared_wall.gd`，无头 | **19/19，退出码 0** | 多岛共享边、门口及外侧视觉。 |
| `tests/test_mc13_revision.gd`，无头 | **21/21，退出码 0** | 既有地图碰撞、缩放与 MC 对战回归。 |

实机截图保存在 Godot `user://map_wall_true3d/`：`world_blue_detail.png`、`world_grass_detail.png` ～ `world_end_detail.png`、`world_grass_door_detail.png`、`wall_mesh_grass.png`、`wall_mesh_Map50x50.png`、`wall_mesh_Map_Portal.png`；已逐一目视检查不同方块材质和开门、多岛的画面。运行日志和修改前备份保存在 `E:\godot\polo-balls-checkpoints\map_walls_true3d_20260926\`。历史角色的资源缺失/路径大小写告警仍会出现在 stderr，本任务没有修复；未做完整双客户端联机战斗或长期 FPS 压力基准。

## 隔离、提交与回退

本轮开始 HEAD 是已隔离的旧 **2.5D** 提交 `ebdd0bf343d29dcdd1ee7a493d777786410fe547`；旧效果被明确否定，新的 `地图立体墙.gd` 已完全替换为真实 3D 实现。其他任务工作期间 HEAD 有继续前进，`scripts/world.gd` 与 `MCP_CONTEXT.md` 还有与本任务无关的未提交差异；提交时只用精准索引补丁暂存自己的 World / 上下文片段，其他路径逐一核对后暂存，不执行 `git add .`、整仓清理或硬重置。回退前再次备份当前状态，优先针对本任务提交执行定向 `git revert` 或反向应用本任务独有的补丁，不要覆盖并行任务尚未提交的文件。
