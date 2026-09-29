# 轮换门转场、图腾判定与计时结算 — 2026-09-29

## 本轮实现

### 轮换：每次交手结束都走原双门
- 使用唯一入口 `scripts/ui/dark_oak_transition.gd::ensure/play`，未复制门动画、几何、材质或音效。
- wheel 换败者、challenge 换红方及下一挑战者、duel 双方下一局均覆盖；队列耗尽的最后一局也经过结果与门流程，不无限等待不存在的下一人。
- 先保留上一局场景/胜者，弹原成就式胜利 UI，停留约 1.2 秒；门真正关严并提交覆盖帧后才预加载、清理或生成下一局。
- 原版经验条从底部屏外升起。进度为真实加载阶段：覆盖后 10%，下一位线程资源加载至 65%，原规则换人/实例化至 90%，下一帧准备好后 100%；缓存资源仍经这些阶段，不伪造下载字节百分比。
- 加载完成短暂停留后，经验条向下、胜利成就向上退出；二者退出才开门，开到 50% 释放公共战斗 gate。
- wheel/challenge 应保留的赢家实例、23HP 测试损伤及原状态保持；duel/挑战整轮仍按原规则重建。
- HUD 在结果期间锁上一局身份；门前成就复用同一 HUD 的只读镜像。双败用“本局结束 / Round Complete”，不伪报单方胜者。
- reset/restart/退出 World 取消旧协程与门；half 信号或回调中取消，不再继续发成功结束。
- 下一位资源缺失/失败：不报告 100% 或开始战斗，保留旧赢家和未推进的队列，关闭遮罩，返回布阵控件并显示加载失败。预览入口对不存在场景安全返回，不重复刷资源错误。

### 图腾与存续
- 死亡/退出通知仅登记候选，0.28 游戏秒后按原 setup 家族和票据重新确认是否真的灭绝；救活/延续仍存活时撤销候选，不划掉头像、不换人。
- 三种轮换规则均用真实唤魔者致死命中触发图腾，验证恢复 50HP 并保原槽位；也覆盖陈旧死亡通知。
- 未修改唤魔者私有保命逻辑，未宣称旧 setter 曾先广播 0HP。复用公共存续/票据机制；史莱姆子代、木剑碎片等仍按原家族存续。

### 计时与顶部 HUD
- 倒计时归零不暂停；唯一最高累计伤害者胜，其余 setup 家族直接进入原死亡路径。
- 行政判败使用已有强制规则死亡标记，跳过图腾等致死预防；封存最终分数，禁止败者后代和训练复活重新进场，赢家继续真实物理运动。
- 最高伤害并列进入加赛，不暂停、不杀并列者或提前处置其他人；首次实际伤害造成唯一领先时，在同一伤害回调立即结算。
- 1v1 仍使用 `scripts/ui/duel_top_hud.gd`：删除生命/心，保留护甲，生命文字改为累计“造成伤害 / Damage”；中央 VS 的时间变倒计时/加赛。
- 不再画下方倒计时；非 1v1 计时也由同一 HUD 只绘中央倒计时，不另建 UI。
- 只由权威端推进时钟、加分和判胜。公共暂停、SceneTree pause、零速均冻结倒计时。
- 每 0.1 秒可靠同步计时状态/分数，进入加赛和结算立即同步；客机不自行计时/判胜，拒绝陈旧序号。
- 轮换 begin 同步上一局名单和索引；进度与 ready 单调，拒绝旧 token。

## 最终实际验证：590 检查，0 断言失败

同一专项的重复 headless/GPU 执行不重复计数；真实 GPU 与 headless 类型分别列出。以下全部在最终业务补丁后完整退出，不以超时退出 0 冒充通过。

| 测试 | 执行方式 | 结果 |
|---|---|---:|
| `test_rotation_timed_flow.gd` | Windows 真实 GPU，540×960 | 71/71 |
| `test_rotation_timed_boundaries.gd` | Windows 真实 GPU，540×960 | 33/33 |
| `test_dark_oak_transition.gd` | Windows 真实 GPU，26 抓帧 | 87/87 |
| `test_duel_top_hud.gd` | Windows 真实 GPU | 82/82 |
| `test_rotation_frames_challenge.gd` | headless | 97/97 |
| `test_battle_lifecycle.gd` | headless | 83/83 |
| `test_evoker_totem.gd` | headless | 41/41 |
| `test_slime_family_victory.gd` | headless | 63/63 |
| `test_rotation_timed_network.gd` | 两个独立 Godot 进程，真实本机 ENet | 服务端12 + 客机21 = 33/33 |

