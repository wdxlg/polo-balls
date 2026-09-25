# 铁匠村民：横扫起手音效与挥剑动作（2026-09-25）

## 本次规则

- 出剑时读取**本次实际攻击输出** `attack_damage(1.0)`：**严格大于 100** 时，挥舞音效切换为项目中已有的七条 Minecraft 原版 `audio/sfx/我的世界/近战/横扫/横扫01～07.ogg`；恰好 100 或更低仍播放原有重击。锻造的永久伤害成长及实时攻击增益均参与判定；不把目标护甲后的实际承伤误用作出剑瞬间的音效阈值，也不因装备名固定音效。仅权威攻击端广播起手音，各端沿用现有本地/RPC 音量及声道入口，不新增音频文件。
- **命中反馈与出剑音效是两件事**：成功造成的实际承伤依旧按原规则 `>=100` 播暴击命中音，否则播普通 MC 受击音；免疫或 0 伤害不伪造命中反馈。此次只调整挥舞选声，未更动它的音量随伤害增长机制、受击倍率、攻击范围/扇角、冷却、阵营筛选或权威伤害结算。
- 旧动作的主斩只有约 0.18 秒，缓出四次曲线在第一帧容易突跳。现在标准挥剑时长由 `0.36→0.46` 秒，命中由 `0.17→0.22` 秒使碰撞发生在剑锋掠过正前方时；蓄力、主斩、收势均使用两端减速的连续插值。大于 200 伤害的原 `1.15×` 略快挥剑仍保留且命中与表现同比例提速，1.0 秒原攻击冷却不变。
- 场景的可视默认值与脚本同步：剑的逻辑缩放 `0.07→0.14`（实际角色还有 `0.2×` 根节点缩放）、握把出剑距离 `31→35`；保留原版剑贴图与握把枢轴。暗色下界合金剑仅在挥舞时略微提亮；残影复用剑贴图，数量 `6→10`、寿命 `0.13→0.18` 秒、透明度 `0.34→0.58`。跳帧时按剑弧中间各个姿态补采样，而不是十张图叠在同一个最新位置；受晕/取消仍立即藏起当前武器。没有自制剑图或额外伤害范围。

## 验证与边界

在 Steam Godot 4.7.2、当前工作区运行：

```powershell
& 'E:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path . --script res://tests/test_blacksmith_sword_sweep.gd
& 'E:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --path . --rendering-driver d3d12 --resolution 680x480 --script res://tests/test_blacksmith_sword_sweep.gd
& 'E:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path . --script res://tests/test_manual_control_roster_extensions.gd
```

- 实例化**真实铁匠场景**的无头测试：**28 项／0 失败**。包括音效阈值 `20 / 99.9 / 100 / 100.001 / 210` 与永久伤害 +1 后的实际 `attack_damage`、原版素材路径和音量公式；保留命中暴击门槛。对真实 Tween 每 1/60 秒步进，挥剑每帧最大旋转 **16.42°**、持续至少 23 帧、命中时刀锋在前方；十条残影有十个不同的角度，反向和打断也通过。
- **真实 D3D12/Forward+ GPU**：同一夹具 **36 项／0 失败**，使用真实角色和 2.2 倍相机，最近一次蓄势/交锋/收势三幅像素对照分别有 **201 / 543 / 387** 个变化采样像素（取样帧时刻略有波动），且相邻两帧剑姿不同；截图在 `user://blacksmith_sword_revision/swing_windup.png`、`swing_contact.png`、`swing_follow.png`，非提交素材。原有全阵容手控绑定回归 `test_manual_control_roster_extensions.gd` **67 项／0 失败**。
- 验证了单机实际声音播放器所载资源与 GPU 画面；没有把静态配置检查当成听感/动画验收，**未做双客户端同步、真实长局音量主观试听或全部地图光照穷举**。项目已有 `scenes/ball.tscn` 的 UID 路径回退警告，测试没有新增脚本解析错误。

更新前 HEAD：`2cd24f40d527760f021ed58b350dcb2801c997cf`。改动前原文件、运行日志备份于 `E:/godot/polo-balls-checkpoints/blacksmith_swing_20260925/`。本轮只提交铁匠脚本/场景、本专项测试、本文及索引中的本任务文字；同时并行进行的其他工作区改动不属于可回退的本轮提交。更新后提交 ID 以 Git 提交结果为准。
