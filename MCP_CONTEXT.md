# polo-balls 项目规则与接入说明

项目所有者维护的当前规则。通过 ShunCode MCP 接入时，先读懂本文件再改，不需要用户重复提醒。代码是数值和实现细节的唯一事实来源；本文件只记录从代码里看不出、以后修改时必须遵守的通用约束和公共入口。

## 0. 本文件与说明纪律（最高优先级）

- **本文件只写真正有用的通用规则，并尽量简化。** 一条规则要同时满足：跨角色/跨系统适用、从代码里看不出来、违反了会出错。**不写某个角色自己的规则**（数值、外观、手感、特例、用户对单个角色的决定）——这些写在该角色的代码和测试里。不写更新流水、日期、"最新/替代上一条"、测试项数、验证过程、已被取代的旧规则。规则变了就原地改写对应条目，新内容先并入已有条目。
- 用户说"写注释/在注释里说明逻辑"，指写在本文件对应条目里，不是写进代码。
- 项目内只允许两份说明文件：根目录 `AGENTS.md`（入口）和本文件。禁止新建其他说明性文件（README、设计文档、测试报告、变更日志、会话笔记等），也不保存本文件的旧版本或备份，需要旧版本用 Git。本文件必须小于 64 KiB（Bridge 单文件上限），越短越好。
- 代码注释只写非显然的意图或约束；不写更新记录、日期、"用户要求…"、测试结果。
- 测试结果、复现过程、截图结论只在对话里报告，不落盘。临时文件（日志、截图、json、patch、备份、一次性脚本、测试用户数据）一律写系统临时目录或 `user://`，用完即删，不进项目目录、不提交。例外：第三方素材按许可必须随附的 `LICENSE`/`NOTICE`/`SOURCE.json`。

## 1. 强制复用公共实现（写任何技能/特效/素材前先查本节）

- 新增或修改技能、特效、UI 条、素材前，**先在下表和已有角色里找现成实现**。同一语义（例如"闪电""云""能量条""扩散环""电弧"）必须调用公共实现，差异用参数、回调或子类保留，**不得复制近似算法、自绘替代品或复制一份同样的素材**。
- 新角色动手前，先把它的每个机制/表现逐条对照下表列出"用哪个公共入口"；表里没有的，先确认确实是新机制（必要时问用户），再把它写成公共实现并补一行。
- 技能只在权威端结算，RPC 同步视觉和破坏。纯视觉的环、粒子、爆炸不得暗带另一套伤害。
- 默认移动：没有明确的特殊移动说明就沿用公共正常移动（`ball.move/stand`、碰撞反弹、手控 WASD）；索敌和瞄准只决定攻击朝向，不改移动方向、不擅自追敌或停步。特殊阶段（冲刺、飞行等）结束后恢复公共移动。

