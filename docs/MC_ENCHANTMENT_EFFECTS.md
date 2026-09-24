# 附魔效果与接入边界（41 种）

等级 `n` 必须是整数 **1–32767**；不同附魔可同时附在任意对象上，不设装备类别/互斥限制。绑定诅咒和消失诅咒已从目录与规则中移除，旧数据也不再接受。有些效果本质是开关（例如精准采集是否掉原方块）；实体数量、位移、范围、持续时间等另有执行安全上限。所有事件统一调用 `MCEnchantments.resolve_event(object,event,context)` 返回修改后的**副本**；必须由该事件的权威结算者应用，不会凭返回值自行生成系统中不存在的水、钓鱼、背包、耐久或经验。

**已接实时通用战斗入口**：`ball._on_hitbox_on_hit` 在权威命中处合并施术者、子装备与弹体的输出附魔，按真实近战/远程模式计算伤害、燃烧与击退；`ball.take_damage` 在扣盾/生命前读取受击者防御附魔，并在减伤后分出破甲穿盾伤害；命中结束后以受击者本次生命＋护盾实际损失触发**一次**荆棘反击。组件不再额外监听 Hitbox/Hurtbox，避免多装备/信号重复触发。`World.new_buff` 驱动攻速与水中移速，离水/卸下附魔后清理增益。其他技能的非 Hitbox 特殊攻击仍须在自己的权威命中处调用 `resolve_event`。本次没有逐角色改写攻击脚本或实现所有缺失玩法；多个子装备同名附魔取最高等级，不会重复乘算。

**水域与目标来源**：只有真实水域系统提供的 `is_in_water()` 或明确的运行时元数据 `in_water=true` 才算在水中；水主题背景不是水。由实际入水/出水逻辑负责切换标记。节肢判定支持 `mc_creature_family=arthropod`、角色的「节肢」标签，以及现有 Minecraft 角色脚本「蜘蛛」「蠹虫」。致密读取施术者的**当前 `Speed` 属性**（包括 Buff），不是速度向量/冲刺位移。减伤比例有封顶；破甲每级从 `Damage_reduction` 中**减去 5 个百分点**（最低 0），再让减伤后伤害的 `5%×n` 绕过护盾直接伤及生命；最终生命/护盾取实际整数损失计算荆棘。

