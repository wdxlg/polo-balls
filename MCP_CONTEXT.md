# polo-balls 项目规则与接入说明

这是项目所有者维护的当前规则。通过 ShunCode MCP 接入时，先理解本文件再修改，不需要用户重复提醒。规则描述开发要求，不代表相关功能已经实现或测试通过。代码是数值和实现细节的唯一事实来源；本文件只记录从代码里看不出、以后修改时必须遵守的约束和公共入口。

## 0. 说明文件纪律（最高优先级，严格遵守）

- **项目内只允许两份说明文件**：根目录 `AGENTS.md`（入口）和本文件 `MCP_CONTEXT.md`（唯一规则正文）。**禁止新建**任何其他说明性文件：`.md`/`.txt`/README/使用说明/设计文档/测试报告/验证记录/更新说明/变更日志/交付记录/回退说明/会话笔记等，无论放在根目录、`docs/`、`tests/`、`scripts/`、`tools/`、`.backups/`、`.arena_*` 还是项目外的 `polo-balls-checkpoints/`。
- **禁止保存本文件或 AGENTS.md 的旧版本/备份副本**（如 `MCP_CONTEXT.before.md`、`context.before.md`、检查点目录里的副本）。需要旧版本时用 Git 历史。
- 测试结果、通过项数、复现过程、截图结论和回退方式**只在对话里向用户报告**，不落盘。可回退依据是 Git 提交，提交信息写清改了什么。
- 本文件**只写长期有效的规则和公共入口**。禁止写：更新流水、日期标签、"最新修订/替代上一条"、测试项数、验证过程、"详见某某.md"、已被取代的旧规则、单个角色的全部数值。规则变了就原地改写对应条目，不追加新段落；新内容先看能否并入已有条目。
- 本文件必须保持在 **64 KiB 以下**（Bridge 自动附带的单文件上限，超出部分模型看不到），越短越好。
- 代码注释同样只写说明非显然意图或约束的简短注释。禁止在代码里写更新记录、日期、"用户要求…"、测试结果或大段说明。
- **用户说"写注释/在注释里说明逻辑"，指的是写在本文件（MCP 注释）对应条目里，不是写进代码。**
- **临时文件用完立即删除（严格遵守）**：命令日志（`.log/.err/.stdout/.stderr`）、截图、跑分/验证结果 json、`.patch/.diff/.bak/.before` 备份、传输分片（`.b64`）、测试用户数据目录、一次性脚本、训练曲线等，一律写到系统临时目录或 `user://`，不得写进项目目录。用完直接删除，最迟在本次任务结束前删完；不提交 Git，不留"以后可能有用"的副本。回退只靠 Git 提交，不另建备份目录（如 `.backups/`、`tools/checkpoints/`、`.arena_*`）。`.gitignore` 已忽略这些类型，但被忽略不等于可以留着。
- 例外：第三方素材/代码按许可必须随附的 `LICENSE`/`NOTICE`/`SOURCE.json`/来源 txt 属于法律归属文件，保留，但不写成说明文档。

## 1. 协作、验证与 Git 回退

- 先读文件再修改；有版本哈希时用 `expected_versions` 防并发覆盖。版本过期就重新读取合并，不用旧副本覆盖。发现另一段对话正在改同一文件时，暂停冲突范围并协调。
- 修改后运行相关诊断、测试与必要的真实画面检查。只报告实际完成的验证，区分静态检查、夹具测试、真实 GPU 渲染和双客户端联机。静态分类、装载成功、旧测试记录都不等于全角色实战通过。
- 用户的核心目标是**能快速、明确地回退到更新前/后的版本**，默认用本地 Git 提交，没有远程也能恢复。
- 修改前检查分支、工作区和暂存区，记下更新前的提交 ID。不得覆盖其他对话的工作。
- 每个独立更新验证后建一个描述清楚的提交，纳入运行必需的代码、场景和素材。只提交本次负责的改动：禁止不核对就 `git add .`，禁止混入凭据、缓存、依赖、大型训练产物或别人的未完成改动，不清空别人的暂存区。
- 完成时报告：更新前/后提交 ID、验证结果、可恢复范围。有未纳入版本的其他改动要说明。
- 回退前先备份当前修改，优先撤销指定提交或恢复指定文件。未经确认不得 `reset --hard`、`clean -fd`、强制推送。只有用户明确授权才推送远程，不擅自创建公开仓库。
- 常用入口：`scripts/world.gd`、`global/game.gd`、`ui/control.gd`、`classes/ball.gd`、`scripts/training/combat_threat_analyzer.gd`。按任务定位，不随意扩大修改范围。
- **Windows 保护发布**：入口 `导出加密Windows版.cmd` / `python tools/protected_export.py export`，使用与离线录制补丁一致的专用 Release 模板，资源与目录全部加密、脚本二进制化；缺密钥、模板不匹配或验证失败必须停止，不允许退回明文。模板通过 `python tools/protected_export.py build` 编译到项目外 `../polo-balls-tools/protected-export/`；私钥只保存在本机账户的 `%LOCALAPPDATA%/PoloBalls/ProtectedExport/`，编辑器凭据在已忽略的 `.godot/export_credentials.cfg`。密钥不得输出、提交或随游戏分发；测试/构建源码不进发布包，运行数据及第三方许可仍保留。加密只提高拆包门槛，不承诺防止逆向。
- Headless 测试：`godot --headless --path . --script res://tests/<脚本>.gd`，退出码 0 为通过。需要 GPU 的测试去掉 `--headless`。`preview_*`/`live_*` 只是摆拍，不作验证依据。

## 2. 伤害结算与伤害音效

