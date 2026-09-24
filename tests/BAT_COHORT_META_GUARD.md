# 大规模战斗软分离的蝙蝠批次元数据报错（2026-09-24）

## 原因与修复

- 编辑器截图反复指向 `scripts/world.gd` 的 `_update_large_battle_crowd_separation()`：大规模模式启用后（默认达到 40 个角色，降至 30 个以下才退出），空间网格约 30Hz 遍历邻近角色对。绝大多数普通角色根本没有 `mc_bat_cohort` 元数据。
- 原代码对每对角色调用 `get_meta("mc_bat_cohort", null)`，误以为 `null` 是安全默认值。本机 Godot 4.7.2 遇到不存在的键**仍会打印 `The object does not have any 'meta' values...`**；代码继续返回 `null`，所以玩法断言可能全部通过，调试器却按角色对和刷新频率刷屏。
- 现在只有**双方都 `has_meta(&"mc_bat_cohort")`**时才读取并比较批次编号；相同批次的蝙蝠继续不进行软分离，缺少编号或编号不同的角色正常分离。没有修改伤害、身体碰撞、地图、录制或蝙蝠生成规则；不是关闭 Godot 报错输出。

## 复现及回归

- 新增 `tests/test_bat_cohort_separation_guard.gd`：真实 World/ball 空间网格，先降低**仅测试实例**的大规模阈值到 2，覆盖无编号普通角色、只有一方有编号、相同/不同批次、移除编号后恢复分离、重复调用热路径及速度清零；再恢复默认阈值，以 **40 个真实角色**复现大规模模式及多人网格遍历。最终 **14/14**。
- 修复前的两人阶段，玩法断言 **11/11** 仍全部通过，但 stderr 中有 **15 条**缺失 `mc_bat_cohort` 元数据错误；修复后扩展到 40 人时 **14/14**，目标错误 **0 条**，其他引擎错误也是 **0 条**。因 Godot 仅记录缺失元数据而不令脚本失败，`tests/verify_bat_cohort_separation.py` 同时检查 GDScript 结果、退出码和引擎 stderr，避免测试“假绿”。运行：工程根目录 `python tests/verify_bat_cohort_separation.py`；换引擎可传 `--godot <路径>` 或设置 `GODOT_BIN`。
- 真蝙蝠与其他批次的 GPU 回归 `tests/test_mc_bat_shield_collision.gd` **66/66**（其中实际检查同批次不软分离、不同批次仍分离）；当前数值回归 `tests/test_mc_bat_stats50.gd` **10/10**，两次均无目标元数据错误及其他引擎错误。
- 更早的 `tests/test_mc_bat.gd`、`tests/test_mc_bat_revision.gd` 中生命/伤害旧数值断言与当前蝙蝠配置不符（后者 **22/29**），本轮没有修改它们；这两项只生成少量蝙蝠，默认未进入大规模软分离，不可把它们的既有失败归因于元数据保护。现有 shader UID、文件名大小写警告及部分测试退出的 ObjectDB 警告也非本次改动。

## 回退范围

修改前 HEAD：`cad6b94fa15c710ec5e6396216a14b51ead9adfa`。已有未提交的 `scripts/world.gd` 和 `MCP_CONTEXT.md` 工作副本备份于 `%TEMP%/polo_bat_meta_before_20260924_135737/`。本次 Git 只收录安全元数据判断、两个新测试入口、本文和索引；其他对话在这两份文件中的未提交改动保持原状。需要回退时先备份当前工作区，再撤销本次提交，不要 `reset --hard`。
