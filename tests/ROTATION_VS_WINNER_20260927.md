# 轮换 VS 与 1v1 胜者头像 — 2026-09-27

## 用户要求与实现

- VS 指与其他模式一致的“XX VS XX”文字，而非头像之间孤立的 VS。
- 轮换（1v1、车轮、挑战）不再被队列模式分支隐藏普通 `versus_label`；直接复用 `build_versus_text`、翻译、阵营颜色、加粗黑描边、屏幕锚定及录制源。当前场上角色换人时沿用普通标题更新机制；无有效参战角色时沿用普通模式的隐藏行为。
- Boss 车轮战继续使用旧名字名单/VS；轮换旧名字名单和孤立 VS 保持隐藏。养成预备、死亡存档覆盖和盔甲架介绍的提前返回不变。
- 1v1 清场前仅真实存活者记录 `won`。头像行已有原版 `check.png` 绿色对勾渲染，与败者 `cross.png` 一样居中叠在头像上，无需重复素材/新网络消息。
- `_rotation_mark_current_dead` 新增可选 winner 参数，默认仍保持非死亡退场 `retired` 的原语义。已归零但未完成移除的对手记为 dead，避免双败被误标获胜。换人、清场、挑战/车轮规则不改。

## 验证

Godot 4.7.2；测试脚本在 Game autoload 初始化后加载场景。

| 项目 | 本轮结果 |
| --- | --- |
| `tests/test_rotation_frames_challenge.gd` headless | 97/97，退出0，SCRIPT ERROR 0 |
| 同脚本 `--visual`，OpenGL / RTX 4060 Laptop | 97/97，退出0，SCRIPT ERROR 0 |
| `tests/test_vs_screen_title.gd` | 27/27，退出0 |
| `tests/test_armor_intro_readability.gd` | 48/48，退出0 |

轮换用例覆盖蓝胜/红胜、双阵亡、归零待移除、下一局不跳号、挑战/车轮/1v1标题、实际头像行收到 won、素材存在、规则切换/重开/重置、头像滚动与 Boss 单一 VS。普通标题和盔甲架回归共75项；轮换97项，共172项不同断言。GPU轮换是相同97项的另一次运行，不重复计入。

## GPU观察与边界（不可写成全部回归通过）

- `tests/rotation_vs_winner_preview_20260927.png`：GPU HUD测试截图，使用真实人物和头像素材、预设的历史胜负序列；为方便检查头像/标题，**仅测试截图隐藏前景云**，游戏中的云设置和云实现未改。人工检查可见“钻石剑 VS 重锤”、上下两排胜者对勾/败者叉号，标题与上排头像不重叠。
- `tests/test_vs_title_motion.gd` 依赖 frame_post_draw，不能按 headless 结果判定。误用 headless 时按其50秒看门狗退出2；随后用真实GPU运行。
- 原版 motion GPU测试24/27通过，三项“主画面/中文录制/英文录制像素完全不变”失败，控制原点最大漂移为0.0。用临时派生 World 恢复**本轮前的 refresh_versus_text 分支**后，相同三项仍失败；没有覆盖工作区源码或回退他人改动。额外临时隐藏云的测试副本仍有这三项失败，因此不把失败武断归因于云。未修改该测试、云层、录制器或既有屏幕锚定来掩盖问题。
- 一次GPU轮换复跑到截图阶段未完成，在75秒由自有进程看门狗终止；最终 headless/GPU轮换均重新完整通过97项并取得截图，不能将那次超时算通过。
- 场景现有 shader UID/大小写警告仍在；本轮未修。未做真实双客户端联机或穷举地图/语言/分辨率。

## 局部回退

- 修改前完整工作文件备份：`%TEMP%/arena_rotation_ui_before_20260927.zip`。
- 局部恢复分支：`checkpoints/rotation-ui-20260927-before`、`checkpoints/rotation-ui-20260927-after`。
- 仅 world.gd、轮换测试、本说明和 MCP_CONTEXT.md 的本次差异进入局部版本；真实主分支 HEAD 与暂存区保持不动，保留已有脏文件/并发工作。这不是整个脏项目的完整快照，禁止直接 checkout 该树覆盖全项目。
- `%TEMP%/arena_rotation_ui_changes.patch` 和 `%TEMP%/arena_rotation_ui_recovery_20260927.zip` 在局部提交成功后生成。回退前先备份当时工作区，并执行 `git apply --reverse --check`；有冲突时人工合并，不用 reset/restore 扫掉他人工作。