- **高伤害特殊反馈**：设置 → 参数的 `High_Damage_Feedback` 为本机开关，默认开，只控制命中拉近与重击顿挫。拉近锚点取本次真实伤害来源：重锤看重锤、子弹看子弹，不追溯射手/Master；中毒、流血等自身状态扣血看承伤角色。命中时冻结世界坐标并随反馈 RPC 传递，不能依赖仍存活的弹体或持久击杀归因；嵌套结算和船载分摊不得串用来源。空间伤害可用 `focus_position` 显式分离视觉来源与 `source` 归属，持续状态的 `carrier=status_tick` 取承伤者；这些信息只改变拉近，不改变伤害、防御或归因。关闭立即清除这两项已排队/播放中的反馈，不影响角色主动时停、剧情镜头和普通抖动。人物受击抖动与镜头伤害抖动按结算后单次实际生命伤害分三档，默认 **≤10 几乎不可见、10<伤害≤50 轻微、>50 明显**，各档内均随伤害增长，高档渐近上限而非过早截平；高档最大强度仍须保留伤害增长空间，旧技能的镜头抖动也跟随“明显抖动强度”。开关下只显示简明调节：抖动三档各一个强度，同时作用于身体与镜头；特殊反馈只留拉近倍率、时停速度、时停时长。不要重新拆出门槛、曲线、起始/极限等高级项目；关闭收起但保留参数，提供本组恢复默认；`global/feedback_settings.gd` 统一登记、校验和曲线，数值属于本机偏好，不改变战斗伤害或 MC 音效阈值。纯护盾最多轻微档，同帧多个命中取最强，不能累计越级。

- **属性结算（全角色强制）**：身体碰撞、近战、投射物、范围/持续伤害、召唤物，都由实际攻击者的**当前**相关属性计算，承伤由受击者当前属性结算。技能的基础值和系数只能作为公式参数，不得把常量当作最终伤害或减伤。
- **MC 伤害音效（全局）**：以结算后实际生命损失为准（封顶到受击前剩余生命，不用面板值、技能标记、过量伤害或范围最大值）。**≤50 播 MC 普通受击，>50 播 MC 暴击**，严格是 `damage > 50`。基础增益 0 dB，随实际伤害增加（`hit_audio_gain.damage_gain`，上限 +6 dB），不得整体压低基础音量，也不得继承原版暴击事件的 0.7 衰减。纯护盾吸收或零伤害不出声。
- 统一实现是 `scripts/effects/我的世界/mc_hit_feedback.gd`：`ball.gd` 的位置/空间/分类伤害和 hitbox 结算在知道真实承伤者和最终生命损失后调用 `settled(...)`；原本没有通用反馈的持续伤害（凋零、冻结、药水等）用 `finish(...)`。角色策略登记在该文件的 `POLICIES`。同一次结算只出一份反馈，不重复叠播。网络上由承伤实体的权威端选变体，经可靠 RPC `request_mc_damage_audio` 同步。
- 明确例外：石矛 0<伤害<50 用原版 `minecraft:item.spear.hit`，=50 普通受击，>50 暴击。武器挥舞/发射/爆炸/专属材质命中、角色受伤叫声是独立层，不受阈值规则影响。
- **带类型伤害**：`ball.receive_classified_positional_damage(damage,point,kind,ignore_block,source)` / `receive_classified_spatial_damage(damage,space,kind,ignore_block,raw_health)`。合法 kind：`ordinary/fire/cold/poison/wither/bleed/drowning/magic`（`physical` 映射为 ordinary）。未知类型、非有限值、矛盾的 kind/element、非权威端结算都会被拒绝。
- **火焰就是火焰伤害**：用 `receive_fire_positional_damage()` / `receive_fire_spatial_damage()`，施加灼烧前查 `can_receive_fire_status()`，保留火焰倍率、火免和药水火抗。普通爆炸不自动算火焰。混合攻击的普通冲击和火焰分量分别登记、分别结算。
- 寒冷用 `receive_cold_*` 与 `can_receive_cold_status()`；雪球直击仍是普通伤害并保留击退。内部流血只能走 `receive_internal_status_damage`（仅 bleed，不能拿来绕过火/寒免疫）。
- 船载分摊先分配未乘元素倍率的伤害，再由每名成员按自己的免疫和倍率结算。
- **被吸收的生命伤害**：计时模式不死停在 1 HP 的部分、无限生命目标（不死盔甲架）吸收的全部伤害都记入 `ball.absorbed_health_loss`（只增不减）。凡是用 before/after 生命算实际掉血的地方（吸血、荆棘、命中反馈、MC 受击音效、战斗统计）都要加回期间增量，或直接比较两次 `health_loss_reading()`。无限生命目标因此与普通盔甲架结算一致，只有 INF 级伤害或特定机制（出界等强制死亡）能击杀；它自己只出受伤镜头和叫声，爆射线与 MC 受击音效由结算方按吸收量生成，不得重复叠加。
- 瞄准可以读取手控鼠标，但**命中筛选必须用被攻击对象的真实位置**，不能用会被替换成鼠标位置的 `combat_target_position`。
- **友伤开关只管普通命中，不管锁定和特殊伤害**：`Have_Team_Damage` 只决定身体接触/标准命中（`hitbox.gd`）打到队友是否扣血；允许读取该开关的只有 `hitbox.gd`、`Sans.gd`（闪避）和 `生成地形安全管理器.gd`。任何自写的敌人判断/选敌函数都必须和 World 的 `_nearest_enemy_candidate_distance_sq` 一致：排除同 Team（除非 `Can_Target_Teammates`）和自己的召唤物，不得写成“友伤关闭才排除队友”。角色自写的特殊伤害（范围、弹幕、火场、吸血、召唤物伤害等）无论开关如何都不选中、不伤同 Team；强制友伤只能用 `Ignore_Team_Damage_Setting`/`force_friendly_fire` 显式声明，背刺鼠、背刺者是有意的友伤角色。

## 3. 真实威胁显示（新角色强制）

- 每个新角色的实际威胁区域都要能在「设置 → 威胁显示」里看到。显示必须与实际伤害判定一致：位置、形状、大小、方向、持续时间、启停时机都要对上，不能用图片外框、角色半径或估计的圆代替。
- 身体碰撞、近战、投射物、射线、范围、持续地面伤害和召唤物都按真实机制注册，优先复用 `hitbox`、`CollisionShape2D`、`AI_Hazard`、`get_ai_hazard_info`、`get_ai_attack_threats`。
- 颜色语义：白到红表示真实伤害区域（越红伤害越高），绿色表示无伤害的物理碰撞，低透明蓝色表示检测/起手范围。关闭显示立即清理，不留残影。

## 4. 素材来源