| 需求 | 唯一入口 | 要点 |
|---|---|---|
| 雷电 | `mc_combat_abilities.gd::lightning(parent,point,seed,radius,warning,options)` | `tuning` 调表现；`fields.origin_world` 从指定点（如云）劈下，默认从屏幕顶；`fields.pause_with_battle` 随时停冻结；`on_impact` 只在权威端接伤害；落点冲击圈就是伤害半径 |
| 电弧连线 | `trident_arc.gd::paint(canvas,from,to,seed,clock,fade,jitter,segments)` | 电网、放电等两点间抖动电弧 |
| 原版方块云 | `minecraft_clouds.gd`（天空云）；局部云块 `cloud_piece(region,transpose)` + `make_patch(mask,tint)` + `place_patch(patch,center)` | 原版 `clouds.png`、同一着色器（`cloud_tint` 染色、`cloud_alpha` 渐隐）、32 像素格、厚度 1/3 格 |
| 能量/进度条 | `frontier/creeper_style_bar.gd::paint(canvas,rect,ratio,warning,fill,trough,opacity)` / `below_body` | 原版 Boss 条外观（`Images/UI/boss_bar/white_*` 三段式、进度裁切），颜色由调用方传入 |
| MC 像素圈/蓄力盘 | `pixel_arc.gd::draw/draw_ring/draw_disk`；持续预警 `mc_combat_abilities.gd::charge_circle` | 不另写平滑 `draw_arc` |
| 无伤害扩散像素环 | `mc_combat_abilities.gd::expanding_ring(parent,point,radius,options)` | `palette`、`direction/depth_ratio` 伪 3D |
| 扩张圆环连续扫掠 | `classes/expanding_ring_sweep.gd::segments/contacts` | 真实环带几何；调用方负责伤害、权威结算、去重 |
| 武器尖端连续扫掠 | `classes/weapon_tip_sweep.gd::contacts(...)` | 只查几何 |
| 真实墙接触 | `ball.wall_contact_impact(normal_speed,point)`；`SurfaceAcceleration.reflect_momentum` | 伤害由订阅者结算 |
| 击退/眩晕 | `apply_knockback(dir,dist,speed,bounce,stun,{"source":caster})` / `apply_stun(duration,caster)` | 不复制 `knockback_effect.gd`，不裸写 `Repel` |
| 强控判断 | `ball.is_hard_controlled()` | 不把 `dizziness` 一律当眩晕 |
| 可挣脱牵引 | `knockback_effect.gd::set_pull/release_pull` | 每步刷新、不锁输入 |
| 不改属性的减速 | `ball.set_motion_speed_factor(key,source,factor,left)` | 不改 `Speed`，多条取乘积 |
| 真实身体击飞 | `physical_airborne_effect.gd::launch(...)` | |
| 地表方向加速 | `surface_acceleration.gd::touch(target,surface)` | |
| 临时免碰撞 | `classes/body_collision_exclusions.gd::acquire/release` | 不改层/掩码 |
| 穿格挡/穿减伤 | 分类伤害上下文 `bypass_guard` / `bypass_damage_reduction` | 不临时改目标属性 |
| 砸地碎屑 | `mc_combat_abilities.gd::ground_impact` | |
| 爆炸 | `mc_combat_abilities.gd::explosion` | 只管表现 |
| 3D 地面火 / 单格 3D 方块 | `mc_fire_block_3d.gd`；`mc_block_3d.gd::create(model,cell)` | 原版模型，碰撞与视觉同格 |
| 碎裂/碎屑 | `item_fragments.gd`、`block_fragments.gd` | |
| 障碍破坏 | `ghast_obstacle_damage.gd` / `mc_combat_abilities.gd::obstacle_blast` | 地图安全边界不可破坏 |
| 烟雾/灵魂/像素拼身粒子 | `mc_visual_effects.gd`、`灵魂粒子.gd`、`像素拼身粒子.gd` | 有全局上限 |
| 状态 | `mc_status_effects.gd` | 同目标同状态一个有效等级；叠加用 `apply_stacking_effect` |
| 打击线/晕眩/受击音增益 | `hit_burst_effect.gd`、`stun_visual.gd`、`hit_audio_gain.gd` | |
| 门转场 | `scripts/ui/dark_oak_transition.gd::ensure/play` | |

## 2. 协作、验证与 Git

- 先读再改；有版本哈希时用 `expected_versions`。另一段对话在改同一文件时，不覆盖它的改动，只提交自己负责的部分。
- 修改后跑相关测试和必要的真实画面检查，只报告实际做过的验证。Headless：`godot --headless --path . --script res://tests/<脚本>.gd`，退出码 0 为通过；需要 GPU 的去掉 `--headless`。测试改设置前先把 `_settings_storage_path` 指到临时文件。
- 每个独立更新验证后建一个描述清楚的本地提交，只纳入运行必需的文件；禁止不核对就 `git add .`，不混入凭据、缓存、别人的改动。完成时报告更新前/后提交 ID。未经确认不 `reset --hard`、`clean -fd`、强推；用户授权才推送远程。
- 保护发布：`python tools/protected_export.py export`，缺密钥或校验失败必须停止，不退回明文；密钥不得输出或提交。

## 3. 伤害结算

