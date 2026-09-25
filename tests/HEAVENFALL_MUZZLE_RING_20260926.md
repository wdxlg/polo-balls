# 天堂陨落长弓：可复用发射像素圆环（2026-09-26）

## 行为与范围

- “扩大冰渐隐”按“扩大并渐隐”实现，**没有修改冰径**。
- 在 `_fire()` 成功创建箭矢后，直接取 `bolt.global_position`，每箭一圈；不是瞄准点、当前图片偏移或远端插值后的身体位置。
- 深青绿 `#14534f`、浅青 `#83dbd6`、银白 `#c8c8c8`，取自现有长弓/裂隙到达圈配色。空心三层像素圆环，起始半径8、目标24、持续0.38秒。沿用现有重锤缓出扩张 `1-(1-p)^3.1` 和透明度 `(1-p)^1.28`，不另写像素算法。
- 世界锚定：不会随射手移动、后坐、旋转、缩放而漂移/变形。绝对Z=2；没有填充盘、射线、地面碎块、采样等待、新声音、命中框或AI威胁。
- 新公共入口 `mc_combat_abilities.gd::expanding_ring(parent,point,radius,options)` 使用原 `重锤落地冲击.gd` 节点。参数 `palette/end_scale/lifetime/z_index/name`；半径保留底层最小值8，end_scale最小1、lifetime最小0.02。
- 底层新增 `show_block_particles`、公开 `ring_palette` 和可选 `pause_with_battle`。旧调用默认碎块/射线、暂停行为不变；空公开色板仍保留工作树原有子类私有色板。纯圆环跳过地表读回及随机种子，不改变战斗随机序列；初始化清理时长不再依赖碎块生成器。
- 单机直接播一次；联网由权威端直接播一次并通过 `authority/call_remote/reliable` 发送真实发射坐标。`accept_visual()`仍只处理已有后坐，避免重复/补播历史圆环。非权威端不能调用 `_fire()` 发箭。
- 没有改射速、蓄力、手控按键、箭伤害/穿墙/追踪/箭雨、瞬移到达伤害和后坐曲线；没有将带伤害的 `heavenfall_ring.gd` 当纯视觉使用。

## 复用示例

```gdscript
const FX = preload("res://scripts/effects/我的世界/mc_combat_abilities.gd")
FX.expanding_ring(world, launch_point, 8.0, {
    "palette": [Color("14534f"), Color("83dbd6"), Color("c8c8c8")],
    "end_scale": 3.0, "lifetime": 0.38
})
```

角色负责RPC；此公共入口不发RPC，不负责伤害。挂入 `BattleTransient`；父节点删除或到时自清理。若需射手死亡后继续播完，父节点使用世界，而不是射手。

## 实际验证

引擎 `E:/godot/polo-balls-tools/offline-engine/runtime/Godot.4.7.2.offline.exe`。GPU：OpenGL Compatibility，NVIDIA RTX 4060 Laptop。命令：

```text
<engine> --path . --script res://tests/test_heavenfall_muzzle_ring.gd --rendering-method gl_compatibility --audio-driver Dummy
<engine> --headless --path . --script res://tests/test_heavenfall_muzzle_network.gd
```

最终6套均退出0，合计 **230项 / 0失败**：

| 测试 | 结果 | 边界 |
| --- | --- | --- |
| `test_heavenfall_muzzle_ring.gd` | 33/33 | 真实场景手控蓄力/取消/射击、AI同入口、坐标、后坐不带走圆环、权限、无伤害、参数/生命周期、两种暂停、缩放父节点、真实GPU像素 |
| `test_heavenfall_muzzle_network.gd` | 16/16 | **一个引擎进程内**两套独立 SceneMultiplayer + loopback ENet，真实Spawner复制长弓与RPC；每端一圈、相同权威坐标/颜色、状态回放不重播、暂停/清理/权威销毁 |
| `test_heavenfall_contacts.gd` | 22/22 | 箭矢人物/地形接触、直接箭伤害不击退、裂隙方向 |
| `test_heavenfall_transit.gd` | 53/53 | 瞬移及到达冲击回归 |
| `test_heavenfall_arrow_pierce.gd` | 71/71 | 穿墙/落箭及地面效果、后坐、GPU裂隙 |
| `test_sulfur_cube_polish.gd` | 35/35 | 共享像素环/TNT预警与硫方怪回归，GPU原版晶簇485可见像素、0不同 |

日志：`tests/<测试名>_muzzle_final.log`（运行证据，不要求提交日志）。

GPU圆环4帧：0、0.19、0.34、0.38秒，峰值alpha依次约0.988、0.533、0.086、0。可见像素360、1080、540、0；初帧外缘半径约12.02、中帧27.06（包含笔画宽度，不是逻辑半径），中心始终透明。像素网格量化且低alpha外围先不可见，晚帧可见外缘26.95不代表逻辑半径倒退；比较允许一个3px网格误差。读取并查看了中帧截图。截图输出 `user://heavenfall_muzzle_*.png`。

首次新夹具因在SceneTree命令脚本顶层提前preload依赖Game的脚本而未启动，已改为autoload就绪后load；第二次夹具将淡出后的可见外缘误当严格连续半径，已按像素网格调整断言。最终上述230项为修正夹具后的实际重跑结果，不计早期失败为通过。

**未验证**：两台机器/两个独立游戏进程的人工联机、弱网重连/延迟表现、大规模射击压力、实时/双语编码录制。没有以节点测试替代这些验收。旧长弓夹具退出仍报告约186–190个ObjectDB实例泄漏；项目原有shader UID/文件名大小写警告仍在；新圆环/GPU和ENet夹具最终无脚本错误。

## 版本与回退

开始前HEAD：`0ebb11fb48cec6accb618684ebd3d06424bc02f3`。独立备份：
`E:/godot/polo-balls-tools/checkpoints/heavenfall-muzzle-ring-20260926-051232`。

长弓、公共能力、重锤效果和MCP说明已有未提交改动。保存版本时发现并发的唤魔者提交 `cd54eb1` 已把本次 `expanding_ring` 公共入口一并收录，故保留该提交、不改写历史；本次提交在其后仅补全圆环参数、长弓接入、测试和说明。提交快照针对HEAD中的默认白圈接入公开palette，工作树仍保留此前私有palette子类逻辑。完整功能跨此前已收录的入口与本次补交，因此单独 git revert 本次提交不是完整功能回退；使用下述按本次完整工作树增量生成的补丁。

专用补丁 `tests/patches/heavenfall_muzzle_ring_20260926.patch` 记录**本次工作树增量**。先关闭运行中的游戏，确认无后续同范围编辑，再检查：

```text
git apply --reverse --check tests/patches/heavenfall_muzzle_ring_20260926.patch
```

检查通过后才可手动去掉 `--check` 执行；本次仅做反向检查，不实际回退。补丁删除本次新增测试/报告、恢复本次代码/文档差异，保留既有未提交工作；补丁文件自身留作记录。不要使用 `git reset --hard` 或整文件覆盖回退。提交前后ID写在上述checkpoint的 `commit_result.json`，并在交付回复提供。