- 「我的世界」分区的音效、图片、动画、粒子取自原版游戏或对应模组已有资源，不自绘、不合成、不用生成素材冒充原版，可以在引擎里组合、裁切、播放。在同目录 `SOURCE.json` 记录来源、版本和许可，不要把"来源于原版"误写成可自由再分发。
- 其他分区用户要求网上取材时，同样在 `SOURCE.json` 记录 URL 和许可。原始大素材包不入 Git。

## 5. 跨角色公共实现（强制复用）

- **默认移动（全角色强制）**：角色只要没有明确的特殊移动说明，就沿用公共正常移动逻辑（`ball.move/stand`、原有方向与碰撞反弹、手控 WASD）。攻击索敌和武器瞄准不得改写普通移动方向，不擅自添加追敌、转向、减速或停步。只有明确说明的冲刺、飞行等特殊阶段可以覆盖移动，阶段结束后恢复公共移动；已有明确指定的移动例外仍按对应规则执行。

新增或修改技能前先查已有实现。同一语义调用公共实现，用参数、回调或子类保留差异，**不得复制近似算法**。只有证明机制确实不同才能新建实现，并在下表补充一行。技能只在权威端结算，RPC 同步视觉和破坏。

| 需求 | 唯一入口 | 要点 |
|---|---|---|
| 武器尖端连续扫掠 | `classes/weapon_tip_sweep.gd::contacts(caster,start,finish,radius,excluded,anchor)` | 只查几何不扣血；调用方负责轨迹细分、公式、去重。钻石长矛/石矛共用 |
| 真实墙接触 | `ball.wall_contact_impact(normal_speed,point)` 信号；`SurfaceAcceleration.reflect_momentum(normal)` | 来自公共 move/stand 的真实碰撞去重，伤害由订阅者按当前属性结算 |
| 雷电 | `mc_combat_abilities.gd::lightning(parent,point,seed,radius,warning,options)` | `tuning` 调表现，`on_impact` 只在权威端接伤害 |
| 平面击退/眩晕 | `target.apply_knockback(dir,dist,speed,bounce,stun,{"source":caster,...})` / `apply_stun(duration,caster)` | 不复制 `knockback_effect.gd`，不裸写 `Repel` |
| 可挣脱的非独占牵引 | `knockback_effect.gd::set_pull/release_pull/pull_velocity` | 每物理步刷新自己的速度贡献，不累加、不锁输入，来源失效自动剔除 |
| 不改属性的实际运动减速 | `ball.set_motion_speed_factor(key,source,factor,left)` / `motion_speed_factor()` / `motion_scaled_delta(delta)` | 只缩放公共 move/stand 和自写强位移的真实速度，不改 `Speed`；按来源租约过期，同一目标多条限制取乘积 |
| 真实身体击飞 | `scripts/effects/physical_airborne_effect.gd::launch(...)`；`landed_at` 或子类 `_on_landing` | 可选钩子 `on_forced_motion_collision(collision)` |
| 地表方向加速 | `scripts/effects/surface_acceleration.gd::touch(target,surface)`；目标可选 `get_surface_acceleration_speed_limit(default)` | 沿真实位移积分，重叠取上限；默认额外上限为基础速度 ×1.5；走 `ball.surface_motion_velocity` |
| 临时角色对免碰撞 | `classes/body_collision_exclusions.gd::acquire/release/are_excluded` | 按 holder 租约，不改层/掩码 |
| 砸地碎屑 | `mc_combat_abilities.gd::ground_impact(parent,point,radius,options)` | 白圈/碎屑可分别关闭；角色负责伤害 |
| MC 像素圈/蓄力盘 | `pixel_arc.gd::draw_ring/draw_disk`；持续预警 `mc_combat_abilities.gd::charge_circle` | MC 范围圈不再另写平滑 `draw_arc` |
| 无伤害扩散像素环 | `mc_combat_abilities.gd::expanding_ring(parent,point,radius,options)` | 支持 `direction/depth_ratio` 伪 3D；真实触发时 RPC 播一次 |
| 爆炸 | `mc_combat_abilities.gd::explosion(context,point,radius,options)` | 只管表现，伤害归技能 |
| 飞离地图的贴图碎裂 | `item_fragments.gd::spawn/spawn_visual/spawn_texture/spawn_obstacle` | 通用效果，恶魂/凋零破障原调用保持 |
| 落地方块小粒子 | `block_fragments.gd::spawn_obstacle/spawn_texture` | 抛物线落地停留后淡出，可传 `seed/effect_parent` |
| 障碍破坏与裂纹 | `ghast_obstacle_damage.gd::ensure` / `mc_combat_abilities.gd::obstacle_blast`；`mc_obstacle_properties.gd` | 0–100 进度，裂纹阈值 34/67；地图安全边界不可破坏 |
| 烟雾拖尾 | `mc_visual_effects.gd::sample_smoke_trail` + `smoke_particle` | 按距离取样，有全局粒子上限 |
| 灵魂粒子/像素拼身 | `scripts/effects/我的世界/灵魂粒子.gd`、`像素拼身粒子.gd`、`character_copy_request.gd::emit_stream/emit_ring` | |
| 状态目录 | `mc_status_effects.gd` | 39 种原版状态；同目标同状态只有一个有效等级，跨来源回退；叠加用 `apply_stacking_effect` |
| 其他 | `hit_burst_effect.gd` 打击线、`stun_visual.gd` 晕眩、`hit_audio_gain.gd` | |

## 6. 音频公共规则

