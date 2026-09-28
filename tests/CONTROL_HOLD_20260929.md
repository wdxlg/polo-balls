# C 键手控长按阈值与钓鱼竿抛收线（2026-09-29）

## 问题与修改

正常右键点击稍慢就会刚抛线即收线：公共长按首次重试仅等待45ms，而钓鱼竿的右键在空闲时抛线、已抛出时收线，第二次调用会把第一次取消。

- `global/game.gd`：`CONTROL_ACTION_HOLD_INITIAL_REPEAT_DELAY_MSEC` 从45改为400毫秒。首次按下仍即时执行，本地和远端服务端的按下入口共用该常量；到期后的原逐物理帧尝试及角色原冷却不变。
- `scripts/characters/我的世界/new5/fishing_rod.gd`：复用既有 `player_control_action_hold_repeat_allowed` 策略，仅禁用右键索引1的保持重复，其他索引交给父类。右键按下一次抛线，松开再按可收线；不会因同一次长按自动切换。左键连续挥剑、数字键原策略保留。
- 未改变钓竿自然落地等待、挂中超时、超距断线/回收、剑与收线斩共享冷却、伤害、动画、蓄力或松键回调。已经开始的技能阶段照常推进。
- 分类范围：系统输入的首次重复门限与角色输入策略；没有新增攻击/载体/伤害分量、视觉或音频实现。沿用公共权威输入循环，不增设角色计时器或新的高频RPC。

## 验证

使用 `../polo-balls-tools/offline-engine/runtime/Godot.4.7.2.offline.exe --headless --path <project> --log-file <absolute-log> --script res://<script>`，Python等待进程实际退出，9组均exit 0，合计930项通过。

| 测试 | 通过/检查 |
| --- | ---: |
| `tests/test_control_hold_click.gd` | 49/49 |
| `tests/test_all_character_manual_control.gd` | 31/31 |
| `tests/test_manual_control_role_actions.gd` | 50/50 |
| `tests/test_manual_control_roster_extensions.gd` | 71/71 |
| `tests/test_boat_onboard_control.gd` | 41/41 |
| `scripts/training/test_fishing_shared_cooldown.gd` | 11/11 |
| `scripts/training/test_fishing_pull_slash.gd` | 17/17 |
| `scripts/training/test_fishing_contacts.gd` | 17/17 |
| `scripts/training/test_fishing_slime.gd` | 643/643 |

新增专项覆盖真实200ms普通点击不重复、释放后不补发、重复按下/释放去重、松开重按即时与新门限、450ms长按开始重复、取消清理13个槽、数字键不连发、无效索引、远端权威循环的到期门限/失效目标清理、客户端不本地重复，以及真实钓竿飞行/挂中/落地三个阶段的按住不收线和松开再按收线。既有回归包括弓/长弓蓄力松键与取消、船载控制及钓竿冷却/接触/史莱姆交互。

结果：`tests/control_hold_validation_20260929.json`；详细日志：`tests/<test-name>_hold_20260929.log` 与对应 `.stdout.log`。两个游戏脚本及新测试脚本的编辑器错误诊断均为0；实际引擎日志无ERROR，仅有既有 `ball.tscn` shader UID失效、`set_rgb_color`/`Set_RGB_Color`大小写警告，本次未扩大修复。

**验证边界**：远端专项是在单进程内给服务端循环注入已接受的hold状态，不是真实ENet双客户端RPC测试；尚未做GPU/鼠标实机手感验收。测试在当前共享工作区运行，不能宣称该局部提交是全项目完整快照或全角色联机实战均已验证。

## 版本与局部恢复

修改前基线：`097aeddb43dd72cbc50f4f52178babd7f6940a7c`（main）。修改前备份：`tools/checkpoints/control_hold_20260929_before/manifest.json`，同目录保存三个涉及文件的工作区原始内容与 `HEAD/` 内容/hash。

本次代码仅包含公共45→400与解释注释、钓竿3行重复策略方法；另纳入新专项、结果JSON、本说明与MCP_CONTEXT索引。两个游戏文件此前已有他人未提交修改，保持原样，不整文件暂存；测试也依赖当前工作区已有的手控接入。提交时从当前HEAD叠加本任务的精确hunks构建index，不混入其他控制/音频/发育模式修改。

恢复前先检查并备份当前工作区：优先局部撤销本任务提交；若与后续更改冲突，仅将首次重试常量恢复45并移除本次钓竿策略方法，按需撤销本任务测试/说明/索引。**不要整份覆盖备份、reset/clean或回退其他角色工作**。完整更新后ID见对应 `fix(control): distinguish clicks from holds and keep fishing toggle edge-only` 提交和交付回复。
