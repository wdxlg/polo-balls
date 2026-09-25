# Minecraft 原版方块云与参数开关（2026-09-26）

## 用户选择 / 现在的行为

用户要求原版 Minecraft 风格的云、设置参数开关，并明确选择：**蓝色背景用战场上空云；草地背景用背景云**。

- `设置 → 参数 → 原版方块云`，位于背景选择下方，默认开启，立即生效并通过既有 `Game.save_persistent_settings()` 保存。旧存档没有此项时开启。英文 `Minecraft Clouds`。
- 蓝色：世界绝对Z=3000，在人物/特效/场外裁剪之上、昼夜乘色和独立菜单CanvasLayer之下；云会从战场和人物上方经过。
- 草地：Z=-5，在场外蓝色背景上、墙/人物/状态框下；云只绘制在地图所有可见岛的补集，不盖住草地竞技场。沙地、石砖、下界、末地、庭院、山巅等其余非蓝主题沿用背景层；这是本项目地图主题规则，不声称模拟原版各维度的天气规则。
- 切地图自动换层，保留漂移相位；关闭立即隐藏并停止推进，开启从原相位继续。暂停冻结，倍速只使用已缩放的物理delta一次；重置归零，无布阵的空重打不改变相位。
- 纯环境效果，不参与伤害/威胁/碰撞，不使用战斗RNG。开关与背景选择一样是本机偏好，不向房间广播；菜单仍遵守原有房客权限限制，未扩大权限。

## 素材与呈现

原文件：`Images/effects/我的世界/clouds/clouds.png`，Minecraft Java **1.21.4** `assets/minecraft/textures/environment/clouds.png`。256×256，占用13356个白色像素，其余52180透明。

- SHA256 `18b72300292efa39f15f0f0e9b77f339b9c9237d054cf8141681ad25f047374f`。
- 镜像仓库 `InventivetalentDev/minecraft-assets`，固定提交 `58d92c8cee4c7ac22d02988fb2bc3e4648af9ef2`；完整固定URL、来源和许可记录在同目录 `SOURCE.json`。
- PNG原字节未改；不是随机噪声、手画轮廓或生成图片。Mojang/Microsoft 原版素材，不是自由再分发许可。
- 采用原版精美云的方格厚层思路：每格12×12、厚4，战场适配4世界像素/方块，即48px网格、16px厚度；透明度0.8，顶面/两侧明暗1/0.9/0.8，0.03块/tick对应2.4世界px/s缓慢西移。
- `minecraft_clouds.gdshader` 用原始alpha占用和正交体素层求交绘制硬边顶面/侧面，最多穿过两个网格边界；不堆每朵云的节点，不新开3D视口。**这是原版云轮廓/体块在本项目俯视战场中的投影适配，不是整个 Minecraft 天空/天气渲染器**。
- 共用一张纹理、一个材质，场外几何复用 `World._map_outside_rects/_current_visual_island_rects`；不复制地图形状算法。雾中人原有雾粒子不是这类天空云，未复用其非原版云片或修改其行为。
- Shader不读墙钟时间，不依赖主相机SCREEN_UV；主画面、总览/共享World2D录制视口用同一云相位，既有昼夜乘色覆盖云。

## 实际验证

引擎：项目 Godot 4.7.2 offline；GPU：OpenGL Compatibility / NVIDIA RTX 4060 Laptop。资源导入退出0，无新增脚本/Shader编译错误。

| 测试 | 结果 | 说明 |
| --- | --- | --- |
| `test_minecraft_clouds.gd` | **45/45** | 原纹理占用、原版体块GPU、蓝/草地层级、其余6主题、真实多岛、开关/实际UI按钮/磁盘保存与重载、暂停/漂移/负delta、节点复用/真实重置、共享录制视口、云昼夜变暗 |
| `test_day_night_cycle.gd`，专用harness | 33/33 | 云关闭，保留原昼夜逻辑断言 |
| `test_map_wall_tooltips.gd`，专用harness | 84/84 | 云关闭，旧地图墙/信息框层级回归 |
| `test_heavenfall_muzzle_ring.gd`，原夹具 | 41/41 | 上一任务伪3D发射环回归 |
| `test_day_night_visual.gd`，专用harness | **31/39，8失败** | 不能记作整套通过，见下文 |