- 空间音效统一走 `mc_native_audio.gd::queue_stream(context,stream,point,options)`：整体延后创建/挂载/播放，弱引用校验原场景（防切场串音），死亡和已结算伤害的尾音可以在 source 删除后播完。**全局 24 声部预算**，伤害/死亡优先，走 `GameplayRecord` 总线（录制只录这条总线，不录 UI）。支持 `audio_parent`、`groups`、取消票据和 `channel_busy(ticket)`。凋零/信标用 `wither/audio.gd`，规则相同。
- 节点 `_ready`/`_exit_tree` 期间不得直接 `add_child` 后立即 `play`。
- 随机变体由权威端选择并可靠同步，不消费战斗 RNG，重复序号不重播。
- **MC 生物型角色**必须接入原版/模组的四类声音：**脚步、呼吸/待机（ambient/idle 也算）、受伤、死亡**。确实不存在的记录检索结果，不伪造。死亡时同时保留项目默认死亡音效，一次死亡只触发一次。受伤按概率、只对实际有效受伤触发。
- 同类周期声音（呼吸/待机等）两次开始的间隔**不得短于上一次实际所播音频的时长**（计入变体和音高）。脚步除外，见下条。
- **脚步按当前实际移速计步**，所有角色自身脚步和苔藓/蛛网等地形脚步统一用 `scripts/effects/我的世界/footstep_cadence.gd`：
  - 按走过的距离计步，每走完一个步幅响一步。步幅 = 基础速度 × 基础间隔，等价于 实际间隔 = 基础间隔 × 基础速度 ÷ 当前移速：越快越密，越慢越稀，停下不响。
  - 基础速度 = `FOOTSTEP.base_speed(角色)`：角色原本的速度，不含临时加/减速，也不含 Boss 倍率（`_apply_boss_training_scaling` 放大前把原速度记在 `training_boss_base_speed` 元数据里）。所以 Boss 速度 ×10，脚步也密 10 倍。
  - 基础间隔 = 该角色按原速行走时原有的节奏：一般是一声脚步时长 + 原停顿的平均值；凋零骷髅（`mc_creature_voice.gd`）和皓宸是 max(0.3 秒, 一声脚步时长)；行商羊驼每 18px 一步。
  - 下一步不等上一声播完，高速时允许重叠；最短间隔 0.07 秒，防止连成噪音；停下超过 0.25 秒后，再起步立刻先响一步。
  - 只算真实行走：眩晕、瞬移/击飞这类超大位移、静止、死亡、暂停都不响。
  - 走 `new5/audio.gd::play` 的脚步要传 `unthrottled`，否则 75ms 限流会吞掉高速脚步。因为可以重叠，停步/死亡时要停掉本角色所有还在响的脚步。
  - 角色的通用碰撞声节点 `Collide_Audio_Node`（名字叫"脚步"）是撞击声，不是走路声，不按移速改（用户决定）。
- 用户指定的例外：硫方怪不播呼吸/待机；雪傀儡每实际射出一颗雪球就播一次发射声，允许重叠。
- **战斗音乐**：设置“音乐”（`Battle_Music`，本机偏好、不随房间同步，默认“无”）唯一实现 `global/battle_music.gd`（Game 子节点 `BattleMusic`）；“音乐音量”滑块（`Battle_Music_Volume`，0–100%，默认 100%）为本机偏好，只调音乐播放器，0% 静音但不停止时间线，调节不重播曲目；新增曲目只在其 `TRACKS`/`OPTIONS` 登记并补 `BATTLE_MUSIC_<KEY>` 译名。开播条件与 World 开场问候同一套（结构性开局 + `is_combat_runtime_active`），时间静止/暂停只推迟不重开；`Game.battle_session_ended`（重置/重打/轮放系列重开）、战场被清空、离开 World 时停止并回到开头。播放器走 `GameplayRecord`、可暂停，由 Audios 统一随时间流速变速。

## 7. C 键直接控制（全角色强制）

- 战场按 `C` 选中鼠标指向的角色，再按 `C` 退出。覆盖所有可选角色和能独立行动的召唤物/子实体，纯弹道和静态障碍不算。`WASD` 移动，鼠标瞄准，两者互不覆盖。
- 实际已有的主动动作按顺序绑定到**左键、右键、中键**，第 4 个起依次绑 `1`～`9`、`0`。不足三个时空着，不重复绑定、不捏造；超过三个不得丢弃。保留原有冷却、蓄力/松键、眩晕、资源和权限限制。
- 手控期间停止该实体 AI 的自动出招，被动、受击、碰撞照常。权威端校验选中目标和动作索引，处理按下/松开与断线清理，在输入框里不误发指令。
- 长按：首击即时，首次重复等待 400 ms，之后走原冷却逻辑。按下沿动作（如钓鱼竿抛/收线）同一次长按不重复切换。
- 新增或修改角色/召唤物时同步维护手控动作顺序与 `tests/manual_control_inventory.csv`。

## 8. 全项目统一分类（强制）

- 适用于所有分区的角色、招式、召唤物、投射物、障碍/地形、状态和特效。新增或修改前按"实体 → 招式/阶段 → 伤害分量"登记。
- 分类是多轴的，不互斥：① 实体身份（`entity_kind`：角色/自主子实体/投射物/障碍/地形/危险区/状态/效果/纯表现/系统/组件）；② 攻击方式（`attack_modes`）；③ 载体（`carriers`：身体接触/武器扫掠/弹体/射线/范围/状态跳伤）；④ 每次伤害的 `damage_kind`；⑤ 附加状态与控制。不得凭目录、Ball_Type、名字或颜色判定类型。未知填"待核验"，不能静默默认普通。
- 注册表 `classes/combat_classification_catalog.gd`，查询 `classes/combat_classification.gd::profile_of(node)` / `is_projectile(node)`（`ball.get_combat_classification()` 是便捷入口）。阶段差异用同一条目的 `stage_field`/`stages`（例：企鹅石头飞行是投射物、落地是障碍；骷髅箭飞行/插墙/嵌入分别是投射物/地形/状态）。注册表里的 `damage_kinds` 只是能力摘要，不能代替每次伤害的声明，`ordinary_or_contextual` 不是合法事件类型。
- **新增脚本/场景必须补登记并通过** `python tests/verify_combat_classification_registry.py`。禁止改测试前缀来绕过清点。
- 修同类问题时先查公共入口和所有调用方，验证同语义的同类对象，不只修一个角色。纯视觉的环、粒子、爆炸不得暗带另一套伤害。

## 9. 状态正负与净化协议

