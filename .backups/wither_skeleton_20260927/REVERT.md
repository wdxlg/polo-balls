# 凋灵骷髅局部回退清单（2026-09-27）

> 基线提交：`8afe73510f7bcc75c286534344d53a320c6bd7af`（main）。本目录的 `*.before.*`
> 保存的是**本次会话改动前**的共享文件状态（含其他会话未提交工作），仅用于撤销本次共享编辑。

## 撤销本次共享文件编辑（保留其他会话工作）

用本目录副本覆盖：
- `classes/combat_classification_catalog.gd` ← `catalog.before.gd`
- `global/translation_catalog.gd` ← `translation.before.gd`
- `MCP_CONTEXT.md` ← `context.before.md`
- `tests/manual_control_inventory.csv` ← `manual.before.csv`

## 删除本次新增文件（完全自有）

```
git rm -r --cached 不适用（若未提交直接删除即可）：
scenes/characters/我的世界/凋灵骷髅.tscn
scripts/characters/我的世界/wither_skeleton/
scripts/effects/我的世界/mc_creature_voice.gd
tools/build_wither_skeleton_assets.py
tools/run_wither_skeleton_checks.py
tests/test_wither_skeleton.gd
tests/preview_wither_skeleton.gd
tests/WITHER_SKELETON_20260927.md
tests/wither_skeleton_gpu_*.png
tests/wither_skeleton_preview_*.png
docs/WITHER_SKELETON.md
Images/characters/我的世界/wither_skeleton/
audio/characters/我的世界/wither_skeleton/
```

若该提交已发生：`git revert <commit>` 只回退自有文件；共享文件按上一步恢复。
日志：本目录 `headless.log` / `gpu.log` / `import.log`；预览探针已删除，不复用。
