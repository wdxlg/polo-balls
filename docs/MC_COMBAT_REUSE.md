# 跨角色战斗能力索引（新增角色先读）

所有参数按技能实例设置，**复用同一实现，不复制算法/原版素材**。MC 分区美术、音频、动画取原版游戏/模组已存在资源并保留来源/许可记录；详见 `MCP_CONTEXT.md`。以下入口是源码用法，不保证未提交的其他角色资源已可独立打包。

| 需求 | 唯一公共入口 | 可调参数/角色保留部分 |
| --- | --- | --- |
| 雷电预警与落雷 | `scripts/effects/我的世界/mc_combat_abilities.gd::lightning(parent, point, seed, radius, warning, options)` → `雷电.gd`；三叉戟传 `options.script=trident_lightning.gd` | `tuning` 可调雷电的导出光柱/辉光/环/声音参数，`on_impact` 一次回调；伤害、蓄能、阶段转换由角色决定。施术者自己 RPC 每端调用；只有权威端接伤害回调。铜剑、溺尸、苦力怕、雾中人已接入。 |
| 水平击退/眩晕 | `target.apply_knockback(direction,distance,speed,bounce,stun,{"source":caster,...})` / `target.apply_stun(duration,caster)` | 距离、速度、撞墙/人物、眩晕、碰撞伤害、控制锁、末段刹车等用 options；别直接复制 `knockback_effect.gd` 或裸写 `Repel`。 |
| 铁傀儡式真实身体击飞 | `scripts/effects/physical_airborne_effect.gd::launch(victim,caster,apex,up_speed,stun,side_speed,options)` | 身体+碰撞体一起飞、地图/障碍扫掠、锁控制、二次命中平滑重发；`landed_at(point,apex_height)` 或子类 `_on_landing` 自定落地伤害/声音。施术者 RPC 同一调用至各端；铁傀儡子类仅保留专属落地玩法。 |
| 冰面/地表方向加速度 | `scripts/effects/surface_acceleration.gd::touch(target,surface)`；surface 提供 `surface_acceleration_at(world_point)` | 单个权威控制器沿目标真实位移积分，参数 `acceleration/max_bonus_ratio/release_deceleration`；重叠地表取上限而不叠加，静止不推动、离开衰减，暂停冻结。通过 `ball.surface_motion_velocity` 接入公共 move/stand 的最终速度，保留物理碰撞，不伪装成 Speed Buff 或抢占击退控制。完全自行移动且绕过公共链的角色须自行接入同一速度字段；不是复制其移动算法。 |
| 临时角色对免碰撞 | `classes/body_collision_exclusions.gd::acquire(a,b,holder)` / `release(a,b,holder)` / `are_excluded(a,b)` | 双向 PhysicsBody 排除，按 holder 保留并发租约；不修改层/掩码或受击 Area，不删除预存例外，任一 body/holder 离树自动释放。`world.gd` 软分离同样查询；不能用清空角色碰撞层代替。硫方怪蜂蜜只排除施术者与被黏目标，目标相对路径由权威端复制。见 `tests/SULFUR_CUBE_CONTACTS_20260926.md`。 |
| 火焰伤害 | `ball.receive_fire_positional_damage(amount,point,false,caster)` / `receive_fire_spatial_damage(amount,space)`；`can_receive_fire_status()` | `fire_effect_ratio=0` 火免，正值缩放；已有药水火抗也免疫。燃烧状态复用现有状态类，按实际有效伤害播 MC 音效。烈焰弹直击/烈焰火场已接入。普通爆炸不默认算火焰。 |
| 砸地/地板碎屑 | `mc_combat_abilities.gd::ground_impact(parent,point,radius,options)` → `重锤落地冲击.gd` | `show_impact_ring/show_impact_streaks`、方块来源/数量/尺寸/高度/飞行时间/散布、中心高度曲线等导出参数；白圈、碎屑可分别关闭。重锤、铁傀儡、三叉戟、监守者及长弓落箭共用真实地表采样与碎屑运动；角色负责伤害。 |
| MC 像素外圈 / 蓄力填充盘 | `pixel_arc.gd::draw_ring(canvas,center,radius,tint,opacity,palette)` / `draw_disk(canvas,center,radius,color)`；持续预警用 `mc_combat_abilities.gd::charge_circle(parent,radius,options)` → `mc_charge_circle.gd` | 重锤与 TNT 共享三层像素环；填充复用同一扫描线缓存。`set_charge(world_point,world_radius,progress)` 由角色真实计时更新，支持颜色、透明度，世界尺度不受父节点缩放影响；角色负责结束隐藏/删除与权威伤害。后续 MC 范围圈优先用此接口，不再另写平滑 `draw_arc/draw_circle` 或复制三层常量。回归见 `tests/SULFUR_CUBE_POLISH_20260926.md`。 |
| 无伤害扩散渐隐像素环 | `mc_combat_abilities.gd::expanding_ring(parent,point,radius,options)` → 原 `重锤落地冲击.gd` → `pixel_arc.draw_ring` | `palette` 三层颜色、`end_scale`、`lifetime`、`z_index`、`name`；世界坐标/尺寸不随父节点缩放移动，半径沿用公共下限8。关闭方块、射线与地表读回，不消费战斗随机种子；暂停冻结，归入 `BattleTransient`，按 lifetime 自清理。施术者只在真实触发时可靠 RPC 每端播一次，不从状态回放重复发圈。天堂陨落长弓已接入，见 `tests/HEAVENFALL_MUZZLE_RING_20260926.md`。 |
| 爆炸 | `mc_combat_abilities.gd::explosion(context,point,radius,options)` → `mc_explosion.gd` | 声音、种子、粒子量、场外显示等仅改变表现；伤害和命中判定归权威技能。 |
| 飞离地图的贴图碎裂（物品死亡等） | `item_fragments.gd::spawn(character,options={})` 供角色；任意可视节点 `spawn_visual(node,options={},tile_info={})`，裸纹理 `spawn_texture(context,texture,point,scale_factor,options)`；旧障碍兼容入口 `spawn_obstacle(node,tile_info={},options={})` | 取源 Sprite/Polygon/TileMap 当前贴图切片，碎片向上飞、旋转并落出地图后删除；`gravity/launch_up_min/launch_up_max/horizontal_speed/spin_speed` 可调。木矛、重锤、钻石剑、铜剑等死亡使用它；**恶魂/凋零破障本来就使用其 `spawn_obstacle` 入口，此次保持原状**。这是通用特效，不限于人物死亡，也不是落地小方块特效。 |
| 方块破坏小粒子（落地） | `block_fragments.gd::spawn_obstacle(block,tile_info={},options={})`，无 Sprite 的方块用 `spawn_texture(context,texture,point,scale_factor,options)` | 取原方块 Sprite/TileMap atlas/Polygon（或传入原版方块纹理），切成至多 `max_pieces` 块；`scatter_radius/arc_height_min/arc_height_max/flight_min/flight_max/ground_hold/fade_time/spin_speed/z_layer` 可调。碎块沿抛物线飞出、**落地停留**再淡出；轨道覆盖、剑工作台与苔藓破块沿用之前已接入的调用。**不更改恶魂/凋零破障原有的离场碎裂与进度、伤害逻辑**。 |
| 障碍破坏与裂纹 | `ghast_obstacle_damage.gd::ensure(context)` / `mc_combat_abilities.gd::obstacle_blast(context,point,radius)`；各端 `apply_obstacle_updates` | 共用 0–100 进度，默认每爆 +34、裂纹阈值 34/67、100 破坏；素材为 `Images/Status/BlockDamage` 中的原版裂纹。静态障碍/地图碰撞格默认走统一属性；场景根节点可挂 `MCObstacleProperties` 调 `destructible/blast_step/crack_thresholds`，TileSet 单格可加 `mc_obstacle_destructible`/`mc_obstacle_blast_step` 自定义数据。地图安全边界强制保护。恶魂/凋零已用同一管理器。 |
| 其他已有能力 | `mc_status_effects.gd` 状态目录、`mc_native_audio.gd`/`hit_audio_gain.gd` 音频、`mc_visual_effects.gd` 末影粒子/烟雾、`hit_burst_effect.gd` 打击线与 `stun_visual.gd` 晕眩表现 | 先查这些公共入口，再增加角色适配层；生物脚步/呼吸/受伤/死亡的强制规范见 `MCP_CONTEXT.md` §6。 |

