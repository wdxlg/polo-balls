# 凋灵骷髅（Wither Skeleton）长期说明

> 场景：`res://scenes/characters/我的世界/凋灵骷髅.tscn`；脚本：`res://scripts/characters/我的世界/wither_skeleton/wither_skeleton.gd`。
> 最新本体/持剑验证与局部恢复见 `tests/WITHER_SKELETON_BODY_20260927.md`；原始接入记录 `tests/WITHER_SKELETON_20260927.md` 保留为历史。

## 玩法定义（用户确认）

- 主动招式一：**石剑两连砍**。伤害窗口 `0.15–0.31` 与 `0.41–0.57`（0.74 秒），随后 0.44 秒收招过渡（整轮 1.18 秒，原1.2秒起手间隔不变）；每刀对同一敌人最多一次有效伤害（公共 `weapon_tip_sweep` 真实受击形状扫掠，穿墙不可命中）。
- 每刀**实际造成伤害后**施加 3 秒凋零：目标无凋零时为 I 级；已有凋零则在**当前有效等级 +1**（沿用 `mc_status_effects` 的 255 级公共上限），并把本来源寿命刷新为 3 秒。其他来源的等级/剩余时间不受影响，本来源到期后回到其余来源。
- 负效果免疫（`get_minecraft_potion_effect_ratio(false)` 为 0）拒绝凋零但**不拒绝**普通剑伤害；零有效伤害不施加状态。
- 暂停冻结连砍；眩晕、死亡、禁攻取消尚未完成的刀；冷却 `Attack_Cooling=1.2` 秒阻止连发。
- 移动使用普通公共方向/撞墙反弹逻辑；索敌只决定刀的瞄准方向，不能追踪改写移动方向。攻击（含收招）自驱速度为正常的 30%，AI/手控一致，结束或取消立即恢复；击退、地表和牵引等外部速度不乘此减速。
- 手控（C 键）：仅左键 `controlled_attack_action` 起手两连砍，鼠标瞄准、WASD 独立；手控期间 AI 不主动出手。右/中/数字键空。
- 基础属性（2026-09-28 用户调整）：生命 **600**、每刀伤害 **20**（`Damage`，随当前攻击属性结算）、移动 88；`minecraft_potion_invert_healing_damage = true`（MC 亡灵族）。下文历史记录中的 420HP/24每刀 已被此值取代。
- 主动招式二（2026-09-28）：**头部凋零烟雾弹**，见文末“头部凋零烟雾弹”一节。

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

- 原生帧 160×224（可见骨架 y55–202），`Image` 局部缩放 **1.214285714**、Y偏移 **−19.285714286**，均为旧值×20/14（根节点仍0.2，可见世界高约36；脚部对齐碰撞盒底部）；身体碰撞 **57.142857×180**、受击 **54.285714×174.285714**（手动拟合，`CharacterAutoFit` 关闭）。
- 石剑为独立持有物：握把对齐原版手锚，长度 `blade_length=20`（约0.56倍新体高，本轮不二次放大）、扫掠半径2.5，有效伤害窗口与刀轨迹同一物理时钟驱动，客户端按权威位姿复刻；无伤害收招单独支持渲染子帧。
- 最新动作（2026-09-27）：一段50帧原模型姿态的源时间为0.98秒；有效两刀不重定时，收招另映射为0.44秒，抬手到头顶→第一刀向下劈→低位衔接→第二刀向上挑→平滑收招，不再重复两段小幅下砍。第一刀剑角 -110°→80°，第二刀90°→-110°，左右镜像保持先下后上；身体/握把/真实伤害段使用同一时钟和手锚，不再给握把添加脱离手臂的突进偏移。
- 本轮专项验证及局部恢复见 `tests/WITHER_SKELETON_SWING_20260927.md`；原战斗伤害窗口、420HP/24每刀、凋零、冷却保持；体型/身体碰撞现按最新用户要求同比放大，不能再用早期尺寸覆盖。

## 全方向瞄准与同向转刀（最新用户确认）

- “360度”是任意方向瞄准挥砍，**不是一刀对周身一圈结算AOE**；刀扫到哪里才在原有效窗口命中哪里。
- 原模型攻击帧另烘焙成身体/右臂两层，`attack_parts.tres` 各50帧；肩部锚点写入 `poses.gd::SHOULDERS`。右臂绕真实肩部随 `combo_heading` 旋转，身体/腿不转；手臂矩阵、握把、剑和实际扫掠一致。待机/走路整身帧不变，死亡恢复完整模型快照。
- 收刀沿上挑方向完整转一圈，再沿同方向对齐持刀角；使用不取模角度，不能用最短角插值吞掉整圈。收刀无伤害、没有第三刀、不显示虚假的预备段。现总时长1.18秒，起手间隔仍1.2秒；原移动减速/两刀规则保持。
- 本轮八方向实战夹具、GPU、边界及局部恢复：`tests/WITHER_SKELETON_AIM360_20260927.md`。上一节直接插值回待机角的收刀方式由本节取代。

## 攻击前伸与缓出收刀（2026-09-27追加）

