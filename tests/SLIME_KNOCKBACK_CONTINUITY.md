# 史莱姆跳跃中击退后的位移连续性

## 修复原因与行为
- 根因：new5.step_mob 在空中继续推进 jump_elapsed，但公共 ball.tick_physics 在 dizziness（含击退控制锁）期间调用 stand，而非史莱姆自己的 move。因此跳跃的 _motion_phase / _jump_lift 没有跟随时钟更新，解控第一帧把积攒的平移和高度差一次补上。
- 史莱姆空中的 Stand 现在也消费本帧的跳跃进度，使用现有碰撞移动完成连续升降，并把 Repel 叠加在当前真实位置上。落地后恢复原公共 Stand 行为。
- 被控制期间抑制的自主跳跃路程随该帧消耗，不储存到解控后补走；短控制结束后只恢复新的逐帧位移。
- 不重新写入起跳原点、不瞬移到旧落点、不免疫击退。三种体型共用此修复，未改变普通跳跃参数、墙体阻挡、伤害或分裂身份/胜负契约。
- 只有史莱姆脚本改动；没有修改公共击退控制器、Ball 移动或其它角色。

## 2026-09-22 最终验证
Godot 4.7.2 / D3D12 GPU 模式，以下 6 个测试进程均 exit 0：

| 测试 | 通过 | 失败 |
|---|---:|---:|
| test_slime_knockback_continuity | 63 | 0 |
| test_slime_physical | 222 | 0 |
| test_slime_family_victory | 63 | 0 |
| test_slime_deferred_turn | 189 | 0 |
| test_slime_damage | 24 | 0 |
| test_slime_adaptive | 87 | 0 |
| 相关回归合计 | 648 | 0 |

新专项在真实 physics_frame 中驱动公共 tick_physics 分派、实际击退控制器和实体碰撞，覆盖大/中/小三阶段的上升/顶点/下降受击、长锁/短锁及恢复过渡、左右位移保留、上下击退、墙阻挡、非锁定 Repel、铁傀儡真实实体击飞及下一跳从当前坐标起步。不是仅修改外观或直接调用 move 绕过受控状态。

脚本错误诊断 0，修改范围 git diff --check 通过。保留既有 shader UID/大小写、旧测试 ObjectDB 退出清理警告。本轮没有重跑跨角色 test_mc_new5 综合旧测试，其上一轮 14 项失败仍见 SLIME_FAMILY_VICTORY.md；这里的 648/0 仅指列出的相关回归。未执行真实双进程联机或人工操作验收。
