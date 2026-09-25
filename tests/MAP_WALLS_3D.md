# 地图墙：一格高原版方块、移动透视和真实地影（2026-09-26）

## 行为与范围

- **草地、沙地、石地、下界、末地**的地图外边界及形状造成的内侧边界，由实际六面 `ArrayMesh` 方块构成，**严格一地图格高**。模型脚印直接取 `World._map_shape_walls()` 已扣除岛屿、传送门和服务员门洞的墙矩形；格间细缝和门洞断面是真实的 3D 几何，不是 2.5D 画布侧面。
- 草地用原版**橡木原木**顶面和树皮；沙地用**砂岩**顶/侧/底；石地用**深板岩砖**；下界用**下界砖**；末地用**紫珀柱**顶/侧。面纹理按格铺设、最近邻采样；纹理及 Mojang 来源见 `Images/effects/我的世界/草方块背景/wall_side_sources.json`。
- **蓝色地图仍是平面**：启动时不创建 3D 墙；由其它主题切回蓝色时隐藏墙并停掉两路 3D Viewport。原有蓝色边框、2D 地面、原物理墙和角色建造的障碍不变。
- 五主题定义和完整背景切换依赖当前工作区已有的另一项并行改动（相关纹理、`地图背景主题.gd`、`world.gd` 的其它片段）；本提交不把它们混入索引。**只检出本次提交而缺少那些依赖的旧快照，并不是已验证的完整项目状态。**
- `World.map_wall_height_cells` 的旧 1.8 格可调高度已经撤销为内部的 1.0 格；渲染脚本自身也始终把高度固定为一个地图格，不受旧调用参数影响。旧的 `map_wall_shadow_cells` 手绘长影开关已删除，避免假投影叠加真实地影。`map_inside_shadow` 仅保留贴边的 2D 接触暗边。

## 为什么镜头移动时有 3D，影子为什么可见

- 上一版**整图正交贴图 / `UPDATE_ONCE` 已弃用**。现在使用 90° 俯视的**透视 Camera3D**，在每一帧从实际 Camera2D 的画布变换取屏幕中心和 zoom，计算与 2D 地图对齐的地面投影，再更新 3D 相机和屏幕贴合的 Sprite2D。地面点保持逐像素重合；高出地面的一格方块会产生随镜头位置变化的透视视差和受光侧面。测试中，同一块墙从两侧观察，其顶面相对底面的水平位移从 **+16.4** 变为 **−13.9** 个 3D 视口像素，而非只平移同一张图片。两路透明 SubViewport 按当前屏幕取景更新，单边最大 2560 像素，不再渲染整幅超大地图。
- 地面三角面只铺在真实岛屿区域，由 `DirectionalLight3D` 对共用方块网格的 **shadows-only 实例**投出影子；这是 3D 光源、3D 遮挡和 3D 接影面计算的 GPU 阴影，最终单独合成为 2D 地面上的暗影。原版方块画面与接影画面分开，避免 `shadow_to_opacity` 在全黑处变成不透明白斑并错误盖住场景。光从右上射入，地影朝左下；反转光源时影子实际换到另一边。
- 特别将 `DirectionalLight3D.directional_shadow_max_distance` 根据当前 3D 相机高度动态加大。Godot 默认的 100 单位会在俯视相机较高时把所有地面阴影裁掉——这是上一版“有光无影”的直接原因。两路 3D Viewport 在离开世界时先停更，然后由 Godot 回收。

## 验证（Godot 4.7.2 / Windows / D3D12）

在 `E:\godot\polo-balls` 用 `E:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe` 运行；无头测试加 `--headless`，真实 GPU 截图测试加 `--rendering-driver d3d12`。用 `Start-Process -PassThru -Wait` 检查**进程退出码**，不只看打印的通过数。

| 入口 | 本次结果 | 核验要点 |
| --- | --- | --- |
| `tests/test_map_wall_3d.gd`，无头 | **93/93，退出码 0** | 六主题、一格高度、两路真实 3D 通道、视差和地面对齐、50×50/多岛、门洞、蓝色停更、碰撞射线/安全墙不变。 |
| `tests/test_map_wall_3d_visual.gd`，D3D12 | **44/44，退出码 0** | 五材质的真实 GPU 网格；接影只在地面附近有 alpha、在空地消失；合成到草地/沙地的像素明显变暗；左右平移同一墙方块视差反向；倒转光源影子换边；开门和大地图截图。 |
| `tests/test_ground_visual_sampling.gd`，D3D12 | **failures=0，退出码 0** | 既有接触暗边、地面取色、拐角及门口渐隐不回归。 |
| `scripts/training/test_mc_backgrounds.gd`，无头 | **126/126，退出码 0** | 六主题底图与设置切换。 |
| `tests/test_portal_shared_wall.gd`，无头 | **19/19；复跑退出码 0** | 多岛共享墙和传送门；首次运行打印 19/19 后进程意外退出，复跑正常，详见下文。 |
| `tests/test_mc13_revision.gd`，无头 | **21/21，退出码 0** | 地图碰撞、缩放等既有玩法回归。 |

截图在项目 Godot `user://map_wall_true3d/`：`world_grass_camera_left.png` / `world_grass_camera_right.png`、`world_grass_detail.png` ～ `world_end_detail.png`、`shadow_receiver_grass.png`、`world_grass_door_detail.png`、`wall_mesh_Map50x50.png` 和 `wall_mesh_Map_Portal.png`。运行日志与改动前备份在 `E:\godot\polo-balls-checkpoints\map_walls_camera_shadow_20260926\`。既有其他角色的资源路径/UID 告警仍可能出现；一次并行回归批次中的 Portal 测试打印全通过后以 Windows access violation 退出，单独复跑为退出码 0；已在地图墙节点退出树时主动停止实时 GPU 视口。未宣称完成长时间 FPS 或双客户端联机压力测试。

## 隔离与回退

本轮只提交地图 3D 墙、World 中与该墙直接相关的三处配置、两套墙测试及本说明；不混入同时进行的 `world.gd`/其他功能差异。提交时对 `world.gd` 用精确索引补丁而非 `git add .`。旧碰撞/角色建造墙没有改变；若需回退，请针对本次提交定向恢复，先保留其它人的工作区改动。
