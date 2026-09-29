# 人物方式 / 随机抽取 / 地图生成方块

## 1. 人物方式

设置 → 训练页：**人物方式**位于原来的“模式”上方。

- **自定义**：默认值。保留原有选人、未选人物时随机、单击及长按框选放置行为。
- **随机**：设置下方显示现有的人物分类开关；新配置中全部关闭。只从开启分类的角色并集中等概率抽取，允许重复，不受选人面板当前分类或已选人物影响。
- 所有分类关闭时不能放置，也不会回退到“全部人物”。分类选择与人物方式沿用现有设置保存机制。
- 随机模式下，单击/框选放置的是统一虚影，不运行人物脚本，不参与碰撞、伤害或胜负。右键可删除虚影，Reset 可清空。
- **按 M 收起工具栏**后出现独立方形阵容面板，不显示“命运抽选”等顶部装饰标题。全部席位从开始就显示，未揭晓为 `?`，人物揭晓后留在原格子中，不再替换上一位。手动/计时按队伍分区，轮放展示双方出场队列，Boss 模式优先突出所选 Boss 队伍。底部使用 Minecraft Java 1.21.4 官方客户端原版经验条贴图切片重组：N 人显示 N 段，每揭晓一人填满一段，超过 45 人换行；旁边显示已揭晓/总人数。贴图来源和哈希见 `Images/UI/minecraft_xp/SOURCE.json`。所有席位揭晓并完成实例化后，才放行战斗。
- “加速揭晓”只加快展示，不跳过人物生成；抽选中 M / ESC 不会绕过战斗锁。抽选前已手动暂停的对局，结束后仍保持暂停。
- 随机身份按完整场景路径记录，避免跨分类同名人物误加载。重打复用已揭晓阵容，不重新抽人。
- 可与手动、轮放、计时、Boss 模式组合。抽完后回到各模式原有启动流程；Boss 开场仍由原设置控制。
- 已放置的虚影不会因临时切换为自定义而丢失，仍在收起工具栏时处理；若抽取前把分类全部关闭，将保留席位并提示重新开启分类。

## 2. 在地图中画生成方块

已在 `scenes/world.tscn` 中加入：

```text
Map_Portal
├─ Character_Spawners   ← 新节点，与 Portal_Characters 平级
├─ Portal_Characters
└─ ...
```

这个节点是独立的 `TileMapLayer`，**不是传送门，也不是地图地面**。刷怪格子不参与岛屿范围、墙体、导航或遮挡计算。

### 最短设置步骤

1. 选中 `Map_Portal/Character_Spawners`。
2. 在 Inspector 的 **Character Table** 中增加元素，新建 `CharacterSpawnEntry`。
3. 展开条目，把需要生成的人物 `.tscn` 拖到 **Character**；可继续增加角色并设置 **Weight**。
4. 使用 Godot 的 TileMap 绘制工具，选择绿色方块，在地图内部画出生成点。
5. 运行游戏，选择 `Map_Portal`，收起工具栏。默认每 3 秒，每个绘制方块尝试生成 1 位人物。

节点默认没有预画方块、角色表也为空，避免自动改变已有地图的对战。两个条件都配置后才开始生成。

### 其它地图

- 将 `res://scenes/character_spawner_tiles.tscn` 实例化到对应地图节点下面，或在“添加节点”中选择 `CharacterSpawnerTiles`。
- **所属地图就是生成节点所在的地图**，完全根据父节点层级自动识别，不需要填写地图名，也不提供 `Target Map` 属性。支持普通 TileMapLayer 地图和 PortalMap，以及地图内的嵌套容器。
- 放在 `Map_Portal` 下就只在该地图选中时生效；移动到 `Map_Portal2` 下就自动归属后者。切到其它地图停止生成；未放在任何地图内的节点不生成。
- 每个图层有独立名单、队伍、时钟、上限；需要不同队伍或不同刷新速度时，复制图层分别配置。

### 属性速查

