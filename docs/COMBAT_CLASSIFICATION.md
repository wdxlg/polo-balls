# 全项目运行时分类与结算接入

2026-09-26。由用户在静态审计后明确授权实施：补齐分类，并统一已确认的实际结算问题。

## 已落地的入口

- `classes/combat_classification_catalog.gd`：显式资源注册表，覆盖当前 **277个游戏场景、601个运行脚本/组件**。包括161个角色场景、动态 `.new()` 实体、UI/系统及公共组件；不把测试、插件、第三方示例当作游戏角色。场景按 `scenes/`、`global/`、`ui/` 清点；脚本按 `classes/`、`scripts/`、`global/`、`ui/`、`Images/characters/` 清点，仅训练目录的测试/预览命名前缀排除。`visual_pixel_sampler.gd` 是运行组件，不再因文件名前缀被误排除。
- `classes/combat_classification.gd::profile_of(node)`：任意节点的公共查询；`ball.get_combat_classification()` 是角色便捷入口。场景身份和脚本身份分别登记；基础场景被替换脚本时按实际脚本解析。无脚本的地图碰撞体、贴图/粒子和碰撞组件有引擎类型兜底；未知脚本资源不按名字猜火焰。
- `combat_classification.gd::is_projectile(node)`：投射物公共识别。`scripts/projectile_contact.gd`、ball运动朝向识别及远程受击反馈均接入，保留虚化策略。静态蜘蛛地网不再因Shooter类型被当作飞行弹体。
- `ball.receive_classified_positional_damage(damage,point,kind,ignore_block,source)`、`receive_classified_spatial_damage(damage,space,kind,ignore_block,raw_health)`：带类型的伤害入口。

### 多轴而不是互斥单标签

`entity_kind` 描述角色、自主子实体、投射物、障碍、地形、危险区、状态、效果、纯表现、系统或组件；`attack_modes` 与 `carriers` 是独立字段。每次伤害的 `damage_kind` 必须由该招式/阶段/分量明确提供，不能从整名角色的注册表摘要推导。

注册表中的 `damage_kinds` 是**现有调用能力摘要**；`ordinary_or_contextual` 不是合法伤害事件类型，不能传给结算入口。空的攻击摘要不表示“绝对没有攻击”。本轮补齐的是实体/组件注册，并接通已确认的伤害语义；**没有把全部复杂招式迁移成完整的逐招式配置资源**，也没有凭关键词把魔角猎人过载/爆炸等未确认语义改成火焰。

`stages` / `stage_field` 参数化描述阶段或模式，公共查询读取实时值，不缓存过期身份：

- 凑企鹅石头：`flying=true` 为投射物，落地后为障碍。
- 小丑场景物件：香蕉皮为环境接触地形，彩带为远程投射物。

这些差异登记在同一注册表，不在多个识别器复制角色特判。

## 实际结算改变

1. **空间上下文明确为火焰/寒冷时，必须经过对应倍率与免疫。** 修复了过去 `element="fire"/"cold"` 只传下去，却可能绕过元素倍率/免疫的路径；包括raw-health空间伤害。
2. 对派生类空间受伤覆写，只执行一次防御逻辑；开发中针对重入导致二次防御增加了失败复现并修正。原有 `receive_fire_*` 和 `receive_cold_*` 兼容入口委托同一个带类型分发器。倍率只计算一次，保留位置/方向防御、格挡、吸收护盾和原有派生受伤覆写。普通爆炸不默认变火焰。
3. **船载分摊保留类型。** 先分配未经过元素倍率的伤害，再由每名成员应用自己的火抗/寒冷倍率，避免船的倍率代替乘客倍率、火免乘客遭受普通扣血。不同普通/火焰分量有独立去重键；原有同一来源同帧的船体/座位重复覆盖保护保留。
4. 普通poison Buff、药水中毒/反转恢复、凋零跳伤标明对应语义和 `status_tick`。不改周期、等级、药水反转或中毒留1HP规则；现有减伤/吸收策略继续沿用原链。
5. 剑客和面包车匕首流血共用 `receive_internal_status_damage`：明确为内部流血，仅权威端扣血，保留原先绕过格挡/减伤/吸收和不重复闪白的规则。此入口只接受 `bleed`，不能拿来绕过火焰或寒冷免疫；叠层、刷新、时长与音效仍由原状态负责。
6. 新带类型入口拒绝未知类型、非有限伤害、矛盾的已知 `damage_kind`/`element` 及非权威端结算。嵌套命中使用独立空间上下文，结束恢复原元数据，不污染下一次伤害。

