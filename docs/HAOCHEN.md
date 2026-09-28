# 皓宸 / Haochen（我的世界分区）

现行规则（2026-09-28）。实现入口：`scripts/characters/我的世界/皓宸.gd`、`scenes/characters/我的世界/皓宸.tscn`；复制施放：`scripts/effects/我的世界/character_copy_request.gd` + `scenes/effects/我的世界/角色复制请求.tscn`；音频：`scripts/characters/我的世界/haochen/audio.gd`。

## 玩法

- **外观**：用户提供的两张我的世界皮肤（雷古勒斯 / 雷古勒斯笑）只取完整头部正面（脸 8,8–16,16 叠加帽子层 40,8–48,16），16 倍最近邻放大为 128×128。**体型为标准人物的一半**：尺寸由公共 `CharacterAutoFit` 决定（标准最长边 205 本地单位≈41 世界 px），皓宸场景覆盖 `visual_size_multiplier = 0.5`（最长边 102.5≈20.5px）与 `collision_min_size = (80,80)`，碰撞框随之由 180×168 减半为 90×84（2026-09-28 用户要求“缩小到二分之一”；手写 Image.scale 会被自动适配覆盖，不再使用）。**蓄能（CHARGING）和满条施放（COPYING）期间显示笑脸**，其余时间与死亡后为普通脸；由已同步的 `charge_phase` setter 切换，各端一致，无额外 RPC。
- **能量条**：身体下方复用苦力怕同源 `frontier/creeper_style_bar.gd::paint/below_body`（紫色填充，施放中转白）。容量 100。
- **蓄能**：半径 80 内每个敌方可选角色/自主子实体每秒提供 20 能量（权威端 0.08 秒扫描）。友军、自己的复制品、纯投射物/障碍不提供。最后不足容量的能量按在场提供者平分，不受遍历顺序影响。
- **减速/恢复**：蓄能时主动移速在 2 秒内线性降到 30% 下限（不为 0）；附近无敌人时 2 秒内恢复到 100%。只缩放自驱移动，击退/牵引/地表速度不缩放。离开范围保留已积累能量与贡献记录。
- **满条复制**：复制“本轮”累计贡献最多的人物（例：A 提供 60、B 提供 40 → 复制 A）；平局取最早开始贡献者。施放 0.65 秒，经公共 `begin_battle_spawn / apply_battle_spawn_identity / finish_battle_spawn` 票据生成原场景的**全新实例**（不是染色假人）。成功后清零并重新计分，失败/取消不消耗满条，0.5 秒后重试；已有复制品不被替换、无隐藏数量上限。
- **复制品**：黑白画风——真实 shader 灰度（`Set_RGB_Color.gdshader` 的 `character_grayscale` 实例参数；无材质的子节点用 `shaders/character_monochrome.gdshader`），不是灰色 modulate；原角色材质不受影响。**除移速外**公共数值减半：Max_health / Damage / Health_Restore / max_block / max_energy 向上取整×0.5，Damage_reduction×0.5，生命/护盾/能量按新上限满额；Speed 不变。攻击/技能冷却保持原值（减半冷却等于加强，不按“数值减半”处理）；技能参数不改。
- **附属**：Master=皓宸、同队，共用皓宸原 setup 的战斗存续身份；皓宸死亡后已确认的施放仍可完成，复制品继续继承原身份，不新增席位。
- **手控**：蓄能与复制都是被动，C 手控不绑定按键（`player_control_action_ids()` 为空）。
- **威胁显示**：只注册 80 半径蓝色检测圈（`haochen_energy_detection`），无伤害区域；皓宸本体无接触伤害。

## 粒子与音效

- **粒子**：全部复用公共原版 portal `generic_0..7` 粒子（`scripts/effects/我的世界/末影粒子.gd`），全局上限 320，纯视觉、每端各自生成：
  - **蓄能粒子流**：CHARGING 时，每个正在供能的敌人（最多 4 个）每 0.05 秒向皓宸流入 3 颗（尺寸 3.2），分组 `MCHaochenChargeParticle`。各端按已同步的 `charge_phase` 与位置本地判断，纯视觉。
  - **被复制者 → 皓宸 连线**：施放期间沿两人之间的线段生成粒子并流入皓宸（开场在被复制者身边 16 颗，之后每 0.03 秒 6 颗，尺寸 4.0），分组 `MCHaochenLinkParticle`。两端点 `link_from/link_to` 由权威端每物理帧按被复制者和皓宸真实位置刷新并同步，客户端只按同步点绘制；被复制者中途死亡则停在最后位置。
  - 两种粒子流共用 `character_copy_request.gd::emit_stream`（同一原版粒子、颜色、上限），不复制实现。
  - 施放点汇聚（开场 10 颗，之后每 0.1 秒 2 颗）与完成时 22 颗向外爆散，分组 `MCHaochenCopyParticle`。
- **音效**（全部走公共 `mc_native_audio.queue_stream`，权威端选择变体并可靠 RPC 同步、带序号防重播）：
  - 开始蓄能：用户提供的 `haochen/charge_start.wav`（0 dB，同一段蓄能只播一次）
  - **复制施放起手：原版 `entity.evoker.prepare_summon`（`唤魔者/evoker.prepare_summon_1.ogg`，0 dB）**——2026-09-28 新增
  - 复制完成：原版末影人 teleport 两个变体（0 dB）
  - 脚步（石头步声，仅真实位移）、待机（唤魔者 ambient，仅 RESTING，间隔≥实际音频时长）、受伤/死亡（唤魔者）；死亡同时保留项目默认 `DeadBell`
- 皓宸本身不造成伤害，无 MC 命中音；复制品的命中音由其原角色自身逻辑负责。
- 来源/哈希：`audio/characters/我的世界/haochen/SOURCE.json`（含两张头像、原始皮肤与处理方式）。原始皮肤保存在 `Images/characters/我的世界/皓宸/skins/`（`.gdignore`，不导入）。唤魔者头像已不再使用；待机/受伤/死亡仍用唤魔者原版声音。

## 分类

`classes/combat_classification_catalog.gd`：皓宸 `character / attack_modes none / carriers none / damage_kinds []`；复制请求 `effect / confirmed_spawn_ticket / no_damage`。

## 验证

见 `tests/HAOCHEN_20260928.md`。