- 两个伤害窗口中，手/握把/整条实际剑轨迹沿锁定瞄准方向额外前伸 **5世界单位**；起手平滑伸出，收招回到0。肩部固定、沿原手臂纵向延伸，厚度保持；石剑长度现20、扫掠半径2.5；前伸不另外放大臂宽，人物及身体碰撞的独立同比放大见下节。八方向视觉与命中共用同一变换。
- 收刀最新由正弦缓出 `sin(t*PI/2)` 驱动，时长0.44秒（0.74–1.18秒），起速比旧0.24秒三次缓出更温和，持续减速至停稳；手臂朝向/前伸同进度归位。收刀使用固定原版手臂纹理与连续手锚变换，末段接实际持刀手；有效刀窗不重定时。纯收刀采用渲染子帧时钟，暂停冻结、不倒转、不影响物理伤害。
- 1.2秒起手间隔不变；收招低速阶段相应多0.2秒。旧0.24秒三次缓出方案仅为历史。最新真实高刷新检查、验证边界及回退见 `tests/WITHER_SKELETON_SMOOTH_20260927.md`。
- 新增八方向“旧两刀扫掠均打不到、新范围实际能扣血”的验证；本轮实测和局部恢复见 `tests/WITHER_SKELETON_REACH_20260927.md`。

## AI真实可达起手与范围加强（当前）

- 参数为石剑长20、手部前伸5、扫掠半径2.5；对应用户批准的14→20、3→5、2→2.5方案。伤害24/刀、1.2秒起手间隔、两刀有效时刻及平滑收刀不变。
- 58单位只负责发现最近敌人。AI两条起手入口共用真实两刀姿态预检与公共 `weapon_tip_sweep.contacts`，目标当前hurt shape必须能被扫到且未隔墙；预检不修改正在显示的姿态或任何战斗状态。保守包围盒仅作快速排除，不替代精确判定。
- 不追踪移动、不突进、不保证命中运动中的敌人；手控可主动空挥。竖向微小浮点误差采用统一朝向规则，保证预检与真实出刀一致。
- 验证及局部回退：`tests/WITHER_SKELETON_RANGE_20260927.md`。

## 本体同比放大与斜向持剑（最新用户确认）

- 本体宽高按剑上一轮14→20的 **20/14≈1.428571** 比例放大一次；图像偏移、身体碰撞和受击形状同步适配，root缩放/速度/血条不再整体放大，石剑长20保持。肩、手臂和握把都跟随放大后的真实原模型手锚，AI可达检查随真实刀轨迹更新。
- 非挥砍姿态统一**45°斜向上持剑**：朝右时剑尖在右上，朝左时镜像在左上；待机、走路和收刀落点一致，握把贴着手，不用悬空偏移。收刀仍沿上挑方向完成整圈再顺向对齐，不在末帧突然旋回。
- 新持刀角改变部分方向的对齐转角，但0.44秒正弦缓出及1.2秒起手节拍不变；手腕连续性按放大后的身体尺寸归一检查，角度按新转角理论导数和<43°/60Hz双重约束，其他原收刀断言保持。本体同比放大检查见 `tests/WITHER_SKELETON_BODY_20260927.md`；斜持剑后续实测及左右画面见 `tests/WITHER_SKELETON_GRIP_20260927.md`。

## 分类注册

`classes/combat_classification_catalog.gd` 已注册场景与脚本：`entity_kind=character`，`attack_modes=[melee]`，`carriers=[weapon_sweep,status_tick]`，`damage_kinds=[ordinary,wither]`；`mc_creature_voice.gd`、`poses.gd`、`sounds.gd` 按 component/visual 注册。`tests/verify_combat_classification_registry.py` 通过（missing/stale/invalid 全空）。

## 翻译与清单

- `global/translation_catalog.gd`：`凋灵骷髅 / Wither Skeleton`。
- `tests/manual_control_inventory.csv`：左键两连砍、其他键空。
- 录制标题不带 `Mc小球` 前缀。

## 头部凋零烟雾弹（2026-09-28）

