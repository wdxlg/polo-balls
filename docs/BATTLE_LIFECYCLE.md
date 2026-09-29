# 角色存续与整组结算协议

适用：普通模式结束铃声、Boss 的常规/车轮结算、轮换 1v1 / 车轮 / 挑战。**计时模式仍按原累计伤害/计时规则结算**；本协议不把计时复活改成整组复活。

## 判定对象

参战单位与场景节点不是一回事。一个玩家放下的角色，可以由本体、同批成员、召唤物、分裂体、后续形态，以及已经确认但尚未完成的生成请求共同代表。

- 对应原 `battle_setup_id` 的存续成员全部消失，且没有已确认的待生成请求，才可将该轮换槽判负、打叉、换人。
- 手动/Boss 最终铃声使用相同存续成员集合，再按胜负阵营汇总。
- **Team 不是角色槽 ID。** 同队两位角色不能替彼此续命；无队伍角色的后代也不能变成新的独立胜负阵营。
- 1v1 存活的后代可以代表已经消失的本体获胜；胜者对勾仍落在原头像。退出该小局时清理整个旧角色组，不能只查原本体节点。
- 使用 `combat_classification.gd::profile_of()` 的现行分类：投射物、落地攻击区域、地形、障碍、装饰不代表角色存续。不能通过旧 `Type == Ball/Creature` 把纯特效或武器误算成仍活着的人物。

## 共用实现

`world.gd`：

- `bind_battle_lifecycle(unit, source = null, force = false)`：生成时冻结来源角色身份。只写存续 metadata，不修改 Team、Master、战斗属性、攻击逻辑。
- `battle_lifecycle_identity`：保存原 setup、胜负阵营、根身份、本局 generation / 小局 round。不是新分类表，不用于猜弹体类别。
- `register_battle_unit()` 自动绑定已设置 `Master / Master_name` 的单位；`ball` 补解析主人名称时也接入同一入口。**不再等某一帧铃声轮询偶然缓存主人。**
- `_battle_unit_keeps_family_alive()` / `_battle_family_alive()`：共同存续判定；两种结算不得各写一套。
- `_scan_rotation_family_extinctions()`：退出事件及结算轮询只要求复核整个角色组，不能直接用本体 `tree_exiting` 将 active ID 清空。
- `_has_active_battle_participant()`：仅后代或有效待生成请求存在时仍允许战斗运行。`_count_primary_battle_characters()` / `_has_alive_primary_battle_character()` 保留原布阵主角色计数语义及性能契约，不要再将两类查询混用。

## 新召唤/分裂/变形的强制接入

### 1. 普通有主人的参战后代

在 `add_child()` 之前设置真实的 `Master`、`Master_name` 和原有 Team。公共注册负责继承身份，后续即使主人删除也保留。孙代同样继承最初角色槽，而不是把上一代节点当成新选手。

### 2. 没有 Master 的独立身体

例如兔子伙伴/幼兔、保安同批成员、木剑碎片。不要为了结算强行改变它们原有 AI/伤害的 Master 关系；在入树前调用：

```gdscript
world.bind_battle_lifecycle(child, source_character)
world.add_child(child, true)
```

变形若保留已有 `battle_setup_id`，仍须验证原槽贯穿变形/恢复。不要为了分裂把新成员加入可编辑的 `_battle_setup`，更不要为各个后代分配新的轮换位置。

### 3. 原身体消失后才生成的单位

不能靠延长固定的 0.28 秒换人时间、猜某个角色名，或把整张地图标为“还活着”。当生成**已经确认**时，先领取存续票据：

```gdscript
var ticket = world.begin_battle_spawn(source_character, request_node)
# request_node 是负责完成/取消这次操作的节点；应尽快入树。
# 完成延迟后、child 入树前：
if not world.apply_battle_spawn_identity(child, ticket):
    child.free() # 重置/换局已取消旧操作，不能继续生成旧局单位。
    return
world.add_child(child, true)
world.finish_battle_spawn(ticket)
```

失败、数量上限、取消也必须释放票据。托管节点消失时公共弱引用校验会回收；重置、重打/小局清场清空票据并改变有效代次。票据序号不复用，旧回调不能占用新请求。

- 保安：对讲机**确认后**才是待到达角色；确认前的可中断施法仍以呼叫者存活为准。请求退出释放票据，并加入清场兼容组 `GuardReinforcementRequest`，不把纯巡逻车画面当角色。
- 蠹虫：真实碎砖孵化申请持票，0.18 秒震动结束后先给新虫继承身份，再释放票据。未触发的砖、烟雾本身不续命。
- 药水：沿用原实际 Team 选择（施法者存在用施法者，否则回退目标），同时给新身体绑定该来源身份。未确认会产生后代的普通状态本身不能永久占住阵营。

## 死亡/复活窗口

生命写为0不等于死亡流程已完成。公共 Ball 的待处理死亡解析、尚未最终进入 Die 的复活/死亡阶段，以及现有显式 death bridge 允许完成真正的角色机制；不允许铃声抢在同帧死亡回调前面。

普通 Creature 没有 Ball 的通用归零死亡解析器，0HP 不能仅因状态机仍是 Move 就无限续命。若确有死后接棒，必须显式持 bridge/票据；普通尸体、死亡动画、无限场地特效不能无限阻塞结算。

旧 `request_silverfish_extinction_victory_recheck()` 只兼容通知统一复核，**不能直接响铃、凭空武装新局或绕过轮换/挑战/计时/养成预备规则**。

## 测试与改动纪律

新增多实体角色至少验证：

1. 本体在首次胜负轮询前死亡，后代仍归原角色。
2. Team 与无队伍；同队不同 setup 不串组。
3. 第一代/孙代、最后一个后代死亡；本体死亡但后代获胜。
4. 0HP 到实际死亡/复活回调之间无假胜利。
5. 无身体、仅确认中的生成请求；失败/取消/重置不残留。
6. 1v1、车轮、挑战各自换人规则与真实铃声触发，不只检查 UI 文本。
7. 投射物、危险区域、障碍和死亡特效不挡结算；新资源继续通过公共分类登记门禁。

运行 `tests/test_battle_lifecycle.gd`、`tests/test_slime_family_victory.gd`、`tests/test_rotation_frames_challenge.gd`、`tests/test_performance_contracts.gd` 和 `tests/verify_combat_classification_registry.py`。不能把 authority 侧本地回归说成真实双客户端已验证；客户端有新增独立表现状态时仍须设计并测试对应同步。

本轮扫描范围、测试证据及恢复边界见 `tests/BATTLE_LIFECYCLE_20260927.md` 和 `docs/BATTLE_LIFECYCLE_AUDIT_20260927.json`。
