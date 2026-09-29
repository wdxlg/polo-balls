# 蜘蛛织网不受控制影响（2026-09-30）

用户要求：“蜘蛛的织网应该是只要它碰到障碍物就织网，不管它当前是否处于眩晕等各种控制”。

## 原因（修改前）

1. `蜘蛛.gd::move()` 扫描滑动碰撞时要求 `mc_live() and not dizziness`。
2. 眩晕/击退/Stand 状态走 `ball.stand()`（Repel、拉拽、推挤、表面运动都会真实位移），它从不调用 `when_collide()`，蜘蛛也没有覆写，撞墙完全不织网。
3. `spider_silk.gd::touch_wall()` 与 `advance()` 要求 `mc_live()`（含“未禁攻”），禁攻期间既不织网，连 0.18 秒接触防抖都停止倒数。
4. `physical_airborne_effect.gd` 自己 `move_and_collide()`，蜘蛛看不到击飞中的碰撞；地图边缘是矩形限位，没有碰撞对象。

## 现在的规则

- 织网资格唯一入口 `蜘蛛.gd::can_weave_silk()`：权威端、存活、战斗运行中、未暂停。**不检查眩晕、禁攻或任何控制**。
- `move()`、新增 `stand()` 覆写、`when_collide()` 都用它扫描墙体碰撞；请求速度为零（本帧没有 `move_and_slide()`）时不复用上一帧旧碰撞。
- 击飞效果新增通用可选钩子：目标有 `on_forced_motion_collision(collision)` 时，报告真实碰撞；被地图矩形限位挡住时沿受阻轴 4px 测试移动（test_only）探到真实墙体再报告。没有该方法的角色零开销、行为不变。
- `spider_silk.gd`：接触防抖、锚点有效性、交叉结网、同步和绘制在任何控制下照常；**伤害/减速/扑击呼叫**（`_tick_contacts`）仍要求 `mc_live()`——禁攻期间网照常形成但不造成伤害，并清空扫掠历史，解除后不会一次性扫过整段时间。
- 扑击本身仍是攻击：眩晕时不能发起（`hunt_web_target` 不变）；撞墙中止扑击仍需 `mc_live()`。
- 暂停、死亡、非权威副本不织网（不属于“控制”）。

## 修改文件

- `scripts/characters/我的世界/蜘蛛.gd`
- `scripts/effects/我的世界/spider_silk.gd`
- `scripts/effects/physical_airborne_effect.gd`（仅新增可选钩子，其它角色无变化）
- `tests/test_spider_weave_under_control.gd`（新）
- `MC16_REWORK.md` 蜘蛛第 10 条

## 验证（Godot 4.7.2 headless，真实 World / Map50x50 / StaticBody 墙）

- `tests/test_spider_weave_under_control.gd`：22/22 通过。覆盖真实 `apply_stun` + `apply_knockback` 撞墙（织网时仍处于眩晕，锚点在墙面）、禁攻+眩晕撞墙、禁攻时防抖倒数、禁攻时固定丝完成并交叉结网但不伤害、解除禁攻后同一网恢复伤害、零位移 `stand()` 不复用旧碰撞、眩晕不能扑击、击飞撞障碍物（落地前织网）、击飞撞地图边缘墙（矩形限位探测）、暂停不织网。
- 在修改前代码上运行同一测试：“眩晕+击退撞墙织网”失败（证明测试能抓住原问题）。
- 回归：`test_mc16_fixed_silk` 28/28；`test_copper_negative_cleanse` 123/123（击飞共享路径）；`test_mc_combat_reuse_smoke` 0 失败；`test_mc16_spider_drowned` 63 项中 18 项溺尸三叉戟失败，与修改前代码完全相同（范围外、既有）。

## 局部恢复

`git revert <本次提交>`，或对上述文件执行 `git checkout <本次提交>^ -- <文件>`；新测试文件可直接删除。
