# 铁砧/信标侧撞反弹与凋零粒子大小（2026-09-24）

## 用户范围

铁砧、信标左右撞到角色时也应反弹，而不是只对墙体生效。用户进一步确认：凋零药水粒子**只统一到女巫的大小**，不改颜色、数量或运动效果。

## 修改

### 铁砧

- 原常态巡游已经有真实身体接触后的转向/碰撞反馈，但 `_horizontal_step()` 在大规模战斗模式下把扫描 mask 改成 1，直接跳过角色层 2。
- 本次仅改该横向扫掠：两种模式均临时扫描 mask=3（地形+角色），之后立即恢复原 mask。常态左右巡游撞敌人/队友均可反弹。
- 继续使用真实 CharacterBody2D 的扫掠与碰撞法线；不把攻击范围或贴图外框当身体，不增加伤害，不把角色接触当成铁砧砸地叮声。
- **不改已有跳砸、贯穿、持续压伤、击退、加速度追踪和连砸规则**。技能跳跃期间仍按原规则双向忽略角色身体；下砸仍保持原来的命中/贯穿。直接控制的左右输入规则保持原状，不新增强制操控反弹。

### 信标

- 原 `_gravity_step()` 碰到侧面只把 X 速度归零，后续追踪下一步又朝碰撞对象走。本次角色侧撞、地形侧撞共用反弹处理。
- 横向移动时临时打开角色层 2，立即恢复 mask；大规模模式也会碰到身体。保留与凋零召唤者的既有碰撞例外，不让它反复撞自己的主人。
- 只对 `abs(normal.x)>0.5` 且速度正朝向碰撞面时触发，反射为纯 X 方向。保留 **0.35 秒游戏时间**的弹开方向，避免追踪下一步立即覆盖反弹；然后恢复原有寻敌 X 追踪。
- 反弹速度继续服从当前阶段移速：发射时半速，末段渐恢复。重力不暂停，不因碰地/支撑误触横向反弹。暂停冻结反弹计时；关闭主动移动仍停止主动横移。
- 复用现有 `when_collide` 碰撞反馈，不新增碰撞伤害。光柱继续从蓝色核心发光、保持竖直并跟随位置；5 秒 / 50×6 基础 300、蓝圈、实际伤害与威胁同步均保留。

### 凋零状态粒子

- 对齐的是 `女巫药水状态.gd` 的世界空间粒子：随机缩放 **0.020～0.030**。不是药水区域粒子的另一组范围，也不是粒子脚本的默认参数。
- `wither/status.gd` 原为 0.042～0.052，本次仅替换这一项；平均线性大小约为原来的 53%。
- 仍使用相同八帧素材，黑色 `Color(0.12,0.12,0.12,0.98)`、0.14 秒生成间隔、位置随机范围、向上速度、0.060～0.072 帧间隔、透明衰减和状态伤害全部保留。
- 女巫生产代码、粒子共用脚本与素材未修改。

## 验收

独立 Godot 4.7.2 / RTX 4060 / D3D12。不是只测试反射向量：创建真实 World、身体和墙体，实际执行运动，再观察接触后的位移。

| 测试 | 检查数 | 失败 |
|---|---:|---:|
| `test_horizontal_contact.gd` | 61 | 0 |
| `test_beacon_cycle.gd` | 62 | 0 |
| `test_wither_beacon_revision.gd` | 42 | 0 |
| `test_wither_live.gd` | 55 | 0 |
| `test_anvil.gd` | 38 | 0 |
| `test_anvil_bounce_audio.gd` | 32 | 0 |
| `test_anvil_through.gd` | 26 | 0 |
| `test_anvil_crush.gd` | 106 | 0 |
| `test_anvil_knockback.gd` | 23 | 0 |
| `test_anvil_jump_passthrough.gd` | 34 | 0 |
| `test_anvil_arc.gd` | 66 | 0 |
| `test_anvil_fall_tracking.gd` | 47 | 0 |
| `test_anvil_impulse_tracking.gd` | 57 | 0 |
| `test_anvil_balance.gd` | 27 | 0 |

