# 我的世界角色的真实持续药水状态信息框

> 此文是**上一版实现与当时测试结果的历史记录**：当时女巫各效果强度及凋零百分比伤害尚未统一。当前 39 种原版等级公式、公共状态节点与最新验证请以 [`MC_UNIFIED_STATUS_EFFECTS.md`](MC_UNIFIED_STATUS_EFFECTS.md) 为准；以下旧数值不得再当作现行规则。

> 2026-09-25 补注：此页旧文中的“独立 CanvasLayer”“信标完整发射结束后才给效果”和“信标效果包含跳跃提升”已过期。真实状态框与演示药水／附魔框现共用**前景单位之下、地图地面之上**的世界画布层级，实测见 [`MC_EFFECT_TOOLTIPS.md`](MC_EFFECT_TOOLTIPS.md) 末节；凋零信标在**正式发射开始时**从四种效果中抽取一项，时序及效果池见 [`BEACON_CYCLE.md`](BEACON_CYCLE.md)。下方旧数据仍保留作历史对照。

## 范围与规则

- `scripts/ui/mc_active_effect_tooltip.gd` 是**实际受影响角色**身上的独立 `CanvasLayer`，借用 `MCPreviewTooltip` 的 Mojang 原版图标、逐行自适应背景、双语名称及右侧屏幕空间定位；不替换默认分区药水／附魔测试盔甲架的可编辑、纯展示数据。演示盔甲架若真被药水命中，两框共存并自动避让；附近空间不足时状态框缩放到另一侧的可用区域。
- 新框仅在真实状态存在时创建；逐帧读取源节点／Buff 的实际剩余时间，**状态集合变化才重建行**，语言切换与录像镜像不重新起表、不另造计时器。目标隐藏、死亡、离屏或状态消失时隐藏内容；新一轮状态可重新启用旧框。瞬间治疗／瞬间伤害没有伪倒计时；免疫导致未创建状态时没有伪信息框。
- 信标每次完整发射结束后仍随机给凋零**一项**持续 6 秒的一级主效果：迅捷、急迫、抗性提升、跳跃提升、力量。高级副效果「生命恢复」已从信标池及之前每秒回复生命的分支移除。已有速度、攻击间隔、减伤和伤害增益机制保持；凋零没有跳跃动作，跳跃提升仍显示原版主效果状态，但不凭空改变其飞行或冲撞数值。信标损毁时当前增益及框立即清除。
- 女巫按现有实装施药，不改变效果强度／时长：生命恢复和中毒为既有无限状态（显示 `∞`）；凋零药水的凋零、隐身各 6.5／6 秒；迅捷、力量、缓慢各 8 秒。凋零药另附带的**虚弱**从目标 `Buff_Dic` 内的「女巫_凋零虚弱」Buff 读其独立的 6.5 秒剩余时间，并非复用凋零时间。瞬间治疗／伤害不加持续行。刷新的状态更新原状态倒计时，已过期只删除对应行。
- 凋零头颅／爆炸及爆炸转化的凋零玫瑰都调用 `apply_wither`，目标读取同一个可刷新的 `WitherStatus.remaining`（3 秒）；潜影贝子弹已有的「飘浮」状态读 `mc_shulker_levitation` 指向的实际节点（3 秒，天花板提前终止时随节点隐藏），不重写战斗伤害机制。
- 左键实时／右键模拟录制对两个镜像分别采用自己的视口摄像机及 `zh`／`en` 内容；同一角色的演示框和状态框按顺序独立镜像、避让，同源实际时间拷贝到两份视频，游戏工具栏及暂停界面仍不录入。凋零的既有外观 RPC 现同时带上信标剩余秒数供远端显示，不再只发送增益名称。

## 其他角色审查与刻意未改之处

- 已纳入现有会真正施加原版药水状态的潜影贝「飘浮」。项目中的普通蜘蛛、普通骷髅、普通守卫者不是洞穴蜘蛛、流浪者或远古守卫者，不把它们的普通攻击虚构成中毒、缓慢或挖掘疲劳。雪傀儡当前「寒冷」是本项目自定义机制，也不冒充原版药水。
- 原版监守者会向附近玩家施加「黑暗」（[Mojang 的角色介绍](https://www.minecraft.net/en-us/article/warden)）。但当前项目 `scripts/characters/我的世界/frontier/warden_screen.gd` 仅有召唤时短暂的全屏暗化动画，**没有**按受影响角色计时的持续黑暗状态。用户明确选择本次只记录此发现，不添加虚假的黑暗倒计时；将来若要做，须先建立真正的受影响目标／刷新／结束机制，再接入本框。
- 女巫持续状态、凋零状态和潜影浮空节点主要由权威端创建；未做双客户端联机回归，**不可声称它们在另一客户端也正确复制**。凋零信标剩余时间虽进入既有 RPC，也只通过单实例夹具验了接收数据，尚未跑真正双机验证。

## 回归入口与本次结果

运行环境：项目根目录、Godot 4.7.2 编辑器构建 `..\polo-balls-tools\offline-engine\runtime\Godot.4.7.2.offline.exe`。日后仍须以对应版本重新运行，不把历史记录当作当前版本的自动保证。

```powershell
& ..\polo-balls-tools\offline-engine\runtime\Godot.4.7.2.offline.exe --headless --path . --script res://tests/test_mc_active_potion_tooltips.gd
& ..\polo-balls-tools\offline-engine\runtime\Godot.4.7.2.offline.exe --headless --path . --script res://tests/test_mc_effect_tooltips.gd
& ..\polo-balls-tools\offline-engine\runtime\Godot.4.7.2.offline.exe --headless --path . --script res://tests/test_mc_effect_tooltips_locale.gd
& ..\polo-balls-tools\offline-engine\runtime\Godot.4.7.2.offline.exe --headless --path . --script res://tests/test_wither_beacon_revision.gd
& ..\polo-balls-tools\offline-engine\runtime\Godot.4.7.2.offline.exe --path . --script res://tests/test_recording_mc_effect_tooltips.gd
```

- 真实战斗场景夹具 `test_mc_active_potion_tooltips.gd`：**47 项/0 失败**，五种信标一级图标与时长、死亡／过期／重发、RPC 剩余时间、女巫全部七种持续状态及额外虚弱、无限和有限剩余时间、语言切换、瞬间药与免疫不误显、凋零重复命中刷新和潜影浮空提前结束。
- 基础信息框 `test_mc_effect_tooltips.gd` **50 项/0 失败**（含同角色真假双框避让及隐藏）；双语 `test_mc_effect_tooltips_locale.gd` **40 项/0 失败**。凋零信标 `test_wither_beacon_revision.gd` **44 项/0 失败**，凋零 `test_wither.gd` 通过、`test_wither_live.gd` **55 项/0 失败**，开场 `test_wither_intro.gd` **26 项/0 失败**。
- 在真实 GPU（非 `--headless`）下执行 `test_recording_mc_effect_tooltips.gd`：**45 项/0 失败**。左键实时与右键模拟各生成中／英文一份 1080×1920 视频；每种模式都验证三源框（演示药水、附魔、受药目标）在两摄像机互不覆盖、英文名称和状态真实时间一致，并在实际编码输入图像切换单一状态镜像时逐像素测得中文 **3772**、英文 **4220** 个变化取样像素（本次测试帧）。视频位于测试专用 `user://recordings/tooltip_recording_test/`，不提交成片、生成缓存或其他会话的改动。
