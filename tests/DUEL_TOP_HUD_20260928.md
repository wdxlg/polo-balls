# 1v1 顶部对战 HUD — 2026-09-28

## 用户要求与确认

- 屏幕上方新增 UI，**仅在场上正好剩两名主角色且分属两方时**显示：开局 1v1，或多方混战打到只剩两人都会出现；召唤物不算角色，比赛延续/死亡演出桥沿用 `return_battle_sides()` 的代表规则（同名延续单位合并为一名、生命合并）。同队两人或三方以上不显示。
- 背景使用项目已有的 Minecraft Java 1.21.4 原版 GUI 素材（未修改 PNG，来源见各目录 `SOURCE.json`）：
  - 左右角色框：`minecraft_tooltips/tooltip_background.png` + `tooltip_frame.png`，九宫格 9/10，GUI 像素倍率 3（与 `mc_effect_tooltip.gd` 一致）。
  - 头像槽：`rotation_frames/item_frame.png` ×4；头像复用 `scripts/ui/rotation_portraits.gd`（原版正脸或角色真实场景图）。
  - 血条：`minecraft_xp/experience_bar_background.png` / `experience_bar_progress.png` ×2（364×10），左侧自左填充、右侧镜像自右填充。
  - 中间对战框：`minecraft_tooltips/effect_background_large.png`，九宫格 5。
- 角色框内容（用户选择）：头像 + 名字 + 当前/最大生命数字 + 血条。名字颜色与普通 VS 同源（`_versus_side_color`：两队蓝/红，中立/无队白）。
- 中间：本局已过去的时间（`mm:ss`，超过 1 小时 `h:mm:ss`，原版黄色）+ 白色 `VS`。
- 原来的“角色名 VS 角色名”文字标题**保留**（用户选择），新 HUD 放在其上方：逻辑视口 y=32–208，VS 标题从 y=240 开始，不重叠。
- 计时按**游戏时间**（用户选择）：只在 `is_combat_runtime_active()` 时累加物理 delta，暂停/时间停止不走、倍速同步；胜利铃响后冻结；`_victory_bell_sequence_generation`（重置/重打/新一局）或开战序号变化时归零。计时从开战就开始，与 HUD 是否显示无关。**录像中也显示**。
- 决出胜负后保留最后一对的结果画面（败者头像/文字变灰、0 血），直到重置或出现新对阵；再加入第三方则隐藏。
- 与普通 VS 同步隐藏：布阵、盔甲架介绍、Boss 车轮战、死亡存档覆盖时不显示。

## 实现

- 新文件 `scripts/ui/duel_top_hud.gd`：挂在 World 的 `VersusScreenLayer`（屏幕画布，不随镜头移动/缩放/震动），以 1080 逻辑宽度设计并按视口宽度等比缩放。贴图层使用最近邻过滤，文字在独立子画布保持字体过滤；Mojangles 字体 + 黑描边。
- `scripts/world.gd`：新增 `DUEL_TOP_HUD_SCRIPT` 常量、`duel_top_hud` 变量，并在 `setup_map_presentation()` 创建 HUD（共 7 行）。
- `scripts/ui/battle_record_locale.gd`：为每个录制抓帧视口的 `RecordingVersus_<locale>` 屏幕层添加 `make_mirror(locale, 语言可见层)` 只读镜像；镜像不计时、不扫描，只读取本体数据并用 `_t_for_locale` 翻译角色名。先判 `is_instance_valid` 再判类型，避免 World 拆除时对已释放对象报错。
- 纯本机 UI：无伤害、无 RPC；多人客户端按本地同步到的生命与战斗状态显示。

## 验证（Godot 4.7.2 离线引擎，真实 GPU 窗口）

