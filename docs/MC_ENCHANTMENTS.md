# 全项目通用附魔数据与原版流光

附魔目录、数据、原版风格流光已接入；现有**41 种按事件触发的效果规则**及标准接触战斗链路（不含绑定诅咒、消失诅咒）。伤害、保护、荆棘、近/远程点燃与击退，以及水中移速和攻速增益已接入对应通用战斗入口；钓鱼、氧气、采矿、装备栏、经验等项目目前没有的玩法只有规则接口，待对应系统接入后才会在对局中生效。逐项效果、等级公式与实际接线边界见 `docs/MC_ENCHANTMENT_EFFECTS.md`。不提供附魔台、获取途径或游戏内附魔按钮；现有对象不会被自动赋予附魔。三叉戟原有专用视觉保留。

## 使用入口

适用于任意项目 `Node`，包括非 Minecraft 角色、武器、投射物、道具、障碍及 UI 容器。附魔数据在该对象的直属子组件中；纯逻辑节点也可储存数据，**只有下列支持的可绘制节点**才产生可见流光：`Sprite2D`、`AnimatedSprite2D`、`Polygon2D`、`TextureRect`、`ColorRect`。组件会递归扫描对象下的这些绘制节点，随动态创建、删除、帧切换、纹理更换与可见性变化更新；视觉叠层不修改原图或碰撞。实战附效另由 `ball.gd` 的权威命中入口触发。非此列表的自定义 `_draw`、粒子、3D 模型等目前只有数据，没有自动视觉适配。

**场景编辑器配置**：在目标对象下创建 `Node` 子节点，附加 `res://scripts/effects/我的世界/mc_enchantments.gd`，在 Inspector 的 `enchantments` 字典填入 `ID: 1–32767 整数等级`，例如 `thorns: 17`、`lunge: 200`。节点名称可自定，组件入场后会校验并规范化 ID。保存场景时按 Godot 正常保存该子节点。运行时增删用 API；仅手工修改字典并不会立即刷新光效。

**脚本配置**（`item` 可以是任意 `Node`，无需类型标记）：

```gdscript
const ENCHANT = preload("res://scripts/effects/我的世界/mc_enchantments.gd")
const CATALOG = preload("res://scripts/effects/我的世界/mc_enchantment_catalog.gd")

ENCHANT.apply(item, "minecraft:thorns", 17) # 剑也可附荆棘；自动创建子组件
ENCHANT.apply(item, "lunge", 200)            # 任意组合，等级 1–32767
var levels:Dictionary = ENCHANT.levels_of(item) # 返回副本，例如 {"thorns":17,"lunge":200}
ENCHANT.remove(item, "thorns")                # 删除单项；删完最后一项清除光效

var component:Node = ENCHANT.ensure(item)      # 获取/创建同一个直属子组件
component.replace_all({"protection":999,"sharpness":8}) # 批量替换并刷新
# component.set_level("unbreaking", 1000) / component.remove_level("lunge")

var entries:Array[MCPreviewEnchantment] = ENCHANT.preview_entries(item)
# entries 可交给已有的 mc_effect_tooltip.gd 展示；不自动创建 UI。
print(CATALOG.display_line("thorns",17)) # 荆棘 XVII
```

目录 `mc_enchantment_catalog.gd` 包含 41 个 ID 的中英名称，含 `lunge`（疾冲）；`binding_curse` 和 `vanishing_curse` 已移除，旧存档中的这两个 ID 不再被接受。接受裸 ID 或 `minecraft:` 前缀、大小写与外侧空白；未知 ID、0/负数和超过 **32767** 的等级不写入。**不实施原版装备类别与互斥限制**：例如剑可同时带荆棘、保护、疾冲。若需读取目录，用 `CATALOG.all_ids()`、`display_name(id, english)`、`display_level(level)`；超出罗马数字常见范围（3999）的等级显示十进制，避免巨长字符串。

光效复用已有三叉戟的 Mojang `Images/characters/我的世界/native_frames/trident_masks/enchanted_item_glint.png` 及独立的通用 canvas shader `mc_enchantment_glint.gdshader`；按绘制节点形状叠加双向流动，不为无附魔对象增加负担。按场景暂停及 `/root/Game.now_stop_state` 暂停流动；**效果部分**由 `mc_enchantment_effects.gd` 解析，标准命中由 `ball.gd` 结算。纹理来源、固定版本和许可见同目录 `ENCHANT_GLINT_SOURCE.json`；Shader 仅是本项目的 2D 适配，不声称精确复刻原版 3D 渲染。

## 验证与边界

- Godot 4.7.2 headless：在工程根目录用 `Godot.4.7.2.offline.exe --headless --script res://tests/test_mc_enchantments.gd`，**109/109** 通过（2026-09-25）。覆盖 41 个名称/ID、1–32767 等级、已移除诅咒的拒绝、不限类别/互斥组合、手动子组件及命名冲突、动态纹理/动画、多种绘制节点、暂停、移除、原版纹理哈希。`tests/test_mc_enchantment_rules.gd` 的纯规则测试 **66/66**，`tests/test_mc_enchantment_rebalance.gd` 的实际场景战斗测试 **27/27**（穿盾、反伤及致命反击、保护、近/远程、实战属性 Buff 及出水清理）。各测试分别用相同 `--headless --script` 命令执行。
- 官方 Godot 图形模式（不要加 `--headless`）：`godot.windows.opt.tools.64.exe --path . --script res://tests/test_mc_enchantments_visual.gd`。渲染显示回读结果：流光像素 4096、9 秒相位变化像素 3884、PNG 写入成功（`user://mc_enchantments_visual/enchanted.png`）；已查看样图呈紫色交错动态纹理，不再是整块纯紫。此为独立绘制样本，不代表所有实战场景已逐一画面验收；支持列表之外的渲染机制需单独接视觉适配，特定场景若另有遮罩、裁剪或子视口也应以实机画面验收。
- 回退只针对本次附魔组件、目录、纯规则、测试、文档及 `classes/ball.gd` 中本次附魔命中/扣血的**局部差异**；项目工作区中其他未提交任务的改动不随本次提交回退。
