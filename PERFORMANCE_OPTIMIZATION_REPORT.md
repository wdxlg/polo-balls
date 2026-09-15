# 百角色性能优化记录（阶段性，目标未达成）

## 结论

本轮已提交保守优化并通过局部等效性验证，但**尚未达到“100 个角色同时存在而几乎不卡”的目标**，不能作为性能验收通过。

场景由用户指定：小刀猎、Map50x50。测试采用 100 个角色、两队各 50 个、关闭友伤、正常伤害/生命/死亡流程、1 倍速、关闭垂直同步，窗口 540×960；保留飞刀、残影、受击线条、音效，并开启血液效果。没有改游戏主入口、项目渲染配置或角色数值。其余设置见 JSON。

硬件：AMD Ryzen 7 8845H、NVIDIA RTX 4060 Laptop GPU。Godot 4.7.2 Steam，Forward+／D3D12。

| 指标 | 修改前（baseline2） | 本轮修改后（step3） |
|---|---:|---:|
| 平均 FPS | 2.26 | 4.21 |
| 帧耗时 P50 | 458.319 ms | 203.292 ms |
| 帧耗时 P95 | 538.134 ms | 355.095 ms |
| 采样时长（墙钟时间） | 12.384 s | 12.120 s |
| 采样帧数 | 28 | 51 |
| 采样中最少存活角色 | 95 | 91 |

**重要限制：** 对战保留自然死亡，因此这不是全程固定 100 名存活者的稳态基准；改动前后墙钟采样窗口中的模拟进度与存活人数也不完全一致。上述数据只表明短时场景有所改善，不能推导“所有百角色组合”“稳定 60 FPS”或整局行为完全等价。最初包含测试入口初始化错误的 baseline 结果已剔除，不用于对比。Vulkan 诊断测试约 4.12 FPS，未见解决瓶颈，故未切换项目后端。

## 已修改的生产代码

1. `res://scripts/world.gd`
   - 战斗运行闸门原来为每个角色和飞刀完整统计全场存活主角色，但调用方只比较 `>= 1`。
   - 新增即时存在性查询，命中首个合格角色即可返回。保留原判定条件，不做跨帧存活缓存，完整计数接口仍然保留。
2. `res://global/game.gd`
   - 固定运行时翻译文案表改为常量，避免每次翻译重建字典和数组。
   - 单次同步 UI 扫描共享重复文本翻译结果，并区分 UI／引擎语言。每次正式扫描重新创建缓存，不做跨帧文本缓存。
3. `res://classes/ball.gd` 与新增 `res://classes/visual_pixel_sampler.gd`
   - 在一次同步采样批次中预取纹理帧、裁剪区域、翻转和颜色链，避免每个像素重新查询节点和纹理。
   - 保持 44 次随机尝试、随机数消费次序、Alpha 阈值、坐标和颜色运算不变。
   - 对没有脚本、子节点、元数据、分组、场景根路径及持久信号连接的纯 Sprite2D 残影，复制全部原生存储属性，省去随后必定被覆盖的源材质和源 Shader 参数复制。其他对象仍走原 `duplicate()`。
4. `res://global/audios.gd`
   - 非音频节点不再排队执行必然无效的音频路由回调。
   - 真正音频节点保持原延迟路由时机，改用实例 ID 防止对象提前释放导致悬空参数。

没有降低物理频率，没有减少飞刀／残影／受击线条数量，没有修改攻击冷却、伤害、生命或碰撞规则。项目原有 40 单位大规模模式、软分离、视觉降频和模糊层策略未在本轮改动。

## 已完成验证

- 战斗存在性与原完整计数：208 项测试，0 个断言失败。包含空场、死亡、召唤、比赛延续、地图外来客、排队删除和随机组合；不是全角色技能回归。
- 像素采样：3200 项与保留的原方法逐项比较，0 处不一致。
- 受击采样结果与随机数状态：160 项一致。
- 残影原生存储属性：468 项一致。
- 同帧双 SubViewport 渲染的静态残影像素数据完全一致。覆盖的是测试用纹理与参数，不代表所有动态特效的全量图像回归。
- 实际对战及最终验证日志保留，未发现其中有 SCRIPT ERROR／ERROR。
- 编辑器诊断为空，但其 LSP 对 GDScript 返回 plaintext／语义结果不确定，因此没有把“空诊断”当作充分证明。

## 瓶颈与下一步

GPU 诊断中绘制约 2 ms；主要压力在 CPU。原生脚本采样显示高频场景实例化、残影创建、受击采样及 UI 翻译是热点。本轮只处理可做局部等效证明的重复工作。

下一阶段需要继续处理飞刀及残影的创建／释放开销，尤其是同一物理帧集中出手的峰值。对象池和批量绘制不能直接粗暴替换：必须保留碰撞事件、命中去重、节点实例身份依赖、透明排序、暂停／倍速和重置／清场行为。没有通过禁用效果或改变战斗来伪造达标。

## 留存文件与复现

- `scripts/training/benchmark_before.json`、`benchmark_after.json`：对比原始指标。
- `scripts/training/benchmark_before_engine.log`、`benchmark_after_engine.log`：实际运行日志。
- `scripts/training/benchmark_native_profile.json`：原生脚本 profiler 采样，供后续继续定位。
- `scripts/training/benchmark_gpu_engine.log`：GPU 诊断。
- `scripts/training/benchmark_visual_equivalence.json`、`benchmark_visual_engine.log`：视觉验证结果。
- `scripts/training/benchmark_contracts_final_engine.log`：存在性验证结果。

以下入口只在显式运行时生效，不挂载到正常游戏场景：

```powershell
$godot = "E:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
& $godot --path . --resolution 540x960 --log-file scripts/training/benchmark_verify_engine.log --script res://scripts/training/benchmark_100.gd -- --label=verify
& $godot --headless --path . --script res://scripts/training/test_performance_contracts.gd --quit-after 5
& $godot --path . --script res://scripts/training/test_visual_equivalence.gd --quit-after 10
```

测试会启动独立进程，正常结束时恢复测试进程内保存的 Game 设置再退出；请勿同时在另一个游戏进程修改并保存设置。压力测试主动开启血液、关闭友伤等临时设置已在正常结束时恢复。临时 profiler 场景和抓取脚本已移除。
