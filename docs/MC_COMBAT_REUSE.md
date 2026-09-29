# 跨角色战斗能力索引（新增角色先读）

所有参数按技能实例设置，**复用同一实现，不复制算法/原版素材**。MC 分区美术、音频、动画取原版游戏/模组已存在资源并保留来源/许可记录；详见 `MCP_CONTEXT.md`。以下入口是源码用法，不保证未提交的其他角色资源已可独立打包。

| 需求 | 唯一公共入口 | 可调参数/角色保留部分 |
| --- | --- | --- |
| 武器尖端连续扫掠 | `classes/weapon_tip_sweep.gd::contacts(caster,start,finish,radius,excluded,anchor)` | 从钻石长矛提取真实hurt-shape胶囊/墙遮挡，石矛共用；只查询几何不扣血，敌人接触位置不使用手控鼠标。调用方提供尖端轨迹、旋转细分、当前属性/速度公式、去重和有效阶段，不能用此接口把矛杆/整圈当伤害。石矛持续四分身架势与钻石长矛定点虚影机制不同，不继承其蓄速损失/突击机制；见 `tests/STONE_SPEAR_20260927.md`。 |
| 真实墙接触 / 冰面反弹同步 | `ball.wall_contact_impact(normal_speed,point)`；`SurfaceAcceleration.reflect_momentum(normal)` | 信号来自公共 move/stand 的真实碰撞与连续接触去重，传相对墙的内向法线速度，伤害由订阅能力按当前属性结算。硫方怪纯蜂蜜零伤害；1秒内有效蜂蜜+铁/冰抓取可把被抓者墙撞交给原铁×1.2075/冰×0.625及170速度基准，不新增蜂蜜倍率。正常铁仍仅向下底部命中；正常冰扩展公共 `_process_physical_contact_hits` 即时全向命中。反弹同步现存地表惯性，保存真实撞击前行程供下一轮积分；没有实际移动才给予一次空采样保护。现行蜂蜜规则见 `tests/SULFUR_HONEY_GRAB_20260927.md`，冰转向见上轮碰撞报告；紫晶0.35/0.23625、TNT200/半径40不变。 |
| 地形效果与地图合成 | 原技能视觉 + `地图立体墙.gd` 的山巅地板/建筑独立通道；地表采样继续用 `地表渲染采样.gd` | 地板绝对-6、石砖-5、冰/轨道/血迹-4，建筑保留原-4遮挡，信息框/角色在前。不要复制技能或统一抬高特效；新地板须符合采样 Z≤-5 且不含建筑颜色，跨通道投影共享原网格。真实效果/七背景/暂停/采样与已知边界见 `tests/TERRAIN_VISIBILITY_20260926.md`。 |
| 雷电预警与落雷 | `scripts/effects/我的世界/mc_combat_abilities.gd::lightning(parent, point, seed, radius, warning, options)` → `雷电.gd`；三叉戟传 `options.script=trident_lightning.gd` | `tuning` 可调雷电的导出光柱/辉光/环/声音参数，`on_impact` 一次回调；伤害、蓄能、阶段转换由角色决定。施术者自己 RPC 每端调用；只有权威端接伤害回调。铜剑、溺尸、苦力怕、雾中人已接入。 |
| 水平击退/眩晕 | `target.apply_knockback(direction,distance,speed,bounce,stun,{"source":caster,...})` / `target.apply_stun(duration,caster)` | 距离、速度、撞墙/人物、眩晕、碰撞伤害、控制锁、末段刹车等用 options；别直接复制 `knockback_effect.gd` 或裸写 `Repel`。 |
| 持续、可挣脱的非独占牵引 | 同一 `scripts/effects/knockback_effect.gd` 的 `set_pull(target,caster,world_velocity)` / `release_pull(target,caster)` / `pull_velocity(target)` | 每物理步刷新、每施术者替换自己的固定速度贡献；公共 `ball.move/stand` 加到最终世界速度，不累计或写入 Repel、不占用/重置现有距离型击退、不锁输入。按来源弱引用隔离，来源失效、权限/位移免疫、未刷新超过2个物理帧会剔除；暂停无位移。完全自行移动而不走公共 move/stand 的载体需接同一贡献接口，不复制控制算法。招式自己维护抓取寿命/接触重置和网络目标列表；硫方怪为1秒、170世界速度，死亡/结束释放自身租约。 |
| 铁傀儡式真实身体击飞 | `scripts/effects/physical_airborne_effect.gd::launch(victim,caster,apex,up_speed,stun,side_speed,options)` | 身体+碰撞体一起飞、地图/障碍扫掠、锁控制、二次命中平滑重发；`landed_at(point,apex_height)` 或子类 `_on_landing` 自定落地伤害/声音。施术者 RPC 同一调用至各端；铁傀儡子类仅保留专属落地玩法。 |
| 冰面/地表方向加速度 | `scripts/effects/surface_acceleration.gd::touch(target,surface)`；surface 提供 `surface_acceleration_at(world_point)`；`steer_momentum(heading,include_release=false)`；目标可选 `get_surface_acceleration_speed_limit(default_limit)` | 单个权威控制器沿真实位移积分，重叠表面取上限而非叠加；普通目标仍限1.5倍基础速度的额外量。硫方怪持有ICE时目标策略返回INF，用户明确要求在冰径上持续移动就继续加速；持有在旧槽也有效，丢失ICE恢复默认上限。高速采样参考真实物理请求，不误判成瞬移；反弹保存真实行程并沿出射方向继续积分，而不是频繁反弹时每帧漏计。现行冰径加速度240（本轮减半）、静止不创造加速，暂停冻结，离开按600衰减；显式include_release可只重定向已有离冰惯性而不加推力，用于铁效果真正移除后的向上随机偏转。通过公共 `ball.surface_motion_velocity`，不改Speed Buff或抢击退。现行铁退出方向、240实际加速度/单格往返/联机见 `tests/SULFUR_IRON_EXIT_20260927.md`；前轮无上限与反弹修正见冰径专题。 |
| 临时角色对免碰撞 | `classes/body_collision_exclusions.gd::acquire(a,b,holder)` / `release(a,b,holder)` / `are_excluded(a,b)` | 双向 PhysicsBody 排除，按 holder 保留并发租约；不修改层/掩码或受击 Area，不删除预存例外，任一 body/holder 离树自动释放。`world.gd` 软分离同样查询；不能用清空角色碰撞层代替。硫方怪蜂蜜只在当前1秒有效抓取内排除施术者与被抓目标，目标相对路径由权威端复制；超时/挣脱立即释放，同一持续接触不能重新续抓。见 `tests/SULFUR_CUBE_CONTACTS_20260926.md`。 |
| 全项目实体与阶段分类 | `classes/combat_classification.gd::profile_of/is_projectile`；`combat_classification_catalog.gd` | 角色、动态弹体、障碍、地形、状态、纯表现与组件分轴；阶段/模式用数据声明，不复制目录识别。新增资源跑注册覆盖闸门，详见 `docs/COMBAT_CLASSIFICATION.md`。 |
| 投射物类别交互与能力 | `classes/projectile_interactions.gd`；`scripts/projectile_interaction_driver.gd` | 候选/阶段/运动/归属/捕获/反射/格挡统一；旧结构只在共享适配层适配一次，新特殊弹体实现能力协议。原生状态与明确的fire等载荷类型保留，禁止角色私有白名单。详见 `docs/PROJECTILE_INTERACTIONS.md`。 |
| 带类型的实际伤害 | `ball.receive_classified_positional_damage` / `receive_classified_spatial_damage`；空间上下文 `damage_kind` | 元素与载体独立；fire/cold统一倍率免疫，船载分摊保留分量与每名成员免疫；未知类型拒绝，嵌套上下文恢复。不得用整角色标签推断每招元素。 |
| 火焰伤害 | `ball.receive_fire_positional_damage(amount,point,false,caster)` / `receive_fire_spatial_damage(amount,space)`；`can_receive_fire_status()` | `fire_effect_ratio=0` 火免，正值缩放；已有药水火抗也免疫。燃烧状态复用现有状态类，按实际有效伤害播 MC 音效。烈焰弹直击/烈焰火场已接入。普通爆炸不默认算火焰。 |
| 寒冷伤害与寒冷条 | `ball.receive_cold_positional_damage` / `receive_cold_spatial_damage`、`can_receive_cold_status()`；原 `snow_golem/cold.gd` | `cold_effect_ratio=0` 或元素免疫同时拒绝伤害/积寒/冻结，清理只释放自身控制租约。雪地和冻结跳伤用此入口；**雪球直击仍为普通伤害，保留击退**。冻结伤害跟随有效来源当前攻击，默认 9→2；完整规则见 `docs/TRAINING_ENVIRONMENTS.md`。 |
| 训练事件 / 统一融化积雪 | `battle_conditions_catalog.gd` + `battle_conditions.gd`；原 `snow_field.gd` 的两层归属和 `snow_cell_at/snow_point_at/snow_tile_at` | 事件注册表为空，环境默认无。角色雪径、环境地面/墙雪共用真实地图一格及原版纹理；默认8融化秒后原占地淡出0.30秒，雪天仅融化时钟0.5倍，接触/寒冷冷却不变。关闭天气停止新增，残雪自然消失，不重置年龄；淡出无伤害/威胁，墙始终装饰。可靠同步带符号剩余时间/倍率，晚加入不续寿；真正换图/重打清理。见 `docs/TRAINING_ENVIRONMENTS.md`、`tests/SNOW_SHARED_MELT_20260927.md`，不要恢复永久层或半格阶段。 |
| 原版动作声音的非重叠通道 / 子世界归属 | `mc_native_audio.gd::queue_stream` + `channel_busy(ticket)`；雪傀儡 `snow_golem/audio.gd::queue_action` 只适配已验证流 | 队列可选 `audio_parent`（弱引用校验）、`groups`、取消票据，默认路径不改；整个创建/挂载/播放延后。通道按queued/真实playing/所选流与音高的实际时长判断，硫方怪旧入口委托同一实现。雪傀儡真实步伐/反弹、0dB发射、原wood.break碎头权威选择变体与可靠复制，不消费攻击RNG；不能用静止速度值触发脚步或用Playing标志代替PCM验收。见 `tests/SNOW_GOLEM_ACTION_AUDIO_20260927.md`。 |
| 雪傀儡概率连射 / 一次性碎头 | 原 `snow_golem.gd::fire_at/step_mob` + `snowball.gd`；`block_fragments.gd::spawn_texture` | 一轮一次10%抽签，20发独立微间隔/±15°，每颗仍是原雪球判定；半血只碎佩戴头并保证下一轮，不构造或召唤。碎片可传 `seed` / `effect_parent` 复用原落地运动，支持正确战场作用域与各端相同轨迹；不用另外复制粒子系统。见 `tests/SNOW_GOLEM_BURST_20260927.md`。 |
| 砸地/地板碎屑 | `mc_combat_abilities.gd::ground_impact(parent,point,radius,options)` → `重锤落地冲击.gd` | `show_impact_ring/show_impact_streaks`、方块来源/数量/尺寸/高度/飞行时间/散布、中心高度曲线等导出参数；白圈、碎屑可分别关闭。重锤、铁傀儡、三叉戟、监守者及长弓落箭共用真实地表采样与碎屑运动；角色负责伤害。 |
| MC 像素外圈 / 蓄力填充盘 | `pixel_arc.gd::draw_ring(canvas,center,radius,tint,opacity,palette)` / `draw_disk(canvas,center,radius,color)`；持续预警用 `mc_combat_abilities.gd::charge_circle(parent,radius,options)` → `mc_charge_circle.gd` | 重锤与 TNT 共享三层像素环；填充复用同一扫描线缓存。`set_charge(world_point,world_radius,progress)` 由角色真实计时更新，支持颜色、透明度，世界尺度不受父节点缩放影响；角色负责结束隐藏/删除与权威伤害。后续 MC 范围圈优先用此接口，不再另写平滑 `draw_arc/draw_circle` 或复制三层常量。回归见 `tests/SULFUR_CUBE_POLISH_20260926.md`。 |
| 无伤害扩散渐隐像素环 | `mc_combat_abilities.gd::expanding_ring(parent,point,radius,options)` → 原 `重锤落地冲击.gd` → `pixel_arc.draw_ring` | `palette` 三层颜色、`end_scale`、`lifetime`、`z_index`、`name`；`direction` 为环面朝向/法线，`depth_ratio` 沿法线投影压缩（默认1平面；长弓0.35伪3D），横向不压缩；世界坐标/尺寸不随父节点缩放移动，半径沿用公共下限8。关闭方块、射线与地表读回，不消费战斗随机种子；暂停冻结，归入 `BattleTransient`，按 lifetime 自清理。施术者只在真实触发时可靠 RPC 每端播一次，不从状态回放重复发圈。天堂陨落长弓已接入，见 `tests/HEAVENFALL_MUZZLE_RING_20260926.md`。 |
| 爆炸 | `mc_combat_abilities.gd::explosion(context,point,radius,options)` → `mc_explosion.gd` | 声音、种子、粒子量、场外显示等仅改变表现；伤害和命中判定归权威技能。 |
| 飞离地图的贴图碎裂（物品死亡等） | `item_fragments.gd::spawn(character,options={})` 供角色；任意可视节点 `spawn_visual(node,options={},tile_info={})`，裸纹理 `spawn_texture(context,texture,point,scale_factor,options)`；旧障碍兼容入口 `spawn_obstacle(node,tile_info={},options={})` | 取源 Sprite/Polygon/TileMap 当前贴图切片，碎片向上飞、旋转并落出地图后删除；`gravity/launch_up_min/launch_up_max/horizontal_speed/spin_speed` 可调。木矛、重锤、钻石剑、铜剑等死亡使用它；**恶魂/凋零破障本来就使用其 `spawn_obstacle` 入口，此次保持原状**。这是通用特效，不限于人物死亡，也不是落地小方块特效。 |
| 方块破坏小粒子（落地） | `block_fragments.gd::spawn_obstacle(block,tile_info={},options={})`，无 Sprite 的方块用 `spawn_texture(context,texture,point,scale_factor,options)` | 取原方块 Sprite/TileMap atlas/Polygon（或传入原版方块纹理），切成至多 `max_pieces` 块；`scatter_radius/arc_height_min/arc_height_max/flight_min/flight_max/ground_hold/fade_time/spin_speed/z_layer` 可调。碎块沿抛物线飞出、**落地停留**再淡出；轨道覆盖、剑工作台与苔藓破块沿用之前已接入的调用。**不更改恶魂/凋零破障原有的离场碎裂与进度、伤害逻辑**。 |
| 障碍破坏与裂纹 | `ghast_obstacle_damage.gd::ensure(context)` / `mc_combat_abilities.gd::obstacle_blast(context,point,radius)`；各端 `apply_obstacle_updates` | 共用 0–100 进度，默认每爆 +34、裂纹阈值 34/67、100 破坏；素材为 `Images/Status/BlockDamage` 中的原版裂纹。静态障碍/地图碰撞格默认走统一属性；场景根节点可挂 `MCObstacleProperties` 调 `destructible/blast_step/crack_thresholds`，TileSet 单格可加 `mc_obstacle_destructible`/`mc_obstacle_blast_step` 自定义数据。地图安全边界强制保护。恶魂/凋零已用同一管理器。 |
| 鞘翅软回航 / 长矛加速穿刺 | `鞘翅重锤.gd::_map_return_aim` 共用原滑翔积分；`鞘翅长矛.gd::try_pierce_dash` 与原矛尖扫掠/命中提速；组合仅覆盖完成回调 | 三种飞行共用96单位距离、速度前瞻和角速度回转；回航不传送/硬钳。已开始的连砸在回航中保留等级/倍率与落砸扫掠，不误作砸空；穿刺后尚未开始的待发连砸仍取消。新冲刺只在两种带矛角色，命中不建第二套伤害体，完成穿越后组合再接原连砸；媒体复用原烟花/残影。手控与权威/晚加入状态见 `tests/ELYTRA_RETURN_DASH_20260926.md`。 |
| 凋零头弹 / 冲刺原版烟雾拖尾 | `mc_visual_effects.gd::sample_smoke_trail` + `smoke_particle`，复用原末影粒子运动/淡出 | 按距离取样，间距/后移参数化；头弹6/6、冲刺12/30，共用48点/次和256枚粒子上限。头弹碰撞路径截断；稳定凋零节点仅同步视觉，不在远端缺失的头弹上RPC。原版来源/生命周期/分类/边界见 `tests/SKULL_TRAIL_COMBO_20260927.md`。 |
| 凋零 / 信标生命周期音效 | `wither/audio.gd::play` / `_play_in_scene` | 整体延后创建、挂载、设置位置和播放；原场景弱引用校验防切场串音/孤立播放器，死亡尾音可在source删除后完成。保留原版流/参数/公共总线；双引擎与实际PCM验证见 `tests/WITHER_AUDIO_LIFECYCLE_20260927.md`。 |
| 原版空间音效安全队列 / 硫方怪材质声 | `mc_native_audio.gd::queue_stream(context,stream,point,options)`；旧 `play` 继续共用 `_create_player`；`sulfur_cube_audio.gd` 仅做素材/参数适配 | 返回请求票据，不提前分配孤立播放器；整体延后挂载/播放，弱引用校验原场景，普通动作随source取消、死亡/已结算伤害尾音可保留。24声部含排队预约，伤害/死亡优先替换材质声，走公共游戏录制总线。硫方怪29事件/92原版Ogg，明确无呼吸且已移除铁落下/撞地声；实际伤害从0dB按公共增益，覆写原版crit事件0.7衰减。移动声按实际开始时间/所选流/音高避免重叠；冰径本地状态单次响并合并同来源短时间批次，角色动作权威选变体RPC每端一次。见 `tests/SULFUR_AUDIO_REVISION_20260927.md`。 |
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

2026-09-26 发射环朝向纠正：长弓使用法线与箭矢一致的伪3D透视椭圆，并可靠同步发射瞬间的方向，不使用接收端实时朝向。复用同一像素环draw变换，旧地面圈不变；GPU六方向、衰减和ENet等239项回归见 `tests/HEAVENFALL_MUZZLE_3D_20260926.md`。

## 2026-09-27：公共负面净化

`target.cleanse_negative_effects()` 由权威端发起，只清除显式负面状态，保留正面药水/数值增益与自主运动。铜剑只在自然锈满落雷的实际命中回调调用；攻击落雷不调用。节点使用公共身份/阶段的 `status_polarity`、`status_cleanup`，动态效果实现 `get_status_effect_polarity()`，可用 `cleanse_status_effect()` 精确释放自己的控制、伤害和视觉；外部节点以弱引用注册，外部数据持有者监听 `negative_effects_cleansed`（蜂蜜范例）。新状态不可只加铜剑特判，必须通过登记/协议门禁。完整协议和当前覆盖见 [STATUS_CLEANSING.md](STATUS_CLEANSING.md)。