- 所有伤害（身体、近战、投射物、范围、持续、召唤物）按攻击者**当前**属性计算、受击者当前属性承伤，走 ball 公共入口并给出真实 `source`；不裸写 `health -=`（强制扣血用 `MCE.direct_health_loss`）。
- 带类型伤害：`receive_classified_positional_damage` / `receive_classified_spatial_damage`，kind 只能是 `ordinary/fire/cold/poison/wither/bleed/drowning/magic`。火焰走 `receive_fire_*` 并先查 `can_receive_fire_status()`，寒冷同理；混合攻击分量分别结算。
- 附魔（`mc_enchantments.gd`）在公共受伤入口统一结算，新角色必须兼容：直接命中标 `carrier`（projectile/body_contact/area/weapon_sweep/ray_beam），持续伤害 `status_tick`；投射物由 `mc_enchant_projectiles.gd` 处理多重/穿透，不手动重复出弹；蓄力乘 `charge_speed(actor)`；新角色在 `mc_enchant_support.gd::SUPPORT` 登记（`tests/verify_mc_enchant_support.gd`）；随机附魔只从 `pool_for(target)` 抽。附魔光只覆盖 `Graphics` 子树，UI 不发光；新的人物 Shader 要 include `mc_enchant_glint.gdshaderinc`。
- MC 受击音由 `mc_hit_feedback.gd` 统一给出：按结算后实际生命损失，`damage > 50` 暴击、否则普通，一次结算一份；角色特例登记在 `POLICIES`。
- 用 before/after 生命算实际掉血时要计入 `ball.absorbed_health_loss`（或比较 `health_loss_reading()`）。
- 命中筛选用目标真实位置，不用会被换成鼠标的 `combat_target_position`。
- 选敌与友伤：自写的敌人判断必须与 World 的 `_nearest_enemy_candidate_distance_sq` 一致（排除同 Team 与自己的召唤物），开头先调 `haochen/copy_friendly_guard.gd::skips_target`。`Have_Team_Damage` 只管普通命中；角色自写的特殊伤害永不伤同 Team，强制友伤要显式声明。
- 人物 Shader 形变只重映射 UV，保留 `deform_rect` 外扩，不得裁切。

## 4. 威胁显示（新角色强制）

- 每个真实伤害区域都要在「威胁显示」里可见，且位置、形状、大小、方向、时机与实际判定一致，优先复用 `hitbox`、`AI_Hazard`、`get_ai_attack_threats`。白→红为伤害，绿为无伤碰撞，淡蓝为检测范围。

## 5. 素材来源

- 「我的世界」分区的图片、音效、粒子取自原版或对应模组资源，不自绘、不用生成素材冒充原版，可在引擎里组合、裁切、染色。同目录 `SOURCE.json` 记录来源、版本、SHA1 和许可。**已有同一原版文件就直接引用，不再复制一份**（先在项目里按文件名/SHA1 查）。
- 其他分区网上取材同样在 `SOURCE.json` 记录 URL 和许可；原始大素材包不入 Git。

## 6. 音频

- 空间音效走 `mc_native_audio.gd::queue_stream(context,stream,point,options)`（全局声部预算、`GameplayRecord` 总线）。随机变体由权威端选并同步，不消费战斗 RNG。
- MC 生物型角色接入原版的脚步、待机、受伤、死亡四类声音（不存在的不伪造），死亡同时保留项目默认死亡音。同类周期声音间隔不短于上一次实际音频时长。
- 脚步统一用 `footstep_cadence.gd`，按实际移动距离计步（越快越密、停下不响；眩晕、瞬移、暂停不响）；`Collide_Audio_Node` 是撞击声，不按移速改。
- 战斗音乐唯一实现 `global/battle_music.gd`。

## 7. C 键直接控制（全角色强制）

- 战场按 `C` 选中/退出，WASD 移动、鼠标瞄准。已有主动动作按顺序绑左键、右键、中键，之后 `1`～`0`，不捏造、不丢弃，保留原有冷却与限制；手控期间停止 AI 自动出招。新增/修改角色同步维护 `tests/manual_control_inventory.csv`。