最小调用示例（在施术者已有的本地/RPC 视觉函数内）：

```gdscript
const ABILITIES = preload("res://scripts/effects/我的世界/mc_combat_abilities.gd")
# RPC 在各端各调用一次；权威端才连接真正的伤害结算。
var on_hit:Callable = _strike_area if is_multiplayer_authority() else Callable()
ABILITIES.lightning(self, point, seed_value, 62.0, 0.68, {"on_impact":on_hit, "tuning":{"core_width":7.0}})
# 独立碰撞后，可直接复用统一移动控制器。
target.apply_knockback(point.direction_to(target.global_position), 50.0, 300.0, 0.0, 0.2, {"source":self})
```

验证至少覆盖：单机/双端仅权威端结算一次、暂停和录制一致性、队友/免疫/遮挡、两次命中累计进度与重置、碰撞层不为 1 的静态障碍、地板碎屑实画面；分别验证通用离场碎裂（含原有恶魂/凋零调用）与可选落地方块碎片，未经要求不迁移既有破障机制。已有入口：`scripts/training/test_ghast_obstacle_damage.gd`、`test_ghast_obstacle_shatter.gd`、`test_mc_round6.gd`、`tests/test_mc_rail_feedback.gd`、`test_mc_moss_feedback.gd`、`test_iron_golem_physical_flight.gd`、`test_mc_native_fire.gd`、`test_mc16_lightning_style.gd`、`test_heavenfall_arrow_pierce.gd`。