- 公共净化 `ball.cleanse_negative_effects()`：只能由存活角色的权威端发起。只清除**负面**持续效果及其所有来源；正面效果、其他角色、装备附魔、乘船、表面加速、自主运动都保留。净化不是治疗，也不是免疫窗口；待执行的斩杀要取消。**禁止给任何净化者维护效果名白名单或脚本名特判。**
- 节点型状态在注册表的身份/阶段里声明 `entity_kind:"status"`、`status_polarity`（`negative/positive/neutral/dynamic`）和 `status_cleanup`（`detach` 或无参清理方法名）。dynamic 状态实现 `get_status_effect_polarity() -> int`（负数有害、0 中性、正数有益）。药水符号来自 `mc_status_effects.SPECS.sign`。
- 可实现 `cleanse_status_effect()`：停止自己持有的 DOT、Buff、物理/碰撞租约、信号、Tween 和视觉，只释放自己的所有权，不清空受击者的全部控制锁。必须幂等。
- 状态放在受影响角色子树里；外部持有的节点用 `victim.register_status_effect(effect)` 弱引用注册。外部数据型控制者监听 `victim.negative_effects_cleansed` 释放自己的记录，结束时断开（蜂蜜抓取是范例）。
- 数值 Buff：`Buff.effect_polarity` 为 -1 有害、+1 有益，0 按 `BENEFIT_DIRECTION` 公共语义。新增 `Buff_types` 必须补语义或符号，登记检查会拒绝缺语义的枚举。负面条目直接移除，不走到期伤害（寄生不能因净化爆炸）。
- 同步：可靠 RPC 走稳定的角色节点，按递增版本幂等，旧包不清除之后新施加的效果。

## 10. 投射物交互协议

- 唯一入口 `classes/projectile_interactions.gd`：类别/阶段（`is_projectile/live/supports`）、候选 `candidates(tree)`、运动 `velocity_of/set_velocity/direction_of/speed_of`、归属 `source_of/owner_of/team_of/hostile/bind_owner`、载荷 `damage_of/damage_kind_of`、`capture_descriptor/reflect/retire/defense`。禁止角色私建弹体名单或猜字段。
- 特殊弹体按需实现协议方法：`get_projectile_velocity`、`set_projectile_velocity`、`get_projectile_source`、`get_projectile_team`、`bind_projectile_owner`、`get_projectile_damage`、`get_projectile_damage_kind`、`get_projectile_radius`、`projectile_supports(capability)`、`relaunch_projectile(point,target)`。元数据 `projectile_capabilities` 可关闭 capture/reflect/redirect，`projectile_damage_kind` 声明载荷类型。没有可写运动接口的对象不自动获得反射/改向能力。
- `scripts/projectile_interaction_driver.gd` 先于普通物理扫掠处理捕获/反射/格挡。原生精确接触要调用 `defense` 并遵从 dodge/reflect/block 结果，**反射或格挡后不得继续原爆炸或销毁**。载荷转移保留 damage_kind，火焰不能因接管或返还变成普通伤害。

## 11. 多实体角色存续与结算（强制）

- **本体死亡或退出不等于整位选手淘汰。** 结束铃声和轮换换人统一用 World 的存续集合判断：原 `battle_setup_id` 下的存活本体、成员、召唤/分裂后代、有效死亡接棒，以及已确认的待生成请求。不得在角色私有代码或 `tree_exiting` 里直接清轮换槽或响铃。Team 不是角色槽，同队不同 setup 不互相续命。
- 有主后代：`add_child` 前设置真实 `Master`/`Master_name`，公共注册自动冻结身份。无主的独立身体入树前调用 `world.bind_battle_lifecycle(child, source)`，不要为结算改 AI 或伤害归属。
- 跨越本体删除的已确认延迟生成：`var t = world.begin_battle_spawn(source, request_node)`；入树前 `if not world.apply_battle_spawn_identity(child, t): child.free(); return`；入树后 `world.finish_battle_spawn(t)`。失败、上限、取消也要释放票据。
- 投射物、危险区、障碍、死亡特效、未触发地形不代表存续，不能阻塞结算。0HP 要先让真实死亡/复活回调完成；普通 Creature 不能因还在 Move 状态就无限续命。
- `_count_primary_battle_characters()` 与 `_has_active_battle_participant()` 语义不同，不要混用。

## 12. 译名与盔甲架介绍（强制）

- 每个新角色都要有中文显示名和英文译名，写入 `translations.csv` 并同步生成 `global/translation_catalog.gd`，英文模式不得回退中文。有官方译名必须用官方名（含原版语言资源）；查不到就标待核验。
- 盔甲架介绍要简洁而完整地概括当前实际战斗特性：攻击与技能、触发条件、成长/阶段、状态与控制、防御/免疫、召唤/分裂/复活、关键限制。不写外观、音效、按键教程、历史改版。中英文同义，以当前代码为准。MC 分区用 `MC_ARMOR_INTRO_*` 翻译键，整句翻译，不逐词拼接。
- 介绍开关 `Show_Armor_Stand_Intro`（设置 → 参数，默认开，本机偏好不同步）。显示介绍时不显示 VS，字号 32，描边 4，顶部 48，左右 24。

## 13. 战斗模式、HUD 与判胜

