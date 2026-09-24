# 附魔效果与接入边界（Java 43 种）

等级 `n` 必须是整数 **1–32767**；不同附魔可同时附在任意对象上，不设装备类别/互斥限制。数值越大增益或抑制越强；有些效果本质是开关（能否卸下/是否消失/是否掉原方块），达到 1 级后核心行为不再变化。实体数量、位移、范围、持续时间等另有执行安全上限。所有事件统一调用 `MCEnchantments.resolve_event(object,event,context)` 返回修改后的**副本**；必须由该事件的权威结算者应用，不会凭返回值自行生成系统中不存在的水、钓鱼、背包、耐久或经验。

**已接实时通用战斗入口**：`ball._on_hitbox_on_hit` 在受击前读取攻击者/所附子武器的输出附魔；`ball.take_damage` 在扣盾/生命前读取受击者防御附魔；附魔组件监听 Hitbox/Hurtbox 的合法接触，对荆棘、击退、燃烧及节肢减速/眩晕作一次效果。其他技能的非 Hitbox 特殊攻击仍须在自己的权威命中处调用 `resolve_event`。本次没有逐角色改写攻击脚本或实现所有缺失玩法。对象在场景内自动寻找到最近的 `ball` 祖先；多个子装备同名附魔取最高等级，不会重复乘算。

