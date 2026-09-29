# 凋灵骷髅（Wither Skeleton）长期说明

> 场景：`res://scenes/characters/我的世界/凋灵骷髅.tscn`；脚本：`res://scripts/characters/我的世界/wither_skeleton/wither_skeleton.gd`。
> 本轮验证记录见 `tests/WITHER_SKELETON_20260927.md`；局部回退清单见 `.backups/wither_skeleton_20260927/REVERT.md`。

## 玩法定义（用户确认）

- 唯一主动招式：**石剑两连砍**。伤害窗口 `0.15–0.31` 与 `0.41–0.57`（0.74 秒），随后 0.24 秒收招过渡（整轮 0.98 秒）；每刀对同一敌人最多一次有效伤害（公共 `weapon_tip_sweep` 真实受击形状扫掠，穿墙不可命中）。
- 每刀**实际造成伤害后**施加 3 秒凋零：目标无凋零时为 I 级；已有凋零则在**当前有效等级 +1**（沿用 `mc_status_effects` 的 255 级公共上限），并把本来源寿命刷新为 3 秒。其他来源的等级/剩余时间不受影响，本来源到期后回到其余来源。
- 负效果免疫（`get_minecraft_potion_effect_ratio(false)` 为 0）拒绝凋零但**不拒绝**普通剑伤害；零有效伤害不施加状态。
- 暂停冻结连砍；眩晕、死亡、禁攻取消尚未完成的刀；冷却 `Attack_Cooling=1.2` 秒阻止连发。
- 移动使用普通公共方向/撞墙反弹逻辑；索敌只决定刀的瞄准方向，不能追踪改写移动方向。攻击（含收招）自驱速度为正常的 30%，AI/手控一致，结束或取消立即恢复；击退、地表和牵引等外部速度不乘此减速。
- 手控（C 键）：仅左键 `controlled_attack_action` 起手两连砍，鼠标瞄准、WASD 独立；手控期间 AI 不主动出手。右/中/数字键空。
- 基础属性：生命 420、每刀伤害 24（`Damage`，随当前攻击属性结算）、移动 88；`minecraft_potion_invert_healing_damage = true`（MC 亡灵族）。

## 公共入口复用（不复制算法）

| 能力 | 公共入口 |
| --- | --- |
| 剑扫掠命中几何 | `classes/weapon_tip_sweep.gd::contacts`（含穿墙射线校验） |
| 带类型伤害 | `ball.receive_classified_positional_damage(..., &"ordinary", ..., self)` |
| 凋零施加/等级/来源寿命 | `scripts/effects/我的世界/mc_status_effects.gd::apply_effect / level_of / current`；状态节点沿用 `wither/status.gd` |
| 命中音 | `hit_audio_gain.damage_gain`，`actual > 50` 用 `entity.player.attack.crit` 否则 `entity.player.hurt`（公共 new5 音库） |
| 挥剑音/脚步/环境/受击/死亡生物音 | `scripts/effects/我的世界/mc_native_audio.gd::queue_stream` 安全队列（24 声部、暂停/切场安全），经通用 `scripts/effects/我的世界/mc_creature_voice.gd` 适配 |
| 死亡 | `new5/base.gd` 公共死亡流程 + `mc_visual_effects.death_pose`，保留项目默认死亡音 |
| 威胁显示/AI | `get_debug_attack_regions`（采样中的真实剑段）、`get_debug_detection_regions`（索敌圈/锁定段）、`get_ai_attack_threats` 委托同一数据 |
| 朝向翻转 | 公共 `set_character_visual_flip_h`（着色器 `sprite_flip_h` 通道），不直接写 `image.flip_h` |

`mc_creature_voice.gd` 是纯音频组件：选择由权威端做，播放/声部/优先级/总线全部走 `mc_native_audio`；死亡音 `keep_after_source`，可靠 RPC 去重（serial 单调）。

## 素材来源与许可

- 原版 Bedrock 模型/贴图及 idle/walk 动作（攻击肩部角度为项目适配，不宣称原版攻击动作）：`Images/characters/我的世界/wither_skeleton/SOURCE.json` 固定 Mojang `bedrock-samples` commit `736072450c26a7c67f07b1661f29d9a5ebaa14b1`（`wither_skeleton.geo.json`、`wither_skeleton.animation.json`、`humanoid.animation.json`、`wither_skeleton.png`、`stone_sword.png`、entity json），sha1/sha256 全记录；帧由项目既有离线光栅器（`bake_native_mobs.Baker` + `bake_native_batch2.BatchBaker` 矩阵）投影，`poses.gd` 保存原版右手锚点。
- 生物音效：Java **1.21.4** 官方资产索引 OGG（idle/hurt/death/step 共 13 个），哈希同记录在 `SOURCE.json`；`scripts/characters/我的世界/wither_skeleton/sounds.gd` 只做 preload 索引。
- 许可：原版 Minecraft 素材，遵循 Minecraft EULA/使用指南；无 AI 生成或重绘源素材。使用 `rl_env/Scripts/python.exe tools/build_wither_skeleton_assets.py --rebake` 可离线重烘焙；该选项只读取固定来源、更新投影帧/手锚和元数据，不联网、不改原模型/贴图/音频。下载模式仍拒绝覆盖不同的原始文件。

## 显示/碰撞

- 原生帧 160×224（可见骨架 y55–202），`Image` 局部缩放 0.85（根节点另有 0.2 倍全局缩放，可见世界高约 25，与共享人型足迹一致；脚部对齐碰撞盒底部）；身体碰撞 40×126、受击 38×122（手动拟合，`CharacterAutoFit` 关闭）。
- 石剑为独立持有物：握把对齐原版手锚，长度 `blade_length=14`（约 0.55 倍体高），角度与伤害窗口同一时钟驱动，客户端按权威位姿复刻。
- 最新动作（2026-09-27）：一段50帧原模型肩部姿态覆盖完整0.98秒，抬手到头顶→第一刀向下劈→低位衔接→第二刀向上挑→平滑收招，不再重复两段小幅下砍。第一刀剑角 -110°→80°，第二刀90°→-110°，左右镜像保持先下后上；身体/握把/真实伤害段使用同一时钟和手锚，不再给握把添加脱离手臂的突进偏移。
- 本轮专项验证及局部恢复见 `tests/WITHER_SKELETON_SWING_20260927.md`；原战斗伤害窗口、420HP/24每刀、凋零、冷却、体型和碰撞不变。

## 分类注册

`classes/combat_classification_catalog.gd` 已注册场景与脚本：`entity_kind=character`，`attack_modes=[melee]`，`carriers=[weapon_sweep,status_tick]`，`damage_kinds=[ordinary,wither]`；`mc_creature_voice.gd`、`poses.gd`、`sounds.gd` 按 component/visual 注册。`tests/verify_combat_classification_registry.py` 通过（missing/stale/invalid 全空）。

## 翻译与清单

- `global/translation_catalog.gd`：`凋灵骷髅 / Wither Skeleton`。
- `tests/manual_control_inventory.csv`：左键两连砍、其他键空。
- 录制标题不带 `Mc小球` 前缀。
