# 计时模式：头顶/顶部数字改为“受到的伤害”，受伤最少者胜（2026-09-30）

用户要求：“修改计时模式。把他的头上的造成的伤害数字改为受到的伤害。”
用户选择：判胜改为**受到伤害最少者胜**；1v1 顶部面板一起改；统计**所有实际掉血**。

## 规则

- 分数 = 每个参战 setup 本局受到的全部实际生命伤害：敌人、召唤物、环境、自伤、无来源直接扣血都算；回血不减分。
- 只统计主战人物/延续单位本身（`_is_primary_battle_character`）；召唤物与杂物自己掉血不计入主人。
- 入口：`classes/ball.gd` health setter 在角色钩子（无敌/格挡回血）之后取确认损失 `confirmed_loss`，计时模式下调用 `World.on_timed_health_loss(target, loss)`。致死只计实际掉到 0 的部分。
- World 只在权威端、`_timed_running` 且未结算时累加；客机仍只收 0.1 秒快照。
- 头顶数字（`_timed_damage_labels`）与 1v1 顶部面板“受到伤害：N / Damage taken: N”读同一份 `_timed_damage_by_setup`（变量名沿用，语义改为受到伤害）。
- 结算：受到伤害最少者胜；最低并列进入加赛，不暂停、不提前杀其他人；加赛中任何一次实际掉血打破最低并列时，在同一次生命写入里立即结算。
- 候选：仍在布阵名单（或有在场人物）且家族存活/等待训练复活的 setup。已删除的布阵、已彻底阵亡（训练复活关闭）的人物不能凭“少挨打”获胜；无人符合时退回全部分数参与。
- 旧的“造成伤害”信号计分（`Game.training_damage_resolved` → `_on_timed_training_damage_resolved`）已从计时模式断开；该信号仍供训练统计面板使用。
- 本条替代 `tests/ROTATION_TIMED_FLOW_20260929.md` 中“唯一最高累计伤害者胜”“生命文字改为累计造成伤害”的描述；倒计时、加赛、强制败者死亡、不暂停、权威同步等其余规则不变。

## 修改文件

- `classes/ball.gd`（health setter 6 行钩子）
- `scripts/world.gd`（`on_timed_health_loss`、`_finish_timed_training` 最少者胜与候选过滤、断开旧信号、变量注释）
- `scripts/ui/duel_top_hud.gd`（文案“受到伤害：”/“Damage taken: ”）
- `tests/test_timed_damage_taken.gd`（新）；`test_rotation_timed_flow/boundaries/network/live_team_victory` 期望改为新规则

## 验证（Godot 4.7.2 headless）

- `test_timed_damage_taken.gd` 16/16：受害者自己加分、头顶数字、回血不变、无变化写入不计、召唤物掉血不计、顶部面板“受到伤害：40”、到时最少者胜并淘汰其余、判定后冻结、最低并列加赛不提前杀高分者、加赛首次掉血立即结算、已删除布阵不参与、致死掉血计入、彻底阵亡者不能获胜。
- `test_rotation_timed_boundaries.gd`：计时相关 8 项全部通过（含三人最低并列加赛、真实生命写入打破并列立即结算、所有败者死亡/赢家存活）；另 6 项失败都在加载失败/双门段，与计时无关。
- `test_rotation_timed_network.gd`（两个独立进程、真实 ENet）：计时段服务端 2 项、客机 6 项全部通过（分数/倒计时复制、客机不能结算或加分、权威选出胜者、终局冻结）；之后的轮换双门段失败。
- `test_rotation_timed_flow.gd`、`test_rotation_live_team_victory.gd`：在进入计时段之前就卡在轮换双门（`_rotation_door` 为 Nil，与当前“车轮战不转场”规则冲突），计时段未能执行；它们的计时期望已按新规则更新，但未在本轮跑到。
- 双门段失败未在修改前代码上对照复现（world.gd 同时含他人未提交改动，未做 stash 对照），只按失败位置判断为范围外。

## 局部恢复

`git revert <本次提交>`；或对上面的文件 `git checkout <本次提交>^ -- <文件>`（world.gd / duel_top_hud.gd 含他人未提交改动，恢复前先备份）。
