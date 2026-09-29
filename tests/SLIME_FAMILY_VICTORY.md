# 史莱姆分裂阵营与整体胜负修复

## 行为（2026-09-22）
- 大 → 两只中 → 四只小的数量、属性、跳跃/碰撞/伤害不变。
- 后代在入树和 World 注册前继承 Team、Master/Master_name、家族 ID，以及原角色的稳定胜负/顶部显示身份；祖先节点删除后仍有效。
- 无队伍模式不把所有史莱姆强行合并：同一家族的后代仍是一方，不同原始史莱姆家族仍彼此为敌。保留原来的同家族不互伤规则。
- 大/中型致死伤害在 health setter 的角色钩子中立即启用既有死亡桥契约，覆盖 HP=0 到 Die()/生成后代之间的胜负轮询空档。两只后代注册完成后撤下桥，不加人为结算延迟。
- 小型不再分裂，也不持有死亡桥。只要家族仍有活体，不能因祖先死亡提前判负；最后一只死亡后由原 World 胜负铃去重逻辑正常判断整场胜负。
- 轮放/车轮战保留原角色的名单槽位，母体退出不会提前标记战死或换人；最终后代退出才接回既有换人流程。另存 continuation_setup_id，不复制 battle_setup_id，避免后代成为重复可编辑布阵条目。
- 三种史莱姆场景的 SlimeIdentitySync 同步家族、胜负身份、顶部显示身份和原名单 ID；Team/Master_name 继续使用现有 ball 生成同步。仅验证本地 authority/replica 分支与配置，不声称真实双端网络验收。

## 专项/相关回归（GPU，全部 exit 0）
| 测试 | 通过 | 失败 |
|---|---:|---:|
| tests/test_slime_family_victory.gd | 63 | 0 |
| scripts/training/test_slime_split_profile.gd | 6 | 0 |
| scripts/training/test_slime_damage.gd | 24 | 0 |
| scripts/training/test_slime_deferred_turn.gd | 189 | 0 |
| scripts/training/test_slime_physical.gd | 222 | 0 |
| scripts/training/test_slime_adaptive.gd | 87 | 0 |
| tests/test_iron_golem_fall_damage.gd | 28 | 0 |
| 相关专项合计 | 619 | 0 |

新胜负专项包括有队伍/空队伍、致死同帧、重复 Die、防重复分裂、祖先实际释放、全部四只末代逐只死亡、独立家族、顶部 VS 分组、生成同步字段和轮放槽位/最终换人。

## 综合测试的已知边界
- 另外运行 scripts/training/test_mc_new5.gd：104 个断言中 90 通过、14 失败，不能算作全部回归通过。
- 其中 13 项为守卫者旧 ±15 度扇区/角度断锁断言；当前 guardian.gd 已明确实现 360 度范围内索敌。另 1 项为钓鱼竿的“速度耗尽前不转为中立”断言。本次未修改两者生产逻辑或这些断言来凑通过。
- 测试退出前现在等待 World 已发起的资源后台加载完成，避免短测试在销毁场景/退出时中止加载、产生假性资源预载报错。该调整只在测试清理中，不改变游戏预热流程。
- 最终史莱姆胜负专项无脚本错误；编辑器错误诊断为 0；修改范围 git diff --check 通过。既有 shader UID/大小写及 ObjectDB 退出清理警告保留，未扩展处理。
