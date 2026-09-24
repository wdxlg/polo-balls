# Minecraft Java 1.21.4 状态效果统一目录（39 种）

## 公共入口

`res://scripts/effects/我的世界/mc_status_effects.gd` 是**唯一等级与强度计算表**：

```gdscript
const MC_EFFECTS = preload("res://scripts/effects/我的世界/mc_status_effects.gd")
MC_EFFECTS.apply_effect(target, "speed", 2, 8.0, caster) # 迅捷 II，8 秒
MC_EFFECTS.apply_effect(target, "minecraft:regeneration", 1, INF, caster)
MC_EFFECTS.clear(target, "speed", caster) # 仅移除该来源
var all_39: Array[String] = MC_EFFECTS.all_java_ids()
var base: Dictionary = MC_EFFECTS.properties("mining_fatigue", 3)
```

- 等级从 **1** 开始（原版命令的 amplifier 0 对应等级 I）；有限秒数、`INF`、施法者可以各自指定。`regen` / `instant_heal` 是旧女巫入口的兼容名；接受原版 `regeneration` / `instant_health` 以及 `minecraft:` 前缀。`all_java_ids()` 返回原版 39 个 ID。
- **数值只由效果种类与等级决定**。源之间不叠算相同效果：一个目标只存在一个节点；每个施加者保留自己的等级和时长，优先显示最高等级（同等级显示较长者），强来源失效后恢复仍有效的来源。目标自身的正／负面效果倍率与治疗／伤害反转仍按项目原有公共协议处理，不能用施法者特例改变等级强度。
- 女巫药瓶沿用无限生命恢复／中毒、凋零及其独立虚弱 6.5 秒、隐身 6 秒、迅捷／力量／缓慢 8 秒；信标仍只抽 **五种一级主效果**并维持 6 秒；凋零头颅和玫瑰的凋零为 3 秒；潜影贝飘浮仍为 3 秒。持续时间**不是**等级公式的一部分。
- 真实信息框从唯一状态节点读取种类、等级与实际剩余时间；39 种图标位于既有 `Images/UI/minecraft_tooltips/mob_effect/`，中英名称共用目录；瞬时状态没有假倒计时，女巫无限状态仍显示 `∞`。录制镜像复用真实时间，演示盔甲架仍仅供 UI 展示。

## 已落地的等级计算及规则

| 原版效果 | 等级 I、II／公式 | 项目落地 |
|---|---|---|
| 迅捷／缓慢 | 移动 ×(1+0.20×等级)／×max(0,1−0.15×等级) | `Buff.Speed`，不同施法者不重复叠加 |
| 急迫／挖掘疲劳 | 攻速 +(10%×等级)／−(10%×等级) | `Attack_Cooling` 倒数；按用户指定挖掘疲劳降低**攻速**而非虚构挖矿玩法 |
| 力量／虚弱 | 近战伤害 +(3×等级)／−(4×等级) HP | 同一个 `Buff.Damage` 加法；凋零的冲撞是近战，头颅／信标射线不加虚构远程伤害 |
| 抗性提升 | 承伤减少 min(20%×等级,100%) | 同一 `Buff.Damage_reduction`；凋零不再另算 −10% |
| 生命提升／伤害吸收 | 最大生命 +4×等级；临时额外承伤 4×等级 HP | 生命上限 Buff；先消耗临时生命再进入真实生命（普通／原始伤害都适用） |
| 瞬间治疗／伤害 | 治疗 4×2^(等级−1)／伤害 6×2^(等级−1) HP | 一次结算，不留下假状态；保留目标自身的治疗／伤害反转 |
| 生命恢复／中毒／凋零 | 每次 1 HP；周期分别 max(1,50≫(等级−1))、max(1,25≫(等级−1))、max(1,40≫(等级−1)) 游戏刻（20刻/秒） | 中毒不会低于 1 HP；凋零可致死；头颅、玫瑰与女巫的同级凋零同强度，绝不按受害者最大生命百分比改变 |
| 飘浮 | 向上加速度随等级线性增长 | 原有真实定向重力及天花板阻挡，等级更高重力相应增强；不改变施加者选的秒数 |
| 防火／水下呼吸／潮涌能量 | 防火免火；后两者免溺水 | 防火接入 `ball.get_fire_effect_ratio()`；`ball.receive_spatial_damage()` 对 `{"element":"drowning"}` 拒伤（项目**尚无氧气条/主动溺水源**），不免普通水攻击 |
| 缓降 | 末端下落速度限定 | 有下降速度的角色限制为每刻 0.125 格（16px 格子为 40px/s） |
| 虫蚀／渗浆／盘丝／蓄风 | 受伤有 10% 概率生成 1–2 蠹虫；死亡 2 只小史莱姆、3 张蛛网或一次击退波；等级不改变触发几率／数量 | 虫蚀召唤已有的蠹虫；盘丝生成可减速的 20 秒蛛网 Area2D，持有者免疫；蓄风调用真实击退。**渗浆小史莱姆只在独立的 `new5` 史莱姆场景资源存在时才能生成**；当前工作区有该资源，但它属于另一个尚未提交的功能，故本次提交不包含它。缺资源时不会报错、不会虚构替代怪物；请勿把单独检出的本提交称为已具备渗浆召唤。|

