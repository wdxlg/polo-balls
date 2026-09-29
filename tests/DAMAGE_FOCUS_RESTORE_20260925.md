# 高伤害镜头推近恢复（2026-09-25）

## 故障与修复

- 普通 100 点命中曾正确进入 `World.request_damage_focus()`，但实时画面、中文录像和英文录像都看不到推近。根因是 `scripts/ui/battle_recorder.gd::_sync_player_composition()` **即使不录制也每帧运行**：地图适配用已含伤害倍率的 `get_effective_camera_zoom()` 当基数，适配系数与该倍率互为倒数，最后覆盖 `Camera2D.zoom`，恰好抵消推近。
- 现在地图适配和平滑跟随只用基础地图 zoom × 手动工具栏倍率计算；电影/命中临时倍率在最终相机 zoom 处再叠加。玩家和中英文录制视口共用这台相机，因此三个画面都会显示同一次命中。保留 FULL / FOLLOW 原有构图及 VS 独立屏幕层。
- 100 点伤害秒杀仅剩 20 HP 的目标时，HP 下限会把实际损失截为 20。仅在**减伤/护盾后确实扣到 0 HP**时按未被 HP 下限截断的请求伤害判断推镜；免疫、纯护盾和角色钩子救回仍以确认后的净生命损失为准。
- 高血量目标的原门槛为 `max(40, 最大生命值 × 0.25)`，1000 HP 目标门槛 250，100 点有效伤害也不触发。现将动态门槛上限设为 75（仍不低于配置的 `damage_focus_min_damage`）；原比例、冷却和推近强度保留。

## 可复现的 GPU 验证

需在 Windows 图形桌面以本项目 Godot 4.7.2 离线引擎运行，不可用 headless 冒充绘制验证：

```powershell
$engine = (Resolve-Path ../polo-balls-tools/offline-engine/runtime/Godot.4.7.2.offline.exe).Path
& $engine --path . --rendering-method gl_compatibility --script res://tests/test_damage_focus_zoom.gd
& $engine --path . --rendering-method gl_compatibility --script res://tests/test_damage_focus_recording.gd
```

2026-09-25 实测：

| 入口 | 结果 | 关键帧/边界 |
| --- | --- | --- |
| `test_damage_focus_zoom.gd` | **19/19** | 普通 100/200：5.8725→6.5772；过量 100/20：→6.7534；高血量 100/1000：→6.3423。10 点、免疫、纯护盾均无虚假推近。 |
| `test_damage_focus_recording.gd` | **16/16** | 真实 LIVE 中英双录：FULL 秒杀 5.8725→6.4239；FOLLOW 非致命 14.5→15.8911；两种语言逐帧同步，VS 镜像持续可见，四份 MP4 均写入磁盘。 |
| 标题/地图既有回归 | **27/27、27/27、73/73、18/18** | `test_vs_title_motion.gd`、`test_vs_screen_title.gd`、`test_vs_map_scaling.gd`、`test_vs_team_counts.gd`。 |

截图和 MP4 位于 `user://recordings/damage_focus_zoom/`（Windows：`%APPDATA%\Godot\app_userdata\polo_balls\recordings\damage_focus_zoom\`），不纳入 Git。实际抽取并检查了中文 FOLLOW MP4 的画面：1080×1920、60 fps、62 帧，拉近时 VS 仍位于标题安全区。此验证覆盖画面与录制输出，不声称覆盖所有角色特效或双客户端联机。

本次提交只包含上述三个生产文件的目标片段、本专题两个回归脚本与本说明；其他既有未提交改动和生成录像均不收录。通过 `git revert` 本提交可独立撤销，不必撤销先前的 VS 修复。