| 测试 | 结果 |
| --- | --- |
| 新增 `tests/test_duel_top_hud.gd` | **30/30**，退出 0 |
| `tests/test_vs_screen_title.gd` | 27/27 |
| `tests/test_vs_map_scaling.gd`、`tests/test_vs_team_counts.gd` | 退出 0 |
| `tests/test_rotation_frames_challenge.gd` | 97/97 |
| `tests/test_armor_intro_readability.gd` | 48/48 |
| `tests/test_vs_title_motion.gd` | 24/27：3 项“像素完全不变”失败，**与 `tests/ROTATION_VS_WINNER_20260927.md` 记录的既有失败相同** |

- 专项覆盖：单人/同队/三方隐藏、1v1 显示、左右顺序与蓝红色、两侧头像取得、真实生命与扣血、HUD 底边高于 VS 标题、计时累加/时间停止冻结/胜利冻结/重置归零、决出胜负后保留结果、中英录制镜像可见且使用各自语言层、中英录像右侧名字实际像素不同、GPU 顶部区域出现 HUD 且左框为原版深色 tooltip 背景。
- motion 对照：用临时副本停用并隐藏新 HUD 后仍是同样 3 项失败（live_max=2145）；带 HUD 原测试两次复跑 live_max=2303 / 2145，属于同一波动范围，失败不是本次引入。临时副本已删除。
- 人工查看 GPU 截图：玩家画面（540×960）、中文/英文录像（1080×1920）均显示左右 tooltip 框、物品展示框头像、名字、生命数字、经验条血条及中间黄色计时 + VS；英文录像为 Creeper / Skeleton。预览：`tests/duel_top_hud_preview_zh_20260928.png`。
- 未验证：真实录制按钮完整成片（MP4）、FOLLOW/FOLLOW_OVERVIEW 录像构图、真实双客户端联机、所有角色头像逐一检查。

## Git 与局部回退

- 修改前 HEAD：`bccd680949f7e742a92fca3782ce48c0e06e2577`。`world.gd`、`battle_record_locale.gd`、`battle_recorder.gd`、`MCP_CONTEXT.md` 修改前工作副本及既有脏差异备份在 `.git/agent-checkpoints/duel_top_hud_20260928/`。
- 本次提交只含：新 HUD 脚本、专项测试、本说明、预览图，以及 `world.gd` / `battle_record_locale.gd` / `MCP_CONTEXT.md` 中本任务的差异块；这些文件里其他任务的未提交改动不在本提交内。
- 回退：先备份当前工作区，再 `git revert <本次提交>`，或 `git show <本次提交> | git apply -R --check` 后人工合并；不要用 `reset --hard` / `clean`。
- 首次提交：`710633d`。

## 纠正（2026-09-28）：“时间完全不动” → 被顶部工具栏遮挡

- 原因：计时本身一直在走（诊断：普通模式、`create_char` 真实放置两人，7.5 秒 elapsed=7.52）；但真实游玩时 `World/CanvasLayer/Control/Settings` 顶部工具栏（游戏设置/队伍/重置…，底边约逻辑 y=81）盖在 HUD 上，中间计时数字和两侧名字只露出底边，看起来完全不动。原专项测试隐藏了工具栏，所以没发现。
- 修正：本体每帧检测工具栏是否可见；可见时整组 HUD 排到工具栏下方 8、原文字 VS 标题上方 6，等比缩小（540×960 实测 0.817）并水平居中；工具栏隐藏时恢复原布局。录制画面没有工具栏，中英镜像只跟随基础倍率，保持原全尺寸布局。
- 验证：`test_duel_top_hud` 39/39（新增：工具栏可见时缩小、面板顶 ≥ 工具栏底、面板底 ≤ VS 标题、居中、计时文字 70 物理帧内前进、镜像保持原布局、隐藏工具栏恢复）；`test_vs_screen_title` 27/27；`test_armor_intro_readability` 48/48。GPU 截图 `user://duel_top_hud/main_duel_toolbar.png` 人工确认工具栏下方完整显示 00:02 / VS / 名字 / 生命。

## 新增（2026-09-28）：10 颗红心 / 护盾 / 伤害吸收 / 盔甲值

