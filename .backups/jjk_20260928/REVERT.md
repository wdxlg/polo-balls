# 咒术回战四角色局部回退清单（2026-09-28）

> 基线：`main` `084d1193ae5d`（见 `head.txt`；改动前工作区脏条目数见 `dirty_count.txt`）。本目录的 `*.before.*`
> 是**本次会话改动前**的共享文件状态（含其他会话未提交的工作），只用于撤销本次共享编辑。

## 撤销本次共享文件编辑（保留其他会话工作）

用本目录副本覆盖：
- `classes/combat_classification_catalog.gd` ← `catalog.before.gd`（+13 行：4 个场景 + 9 个脚本）
- `global/translation_catalog.gd` ← `translation.before.gd`（中/英各 +13 个键）
- `translations.csv` ← `translations.before.csv`（+13 行）
- `tests/manual_control_inventory.csv` ← `manual.before.csv`（+4 行）
- `tests/test_manual_control_roster_extensions.gd` ← `roster_ext.before.gd`（+4 行）

如果其他会话之后又改了这些文件，就不要整文件覆盖，改为手动删除含 `五条悟/宿傩/魔虚罗/嵌合暗兽/咒术回战` 的行
（`tools/jjk_integrate.py` 是幂等的，可以对照它插入的内容）。

## 删除本次新增文件（完全自有）

```
scenes/characters/动漫/五条悟.tscn  宿傩.tscn  魔虚罗.tscn  嵌合暗兽.tscn
scripts/characters/动漫/咒术回战/
Images/characters/动漫/咒术回战/
audio/characters/咒术回战/
sources/jjk/
tools/build_jjk_assets.py
tools/jjk_integrate.py
tools/run_jjk_checks.py
tests/test_jjk.gd
tests/test_jjk_gpu.gd
docs/JJK_CHARACTERS.md
```

如果已经提交：`git revert <commit>`，它只回退该提交里的自有文件和登记行；共享文件照上一步处理。
日志：本目录 `headless.log`、`gpu.log`、`test_*.log`，截图 `shot_*.png`。

## 提交范围说明
- 提交只包含自有新文件，以及三个已跟踪共享文件里本次新增的行（`translations.csv`、`global/translation_catalog.gd`、
  `tests/manual_control_inventory.csv`；通过 `shared_hunks.patch` 只暂存本次改动，没有带上其他会话未提交的工作）。
- `classes/combat_classification_catalog.gd`、`tests/test_manual_control_roster_extensions.gd` 在 git 里**未跟踪**，
  本次对它们的登记只在工作区，没有提交（提交它们会把其他会话的整份未提交内容一起带进去）。