- 判胜只由 World 负责，1v1 顶部 HUD 唯一实现是 `scripts/ui/duel_top_hud.gd`，录制用它的 `make_mirror` 只读镜像，不得复制第二套。
- 1v1 HUD：场上正好剩两名分属两方的主角色时显示（召唤物不算），双方原版 tooltip 框、头像、同色名字、血条，中间是本局游戏时间 + VS。显示期间普通 VS 标题只用 `self_modulate.a=0` 隐藏，右上角世界时间下移。结算时只有之前实际显示过的面板才上移退场，不得补出面板。
- 普通 VS 标题在独立屏幕画布上，镜头移动时零位移。单队/中立白字，多队按蓝、红、后续稳定随机色，加粗黑描边。
- **计时模式**：头顶数字是本人本局受到的全部实际生命伤害（回血不抵扣，召唤物自身掉血不计）；唯一入口是 `ball.gd` health setter 调 `World.on_timed_health_loss`，只在权威端累加。按队伍计算（有 Team 同队，无 Team 各自成队，`World.timed_team_map`）：队伍总受伤最少的队伍整队获胜，最低并列就加赛，首次打破并列立即结算；已删除或全员彻底阵亡的队伍不能凭挨打少获胜。头顶和面板数字按所在队伍总受伤排名由白到红渐变（同分同色）。顶部对战面板按队伍组对，正好 2 个队伍时显示，只显示数字；多人队伍显示羊毛与“X色队伍”，数值为队伍总受伤。开打后（含加赛）主战人物不会因扣血死亡：致命写入停在 1 HP，被吸收的量记入 `ball.absorbed_health_loss`（见伤害结算的吸收规则），受击反馈、角色受伤钩子和计分都按完整伤害照常进行；出界强制死亡和时间到判负淘汰照常。头顶数字字形高度与普通血量数字一致（高分辨率字号再缩放，保证清晰），底边锚在贴图 alpha 可见像素顶部上方一小段，不能锚贴图矩形顶部（MC 贴图透明留白大，会离头很远）。世界时间只在左右对战面板出现时下移，只剩计时面板时不动。计时不暂停。
- **随机人物排除**：队伍页被排除的人物用持久红色底和 ASCII `X` 标记，不能只靠主题的按下位移；再次点击恢复，切回自定义移除排除样式，保存及切语言不改变排除身份。
- **放置预览**：`Game._process` 必须在 `world.process_always()` 之前采样鼠标世界坐标，与输入事件（真实落点）使用同一画布变换；process_always 会立即改写 Camera2D 缩放，录像构图镜头随后在同帧覆盖回显示镜头，夹在中间采样会让预览偏离落点且视野越大偏差越大。
- **轮换**：选轮换即出现固定的蓝队/红队，队下手动选轮；"同队同轮多人物"开启时不自动跳轮。红蓝数量倍数 1–100（不改属性）。车轮战优先于挑战。**车轮战不转场**：败方直接换下，下一位从最近的墙外连续走入边界，赢家实例/生命/状态保留。其余轮换在成就停留和关门期间继续上一局，全覆盖后才清理/加载。主机统一生成，客机只请求。
- 1v1 胜者头像标 `won`（`Images/UI/rotation_frames/check.png`），阵亡标 `dead`（叉号）。同步阵亡或血量归零仍在死亡演出中的不得获得对勾。
- 非轮换玩法里多人获胜方显示原 VS 队色队名和同色原版羊毛；按原参战成员计数，召唤物不凑人数。
- 自由模式：战后添加主角色要解除旧胜利提示，开启新的参战身份范围；reset 清理判胜资格、名册、对阵、提示、镜头和旧铃声。
- 出界：不显示红色倒计时，内部 3 秒淘汰和回图取消保留。
- **墙边回推**：落点按实际 `CollisionShape2D` 的完整 global_transform 包围矩形计算（含偏移、旋转、缩放、余量），不能只用根坐标±半宽高。普通回推和车轮入场共用唯一运动 Tween，保存/暂停并恢复人物根和子状态机的 physics 处理，随游戏暂停。只有权威端创建，客机沿位置同步。

## 14. 录制

- 左键实时录制正在进行的对战；右键从点击瞬间的完整状态固定 60fps 离线计算（不重打、不 reset），需要配套离线引擎。输出原生 1080×1920/60fps 纯对战画面和 `GameplayRecord` 音轨，排除工具栏、鼠标、暂停 UI 和恢复倒计时。每局同时输出中文/英文两份，共享一次计算和一条音频时间线。
- 录制结束以世界正式终局为准；轮换/车轮队列统一读 `World.is_queue_battle_finished()`，小局铃声、换人/关门等待、挑战中红队打完后的重置均不是整轮结束，整轮结束后再按设置续录 N 秒游戏时间（默认 5，0–600），不能用固定时长截断。盔甲架录像也要在真实终局后才停。
- 文件名：中文 `3个钻石剑 vs 2个木剑.mp4`，盔甲架 `角色名.mp4`；英文 `Character * 3 vs ...`。不加 `Mc小球` 前缀。冒号和星号用全角 `：`/`＊`；同队同名合并计数，不跨阵营；重名和中间文件编号避让，不改已有录像。
- 录制结果弹窗按实际窗口缩放；长错误可滚动，路径可选中复制，暂停时仍可操作。
- LIVE 实时录制：D3D12 首帧绘制/读回要在正式计时前准备好；双语言 NVENC 用 `-filter_threads 2` 限制滤镜线程；前台录制期间临时把帧率上限限制到 60，结束恢复。速度验收要对比真实物理推进和绘制帧率，不能只看标称 FPS。轮换门转场/加载（`World.is_rotation_scene_transition_active()`）只重置速度采样窗口，帧和音轨照录。LIVE 遇到减速、渲染阻塞、读回异常或编码积压不得主动中断：有界缓存内同步重复双语最近画面以保留时长，音频溢出的缺失区间补静音；问题累计到结束结果中说明，不弹窗打断，也不冒称画面/声音无损。真正无法写入或编码器故障仍须明确报告未完成/部分文件；SIM 固定 60fps 精确输出不降级。
- 使用屏幕纹理/BackBufferCopy 的效果必须在真实 GPU 录制画面里检查。
- **离线录制引擎**：Godot 4.7.2 源码补丁版（`tools/offline_engine/engine.patch`、`build.ps1`、`build_manifest.json`），新增 `Engine.set_recording_fixed_fps`、`AudioServer.set_offline_audio/render_offline_audio`、离线虚拟 `Time.get_ticks_*` 和 `Time.get_wall_ticks_*`。二进制在项目外 `../polo-balls-tools/offline-engine/runtime/Godot.4.7.2.offline.exe`，不入 Git。启动方式：编辑器工具栏「▶ 运行右键录制版」（`addons/offline_record_launcher/`），或根目录 `启动离线录制版.cmd` / `启动离线版编辑器.cmd`。Steam 原版 F5 不支持右键录制，找不到引擎时明确提示，绝不退回重打。导出时基础倍速规范为 1x，结束恢复并暂停在结果状态。

## 15. 地图、渲染层级与环境

