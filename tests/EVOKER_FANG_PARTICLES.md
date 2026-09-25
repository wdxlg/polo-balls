# 唤魔者尖牙：闭合粒子与出土方块碎屑

2026-09-26 实现说明。目标来自用户两点要求：尖牙**闭合时**要有原版那样的粒子；**钻出地面时**复用重锤的小方块粒子，但**不要中心那一团，只要四周，且向上的力不大**。伤害、命中判定、音效、图腾与其他技能均未改动。

## 原版参照

`net.minecraft.world.entity.projectile.EvokerFangs#tick()`（`mahtomedi/minecraft` 镜像，已在会话中核对）：服务端在 `warmupDelayTicks == -8` 结算伤害并广播 entity event 4；客户端收到事件后置 `clientSideAttackStarted`，当 `lifeTicks == 14` 时在尖牙包围盒内随机取 12 个点发射 `ParticleTypes.CRIT`，速度 `(±0.3, 0.3+rand*0.3, ±0.3)`。**是否命中不影响粒子**。

## 实现

- `scripts/effects/我的世界/唤魔尖牙.gd`
  - `native_animation_progress() >= 0`（ jaw 开始出土的那一帧）触发一次 `_emit_emergence()`；`_delay` 命中帧触发一次 `_emit_bite()`。时序与伤害判定不变。
  - 出土：调用公共入口 `mc_combat_abilities.gd::ground_impact`（即重锤的 `重锤落地冲击.gd`），关闭 `show_impact_ring/show_impact_streaks`，只保留小方块碎屑。环形采样 `block_source_inner_radius_scale=0.70`、`block_source_radius_max_scale=0.95`、`block_exclusion_radius=7.0` 把出生点排在尖牙四周，中心不放碎屑；上升高度 `2–4` 像素、飞行 `0.25–0.36s`、落地停留 `0.06–0.12s`，尺寸 `1–2` 像素。
  - 一次施法会同时抬起数十张嘴（环形 12/16/20），所以用技能已有的共享 `_hits` 账本作本地配额：每份 `_hits` 只允许 4 次碎屑爆发，其余尖牙照常出土与闭合，避免一次施法生成上百个采样节点。
  - 闭合：`mc_combat_abilities.gd::critical_burst` 发射 12 颗 CRIT，位置为尖牙上方 10 像素、半径 10 像素圆面采样，中性灰白（`neutral_tone`、`tone 0.86–1.0`），上抛 24–42 像素/秒、重力 100–140，寿命沿用批量层的 0.29–0.37s。
- `scripts/effects/combat_impact_layer.gd`：新增 `add_visual_critical_burst()`，只做视觉，不生成伤害、不改 `critical_particle_count()` 的 >50 伤害阈值；`side/up/gravity/tone/neutral_tone` 成为可选参数，默认值即原行为。
- `scripts/effects/我的世界/mc_combat_abilities.gd`：`critical_burst()` 复用世界已有的 `CombatImpactLayer` 批量层（沿用其单兵/全局上限与屏外剔除），不新建角色专用粒子实现。
- `scripts/effects/我的世界/重锤落地冲击.gd`：新增 `block_source_inner_radius_scale`、`block_exclusion_radius` 两个导出参数，默认 `0.0` 时行为与改动前完全一致，重锤/监守者/三叉戟等既有调用者不受影响。

## 验证

`tests/test_evoker_fang_particles.gd`（Godot 4.7.2，`--headless` 与真实 GPU 各一遍）：

- headless **25/25**，D3D12 实际渲染 **26/26**；GPU 差分像素出土碎屑 212、闭合粒子 893（`user://fang_particles_gpu.png`，已人工查看）。
- 覆盖：闭合前无碎屑/无粒子、碎屑早于命中时间、复用重锤脚本、12–18 块上限、无中心圈与射线、所有碎屑起点在 7 像素外且向外飞、上升 2–4 像素、四个方向都有出生点、一次施法仅 4 份额外碎屑批次但每颗尖牙仍照常出土闭合、闭合恰好 12 颗、使用与原版像素一致的 `Images/paricle/critical_hit.png`、尺寸沿用共享渐变而非另设贴图、普通伤害暴击阈值不变、暂停不重复触发、粒子按寿命清空、碎屑与尖牙各自独立清理。
- 回归：`tests/test_mc_warden_ground_debris.gd` 140/140（真实 GPU）、`tests/test_ground_visual_sampling.gd` 0 失败、`tests/test_drowned_wall_only.gd` 45/45、`tests/test_mc_fragment_contract.gd` 18/18、`tests/test_mc_evoker_impact_audio.gd` 16/16、图腾三项 41/41、17/17、13/13。`tests/test_drowned_surface_rules.gd` 是既有的主动 SKIP。
- `tests/test_mc16_charged_impact.gd` 有 4 项失败（三叉戟附魔光泽贴图与落插状态），该文件与相关代码在本任务前后均无改动，属既有失败，未一并处理。

## 边界与回滚

- 尚未做真实双客户端联机观察与连续视频人工验收；粒子为每端本地表现，不进入网络同步与随机主序列（视觉 RNG 独立）。
- 引擎既有告警仍在：`ball.tscn` 着色器 UID 回退、`set_rgb_color.gdshader` 大小写、测试退出时 ObjectDB 泄漏若干实例。
- 回滚仅需还原上述 4 个脚本与本测试/文档；默认导出参数为 0 时公共落地冲击行为与旧版一致。
