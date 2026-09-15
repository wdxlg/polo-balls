# 第三轮：百人小刀猎性能优化

## 结论

本轮保留残影绘制命令缓存，撤回没有测出收益的碰撞掩码合并实验。
百人场景本轮修改前 6.1616 FPS；修改后两次为 6.3212 / 6.3320 FPS。
平均约 +2.7%，幅度很小，样本不足以证明稳定的显著提升；仍未解决卡顿。
没有减少人物、飞刀或残影数量，没有降低物理频率或修改战斗速度。

## 保留的生产改动

`classes/after_image_render_batch.gd`：
- 空闲的、不可见且已脱离父画布的残影 RID 保留已有纹理绘制命令和材质引用。
- 下次复用时，仅在纹理身份或有效绘制矩形发生变化时清除并重建命令。
- 材质变化时才重新绑定材质。
- 颜色、进度、方向、变换、缩放、寿命、透明绘制顺序仍按原路径更新。
- 飞刀销毁后，进度停止更新而缩放继续的原有 Tween 行为保留。
- 空闲记录仍限制为 2048；池内现在会保留对应的纹理/材质引用，换取更少的重建。
- 不保留飞刀 Node 引用，不复用玩法对象、物理身份或异步协程。

本次减少的是 CPU 端绘制命令的重复录制/清除，并非 GPU draw call 数量。

## 实测

Godot 4.7.2 Steam、RTX 4060 Laptop、D3D12 Forward+、540×960、HDR2D；
100 小刀猎、50 对 50、Map50x50、seed 20260914，血液开启、速度 1。
预热 2 秒、采样约 12 秒；配置 60Hz/default 8 physics steps，无 steps 覆盖。

| 指标 | 修改前 | 缓存第 1 次 | 缓存第 2 次 |
|---|---:|---:|---:|
| FPS | 6.1616085 | 6.3212313 | 6.3320026 |
| 帧时间 P50 ms | 147.504 | 146.938 | 154.230 |
| 帧时间 P95 ms | 240.020 | 231.668 | 226.298 |
| 最大帧时间 ms | 254.296 | 246.905 | 240.602 |
| 物理 ticks / 墙钟秒 | 48.5435 | 49.9045 | 48.7398 |
| 节点峰值 | 8705 | 8700 | 8876 |
| GPU draw calls 峰值 | 2819 | 2840 | 2869 |
| 采样最低存活数 | 88 | 87 | 86 |
| 新录制命令数（含预热） | 未计数 | 2283 | 2280 |
| 复用命令数（含预热） | 不支持 | 57614 | 59090 |

修改后约 96% 的残影创建复用了既有绘制命令。该比例不是 FPS 提升率。
战斗允许自然死亡，不是固定存活数、相同状态的确定性重放；运行噪声仍存在。

JSON 位于 `scripts/training/benchmark_round3_before.json`、
`benchmark_round3_cache1.json`、`benchmark_round3_cache2.json`（基准按 label 保存）。
工具运行记录：基线 cmd_1789364127245_143；缓存两次 cmd_1789364320581_146，实际退出码均为 0。

## 已撤回 / 未采用

- 连续碰撞层写入合并：6.0666 FPS，相对本轮基线没有收益，已还原；
  `classes/ball.gd` 最终 SHA256 与第二轮结束时一致：
  `36ec350faadb13d2b7baced79ca645b3083708f780367ec0ad023cfc2528e6ac`。
- 未删除 Health_Bar：它不仅是视觉节点，还承载生命、护盾、能量信号；
  基类 block setter 在没有 health_bar 时会提前返回。直接裁剪可能改变玩法接口。
- 没有替换飞刀的 ball 继承架构，没有删除状态机、碰撞体、计时器或同步节点。

## 最终验证

实际 Godot 图形运行，cmd_1789364475516_148，四个进程均实际退出 0，日志无此前错误的 res:// 日志路径问题。
- 场景缓存：3212 检查，0 失败。
- 伸缩材质参数缓存：521 检查，0 失败。
- 视觉采样：3200 像素、468 属性、2720 条纹/随机序列检查，0 失败；GPU snapshot 完全一致。
- 残影命令缓存：4 波、28 帧、最大通道差 0；54 次重录、18 次复用。
  覆盖更换颜色、offset/centered、纹理，以及最后一波提前销毁飞刀。
- 修改文件诊断为 0。

日志：`scripts/training/test_runtime_knife_scene_round3.log`、
`test_stretch_uniform_cache_round3.log`、`test_round2_sampling_round3.log`、
`test_render_batch_round3.log`。

没有完成全角色、联机、长期内存压力回归，不能据本轮测试声称这些场景全部通过。

## 复现

使用提供的 Godot，从项目目录串行运行：

```powershell
$g = 'E:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
$p = Start-Process -FilePath $g -ArgumentList @('--path','.', '--resolution','540x960', '--script','res://scripts/training/benchmark_round3_final.gd','--','--label=round3_repro') -Wait -PassThru -NoNewWindow
$p.ExitCode
```

必须检查进程实际 ExitCode；不要添加 --steps 覆盖。