- 用户要求：敌人在近战攻击范围外时，头部飞出子弹攻击敌人；伤害 5，同样有凋零；冷却中等；必须在敌人不在近战范围时才能冷却；子弹本体是凋灵头颅拖尾粒子的聚合体并有同样拖尾；带小幅追踪。
- 近战范围 = 石剑索敌半径 `acquisition_range`（58，也是两连砍能否起手的前置半径）。`enemy_outside_melee(U.nearest(self))` 为真时 `bolt_cooldown_left` 才按战斗时间递减；最近敌人在近战范围内、没有敌人、眩晕/死亡/禁攻/暂停时冷却冻结。冷却 **3 秒**，开局为未就绪。
- AI：就绪、不在砍击中、头部到目标无墙阻挡时向最近敌人发射；有墙则保留就绪弹等视线打开。C 键手控：右键发射（同样要求就绪且近战范围内无敌人），朝鼠标方向，追踪鼠标附近 160 内最近敌人。
- 发射点：原版 160×224 帧的脸部像素 (80,86)，经 `image.global_transform` 投影（与手锚同一套换算）。
- 弹道（`scripts/characters/我的世界/wither_skeleton/wither_bolt.gd`）：速度 200、寿命 3 秒；小幅追踪——每秒最多转 1.4 弧度朝目标当前位置（转弯半径约 143，近距离大角度侧向目标追不上），目标死亡后直飞。碰撞与凋灵头颅相同：射线查询 mask 3，跳过自身/友军/死亡单位，非单位即墙；命中或到期散开。
- 伤害：`attack_damage(5/20)`，基础 5，随当前攻击属性缩放；命中走 `receive_classified_positional_damage(..., &"ordinary", ..., self)`（流血类型 pierce），实际扣血后调用与砍击相同的 `apply_stacking_wither`（当前等级 +1、本来源 3 秒）。受击音同砍击规则（≤50 普通/＞50 暴击）。
- 视觉：弹体 = 9 粒凋灵头颅拖尾同款粒子（`wither/big_smoke_0.png`、深灰 0.22/α0.85、宽 8，中心 1 + 内环 3 + 外环 5，缓慢旋转呼吸）；拖尾参数与凋灵头颅一致（每 6 单位 1 粒、寿命 0.5、向后漂移 12）。粒子基于已提交的原版粒子节点 `末影粒子.gd`，未依赖工作区中他人尚未提交的 `mc_visual_effects.sample_smoke_trail/smoke_particle`，独立上限 256。
- AI 躲避：弹体加入 `AI_Hazard`，`kind = wither_skeleton_bolt`，半径 5。
- 联机：权威端模拟伤害；客户端经 `_spawn_bolt_visual` 生成同参数纯视觉副本（同运动学、同拖尾），`_end_bolt_visual` 同步收尾位置。
- 验证：`tests/test_wither_skeleton_bolt.gd` 32/32（属性 600/20、弹伤 5、近战范围内冷却冻结/离开后继续/再进入暂停/眩晕冻结、就绪发射并重置、发射点在原版头部像素内、弹体为同款粒子团、拖尾同款、命中恰好 5 + 凋零 I、第二发叠到 II、伤害随攻击力、单次转向 ≤1.4 rad/s、25° 偏差 300 距离能修正命中、近距离 90° 侧向不追上、暂停冻结、发射者死亡弹体散开）；`tests/test_wither_skeleton.gd` 400/400（基线改为 600/20、每刀 20、右键动作）。真实对局诊断（普通手动模式，Map10x10，对骷髅 10 秒）：近战 3 次命中每刀 20，远程 2 发 2 中，近战范围内冷却冻结，截图确认头部发出烟雾团与拖尾。

### 修订（2026-09-28 同日第二轮，以此为准）

- 用户要求：子弹本体一直旋转；先沿“先向后再向前”的抛物线行动；速度 120；发射要有音效；人物整体缩小到 0.9 倍（用户确认指凋灵骷髅本体，子弹不变）。
- 轨迹：发射初速 100，方向为背离瞄准方向 40°、偏向屏幕上方一侧（竖直发射时偏右）；之后沿瞄准方向恒定拉力 240/s²，路径为真抛物线（后退约 12 单位后折返）；前向速度达到 **120** 后匀速巡航。小幅追踪仍为 1.4 rad/s：抛物线阶段转的是拉力方向，巡航阶段转的是飞行方向。寿命 3→4 秒（速度降低后保持射程）。初速度由纯函数 `launch_velocity` 计算，联机视觉副本同一轨迹。
- 旋转：9 粒子挂在 `SpinningCluster` 下整体持续旋转（每秒 1.25 圈），暂停/停战冻结；各粒子保留轻微呼吸。
- 音效：原版凋灵 `entity.wither.shoot`（项目已校验的 `audio/characters/我的世界/wither/shoot.ogg`，直接 preload，未改他人未提交的 wither/audio.gd），走本角色 `mc_creature_voice`（联机同步、暂停安全），音高 0.9/1.0/1.1 随机、−6 dB。
- 体型 ×0.9（`SIZE_SCALE`）：Image 缩放 1.092857143、Y 偏移 −17.357142857，身体碰撞 51.428571×162、受击 48.857143×156.857143（脚底仍对齐碰撞盒底部）；石剑 18、扫掠半径 2.25、手部前伸 4.5；近战范围（挥剑索敌 + 远程冷却判定）58→**52.2**。上文 57.14×180、1.214、20/2.5/5、58 等为历史值。
- 验证：`test_wither_skeleton_bolt.gd` 41/41（新增：后上方 100 初速、首帧向后上、后退距离≈理论 12.2、无目标弹体二阶差分恒为拉力的真抛物线、巡航 120 向前、持续旋转且暂停冻结、每发一次原版凋灵射击音）；`test_wither_skeleton.gd` 400/400（尺寸断言改为 ×0.9）。真实对局 15 秒：3 发 3 次射击音，近战范围内冷却冻结 196/198 帧，截图确认拖尾先向后弯出再折向敌人；因速度降到 120 且带弧线，移动中的骷髅躲开了这 3 发（此前 200 速时 2 发 2 中）。
