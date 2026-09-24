# 兔子繁殖误触发伤害反馈修复

日期：2026-09-24。

## 原因与范围

幼兔原先在父类 `@onready health = Max_health` 时获得成年兔的 145 生命，随后在兔子的 `_ready()` 里改成 36。生命 setter 将 145→36 解释为 109 点真实伤害，因此在繁殖/出生位置触发伤害推镜、暴击粒子和受击抖动。`suppress_floating_text` 只隐藏跳字，不会停止这些伤害反馈。

现在只改 `scripts/characters/兔子.gd`：幼兔在 `_enter_tree()` 中先保存成年上限，再设置幼兔上限，父类直接初始化为 36/36；删除 `_ready()` 中的伪扣血。已初始化的幼兔重新入树不会再次覆盖保存的成年上限。成年兔初始化不变。

未修改公共 `classes/ball.gd`、`scripts/world.gd`、暴击粒子绘制、繁殖特效/音频资源或真正战斗伤害规则。繁殖冷却/数量上限、出生位置、幼兔比例、5.2 秒成长及按当前生命比例长大保持原样。不加临时无敌，也不借用死亡回归标记屏蔽战斗。

## 实际验证

使用独立 `Godot.4.7.2.offline.exe`，没有关闭或替换用户正在运行的游戏/Steam 编辑器。

1. `tests/test_rabbit_birth_feedback.gd`：真实 World、真实兔子场景和生命 setter，分别覆盖普通对战和发育期；出生前保证战斗反馈启用、出生位置在画面内，防止用“画外/暂停”得到假通过。
   - 修改前 **58 项 / 8 失败**：两种模式各重现 145→36 的伪伤害、镜头请求、暴击粒子和受击抖动。
   - 修改后 **58 项 / 0 失败**：幼兔 36/36、成年上限 145、正确体型/元数据、六个爱心和原繁殖音效、初始成年伙伴、幼兔立刻可受真实伤害、半血成长到 73/145。
   - 真正 50 点伤害不出暴击粒子；60 点伤害仍有粒子和正常重击镜头。没有为了修复繁殖而禁用正常反馈。
2. `tests/test_rabbit_birth_render.gd`：D3D12 / RTX 4060 真实 GPU 渲染，实际 World Camera2D，镜头聚焦与粒子仍开启；90 帧内触发两次繁殖并生成两只真实幼兔。
   - **8 项 / 0 失败**。
   - 全 90 帧镜头 zoom 差值 **0**、镜头位置差值 **0**、伤害推镜权重 **0**、暴击粒子数 **0**、伪扣血事件 **0**。
   - 保存第 0/13/25/49/65/89 帧与逐帧 JSON，已目视检查第 25 帧：两只成年兔、36 血幼兔、繁殖爱心正常。
3. 现有未提交的 `tests/test_dev_rabbit_knife.gd`：**14 项 / 0 失败**，发育分区、合并后繁殖、原点定位修复与短刀实际判定均保持。该文件仅运行，未修改或纳入本次提交。
4. 修改的兔子脚本语言服务诊断：0 错误/警告。

累计 **80 项 / 0 失败**。验证摘要：`tests/rabbit_birth_feedback_validation.json`。

这是单机受控夹具测试（冻结角色移动以隔离出生事件）和真实 GPU 镜头测试，不是双客户端联机验收或大规模性能验收。原项目 `set_rgb_color.gdshader` 的 UID/大小写警告仍存在，本次未扩大修复范围。

GPU 原始文件：`user://rabbit_birth_feedback/`；启动示例：

```text
Godot.4.7.2.offline.exe --path E:/godot/polo-balls --headless --script res://tests/test_rabbit_birth_feedback.gd
Godot.4.7.2.offline.exe --path E:/godot/polo-balls --script res://tests/test_rabbit_birth_render.gd
```

## 本地回退范围

- 更新前 HEAD：`280a721a5169a17d8540ddfe60124964415cf45c`。
- 标签：`checkpoint/rabbit-birth-before-20260924` / `checkpoint/rabbit-birth-ready-20260924`。
- 独立原始备份和测试日志：`E:/godot/polo-balls-checkpoints/rabbit_birth_feedback_20260924_104546/`；其中 `before/` 是更新前实际工作树文件，`head/` 是原提交版本，`completion.json` 记录提交结果。
- 兔子脚本原本已有其他任务的未提交出生位置/发育分区改动；本次只暂存幼兔生命初始化的三个精确修改块。MCP_CONTEXT.md 也只暂存本次一行索引。其他工作保持原样，不能把本次提交当作整个工作区快照。
- 回退前先备份当前工作区，撤销 ready 标签对应的本次提交即可撤销本次生命初始化修复；如 Git 因同文件未提交修改拒绝操作，应按本次提交的兔子初始化差异逐块反向应用，保留外部出生位置与发育逻辑。不要用旧文件整份覆盖、`reset --hard` 或 `clean -fd`。
- 原来已经运行的游戏进程可能仍持有旧脚本；请重新启动该游戏实例后验证。