## 8. 统一分类（强制）

- 所有角色、招式、召唤物、投射物、障碍、状态、特效在 `classes/combat_classification_catalog.gd` 登记（实体身份、攻击方式、载体、伤害类型、状态与控制），不凭目录或名字判定。新增脚本/场景必须通过 `python tests/verify_combat_classification_registry.py`。修同类问题先查公共入口和所有调用方。

## 9. 状态与净化

- 公共净化 `ball.cleanse_negative_effects()` 只清负面效果，禁止给净化者写效果名白名单。节点型状态在注册表声明 `status_polarity` 和 `status_cleanup`，实现幂等的 `cleanse_status_effect()`；外部持有的状态用 `register_status_effect` 注册。新增 `Buff_types` 必须补正负语义。

## 10. 投射物

- 统一走 `classes/projectile_interactions.gd`（类别、运动、归属、载荷、捕获/反射/格挡），禁止私建弹体名单或猜字段；特殊弹体实现协议方法。反射或格挡后不得继续原爆炸或销毁，载荷转移保留伤害类型。

## 11. 多实体角色存续（强制）

- 本体死亡不等于整位选手淘汰：结束与换人统一用 World 的存续集合判断，角色代码里不直接清轮换槽或响铃。有主后代在 `add_child` 前设置 `Master`；无主独立身体用 `world.bind_battle_lifecycle`；跨本体删除的延迟生成用 `begin_battle_spawn` / `apply_battle_spawn_identity` / `finish_battle_spawn`。投射物、危险区、特效不代表存续。

## 12. 译名与盔甲架介绍（强制）

- 新角色要有中英文名（`translations.csv` → `global/translation_catalog.gd`），有官方译名用官方名。盔甲架介绍（MC 分区 `MC_ARMOR_INTRO_*`）简洁完整地概括实际战斗特性，不写外观、音效、按键、历史；中英同义，整句翻译。

## 13. 模式、HUD 与判胜

- 判胜只由 World 负责。HUD 唯一实现：1v1/对阵面板 `scripts/ui/duel_top_hud.gd`（录制用 `make_mirror`），VS 立体标题 `versus_title_3d.gd`；不得复制第二套。
- 计时模式受伤计数的唯一入口是 `ball.gd` health setter → `World.on_timed_health_loss`，只在权威端累加。
- 鼠标世界坐标必须在 `world.process_always()` 之前采样（放置预览与落点一致）。
- 墙边回推按 `CollisionShape2D` 的完整 global_transform 计算，只在权威端创建。

## 14. 录制

- 录制结束以 World 正式终局为准（轮换用 `World.is_queue_battle_finished()`），再按设置续录。命名唯一在 `battle_record_naming.gd`，封面在 `battle_record_cover.gd`。
- 右键离线录制需要项目外的离线引擎（`tools/offline_engine/`，二进制不入 Git），找不到时明确提示，绝不退回重打。LIVE 录制遇到卡顿不主动中断，问题在结果里如实说明。使用屏幕纹理的效果要在真实 GPU 录制画面里检查。

## 15. 地图、渲染层级与环境

- Z 层级：山体 -8、云 -7、地板 -6、石砖 -5、冰/轨道/血迹/3D 墙与地影 -4、药水/附魔/状态信息框 -3、人物/投射物在上。不得靠抬高技能层级绕过地板，也不得让信息框盖住人物。
- 地图/3D 背景统一真实受光，不用补偿性自发光。动态模糊唯一实现 `scripts/effects/motion_blur.gd`，CanvasLayer 第 1 层专属于它，界面放第 2 层。
- 环境/积雪等同步相对剩余时间，只在换图、重置、重打时清理。

## 16. MCP 接入

- Bridge 每次新建会话把本文件附到 `initialize.result.instructions` 和 `read_files` 工具描述中（单文件上限 64 KiB）。安装/检查：`python tools/mcp_context/install.py --extension <ShunCode扩展目录>` / `--check`，自检 `node tools/mcp_context/test-context.cjs`。旧会话不会自动刷新。不要在本文件写凭据。