合法事件kind目前为 `ordinary/fire/cold/poison/wither/bleed/drowning/magic`；`physical`兼容映射为ordinary。登记语义不意味着凭空添加了每种状态的新抗性数值。旧 `element=projectile/explosion/fall` 继续作为附魔兼容上下文保留，不把投射物或爆炸当新元素。

## 新增内容接入范例

```gdscript
const CLASSIFICATION = preload("res://classes/combat_classification.gd")
var entity_info:Dictionary = CLASSIFICATION.profile_of(node)

# 火焰仍可用原有兼容函数。
victim.receive_fire_positional_damage(caster.attack_damage(0.5), hit_point, false, caster)

# 或明确给出独立的伤害语义、载体和空间。
victim.receive_classified_spatial_damage(
    caster.attack_damage(0.5),
    {"shape":"circle", "point":hit_point, "radius":24.0,
     "source":caster, "carrier":"area"},
    &"fire", false, false
)
```

这是结算入口，不代替实际敌我筛选、物理查询或范围命中判断。不能给整名混合角色设置一个“火焰开关”，然后让其所有攻击都变火焰。

新增脚本/场景需补注册表；有阶段差异用stages。运行覆盖闸门：

```text
python tests/verify_combat_classification_registry.py
Godot --headless --path . --script res://tests/test_combat_classification.gd
```

覆盖脚本是只读检查，不会自动按文件名填类型。禁止为了让测试通过而将游戏脚本改名为测试前缀来绕过清点。

## 验证与限制

专项回归 `test_combat_classification_regression.gd` 在修改前：6项检查中5项失败（另外1项确认真实船座夹具已挂接）；修改后6/6。

本轮还执行了：

- 分类注册、277场景覆盖、224个角色/子实体/投射物场景实例查询、倍率/免疫/raw-health、护盾、权威拒绝、药水火抗、阶段变化、内部流血、混合船载分摊及嵌套事件测试；**2762/2762通过**。
- 原生火焰18/18；虚化投射物接触68/68；MC统一状态137/137；船载手控41/41；扩展投射物25/25；雪傀儡投射物接触13/13。
- 旧角色装载审计：224/224装载成功；不等于224对象逐招实战验收。
- 注册覆盖检查：277场景、598脚本，缺项/失效项/非法身份均为0。

测试开发期间修正过夹具缺少max_block、药水目录调用参数顺序、探针文件父目录不存在等问题；这些失败不能算游戏缺陷。MCP中途断线后已恢复并重新核验。引擎既有shader UID/大小写警告仍存在；headless的dummy纹理反馈在部分测试运行中报告过Parameter t is null，未将其冒充GPU画面通过。

**本轮未做真实双客户端联机、GPU逐角色画面或录制验收。** 权威拒绝检查是在单机夹具中设置非本机authority验证，不冒充双端联机。注册和装载不代表每个角色每招的伤害语义、动画、范围和手控均已验收。

## 版本范围

工作区有其他任务的未提交更新。本轮只保存相关文件的前后检查点和可逆差异，不混入其他任务到main或清空原暂存区。检查点是**专项文件版本，不是整个项目可独立运行的完整快照**。

回退前先备份当前文件，并核对之后是否有新改动；仅反向应用本轮差异，不能直接覆盖整份共享ball/world/MCP文件，也不能使用reset --hard或clean。具体检查点ID和独立恢复材料见本轮交付记录。

## 2026-09-26 类别交互消费者补齐

此前分类登记不等于所有技能已读取分类。本次将悦灵、盾狗/铁丝网、磁铁、醉汉、末影人、镜子、凋零反射、羊毛、极速者、猪与剑客相关入口接至公共交互协议，并提供公共移动前拦截和原生接触结果处理。补入3个运行组件后为277场景/601脚本。

新增/修改对象必须同时完成身份/阶段登记与适用能力协议；不可再给每个角色追加具体弹体名。天陨主箭/落箭实际捕获、返还及伤害、旧弹体兼容和新无旧字段夹具已验证。火焰载荷类型在羊毛和原生返还过程中保留。规范见 `PROJECTILE_INTERACTIONS.md`，回归与局限见 `../tests/CATEGORY_INTERACTIONS_20260926.md`。

## 状态正负与净化（2026-09-27）

`entity_kind=status` 的基础/阶段声明须有 `status_polarity`（negative/positive/neutral/dynamic）和 `status_cleanup`（detach或无参清理方法名）。dynamic须提供可继承的 `get_status_effect_polarity()`；清理方法也会被登记检查验证。药水符号来自同一 `mc_status_effects.SPECS`，不是净化消费者自建名单。嵌入箭只有stage2为负面状态；飞行和插墙阶段不会删除。运行时协议、外部持有者、Buff语义及RPC规则见 [STATUS_CLEANSING.md](STATUS_CLEANSING.md)。
