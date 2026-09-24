# 跨角色战斗能力索引（新增角色先读）

所有参数按技能实例设置，**复用同一实现，不复制算法/原版素材**。MC 分区美术、音频、动画取原版游戏/模组已存在资源并保留来源/许可记录；详见 `MCP_CONTEXT.md`。以下入口是源码用法，不保证未提交的其他角色资源已可独立打包。

| 需求 | 唯一公共入口 | 可调参数/角色保留部分 |
| --- | --- | --- |
| 雷电预警与落雷 | `scripts/effects/我的世界/mc_combat_abilities.gd::lightning(parent, point, seed, radius, warning, options)` → `雷电.gd`；三叉戟传 `options.script=trident_lightning.gd` | `tuning` 可调雷电的导出光柱/辉光/环/声音参数，`on_impact` 一次回调；伤害、蓄能、阶段转换由角色决定。施术者自己 RPC 每端调用；只有权威端接伤害回调。铜剑、溺尸、苦力怕、雾中人已接入。 |
| 水平击退/眩晕 | `target.apply_knockback(direction,distance,speed,bounce,stun,{"source":caster,...})` / `target.apply_stun(duration,caster)` | 距离、速度、撞墙/人物、眩晕、碰撞伤害、控制锁、末段刹车等用 options；别直接复制 `knockback_effect.gd` 或裸写 `Repel`。 |
| 铁傀儡式真实身体击飞 | `scripts/effects/physical_airborne_effect.gd::launch(victim,caster,apex,up_speed,stun,side_speed,options)` | 身体+碰撞体一起飞、地图/障碍扫掠、锁控制、二次命中平滑重发；`landed_at(point,apex_height)` 或子类 `_on_landing` 自定落地伤害/声音。施术者 RPC 同一调用至各端；铁傀儡子类仅保留专属落地玩法。 |
| 火焰伤害 | `ball.receive_fire_positional_damage(amount,point,false,caster)` / `receive_fire_spatial_damage(amount,space)`；`can_receive_fire_status()` | `fire_effect_ratio=0` 火免，正值缩放；已有药水火抗也免疫。燃烧状态复用现有状态类，按实际有效伤害播 MC 音效。烈焰弹直击/烈焰火场已接入。普通爆炸不默认算火焰。 |
| 砸地/地板碎屑 | `mc_combat_abilities.gd::ground_impact(parent,point,radius,options)` → `重锤落地冲击.gd` | `show_impact_ring/show_impact_streaks`、方块来源/数量/尺寸/高度/飞行时间/散布、中心高度曲线等导出参数；白圈、碎屑可分别关闭。重锤、铁傀儡、三叉戟、监守者及长弓落箭共用真实地表采样与碎屑运动；角色负责伤害。 |
| 爆炸/道具碎片 | `mc_combat_abilities.gd::explosion(context,point,radius,options)` → `mc_explosion.gd`；`item_fragments.gd::spawn_obstacle()` | 声音、种子、粒子量、场外显示等仅改变表现；伤害和命中判定归权威技能。 |
| 障碍破坏与裂纹 | `ghast_obstacle_damage.gd::ensure(context)` / `mc_combat_abilities.gd::obstacle_blast(context,point,radius)`；各端 `apply_obstacle_updates` | 共用 0–100 进度，默认每爆 +34、裂纹阈值 34/67、100 破坏；素材为 `Images/Status/BlockDamage` 中的原版裂纹。静态障碍/地图碰撞格默认走统一属性；场景根节点可挂 `MCObstacleProperties` 调 `destructible/blast_step/crack_thresholds`，TileSet 单格可加 `mc_obstacle_destructible`/`mc_obstacle_blast_step` 自定义数据。地图安全边界强制保护。恶魂/凋零已用同一管理器。 |
| 其他已有能力 | `mc_status_effects.gd` 状态目录、`mc_native_audio.gd`/`hit_audio_gain.gd` 音频、`mc_visual_effects.gd` 末影粒子/烟雾、`hit_burst_effect.gd` 打击线与 `stun_visual.gd` 晕眩表现 | 先查这些公共入口，再增加角色适配层；不要创建相同素材的第二套。 |

最小调用示例（在施术者已有的本地/RPC 视觉函数内）：

```gdscript
const ABILITIES = preload("res://scripts/effects/我的世界/mc_combat_abilities.gd")
# RPC 在各端各调用一次；权威端才连接真正的伤害结算。
var on_hit:Callable = _strike_area if is_multiplayer_authority() else Callable()
ABILITIES.lightning(self, point, seed_value, 62.0, 0.68, {"on_impact":on_hit, "tuning":{"core_width":7.0}})
# 独立碰撞后，可直接复用统一移动控制器。
target.apply_knockback(point.direction_to(target.global_position), 50.0, 300.0, 0.0, 0.2, {"source":self})
```

验证至少覆盖：单机/双端仅权威端结算一次、暂停和录制一致性、队友/免疫/遮挡、两次命中累计进度与重置、碰撞层不为 1 的静态障碍、地板碎屑实画面。已有入口：`scripts/training/test_ghast_obstacle_damage.gd`、`test_ghast_obstacle_shatter.gd`、`tests/test_iron_golem_physical_flight.gd`、`test_mc_native_fire.gd`、`test_mc16_lightning_style.gd`、`test_heavenfall_arrow_pierce.gd`。

2026-09-24 验证（Steam 官方 Godot 4.7.2，`--headless --path . --script res://<路径>`）：公共能力 smoke 0 失败；恶魂破障 35/35、碎裂 29/29、铁傀儡物理击飞 27/27、火焰 18/18、凋零冲撞 16/16、长弓落箭 63/63、雷电 53/53。`test_stone_obstacle.gd` 前 18 项通过，但在既有 `game.gd` 不存在的 `_find_deletable_ancestor` 处中断，整项不能记为通过。引擎仍报告 `set_rgb_color.gdshader` 大小写/UID 警告和部分旧测试退出时的对象泄漏。尚未进行双客户端联机、实际录制和人工实画面检查。
