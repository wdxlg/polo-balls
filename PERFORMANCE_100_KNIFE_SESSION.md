# 100 小刀猎 / 50×50：本轮优化与验证

## 结论：有所改善，尚未解决流畅性问题

在当前 ShunCode 工作区 `E:\godot\polo-balls` 修改并实测。使用用户指定的 Steam Godot 4.7.2，可视窗口 540×960，Forward+ / D3D12 / RTX 4060 Laptop GPU。

本轮正式逻辑已接入三项优化；当前压力场景仍仅约 5 FPS，不能视为“百人流畅”验收通过。

| 指标 | 本轮开始前 session_baseline | 最终代码 session_verified |
|---|---:|---:|
| 平均 FPS | 3.870 | 5.308 |
| 帧耗时 P50 | 216.194 ms | 167.776 ms |
| 帧耗时 P95 | 407.823 ms | 298.049 ms |
| 帧耗时最大值 | 485.148 ms | 328.016 ms |
| 采样帧数 | 47 | 64 |
| 采样墙钟时长 | 12.146 s | 12.057 s |
| 最少存活角色 | 92 | 88 |
| 节点峰值 | 10106 | 8740 |
| 创建 100 人耗时 | 160.158 ms | 221.682 ms |

最终帧率比本轮基线高约 37%，但两次战斗允许自然死亡，模拟推进和存活人数不同，不是严格同状态回放或全程固定 100 人的稳态对照。初始化变慢主要包含新增音频预热成本；没有把这部分开销隐瞒在战斗指标中。另一轮接近最终版本的运行得到 5.462 FPS，不应据此承诺稳定帧率。

场景：100 个小刀猎，两队各 50 人，Map50x50，友伤关闭，血液效果开启，正常生命、攻击和死亡，1 倍速，关闭 VSync。没有减少人数、伤害、飞刀、残影数量，也没有降低物理更新频率或开启独立渲染线程。

## 本轮生产改动

1. `scripts/shooter/knife.gd`
   - 普通飞刀在物理更新期间使用现有 `classes/after_image_render_batch.gd` 管理残影 RID，避免每张残影创建 Sprite2D 和独立 Tween。
   - 保持残影采样时机、数量、透明排序分组、持续时间和曲线；不支持的节点特性自动回退原实现。
   - 非物理阶段保留原实现，避免在 SceneTree Tween 阶段中创建残影时提前推进一帧。
   - 保留 `batch_after_image_snapshots` 开关，可在 Inspector 关闭以对照原路径。
2. `classes/after_image_render_batch.gd`
   - 将直接计算的进度比例改为与原实现相同的 `Tween.interpolate_value` 线性 / EASE_IN_OUT 运算。
   - 修复初次视觉对照出现的少量单通道 1 级差异；最终严格像素比较为零差异，没有放宽测试阈值。
3. `global/audios.gd` 与 `scripts/characters/杀戮尖塔/小刀猎.gd`
   - 首次创建小刀猎时预热 `KnifeThrow1` 的 128 个 Ogg playback。
   - 使用项目已有的 `prewarmed_audio_stream.gd`；仅当 playback 没有外部持有引用时复用，忙碌的声音不被抢占，容量不足回退新建。
   - 不改变播放调用次数、参数、音高随机化、解码器和音频总线路由；其他音频格式不接入此优化。
4. `global/game.gd`
   - 运行时翻译使用非持久 Control 分组索引，不再递归扫描所有飞刀、计时器和特效节点。
   - 保留动态文字刷新、当前场景与 Game 的范围限制、内部节点排除规则、节点退出 / 释放 / 重挂处理。
   - 仍然每次扫描重新建立翻译结果缓存，不引入跨帧译文缓存。

没有接入 `.performance_tools` 中的实验原生 DLL、异步场景构造或更换 Godot 可执行文件。

## 验证

所有下述最终测试均通过 Start-Process -Wait -PassThru 等待实际 Godot 退出并检查 ExitCode=0，而非只依赖 PowerShell 的默认成功状态。

- 残影视觉：正常源、提前释放源各 7 帧，共 14 帧严格逐字节一致，覆盖六种风格、翻转、颜色、多个位置及淡出；生命周期结束后 snapshots 和 groups 均为空。
- 音频：385 项，0 失败，覆盖复用、打断后重启、seek、不同播放速率及外部持有引用；这是 playback 级验证，不是多人联机音频的全量测试。
- 战斗存在性旧契约：208 项，0 失败。
- 新增翻译索引测试：9 项，0 失败，覆盖动态新增、内部节点及其后代、移入 / 移出内部子树、移出 / 重挂、释放和动态文本。
- 翻译微基准：3000 个非 Control 节点 + 200 个 Label，20 次扫描，旧递归约 37.180 ms，索引约 13.682 ms。此结果仅为局部微基准，不等同整局收益。
- 最终真实对战基准正常退出，编辑器 diagnostics 无错误 / 警告。空 diagnostics 不作为独立的完整正确性证明。

未完成：全角色技能、多人同步、全局暂停 / 多倍率战斗、不同地图和长时间稳态的完整回归。

## 排除的方案

本轮尝试仅通过命令行启用独立渲染线程：约 3.976 FPS，收益不明显，Godot 提示该功能实验性，退出时报 render-thread finalize 错误。未写入 project.godot，正式代码仍使用默认安全模式。

## 留存与复现

- `scripts/training/benchmark_session_baseline.json`
- `scripts/training/benchmark_session_verified.json`
- 对应的 `benchmark_session_baseline_engine.log`、`benchmark_session_verified_engine.log`
- `scripts/training/test_batch_normal_session_verified.log`
- `scripts/training/test_batch_death_session_verified.log`
- `scripts/training/test_audio_pool_session_verified.log`
- `scripts/training/test_performance_contracts_session_verified.log`
- `scripts/training/test_localization_index_session_verified.log`
- 新增测试：`scripts/training/test_localization_index.gd`
- 残影比较测试新增 `--kill-source`；原生实验对照测试显式关闭生产批量路径，避免对照基线被替换。

```powershell
$g = 'E:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
$p = Start-Process -FilePath $g -ArgumentList @('--path','.', '--resolution','540x960', '--script','res://scripts/training/benchmark_100.gd','--','--label=manual_verify') -NoNewWindow -Wait -PassThru
$p.ExitCode
```

测试入口不挂到正常游戏场景；基准正常结束会恢复测试进程中的 Game 设置。不要同时运行多个压力测试或在另一游戏进程里修改保存设置。

## 仍需继续解决的瓶颈

百人攻击链仍有大量完整 ball 派生飞刀场景创建 / 释放、脚本调用、受击像素采样和效果生命周期开销。小修不足以从 5 FPS 达到流畅。下一阶段需要针对当前正式代码重新采集稳定场景 profile，再评估轻量飞刀生命周期 / 碰撞接口或更深层批处理重构，并明确验证命中、伤害归属、特殊状态、联机、暂停与重置；不能把目前结果称为已经解决。
