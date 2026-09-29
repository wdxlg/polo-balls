# 自由模式胜利状态生命周期修复（2026-09-29）

## 用户问题与根因

用户反馈：两人对战决出胜者后再放人物，仍保持旧胜利；重置后只放一个人物也错误显示胜利。

改前使用真实 `world.tscn`、`ball.tscn` 和 `world.create_char/reset` 复现，9 项断言中 4 项失败。没有手动伪造胜利标志。

1. World 判胜和 HUD 都在旧胜利状态下提前返回，新增角色没有结束旧结果。
2. reset 使用 queue_free，旧人物尚未出树时，空阵容的判胜回退仍将其计为参战者，重新武装了胜利条件。
3. 重打阵容保留历史死者；若仅清空 played/UI，会把历史敌方重新计入判胜，且污染新一场的队伍人数。

## 改动范围

业务仅改 `scripts/world.gd`、`scripts/ui/duel_top_hud.gd`，没有另建判胜器或 HUD。

- 自由模式获胜后成功添加主角色：解除旧结果，保留存活角色实例、生命和状态，重新建立本次遭遇的参战身份范围。
- 共享判胜轮询也检查真实新增对立阵营，支持非 create_char 的正常生成入口。
- 新增同队成员不因历史敌方已经死亡而立即再判胜；召唤物不作为新增主角色重开结果。
- 当前遭遇身份与完整重打记录分开：历史死者不计入下一场的人数，但不删重打阵容；同一场原多人队伍只剩一人仍按队伍显示。
- 空阵容回退复用已有生命周期存续校验，排除待删除、正在退出及旧代次人物。
- 重置统一清理旧结果、名册、对阵、镜头聚焦与时钟；过期代次不再补播第二、第三下胜利铃。
- 非车轮全关门前继续战斗、车轮场外走入、队伍羊毛提示、图腾/家族重验、计时/加赛原规则保持。

## 验证

最终有效检查按测试去重，共 **644 项 / 0 失败**，不是穷举所有角色对局。

| 测试 | 环境 | 检查数 |
|---|---|---:|
| test_victory_lifecycle_reset | Windows GPU | 30 |
| test_rotation_live_team_victory | Windows GPU | 45 |
| test_duel_top_hud | Windows GPU | 82 |
| test_rotation_timed_flow | Windows GPU | 55 |
| test_rotation_timed_boundaries | Windows GPU | 28 |
| test_dark_oak_transition | Windows GPU | 87 |
| test_rotation_frames_challenge | headless | 97 |
| test_battle_lifecycle | headless | 83 |
| test_evoker_totem | headless | 41 |
| test_slime_family_victory | headless | 63 |
| test_rotation_timed_network | 独立双进程 ENet | 12 + 21 |

新专项覆盖：首次单人不获胜、两方正常结算、战后放对手返回 VS、保留赢家实例和 321 生命、连续三场再次结算、新场展示代次改变、同队增员不误胜、旧死者不污染新队伍人数、原多人队伍本场单存活仍显示队伍、下一场独自参赛显示人物、直接生成入口、召唤物不重开、reset 同帧/跨帧/连续执行、单人放置、取消旧铃声、镜头/提示清理，以及真实 rematch 重建完整保存阵容。

GPU 抓取了首胜、新对手、重置单人三个实际 World 画面，已目视核对：首胜成就正常，新对手恢复顶部 VS 且旧胜者仍为 321/1000，重置单人无胜利成就。夹具使用基础 ball，不作为人物外观验收或完整录制验收。

`get_diagnostics` 返回 0。全局分类检查仍有原有 35 个范围外缺失；本次两个运行脚本已登记，不声称项目全局 gate 全绿。基础场景仍有原有 shader UID/文件大小写警告；部分旧回归退出仍有 ObjectDB 残留警告，原始日志未隐藏。新专项最终运行没有 ObjectDB/resource 残留警告。

ENet 仅验证已有生产 RPC/状态夹具，不等同公网完整人物复制、晚加入/重连或 MP4 验收；本轮未新增这类保证。

## 备份与局部恢复

改前备份：`../polo-balls-checkpoints/victory_lifecycle_20260929/before/`。

隔离归档（不切换主分支、不改主 index）：

- `refs/checkpoints/victory-lifecycle-20260929-before`
- `refs/checkpoints/victory-lifecycle-20260929-after`
- `../polo-balls-checkpoints/victory_lifecycle_20260929/version.json`
- `../polo-balls-checkpoints/victory_lifecycle_20260929/victory_lifecycle.patch`

归档从当前文件逐项逆本次 hunk 构建 before，保留既有轮换/计时和并行修改；只在 reverse-check 通过后形成检查点。恢复必须先备份并检查 `git apply --reverse --check --unidiff-zero <patch>`，不允许整文件覆盖、reset/clean 或恢复整个仓库。开工后并行仙人掌提交独立保留。

日志、初次失败复现、截图与逐文件哈希存放在同一检查点目录；新测试为 `tests/test_victory_lifecycle_reset.gd`。
