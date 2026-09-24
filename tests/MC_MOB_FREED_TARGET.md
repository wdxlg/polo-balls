# Minecraft 生物索敌：已释放实例修复

用户编辑器截图：`mc_mob_base.gd` 的 `mc_nearest()` 原第 73 行报 `Trying to assign invalid previously freed instance.`。World 的 30 Hz 目标候选快照在单位 `free()` 后、下一次网格刷新前可能暂时保留无效引用；`for node:Node in Array` **进入循环体前**就尝试把该引用赋给强类型 `Node`，因此在 `mc_enemy()` 的有效性防护执行前已经出错。不能只往原有 `if node is ball` 后补检测。

只改 `scripts/characters/我的世界/mc_mob_base.gd` 的这一段：以 `for raw:Variant` 遍历，先 `is_instance_valid(raw)`、再检查是否 `ball`，之后才转换为 `ball` 并执行原有敌我/锁定/距离判断；缓存逻辑、选最近目标、World 快照和其他人物都保持原样。`tests/test_mc_mob_freed_target.gd` 真实实例化 World/末影人/两个球，把其中一球 `free()` 后留下失效引用，再验证仍可找到活目标和全部失效时返回 null。

对比验证（Godot 4.7.2）：**修复前**同一专项 `EXIT=1`，`4 checks / 1 failures`，stderr 两次原文 `Trying to assign invalid previously freed instance.`；**修复后** headless `4 / 0`、真实 GPU `4 / 0`，均无上述 SCRIPT ERROR。关联回归：硫方怪 headless `54 / 0`、双 ENet `19 / 0`、凋灵节奏 `NEW5_RESULT checks=32 failures=0`。原索敌全局测试 `TARGETING_CANDIDATES_RESULT {"checks":20,"failures":0}`，但该测试同时在 stderr 报另一并行任务素材（如 `cactus_note` 与 `new5/fishing_rod`）尚未导入的 preload/解析错误；**不能将它说成完全无日志错误**，此处未擅改其他素材。

**版本/回退边界：**修改前分支 `main`/HEAD `92c3138`，共享 `mc_mob_base.gd` 已有其他任务未提交改动；检查点为 Arena 工作区 `/home/user/MC生物索敌报错_修改前检查点.zip` 和 `/home/user/MC生物索敌报错_修改后检查点.zip`。本次共享脚本的唯一增量另存 `tests/patches/mc_mob_freed_target.patch`，在当前工作区 `git apply --reverse --check --no-index` 通过。Git 仅暂存可分离的增量补丁、测试与说明，不捎带该脚本其他任务未提交差异。**单独检出补丁提交不是完整运行快照**：需先保留或并入当前共享脚本基线。不要直接 `reset --hard`/`clean`；回退前重新确认目标文件状态与备份。正在调试/暂停的旧进程未必加载到新脚本；停止并重新运行战斗、清除旧调试记录后再复核这个错误。