| 附魔 | 游戏中的效果与触发条件 | 当前接线 |
| --- | --- | --- |
| 水下速掘 Aqua Affinity | **实际在水中**时攻击速度乘 `1+0.10n`，与效率的攻速加成相加，封顶 12 倍；不再加快采矿 | `attack_rate(in_water)`；`World.new_buff` 改变实际 `Attack_Cooling` |
| 节肢杀手 Bane of Arthropods | 对节肢目标的攻击伤害乘 `1+0.30n`；不再追加眩晕 | 标准近/远程命中已接；节肢判定见上 |
| 爆炸保护 Blast Protection | 爆炸伤害乘 `max(1−0.10n,0)`，冲击力倍率同上 | 带 `element=explosion` 的空间伤害已接减伤；击退倍率需施术者读取 |
| 破甲 Breach | 每级无视 **5 个百分点**的 `Damage_reduction`，并让减伤后伤害的 `5%×n` 穿过护盾直达生命；两项均封顶 100% | 标准近/远程命中已接；不跳过其他免疫或伤害类型抗性 |
| 引雷 Channeling | 潮湿三叉戟命中请求一次落雷，半径随 n 增大（封顶 120） | `on_hit(mode=trident,wet)`；三叉戟技能调用者待接公共雷电能力 |
| 致密 Density | 每级将施术者**当前 `Speed` 属性的 1%** 加到本次攻击伤害上；非下坠专用 | 标准命中已接；`damage_out(current_speed)` 可供其他技能调用 |
| 深海探索者 Depth Strider | 实际在水中时移动速度乘 `1+0.10n`，最多 4 倍；离水即取消 | `move(in_water)`；`World.new_buff` 改变实际 `Speed` |
| 效率 Efficiency | 攻击速度乘 `1+0.05n`，封顶 12 倍；不再加快采矿 | `attack_rate`；`World.new_buff` 改变实际 `Attack_Cooling` |
| 摔落保护 Feather Falling | 摔落伤害乘 `max(1−0.10n,0)` | `damage_in(element=fall)`；坠落调用者须标注类型 |
| 火焰附加 Fire Aspect | **仅近战**命中使敌人灼烧 `0.7n` 秒（最长 12 秒）、每跳伤害随 n 增至安全上限 | 标准近战命中已接，复用现有灼烧状态与火抗 |
| 火焰保护 Fire Protection | 火焰伤害与燃烧时长均乘 `max(1−0.10n,0)` | 带火焰类型的受击已接减伤；外部燃烧时长需读取倍率 |
| 火矢 Flame | **仅远程**命中点燃敌人，时长/伤害同火焰附加 | 标准远程命中已接；自定义箭矢需主动接入 |
| 时运 Fortune | 采矿每个基础掉落最多增加 `n` 件，总增加数量封顶 64 | `mine`；掉落系统待接 |
| 冰霜行者 Frost Walker | 靠近水面时可冻结半径约 `0.3n`，最多 8 世界单位 | `move(near_water)`；水面修改待接 |
| 穿刺 Impaling | 湿润三叉戟命中附加 `0.6n` 伤害 | `damage_out(mode=trident,wet)`；三叉戟技能待接 |
| 无限 Infinity | 射普通箭不消耗弹药 | `shoot(is_arrow)`；弹药系统待接 |
| 击退 Knockback | **仅近战**接触后击退距离 `8n`，最多 220，复用公共击退控制器 | 标准近战命中已接 |
| 抢夺 Looting | 击杀物品掉落倍率 `1+0.08n`，经验倍率 `1+0.04n` | `on_kill`；统一死亡掉落待接 |
| 忠诚 Loyalty | 掷出三叉戟回归速度增幅 `0.1n`，最多 5 倍 | `projectile`；三叉戟飞行待接 |
| 海之眷顾 Luck of the Sea | 钓鱼宝藏权重变为 `1+0.1n` | `fishing`；钓鱼待接 |
| 疾冲 Lunge | 长矛突刺移动速度增幅 `0.12n`，最多 5 倍 | `projectile`；长矛突刺待接 |
| 饵钓 Lure | 钓鱼上钩等待除以 `1+0.1n` | `fishing`；钓鱼待接 |
| 经验修补 Mending | 获得经验时优先修复缺失耐久，每点经验修复 `2×(1+0.05n)`，不超过缺口 | `experience`；经验/耐久待接 |
| 多重射击 Multishot | 一次发射 `1+2n` 枚，执行上限 9 枚 | `shoot`；连发生成待接 |
| 穿透 Piercing | 箭矢可继续击中至多 n 个额外目标，执行上限 32 | `shoot`；贯穿追踪待接 |
| 力量 Power | 远程伤害乘以 `1+0.10n` | 标准远程 Hitbox 已接；技能自带伤害仍需主动接入 |
| 弹射物保护 Projectile Protection | 弹射物伤害乘 `max(1−0.10n,0)` | 标准远程命中已接；自定义弹丸需标注元素 |
| 保护 Protection | 通用受击伤害乘 `max(1−0.05n,0)`；再与适用的专项保护相乘 | `ball.take_damage` 已接 |
| 冲击 Punch | **仅远程**击退距离 `6n`，最多 220 | 标准远程命中已接 |
| 快速装填 Quick Charge | 装填等待除以 `1+0.10n` | `shoot`；弩装填待接 |
| 水下呼吸 Respiration | 氧气消耗除以 `1+0.12n`，水下视距最多 3 倍 | `oxygen/visual`；氧气条/水域视觉待接 |
| 激流 Riptide | 湿润状态下持三叉戟突进速度增幅 `0.1n`，最多 5 倍 | `projectile(wet)`；三叉戟突进待接 |
| 锋利 Sharpness | 近战每次额外 `0.5n` 伤害 | 标准 Hitbox 已接 |
| 精准采集 Silk Touch | 采掘时返回方块自身而非普通材料 | `mine`；方块采集/掉落待接 |
| 亡灵杀手 Smite | 近战对标记 `mc_creature_family=undead` 的目标额外 `n` 伤害 | 标准 Hitbox 已接；目标须有分类标记 |
| 灵魂疾行 Soul Speed | 在灵魂方块上移动速度增幅 `0.05n`，最多 4 倍 | `move(on_soul)`；地面类型待接 |
| 横扫之刃 Sweeping Edge | 标为横扫的近战攻击额外获得 `0.08n×基础伤害` | `damage_out(sweeping)`；横扫技能需传入标记 |
| 迅捷潜行 Swift Sneak | 潜行移动速度增幅 `0.05n`，最多 4 倍 | `move(sneaking)`；潜行待接 |
| 荆棘 Thorns | 每级按该次**实际生命＋护盾总损失的 5%** 反击一次；反击仍经攻击者的正常受伤结算，不通过 Hitbox 再触发自己 | 标准命中末尾已接，剑等子装备也可装备 |
| 耐久 Unbreaking | 使用时消耗耐久的概率为 `1/(1+n)`，随机值由使用者提供 | `wear(roll)`；耐久扣除点待接 |
| 风爆 Wind Burst | 重锤落地击飞距离 `6n`，最多 240 | `smash`；重锤落地待接 |

**演示调用**：

```gdscript
const ENCHANT = preload("res://scripts/effects/我的世界/mc_enchantments.gd")
# 施术者的权威钓鱼结算：当前游戏尚无此系统，所以这里只展示接口。
var fishing:Dictionary = ENCHANT.resolve_event(rod,"fishing",{"base_wait":12.0})
var actual_wait:float = float(fishing.base_wait) * float(fishing.bite_wait_multiplier)
# 水/地形/背包/耐久等必须由对应系统读回并真正应用结果。
```

**验收边界**：规则夹具 `tests/test_mc_enchantment_rules.gd` 对照原始/一级 **41/41** 个 ID 均有可观察的事件结果，验证指定百分比、高等级防御与数量/位移上限（66/66）；节点与光效夹具 `tests/test_mc_enchantments.gd` 验证 1–32767、非法 32768、删除诅咒、任意装备组合（109/109）；场景实战夹具 `tests/test_mc_enchantment_rebalance.gd` 检查穿盾、致密、节肢、实际反伤与致命一击、实际 Buff/离水清理、近/远程灼烧与击退（27/27）。规则夹具不等于真实钓鱼、采矿等玩法测试；未在游戏中存在的系统明确标注待接，不宣称已经发生真实效果。