- 用户要求：血量换成 10 颗原版红心；盔甲值 = 伤害减免（抗性提升、铁匠村民等都算），只在有时显示；护盾把红心染成盔甲颜色；伤害吸收把红心染成金色；都按实际数值占比。方向：左侧面板红心从右往左掉，盔甲值与护盾从左（低血量端）往右增加，伤害吸收反过来从右往左；右侧面板整体镜像。
- 用户确认：护盾从低血量端开始；红心/护盾/吸收都按**最大生命值**换算（10 颗心 = 最大生命，超出截断）；10 个盔甲图标 = 100% 减伤（每半个 5%）；保留“当前/最大”生命数字。
- 数据来源（均为实时值，不另存）：生命 `health`/`Max_health`；护盾 `block`；吸收 = 原版伤害吸收效果节点 `MinecraftStatus_absorption.absorption_remaining`（与 `ball._consume_minecraft_absorption` 同源）；盔甲值 = `Damage_reduction`（buff 系统已把抗性提升每级 +20%、铁匠头盔、各类减伤 buff 汇总进去），负值（易伤）不显示。延续单位合并时生命/护盾/吸收相加，减伤取最高。
- 换算：半心为单位，正值至少半颗（与原版一致）；盔甲四舍五入到 5%，正值至少半个。叠放顺序：空心槽 → 红心 → 护盾色心 → 金心。
- 素材：官方 1.21.4 客户端 JAR（SHA-1 校验一致）原样取出 `heart/full|half|container|absorbing_full|absorbing_half`、`armor_full|half|empty`，放在 `Images/UI/minecraft_hud/`（来源见同目录 `SOURCE.json`）。护盾心不新画：运行时把原版红心三色（ff1313/ffc8c8/bb1313）逐像素换成原版 armor_full 三色（b8b9c4/e6e7f2/696a70）。右侧面板的半心/半盔甲水平翻转。
- 布局：头像 96（物品框 ×3，与 tooltip 同为 GUI 像素 ×3）；右侧文字列依次为名字、红心行、盔甲行（9×9 精灵间距 8、×3，一行宽 243）；生命数字移到头像下方整行。原经验条血条移除。
- 验证：`test_duel_top_hud` 52/52（新增：半心/盔甲换算、护盾/吸收/减伤实时读数、真实 `apply_effect(absorption)`、GPU 按原版源像素取色确认左侧护盾色心在低端、红心、金心在高端且半颗金心只占高端半边、4 个满盔甲后为空盔甲、右侧镜像红心靠头像、无减伤不画盔甲行）；`test_vs_screen_title` 27/27；`test_armor_intro_readability` 48/48；`test_rotation_frames_challenge` 97/0。截图对比时注意：视口读回为线性色值，且全屏暗角把边缘压暗约 0.8 倍。预览：`tests/duel_top_hud_hearts_zh_20260928.png`。
- 未验证：所有角色逐一核对减伤数值来源；超大最大生命（心很少）时的可读性仅靠换算保证。

## 纠正（2026-09-28）：红心按实际百分比连续填充

- 用户纠正：心的减少不应最少减半，而要按实际血量换算百分比。现红心、护盾色心、金色吸收心都按 `数值 / 最大生命 × 10` 连续换算，每颗心按占比裁切原版整心精灵（比例映射到心形实心的第 1–7 列，0.5 恰为一半）：37/420 = 0.88 颗心，1 HP 只是一条细缝，不再取整、也不再强制至少半颗。低血量端/高血量端方向与镜像不变；不再使用半心精灵（素材文件保留）。盔甲图标仍按用户选定的每半个 5%。
- 验证：`test_duel_top_hud` 55/55（新增：37/420 精确 0.881、连续换算、吸收从高端按比例、2.33 颗金心时第 7 颗只远端 1/3 为金、右侧 0.88 颗心远端边缘为空槽）；放大录像截图人工确认部分心形。
