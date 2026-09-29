# 凋零计时修复 + 凋灵骷髅生命 700（2026-09-29）

## 用户要求
「修凋零计时，然后血量增加100」——凋灵骷髅 600 → **700** HP；修复凋零在等级变化时重置扣血时钟的问题。未加叠层上限（用户未要求）。

## 问题（修复前实测）
- 公共 `scripts/characters/我的世界/wither/status.gd::_choose_application` 在等级变化时把 `tick_left` 重设为 1 秒。
- 凋灵骷髅一轮第二刀 → 下一轮第一刀间隔 0.97 秒 < 1 秒，**贴身连砍 10 秒（叠到 XVII）凋零扣血 0**；脱离后 3 秒内按 17%/秒 一次性结算 51% 最大生命。任何以 < 1 秒间隔升级的来源（女巫叠加药水区域等）同样被推迟。

## 修复
- 等级变化只把时钟夹到新等级周期（`minf(tick_left, period)`），不再重启；首次施加仍在 1 秒后首跳，同等级刷新不移相，强来源到期降级也保持原相位。每跳按当时有效等级结算，其余（1%最大生命/级/秒、来源寿命与回退、免疫、255 上限、权威端结算）不变。
- 场景 `凋灵骷髅.tscn`：`Max_health` 600 → 700。

## 验证
| 测试 | 结果 | 说明 |
|---|---|---|
| `tests/test_wither_tick_phase.gd`（新增） | 11/11 | 每 0.5 秒升级仍 1/2/3/4 秒各一跳且按当时等级 200/400/600/800；同级刷新不移相；V 覆盖到期回 I 保持相位；真实凋灵骷髅贴身 6 秒连砍期间 ≥5 跳；生命 700 |
| `test_wither_skeleton.gd` | 398/399 | 唯一失败 `armor-test explanation supplied`（检查介绍含“3”，09-29 介绍重写后已无“3”），与本次无关、修复前同样失败 |
| `test_wither_skeleton_bolt.gd` | 生命 700 断言通过；之后在 `bolt is visible to AI dodge` 后挂起 | 修复前（HEAD status.gd）同样挂起，既有问题 |
| `test_mc_unified_status_effects.gd` | 132/137 | 5 项凋灵头弹威胁/力量倍率失败，HEAD 版 status.gd 下完全相同，既有 |
| `test_wither.gd` | 断言 `small skull sprite and threat agree` 挂起 | HEAD 版同样，既有 |
| `test_wither_balance_20260927.gd` | 30/32 | 2 项凋灵技能描述文本，与计时无关 |
| `test_witch_potion_upgrade` / `test_wither_live` 54 / `test_mc_active_potion_tooltips` 44 / `test_copper_negative_cleanse` 123 / `test_evoker_totem` 41 | 通过 | |
| `test_mc_damage_audio_unified.gd` | 1573/1576 | 角色总数与流浪商人/皓宸音频策略登记缺口，与本次无关 |

## 实战对比（真实 World、双方正常 AI，15 个 MC 对手 × 6 局，headless 固定 60fps）
| | 修复前（600HP） | 修复后（700HP） |
|---|---|---|
| 总胜率 | 22/90 = 24% | 28/90 = **31%** |
| 共同 7 对手（参照：铜剑 61%、钻石剑 54%、石矛 32%） | 29% | 31% |
| 凋零实际秒伤 | 5.4 | 6.6 |

变化最大：监守者 0-6→2-4（凋零/局 162→517，最高 XV）、女巫 2-4→4-2；远程（骷髅/弓/烈焰人）仍 0-6。实测贴身时间短，未出现长时间叠到很高等级的失衡，但理论上持续贴身时凋零每秒按当前等级%最大生命结算，无叠层上限。

## 回退
- 本次提交只含：`wither/status.gd`、`凋灵骷髅.tscn`、两份凋灵骷髅测试的 700 断言、新增回归测试与本记录、`docs/WITHER_SKELETON.md`。`git revert <本提交>` 即可整体撤销；只撤计时：`git checkout <上一提交> -- scripts/characters/我的世界/wither/status.gd`。
- `MCP_CONTEXT.md` 第 34 行同步更新但该文件含他人未提交改动，未纳入提交。