| 属性 | 含义 / 默认值 |
|---|---|
| Spawning Enabled | 生成开关，默认开启 |
| Only During Battle | 默认开启：手动模式收起工具栏后生成；轮放/计时/Boss 正式开战后生成。关闭则选中地图时即可生成，但仍服从暂停和抽选锁 |
| Character Table | `CharacterSpawnEntry` 列表；条目可以禁用。权重 0 不会被选中；正权重相对分配概率 |
| Spawn Team | 队伍名，如 `Team0` / `Team1`；空为无队伍，`random` 为随机现有队伍 |
| Spawn Interval | 生成间隔，默认 3 秒；运行时至少 0.05 秒 |
| Initial Delay | 激活后的首次等待，默认 0 |
| Spawn Immediately | 默认开启；关闭时首次额外等待一个完整间隔 |
| Spawn Count | 每个选中格子每轮尝试生成数量，默认 1 |
| Cell Selection | 每个方块 / 整层轮流一个方块 / 整层随机一个方块 |
| Frame Spawn Budget | 每物理帧最多尝试实例化数量，默认 4；大批量绘制分帧处理 |
| Max Alive | 本图层当前存活上限，默认 32；死亡或删除后释放名额 |
| Max Alive Per Cell | 每个方块当前存活上限，默认 4 |
| Max Total | 累计成功生成上限，默认 0（无限补充） |
| Character Scale | 人物整体缩放，默认 1 |
| Random Seed | 非 0 为固定的选人/选格/偏移随机序列 |
| Randomize Position / Position Jitter | 是否在格内随机偏移及偏移幅度；默认在格子中心生成 |
| Min Spawn Distance / Position Attempts | 与现存人物最小距离及尝试次数；找不到空间时跳过本次，不强塞 |
| Require Inside Map | 默认开启，地图外格子不会生成 |
| Show Spawn Markers / Marker Color | 运行时显示生成点轮廓及颜色 |
| Reset On Map Change | 离开所属地图时重置计数、波次和时钟，默认开启 |
| Despawn On Map Change | 随上述重置移除该图层已生成角色，默认开启 |

**三个数量上限均以 0 表示不限制。** 存活上限仅统计该图层直接生成的根角色，不包含人物技能自行召唤的子单位。多个图层之间不共用额度。

世界 Reset / 重打会重置生成器。地图刷出的角色不写入玩家布阵阵容，也不会套用“玩家布阵人物自动复活”的额外规则。暂停不会积攒需要瞬间补发的历史波次。

## 3. 文件与验证

主要实现：

- `scripts/random_character_draft.gd`：池、席位、抽取时序、暂停和服务端结果同步。
- `scripts/ui/random_character_placeholder.gd`：固定虚影。
- `scripts/ui/random_character_draw_overlay.gd`：独立抽选界面。
- `classes/character_spawn_entry.gd`：角色表条目。
- `addons/character_spawner/character_spawner_tiles.gd`：可绘制生成节点。
- `scenes/character_spawner_tiles.tscn`：可复用节点场景。

逻辑回归（在工程目录执行，将 `<godot.exe>` 换成实际路径）：

```powershell
& <godot.exe> --headless --path . --script res://tests/test_random_character_draft.gd
& <godot.exe> --headless --path . --script res://tests/test_character_spawner_tiles.gd
```

回归脚本使用轻量人物场景，覆盖分类过滤、默认值、空池、固定虚影、右键删除、抽取锁、取消、各战斗模式衔接、地图匹配、生成时序、分帧预算、三种数量上限、位置变换和重置。不依赖全量 Minecraft 冷资源预热。

视觉检查（需要真实窗口 / GPU，不作为逻辑回归证据）：

```powershell
& <godot.exe> --path . --resolution 540x960 --audio-driver Dummy --script res://tests/preview_random_character_draw.gd
```

该脚本在 `tests/` 保存设置页、虚影布阵、抽选界面的 JPG。多人路径已按现有 authority / RPC 机制接入；双客户端网络时序不属于这两项单进程回归的覆盖范围。

### 本轮执行结果（2026-09-20，Godot 4.7.2）

- `RANDOM_CHARACTER_DRAFT checks=58 failures=0`
- `CHARACTER_SPAWNER_TILES checks=44 failures=0`（含取消手动目标地图属性、嵌套归属、移动到另一地图、未归属地图时停产的补充回归；测试使用独立节点，不改写已绘制方块和角色表。）
- 真实 GPU / Forward+ 窗口完成三张截图，并人工检查了设置顺序、固定虚影、卡牌抽取布局；最新三项验证日志无 `SCRIPT ERROR` / `ERROR:`。
- 编辑器导入及窗口启动另有现存资源引用的 UID 回退、着色器路径大小写警告。没有为消除这些警告而改动无关资源；跨大小写敏感平台导出前仍应单独检查这些旧引用。
- 未做全人物资产穷举、双客户端联机或跨平台导出测试。