前4套共203项通过。不要把这项统计描述为“所有回归零失败”。

云GPU：512×384隔离画面有65216个云像素；顶面/两侧实测亮度级100/90/80；70个云格中心逐一匹配原贴图alpha。一格漂移后图像精确平移、不重新生成形状。蓝色云覆盖实际人物层红色探针；草地开/关云时竞技场内部0像素变化、场外有云；两份相同投影的共享World2D视口全图字节相同。已读回并查看蓝色与草地实机截图：`user://minecraft_clouds_blue.png`、`minecraft_clouds_grass.png`、`minecraft_clouds_native_volume.png`。

### 旧昼夜GPU问题的边界（未在本任务修复）

旧 `test_day_night_visual.gd` 的草地暮色/午夜/清晨与沙/石/下界/末地地面亮度有8项未通过。**关闭云时和专门释放云节点后均为同样的8项失败、相同采样值**：草地正午0.135588、18:00为0.173322、午夜0.170871。云功能自己的夜间变暗检查通过；不能据此说旧地面亮度也通过，亦不把该问题未经归因归咎于云。本次不改旧昼夜/墙光照算法。

首轮直接运行旧昼夜逻辑夹具虽33断言通过，但退出时后台资源预热产生资源加载错误。新增 `verify_cloud_legacy_regressions.py` 只在临时夹具里：关闭云以比较旧画面基线、在后台预热deferred开始前释放预热器、将旧frame_post_draw等待替换为force_draw。原测试文件不改、原断言保留。这样逻辑33和墙84重跑退出0且无上述脚本错误。释放云节点的隔离复现参数：`--remove-cloud-node`。

```text
<engine> --path . --script res://tests/test_minecraft_clouds.gd --rendering-method gl_compatibility --audio-driver Dummy
python tests/verify_cloud_legacy_regressions.py
python tests/verify_cloud_legacy_regressions.py test_day_night_visual --remove-cloud-node
```

日志：`tests/minecraft_clouds_gpu.log`、`tests/test_*_cloud_harness.log`、`tests/test_day_night_visual_cloud_removed_harness.log`、`tests/test_heavenfall_muzzle_ring_cloud_final.log`。

未验证：两个独立客户端、实际双语视频编码、低端GPU帧率/极端缩放压力、长期运行。共享World2D GPU对照不是视频编码验收。原有shader UID/大小写警告仍在。

## 文件和回退

主要入口：`scripts/effects/我的世界/minecraft_clouds.gd`、`shaders/minecraft_clouds.gdshader`；World只负责创建、物理推进、地图/开关刷新与重置。复用原参数开关、持久化和翻译入口；CSV、编译期词典及两份运行时翻译资源均包含新标签。

开始前HEAD `69d265d819c2a6c7bd98dff72c2656cdb7e3c869`；检查点 `E:/godot/polo-balls-tools/checkpoints/minecraft-clouds-20260926-054505`。已有工作区改动保留。两份翻译二进制在导入前已脏，已从该检查点预先保存的完整binary patch还原到检查点副本；未回写覆盖当前文件。提交版本的翻译二进制由HEAD CSV+本次一条翻译生成，不将其他未提交翻译混入。

回退补丁 `tests/patches/minecraft_clouds_20260926.patch` 包含本次代码、原版PNG及导入配置、Shader/脚本UID、测试/说明和翻译资源增量。关闭游戏/编辑器，另备份当前状态，再运行 `git apply --reverse --check <补丁>`；检查通过才可去掉 `--check` 手动回退。回退范围仅本次云功能，不回退长弓或其他任务。仅检查，不实际执行回退；不使用全库reset。提交前后ID记录于检查点 `commit_result.json` 与最终回复。
