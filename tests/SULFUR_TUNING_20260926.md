# 硫方怪：蜂蜜撞墙与第二轮数值调整（2026-09-26）

> 2026-09-27 后续调整：蜂蜜伤害在本文基线上降低75%（倍率0.25），铁下砸倍率升至1.2075；冰按当前攻击×0.625×真实碰撞速度/170线性结算、全方向身体碰撞即时生效，转向保留速度/冰面加速。本文旧数值和测试结果保留作历史；现行实现与追加验证见 `SULFUR_COLLISION_REVISION_20260927.md`。

## 确认后的数值

| 能力 | 调整前 | 现在 |
| --- | --- | --- |
| 铁首次底部撞击倍率 | 1.61 | 0.805 |
| 铁持续碾压倍率，每0.25秒 | 0.24 | 0.12 |
| 附着紫水晶倍率 | 1.4 | 0.7 |
| 飞出紫水晶倍率 | 0.945 | 0.4725 |
| TNT 默认攻击下的基础伤害 | 150 | 200 |
| TNT 半径（判定/预警/爆炸表现入口/威胁） | 80 | 40 |
| 冰自身转向加速度 | 210 | 420 |
| 冰面地表加速度 | 240 | 480 |

铁/紫晶是此前已削弱版本再乘0.5，不是恢复旧基线后减半。爆炸半径减半意味着圆面积剩四分之一。冰既有速度上限不变；地表额外上限仍1.5倍基础速度。TNT保留2.4秒引信、自伤60、双槽消费与补位规则。

## 蜂蜜撞墙

受黏目标订阅公共 `ball.wall_contact_impact(normal_speed,point)`。信号位于共享 move/stand 的真实 slide collision 链，复用连续接触锁和墙体识别；排除角色碰撞和定向重力安静支撑面，不从贴近、粒子或持续吸附计时推测撞墙。

`normal_speed = max(-(requested_velocity - collider_velocity).dot(wall_normal), 0)`。

伤害通过施术者当前 `attack_damage(normal_speed / 170)` 与已有 `_damage_with_impact` → 公共位置伤害/受击减伤通道结算。默认攻击48：法向速度85造成24，170造成48；170的切向速度不提高85法向的伤害。速度≤1忽略。普通物理伤害，不伪装火焰，也不绕过友伤、权威、存活、暂停和输出能力保护。

必须仍是敌方、仍有蜂蜜、目标在当前权威黏附列表且真实碰撞排除租约存在。持续顶同一面墙不重复扣血；脱离后重新撞入才再次触发。脱黏、失去蜂蜜、死亡与离树沿已有清理通道断开订阅。保留蜂蜜、第二槽获得冰不破坏订阅。威胁只在真实命中的物理帧报告受击目标身体圆，不新增持续墙边范围伤害。

## 公共复用与分类

- 新公共信号 `classes/ball.gd::wall_contact_impact` 只报告接触；伤害配方仍属于硫方怪。
- 新公共方法 `surface_acceleration.gd::reflect_momentum(normal)` 同步反射地表额外惯性，并重置前一位置，避免下一帧用撞墙前位移重新向墙内加速。硫方怪原冰惯性反射后调用它；不复制移动算法，不放大速度上限，不延长反弹锁。
- 角色仍为原角色资源；水晶仍为原弹体、冰径仍为原地表、SurfaceAcceleration仍为原状态/组件。蜂蜜订阅是角色能力，没有创造新的弹体/障碍/地形资源。复用索引见 `docs/MC_COMBAT_REUSE.md`。
- 分类覆盖闸门：277场景/601脚本，missing/stale/invalid_kinds均空。

## 最终验证

真实 Godot 4.7.2 offline runtime，Windows D3D12 / RTX 4060 Laptop GPU，未使用 headless。最后一轮全部退出码0：

| 测试 | 通过 |
| --- | --- |
| test_sulfur_tuning.gd（新增） | 31/31 |
| test_sulfur_cube_dual.gd | 149/149 |
| test_sulfur_cube_contacts.gd | 34/34 |
| test_sulfur_cube_balance.gd | 30/30 |
| test_sulfur_cube_polish.gd | 35/35 |
| test_sulfur_cube_dual_network.gd | 36/36 |
| 合计 | 315/315 |

专项使用真实 StaticBody2D 与 move_and_slide 接触，再显式驱动公共墙接触处理器；覆盖法向速度、切向排除、持续顶墙、现时攻击、目标防御、暂停、友方、非权威、解绑、双槽保留蜂蜜、冰面实际积分、TNT伤害与半径外目标不受伤。旧balance断言更新为本次批准的系数与积分上界，不删除/跳过检查。

首次polish回归捕获加速后手控冰反弹被地表惯性抵消的问题；修复公共地表反射后，原测试保持不变通过。旧套件还覆盖双槽顺序/消耗/死亡清理、真实GPU水晶模型像素一致性及预警环、实际ENet两端。联机测试为**同一进程内两个真实ENet peer**，不是两台客户端；未声称实际录制回放、人工整局或移动墙专门实测。

日志：`.git/sulfur-tuning/test_sulfur_*.log`（本机，不提交）。既有 shader UID/文件名大小写警告仍存在，与本次调整无关。

## 版本与局部回退

基线保存在 `checkpoints/sulfur-tuning`，结果保存在 `results/sulfur-tuning`，只用独立GIT_INDEX_FILE组装，未切换/覆盖main或用户普通暂存区。结果commit的父节点就是最终基线。局部比较：`git diff results/sulfur-tuning^ results/sulfur-tuning -- <目标路径>`；回退时仅人工逆向应用本任务差异，先检查并保留之后的并行更改，不使用reset --hard或全树恢复。