2026-09-24 验证（Steam 官方 Godot 4.7.2，`--headless --path . --script res://<路径>`）：公共能力 smoke 0 失败；恶魂破障 35/35、碎裂 29/29、铁傀儡物理击飞 27/27、火焰 18/18、凋零冲撞 16/16、长弓落箭 63/63、雷电 53/53。`test_stone_obstacle.gd` 前 18 项通过，但在既有 `game.gd` 不存在的 `_find_deletable_ancestor` 处中断，整项不能记为通过。引擎仍报告 `set_rgb_color.gdshader` 大小写/UID 警告和部分旧测试退出时的对象泄漏。尚未进行双客户端联机、实际录制和人工实画面检查。

2026-09-25 碎裂拆分及纠正验证（Steam 官方 Godot 4.7.2）：`tests/test_mc_fragment_contract.gd` 18/18（角色死亡及普通 Sprite/Polygon/TileMap/裸纹理均可使用离场碎裂；另验证落地小方块、参数和工作台）；恶魂破障 35/35、保留原离场碎裂的恶魂障碍 29/29、凋零冲撞破障 16/16、轨道 24/24；苔藓破坏 52/52、苔藓表现 77/77 为接入方块落地特效时的回归。`test_mc_round6.gd` 297/299，其余两项失败发生在守卫者锁定及钻石剑伤害倍数，物品死亡检查未报错；`test_mc_wood_revision3.gd` 在锻造台检查前因木剑缺 `brace_left` 中断，不能记作通过，故工作台另在碎裂夹具中验证。未做人工画面/双客户端联机/实际录制验证；项目既有 UID 大小写警告和测试退出时对象泄漏仍在。

2026-09-26 硫方怪接触追补：冰径/裂纹及其 `block_fragments.gd` 落地碎屑使用绝对 Z=-4；随机 3–8 根水晶只由权威端生成根/尖布局，沿用 `sulfur_amethyst_crystal.gd` 原版交叉网格及射出帧姿态。每根附着水晶对每个敌人每轮生长结算一次，不共享冷却；完整物理/GPU/ENet验证及边界见 `tests/SULFUR_CUBE_CONTACTS_20260926.md`。

2026-09-26 硫方怪平衡追补：铁/紫水晶三类单次伤害系数×0.7；铁底部每0.25秒小额持续碾压，调用 `apply_knockback` 续用同一控制器、不锁死输入。新地表控制器区别于定向重力/技能击退：加速度由目标自身实际运动决定，不修改 Speed、Repel 或施术者朝向。参数、真实位移与173项回归见 `tests/SULFUR_CUBE_BALANCE_20260926.md`。

2026-09-26 天堂陨落长弓发射环：真实箭矢出生点触发8→24像素半径、0.38秒扩散渐隐青绿/浅青/银白空心环；复用现有重锤时序与三层像素光栅，不改变箭雨/瞬移到达圈伤害。230项检查含GPU与单进程双ENet端，边界与回退见专题报告。
