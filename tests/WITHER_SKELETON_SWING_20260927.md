# 凋灵骷髅挥刀与移动纠正（2026-09-27）

## 用户要求与实现

- **动作先抬手、向下挥刀、再向上挑，幅度明显放大**。原版模型/贴图不变，使用既有 Baker/BatchBaker 将原模型右肩在 -18°→-160°→-10°→0°→-160°→-170°→-18°间缓动；50帧覆盖整个0.98秒，不再重复16帧小幅下砍。剑第一刀 -110°→80°、第二刀90°→-110°，左侧镜像；握把取当前身体帧的真实投影手锚，不再额外向前推离手臂。此为项目适配骨骼动作，不声称原版攻击动画原样播放。
- **正常移动，不追敌**：移除 `step_mob` 中指向最近敌人的 `direction` 写入；索敌仅决定起手时的 `combo_heading`。沿公共 `ball.move/when_collide` 移动/碰撞反弹，不锁死或缓存覆盖方向。
- **攻击减速**：AI/手控统一自驱速度×0.3，包含0.74–0.98秒收招；完成/取消即恢复。公共击退、牵引、地表速度不缩放，WASD不被鼠标瞄准取代。
- 保留420HP、24每刀、88基础速度、1.2秒起手间隔、两个原伤害窗口、每刀每敌一次、凋零叠级和来源寿命、暂停/禁攻/死亡规则、体型和碰撞。可视剑段与真实伤害/威胁继续共用 `blade_segment/weapon_tip_sweep`；未另建伤害或移动算法。

## 本轮实际执行

| 检查 | 结果 |
| --- | --- |
| Godot headless editor 导入 | exit 0，无脚本/解析错误 |
| `test_wither_skeleton.gd` headless | **77/77，0失败** |
| 同一夹具真实 GPU / gl_compatibility | **78/78，0失败** |
| `test_all_character_manual_control.gd` | **31/31，0失败** |
| `test_manual_control_roster_extensions.gd` | **67/67，0失败** |
| `preview_wither_skeleton.gd` GPU五阶段 | exit 0，四姿态相对待机差异1270/931/1281/1279像素 |
| 原版来源哈希 | SOURCE.json各原始文件SHA256全部匹配 |
| idle/walk图片对修改前备份比较 | 全部不变 |
| VS Code诊断：角色脚本目录 | 0条；LSP导航为空且provider不确定，因此以引擎运行结果为准 |

新增覆盖：索敌前后/冷却期移动不追踪；朝右挥剑仍向左移动；攻击减速、自然收招恢复；真实WASD速度与外部击退分量；真实StaticBody2D碰撞触发反弹且下一次索敌不覆盖；左右两侧手部上下行程>10世界单位、剑尖上下行程>25单位；七个关键时点可见握把与伤害握把一致；完整身体收招帧。原两刀伤害/凋零/阻墙/友伤/权限/暂停和音效事件回归仍运行。

GPU图片：`tests/wither_skeleton_swing_preview_0..4.png`（待机/抬手/下劈/上挑/收招），已读取实际截图核对姿态和握持。专项GPU夹具另输出 `tests/wither_skeleton_swing_gpu_*.png`。本轮日志独立留在 `.backups/wither_skeleton_swing_20260927/`。

## 未通过与未验证边界

- 全项目 `verify_combat_classification_registry.py` **exit 1**：278场景/611脚本，缺项为本次范围外 `res://classes/sprite_snapshot_trail.gd`，其他missing/stale/invalid状态项为空。本次未创建或改动该脚本及公共注册表，不覆盖其他任务来消除这项失败；不能宣称全项目登记通过。
- 导入/运行仍报告 `scenes/ball.tscn` 中 `Set_RGB_Color.gdshader` 路径大小写及旧UID回退警告；这些文件未在本轮修改。
- GPU为OpenGL兼容模式，不代表D3D12、录制输出或双客户端联机已通过。未做真实多人联机/晚加入实战。
- 音频使用Dummy驱动；验证原事件计数/生命周期，不声称PCM听验通过。用户实际对局手感仍需最终确认。

## 局部恢复与范围

- 修改前HEAD：`1584017efbfd1090b7bcc955e38afb936123a8a0`，分支main。
- 修改前独立文件备份/哈希清单：`.backups/wither_skeleton_swing_20260927/manifest.json`，共108文件，包含当时已有未提交修改的 `MCP_CONTEXT.md`。
- 本次提交仅收录角色脚本、原模型攻击投影50帧/帧资源/手锚/来源说明、烘焙工具、两份夹具、长期说明、本报告及MCP_CONTEXT新增纠正条目。没有提交其他角色、公共ball、公共注册表或他人的既有未提交改动；截图/日志为本机验证产物。
- 更新后提交ID由交付消息报告，亦可用 `git log --oneline --grep="wither skeleton: broad down-up swing and non-tracking movement"` 查找。
- 回退前先检查并备份当前工作区；优先 `git revert <本次提交ID>`，发生共享说明冲突时仅撤销本轮新增条目。或按该提交文件清单逐文件恢复，不运行 `reset --hard` / `clean -fd`。新增34帧及相应import配置也在本次提交中，可随指定提交撤销。
- 工作区存在大量其他未提交内容，本次提交是局部更新，不是整个项目的完整快照；未推送远程。