共 **676 项通过**；另 `test_wither.gd` headless 加载/行为检查 EXIT 0。最终日志无 SCRIPT ERROR。既有 shader UID/大小写、World 退出 ObjectDB 警告未宣称修复。没有进行双客户端或人数压力/帧率测试；“大规模模式通过”指直接开启对应模式的碰撞逻辑，不是数百角色性能认证。

专项覆盖普通/大规模模式 × 左/右 × 敌人/队友；验证真实反向位移、碰撞 mask 恢复、无附加伤害或砸地叮声、信标双向墙反弹、半速发射移动、竖直光柱、地面支撑、暂停及召唤者例外。

真实生成 64 个凋零粒子和 64 个女巫状态粒子，全部世界缩放落在 0.020～0.030，无父节点缩放造成的隐性放大。本次采样均值分别 **0.0252794278 / 0.0243537386**；颜色、运动、时序、生成间隔和状态伤害保留断言通过。既有信标伤害仍在 60fps、30fps 和 5.6 秒长步长下均为 **1000→700**。

测试开发时修正了 SceneTree 脚本在 autoload 注册前 preload 依赖 Game 的夹具加载方式，并在身体初始化后等待实际帧。远端 World 的帧驱动位置更新会重定位测试诱饵，所以在墙测试开始手动积分前重新固定其位置。未通过改变生产碰撞/寻敌逻辑来迁就夹具。

## 精确版本与未提交铁砧的特殊处理

- 修改前 HEAD：`e99d151aa343128794fa5a589b1a27dd79951d80`。
- 完整修改前备份、铁砧前/后原始字节副本、最终测试日志：`E:/godot/polo-balls-checkpoints/contact_bounce_20260924_075021/`。
- 标签：`checkpoint/contact-bounce-before-20260924` / `checkpoint/contact-bounce-ready-20260924`。
- 接入时 **`scripts/characters/我的世界/铁砧.gd` 与 `tests/ANVIL.md` 已是未跟踪文件**。后者完全未改；铁砧只改横向 mask 的一个局部块，不把整套既有铁砧工作、资源或旧测试强行纳入本次 Git 提交。
- 信标/状态/本次测试/说明纳入常规本地提交。铁砧本次差异以 `tools/checkpoints/horizontal_contact/anvil.patch`、`anvil_delta.json` 和严格校验的恢复脚本纳入同一提交。**这是本轮的局部恢复版本，不是整个项目或铁砧历史的完整 Git 快照。**

### 恢复铁砧本轮差异

先保存编辑器并备份当前修改。以下命令默认只校验、不写文件：

```text
python tools/checkpoints/horizontal_contact/restore_anvil.py --state before
python tools/checkpoints/horizontal_contact/restore_anvil.py --state after
```

确认输出 `DRY RUN OK` 后，加 `--apply` 才实际恢复。脚本校验完整文件前后 SHA-256，只替换本轮局部块，并恢复精确字节；有后来编辑时会拒绝，不覆盖后续工作。已在独立备份测试目录执行 before→after 双向实际写入并验证字节一致，真实工作文件保持更新后状态。

正常 Git 文件回退只撤销指定提交或恢复本次文件；不要 `reset --hard`、清空其他 dirty、`git add .` 或上传整个工作区。除本轮选中修改的铁砧和下述并行外部更新外，其余预存 dirty 文件逐一 SHA-256 核对保持不变，不把铁砧误报成“原文件完全未变”。

### 工作期间的并行外部更新

审计发现 `scripts/world.gd`、`ui/control.gd`、`scripts/characters/我的世界/new6/heavenfall_bolt.gd`、`scripts/characters/我的世界/new6/heavenfall_longbow.gd` 和 `tests/test_heavenfall_contacts.gd` 在本轮期间被其他工作更新。这些文件未被本轮编辑、还原或提交；保留观测到的最新版并记录独立哈希；若提交前又出现其他不相交的外部更新，以检查点 `completion.json` / `external_changes.json` 的最终清单为准，不反复覆盖或撤销外部工作。发现后又在当前工作区重跑碰撞专项 61、信标周期 62、信标回归 42、凋零 55 及 headless smoke，全部通过。铁砧十组回归结果为本轮各自日志中的实测，不声称对其他任务的长弓/录制功能进行了验收。