其余状态也**在 39 种目录中具备原版名称、图标、等级属性、可刷新的真实时长和查询接口**：跳跃提升（每级跳跃强度 +0.1、跌落伤害减 1 HP）、失明、黑暗、夜视、反胃、发光、海豚的恩惠、幸运、霉运、饥饿、饱和、不祥之兆、袭击之兆、试炼之兆、村庄英雄等。项目目前没有通用跳跃接口、昼夜/水下视野、眩晕镜头、玩家氧气/饥饿/饱和度、可挖掘方块、捕鱼掉落、村庄/袭击/试炼事件；**不把这些没有对应系统的环境／事件效果偷偷换成战斗增益，也不声称原版场景玩法已实现**。监守者当前仍只有既有召唤画面暗化，**未**自动给目标施加黑暗状态；需要实际目标与持续伤害/视觉机制时再接 `MC_EFFECTS.apply_effect()`。

## 验证与局限（2026-09-24）

项目根目录使用本地 Godot 4.7.2 离线构建。相关脚本：

```powershell
& ..\polo-balls-tools\offline-engine\runtime\Godot.4.7.2.offline.exe --headless --path . --script tests/test_mc_unified_status_effects.gd
& ..\polo-balls-tools\offline-engine\runtime\Godot.4.7.2.offline.exe --headless --path . --script tests/test_mc_active_potion_tooltips.gd
& ..\polo-balls-tools\offline-engine\runtime\Godot.4.7.2.offline.exe --headless --path . --script tests/test_wither_live.gd
& ..\polo-balls-tools\offline-engine\runtime\Godot.4.7.2.offline.exe --headless --path . --script tests/test_wither_beacon_revision.gd
& ..\polo-balls-tools\offline-engine\runtime\Godot.4.7.2.offline.exe --path . --script tests/test_recording_mc_effect_tooltips.gd
```

- 新统一目录独立夹具 **109/0**：39 个图标／双语名／两级计算，真实跨源共享、来源时长切换、挖掘疲劳 II 的实战攻速降低及其他属性 Buff、火焰／溺水／伤害吸收／缓降、盘丝蛛网减速与清理；渗浆召唤在上述可选场景存在时验证，**不是独立提交可保证的机制**。女巫／信标／凋零／潜影贝状态框 **47/0**，凋零命中 **55/0**，信标 **44/0**，水平接触及凋零粒子 **61/0**。基础框 **49/0**、语言 **40/0**。
- **新夹具直接继承 `SceneTree`，无需 `new5` 的临时测试父类**。部分上述旧回归夹具依赖当前工作区中另一个会话尚未纳入 Git 的 `scripts/training/test_mc_new5.gd`，其结果是当前工作树验证，不代表单独检出本提交后旧夹具一定可独立运行。
- 真实 NVIDIA RTX 4060 Laptop GPU、D3D12 / Forward+ 双语录像 **45/0**，实时和模拟模式都生成中英两份视频，并逐像素核对录制中的真实状态框；文件仅在测试专用 Godot `user://recordings/tooltip_recording_test/`，未提交。
- **没有跑双客户端联机**；状态施加、衍生召唤与死亡波以权威端结算，凋零信标沿原有外观 RPC 同步计时，其他非信标状态尚不能宣称客户端已完整复制。Godot 运行中可见既有 shader 文件大小写/UID 警告，部分旧凋零场景卸载有资源泄漏警告，不能误记为本次断言失败。