- 专项边界：最后一局、缺失下一位资源、旧胜者保留、三人计时中央钟、三类暂停、即时加赛判胜、所有败者死亡、half 回调取消、World 在全覆盖时退出。
- ENet 验证生产 World RPC：权威时钟/分数/加赛/终局、旧包拒绝、上一局身份、真实门关闭/进度等待/半开释放及旧 token。不是完整公网双客户端游玩验收；客机使用无战斗演员的展示夹具，未据此声称角色复制全链路通过。
- 真实 GPU 抓帧已下载目视：旧局结果、全关门初始进度、满经验条、成就向上退出/经验条下退、半开门新局、计时伤害/护甲无生命、三人中央时钟。测试地图原有云层遮挡没有被当作本轮 UI 错误或加以扩改。
- MCP `get_diagnostics` 最终返回 0 项；这是编辑器诊断结果，不等于全工程所有运行路径无错误。

### 验证过程中修正与保留的边界
- 原轮换/生命周期夹具只等固定短延迟，现改为等待实际转场结束并设明确超时；不绕过门或伪造 ready。
- 旧史莱姆测试期望在通知当刻把 setup 擦成 -1，与本轮“先重验图腾/家族”的新契约冲突。现检查候选已排队且旧 setup 尚保留；其余家族断言保持。
- 生命周期初跑虽 83/83，但木剑 split 出现 `body->get_space()` null。定位到夹具用 `PROCESS_MODE_DISABLED` 从物理空间移除本体后直接调用真实 `move_and_collide`。仅在 split 前恢复夹具本体物理空间，未改木剑业务；最终该错误不再出现。
- 缺失资源注入初跑暴露旧头像预览反复 load 不存在场景；公共路径入口补 exists 检查后，最终故障注入成功且不再刷该错误。
- 仍可见历史 shader UID 回退/文件名大小写告警。未改这些无关资源，不声称跨大小写敏感平台导出已通过。
- 全局分类门禁仍未全过：291 场景/661 脚本，35 项其他范围未登记，stale/invalid kinds/status policy/buff polarity 均为空。本轮补齐原遗漏的 `duel_top_hud.gd` system 登记；本轮三个业务脚本不在 missing 中。详见检查点 `classification_final.json`，不扩改流浪商人等并行工作。
- 未验收：公网/高延迟/断线重连/中途加入的完整实战、所有角色组合、主窗口以外的 root 双门录制合成、离线倍速录制成片及人工完整操作流程。HUD 继续沿既有只读录制镜像接口，未另造第二套。

## 文件与隔离归档

业务：`scripts/world.gd`、`scripts/ui/dark_oak_transition.gd`、`scripts/ui/duel_top_hud.gd`。

共享登记/规则：`classes/combat_classification_catalog.gd`（仅本 HUD 登记）、`MCP_CONTEXT.md`（本轮规则）。

原测试：`tests/test_rotation_frames_challenge.gd`、`tests/test_battle_lifecycle.gd`、`tests/test_slime_family_victory.gd`。

新增专项：`tests/test_rotation_timed_flow.gd`、`tests/test_rotation_timed_boundaries.gd`、`tests/test_rotation_timed_network.gd`，及实际生成的对应 `.uid`。

检查点：`E:/godot/polo-balls-checkpoints/rotation_timed_flow_20260929/`，包含改前防灾备份、最终测试日志/PNG、分类报告、隔离 before/after、补丁和 `version.json`。

- 开始基线 HEAD：`d238b440a49a9d20002743e7cbb8f1d568e27625`。任务期间并行工作产生流浪商人提交 `386eda1`、`f466e3a`，未涉及本轮文件；保留当前主分支，不回退这些提交。
- 本轮隔离归档以归档时最新 HEAD 为父；使用独立 `GIT_INDEX_FILE`，不 checkout/reset/clean/push，不写主 index。
- before 从最新 after **逆序撤销本轮精确 hunks** 得到，保留同文件内其他改动；初始整文件 backup 只作防灾，不用来覆盖当前工作树。
- refs：`refs/checkpoints/rotation-timed-flow-20260929-before`、`refs/checkpoints/rotation-timed-flow-20260929-after`。确切 hash、归档前后 HEAD/index 校验及逆向补丁检查见 `version.json`。

局部回退只在确认需要时执行，先检查：

```powershell
git apply --reverse --check --unidiff-zero ../polo-balls-checkpoints/rotation_timed_flow_20260929/rotation_timed_flow.patch
```

检查通过后才去掉 `--check`；如果以后同一区域被别人修改而冲突，停止并手工合并，不强制覆盖。不要 `git reset --hard` 到检查点。