- 背景七项：蓝色、草地、沙地、石砖、下界、末地、山巅（`summit`）。已删除的 `courtyard3d` 旧设置回退 `blue`。
- 地图/3D 背景统一真实受光，不用补偿性自发光。Z 层级：山体 -8、云 -7、地板 -6、石砖 -5、冰/轨道/血迹/3D 墙与地影 -4、药水/附魔/状态信息框 -3（跟随屏幕的世界画布，不用高层 CanvasLayer）、人物/投射物在上。不得靠抬高技能层级绕过不透明地板，也不得恢复墙 90 层或让信息框盖住人物。
- 五种方块主题的边界是原版纹理真实 3D 低墙，高 0.4 格，相邻无缝，12:00 投影约 0.6 格；蓝色边框保持平面。墙与地影合成用 `map_wall_composite.gdshader`，保留未取整的逆相机变换，不关全局 pixel snap。
- 昼夜：默认 12:00，1 游戏秒 = 1 分钟，太阳顺时针，16–20 点渐暗、05–08 点渐亮，菜单和时钟不压暗。时钟固定在右上角，上/右留 24 逻辑像素。
- 原版方块云（设置 → 参数，本机开关，默认开）：原始 `clouds.png`，32×32 平铺，不倾斜、不透视，实心白面，下沿 32/3 像素、明暗 0.70，视差 1.25（比背景移动更多）。
- 山巅：浮空竞技场冷灰石材，群山共用 `shandian_natural.glb`，三个 3D 通道共用同一 World3D、太阳和投影。对战聚焦只做轻度 RGB 调整，不改取景和层级。
- 设置下拉框不按最长选项撑宽父容器。
- 训练设置里"事件"注册表为空，环境默认"无"。**积雪**：雪傀儡雪径和环境地面/墙雪统一用真实一方块网格和原版雪纹理；默认 8 个融化秒后原占地 0.30 秒渐隐，雪环境只让融化计时减半。关闭雪天时停止新增，空中雪花 0.9 战斗秒渐出（开启同样渐入）。淡出开始即无伤害/威胁，墙雪纯装饰。同步相对剩余时间，晚加入不续寿；只有换图、重置、重打才清理。
- 深色橡木双门转场唯一实现 `scripts/ui/dark_oak_transition.gd::ensure/play`（真 3D 门板、边转边移入，关门 0.275 s、开门 0.30 s，全遮挡停留 0.20 s），不得复制。

## 16. 角色专属约束（用户明确决定，代码之外的要求）

