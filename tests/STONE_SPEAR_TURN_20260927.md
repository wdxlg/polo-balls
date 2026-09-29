# 石矛本体快速转向（2026-09-27）

用户反馈本体转向太慢。本轮仅将原固定360°/秒改为导出参数 `body_turn_degrees_per_second=1440`（4倍），原最短角度rotate_toward算法不变。普通状态90°约0.0625秒、180°约0.125秒，实际完成时间向上取整至物理帧；不是瞬间传送角度。

分身位置/角度的平滑跟随、随行外排滞后、旋转切线、伸刺锁定方向和回收无伤、每秒20移动成长与永久保留、基础生命/攻击/透明度/冷却均未改。已发起伸刺期间仍锁定本次朝向，不将该动作改成追踪攻击。

## 本轮验证

Godot 4.7.2 Steam：
- `tests/test_stone_spear_turn.gd` headless 31/31；图形后端再运行31/31（同一批逻辑/节点姿态断言，不是额外31个独立场景，也不声称做了截图像素验收）。覆盖30/60/120Hz的90°/180°完成时长、不超调、每60Hz帧24°、主体图像/受击框角度、分身继续滞后动画、±PI最短转向、暂停/眩晕、出刺锁向、成长保留。
- 原角色 `test_stone_spear.gd` 132/132；分身 `test_stone_spear_follow.gd` 89/89；双SceneMultiplayer实际ENet `test_stone_spear_network.gd` 20/20。
- 以上最终进程全部退出0，无SCRIPT ERROR；保留原项目shader UID和大小写警告。不将上轮GPU逐帧/PCM或完整游戏录制当成本轮重验。

## 局部版本

修改前主HEAD为5944fee7ad0455c1ae107f62a073d3ea81dd6270；先备份本轮触及文件，然后独立index建立 `checkpoints/stone-spear-turn-20260927` → `updates/stone-spear-turn-20260927`。只包括石矛的两行运行修改、本主题MCP说明及专项测试/报告，不修改分身参数或其他角色，不移动主HEAD/共享暂存区、不推送。

`E:/godot/polo-balls-checkpoints/stone_spear_turn_20260927/` 保存before、日志、baseline.json、commit_ids.json和owned_update_minimal.patch。回退前备份当前修改，先 `git apply -R --check --unidiff-zero <补丁路径>`，通过后再定向应用；共享文件有后续修改须合并，禁止整库reset/clean。局部提交不是全工作区完整快照。
