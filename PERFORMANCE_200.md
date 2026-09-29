# PERFORMANCE_200 —— 200 单位同屏优化报告

目标：任意 200 个角色同时存在时基本流畅（用户确认目标 ≥60 FPS）。
测试机：RTX 4060 Laptop，Godot 4.7.2，540x960，`tests/benchmark_200.gd`（100 初始 + 100 追加 = 200 单位，12 秒采样）。

## 结果汇总

| 场景 | 优化前 | 优化后 | 说明 |
|---|---|---|---|
| 200 × 战士（近战，无投射物） | 25.7 FPS | **61.7 FPS**（p50 8.1 ms，p95 33 ms） | 达标 |
| 200 × 小刀猎（每人持续发射飞刀，同屏约 320~350 把活飞刀） | 9.5 FPS | 9.8~11 FPS（p50 80~92 ms） | 未达标，见下文 |

战士类 200 单位已达到 60 FPS。小刀猎类是最坏情况：200 个角色 + 300 多个活的飞刀刚体，等价于 500+ 个物理体互相查询，瓶颈在物理服务器本身，而非脚本/特效。

## 做了什么（规则不变：伤害、冷却、碰撞规则全部保持）

1. **大战斗物理 30Hz**（`world.gd: large_battle_reduce_physics_tick / large_battle_physics_ticks_per_second`，`game.gd: set/get_large_battle_physics_tick_override`）：单位数超过阈值时自动降到 30 tick/s，数量回落后自动恢复 60。状态机分频器和 ball 视觉分频器同步调整，保证移动速度、冷却时间不变。
2. **投射物瘦身**（`classes/runtime_knife_scene.gd`）：运行时从 knife.tscn 剥离对投射物无意义的节点：Health_Bar、AnimationPlayer、Status_Image、Health_Restore_Timer、Hurting_Timer、CharacterAutoFit、Graphics/AnimatedSprite2D，以及离线（OfflineMultiplayerPeer）时的 MultiplayerSynchronizer。外观与伤害不变；实例化耗时 101 ms → 20 ms / 300 次（`tests/test_runtime_knife_scene.gd`）。
3. **最近敌人查询缓存**（`world.gd: _refresh_one_nearest_enemy`），分帧刷新。
4. **视觉密度随单位数自动降低**（`world.gd: get_large_battle_visual_density()`，最低 0.35，160 单位以上生效，回落自动恢复）：受击粒子、命中取样次数、飘字、击杀血迹、飞刀残影间距/上限都按密度缩放。
5. `set_image_node_type` 容忍被剥离的节点；`_character_ground_shadow_body_metrics` 确认只在生成时调用一次（0.18 s 一次性），不是每帧热点。

## 小刀猎为何仍是 ~10 FPS（实验数据）

用 `tests/benchmark_200_exp.gd --exp=` 做了排除法（都在全部优化基础上）：

| 实验 | FPS | p50 帧时 | 物理 p50 |
|---|---|---|---|
| 当前代码 | 9.8 | 92 ms | ~92 ms |
| 完全关闭飞刀残影 | 10.7 | 80 ms | 91 ms |
| 关闭血迹 | 11.0 | 79 ms | 90 ms |
| 关闭受击飘字 | 10.1 | 87 ms | 93 ms |

帧阶段分解：物理墙钟 p50 43~63 ms，process 21~27 ms，渲染仅 6~8 ms。特效全关也只能多 1~2 FPS，剩下的开销全部是 **~340 个活飞刀刚体**：物理 `flush_queries`/碰撞对、每帧 30+ 次飞刀实例化 + `add_child`、命中链路（hitbox.try_hit_hurtbox → knife._on_hitbox_on_hit → take_damage → Die）。这已经不是"200 个角色"的问题，而是"550 个物理体"的问题。

## 要让 200 小刀猎也到 60 FPS 需要什么（超出本轮范围，会改动结构）

1. **飞刀对象池**：不销毁/重建，复用节点，消灭每帧实例化 + add_child + 物理体注册成本（预计 -15~20 ms/帧）。
2. **服务器端射线/形状投射代替飞刀刚体**：飞刀改为 `PhysicsDirectSpaceState2D.intersect_ray/cast_motion` 的纯数据弹道，只保留一个 Node2D 做渲染（或 MultiMesh），物理体数从 550 降回 200。这是唯一能把物理墙钟压到 16 ms 以下的方案。
3. 飞刀命中后的 `Die` 路径简化（312 µs/次，30+ 次/帧）。

## 文件
- 基准：`tests/benchmark_200.gd`（`--char= --count= --label= --duration=`）、`tests/benchmark_200_exp.gd`（`--exp=noafterimage|nostretch|minvisual|noblood|notext`）
- 结果 JSON：`scripts/training/benchmark_b200_*.json`；日志 `bench_b200_*.log`
- 测试：`tests/test_rotation_wasted_overlay.gd`（11/11）、`tests/test_performance_contracts.gd`（208/208）、`tests/test_runtime_knife_scene.gd`（1348/1348）