- **蜘蛛**：只要真实碰到障碍就织网，任何控制都不阻止（资格唯一在 `蜘蛛.gd::can_weave_silk()`）。丝网伤害、减速、扑击仍受禁攻限制，眩晕不能扑击。碰墙时丝线沿自身方向从腹部延伸，延伸到真实墙体的命中点作为端点（方向不朝墙或够不到墙体形状才退回精确碰撞接触点）；丝端沿丝方向伸进墙内 `WALL_SINK`（薄墙退回墙面），丝与蛛网画在绝对 z=-5（地面贴图之上、墙/墙影/障碍物之下），让墙遮住丝端；平面主题的地图边墙改为停在黑色边线内侧。像素描边用 floor 取整，不用 round。
- **女巫**：每次生效（喝药、瓶子命中、药水区域每秒生效）让对应持续效果等级 +1（最高 255），清除/过期后从一级重来。只有女巫三个入口用 `apply_stacking_effect`。瓶身伤害按当前攻击/防御结算。
- **羊**：吃草结束或被扣血打断后冷却 8 游戏秒；仍要求生命低于 75% 且 3 秒未受伤。
- **苔藓**：16×16 格按角色真实身体形状判定接触；每格独立冷却（目标 ID + 铺设 serial），同来源减速取最强档不相乘。
- **皓宸**：复制品及其后代永不伤害或锁定皓宸一方，规则唯一在 `haochen/copy_friendly_guard.gd`：伤害入口走 `blocks()`，任何自写的敌人判断/选敌函数（`_is_enemy`、`_is_valid_enemy`、`mc_enemy` 等）开头必须先调 `skips_target(发起者,候选)`，新角色同样。复制品体型减半（`CharacterAutoFit.visual_size_multiplier`，不手写 `Image.scale`）；忽略父缩放的自身 UI/手持部件（top_level、固定 global_scale）乘 `haochen/copy_body_scale.gd` 的系数，投射物/召唤物/技能范围不乘。复制数值取初始形态：数值随形态变化的角色实现 `character_copy_template_stats(stats)`。特效只用原版灵魂粒子，语音用用户提供的录音。被动角色，没有手控键。
- **流浪商人**：两只缰绳羊驼不复活、不计胜负，商人死亡时随之退场；只在有负面效果时喝牛奶（与铜剑用同一净化）。
- **铜剑**：只在锈满后的**自然落雷实际命中**时净化自身负面状态，攻击召雷不净化。
- **凋灵骷髅**：石剑两连砍，每刀实际扣血后施加凋零（等级 +1）。**凋零等级变化不得重置公共 1 秒扣血时钟**（`wither/status.gd`）。360 度指任意方向瞄准，不是周身 AOE。移动用公共正常移动，索敌只决定刀的朝向，不改移动方向；攻击期间减速到 30%。握把绑定真实手锚，收刀沿上挑方向转满一圈，纯视觉。
- **凋灵**：玫瑰技能已删除；手控左键头弹、右键冲刺。冲刺速度为原曲线的 65%，身后有原版烟雾。开场不搭方块，直接显示新版模型旋转 3 秒后觉醒；选角预览用当前模型烘焙图。信标的随机主效果在光柱**正式发射瞬间**抽取，预警期间不给。
- **石矛**：四个分身三种架势（随行刺阵/切线旋转阵/四向伸缩刺阵）5 秒随机切换；只有真实矛尖扫掠造成伤害。实际移动积累移速（暂停/静止/传送不增长）。只有旋转形态的矛头接入公共格挡/消弹。
- **雪傀儡**：取消南瓜落地、堆雪和召唤小雪人；半血只把头上的南瓜碎成短暂碎片。每轮有效攻击 10% 概率 20 连射，首次半血后下一轮必连射。移动用原版前斜视角，只有发射时 16 方向瞄准。
- **硫方怪**：保留最近两种方块特性（双槽 FIFO，TNT 爆炸消耗该槽）。纯蜂蜜零独立伤害；抓取最多 1 秒，可反向挣脱，超时后须离开再进入才能重抓；持有蜂蜜+铁/冰时被抓者撞墙按铁/冰普通伤害结算。持有 ICE 时冰径加速无上限（其他角色仍是 1.5 倍上限）。铁特性真正离开双槽时方向随机向上偏 30°–60°。已删除铁的落地/撞地声。
- **鞘翅三种与重锤连砸**：鞘翅三种共用带速度前瞻的地图外软回航（不传送、不钳坐标）。带长矛的两种有直线穿刺；组合型先穿过、命中继续加速，再接重锤连砸。已起跳的连砸不因回航清零。普通重锤和两种鞘翅重锤腾空时，只有眩晕、冰冻等强控暂停跳跃、旋转与落锤结算；控制结束或净化后从原进度继续，保留连砸层数、伤害倍率与飞行动量，不补跑受控时间。普通击退、减速不触发暂停；强控叠加须等最后一个生效控制解除。判定复用 `ball.is_hard_controlled()`，排除通用击退/恢复阶段的软锁，不能直接把 `dizziness` 都算成眩晕；控制器自身计时照常运行。
- **铁匠村民**：挥舞声以出剑时 `attack_damage(1.0) > 100` 选横扫，命中音仍按 50 阈值。击杀后转剑 3 圈纯视觉。挥剑收势不得跨 ±PI 回插多转一圈。
- **烈焰人**：本体视觉和碰撞 ×0.8，烈焰棒尺寸、环绕和范围不缩。
- **史莱姆**：落地和死亡冲击的绿圈用 `pixel_arc.draw_ring`；死亡时权威端对附近敌人结算一次并击退。
- **兔子**：幼兔出生时在父类生命初始化前设置幼兔上限，避免误触发受击反馈。
- **天堂陨落长弓**：普通箭命中不击退；每次出箭在出生点播一个面向发射方向的伪 3D 扩散环（`expanding_ring`，depth_ratio 0.35），同步出生朝向。箭只穿一次障碍物；碰到地图安全墙时沿直线在剩余射程内找回到地面的点：找得到就是地图内部空洞/隔墙，整段算这一次穿透，回到地面后照常飞行、追踪和命中；找不到才是外墙，出墙后飞离屏幕消失。
- **山羊角**：召来的山羊是瞬时技能实体（`goat_horn/goat_charger.gd`）：无敌、不可选中、无生命、不计存续，全程穿过墙体与障碍；被撞的敌人仍正常撞墙反弹。每 15 秒吹一次号（开战约 4 秒首吹），每次召 14–16 只，号声每次随机取原版 8 种之一。每只山羊出现时锁定一个随机敌人当时的位置，从屏幕外沿直线冲过去（不追踪），途中冲撞直接套用羊的冲撞曲线（`impact_profile`，按山羊实际速度 ÷ 羊冲锋速度 520 换算，击退与伤害和同速的羊一致），持续顶住周期推撞并造成伤害；撞完或越过锁定点后加速冲出屏幕。贴图只朝左或朝右，不随斜向旋转，全程保持低头冲撞姿势。号声后山羊一只一只陆续出现（相邻间隔约 0.8 秒），吹奏结束后仍按时间表继续出现。脚步声按实际移动距离计步；奔跑时身后持续生成取自地面贴图的原版方块碎屑（亮度 ×0.6），在墙/障碍上或地图外不生成。山羊显示与判定尺寸按山羊角本体的根缩放换算，与羊同大；山羊画在地图外遮罩之上（绝对 z=91），屏幕外进出全程可见。
- **卫道士**：除冲刺阶段外沿用公共正常移动，蓄力、挥斧和收势不追敌、不自行减速或停步；索敌只决定攻击朝向。原版投影的持斧臂位于躯干后，斧柄锚定掌心并由手遮挡，左右朝向镜像整个手臂和斧头组合，不能只移动肩点。待机和蓄力时斧柄保持竖直向上，不随前臂倾斜；整个0%–100%蓄力过程持续抬高手和斧头，不提前到顶停住。松手从当时握姿连续转入挥砍，不跳到满蓄力姿势。左键按住高抬斧蓄力、松开挥斧，满蓄力自动挥斧，AI按距离择机释放；伤害随实际蓄力增加。达到50%穿透格挡、招架和弹反，达到75%再无视护甲及伤害减免；闪避、无敌和不可命中状态仍有效。右键加速冲向敌人，途中同步蓄力，近敌后按实际比例挥斧，不赠送满蓄力。强控/禁攻/控制权丢失取消未完成动作；暂停不推进时钟。武器命中与威胁显示共用真实斧刃连续扫掠，每次挥斧对同一目标只结算一次。穿防使用公共分类伤害上下文 `bypass_guard` / `bypass_damage_reduction`，防御者通过 `incoming_damage_bypasses_guard()` 判断，实际扣血回调用 `current_health_damage_bypasses_guard()` 获取本次扣血作用域；不直接扣血，不临时改写目标防御属性，后续或嵌套伤害不得继承穿防。
- **唤魔者**：尖牙出土复用重锤外圈小碎屑，闭合时每口 4 颗原版 CRIT 星芒（`critical_burst`）；图腾期间持续金绿粒子。
- **大规模软分离**：只对双方都有 `mc_bat_cohort` 元数据的角色比较批次，不得用 `get_meta(..., null)` 逐对报错。
- **丁某人睡觉**（默认分类，英文名 `me`）：闭眼每 4 秒 4 个轻追踪 Z，60 秒倒计时后睁眼发一次像素波（按每个目标当时自己的 HP，走公共 raw-health 空间入口）。Z 和波的形变以可见猫图底部中央为锚点，只改 Graphics。
- **咒术回战**（动漫分区：五条悟/宿傩/魔虚罗/嵌合暗兽，脚本在 `scripts/characters/动漫/咒术回战/`）：外观统一用网上的 Minecraft 皮肤脸；**体型与普通角色一致**（AutoFit 0.5，和皓宸同尺寸）；数值接近同分区普通角色；语音全部日语原声，素材来自网络并在 `SOURCE.json` 记录；宿傩无真身；魔虚罗是可 C 键操控的独立角色，也能被宿傩召唤。无量空处是谁都出不去的巨大圆形结界，伏魔御厨子覆盖全图，宿傩 1 血锁血后放世界斩。**持续性特效必须画在人物下层（`_under` 层 z=-1），不得遮挡人物**。检查：`python tools/run_jjk_checks.py`。

## 17. MCP 接入

- Bridge 每次新建会话时读取本文件附到 `initialize.result.instructions` 和 `read_files` 工具描述中（单文件上限 64 KiB）。安装/检查：`python tools/mcp_context/install.py --extension <ShunCode扩展目录>` / `--check`，自检 `node tools/mcp_context/test-context.cjs`。首次安装后需重载 ShunCode 一次；旧会话不会自动刷新。不要在本文件写凭据或秘密。