| 附魔 | 游戏中的效果与触发条件 | 当前接线 |
| --- | --- | --- |
| 水下速掘 Aqua Affinity | 水下采集速度按 `1+0.12n` 增长，执行上限 12 倍 | `mine(underwater)`；采集系统待接 |
| 节肢杀手 Bane of Arthropods | 近战对标记 `mc_creature_family=arthropod` 的目标加 `n` 伤害；命中短暂眩晕（上限 3 秒） | 标准 Hitbox 已接；目标须有分类标记 |
| 绑定诅咒 Curse of Binding | 活着不能从装备栏卸下；死亡后可处理 | `equipment(alive)`；装备栏待接 |
| 爆炸保护 Blast Protection | 爆炸伤害除以 `1+0.08n`，冲击力另除以 `1+0.035n` | 带 `element=explosion` 的空间伤害已接减伤；击退倍率需施术者读取 |
| 破甲 Breach | 近战穿透 `1−1/(1+0.12n)` 的护甲减伤，最多 90% | 标准 Hitbox 已接；仅穿护甲，不跳过其他免疫 |
| 引雷 Channeling | 潮湿三叉戟命中请求一次落雷，半径随 n 增大（封顶 120） | `on_hit(mode=trident,wet)`；三叉戟技能调用者待接公共雷电能力 |
| 致密 Density | 重锤下坠攻击每单位落距附加 `0.5n` 伤害 | `damage_out(mode=smash,fall_distance)`；重锤下砸待接 |
| 深海探索者 Depth Strider | 水中移动速度增幅 `0.05n`，最多 4 倍 | `move(in_water)`；水域移动待接 |
| 效率 Efficiency | 采集速度增幅 `0.12n`，最多 12 倍 | `mine`；采集待接 |
| 摔落保护 Feather Falling | 摔落伤害除以 `1+0.10n` | `damage_in(element=fall)`；坠落调用者须标注类型 |
| 火焰附加 Fire Aspect | 近战命中使敌人灼烧 `0.7n` 秒（最长 12 秒）、每跳伤害随 n 增至安全上限 | 标准 Hitbox 已接，复用现有灼烧状态与火抗 |
| 火焰保护 Fire Protection | 火焰伤害除以 `1+0.08n`；燃烧时间另减 | 带火焰类型的受击已接减伤；外部燃烧时长需读取倍率 |
| 火矢 Flame | 远程接触命中点燃敌人，时长/伤害同火焰附加 | 标准远程 Hitbox 已接；自定义箭矢需主动接入 |
| 时运 Fortune | 采矿每个基础掉落最多增加 `n` 件，总增加数量封顶 64 | `mine`；掉落系统待接 |
| 冰霜行者 Frost Walker | 靠近水面时可冻结半径约 `0.3n`，最多 8 世界单位 | `move(near_water)`；水面修改待接 |
| 穿刺 Impaling | 湿润三叉戟命中附加 `0.6n` 伤害 | `damage_out(mode=trident,wet)`；三叉戟技能待接 |
| 无限 Infinity | 射普通箭不消耗弹药 | `shoot(is_arrow)`；弹药系统待接 |
| 击退 Knockback | 近战接触后击退距离 `8n`，最多 220，复用公共击退控制器 | 标准 Hitbox 已接 |
| 抢夺 Looting | 击杀物品掉落倍率 `1+0.08n`，经验倍率 `1+0.04n` | `on_kill`；统一死亡掉落待接 |
| 忠诚 Loyalty | 掷出三叉戟回归速度增幅 `0.1n`，最多 5 倍 | `projectile`；三叉戟飞行待接 |
| 海之眷顾 Luck of the Sea | 钓鱼宝藏权重变为 `1+0.1n` | `fishing`；钓鱼待接 |
| 疾冲 Lunge | 长矛突刺移动速度增幅 `0.12n`，最多 5 倍 | `projectile`；长矛突刺待接 |
| 饵钓 Lure | 钓鱼上钩等待除以 `1+0.1n` | `fishing`；钓鱼待接 |
| 经验修补 Mending | 获得经验时优先修复缺失耐久，每点经验修复 `2×(1+0.05n)`，不超过缺口 | `experience`；经验/耐久待接 |
| 多重射击 Multishot | 一次发射 `1+2n` 枚，执行上限 9 枚 | `shoot`；连发生成待接 |
| 穿透 Piercing | 箭矢可继续击中至多 n 个额外目标，执行上限 32 | `shoot`；贯穿追踪待接 |
| 力量 Power | 远程伤害乘以 `1+0.10n` | 标准远程 Hitbox 已接；技能自带伤害仍需主动接入 |
| 弹射物保护 Projectile Protection | 弹射物伤害除以 `1+0.08n` | 标准远程 Hitbox 已接；自定义弹丸需标注元素 |
| 保护 Protection | 通用直击伤害除以 `1+0.045n` | `ball.take_damage` 已接 |
| 冲击 Punch | 远程击退距离 `6n`，最多 220 | 标准远程 Hitbox 已接 |
| 快速装填 Quick Charge | 装填等待除以 `1+0.10n` | `shoot`；弩装填待接 |
| 水下呼吸 Respiration | 氧气消耗除以 `1+0.12n`，水下视距最多 3 倍 | `oxygen/visual`；氧气条/水域视觉待接 |
| 激流 Riptide | 湿润状态下持三叉戟突进速度增幅 `0.1n`，最多 5 倍 | `projectile(wet)`；三叉戟突进待接 |
| 锋利 Sharpness | 近战每次额外 `0.5n` 伤害 | 标准 Hitbox 已接 |
| 精准采集 Silk Touch | 采掘时返回方块自身而非普通材料 | `mine`；方块采集/掉落待接 |
| 亡灵杀手 Smite | 近战对标记 `mc_creature_family=undead` 的目标额外 `n` 伤害 | 标准 Hitbox 已接；目标须有分类标记 |
| 灵魂疾行 Soul Speed | 在灵魂方块上移动速度增幅 `0.05n`，最多 4 倍 | `move(on_soul)`；地面类型待接 |
| 横扫之刃 Sweeping Edge | 标为横扫的近战攻击额外获得 `0.08n×基础伤害` | `damage_out(sweeping)`；横扫技能需传入标记 |
| 迅捷潜行 Swift Sneak | 潜行移动速度增幅 `0.05n`，最多 4 倍 | `move(sneaking)`；潜行待接 |
| 荆棘 Thorns | 接触受击时反弹 `0.8n` 伤害，不通过 Hitbox 再触发自己 | 标准 Hurtbox 已接，剑等子装备也可装备 |
| 耐久 Unbreaking | 使用时消耗耐久的概率为 `1/(1+n)`，随机值由使用者提供 | `wear(roll)`；耐久扣除点待接 |
| 消失诅咒 Curse of Vanishing | 死亡后不掉落此物品 | `equipment/on_kill`；物品掉落待接 |
| 风爆 Wind Burst | 重锤落地击飞距离 `6n`，最多 240 | `smash`；重锤落地待接 |

**演示调用**：

```gdscript
const ENCHANT = preload("res://scripts/effects/我的世界/mc_enchantments.gd")
# 施术者的权威钓鱼结算：当前游戏尚无此系统，所以这里只展示接口。
var fishing:Dictionary = ENCHANT.resolve_event(rod,"fishing",{"base_wait":12.0})
var actual_wait:float = float(fishing.base_wait) * float(fishing.bite_wait_multiplier)
# 水/地形/背包/耐久等必须由对应系统读回并真正应用结果。
```

**验收边界**：规则夹具 `tests/test_mc_enchantment_rules.gd` 对照原始/一级 43/43 个 ID 均有可观察的事件结果，验证高等级防御和数量/位移上限；节点与光效夹具 `tests/test_mc_enchantments.gd` 验证 1–32767、非法 32768、任意装备组合。规则夹具不等于真实钓鱼、采矿等玩法测试；未在游戏中存在的系统明确标注待接，不宣称已经发生真实效果。
