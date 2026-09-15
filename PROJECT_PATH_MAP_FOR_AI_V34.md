# Godot 项目路径基准表（给 AI 使用）

> **用途：** 把本文件连同你要 AI 修改的项目文件一起上传。此表是目录结构基准。AI 必须优先遵守本表，不能因为某个文件/文件夹没有上传就自行创建同义目录、改大小写、移动资源或猜测缺失路径。
>
> **当前路径基准版本：V34 累计更新包。** V7 清单保留为历史基线；V34 新增/确认路径见文末“V34 累计新增与确认路径”。

## AI 必须遵守的硬规则

1. 项目根目录由 `project.godot` 所在目录定义；所有项目路径统一写成 `res://...`。
2. **“本次没有上传”不等于“不存在”。** 未上传的目录只能标记为“未知/未提供”，禁止据此新建替代目录。
3. 禁止创建这些已经发生过的同义/大小写重复目录：`Audio/`、`Audios/`、`Voices/`、`scripts/Characters/`、`scripts/Effects/`、`scripts/Shooter/`、`scripts/Audio/`、`scripts/UI/`、`images/`。
4. 当前规范目录以本表为准：声音只进 `audio/`；脚本只进 `scripts/` / `classes/` / `global/`；场景只进 `scenes/`；图片保持项目现有的 **`Images/` 大写 I**；UI 资源目录是项目根部 **`ui/` 小写**，而图片 UI 子目录是 **`Images/UI/` 大写 UI**。
5. 不要为了“统一命名”擅自把现有中文目录改成英文，也不要把 `Images/` 改成 `images/`。修改已有路径必须同时更新所有 `.gd/.tscn/.tres/.gdshader/project.godot` 中的 `res://` 引用。
6. 遇到清单中没有列出的资源引用时，先搜索项目内容；如果对应文件未随本次对话上传，明确写“需要用户补充该目录/文件”，不要生成一个同名空文件或新文件夹。
7. `.godot/`、`.import` 属于可再生成/导入数据，不把它们当作项目源资源目录结构的依据。
8. 新增资源前，先在本表和项目内搜索是否已有同用途目录。角色音频固定放 `audio/characters/<角色名>/`，角色脚本固定放 `scripts/characters/...`，角色场景固定放 `scenes/characters/...`。

## 项目根目录（当前基准）

```text
res://
├── addons/
├── audio/
├── classes/
├── fonts/
├── global/
├── Images/
├── particles/
├── scenes/
├── scripts/
├── shaders/
├── ui/
├── translations.csv
└── project.godot  # 项目根标识；若本次未上传，也不要创建第二个项目根
```

## 规范目录树（V7 基线 + V34 累计更新包确认）

```text
├── audio/
│   ├── characters/
│   │   ├── 三角洲/
│   │   ├── 伤心的男人/
│   │   ├── 保安/
│   │   ├── 储君/
│   │   ├── 兔子/
│   │   ├── 军官/
│   │   ├── 决斗者/
│   │   ├── 剑客/
│   │   ├── 咔咔/
│   │   │   ├── hurt/
│   │   │   └── skill/
│   │   ├── 小偷/
│   │   ├── 建筑工人/
│   │   ├── 异蛙寄生虫/
│   │   ├── 影子/
│   │   ├── 战士/
│   │   ├── 投资者/
│   │   ├── 拳击手/
│   │   ├── 收债人/
│   │   ├── 时光客/
│   │   ├── 服务员/
│   │   ├── 气球/
│   │   ├── 炮兵/
│   │   ├── 炸弹客/
│   │   ├── 牛/
│   │   ├── 猎人/
│   │   ├── 矿工/
│   │   ├── 背刺者/
│   │   ├── 蜜蜂术士/
│   │   ├── 观者/
│   │   ├── 赌徒/
│   │   ├── 键盘侠/
│   │   │   └── 键盘/
│   │   ├── 面包车/
│   │   ├── 黑帮老大/
│   │   ├── 醉汉/
│   │   ├── 月计/
│   │   │   ├── 殷红迷雾/
│   │   │   └── 伞夫/
│   │   ├── meme/
│   │   │   └── 凑企鹅/
│   │   └── 鼓手/
│   ├── sfx/
│   │   ├── boss/
│   │   ├── combat/
│   │   ├── physics/
│   │   ├── shooter/
│   │   ├── 我的世界/
│   │   ├── 战斗/
│   │   ├── 枪/
│   │   │   └── 单发/
│   │   ├── 脚步/
│   │   └── 防御/
│   ├── status/
│   │   ├── buff/
│   │   └── debuff/
│   ├── system/
│   └── ui/
│       ├── button/
│       └── slider/
├── classes/
├── global/
├── particles/
├── scenes/
│   ├── characters/
│   │   ├── 三角洲/
│   │   ├── 人物/
│   │   ├── 动物/
│   │   ├── 杀戮尖塔/
│   │   ├── 物品/
│   │   ├── 月计/
│   │   ├── meme/
│   │   └── 默认/
│   ├── creatures/
│   ├── effects/
│   ├── particle/
│   │   ├── 宿傩/
│   │   ├── 宿傩效果备份/
│   │   ├── 异蛙寄生虫/
│   │   └── 蜂群术士/
│   ├── shooter/
│   │   └── clown/
│   ├── terrain/
│   └── training/
├── scripts/
│   ├── audio/
│   ├── characters/
│   │   ├── RL/
│   │   ├── 三角洲/
│   │   ├── 动物/
│   │   ├── 杀戮尖塔/
│   │   ├── 月计/
│   │   ├── meme/
│   │   └── 默认/
│   ├── creatures/
│   ├── effects/
│   ├── shooter/
│   │   └── clown/
│   ├── status/
│   ├── terrain/
│   ├── training/
│   └── ui/
├── shaders/
│   └── ui/
└── ui/
    └── Button/
```

## Images/ 已知目录树（来自你提供的 Godot 文件系统截图）

> `Images/` 太大，没有完整上传。因此下面表示“已确认存在的路径”，**不是说没有列出的图片路径就不存在**。AI 不得根据缺失项自行重建 `Images/`。

```text
Images/
├── Base-01.png
├── bilibili.png
├── characters/
│   ├── 三角洲/
│   │   ├── 乌鱼兽/
│   │   ├── 红狼/
│   │   └── 青刺/
│   ├── 人物/
│   │   ├── 伤心的男人/
│   │   ├── 保安/
│   │   ├── 军火商/
│   │   ├── 决斗者/
│   │   ├── 剑客/
│   │   │   ├── 反击矩形.png
│   │   │   ├── 招架.png
│   │   │   ├── 挥剑.png
│   │   │   ├── 普通.png
│   │   │   └── 突刺.png
│   │   ├── 变形者/
│   │   ├── 国王/
│   │   ├── 小丑/
│   │   ├── 小偷/
│   │   ├── 影子/
│   │   ├── 投资者/
│   │   ├── 拳击手/
│   │   ├── 收债人/
│   │   ├── 时光客/
│   │   ├── 智者/
│   │   ├── 服务员/
│   │   ├── 极速者/
│   │   ├── 棋手/
│   │   ├── 气球/
│   │   ├── 炮兵/
│   │   ├── 炸弹客/
│   │   ├── 猎人/
│   │   ├── 矿工/
│   │   ├── 磁铁/
│   │   ├── 科学家/
│   │   ├── 背刺者/
│   │   ├── 裁判/
│   │   ├── 赌徒/
│   │   ├── 重女/
│   │   ├── 醉汉/
│   │   ├── 键盘侠/
│   │   ├── 镜子/
│   │   ├── 面包车/
│   │   ├── 黑帮老大/
│   │   └── 鼓手/
│   ├── 动物/
│   │   ├── 九头蛇/
│   │   ├── 兔子/
│   │   └── 猫/
│   ├── 布鲁斯/
│   ├── 建筑工人/
│   ├── 月计/
│   │   └── 殷红迷雾/
│   ├── meme/
│   │   └── 凑企鹅/
│   ├── 杀戮尖塔/
│   │   ├── masterful_stab.png
│   │   ├── 储君/
│   │   ├── 废墟雕刻师/
│   │   ├── 异蛙寄生虫/
│   │   ├── 战士/
│   │   ├── 猎人/
│   │   ├── 猎人杀手/
│   │   ├── 蜂群术士/
│   │   ├── 观者/
│   │   └── 门扉缔造者/
│   └── 默认/
│       └── 军官/
├── gdb-gamepad-2(all)/
├── paricle/
├── shooter/
│   ├── 炸弹客/
│   ├── meme/
│   └── 裁判牌/
│       └── Knife.png
├── Status/
│   ├── dazed.png
│   ├── demon_form.png
│   ├── infection.png
│   ├── Stun/
│   ├── wound.png
│   ├── 储君/
│   └── 观者/
├── terrain/
│   └── 矿工石头/
├── tiktok.png
├── UI/
│   └── BossIntro/
├── youtube.png
├── 未标题-1.png
├── 牛/
│   └── 吃草动画/
│       ├── 图层 2.png
│       ├── 图层 3.png
│       ├── 图层 4.png
│       ├── 牛犊子_冲刺.png
│       ├── 牛犊子_吃草.png
│       └── 牛犊子_慢走.png
└── 鼠标/
    ├── 鼠标点击.png
    └── 鼠标默认.png
├── DM_20260825172438_0...  # 截图中文件名被截断；禁止猜完整名称
```

## 目录职责速查

| 路径 | 用途 | 约束 |
|---|---|---|
| `res://audio/characters/<角色>/` | 角色专属语音/动作音效 | 不要把角色音频放回 `audio/` 根目录 |
| `res://audio/characters/月计/<角色>/` | 月计角色专属音频 | 已确认 `殷红迷雾/`、`伞夫/`；不要另建英文别名目录 |
| `res://audio/characters/meme/<角色>/` | meme 角色专属音频 | 已确认 `凑企鹅/`；`meme` 保持小写 |
| `res://audio/sfx/` | 通用 SFX | `boss/`, `combat/`, `physics/`, `shooter/`, `我的世界/`, `战斗/`, `枪/`, `脚步/`, `防御/` 已存在 |
| `res://audio/status/` | Buff/Debuff 状态音效 | 固定 `buff/`、`debuff/` |
| `res://audio/system/` | 系统音效 | — |
| `res://audio/ui/` | UI 音效 | 已有 `button/`、`slider/` |
| `res://scripts/characters/` | 角色逻辑 | 不创建 `scripts/Characters/` |
| `res://scripts/characters/月计/` | 月计角色逻辑 | 已确认 `月计理智角色.gd`、`殷红迷雾.gd`、`殷红迷雾视觉.gd`、`伞夫.gd`、`堇紫泪滴.gd` |
| `res://scripts/characters/meme/` | meme 角色逻辑 | 已确认 `凑企鹅.gd`、`棍母.gd`、`愤怒的普通人.gd`、`肌肉男.gd`；目录名固定为小写 `meme` |
| `res://scripts/creatures/` | 生物/召唤物脚本 | — |
| `res://scripts/effects/` | 效果脚本 | 不创建 `scripts/Effects/` |
| `res://scripts/shooter/` | 投射物/射击系统 | 不创建 `scripts/Shooter/` |
| `res://scripts/status/` | 状态脚本 | — |
| `res://scripts/terrain/` | 地形脚本 | — |
| `res://scripts/training/` | 训练/RL | — |
| `res://scripts/ui/` | UI 脚本 | 根目录 UI 资源仍在 `res://ui/` |
| `res://classes/` | 通用基类/组件类 | 不随意搬入 `scripts/characters/` |
| `res://global/` | Autoload/全局对象与全局场景 | 修改前检查 `project.godot` autoload |
| `res://scenes/characters/` | 角色场景 | 角色主体场景 |
| `res://scenes/characters/月计/` | 月计角色场景 | 已确认 `殷红迷雾.tscn`、`伞夫.tscn`、`堇紫泪滴.tscn` |
| `res://scenes/characters/meme/` | meme 角色场景 | 已确认 `凑企鹅.tscn`、`棍母.tscn`、`愤怒的普通人.tscn`、`肌肉男.tscn` |
| `res://scenes/creatures/` | 生物/召唤物场景 | — |
| `res://scenes/effects/` | 通用视觉/效果场景 | — |
| `res://scenes/particle/` | 粒子场景 | 注意项目原来就是单数 `particle` |
| `res://scenes/shooter/` | 投射物/射击场景 | — |
| `res://scenes/terrain/` | 地形场景 | — |
| `res://scenes/training/` | 训练/RL 场景 | — |
| `res://Images/` | 图片/贴图 | **I 大写，保持现状** |
| `res://Images/characters/月计/` | 月计角色图片 | 已确认 `殷红迷雾/`；堇紫泪滴图片附件尚未正式入项目，禁止猜路径 |
| `res://Images/characters/meme/` | meme 角色图片 | 已确认 `凑企鹅/`、`愤怒的普通人/`、`肌肉男/` |
| `res://Images/shooter/meme/` | meme 投射物图片 | 已确认 `凑企鹅石头.png` |
| `res://shaders/` | Shader | 已删除的 `伏魔御厨子.gdshader` 不得重新创建 |
| `res://shaders/ui/` | UI Shader | 已确认 `月计理智流动.gdshader` |
| `res://particles/` | 粒子材质/资源 | 与 `scenes/particle/` 不是同一目录 |
| `res://ui/` | UI 场景、主题、样式资源 | 与 `Images/UI/` 不同 |
| `res://fonts/` | 字体 | 本轮未完整上传；缺失时先向用户索取 |
| `res://addons/` | 第三方/插件 | 不搬到 scripts |

## 明确禁止重新创建/恢复的旧路径

```text
res://Audio/
res://Audios/
res://Voices/
res://images/
res://scripts/Characters/
res://scripts/Effects/
res://scripts/Shooter/
res://scripts/Audio/
res://scripts/Status/
res://scripts/UI/
res://shaders/伏魔御厨子.gdshader
res://scripts/audio/网络CC0音效.gd
```

## 给 AI 的处理协议（可直接作为提示词）

```text
你正在维护一个现有 Godot 4 项目。PROJECT_PATH_MAP_FOR_AI.md 是目录结构的权威基准。
任何本次未上传的文件或目录都必须视为“可能存在但未提供”，绝不能因为看不到它就新建同义目录或替代文件。
在新增/移动/重命名任何资源前：
1) 先查本路径表；
2) 再搜索当前已上传项目中的 res:// 引用和同名资源；
3) 如果目标目录已存在，只能使用已有目录；
4) 如果路径表确认该目录存在但本次未上传，要求用户补充文件，不要创建；
5) 任何路径修改必须同步修改所有文本资源引用，并严格保持大小写；
6) 禁止恢复“明确禁止重新创建/恢复的旧路径”列表中的内容。
输出修改结果时必须给出：旧路径 -> 新路径、删除项、创建项、未能确认项。
```

## V7 历史基线：已实际收到/生成的完整文件路径清单

> 下面是 V7 `project_parts/` 内实际存在的文件。它可以帮助 AI 判断“当前修复包真正包含了什么”。未列出 ≠ 原项目不存在。

```text
res://Images/characters/人物/服务员/服务员_弯腰请进状态.png
res://Images/characters/人物/服务员/服务员_弯腰请进状态.png.import
res://Images/characters/人物/服务员/服务员_普通状态.png
res://Images/characters/人物/服务员/服务员_普通状态.png.import
res://Images/characters/人物/炮兵/导弹.png
res://Images/characters/人物/炮兵/导弹.png.import
res://Images/characters/人物/炮兵/炮兵_指挥开火.png
res://Images/characters/人物/炮兵/炮兵_指挥开火.png.import
res://Images/characters/人物/炮兵/炮兵_普通状态.png
res://Images/characters/人物/炮兵/炮兵_普通状态.png.import
res://audio/characters/三角洲/我的浮木死了.mp3
res://audio/characters/三角洲/我的浮木死了.mp3.import
res://audio/characters/三角洲/蜂医新年快乐.mp3
res://audio/characters/三角洲/蜂医新年快乐.mp3.import
res://audio/characters/伤心的男人/下雨.mp3
res://audio/characters/伤心的男人/下雨.mp3.import
res://audio/characters/伤心的男人/雨滴撞伞1.mp3
res://audio/characters/伤心的男人/雨滴撞伞1.mp3.import
res://audio/characters/伤心的男人/雨滴撞伞2.mp3
res://audio/characters/伤心的男人/雨滴撞伞2.mp3.import
res://audio/characters/保安/保安_下车.mp3
res://audio/characters/保安/保安_下车.mp3.import
res://audio/characters/保安/保安_打电话.mp3
res://audio/characters/保安/保安_打电话.mp3.import
res://audio/characters/保安/保安_车喇叭.mp3
res://audio/characters/保安/保安_车喇叭.mp3.import
res://audio/characters/保安/保安_钢叉.mp3
res://audio/characters/保安/保安_钢叉.mp3.import
res://audio/characters/储君/mc锻造.ogg
res://audio/characters/储君/mc锻造.ogg.import
res://audio/characters/兔子/兔子繁殖.mp3
res://audio/characters/兔子/兔子繁殖.mp3.import
res://audio/characters/军官/打火机点火.mp3
res://audio/characters/军官/打火机点火.mp3.import
res://audio/characters/军官/核弹爆炸.wav
res://audio/characters/军官/核弹爆炸.wav.import
res://audio/characters/决斗者/剑戟（刺击、切割、拔刀）C-金属撞击声-尖叫声_爱给网_aigei_com.mp3
res://audio/characters/决斗者/剑戟（刺击、切割、拔刀）C-金属撞击声-尖叫声_爱给网_aigei_com.mp3.import
res://audio/characters/决斗者/嗖一下转场，唰，划走转场音，冲刺音_爱给网_aigei_com.wav
res://audio/characters/决斗者/嗖一下转场，唰，划走转场音，冲刺音_爱给网_aigei_com.wav.import
res://audio/characters/剑客/刺冲刺.mp3
res://audio/characters/剑客/刺冲刺.mp3.import
res://audio/characters/剑客/刺冲刺2.mp3
res://audio/characters/剑客/刺冲刺2.mp3.import
res://audio/characters/剑客/剑伤害.mp3
res://audio/characters/剑客/剑伤害.mp3.import
res://audio/characters/剑客/剑客刺击中.mp3
res://audio/characters/剑客/剑客刺击中.mp3.import
res://audio/characters/剑客/剑挥舞.mp3
res://audio/characters/剑客/剑挥舞.mp3.import
res://audio/characters/剑客/格挡1.mp3
res://audio/characters/剑客/格挡1.mp3.import
res://audio/characters/剑客/格挡2.mp3
res://audio/characters/剑客/格挡2.mp3.import
res://audio/characters/剑客/格挡3.mp3
res://audio/characters/剑客/格挡3.mp3.import
res://audio/characters/咔咔/hurt/kaka_hurt1.ogg
res://audio/characters/咔咔/hurt/kaka_hurt1.ogg.import
res://audio/characters/咔咔/hurt/kaka_hurt2.ogg
res://audio/characters/咔咔/hurt/kaka_hurt2.ogg.import
res://audio/characters/咔咔/hurt/kaka_hurt3.ogg
res://audio/characters/咔咔/hurt/kaka_hurt3.ogg.import
res://audio/characters/咔咔/skill/kaka_skill1.ogg
res://audio/characters/咔咔/skill/kaka_skill1.ogg.import
res://audio/characters/咔咔/skill/kaka_skill2.ogg
res://audio/characters/咔咔/skill/kaka_skill2.ogg.import
res://audio/characters/咔咔/skill/kaka_skill3.ogg
res://audio/characters/咔咔/skill/kaka_skill3.ogg.import
res://audio/characters/小偷/小偷_坏笑.mp3
res://audio/characters/小偷/小偷_坏笑.mp3.import
res://audio/characters/小偷/小偷_金币.mp3
res://audio/characters/小偷/小偷_金币.mp3.import
res://audio/characters/建筑工人/墙倒塌.wav
res://audio/characters/建筑工人/墙倒塌.wav.import
res://audio/characters/建筑工人/墙颤抖.wav
res://audio/characters/建筑工人/墙颤抖.wav.import
res://audio/characters/建筑工人/建墙.wav
res://audio/characters/建筑工人/建墙.wav.import
res://audio/characters/建筑工人/扔砖头.wav
res://audio/characters/建筑工人/扔砖头.wav.import
res://audio/characters/建筑工人/砖头摔倒.wav
res://audio/characters/建筑工人/砖头摔倒.wav.import
res://audio/characters/异蛙寄生虫/寄生.mp3
res://audio/characters/异蛙寄生虫/寄生.mp3.import
res://audio/characters/异蛙寄生虫/蛆爆浆.mp3
res://audio/characters/异蛙寄生虫/蛆爆浆.mp3.import
res://audio/characters/异蛙寄生虫/蛆爆炸.mp3
res://audio/characters/异蛙寄生虫/蛆爆炸.mp3.import
res://audio/characters/异蛙寄生虫/蛆生.mp3
res://audio/characters/异蛙寄生虫/蛆生.mp3.import
res://audio/characters/影子/喊叫.mp3
res://audio/characters/影子/喊叫.mp3.import
res://audio/characters/影子/喊叫_影子粗慢.wav
res://audio/characters/影子/喊叫_影子粗慢.wav.import
res://audio/characters/影子/影子喊叫.mp3
res://audio/characters/影子/影子喊叫.mp3.import
res://audio/characters/影子/影子喊叫_粗慢.wav
res://audio/characters/影子/影子喊叫_粗慢.wav.import
res://audio/characters/战士/战士Attack1.ogg
res://audio/characters/战士/战士Attack1.ogg.import
res://audio/characters/投资者/投资者_红条.mp3
res://audio/characters/投资者/投资者_红条.mp3.import
res://audio/characters/拳击手/拳击手_命中.mp3
res://audio/characters/拳击手/拳击手_命中.mp3.import
res://audio/characters/拳击手/拳击手_挥拳.mp3
res://audio/characters/拳击手/拳击手_挥拳.mp3.import
res://audio/characters/收债人/结账.mp3
res://audio/characters/收债人/结账.mp3.import
res://audio/characters/收债人/金币1.mp3
res://audio/characters/收债人/金币1.mp3.import
res://audio/characters/收债人/金币2.mp3
res://audio/characters/收债人/金币2.mp3.import
res://audio/characters/收债人/钞票.mp3
res://audio/characters/收债人/钞票.mp3.import
res://audio/characters/时光客/倒放.mp3
res://audio/characters/时光客/倒放.mp3.import
res://audio/characters/服务员/关门.mp3
res://audio/characters/服务员/关门.mp3.import
res://audio/characters/服务员/开门.mp3
res://audio/characters/服务员/开门.mp3.import
res://audio/characters/气球/充气.mp3
res://audio/characters/气球/充气.mp3.import
res://audio/characters/气球/爆炸.mp3
res://audio/characters/气球/爆炸.mp3.import
res://audio/characters/炮兵/呼叫.mp3
res://audio/characters/炮兵/呼叫.mp3.import
res://audio/characters/炮兵/导弹发射.mp3
res://audio/characters/炮兵/导弹发射.mp3.import
res://audio/characters/炮兵/爆炸.mp3
res://audio/characters/炮兵/爆炸.mp3.import
res://audio/characters/炸弹客/爆炸.mp3
res://audio/characters/炸弹客/爆炸.mp3.import
res://audio/characters/炸弹客/计时.mp3
res://audio/characters/炸弹客/计时.mp3.import
res://audio/characters/牛/牛叫.mp3
res://audio/characters/牛/牛叫.mp3.import
res://audio/characters/猎人/蛇叫.mp3
res://audio/characters/猎人/蛇叫.mp3.import
res://audio/characters/矿工/挥舞.mp3
res://audio/characters/矿工/挥舞.mp3.import
res://audio/characters/矿工/攻击.mp3
res://audio/characters/矿工/攻击.mp3.import
res://audio/characters/矿工/石子.mp3
res://audio/characters/矿工/石子.mp3.import
res://audio/characters/矿工/重击叠加.mp3
res://audio/characters/矿工/重击叠加.mp3.import
res://audio/characters/背刺者/恢复普通.mp3
res://audio/characters/背刺者/恢复普通.mp3.import
res://audio/characters/背刺者/进入背刺.mp3
res://audio/characters/背刺者/进入背刺.mp3.import
res://audio/characters/背刺者/飞刀命中.mp3
res://audio/characters/背刺者/飞刀命中.mp3.import
res://audio/characters/背刺者/飞刀掷出.mp3
res://audio/characters/背刺者/飞刀掷出.mp3.import
res://audio/characters/蜜蜂术士/bee1.mp3
res://audio/characters/蜜蜂术士/bee1.mp3.import
res://audio/characters/蜜蜂术士/bee2.mp3
res://audio/characters/蜜蜂术士/bee2.mp3.import
res://audio/characters/蜜蜂术士/bee3.mp3
res://audio/characters/蜜蜂术士/bee3.mp3.import
res://audio/characters/观者/Blue.ogg
res://audio/characters/观者/Blue.ogg.import
res://audio/characters/观者/Blue_loop.ogg
res://audio/characters/观者/Blue_loop.ogg.import
res://audio/characters/观者/God.ogg
res://audio/characters/观者/God.ogg.import
res://audio/characters/观者/God_loop.ogg
res://audio/characters/观者/God_loop.ogg.import
res://audio/characters/观者/Red.ogg
res://audio/characters/观者/Red.ogg.import
res://audio/characters/观者/Red_loop.ogg
res://audio/characters/观者/Red_loop.ogg.import
res://audio/characters/赌徒/卡壳.mp3
res://audio/characters/赌徒/卡壳.mp3.import
res://audio/characters/赌徒/左轮射击.mp3
res://audio/characters/赌徒/左轮射击.mp3.import
res://audio/characters/赌徒/装填.mp3
res://audio/characters/赌徒/装填.mp3.import
res://audio/characters/键盘侠/键盘/键盘敲击01.mp3
res://audio/characters/键盘侠/键盘/键盘敲击01.mp3.import
res://audio/characters/键盘侠/键盘/键盘敲击02.mp3
res://audio/characters/键盘侠/键盘/键盘敲击02.mp3.import
res://audio/characters/键盘侠/键盘/键盘敲击03.mp3
res://audio/characters/键盘侠/键盘/键盘敲击03.mp3.import
res://audio/characters/键盘侠/键盘/键盘敲击04.mp3
res://audio/characters/键盘侠/键盘/键盘敲击04.mp3.import
res://audio/characters/键盘侠/键盘/键盘敲击05.mp3
res://audio/characters/键盘侠/键盘/键盘敲击05.mp3.import
res://audio/characters/键盘侠/键盘/键盘敲击06.mp3
res://audio/characters/键盘侠/键盘/键盘敲击06.mp3.import
res://audio/characters/键盘侠/键盘/键盘敲击07.mp3
res://audio/characters/键盘侠/键盘/键盘敲击07.mp3.import
res://audio/characters/键盘侠/键盘/键盘敲击08.mp3
res://audio/characters/键盘侠/键盘/键盘敲击08.mp3.import
res://audio/characters/键盘侠/键盘/键盘敲击09.mp3
res://audio/characters/键盘侠/键盘/键盘敲击09.mp3.import
res://audio/characters/键盘侠/键盘/键盘敲击10.mp3
res://audio/characters/键盘侠/键盘/键盘敲击10.mp3.import
res://audio/characters/键盘侠/键盘/键盘敲击11.mp3
res://audio/characters/键盘侠/键盘/键盘敲击11.mp3.import
res://audio/characters/键盘侠/键盘/键盘敲击12.mp3
res://audio/characters/键盘侠/键盘/键盘敲击12.mp3.import
res://audio/characters/键盘侠/键盘/键盘敲击13.mp3
res://audio/characters/键盘侠/键盘/键盘敲击13.mp3.import
res://audio/characters/键盘侠/键盘/键盘敲击14.mp3
res://audio/characters/键盘侠/键盘/键盘敲击14.mp3.import
res://audio/characters/键盘侠/键盘/键盘敲击15.mp3
res://audio/characters/键盘侠/键盘/键盘敲击15.mp3.import
res://audio/characters/键盘侠/键盘/键盘敲击16.mp3
res://audio/characters/键盘侠/键盘/键盘敲击16.mp3.import
res://audio/characters/键盘侠/键盘/键盘敲击17.mp3
res://audio/characters/键盘侠/键盘/键盘敲击17.mp3.import
res://audio/characters/键盘侠/键盘/键盘敲击18.mp3
res://audio/characters/键盘侠/键盘/键盘敲击18.mp3.import
res://audio/characters/键盘侠/键盘/键盘敲击19.mp3
res://audio/characters/键盘侠/键盘/键盘敲击19.mp3.import
res://audio/characters/键盘侠/键盘/键盘敲击20.mp3
res://audio/characters/键盘侠/键盘/键盘敲击20.mp3.import
res://audio/characters/面包车/倒车.mp3
res://audio/characters/面包车/倒车.mp3.import
res://audio/characters/面包车/前进.mp3
res://audio/characters/面包车/前进.mp3.import
res://audio/characters/面包车/匕首刺.mp3
res://audio/characters/面包车/匕首刺.mp3.import
res://audio/characters/面包车/匕首命中.mp3
res://audio/characters/面包车/匕首命中.mp3.import
res://audio/characters/面包车/拳头命中.mp3
res://audio/characters/面包车/拳头命中.mp3.import
res://audio/characters/面包车/拳头挥舞.mp3
res://audio/characters/面包车/拳头挥舞.mp3.import
res://audio/characters/面包车/撞墙.mp3
res://audio/characters/面包车/撞墙.mp3.import
res://audio/characters/面包车/铁棍打人.mp3
res://audio/characters/面包车/铁棍打人.mp3.import
res://audio/characters/面包车/铁棍打墙.mp3
res://audio/characters/面包车/铁棍打墙.mp3.import
res://audio/characters/面包车/铁棍挥舞.mp3
res://audio/characters/面包车/铁棍挥舞.mp3.import
res://audio/characters/黑帮老大/吹哨1.mp3
res://audio/characters/黑帮老大/吹哨1.mp3.import
res://audio/characters/黑帮老大/吹哨2.mp3
res://audio/characters/黑帮老大/吹哨2.mp3.import
res://audio/characters/黑帮老大/吹哨3.mp3
res://audio/characters/黑帮老大/吹哨3.mp3.import
res://audio/characters/黑帮老大/扔钱.mp3
res://audio/characters/黑帮老大/扔钱.mp3.import
res://audio/characters/黑帮老大/收购.mp3
res://audio/characters/黑帮老大/收购.mp3.import
res://audio/characters/黑帮老大/跑路了兄弟.mp3
res://audio/characters/黑帮老大/跑路了兄弟.mp3.import
res://audio/characters/鼓手/鼓点01.mp3
res://audio/characters/鼓手/鼓点01.mp3.import
res://audio/characters/鼓手/鼓点02.mp3
res://audio/characters/鼓手/鼓点02.mp3.import
res://audio/characters/鼓手/鼓点03.mp3
res://audio/characters/鼓手/鼓点03.mp3.import
res://audio/characters/鼓手/鼓点04.mp3
res://audio/characters/鼓手/鼓点04.mp3.import
res://audio/characters/鼓手/鼓点05.mp3
res://audio/characters/鼓手/鼓点05.mp3.import
res://audio/characters/鼓手/鼓点06.mp3
res://audio/characters/鼓手/鼓点06.mp3.import
res://audio/sfx/boss/鞭子1.mp3
res://audio/sfx/boss/鞭子1.mp3.import
res://audio/sfx/boss/鞭子2.mp3
res://audio/sfx/boss/鞭子2.mp3.import
res://audio/sfx/boss/鞭子3.mp3
res://audio/sfx/boss/鞭子3.mp3.import
res://audio/sfx/combat/explosion1.sfxr
res://audio/sfx/combat/explosion1.sfxr.import
res://audio/sfx/physics/balls_collide1.sfxr
res://audio/sfx/physics/balls_collide1.sfxr.import
res://audio/sfx/physics/balls_hit1.sfxr
res://audio/sfx/physics/balls_hit1.sfxr.import
res://audio/sfx/shooter/Knife_throw.ogg
res://audio/sfx/shooter/Knife_throw.ogg.import
res://audio/sfx/我的世界/草放置.ogg
res://audio/sfx/我的世界/草放置.ogg.import
res://audio/sfx/我的世界/草破坏.ogg
res://audio/sfx/我的世界/草破坏.ogg.import
res://audio/sfx/战斗/加特林发射.mp3
res://audio/sfx/战斗/加特林发射.mp3.import
res://audio/sfx/战斗/加特林蓄力.mp3
res://audio/sfx/战斗/加特林蓄力.mp3.import
res://audio/sfx/战斗/子弹打人.mp3
res://audio/sfx/战斗/子弹打人.mp3.import
res://audio/sfx/战斗/子弹打墙.mp3
res://audio/sfx/战斗/子弹打墙.mp3.import
res://audio/sfx/战斗/捕兽夹放置.mp3
res://audio/sfx/战斗/捕兽夹放置.mp3.import
res://audio/sfx/战斗/捕兽夹触发.mp3
res://audio/sfx/战斗/捕兽夹触发.mp3.import
res://audio/sfx/战斗/火箭筒发射.mp3
res://audio/sfx/战斗/火箭筒发射.mp3.import
res://audio/sfx/战斗/火箭筒爆炸.mp3
res://audio/sfx/战斗/火箭筒爆炸.mp3.import
res://audio/sfx/战斗/狙击枪发射.mp3
res://audio/sfx/战斗/狙击枪发射.mp3.import
res://audio/sfx/战斗/狙击枪攻击.mp3
res://audio/sfx/战斗/狙击枪攻击.mp3.import
res://audio/sfx/战斗/霰弹枪上膛.mp3
res://audio/sfx/战斗/霰弹枪上膛.mp3.import
res://audio/sfx/战斗/霰弹枪攻击.mp3
res://audio/sfx/战斗/霰弹枪攻击.mp3.import
res://audio/sfx/枪/单发/MP7_单发.mp3
res://audio/sfx/枪/单发/MP7_单发.mp3.import
res://audio/sfx/枪/单发/g18_单发.mp3
res://audio/sfx/枪/单发/g18_单发.mp3.import
res://audio/sfx/脚步/脚步1.wav
res://audio/sfx/脚步/脚步1.wav.import
res://audio/sfx/脚步/脚步2.wav
res://audio/sfx/脚步/脚步2.wav.import
res://audio/sfx/脚步/脚步3.wav
res://audio/sfx/脚步/脚步3.wav.import
res://audio/sfx/脚步/脚步4.wav
res://audio/sfx/脚步/脚步4.wav.import
res://audio/sfx/脚步/脚步5.wav
res://audio/sfx/脚步/脚步5.wav.import
res://audio/sfx/脚步/脚步6.wav
res://audio/sfx/脚步/脚步6.wav.import
res://audio/sfx/脚步/脚步7.wav
res://audio/sfx/脚步/脚步7.wav.import
res://audio/sfx/防御/BlockAtt.ogg
res://audio/sfx/防御/BlockAtt.ogg.import
res://audio/sfx/防御/Defense1.ogg
res://audio/sfx/防御/Defense1.ogg.import
res://audio/sfx/防御/Defense2.ogg
res://audio/sfx/防御/Defense2.ogg.import
res://audio/sfx/防御/Defense3.ogg
res://audio/sfx/防御/Defense3.ogg.import
res://audio/sfx/防御/Defense4.ogg
res://audio/sfx/防御/Defense4.ogg.import
res://audio/sfx/防御/DefenseBreak.ogg
res://audio/sfx/防御/DefenseBreak.ogg.import
res://audio/status/buff/Buff1.ogg
res://audio/status/buff/Buff1.ogg.import
res://audio/status/buff/Buff2.ogg
res://audio/status/buff/Buff2.ogg.import
res://audio/status/buff/Buff3.ogg
res://audio/status/buff/Buff3.ogg.import
res://audio/status/debuff/Debuff1.ogg
res://audio/status/debuff/Debuff1.ogg.import
res://audio/status/debuff/Debuff2.ogg
res://audio/status/debuff/Debuff2.ogg.import
res://audio/status/debuff/Debuff3.ogg
res://audio/status/debuff/Debuff3.ogg.import
res://audio/system/dead_bell.wav
res://audio/system/dead_bell.wav.import
res://audio/system/stop_game.sfxr
res://audio/system/stop_game.sfxr.import
res://audio/system/胜利铃声.mp3
res://audio/system/胜利铃声.mp3.import
res://audio/ui/button/Button_Down1.ogg
res://audio/ui/button/Button_Down1.ogg.import
res://audio/ui/button/Button_Down2.ogg
res://audio/ui/button/Button_Down2.ogg.import
res://audio/ui/button/Button_Up_Mouse_Out.ogg
res://audio/ui/button/Button_Up_Mouse_Out.ogg.import
res://audio/ui/button/Mouse_Enter_Button1.ogg
res://audio/ui/button/Mouse_Enter_Button1.ogg.import
res://audio/ui/slider/Slider1.ogg
res://audio/ui/slider/Slider1.ogg.import
res://audio/ui/stop_text_click.ogg
res://audio/ui/stop_text_click.ogg.import
res://classes/ball.gd
res://classes/ball.gd.uid
res://classes/buff.gd
res://classes/buff.gd.uid
res://classes/health_bar.gd
res://classes/health_bar.gd.uid
res://classes/hitbox.gd
res://classes/hitbox.gd.uid
res://classes/hurtbox.gd
res://classes/hurtbox.gd.uid
res://classes/particles.gd
res://classes/particles.gd.uid
res://classes/state_machine.gd
res://classes/state_machine.gd.uid
res://global/audios.gd
res://global/audios.gd.uid
res://global/audios.tscn
res://global/game.gd
res://global/game.gd.uid
res://global/game.tscn
res://global/注释.gd
res://global/注释.gd.uid
res://particles/bee.tres
res://particles/hit_white_points_material.tres
res://scenes/ball.tscn
res://scenes/characters/三角洲/夺舍狼.tscn
res://scenes/characters/三角洲/背刺鼠.tscn
res://scenes/characters/人物/NC佬.tscn
res://scenes/characters/人物/伤心的男人.tscn
res://scenes/characters/人物/保安.tscn
res://scenes/characters/人物/军官.tscn
res://scenes/characters/人物/军火商.tscn
res://scenes/characters/人物/决斗者.tscn
res://scenes/characters/人物/剑客.tscn
res://scenes/characters/人物/变形者.tscn
res://scenes/characters/人物/国王.tscn
res://scenes/characters/人物/小丑.tscn
res://scenes/characters/人物/小偷.tscn
res://scenes/characters/人物/布鲁斯.tscn
res://scenes/characters/人物/建筑工人.tscn
res://scenes/characters/人物/影子.tscn
res://scenes/characters/人物/投资者.tscn
res://scenes/characters/人物/拳击手.tscn
res://scenes/characters/人物/收债人.tscn
res://scenes/characters/人物/时光客.tscn
res://scenes/characters/人物/智者.tscn
res://scenes/characters/人物/服务员.tscn
res://scenes/characters/人物/极速者.tscn
res://scenes/characters/人物/棋手.tscn
res://scenes/characters/人物/炮兵.tscn
res://scenes/characters/人物/炸弹客.tscn
res://scenes/characters/人物/猎人.tscn
res://scenes/characters/人物/矿工.tscn
res://scenes/characters/人物/磁铁.tscn
res://scenes/characters/人物/科学家.tscn
res://scenes/characters/人物/背刺者.tscn
res://scenes/characters/人物/裁判.tscn
res://scenes/characters/人物/赌徒.tscn
res://scenes/characters/人物/醉汉.tscn
res://scenes/characters/人物/重女.tscn
res://scenes/characters/人物/键盘侠.tscn
res://scenes/characters/人物/镜子.tscn
res://scenes/characters/人物/雨衣男.tscn
res://scenes/characters/人物/面包车.tscn
res://scenes/characters/人物/黑帮老大.tscn
res://scenes/characters/人物/鼓手.tscn
res://scenes/characters/动物/九头蛇.tscn
res://scenes/characters/动物/兔子.tscn
res://scenes/characters/动物/牛.tscn
res://scenes/characters/动物/牛犊子.tscn
res://scenes/characters/动物/猫.tscn
res://scenes/characters/杀戮尖塔/小刀猎.tscn
res://scenes/characters/杀戮尖塔/异蛙寄生虫.tscn
res://scenes/characters/杀戮尖塔/异蛙寄生虫_小.tscn
res://scenes/characters/杀戮尖塔/战士.tscn
res://scenes/characters/杀戮尖塔/猎人杀手.tscn
res://scenes/characters/杀戮尖塔/虔诚雕刻师.tscn
res://scenes/characters/杀戮尖塔/蛇咬相生猎.tscn
res://scenes/characters/杀戮尖塔/蜂群术士.tscn
res://scenes/characters/杀戮尖塔/观者.tscn
res://scenes/characters/杀戮尖塔/锻剑储君.tscn
res://scenes/characters/杀戮尖塔/门扉缔造者.tscn
res://scenes/characters/物品/气球.tscn
res://scenes/characters/默认/bilibili.tscn
res://scenes/characters/默认/test_ball.tscn
res://scenes/characters/默认/tiktok.tscn
res://scenes/creatures/九头蛇_头.tscn
res://scenes/creatures/储君_sword.tscn
res://scenes/creatures/军火商_枪.tscn
res://scenes/creatures/布鲁斯_狗.tscn
res://scenes/creatures/建筑工人_墙.tscn
res://scenes/creatures/投稿随从.tscn
res://scenes/creatures/猎人_捕兽夹.tscn
res://scenes/creatures/门扉缔造者_手.tscn
res://scenes/damage_text.tscn
res://scenes/debug_in_hit.tscn
res://scenes/effects/stun_visual.tscn
res://scenes/effects/兔子繁殖特效.tscn
res://scenes/health_bar.tscn
res://scenes/node_2d.tscn
res://scenes/particle.tscn
res://scenes/particle/Attack_white_points.tscn
res://scenes/particle/gpu_particles_2d.tscn
res://scenes/particle/宿傩/捌.tscn
res://scenes/particle/宿傩/解.tscn
res://scenes/particle/宿傩效果备份/领域.tres
res://scenes/particle/异蛙寄生虫/汁液.tscn
res://scenes/particle/异蛙寄生虫/蛆.tscn
res://scenes/particle/类似斩击效果.tscn
res://scenes/particle/蜂群术士/Bee_Follow.tscn
res://scenes/particle/蜂群术士/Bee_In_Char.tscn
res://scenes/particle/蜂群术士/Bee_Stand.tscn
res://scenes/shooter/bee.tscn
res://scenes/shooter/clown/clown_area_object.tscn
res://scenes/shooter/clown/clown_projectile.tscn
res://scenes/shooter/clown_projectile.tscn
res://scenes/shooter/knife.tscn
res://scenes/shooter/军火商_子弹.tscn
res://scenes/shooter/子弹.tscn
res://scenes/shooter/建筑工人_砖块.tscn
res://scenes/shooter/时光客时钟.tscn
res://scenes/shooter/炸弹客炸弹.tscn
res://scenes/shooter/猎人_霰弹.tscn
res://scenes/shooter/磁铁_电球.tscn
res://scenes/shooter/科学家弹丸.tscn
res://scenes/shooter/蛇咬.tscn
res://scenes/shooter/裁判红牌.tscn
res://scenes/shooter/裁判蓝牌.tscn
res://scenes/shooter/裁判黄牌.tscn
res://scenes/shooter/酒瓶.tscn
res://scenes/shooter/键盘文字.tscn
res://scenes/status_image.tscn
res://scenes/terrain/矿工小石头.tscn
res://scenes/training/SpeedsterDodgeTrainingArena.tscn
res://scenes/training/SpeedsterRLWorld.tscn
res://scenes/training/SpeedsterTrainingProjectile.tscn
res://scenes/world.tscn
res://scripts/audio/local_positional_sfx.gd
res://scripts/ball.gd
res://scripts/ball.gd.uid
res://scripts/character_auto_fit.gd
res://scripts/character_auto_fit.gd.uid
res://scripts/characters/NC佬.gd
res://scripts/characters/NC佬.gd.uid
res://scripts/characters/RL/speedster_dodge_rl_controller.gd
res://scripts/characters/RL/speedster_dodge_rl_controller.gd.uid
res://scripts/characters/bilibili.gd
res://scripts/characters/bilibili.gd.uid
res://scripts/characters/speedster_motion_plan.gd
res://scripts/characters/speedster_motion_plan.gd.uid
res://scripts/characters/speedster_ricochet_planner.gd
res://scripts/characters/speedster_ricochet_planner.gd.uid
res://scripts/characters/speedster_threat.gd
res://scripts/characters/speedster_threat.gd.uid
res://scripts/characters/三角洲/背刺鼠.gd
res://scripts/characters/三角洲/背刺鼠.gd.uid
res://scripts/characters/伤心的男人.gd
res://scripts/characters/伤心的男人.gd.uid
res://scripts/characters/保安.gd
res://scripts/characters/保安.gd.uid
res://scripts/characters/保安_增援请求.gd
res://scripts/characters/保安_增援请求.gd.uid
res://scripts/characters/兔子.gd
res://scripts/characters/兔子.gd.uid
res://scripts/characters/军火商.gd
res://scripts/characters/军火商.gd.uid
res://scripts/characters/决斗者.gd
res://scripts/characters/决斗者.gd.uid
res://scripts/characters/剑客.gd
res://scripts/characters/剑客.gd.uid
res://scripts/characters/动物/九头蛇.gd
res://scripts/characters/动物/九头蛇.gd.uid
res://scripts/characters/动物/九头蛇_头.gd
res://scripts/characters/动物/九头蛇_头.gd.uid
res://scripts/characters/动物/牛系.gd
res://scripts/characters/动物/牛系.gd.uid
res://scripts/characters/变形者.gd
res://scripts/characters/变形者.gd.uid
res://scripts/characters/变形者_图片预演.gd
res://scripts/characters/变形者_图片预演.gd.uid
res://scripts/characters/变形者_形态控制器.gd
res://scripts/characters/变形者_形态控制器.gd.uid
res://scripts/characters/国王.gd
res://scripts/characters/国王.gd.uid
res://scripts/characters/夺舍狼.gd
res://scripts/characters/夺舍狼.gd.uid
res://scripts/characters/小丑.gd
res://scripts/characters/小丑.gd.uid
res://scripts/characters/小偷.gd
res://scripts/characters/小偷.gd.uid
res://scripts/characters/属性提示.gd
res://scripts/characters/属性提示.gd.uid
res://scripts/characters/布鲁斯.gd
res://scripts/characters/布鲁斯.gd.uid
res://scripts/characters/建筑工人.gd
res://scripts/characters/建筑工人.gd.uid
res://scripts/characters/影子.gd
res://scripts/characters/影子.gd.uid
res://scripts/characters/投稿角色工具.gd
res://scripts/characters/投稿角色工具.gd.uid
res://scripts/characters/投资者.gd
res://scripts/characters/投资者.gd.uid
res://scripts/characters/投资者_地图控制器.gd
res://scripts/characters/投资者_地图控制器.gd.uid
res://scripts/characters/投资者_柱.gd
res://scripts/characters/投资者_柱.gd.uid
res://scripts/characters/拳击手.gd
res://scripts/characters/拳击手.gd.uid
res://scripts/characters/收债人.gd
res://scripts/characters/收债人.gd.uid
res://scripts/characters/时光客.gd
res://scripts/characters/时光客.gd.uid
res://scripts/characters/智者.gd
res://scripts/characters/智者.gd.uid
res://scripts/characters/智者_布局点.gd
res://scripts/characters/智者_布局点.gd.uid
res://scripts/characters/智者_阵石.gd
res://scripts/characters/智者_阵石.gd.uid
res://scripts/characters/服务员.gd
res://scripts/characters/服务员.gd.uid
res://scripts/characters/杀戮尖塔/小刀猎.gd
res://scripts/characters/杀戮尖塔/小刀猎.gd.uid
res://scripts/characters/杀戮尖塔/异蛙寄生虫.gd
res://scripts/characters/杀戮尖塔/异蛙寄生虫.gd.uid
res://scripts/characters/杀戮尖塔/异蛙寄生虫_小.gd
res://scripts/characters/杀戮尖塔/异蛙寄生虫_小.gd.uid
res://scripts/characters/杀戮尖塔/战士.gd
res://scripts/characters/杀戮尖塔/战士.gd.uid
res://scripts/characters/杀戮尖塔/猎人杀手.gd
res://scripts/characters/杀戮尖塔/猎人杀手.gd.uid
res://scripts/characters/杀戮尖塔/虔诚雕刻师.gd
res://scripts/characters/杀戮尖塔/虔诚雕刻师.gd.uid
res://scripts/characters/杀戮尖塔/蛇咬相生猎.gd
res://scripts/characters/杀戮尖塔/蛇咬相生猎.gd.uid
res://scripts/characters/杀戮尖塔/蜂群术士.gd
res://scripts/characters/杀戮尖塔/蜂群术士.gd.uid
res://scripts/characters/杀戮尖塔/观者.gd
res://scripts/characters/杀戮尖塔/观者.gd.uid
res://scripts/characters/杀戮尖塔/锻剑储君.gd
res://scripts/characters/杀戮尖塔/锻剑储君.gd.uid
res://scripts/characters/杀戮尖塔/门扉缔造者.gd
res://scripts/characters/杀戮尖塔/门扉缔造者.gd.uid
res://scripts/characters/极速者.gd
res://scripts/characters/极速者.gd.uid
res://scripts/characters/棋子.gd
res://scripts/characters/棋子.gd.uid
res://scripts/characters/棋手.gd
res://scripts/characters/棋手.gd.uid
res://scripts/characters/棋盘控制器.gd
res://scripts/characters/棋盘控制器.gd.uid
res://scripts/characters/气球.gd
res://scripts/characters/气球.gd.uid
res://scripts/characters/炮兵.gd
res://scripts/characters/炮兵.gd.uid
res://scripts/characters/炸弹客.gd
res://scripts/characters/炸弹客.gd.uid
res://scripts/characters/猎人.gd
res://scripts/characters/猎人.gd.uid
res://scripts/characters/猫.gd
res://scripts/characters/猫.gd.uid
res://scripts/characters/矿工.gd
res://scripts/characters/矿工.gd.uid
res://scripts/characters/磁铁.gd
res://scripts/characters/磁铁.gd.uid
res://scripts/characters/科学家.gd
res://scripts/characters/科学家.gd.uid
res://scripts/characters/科学家_传送门.gd
res://scripts/characters/科学家_传送门.gd.uid
res://scripts/characters/背刺者.gd
res://scripts/characters/背刺者.gd.uid
res://scripts/characters/裁判.gd
res://scripts/characters/裁判.gd.uid
res://scripts/characters/赌徒.gd
res://scripts/characters/赌徒.gd.uid
res://scripts/characters/醉汉.gd
res://scripts/characters/醉汉.gd.uid
res://scripts/characters/重女.gd
res://scripts/characters/重女.gd.uid
res://scripts/characters/键盘侠.gd
res://scripts/characters/键盘侠.gd.uid
res://scripts/characters/镜子.gd
res://scripts/characters/镜子.gd.uid
res://scripts/characters/雨衣男.gd
res://scripts/characters/雨衣男.gd.uid
res://scripts/characters/面包车.gd
res://scripts/characters/面包车.gd.uid
res://scripts/characters/黑帮老大.gd
res://scripts/characters/黑帮老大.gd.uid
res://scripts/characters/默认/军官.gd
res://scripts/characters/默认/军官.gd.uid
res://scripts/characters/鼓手.gd
res://scripts/characters/鼓手.gd.uid
res://scripts/creatures/储君_sword.gd
res://scripts/creatures/储君_sword.gd.uid
res://scripts/creatures/军火商_枪.gd
res://scripts/creatures/军火商_枪.gd.uid
res://scripts/creatures/布鲁斯_狗.gd
res://scripts/creatures/布鲁斯_狗.gd.uid
res://scripts/creatures/布鲁斯_食物.gd
res://scripts/creatures/布鲁斯_食物.gd.uid
res://scripts/creatures/建筑工人_墙.gd
res://scripts/creatures/建筑工人_墙.gd.uid
res://scripts/creatures/投稿随从.gd
res://scripts/creatures/投稿随从.gd.uid
res://scripts/creatures/猎人_捕兽夹.gd
res://scripts/creatures/猎人_捕兽夹.gd.uid
res://scripts/creatures/门扉缔造者_手.gd
res://scripts/creatures/门扉缔造者_手.gd.uid
res://scripts/damage_text.gd
res://scripts/damage_text.gd.uid
res://scripts/effects/hit_burst_effect.gd
res://scripts/effects/hit_burst_effect.gd.uid
res://scripts/effects/knockback_effect.gd
res://scripts/effects/knockback_effect.gd.uid
res://scripts/effects/stun_visual.gd
res://scripts/effects/stun_visual.gd.uid
res://scripts/effects/umbrella_hit_burst.gd
res://scripts/effects/umbrella_hit_burst.gd.uid
res://scripts/effects/umbrella_hit_burst_follow.gd
res://scripts/effects/umbrella_hit_burst_follow.gd.uid
res://scripts/effects/wall_hit_burst.gd
res://scripts/effects/wall_hit_burst.gd.uid
res://scripts/effects/保安_巡逻车碰撞.gd
res://scripts/effects/保安_巡逻车碰撞.gd.uid
res://scripts/effects/兔子繁殖特效.gd
res://scripts/effects/兔子繁殖特效.gd.uid
res://scripts/effects/影子_吼叫波.gd
res://scripts/effects/影子_吼叫波.gd.uid
res://scripts/effects/投稿雨滴.gd
res://scripts/effects/投稿雨滴.gd.uid
res://scripts/effects/服务员门.gd
res://scripts/effects/服务员门.gd.uid
res://scripts/effects/炮兵炮击区域.gd
res://scripts/effects/炮兵炮击区域.gd.uid
res://scripts/effects/重女文字.gd
res://scripts/effects/重女文字.gd.uid
res://scripts/effects/重女黑洞视觉.gd
res://scripts/effects/重女黑洞视觉.gd.uid
res://scripts/effects/黑帮老大_扔钱.gd
res://scripts/effects/黑帮老大_扔钱.gd.uid
res://scripts/game_recorder.gd
res://scripts/game_recorder.gd.uid
res://scripts/shooter/bee.gd
res://scripts/shooter/bee.gd.uid
res://scripts/shooter/clown/clown_area_object.gd
res://scripts/shooter/clown/clown_area_object.gd.uid
res://scripts/shooter/clown/clown_motion_effect.gd
res://scripts/shooter/clown/clown_motion_effect.gd.uid
res://scripts/shooter/clown/clown_projectile.gd
res://scripts/shooter/clown/clown_projectile.gd.uid
res://scripts/shooter/clown_projectile.gd
res://scripts/shooter/clown_projectile.gd.uid
res://scripts/shooter/knife.gd
res://scripts/shooter/knife.gd.uid
res://scripts/shooter/军火商_子弹.gd
res://scripts/shooter/军火商_子弹.gd.uid
res://scripts/shooter/子弹.gd
res://scripts/shooter/子弹.gd.uid
res://scripts/shooter/建筑工人_砖块.gd
res://scripts/shooter/建筑工人_砖块.gd.uid
res://scripts/shooter/收债人_钱.gd
res://scripts/shooter/收债人_钱.gd.uid
res://scripts/shooter/时光客时钟.gd
res://scripts/shooter/时光客时钟.gd.uid
res://scripts/shooter/炸弹客炸弹.gd
res://scripts/shooter/炸弹客炸弹.gd.uid
res://scripts/shooter/猎人_霰弹.gd
res://scripts/shooter/猎人_霰弹.gd.uid
res://scripts/shooter/磁铁_电球.gd
res://scripts/shooter/磁铁_电球.gd.uid
res://scripts/shooter/科学家弹丸.gd
res://scripts/shooter/科学家弹丸.gd.uid
res://scripts/shooter/蛇咬.gd
res://scripts/shooter/蛇咬.gd.uid
res://scripts/shooter/裁判牌.gd
res://scripts/shooter/裁判牌.gd.uid
res://scripts/shooter/酒瓶.gd
res://scripts/shooter/酒瓶.gd.uid
res://scripts/shooter/键盘文字.gd
res://scripts/shooter/键盘文字.gd.uid
res://scripts/status/剑客_流血.gd
res://scripts/status/剑客_流血.gd.uid
res://scripts/status/面包车_匕首流血.gd
res://scripts/status/面包车_匕首流血.gd.uid
res://scripts/terrain/生成地形安全管理器.gd
res://scripts/terrain/生成地形安全管理器.gd.uid
res://scripts/terrain/矿工小石头.gd
res://scripts/terrain/矿工小石头.gd.uid
res://scripts/training/combat_threat_analyzer.gd
res://scripts/training/combat_threat_analyzer.gd.uid
res://scripts/training/manual_training_controller.gd
res://scripts/training/manual_training_controller.gd.uid
res://scripts/training/speedster_dodge_training_arena.gd
res://scripts/training/speedster_dodge_training_arena.gd.uid
res://scripts/training/speedster_rl_world_controller.gd
res://scripts/training/speedster_rl_world_controller.gd.uid
res://scripts/training/speedster_training_projectile.gd
res://scripts/training/speedster_training_projectile.gd.uid
res://scripts/training/training_respawn_manager.gd
res://scripts/training/training_respawn_manager.gd.uid
res://scripts/training/training_stats_hud.gd
res://scripts/training/training_stats_hud.gd.uid
res://scripts/ui/boss_intro_overlay.gd
res://scripts/ui/boss_intro_overlay.gd.uid
res://scripts/ui/character_side_status_ui.gd
res://scripts/ui/character_side_status_ui.gd.uid
res://scripts/ui/placement_box_overlay.gd
res://scripts/ui/placement_box_overlay.gd.uid
res://scripts/world.gd
res://scripts/world.gd.uid
res://shaders/after_image.gdshader
res://shaders/after_image.gdshader.uid
res://shaders/after_image_material.tres
res://shaders/after_image_stretch.gdshader
res://shaders/after_image_stretch.gdshader.uid
res://shaders/after_image_stretch_material.tres
res://shaders/attack_white_points_stretch.gdshader
res://shaders/attack_white_points_stretch.gdshader.uid
res://shaders/particle_stretch.gdshader
res://shaders/particle_stretch.gdshader.uid
res://shaders/set_rgb_color.gdshader
res://shaders/set_rgb_color.gdshader.uid
res://shaders/time_rewind_vhs.gdshader
res://shaders/time_rewind_vhs.gdshader.uid
res://shaders/vignette.gdshader
res://shaders/vignette.gdshader.uid
res://shaders/变形者_扭曲变形.gdshader
res://shaders/变形者_扭曲变形.gdshader.uid
res://translations.csv
res://ui/Button/focus.tres
res://ui/Button/hover.tres
res://ui/Button/normal.tres
res://ui/control.gd
res://ui/control.gd.uid
res://ui/control.tscn
res://ui/default.tres
res://ui/game_setting.tscn
res://ui/mouseclick1.ogg
res://ui/mouseclick1.ogg.import
res://ui/set_button_background.tres
res://ui/setting_panel_stylebox.tres
res://ui/slider.tres
res://ui/team_set_button.tres
res://ui/team_set_button.tscn
```


## V34 累计新增与确认路径（相对 V7 历史基线）

> **确认来源：** `Godot_完整更新_UI优先中键拖动_v34.zip`，共 500 个项目文件。下面只列出 V7 清单中没有出现、但 V34 累计包已实际包含的路径。
>
> V34 累计包不以 `.godot/`、`.import` 作为源目录依据；这类导入缓存缺失不代表源资源不存在。

```text
res://Images/characters/meme/凑企鹅/凑企鹅.png
res://Images/characters/meme/凑企鹅/同化1.png
res://Images/characters/meme/凑企鹅/同化2.png
res://Images/characters/meme/凑企鹅/同化3.png
res://Images/characters/meme/凑企鹅/同化4.png
res://Images/characters/meme/凑企鹅/同化5.png
res://Images/characters/人物/重女/高松灯_ON常服.png
res://Images/characters/人物/重女/高松灯黑脸.png
res://Images/characters/月计/殷红迷雾/ego冲刺.png
res://Images/characters/月计/殷红迷雾/ego后退.png
res://Images/characters/月计/殷红迷雾/ego斩.png
res://Images/characters/月计/殷红迷雾/ego斩1.png
res://Images/characters/月计/殷红迷雾/ego斩2.png
res://Images/characters/月计/殷红迷雾/ego斩杀1.png
res://Images/characters/月计/殷红迷雾/ego突刺.png
res://Images/characters/月计/殷红迷雾/ego站立.png
res://Images/characters/月计/殷红迷雾/ego防御.png
res://Images/characters/月计/殷红迷雾/尸横遍野.png
res://Images/characters/月计/殷红迷雾/斩杀2.png
res://Images/characters/月计/殷红迷雾/斩杀3.png
res://Images/characters/月计/殷红迷雾/斩杀4.png
res://Images/characters/月计/殷红迷雾/斩杀5.png
res://Images/characters/月计/殷红迷雾/斩杀6.png
res://Images/characters/月计/殷红迷雾/普通冲刺.png
res://Images/characters/月计/殷红迷雾/普通刺.png
res://Images/characters/月计/殷红迷雾/普通斩.png
res://Images/characters/月计/殷红迷雾/普通斩2.png
res://Images/characters/月计/殷红迷雾/普通站立.png
res://Images/characters/月计/殷红迷雾/普通防御.png
res://Images/shooter/meme/凑企鹅石头.png
res://audio/characters/meme/凑企鹅/你是凑企鹅.MP3
res://audio/characters/meme/凑企鹅/咕咕嘎嘎1.MP3
res://audio/characters/meme/凑企鹅/咕咕嘎嘎2.MP3
res://audio/characters/meme/凑企鹅/咕咕嘎嘎3.MP3
res://audio/characters/meme/凑企鹅/咕咕嘎嘎4.MP3
res://audio/characters/meme/凑企鹅/咕咕嘎嘎5.MP3
res://audio/characters/meme/凑企鹅/灵感蘑.MP3
res://audio/characters/月计/伞夫/开场问候.ogg
res://audio/characters/月计/殷红迷雾/EGO_BGM.ogg
res://audio/characters/月计/殷红迷雾/ego刺.MP3
res://audio/characters/月计/殷红迷雾/ego斩1.MP3
res://audio/characters/月计/殷红迷雾/ego斩2.MP3
res://audio/characters/月计/殷红迷雾/刺.MP3
res://audio/characters/月计/殷红迷雾/尸横遍野.MP3
res://audio/characters/月计/殷红迷雾/斩1.MP3
res://audio/characters/月计/殷红迷雾/血雾弥漫.MP3
res://audio/characters/醉汉/酒瓶碎裂.mp3
res://scenes/characters/meme/凑企鹅.tscn
res://scenes/characters/月计/伞夫.tscn
res://scenes/characters/月计/堇紫泪滴.tscn
res://scenes/characters/月计/殷红迷雾.tscn
res://scenes/shooter/凑企鹅石头.tscn
res://scripts/audio/local_positional_sfx.gd.uid
res://scripts/characters/meme/凑企鹅.gd
res://scripts/characters/月计/伞夫.gd
res://scripts/characters/月计/堇紫泪滴.gd
res://scripts/characters/月计/月计理智角色.gd
res://scripts/characters/月计/殷红迷雾.gd
res://scripts/characters/月计/殷红迷雾视觉.gd
res://scripts/shooter/凑企鹅石头.gd
res://scripts/ui/月计理智条.gd
res://shaders/ui/月计理智流动.gdshader
```

### V34 角色分类与兼容说明

- `月计` 是当前已确认的独立角色分类，场景固定在 `res://scenes/characters/月计/`，脚本固定在 `res://scripts/characters/月计/`。
- 当前月计场景已确认：`殷红迷雾.tscn`、`伞夫.tscn`、`堇紫泪滴.tscn`。
- `meme` 是当前已确认的独立角色分类，目录名固定为小写英文 `meme`。本轮上传基线已确认 `凑企鹅`、`棍母`；本次新增 `愤怒的普通人`、`肌肉男`。
- V7 历史路径中的 `res://scenes/characters/人物/雨衣男.tscn` / `res://scripts/characters/雨衣男.gd` 属于旧路径记录；V34 的新角色路径为 `res://scenes/characters/月计/伞夫.tscn` 与 `res://scripts/characters/月计/伞夫.gd`。**不要仅凭历史条目擅自删除旧文件**，除非项目内引用检查确认并且用户明确要求清理。
- 月计理智 UI 固定使用 `res://scripts/ui/月计理智条.gd` 与 `res://shaders/ui/月计理智流动.gdshader`。
- 凑企鹅的唯一石头投射物固定使用 `res://scenes/shooter/凑企鹅石头.tscn`、`res://scripts/shooter/凑企鹅石头.gd`、`res://Images/shooter/meme/凑企鹅石头.png`。

### 本轮对话中已上传、但尚未确认写入 V34 项目路径的素材

下列“堇紫泪滴”图片已经作为对话附件提供，但 **V34 累计包中尚无 `res://Images/characters/月计/堇紫泪滴/` 目录**。因此本表暂不把这些附件映射成 `res://` 路径；下一次正式接入角色图片时，必须先使用当前项目/更新包确认目标目录，再写入路径：

```text
打击(1).png
打击姿态(1).png
防御(1).png
突刺1(1).png
突刺2(1).png
突刺姿态(1).png
斩击1(1).png
斩击2(1).png
斩击姿态(1).png
站立(1).png
```

### V34 路径维护规则补充

1. 新角色分类目录已经确认存在后，继续使用现有分类，不创建同义目录：`月计` 不改成 `ProjectMoon` / `project_moon`，`meme` 不改成 `Meme`。
2. 角色专属声音仍放 `res://audio/characters/<分类或角色现有层级>/...`；本项目现有新例子为 `audio/characters/月计/...` 与 `audio/characters/meme/...`。
3. 图片目录继续严格使用根部大写 `Images/`。尤其不要创建 `images/characters/月计/` 或 `images/characters/meme/`。
4. 当前 V34 已确认存在 `res://shaders/ui/`，所以月计理智 Shader 继续放这里，不要另建 `shaders/UI/`。
5. `translations.csv` 已在 V34 累计包中确认位于项目根目录 `res://translations.csv`。

## 来源与命名原则

Godot 官方说明 `res://` 永远指向包含 `project.godot` 的项目根目录；移动或重命名资源会影响引用。官方也建议文件与目录命名保持一致并注意大小写，因为 Windows 通常不区分大小写，而 Godot 的导出资源文件系统可能区分大小写。此项目当前已有大量中文资源名，因此本表的原则是“保持现有真实路径，不擅自大改名”，而不是强行把整个老项目一次性改成英文 snake_case。

## 当前会话累计完整更新包目录（V63：累计更新 + meme 大狗叫/小狗叫）

> 这一段是本次会话开始维护后的**累计更新包唯一完整目录表**。压缩包解压后按下列相对路径直接覆盖到 `project.godot` 所在项目根目录。未列出的原项目文件保持原样。
> `05_肌肉男_侧身展示手臂肌肉.png` 按用户明确要求 **不接入项目**，所以不在目录表和两个更新包中。

```text
res://
├── Images/
│   └── characters/
│       ├── meme/
│       │   ├── 愤怒的普通人/
│       │   │   ├── 01_普通人_微笑持刀.png
│       │   │   ├── 02_普通人_微笑刺出小刀.png
│       │   │   ├── 03_普通人_愤怒持刀.png
│       │   │   ├── 04_普通人_愤怒刺出小刀.png
│       │   │   ├── 08_小刀本体.png
│       │   │   └── 愤怒的普通人.svg
│       │   └── 肌肉男/
│       │       ├── 06_肌肉男_独立手臂.png
│       │       ├── 07_肌肉男_独立身体.png
│       │       └── 肌肉男.svg
│       └── 月计/
│           └── 殷红迷雾/
│               ├── 刀光斩击遮罩.png
│               └── 刀光突刺遮罩.png
├── audio/
│   └── characters/
│       └── meme/
│           ├── 大狗叫/
│           │   ├── 大狗持续叫.wav
│           │   ├── 大狗短叫.wav
│           │   ├── 小狗持续叫.wav
│           │   └── 小狗短叫.wav
│           ├── 愤怒的普通人/
│           │   ├── 刺.mp3
│           │   ├── 小刀刺_[cut_1sec] (1).mp3
│           │   ├── 小刀刺_[cut_1sec] (2).mp3
│           │   ├── 小刀刺_[cut_1sec] (3).mp3
│           │   ├── 小刀刺_[cut_1sec] (4).mp3
│           │   ├── 小刀刺_[cut_1sec] (5).mp3
│           │   ├── 小刀刺_[cut_1sec].mp3
│           │   └── 怪物叫.wav
│           └── 肌肉男/
│               └── 旋转.mp3
├── classes/
│   ├── ball.gd
│   └── state_machine.gd
├── scenes/
│   ├── characters/
│   │   ├── meme/
│   │   │   ├── 大狗叫.tscn
│   │   │   ├── 愤怒的普通人.tscn
│   │   │   └── 肌肉男.tscn
│   │   └── 月计/
│   │       ├── 伞夫.tscn
│   │       └── 伞夫动画帧.tres
│   └── creatures/
│       └── 小狗叫.tscn
├── scripts/
│   ├── characters/
│   │   ├── meme/
│   │   │   ├── 大狗叫.gd
│   │   │   ├── 愤怒的普通人.gd
│   │   │   ├── 狗叫机制.gd
│   │   │   └── 肌肉男.gd
│   │   └── 月计/
│   │       ├── 伞夫.gd
│   │       └── 殷红迷雾.gd
│   ├── creatures/
│   │   └── 小狗叫.gd
│   ├── effects/
│   │   ├── 殷红迷雾_刀光.gd
│   │   └── 狗叫声波.gd
│   ├── ui/
│   │   └── character_side_status_ui.gd
│   └── world.gd
├── shaders/
│   └── 殷红迷雾_血肉拖尾.gdshader
├── PROJECT_PATH_MAP_FOR_AI_V34.md
└── translations.csv
```

### 本次角色机制确认（当前版本）

- `愤怒的普通人`：真实 `Area2D + RectangleShape2D` 小刀突刺。V39 最大生命提高为 `700`；V42 基础突刺伤害从 `24` 提高为 `50`。满血基础攻速保持 `Attack_Cooling = 0.90`、基础突刺时长 `0.34s` 不变。生命越少，伤害以 `50` 为基础继续连续提高、人物连续变红，同时攻速倍率显著上升：默认半血约 `3.0x`、25% 血约 `4.375x`、濒死最高 `5.0x`，突刺动作与有效命中窗口同步加速，避免只缩冷却却被固定攻击动作卡速。V38 起愤怒阶段阈值固定为 `HP <= 50%`（默认 `angry_expression_threshold = 0.50`，以 rage 比例表示），首次进入后锁定愤怒阶段：待机从 01 切到 03、突刺从 02 切到 04，并播放一次 `怪物叫.wav`；回血不会反复切回正常图片或重复触发怪叫。
- `愤怒的普通人`：每次突刺开始播放 `刺.mp3`；真实命中有效角色时，从 6 个 `小刀刺_[cut_1sec]...mp3` 中随机播放一个。V37 起 `08_小刀本体.png` 作为独立 `KnifeVisual` 正式叠加到真实突刺 Hitbox 上，并随突刺方向/距离移动；尺寸显著放大，用于解决整身姿态图里的刀在实际游戏缩放下过小、几乎看不见的问题。
- `肌肉男`：07 为身体，06 为独立旋转手臂。V37 提高旋转基础速度、加速度和最高速度：默认约从 `6.5 rad/s` 起步，以 `6.0 rad/s²` 加速到 `28 rad/s`；V39 将旋转伤害从上一版 `55~280` 下调为 `45~210`；V40 最大生命调整为 `750`；V41 将目标击退明显收小。V42 按用户澄清取消“角色身体自身回弹”，改为拳头真实命中后**手臂本身沿旋转反方向弹开**：低速默认约 `12°`，最高转速约 `52°`，随后在停转阶段缓缓回到原旋转轨道。手臂视觉随转速最多放大到基础尺寸约 `1.65x`；真实圆形拳头 Shape 的半径最多同步增长到约 `1.42x`，但 `CollisionShape2D.scale` 保持 `(1,1)`。命中停转后的放大尺寸也改为逐帧缓慢恢复，不再重启时瞬间缩回。只有真实命中有效角色才停。
- `肌肉男`：`旋转.mp3` 不启用资源原生 Loop。脚本读取 `AudioStream.get_length()`，每段在结束前 `0.33` 秒启动下一段，以 A/B 两个 `AudioStreamPlayer2D` 交替重叠播放；音量按当前转速从 `-48 dB`（开始基本听不见）逐步提高到 `+3 dB` 上限。命中停转时两轨立即停止，重新起转后从最低音量重新增长。
- 两个角色继续使用既有 `meme` 分类，未创建 `Meme/`、`images/`、`Audio/` 等同义目录。

### 本轮路径变更记录

- 旧路径 -> 新路径：无。
- 删除项：无；`05_肌肉男_侧身展示手臂肌肉.png` 从未接入，因此不是删除项。
- 累计创建项：本会话已新增 9 个 PNG、8 个 MP3、1 个 WAV，共 18 个源资源文件。V38 新增 `res://audio/characters/meme/愤怒的普通人/怪物叫.wav`。
- V37 修改项：`res://scripts/characters/meme/肌肉男.gd`、`res://scenes/characters/meme/肌肉男.tscn`、`res://scenes/characters/meme/愤怒的普通人.tscn`、`PROJECT_PATH_MAP_FOR_AI_V34.md`。
- V37 调整：肌肉男大幅提高转速、伤害与击退，并让手臂视觉/真实圆形拳头 Shape 随转速受限增大；愤怒的普通人启用独立放大的 `08_小刀本体.png` 作为可见刀具。
- V38 本次修改项：`res://scripts/characters/meme/愤怒的普通人.gd`、`PROJECT_PATH_MAP_FOR_AI_V34.md`；新增 `res://audio/characters/meme/愤怒的普通人/怪物叫.wav`。
- V38 调整：愤怒的普通人在当前生命降到最大生命的 50% 或以下时立即进入并锁定愤怒阶段，同时播放一次 `怪物叫.wav`；之后使用愤怒待机/突刺图片。

- V39 本次修改项：`res://scripts/characters/meme/愤怒的普通人.gd`、`res://scenes/characters/meme/愤怒的普通人.tscn`、`res://scripts/characters/meme/肌肉男.gd`、`res://scenes/characters/meme/肌肉男.tscn`、`PROJECT_PATH_MAP_FOR_AI_V34.md`。
- V39 调整：愤怒的普通人最大生命从 `260` 提高为 `700`；满血基础 `Attack_Cooling = 0.90` 保持不变，残血攻速强化提高到半血约 `3.0x`、25% 血约 `4.375x`、濒死最高 `5.0x`，且突刺动作/命中窗口同步提速。肌肉男保持 V37 的转速、击退、手臂随速度增大与旋转音机制不变，旋转伤害从 `55~280` 下调为 `45~210`。

- V40 本次修改项：`res://scripts/characters/meme/愤怒的普通人.gd`、`res://scenes/characters/meme/肌肉男.tscn`、`PROJECT_PATH_MAP_FOR_AI_V34.md`；为修复用户当前项目实际缺失音频导致的解析错误，本次最小更新包额外重新携带 `res://audio/characters/meme/愤怒的普通人/怪物叫.wav`。
- V40 修复：将 `怪物叫.wav` 从编译期 `preload()` 改为 `ResourceLoader.exists()` + `ResourceLoader.load()` 的运行时安全加载；音频存在时仍正常播放，单个音频漏拷时不再导致整个 `愤怒的普通人.gd` Parser Error。
- V40 数值：肌肉男 `Max_health` 从 `460` 调整为 `750`；转速、伤害 `45~210`、击退和手臂随速度增大机制均保持 V39 不变。

- V41 本次修改项：`res://scripts/characters/meme/肌肉男.gd`、`PROJECT_PATH_MAP_FOR_AI_V34.md`。
- V41 平衡：肌肉男对目标的击退距离从 `85~480` 下调为 `45~180`，击退速度从 `760~1780` 下调为 `520~1050`，撞墙反弹倍率从 `0.18` 下调为 `0.08`。旋转伤害、转速、750 生命、手臂随速度增大和旋转音机制不变。
- V41 新机制：拳头真实命中有效角色时，肌肉男自身会沿目标反方向产生小幅回弹；回弹距离默认从 `10` 随转速提高到 `65`，回弹速度从 `280` 提高到 `780`，使用既有 `ball.apply_knockback()`，且不锁住自身控制。

- V42 本次修改项：`res://scripts/characters/meme/愤怒的普通人.gd`、`res://scenes/characters/meme/愤怒的普通人.tscn`、`res://scripts/characters/meme/肌肉男.gd`、`PROJECT_PATH_MAP_FOR_AI_V34.md`。
- V42 数值：愤怒的普通人基础突刺伤害从 `24` 提高为 `50`；700 生命、满血基础攻速、残血攻速强化、半血愤怒图片/怪叫与残血增伤倍率均保持。
- V42 肌肉男回弹修正：移除 V41 错误理解的“肌肉男身体自身回弹”。现在命中时仅旋转手臂沿当前旋转的反方向产生角度回弹，默认随转速从约 `12°` 提高到 `52°`，之后以约 `150°/s` 平滑回到旋转轨道；身体位置不因这一机制改变。
- V42 手臂尺寸恢复：命中停转后，当前高速放大的手臂视觉与真实圆形拳头半径使用持久显示倍率逐帧恢复（默认恢复速度 `1.25/s`），不再在重新起转时瞬间回到基础尺寸。


- V43 本次修改项：`res://scripts/characters/月计/伞夫.gd`、`res://scenes/characters/月计/伞夫.tscn`、`res://scenes/characters/月计/伞夫动画帧.tres`、`PROJECT_PATH_MAP_FOR_AI_V34.md`。
- V43 攻速：伞夫 `Attack_Cooling` 从 `1.75s` 降为 `1.15s`；Attack1 动画从 `22 fps` 提高到 `30 fps`，Attack2 从 `16 fps` 提高到 `24 fps`，Attack3 从 `22 fps` 提高到 `30 fps`；攻击末帧停留从 `0.18s` 缩短为 `0.10s`。
- V43 选招检测修复：攻击1/攻击2起手检测只检查各自**第一实际命中段**的真实 `CollisionShape2D`，不再把负理智才出现的第二/第三段范围并入起手资格。技能袋当前格子在此站位打不到时，会按技能袋顺序向后跳过，选择当前真正能命中的攻击；因此不会再因为“攻击1能覆盖该位置”却硬放一个第一段覆盖不到的攻击2。
- V43 攻击3修复：确认当前 `Attack3` 动画只有 10 帧（索引 `0~9`），旧 `attack3_hit_frame = 17` 永远无法达到，会一直拖到 watchdog。现改为索引 `3`（对应当前素材序列的 `frame_0017`），并把攻击3改成真实位移技逻辑：`attack3_engage_range = 340` 作为蓝色冲刺起手检测，`attack3_dash_speed = 760`、最大冲刺 `0.42s`、停止距离 `42`；最终伤害仍只由攻击3红色真实 `CollisionShape2D` 结算。
- V43 攻击3真实命中框：最终伤害矩形调整为 `360×280`，面朝右 authored 位置调整为 `(95, 0)`，仍随角色朝向镜像并继承现有 `attack_range_scale_multiplier = 1.18`。这是实际伤害 Shape，不是角色半径兜底。

- V44 本次修改项：`res://scripts/characters/月计/伞夫.gd`、`PROJECT_PATH_MAP_FOR_AI_V34.md`。
- V44 攻击3固定机制：攻击3仍只在真实 `攻击3范围/CollisionShape2D` 成功造成伤害后触发固定；不会因为冲刺接近、角色实体碰撞或 engage_range 检测就直接抓人。真实命中目标后，目标进入独立 motion-lock，停止自主移动/攻击/技能，并在每个物理帧固定到攻击3真实 Shape 的中心（可由 `attack3_pin_offset` 微调）。固定期间不提前显示/结算眩晕。
- V44 攻击3释放与后置眩晕：伞夫继续完整播放 Attack3 到最后一帧并完成 `attack_end_hold_seconds` 末帧停留后，才解除固定并调用目标现有 `apply_stun(attack3_stun_duration)`；默认释放后眩晕 `0.45s`。如果 Attack3 被异常中断、伞夫死亡或目标死亡，则立即清理固定锁且不追加正常收尾眩晕，避免目标永久卡住。
- V44 控制锁兼容：攻击3固定复用通用 `KnockbackEffect` 的 `generic_motion_lock_count` / `generic_motion_lock_baseline` metadata 计数语义，因此与项目已有击退/眩晕锁可以叠加，不会在释放伞夫固定时错误解除其他来源仍生效的控制锁。
- 未能确认项：无。

- V45 本次修改项：`res://scripts/characters/月计/伞夫.gd`、`PROJECT_PATH_MAP_FOR_AI_V34.md`。
- V45 攻击3固定位置修复：不再把命中目标强制吸到 `攻击3范围/CollisionShape2D` 的大矩形中心。真实命中成功时记录目标当时在 `攻击3范围` Area2D 本地空间中的实际位置，固定期间持续把该局部点转换回世界坐标；`attack3_pin_offset` 仅作为实际命中位置上的可选美术微调。因此目标不会再在被叉中瞬间跳到错误的伤害框中心。
- V45 攻击3实体挤压修复：固定期间保存目标原有 `CharacterBody2D.collision_layer` / `collision_mask` 后临时设为 `0`，使被叉住目标的角色本体不参与墙体/角色实体碰撞；其独立 `hurtbox Area2D` 不受影响。正常释放、异常中断或目标死亡清理时都会恢复原始 layer/mask。固定期间伞夫本体也会清空 `direction / velocity / Repel`，防止 Attack 状态沿旧移动方向继续 `move_and_slide()` 把挂住的目标挤向墙。

- V46 本次修改项：`res://scripts/characters/月计/伞夫.gd`、`PROJECT_PATH_MAP_FOR_AI_V34.md`。
- V46 攻击3固定点修正：按用户明确要求，撤销 V45 的“保留真实命中瞬间位置”语义。攻击3真实命中后，敌人现在会**立即移动到伞上的固定锚点**，而不是保持原位置。锚点以 `攻击3范围/CollisionShape2D` 中心为基准，默认 `attack3_pin_offset = Vector2(75, -20)`，即面朝右时向伞前端移动 75px、向上 20px；面朝左时 X 自动镜像。固定期间继续沿用 V45 的实体碰撞关闭/恢复机制，避免被挂住的敌人把伞夫挤进墙。


- V47 本次修改项：`res://scripts/characters/月计/伞夫.gd`、`res://scenes/characters/月计/伞夫.tscn`、`PROJECT_PATH_MAP_FOR_AI_V34.md`。
- V47 攻击3编辑器挂点：在 `res://scenes/characters/月计/伞夫.tscn` 的 `伞夫攻击范围_直接调整/攻击3敌人固定点_编辑器拖这里` 新增 `Marker2D`。以后直接在 Godot 2D 编辑器拖这个十字即可修改攻击3把敌人挂到伞上的“期望位置”，不再依赖脚本里反复试 `Vector2`。该 Marker 与攻击范围共用 authored transform，会跟随左右镜像、`attack_range_scale_multiplier` 与本次攻击瞄准旋转。
- V47 攻击3自动防重叠：Marker 只表示期望点。攻击3真实命中后，脚本读取目标与伞夫各自 `CharacterBody2D` 直属的真实 `CollisionShape2D`，通过 `Shape2D.collide()` 检查把目标放到 Marker 时是否会与伞夫本体实体碰撞框重叠。如果重叠，则沿“伞夫身体中心 -> Marker”方向以默认 `3px` 步进向外搜索，直到双方真实 Shape 不再重叠，再额外留默认 `10px` 安全间距；最大自动外推默认 `240px`。因此用户仍可自由拖 Marker，但无效的过近点会自动修正到最近的安全位置。
- V47 兼容：旧 `attack3_pin_offset` 保留为缺少 Marker2D 的旧场景后备；V45 起固定期间临时关闭目标实体 `collision_layer / collision_mask`、释放后恢复的防挤墙机制继续保留；攻击结束后再眩晕 `0.45s` 的流程不变。

- V48 本次修改项：`res://scripts/characters/月计/殷红迷雾.gd`、`res://scripts/effects/殷红迷雾_刀光.gd`、`PROJECT_PATH_MAP_FOR_AI_V34.md`。
- V48 殷红迷雾刀光：新增程序化 `Line2D` 双层刀光，不依赖新贴图。普通突刺生成暖白直线刀光，普通斩击生成暖白弧光；E.G.O 突刺/双斩使用更长、更粗的猩红刀光，第二斩反向扫回；`尸横遍野` 按当前真实横斩攻击体长度生成长距离横向刀光；`血雾弥漫` 六个演出声段会各生成一次交替方向的短促红色弧光。
- V48 刀光表现：刀光使用两层 `Line2D`（半透明外发光 + 高亮白芯），两端通过 `Curve` 收尖，开启 `antialiased` 并使用 `CanvasItemMaterial.BLEND_MODE_ADD` 加色混合；生命周期默认 `0.22s`，快速亮起后平滑淡出并轻微张开。所有刀光仅为视觉，不参与命中、伤害或威胁判定。
- V48 可调参数：在殷红迷雾 Inspector 新增 `blade_light_enabled`、持续时间、普通/E.G.O 长度倍率、普通/E.G.O 宽度、出生前偏移及两套颜色。特效脚本运行时用 `ResourceLoader.exists()` 安全加载，缺少特效文件时只跳过视觉，不会让角色脚本因编译期资源缺失而 Parser Error。
- V48 多人兼容：刀光出生位置、旋转、尺寸、颜色与斩击方向通过 authority 的不可靠 RPC 同步到远端，仅重放视觉；伤害仍完全走原有真实 `Area2D + CollisionShape2D` 攻击体积。


- V49 本次修改项：`res://scripts/characters/月计/殷红迷雾.gd`、`res://scripts/effects/殷红迷雾_刀光.gd`、`PROJECT_PATH_MAP_FOR_AI_V34.md`。
- V49 刀光定位修复：撤销 V48 的“`global_position + 固定前偏移`”出生方式。普通突刺、普通/E.G.O 斩击、E.G.O 突刺与 `尸横遍野` 现在都**先创建真实伤害 `Area2D`，再直接读取该 Area2D 的 `global_position`、`global_rotation` 和真实攻击尺寸作为刀光 Transform/尺寸基准**；因此刀光与对应红色真实伤害区域共用同一空间基准，不再从人物根节点猜位置。`血雾弥漫` 的分段刀光则改为围绕当前被处决目标的世界位置生成。
- V49 刀光美术重做：删除 V48 的双层 `Line2D` 粗线方案，改为多层抗锯齿 `Polygon2D` 剑气。突刺使用尖锐收束的长梭形剑气并带两片碎光；普通/E.G.O 斩击使用带外发光、主体渐变和白色锋线的弯月环带；`尸横遍野` 使用两端收尖、略带弯曲的大范围横斩带；`血雾弥漫` 使用围绕目标交替倾斜的短促弯月。所有多边形使用 `vertex_colors` 做首尾透明/中段高亮渐变，并使用 `BLEND_MODE_ADD` 只增强视觉亮度。
- V49 刀光动画调整：默认生命周期从 `0.22s` 缩短为 `0.18s`，不再从 `0.78x` 大幅放大到 `1.08x`；改为约 `0.96x/0.90y -> 1.03x/1.04y` 的轻微展开，斩击只额外扫动约 `8°` 后快速消散，减少“粗线拉伸”和橡皮筋感。普通/E.G.O 默认视觉宽度提高为 `34/52`，但最终厚度仍受真实攻击矩形高度限制。


- V50 本次修改项：`res://scripts/characters/月计/殷红迷雾.gd`、`res://scripts/effects/殷红迷雾_刀光.gd`、`PROJECT_PATH_MAP_FOR_AI_V34.md`；新增 `res://shaders/殷红迷雾_血肉拖尾.gdshader`。
- V50 刀光方向重做：撤销 V49 的“整块月牙 Polygon2D 闪现”表现，改成沿攻击路径逐步推进的**红色血肉拖尾**。真实攻击 `Area2D` 仍提供世界位置/旋转/尺寸，同时额外把殷红迷雾本体在该攻击框局部空间中的真实位置传给特效；因此突刺/斩击拖尾会从人物/武器侧向攻击框前端推进，不再从矩形中心整块出现。`尸横遍野` 使用长路径快速推进，`血雾弥漫` 继续围绕处决目标生成。
- V50 血肉内部动画：新增 `res://shaders/殷红迷雾_血肉拖尾.gdshader`。拖尾 Polygon2D 显式生成沿路径方向的 UV，CanvasItem Shader 使用 `progress` 做头部推进/尾部残留，并使用 TIME 驱动的多级连续噪声让深红色血肉暗流、血管和边缘啃蚀持续运动；主体不再使用白色剑气芯，整体以鲜红边缘 + 深红流动内部为主。
- V50 眼睛动画：血肉拖尾内部程序化生成多只 Mimicry 风格眼睛；普通拖尾默认较少，E.G.O、尸横遍野更多。眼睛包含深红眼眶、浅色眼白、绿色虹膜与黑色瞳孔，并按独立相位在拖尾推进后进行“睁眼 -> 合眼成细缝 -> 再睁开”的可见动画；眼睛随拖尾头部出现并随尾部/整体淡出，不是静态贴图。
- V50 默认视觉参数：`blade_light_lifetime` 从 `0.18s` 提高为 `0.46s` 以容纳可见的推进与眨眼过程；普通/E.G.O 拖尾宽度默认改为 `48/72`，颜色统一改为鲜红/猩红，长度倍率改为 `1.00/1.12`。这些改动只影响视觉，真实伤害、Hitbox、E.G.O 倍率与威胁检测全部保持原逻辑。


- V51 本次交付修复：上一轮 V50 的血肉拖尾代码、动态 Shader 与眨眼实现已经生成，但最终对话附件错误沿用了 V49 的旧 ZIP，因此用户覆盖后看不到任何 V50 变化。本轮重新从 V50 实际工作目录生成完整/最小更新包；项目内部路径与文件名均不改变。
- V51 运行确认标识：运行时创建的殷红迷雾动态拖尾节点命名为 `殷红迷雾_血肉拖尾_V51`，可在 Godot Remote 场景树中确认当前实际运行的是本轮代码；该名称只用于调试识别。


- V52 殷红迷雾血肉拖尾重做：V51 的主体依赖 Polygon2D+Shader，用户实机只看到眼睛而看不到拖尾。本轮主体改为四层动态 Line2D（红雾外辉/鲜红血肉/深红核心/前端亮红锋线），不依赖 Shader 即可显示；可见点集逐帧从刀柄侧向刀锋推进，是真正的路径动画。
- V52 深红内部流动：沿当前可见拖尾生成 12~26 个深红血肉块并持续向前流动；即使 Shader 不工作也能看见暗红内部在移动。
- V52 小眼睛群：按拖尾长度动态生成 8~34 只小眼睛，E.G.O 与尸横遍野数量更多；眼睛沿当前可见拖尾分布并缓慢随拖尾流动，每只眼睛使用独立相位执行睁眼→合眼→短暂停留→再睁眼。
- V52 默认拖尾寿命从 0.46 秒提高到 0.68 秒，确保红色拖尾推进、内部暗红流动和错峰眨眼都能被肉眼观察到。运行时特效节点标识更新为 `殷红迷雾_血肉拖尾_V52`。

- V53 本次修改项：`res://scripts/characters/月计/殷红迷雾.gd`、`res://scripts/effects/殷红迷雾_刀光.gd`、`PROJECT_PATH_MAP_FOR_AI_V34.md`。
- V53 参考图重做：根据用户提供的四张原游戏视觉参考，撤销 V52 的多层 `Line2D` 粗拖尾主体。新主体改为 `Node2D._draw()` 每帧生成的动态多边形血肉刀幕：路径中段宽厚、首尾尖锐收束，普通/E.G.O 斩击使用明显弧形中心线，突刺使用长梭形尖刃，尸横遍野使用超长横向刀幕；整体更接近参考图中大面积弯曲红色血刃而不是圆头线条。
- V53 深色内部修正：取消 V52 的中央深红核心和椭圆血块。现在在主刀幕内部绘制 8~14 条独立黑红/深红筋络，每条都沿中心路径弯曲并按独立速度、相位持续流向刀锋；另有 7~13 条鲜红细拉丝靠近刀幕上下区域，用于模拟参考图中大量顺着斩击方向延伸的血肉沟槽、暗纹和高速红光。
- V53 眼睛群修正：眼睛不再作为规则队列节点排列，而是在刀幕内部按路径长度生成 12~44 只小眼睛，大小、上下偏移、倾角、虹膜颜色和眨眼相位均错开；眼睛只有在对应路径段实际进入当前可见刀幕后才出现，尾端扫过后消失，因此会随刀幕推进而逐批出现/离开。每只眼睛使用真实 Y 缩放执行睁开->闭合成细缝->重新睁开的独立动画。
- V53 默认视觉参数：`blade_light_lifetime = 0.74s`、普通/E.G.O 长度倍率 `1.06/1.18`、普通/E.G.O 基础宽度 `64/100`；刀幕仍直接使用真实攻击 `Area2D` 的世界位置、旋转和攻击尺寸作为空间基准，只影响视觉，不改变任何伤害、Hitbox、E.G.O 倍率或威胁检测。运行时节点标识更新为 `殷红迷雾_血肉刀幕_V53`。

### V54 殷红迷雾流带刀光修复

- `res://scripts/effects/殷红迷雾_刀光.gd`：V53 的宽多边形主体容易形成大块棱角红色肉块。V54 改成多条抗锯齿 `Line2D` 流带共同组成刀光：三层半透明基础血肉带负责整体弧形，9~16 条暗红内部流带负责深红血肉流动，12~22 条鲜红拉丝负责高速刀光纹理。
- 所有流带共享高采样三次贝塞尔中心线，并使用 `Line2D.width_curve` 在首尾自动收尖；`joint_mode=LINE_JOINT_ROUND`、`antialiased=true`，取消 V53 主轮廓随机抖动，因此不会再出现明显多边形棱线。
- V54 默认把刀光比例改得更长更窄：普通长度倍率 1.42、E.G.O 长度倍率 1.72；普通视觉宽度 52、E.G.O 视觉宽度 78；默认寿命 0.82 秒。
- 眼睛改为相对于“当前可见刀光头尾”计算：`u = lerp(tail_u, head_u, material_u)`。刀光向前推进时眼睛会与当前刀光一起移动，不再固定在整条攻击路径的某个世界位置；眼睛仍然独立眨眼。
- 运行时节点名更新为 `殷红迷雾_流带刀光_V54`，仅用于 Remote 场景树确认版本，不影响玩法。


### V55 殷红迷雾非对称刀光轮廓修复

- V55 本次修改项：`res://scripts/characters/月计/殷红迷雾.gd`、`res://scripts/effects/殷红迷雾_刀光.gd`、`PROJECT_PATH_MAP_FOR_AI_V34.md`。
- V55 斩击轮廓：按用户反馈撤销 V54 的“首尾同时收尖”。普通斩击、E.G.O 斩击、尸横遍野与处决斩击现在从拖尾后缘开始就保持粗厚，向刀光前缘逐步收尖；后缘不会再缩成细线。
- V55 突刺轮廓：突刺使用相反的非对称宽度语义——靠角色/拖尾后方保持尖细，越向突刺前方越粗，最前端维持厚度并使用圆润端帽，不会在前端再次收尖。
- V55 不规则形变：基础宽度曲线改为 20 段高采样有机曲线，叠加两组不同频率的小幅厚度起伏；三层主体还会产生轻微错位与慢速摆动，贝塞尔中心线本身增加小尺度有机波动。眼睛与内部深红/鲜红流带继续沿同一条动态中心线移动，因此不会与刀光脱离。
- V55 运行时节点名更新为 `殷红迷雾_非对称流带刀光_V55`，仅用于 Remote 场景树确认当前版本，不影响玩法。

### V56 殷红迷雾刀光方向语义与斩击轮廓重做

- V56 本次修改项：`res://scripts/characters/月计/殷红迷雾.gd`、`res://scripts/effects/殷红迷雾_刀光.gd`、`PROJECT_PATH_MAP_FOR_AI_V34.md`。
- V56 前后语义修正：严格按用户定义，刀光路径 `u=0` 表示“前/一开始”，`u=1` 表示“后/后面”。斩击改为前段较窄、越到后段越粗，路径末端保持厚度不再收尖；突刺改为前段粗厚、越到后段越细，并在路径末端收成尖端。该语义不再按角色空间上的前/后解释。
- V56 斩击主体重做：取消 V55 以多层 `Line2D.width_curve` 作为主体轮廓的方案。主刀光改为 `Node2D._draw()` 生成的高采样非对称血肉刀幕，多边形外缘与内缘使用两套独立、平滑插值的确定性随机控制值；斩击外侧边缘约为内侧的两倍厚度，内侧明显削入，形成弯月/挥砍刀面而不是规则对称丝带。
- V56 不规则表现：主中心弧、外缘、内缘均使用独立平滑随机轮廓；刀幕外缘额外生成多条细长甩丝，内部保留会沿路径实际移动的深红筋络与鲜红高速拉丝，避免规则几何弧带。随机 seed 仅由攻击尺寸、类型与扫击方向生成，保证多人端视觉一致。
- V56 眼睛移动：眼睛改为直接使用 `u = base_u + elapsed * flow_speed` 沿整条刀光绝对路径移动；仅在其 u 进入当前可见头尾范围时绘制。眼睛不再通过当前可见区间重新映射到近似固定位置，仍保留大量小眼睛、独立眨眼、大小/偏移/倾角差异。
- V56 运行时节点名更新为 `殷红迷雾_非对称血肉斩光_V56`，仅用于 Godot Remote 场景树确认当前版本，不影响玩法。


### V57 殷红迷雾破碎血肉刀光重做

- V57 本次修改项：`res://scripts/characters/月计/殷红迷雾.gd`、`res://scripts/effects/殷红迷雾_刀光.gd`、`PROJECT_PATH_MAP_FOR_AI_V34.md`。
- V57 取消波浪轮廓：按用户反馈，删除 V56 以连续平滑随机起伏塑形的思路。中心路径现在只保留基础斩击弧，并叠加少量局部结构性扭曲点；这些扭曲只在有限区间内生效，不形成重复波浪。刀幕厚度也改为少数局部肉块凸起/凹口，重点是缺肉、扭曲和不对称，而不是周期起伏。
- V57 尾部尖刺：普通/E.G.O 斩击、尸横遍野与处决斩击的路径后段会生成多枚大小、方向不同的血肉尖刺；同时后段额外加入单侧深凹口，使尾缘出现撕裂、分叉和刺状轮廓。突刺只保留少量较小侧刺，继续维持“前段粗、后段尖”的方向语义。
- V57 内部透明空洞：主刀幕不再是一整块填满的 Polygon。绘制时把血肉拆成多条连续纵向肉层，并依据多组不等边六边形 UV 破洞在对应区间断开，因此洞口区域不绘制任何红色主体，游戏背景会真正从刀幕内部透出来。深红筋络、鲜红拉丝和眼睛进入这些洞口时也会断开/隐藏，避免出现“洞是假的但纹理还盖在上面”。
- V57 深色内部：内部深红/黑红流带改成少量局部折弯轨迹，去掉周期正弦摆动；每条筋络仍然通过 phase 随时间沿刀幕方向移动，并在空洞处自动断开。
- V57 眼睛：眼睛继续沿绝对路径 `u = base_u + elapsed * flow_speed` 移动并独立眨眼；若当前眼睛进入真实透明破洞，则临时不绘制，离开洞口后继续出现。
- V57 运行时节点名更新为 `殷红迷雾_破碎血肉刀光_V57`，仅用于 Godot Remote 场景树确认当前版本，不影响玩法。


### V58 殷红迷雾刀光报错修复与主体重构

- V58 本次修改项：`res://scripts/characters/月计/殷红迷雾.gd`、`res://scripts/effects/殷红迷雾_刀光.gd`、`PROJECT_PATH_MAP_FOR_AI_V34.md`。
- V58 报错修复：用户实机出现 `殷红迷雾_刀光.gd:292 @ _draw_lane_polygon(): Invalid polygon data, triangulation failed.`。根因是 V57 用弯曲上下边界拼成长多边形后，某些帧会出现边界交叉/自相交，Godot 无法完成三角剖分。V58 删除长 lane polygon，主体改为小型局部网格单元，并把每个单元拆成两个非退化三角形绘制；面积过小的三角形直接跳过，因此不再向 `draw_colored_polygon()` 提交可能自相交的大多边形。
- V58 视觉重构：继续保持 `u=0` 为“前/一开始”、`u=1` 为“后/后面”。斩击前段较窄、后段持续变厚且末端不收尖；突刺前段粗、后段逐步收尖。取消连续波浪，中心线只保留单一斩击弧与 1~3 个局部歪折；轮廓只通过少量局部缺口、肉块凸起和后段撕裂改变。
- V58 尾刺与空洞：尾刺缩短并限制在后段局部，不再生成 V57 预览里过长的放射状大三角。空洞继续是真透明：网格中心落在破洞 UV 内时对应单元直接不绘制；洞口同时会截断深红沟槽、鲜红拉丝和眼睛。
- V58 眼睛移动：眼睛改为 `material_u = base_u + elapsed * flow_speed` 后，再映射到当前可见 `tail_u..head_u` 区间；因此刀光整体推进时眼睛会跟随刀光一起向前移动，同时保留各自独立眨眼相位。
- V58 运行时节点名更新为 `殷红迷雾_网格血肉刀光_V58`，仅用于 Godot Remote 场景树确认版本，不影响玩法。


### V59 殷红迷雾 GPU 刀光性能与美术重构

- V59 本次修改项：`res://scripts/characters/月计/殷红迷雾.gd`、`res://scripts/effects/殷红迷雾_刀光.gd`、`res://shaders/殷红迷雾_血肉拖尾.gdshader`、`PROJECT_PATH_MAP_FOR_AI_V34.md`；新增 `res://Images/characters/月计/殷红迷雾/刀光斩击遮罩.png` 与 `res://Images/characters/月计/殷红迷雾/刀光突刺遮罩.png`。
- V59 性能修复：撤销 V58 每帧 `queue_redraw()` 后生成数百至上千主体三角形、几十条流带，并为每只眼睛再次绘制大量三角扇的 CPU 自定义绘制方案。新效果每次攻击只创建 **1 个 Sprite2D + 1 个 ShaderMaterial**；每帧仅更新 `head_progress / tail_progress / opacity / anim_time` 四个 Shader 参数，不再逐帧构建网格、三角形、眼睛节点或调用 `draw_colored_polygon()`。
- V59 刀光轮廓：主体改用两张角色专属透明遮罩。斩击遮罩严格保持 `u=0`（一开始）较窄、`u=1`（后面）持续变粗，后半段加入不对称短刺、缺口、撕裂边和真实透明洞；突刺遮罩相反，`u=0` 一开始粗厚，随后逐步变窄并在 `u=1` 后面形成尖端。轮廓本身不做周期波浪。
- V59 深红流动：`res://shaders/殷红迷雾_血肉拖尾.gdshader` 重写为单 Pass CanvasItem Shader；在静态有机轮廓内部用多层 value-noise/fBm 沿 X 方向持续流动，形成不规则黑红沟槽、深红血肉块与更高速的鲜红纤维。透明洞直接来自遮罩，不需要 CPU 每帧判断/切割多边形。
- V59 小眼睛群：眼睛完全移到同一个 Shader 内按移动网格程序化生成；普通攻击与 E.G.O 使用不同密度。眼睛网格随 `anim_time` 沿刀光方向平移，每个格子用独立 hash 决定偏移、大小、倾角、虹膜和眨眼速度，因此大量小眼睛会跟随整片刀光持续移动并错峰睁合，不再创建几十个 Node2D/Polygon 绘制调用。
- V59 动画与定位：仍直接使用真实攻击 `Area2D` 的世界位置、旋转和实际攻击尺寸；遮罩左端按 `character_local_position` 锚到人物/武器侧，再从 `u=0` 向 `u=1` 推进。默认刀光寿命从 `0.82s` 收紧到 `0.72s`，减少同时存在的特效数量。所有改动纯视觉，不改变真实伤害、Hitbox、E.G.O 数值或威胁检测。
- V59 运行时节点名更新为 `殷红迷雾_GPU血肉刀光_V59`，仅用于 Godot Remote 场景树确认当前版本。


### V59 殷红迷雾 GPU 刀光重构（性能与视觉方向重置）

- V59 本次修改项：`res://scripts/characters/月计/殷红迷雾.gd`、`res://scripts/effects/殷红迷雾_刀光.gd`、`res://shaders/殷红迷雾_血肉拖尾.gdshader`；新增 `res://Images/characters/月计/殷红迷雾/刀光斩击遮罩.png` 与 `res://Images/characters/月计/殷红迷雾/刀光突刺遮罩.png`。
- V59 性能重构：撤销 V58 每帧 `_draw()` 大量三角网格、CPU 眼睛和 CPU 内部筋络。每次攻击只创建 1 个 `Sprite2D + ShaderMaterial`；CPU 每帧只更新 `head_progress`、`tail_progress`、`opacity`、`anim_time` 四个 Shader 参数，不再 `queue_redraw()`、不再每帧生成/三角剖分多边形，也不再为大量眼睛建立独立节点。
- V59 斩击形状：使用独立 `刀光斩击遮罩.png` 固定主轮廓。路径左侧 `u=0` 是“一开始”，轮廓较窄；越到右侧 `u=1` 越厚，末端保留明显撕裂尖刺、歪斜凸起和多个真实透明空洞，不使用连续波浪。
- V59 突刺形状：使用独立 `刀光突刺遮罩.png`；`u=0` 一开始粗厚并带局部破损/侧刺，越向 `u=1` 越细，末端收成尖端。斩击与突刺不再共用同一种轮廓算法。
- V59 GPU 内部动画：`殷红迷雾_血肉拖尾.gdshader` 在遮罩内部生成鲜红血肉主体、沿刀光方向持续流动的深红/黑红噪声沟槽和高速鲜红纤维；内部深色不是单条中心线。
- V59 GPU 眼睛群：眼睛全部在 Shader 中批量生成，不创建眼睛 Node。眼睛随 `anim_time` 沿刀光方向移动，每个网格单元独立决定大小、倾角、虹膜和眨眼相位，并且只显示在遮罩真实血肉区域，不覆盖透明空洞。
- V59 刀光推进：Shader 使用 `head_progress` / `tail_progress` 做整片刀光的头部推进与尾部追赶消散；主轮廓不再运行时重建，因此不会再出现 `Invalid polygon data, triangulation failed`。
- V59 运行时节点名：`殷红迷雾_GPU血肉刀光_V59`，仅用于 Godot Remote 场景树确认版本，不影响玩法。


### V60 大规模战斗性能优化（100+ 单位公共路径）

- 根因确认：`res://scripts/world.gd` 虽然早已有 `nearest_enemy_refresh_interval = 0.10` 和“Nearest_Enemy 原版每 physics tick O(n²)”的注释，但原 `_physics_process()` 从未使用该间隔，仍然每 60Hz 物理帧让所有单位互相完整扫描。100 单位时约 9,900 次候选判断/物理帧，60Hz 约 594,000 次/秒，并且无论角色类型都会付出该成本。
- V60 最近敌人：改为分帧预算调度。每个单位平均仍约 0.10 秒刷新一次最近敌人，但 N 个单位均匀摊到连续物理帧，不再同一帧执行完整 O(N²) 扫描，也不再产生 0.1 秒一次的大尖峰。
- V60 SceneTree 扫描：服务员门、地图挤回、越界规则复用 `_physics_process()` 已经取得的角色数组，不再各自重复 `get_nodes_in_group("Ball")`。地图挤回/越界规则降为默认 20Hz，越界计时使用累计 delta，规则时间不丢失。
- V60 渲染帧 housekeeping：血条 Z、随机方向、阵营着色/恢复从“每渲染帧扫描所有 Ball”改为默认 20Hz；只有属性真的不一致时才写血条 Z。
- V60 Buff：四阶段 Buff 循环先筛出 `Buff_Dic` 非空角色；没有 Buff 的普通单位不再四次进入无意义循环。
- V60 `res://classes/ball.gd`：角色侧边状态 UI 改为真正懒加载，普通无状态单位出生时不再创建 CharacterSideStatus 的多层 Control/VBox 节点。第一次真正显示状态文字时才创建。
- V60 `res://scripts/ui/character_side_status_ui.gd`：临时状态全部结束且无永久状态 1.5 秒后自动释放空 UI；位置跟随不再每帧重写不变的布局尺寸。
- V60 `res://classes/ball.gd`：`motion_params` / `sprite_flip_h` Shader 能力检测按 Shader Resource 缓存，不再每个单位每个物理帧反复执行 `shader.code.find()`；移动软体 Shader 参数增加近似值去重。
- V60 `res://classes/state_machine.gd`：稳定状态采用无 Dictionary 分配快速路径；项目实际冷却只维护 Attack/Skill 两项，不再每单位每帧遍历整个 `last_state_dis` 并执行 `str()`。
- V60 不改变：角色伤害、攻速、技能机制、碰撞层/掩码、CharacterBody2D 实体碰撞、友伤规则、Hitbox/Hurtbox 真实命中、60Hz 物理 tick。若后续 Profiler 仍显示 Physics 2D 为主瓶颈，再单独处理密集 CharacterBody2D 碰撞对，而不是本轮直接牺牲碰撞玩法。
- V60 本次新增进入累计更新包的原项目文件：`res://classes/ball.gd`、`res://classes/state_machine.gd`、`res://scripts/world.gd`、`res://scripts/ui/character_side_status_ui.gd`。


### V61 V60 解析错误修复

- 修复 `res://scripts/world.gd` 的 `figure_buffs()`：V60 在把 Buff 单位预筛选加入函数时错误破坏了缩进，导致 `if process_time >= 1` 脱离 `buff / b / buff_to_delete` 所在循环作用域，使 `class_name World` 无法解析。
- 该错误会级联影响 `res://classes/ball.gd`，因为 ball 基类中存在 `var world:World` 强类型引用；因此编辑器会同时显示 `world.gd`、`ball.gd` 以及所有依赖它们的脚本 Parse error。V61 修复根错误，不需要回退 ball 的 V60 性能缓存。
- V60 的性能优化全部保留：Nearest_Enemy 分帧预算、地图规则降频并复用单位列表、空 Buff 角色跳过四阶段处理、侧边状态 UI 懒加载、Shader 能力缓存、状态机稳定状态快速路径。
- `figure_buffs()` 的原有游戏语义恢复：属性 Buff 仍按四阶段应用；毒伤仍只在 `process_time >= 1` 时触发；持续时间仍逐帧减少；寄生结束处理仍在对应来源字典内执行。


### V62 100+ 单位 Physics 2D 自适应优化

- 用户实测 V60/V61 的脚本扫描优化后，100 个任意单位仍然明显卡顿，因此确认最近敌人 O(N²) 不是主要瓶颈。本轮转向公共 `CharacterBody2D` 物理路径。
- 当前基础角色场景 `res://scenes/ball.tscn` 的角色根节点是 `CharacterBody2D`，默认 `collision_layer = 2`、`collision_mask = 3`，因此角色身体会扫描 Layer 1 墙体和 Layer 2 其他角色。角色密集时 Physics 2D 会形成大量角色↔角色碰撞对；每个活动角色还会调用 `move_and_slide()`。
- V62 在 `res://scripts/world.gd` 新增“大规模战斗性能”参数。默认单位达到 64 个启用，下降到 52 个以下才关闭，避免阈值附近反复切换。
- 大规模模式下，仅从角色根 `CharacterBody2D` 的 collision mask 中关闭 Layer 2 角色身体扫描；Layer 1 墙体仍保留。`self_hitbox` / `self_hurtbox` 的 collision layer/mask 完全不改，所以真实攻击、受伤、技能 Area2D 判定继续存在。
- 角色身体互撞改由 World 统一空间网格做轻量软分离：只检查当前格及相邻八格，复杂度接近 O(N + 局部邻居对)，分离速度仍通过角色原本 `move_and_slide()` 移动，因此墙体碰撞仍由 Godot Physics 2D 处理，不直接写 `global_position`。
- 大规模模式下 `CharacterBody2D.max_slides` 临时降为 1；退出模式时恢复场景原值。Godot 默认 `max_slides = 4`，代表一次 `move_and_slide()` 最多允许多次改变方向；密集角色互撞移除后不再需要这一高上限。
- 大规模模式下移动软体纯视觉参数按实例错峰到约 30Hz；玩法物理、AI、攻击、伤害仍保持项目原物理 Tick。
- 单机且没有 Multiplayer Peer 时，大规模模式会暂时禁用每个角色的 `MultiplayerSynchronizer` 内部处理；退出模式恢复。真实多人连接时不禁用同步器。
- World Inspector 可调整：`large_battle_unit_threshold`、`large_battle_disable_below`、`large_battle_grid_cell_size`、`large_battle_separation_margin`、`large_battle_separation_response`、`large_battle_separation_max_speed`。
- `large_battle_print_monitor = true` 时每秒打印一次 Godot `PHYSICS_2D_COLLISION_PAIRS` 与 Physics Process 毫秒数，用于直接验证角色身体碰撞对是否下降；默认关闭，不产生日志成本。
- V60/V61 的 Nearest_Enemy 分帧、Buff 预筛选、侧边 UI 懒加载、Shader 能力缓存和状态机快速路径继续保留。


### V63 meme 新角色：大狗叫（Dog barking）

- 新增可选角色 `res://scenes/characters/meme/大狗叫.tscn`，脚本为 `res://scripts/characters/meme/大狗叫.gd`，继续放在既有小写 `meme` 分类，不创建 `Meme/` 等同义目录。
- 角色英文翻译按用户指定写入 `translations.csv`：`大狗叫 -> Dog barking`；附属单位翻译为 `小狗叫 -> Puppy barking`。
- 大狗叫没有普通攻击/手动技能按钮；核心机制自动运行。发生碰撞（`ContactArea` 的真实 `body_entered`）时会短叫；平时也会按默认约 `1.65s ± 0.22s` 的小幅随机间隔短叫。每次短叫都会累计次数，默认累计 5 次后进入约 3.2 秒持续犬吠阶段。
- 持续犬吠阶段启用真实 `Area2D + CircleShape2D` 声波伤害圆，默认每 `0.28s` 结算一次：大狗半径约 `145px`、每波基础伤害 `11`、小幅击退。伤害仍调用目标现有 `receive_spatial_damage()`，并尊重阵营/友伤和大狗当前伤害输出禁用状态。
- 碰撞短叫与声波伤害不依赖 CharacterBody2D 身体互撞，因此兼容 V62 的 64+ 单位大规模战斗模式：即使角色身体互撞被切换为软分离，`ContactArea` / `DamageArea` 仍按 Layer 2 真实重叠工作。
- 新增共享脚本 `res://scripts/characters/meme/狗叫机制.gd`，大狗与小狗共用同一套“碰撞短叫 + 随机短叫 + 累计次数 + 持续犬吠 + 连续声波”逻辑，避免复制两套状态机。
- 新增附属场景 `res://scenes/creatures/小狗叫.tscn` 与脚本 `res://scripts/creatures/小狗叫.gd`。小狗不是 `ball`，不加入 `Ball` 组，没有 `Health_Bar`、`hurtbox`、生命值或可受击入口，因此不会被锁定或受到伤害；它以 `top_level` 世界坐标平滑跟随大狗，并独立累计自己的短叫次数和持续犬吠。
- 小狗机制与大狗相同，但为附属单位使用较小声波数值：默认半径约 `96px`、每波基础伤害 `5`、较轻击退；伤害来源仍归属大狗，便于伤害统计和友伤判定。
- 新增 `res://scripts/effects/狗叫声波.gd`：每次实际伤害脉冲会在发声原点生成两层短命扩散圆环；视觉节点不参与伤害。真实威胁区域由 `狗叫机制.gd` 的 `DamageArea/CollisionShape2D` 提供，并注册 `AI_Hazard/get_ai_hazard_info()`，符合 `global/注释.gd` 关于“不要用角色半径兜底冒充伤害区域”的要求。
- 本轮新增 4 个原创 WAV：`大狗短叫.wav`、`大狗持续叫.wav`、`小狗短叫.wav`、`小狗持续叫.wav`，均为本轮程序合成，不使用外部受版权限制的音频；场景内 `AudioStreamPlayer2D` 会被现有 `global/audios.gd` 自动路由到 GameplayRecord 总线。
- 视觉复用项目内已确认存在并已被 `布鲁斯_狗.gd` 使用的 `res://Images/characters/布鲁斯/狗坐下.png`、`狗跑步.png`、`狗咬人.png`；没有猜测或新建另一套同义 Images 目录。


### V64 大狗叫附属小狗碰撞与软跟随修复

- V64 本次修改项：`res://scripts/creatures/小狗叫.gd`、`res://scenes/creatures/小狗叫.tscn`、`res://scripts/characters/meme/狗叫机制.gd`。
- 小狗从纯 `Node2D` 改为独立 `CharacterBody2D`，新增直属真实 `CollisionShape2D + CircleShape2D`。默认身体位于 Layer 2、Mask 3，可与 Layer 1 墙体和 Layer 2 普通角色产生实体碰撞；仍不创建 `hurtbox`、HealthBar、生命值或 `Ball` 组成员，因此不会成为普通角色攻击/锁定目标。
- 小狗与自己的大狗主人建立双向 `add_collision_exception_with()`，避免附属小狗持续顶住主人；它仍可正常撞墙和其他单位。
- 碰撞短叫增加双保险：原 `ContactArea.body_entered` 保留，同时小狗每次 `move_and_slide()` 后遍历 `get_slide_collision_count()` / `get_slide_collision()`，将真实实体碰撞对象送入共享 `notify_collision()`；两条路径共用原 contact cooldown，不会同一碰撞疯狂叠音。
- 小狗跟随从固定匀速 `global_position.move_toward()` 改为物理软跟随。偏好跟随点先做指数平滑，再使用 `velocity.move_toward()` 加减速并通过 `move_and_slide()` 移动；近处存在默认 18px 舒适区，小狗可以自然落后/超前，不再死死吸附到固定点。
- 跟随速度按距离连续变化：近处默认约 55px/s，中等距离约 155px/s，拉开后最高约 335px/s；所以同一只小狗会根据实际距离“有时慢、有时快”。这些值以及 acceleration/deceleration、dead zone、catchup distance 均可在小狗场景 Inspector 调整。
- 只有主人出生/传送导致距离超过默认约 560px 时才进行一次紧急位置同步；普通战斗跟随不会瞬移。
- 主人死亡/失效后，小狗隐藏并将自身 collision layer/mask 设为 0，同时关闭狗叫机制，避免不可见碰撞体继续挡路。


### V65 大狗叫/小狗叫音频、声波与墙体弹性重构

- 接入用户提供的 `res://audio/characters/meme/大狗叫/大狗.mp3` 与 `res://audio/characters/meme/大狗叫/叫.mp3`。原始文件保留在同一现有角色音频目录，不新建同义 Audio/Voices 目录。
- `大狗.mp3` 原始长度约 0.48 秒；V65 使用 FFmpeg `atempo` 预生成 `大狗_节奏0.wav` ～ `大狗_节奏4.wav` 五档，节奏倍率依次约 1.00 / 1.12 / 1.28 / 1.46 / 1.68。运行时 `AudioStreamPlayer2D.pitch_scale` 固定 1.0，因此不会通过采样率改变音高。
- 普通叫累计次数越高，不但 WAV 本身越短，下一次自动叫的间隔也从默认 1.65 秒平滑缩短到约 0.48 秒；最后一声普通叫完整播放结束后才进入攻击叫。攻击叫结束后 `_sound_count` 清零，下一轮恢复第一档慢节奏。
- `叫.mp3` 原始长度约 0.552 秒；V65 预生成 `叫_延长.wav`（约 1.65 秒），使用 atempo 链降低 tempo 并保持 pitch。攻击阶段播放该延长版，不循环。
- “只有叫没停止就持续攻击”改为硬规则：DamageArea 只有攻击音频 `playing == true` 时持续按 `wave_interval` 发出声波；`AudioStreamPlayer2D.finished` 一触发就立即关闭 DamageArea、停止攻击并恢复蓄力节奏，不再使用独立 `howl_duration`。
- 声波视觉改为单个白色 `Line2D` 描边圆：从中心附近扩散到真实伤害半径，同时 alpha 平滑衰减到 0；删除旧的黄/橙双层圆环。
- 大狗默认声波仍为较大范围（约 150px、11 基础伤害），命中有击退（约 14px / 230px/s）。小狗机制流程相同，但默认只有约 52px 范围、2 基础伤害、3px / 80px/s 轻击退，范围与伤害均显著低于大狗。
- 小狗撞墙新增 `wall_bounce_elasticity` / `wall_bounce_hold_time`：`move_and_slide()` 返回墙体碰撞后，用碰撞法线 `bounce()` 反射进入速度，短时间优先保持反弹速度，再平滑重新接回软跟随；撞其他角色仍使用正常物理滑动。
- 大小狗短叫和攻击叫都不再运行时随机改 pitch；大小狗只通过音量区分。所有“变快/拉长”都由预处理音频承担，避免运行时 `pitch_scale` 同时改变节奏和音高。


### V66 大狗叫/小狗叫长蓄力、长攻击音频与小狗墙体安全修复

- V66 本次使用用户上传 `大狗.mp3` 与 `叫.mp3` 重新生成实际运行音频。`大狗.mp3` 原始约 0.48 秒，生成 `大狗_节奏0.wav` ～ `大狗_节奏9.wav` 十档；使用 FFmpeg Rubber Band 调整 tempo，`pitch=1.0` 且 `formant=preserved`，运行时 `AudioStreamPlayer2D.pitch_scale` 固定 1.0。
- 大狗/小狗从默认 5 次蓄力提高到 18 次。18 次短叫按进度映射到 10 档音频，并且自动叫间隔从约 1.85 秒逐渐缩短到约 0.30 秒；长攻击叫结束后 `_sound_count = 0`，下一轮恢复最慢的第一档。
- `叫.mp3` 不做极端慢放。V66 使用原波形重复 + 约 70ms 交叉淡化生成约 8 秒 `叫_延长.wav`，不改变单次叫声的播放速度、采样率音高或 formant，避免长倍数 time-stretch 产生金属/颤动伪影。
- “只有叫没停止才持续攻击”继续作为硬规则：权威端只在 `HowlAudio.playing == true` 时按 `wave_interval` 结算声波；音频 `finished` 后同帧关闭 DamageArea、清理声波视觉并恢复第一档蓄力。
- 大狗声波视觉简化为任何时刻最多 1 个 `Line2D` 白色细描边圆；没有内圈、外圈、颜色层或残影。大狗默认声波间隔 0.58 秒、白圈寿命 0.38 秒，因此正常情况下不会多圈叠加。
- 大狗声波默认范围 145、伤害 11、击退距离 16 / 速度 250。小狗明显缩小到范围 34、伤害 1、击退距离 1.5 / 速度 55，且声波间隔 0.78 秒。
- 小狗不再允许出生/紧急跟随直接把 `global_position` 写到未检查目标。所有安全救援点都必须通过小狗真实 CircleShape2D 对 Layer1 墙的 `intersect_shape()` 检查，并且主人到候选点之间的 Layer1 `intersect_ray()` 必须无墙，因此不会把小狗放到墙另一侧/地图外侧。
- 小狗正常追赶仍全程 `move_and_slide()`；墙体命中按碰撞法线对请求速度执行 `bounce()`，默认弹性 0.92、保持 0.18 秒。若小狗与主人被墙长期隔开约 0.85 秒且距离 >= 70，才执行一次上述安全救援，处理此前可能出现的“墙外卡住”。
- 小狗场景 `max_slides` 恢复为 4、`safe_margin` 为 0.08，以接近项目 ball 默认 CharacterBody2D 的墙体恢复/滑动容错；小狗仍无 Hurtbox、无生命值、不会被攻击。
- V66 本次修改/新增：`scripts/characters/meme/狗叫机制.gd`、`scripts/creatures/小狗叫.gd`、`scripts/effects/狗叫声波.gd`、`scenes/characters/meme/大狗叫.tscn`、`scenes/creatures/小狗叫.tscn`、`audio/characters/meme/大狗叫/大狗_节奏0.wav` ～ `大狗_节奏9.wav`、`audio/characters/meme/大狗叫/叫_延长.wav`。

### V67 大狗叫连续声波、音量与持续拉长攻击叫

- V67 修改：`res://scripts/characters/meme/狗叫机制.gd`、`res://scripts/effects/狗叫声波.gd`、`res://scenes/characters/meme/大狗叫.tscn`、`res://scenes/creatures/小狗叫.tscn`、`res://audio/characters/meme/大狗叫/叫_延长.wav`。
- 声波视觉不再“新波出现就删除旧波”。攻击叫播放期间按声波节奏不断加入新白圈；每枚白圈独立扩散和渐隐，因此多个圆可以同时存在。为了避免大量 SceneTree 节点，同一只狗只创建一个轻量声波管理器，内部统一绘制所有存活白圈。
- 大狗声波默认间隔从 0.58s 改为 0.30s，白圈寿命约 0.92s，所以稳定攻击时通常可同时看到约 3 个连续扩散圆；小狗默认 0.40s、寿命约 0.72s。单波伤害/击退同步降低，使总 DPS 与旧版接近，不因为单纯提高声波频率而数值暴涨。
- 整体音量明显提高：大狗短叫默认 1.5dB、攻击叫 3.0dB，最大听距 2200、衰减指数 0.45；小狗短叫 0dB、攻击叫 1.5dB，最大听距 1400、衰减指数 0.55。
- `叫_延长.wav` 不再由多次原音拼接。V67 从用户原始 `叫.mp3` 重新使用 FFmpeg Rubber Band 做一次连续时间拉伸，最终长度约 9.991s；tempo 单独降低、pitch=1.0、formant=preserved，运行时 `AudioStreamPlayer2D.pitch_scale` 继续固定 1.0。
- 攻击仍严格绑定攻击叫播放器：只有该约 10 秒持续拉长音频仍在播放时，权威端才不断结算声波；音频自然结束后停止产生新声波并恢复蓄力。已经发出的白圈只完成自己的透明渐隐，不再被强制删除。



### V69 大狗叫/小狗叫碰撞蓄力与弹性修正

- 大狗与小狗不再定时/随机自动短叫；只有真实碰撞才播放各自短叫音频并把蓄力进度增加 1。默认 24 次有效碰撞后进入持续攻击叫。
- 大狗除了 ContactArea 外，还读取 ball 根 CharacterBody2D 最近一次 `move_and_slide()` 的真实 slide collision；墙和单位身体碰撞都能推进进度，两路共用 contact cooldown 防止一次碰撞重复计数。
- 小狗从 `move_and_slide()` 改为 `move_and_collide()` 手动反射。墙体默认弹性 1.00，其他角色默认 0.82；碰撞时使用真实 normal 对请求速度 `bounce()`，并把 remainder 反射补走一次，避免“只是贴墙滑动、看不出弹性”。
- 大狗视觉默认最大本地尺寸从 330 降到 225，同时 CharacterAutoFit 视觉倍率从 1.18 降到 0.92；不改变大狗生命或声波范围。
- 大狗持续攻击改为默认每 0.10 秒一波、基础伤害 8.0。用户提供的大狗持续叫约 4.05 秒，因此完整播放可产生约 40 次声波。
- 小狗仍明显弱化：默认范围 32px、每 0.16 秒一波、基础伤害 1.5、击退距离 1.2、击退速度 65；其持续叫约 4.21 秒，可产生约 26 次声波。
- 大小狗攻击仍只在各自原始持续叫 MP3 的 `AudioStreamPlayer2D.playing == true` 时进行；音频结束后停止产生新波、进度清零，运行时 `pitch_scale = 1.0`。


### V70 V69 狗叫机制解析错误修复

- 修复 `res://scripts/characters/meme/狗叫机制.gd` 第 285 行附近的 GDScript Parse Error。
- V69 删除“攻击结束后自动重新安排短叫”时，只删除了 `if reschedule:` 内部语句，却遗留了空 `if` 块；GDScript 的 `if:` 后必须存在缩进代码，因此编辑器报 `Expected indented block after "if" block`。
- V70 删除该空块，并把 `_stop_howl(reschedule:bool)` 的未使用参数改名为 `_reschedule`；现有位置参数调用保持兼容。
- 本轮不改变 V69 已确认的玩法：大小狗只有真实碰撞才短叫并增加进度、默认 24 次碰撞进入持续叫；大狗缩小、持续攻击 0.10 秒一波/8 基础伤害；小狗 `move_and_collide()` 手动弹性和弱化声波数值均保持不变。
- 另外扫描 `狗叫机制.gd`、`大狗叫.gd`、`小狗叫.gd` 的常见控制块/函数块，未再发现同类“块声明后没有实际缩进代码”的残留。


### V71 小狗叫改为独立 ball / 无生命不可瞄准 / 单向碰撞

- `res://scenes/creatures/小狗叫.tscn` 不再是手写 `CharacterBody2D` 场景；现在直接 `instance=ExtResource("res://scenes/ball.tscn")`，脚本 `res://scripts/creatures/小狗叫.gd` 改为 `extends ball`。因此小狗拥有项目标准 ball 的 CharacterBody2D/状态机/公共字段基础，但自己覆写移动、伤害与目标资格。
- 小狗 `_ready()` 设置 `Type = Ball_Type.Creature`、`Master = 大狗`、`Team = 大狗.Team` 后调用 `super._ready()`；随后从普通 `"Ball"` 组移除并加入 `"DogBarkingCompanion"`。它仍是真正 ball 对象，但不会被绝大多数按 Ball 组枚举的索敌、胜负、训练统计等逻辑当成普通战斗单位。
- 新增 `is_combat_targetable() -> false`；同时关闭 inherited `hurtbox` 的 layer/mask/monitoring/monitorable 并禁用其 CollisionShape2D。所有 `receive_*_damage()`、`take_damage()` 和 `hit_white()` 入口均拒绝伤害，因此小狗功能上没有生命，也不会被 Area2D/Hitbox 或直接伤害接口打中。HealthBar 被隐藏并停止处理。
- 小狗根身体使用专用 `collision_layer = 8`（项目此前未使用的第 4 身体层），`collision_mask = 3`。这样小狗自己会扫描 Layer1 墙 + Layer2 普通角色/大狗并发生真实 `move_and_collide()` 反弹；而普通 ball/大狗默认 `collision_mask = 3` 不扫描 Layer8，所以小狗不会阻挡、推挤或改变大狗的运动，形成“只对小狗生效”的单向碰撞。
- 不再给大小狗建立 collision exception；小狗撞大狗会得到真实 KinematicCollision2D normal 并按 `character_bounce_elasticity` 反弹。
- 大狗的 BarkMechanic `ContactArea` 默认 mask=3，也不会扫描 Layer8 小狗；同时 `狗叫机制.gd` 新增逻辑保险：大狗机制遇到 `is_dog_barking_companion()==true` 的身体直接忽略，因此即使未来碰撞层被改，小狗碰大狗也绝不会增加大狗的狗叫进度。
- 小狗自己的 BarkMechanic 仍允许把“撞到大狗”视为小狗自身的一次有效碰撞，因此小狗会正常播放自己的短叫并增加自己的进度；这不会反馈到大狗。
- 小狗主人死亡后直接 `queue_free()`，避免不可受伤的附属 ball 在主人死亡后残留场景。


### V72 小狗主动追大狗身后 / 绕主人不穿模

- 小狗的默认偏好点改为大狗正后方：`follow_distance = 62`、`follow_side_offset = 0`、`follow_dead_zone = 8`。大狗移动或改变朝向时，小狗会持续主动追新的身后位置，不再把出生点/某个固定世界位置当目标。
- 新增主人避障导航。每帧先计算真正的“身后点”；如果“小狗当前位置 → 身后点”的直线与大狗实际身体安全圆相交，小狗不会直线穿过去，而是进入 `routing_around_master` 状态。
- 绕行时根据小狗当前位于大狗左侧还是右侧选择固定绕行方向，先跑到大狗侧后方的 orbit waypoint，再在进入后半侧且直线已经不切过大狗身体后转向真正身后点。绕行侧在一次路径过程中保持稳定，避免左右抖动。
- 大狗安全圆优先读取公共 `ball.get_crowd_separation_radius_world()` 的真实世界碰撞尺寸，再叠加小狗自身 `body_radius` 与 `master_avoidance_margin`，不是按图片尺寸猜测。
- 如果首选绕行侧贴墙，会尝试另一侧；墙体检查继续使用 Layer1 的真实 PhysicsShape/Ray 查询。
- 小狗仍使用 V71 的 `collision_layer=8 / collision_mask=3` 单向实体碰撞，所以它在运动过程中会真实 `move_and_collide()` 到大狗并反弹；大狗自己仍不扫描 Layer8，因此不会被小狗推、挡或增加狗叫进度。
- 极端救援路径也不再允许直接把小狗放到大狗中心；掉队救援会先经过同一套 navigation anchor，因此不会用坐标瞬移把小狗从大狗前方穿到背后。


### V73 狗叫伤害调整 / 凑企鹅飞踢命中修复

- 大狗叫持续声波基础伤害从 8 提高到 10；`狗叫机制.gd` 默认值与 `大狗叫.tscn` 保存值同步更新。
- 小狗叫持续声波基础伤害从 1.5 提高到 5；小狗仍保持 32px 小范围、0.16 秒一波和很小击退，只提高单波伤害。
- 本轮把用户原项目 `res://scripts/characters/meme/凑企鹅.gd` 加入累计更新包并修复飞踢。原实现冲刺使用 `move_and_slide()`，CharacterBody2D 先碰到敌人后会自动沿表面滑动；同时伤害又只等 FlyKickArea/Hurtbox overlap，于是可能出现“视觉已经踢到，伤害圆还差一点，然后企鹅从旁边滑走”。
- V73 飞踢冲刺改用 `move_and_collide(requested_motion)`。实体身体第一次碰到合法敌方 ball 时立即按飞踢命中结算并结束冲刺，不再允许把敌人当成可滑过去的表面；撞墙仍立即结束。
- 撞到非敌方 ball 时只对剩余位移做一次 `remainder.slide(normal)`，保留队友阻挡时的移动容错。
- 新增基于真实 `FlyKickArea/CollisionShape2D` 与目标真实 `hurtbox/CollisionShape2D` 的 `Shape2D.collide_with_motion()` 连续扫掠。它检查本帧完整冲刺运动，即使高速一帧跨过 Hurtbox、或大规模模式下角色根身体不互撞，也能按真实形状轨迹捕获飞踢目标。
- 原 `FlyKickArea.get_overlapping_areas()` 仍保留作为最终兜底。当前飞踢命中链为：实体 CharacterBody2D 接触 → 连续 Shape2D 扫掠 → Area2D overlap；墙体碰撞优先阻断，不会隔墙命中。
- 飞踢伤害 58、速度 650、最大距离 230、击退、撞墙追加伤害和眩晕均未修改。


### V74 大狗范围/伤害调整与碰撞短叫真正叠加

- 大狗持续声波基础范围从 145px 降到 130px，基础伤害从 10 提高到 15；0.10 秒声波间隔、击退与持续攻击音频均保持 V73 不变。
- V73 虽然使用 `ShortBarkAudio` + `ShortBarkAudioB` 两个 AudioStreamPlayer2D 交替短叫，但二者 `max_polyphony` 仍为 Godot 默认 1。当两台都还在播放而第三次碰撞再次触发 `play()` 时，会在忙碌播放器上超过 polyphony 上限并截断该播放器最旧 voice。
- V74 大狗两台短叫播放器各设 `max_polyphony = 12`，合计最多可同时保留 24 个 short-bark voice；在当前 0.24 秒碰撞发声冷却和约 0.94 秒短叫长度下，正常情况下不会达到上限，因此后一声不会停止前一声。
- 小狗两台短叫播放器各设 `max_polyphony = 8`，保持同样的叠加语义；小狗范围 32px、伤害 5、0.16 秒攻击波频率等 V73 数值不变。
- `狗叫机制.gd::_configure_runtime_nodes()` 运行时也会重新设置对应 polyphony，因此即使场景资源被旧缓存加载，进入游戏后仍会得到大狗 12 / 小狗 8 的多声部配置。
- 所有短叫继续使用用户原始 MP3、`pitch_scale = 1.0`，叠加只增加并行 voice，不改变每一声的音高、速度或长度。


### V75 狗碰撞短叫单播放槽 / 按进度逐档加速

- 大狗与小狗碰撞短叫改回严格单播放槽。`ShortBarkAudio.max_polyphony = 1`；每次新的有效碰撞短叫开始前都会先 `stop()` 前一声，因此后一声一定会立即停止前一声，不再叠加。
- 旧 `ShortBarkAudioB` 节点为兼容场景结构继续保留，但运行时始终 stop，并设置 `PROCESS_MODE_DISABLED`；不再参与任何短叫播放。
- 碰撞蓄力阈值仍为 24 次，只有真实碰撞会增加进度。短叫速度现在直接随这一碰撞进度增加，而不是靠缩短自动发声间隔；项目仍不存在定时自动短叫。
- 为避免 Godot `pitch_scale` 同时改变音高与节奏，本轮不在运行时用 pitch_scale 变速。基于用户当前 `大狗大狗.MP3` / `小狗小狗.MP3` 离线生成 12 档 tempo 文件，Rubber Band 使用 `pitch=1.0` + `formant=preserved`。
- 12 档 tempo 为：0.70 / 0.75 / 0.80 / 0.86 / 0.92 / 0.98 / 1.04 / 1.10 / 1.16 / 1.22 / 1.28 / 1.34。第一批碰撞明显比原音慢，随后大约每 2 次碰撞上升一档，接近 24 次阈值时明显快于原音。
- 多人模式下速度档索引由 authority 根据 `_sound_count` 计算后作为 RPC 参数传给所有客户端，避免远端本地碰撞计数不同步导致播放速度不一致。
- 持续攻击叫 `大狗叫.MP3` / `小狗叫.MP3`、声波伤害/范围和 V74 的大狗 130px / 15 伤害、小狗 32px / 5 伤害均不变。


### V76 大小狗缩小 / 取消短叫时间拉伸

- 大狗视觉默认最大本地尺寸从 225 降到 185；根 scale、实体碰撞、130px 声波范围和 15 基础声波伤害都不变。
- 小狗视觉默认世界尺寸从 34px 降到 27px；独立 ball、15px 身体半径、单向碰撞、弹性、主动绕行到大狗身后等 V72/V71 机制不变。
- 用户实测 V75 只有 1.0x 原速短叫自然，所有保持音高的慢速/快速 time-stretch 档仍然难听。V76 因此彻底取消运行时对 24 个 `*_速度01~12.wav` 的引用；这些旧文件为累计兼容仍可留在完整更新包中，但不会 preload、不会播放，也不会影响运行时。
- 大狗碰撞短叫固定使用用户原始 `大狗大狗.MP3`，小狗固定使用原始 `小狗小狗.MP3`；`pitch_scale` 永远为 1.0。后一声仍严格 `stop()` 前一声再播放，不叠加。
- “一开始慢、随着进度越来越快”改为发声节奏而不是音频 time-stretch：默认 0 进度约 0.62 秒碰撞发声冷却，进度接近 24 时平滑降到约 0.16 秒；曲线指数默认 1.25。每一声内部的语速、音高和长度完全保持用户原始录音。
- 碰撞进度仍只在通过当前冷却后的有效真实碰撞上 +1；没有碰撞不会自动叫或自动加进度。


### V77 大狗/小狗视觉继续缩小

- 大狗 `res://scripts/characters/meme/大狗叫.gd` 的 `visual_max_local_size` 从 185 降到 155；只缩用户提供的大狗普通/持续叫图片，不修改根 `CharacterBody2D` scale、实体碰撞、130px 声波范围、15 基础伤害、24 次碰撞蓄力或音频机制。
- 小狗 `res://scripts/creatures/小狗叫.gd` 的 `visual_max_world_size` 从 27px 降到 22px；只缩用户提供的小狗普通/持续叫图片，不修改 15px 真实身体半径、独立 ball、单向碰撞、弹性、绕行到大狗身后、32px 声波范围或 5 基础伤害。
- V76 的“短叫永远使用用户原始正常速度 MP3；前期碰撞发声冷却长、进度越高冷却越短；后一声停止前一声”的声音机制全部保持不变。


### V78 通用眩晕角色抖动

- 在公共 `res://classes/ball.gd` 的既有 `begin_stun_visual()` / `end_stun_visual()` 真眩晕生命周期上加入角色视觉抖动。严格遵守项目原注释：不直接监听 `dizziness`，因为击退过程、伞夫固定等控制锁也会临时设置 dizziness；只有真正进入 KnockbackEffect 的 stun stage / `apply_stun()` 才抖动。
- 抖动只修改 `Graphics.position`，不会修改 ball 根 `CharacterBody2D.global_position`，因此实体 CollisionShape2D、Hitbox、Hurtbox、墙体/角色碰撞和伤害几何完全不抖。
- 默认世界屏幕振幅约 2.6px、主频约 21Hz，并叠加不同非整数倍频率的 X/Y 颤动，使效果不是机械的单轴往返。Inspector 新增 `stun_shake_enabled`、`stun_shake_world_strength`、`stun_shake_frequency`。
- 抖动位移先按世界像素生成，再通过 `to_local()` 转成角色根节点局部位移，所以不同人物的根 scale 不会导致抖动视觉强度成倍变化。
- 使用“上一帧只由眩晕系统添加的 offset”做可逆叠加；如果人物专属动画在眩晕期间主动重写 `Graphics.position`，系统会把新位置作为新基准，不强行覆盖。最后一个 stun visual 引用释放时只撤销自身最后一次偏移。
- 联机时只由 authority 写 `Graphics` transform，避免远端客户端在同步位置上再次本地叠加一次抖动；单机正常本地执行。
- 现有星星眩晕图标、apply_stun、击退控制锁、眩晕时长和所有角色数值均未修改。

### V78 当前累计完整更新包详细目录

```text
Images/characters/meme/大狗叫/大狗.png
Images/characters/meme/大狗叫/大狗叫.png
Images/characters/meme/大狗叫/小狗.png
Images/characters/meme/大狗叫/小狗叫.png
Images/characters/meme/愤怒的普通人/01_普通人_微笑持刀.png
Images/characters/meme/愤怒的普通人/02_普通人_微笑刺出小刀.png
Images/characters/meme/愤怒的普通人/03_普通人_愤怒持刀.png
Images/characters/meme/愤怒的普通人/04_普通人_愤怒刺出小刀.png
Images/characters/meme/愤怒的普通人/08_小刀本体.png
Images/characters/meme/愤怒的普通人/愤怒的普通人.svg
Images/characters/meme/肌肉男/06_肌肉男_独立手臂.png
Images/characters/meme/肌肉男/07_肌肉男_独立身体.png
Images/characters/meme/肌肉男/肌肉男.svg
Images/characters/月计/殷红迷雾/刀光斩击遮罩.png
Images/characters/月计/殷红迷雾/刀光突刺遮罩.png
PROJECT_PATH_MAP_FOR_AI_V34.md
audio/characters/meme/大狗叫/大狗叫.MP3
audio/characters/meme/大狗叫/大狗大狗.MP3
audio/characters/meme/大狗叫/大狗大狗_速度01.wav
audio/characters/meme/大狗叫/大狗大狗_速度02.wav
audio/characters/meme/大狗叫/大狗大狗_速度03.wav
audio/characters/meme/大狗叫/大狗大狗_速度04.wav
audio/characters/meme/大狗叫/大狗大狗_速度05.wav
audio/characters/meme/大狗叫/大狗大狗_速度06.wav
audio/characters/meme/大狗叫/大狗大狗_速度07.wav
audio/characters/meme/大狗叫/大狗大狗_速度08.wav
audio/characters/meme/大狗叫/大狗大狗_速度09.wav
audio/characters/meme/大狗叫/大狗大狗_速度10.wav
audio/characters/meme/大狗叫/大狗大狗_速度11.wav
audio/characters/meme/大狗叫/大狗大狗_速度12.wav
audio/characters/meme/大狗叫/小狗叫.MP3
audio/characters/meme/大狗叫/小狗小狗.MP3
audio/characters/meme/大狗叫/小狗小狗_速度01.wav
audio/characters/meme/大狗叫/小狗小狗_速度02.wav
audio/characters/meme/大狗叫/小狗小狗_速度03.wav
audio/characters/meme/大狗叫/小狗小狗_速度04.wav
audio/characters/meme/大狗叫/小狗小狗_速度05.wav
audio/characters/meme/大狗叫/小狗小狗_速度06.wav
audio/characters/meme/大狗叫/小狗小狗_速度07.wav
audio/characters/meme/大狗叫/小狗小狗_速度08.wav
audio/characters/meme/大狗叫/小狗小狗_速度09.wav
audio/characters/meme/大狗叫/小狗小狗_速度10.wav
audio/characters/meme/大狗叫/小狗小狗_速度11.wav
audio/characters/meme/大狗叫/小狗小狗_速度12.wav
audio/characters/meme/愤怒的普通人/刺.mp3
audio/characters/meme/愤怒的普通人/小刀刺_[cut_1sec] (1).mp3
audio/characters/meme/愤怒的普通人/小刀刺_[cut_1sec] (2).mp3
audio/characters/meme/愤怒的普通人/小刀刺_[cut_1sec] (3).mp3
audio/characters/meme/愤怒的普通人/小刀刺_[cut_1sec] (4).mp3
audio/characters/meme/愤怒的普通人/小刀刺_[cut_1sec] (5).mp3
audio/characters/meme/愤怒的普通人/小刀刺_[cut_1sec].mp3
audio/characters/meme/愤怒的普通人/怪物叫.wav
audio/characters/meme/肌肉男/旋转.mp3
classes/ball.gd
classes/state_machine.gd
scenes/characters/meme/大狗叫.tscn
scenes/characters/meme/愤怒的普通人.tscn
scenes/characters/meme/肌肉男.tscn
scenes/characters/月计/伞夫.tscn
scenes/characters/月计/伞夫动画帧.tres
scenes/creatures/小狗叫.tscn
scripts/characters/meme/凑企鹅.gd
scripts/characters/meme/大狗叫.gd
scripts/characters/meme/愤怒的普通人.gd
scripts/characters/meme/狗叫机制.gd
scripts/characters/meme/肌肉男.gd
scripts/characters/月计/伞夫.gd
scripts/characters/月计/殷红迷雾.gd
scripts/creatures/小狗叫.gd
scripts/effects/殷红迷雾_刀光.gd
scripts/effects/狗叫声波.gd
scripts/ui/character_side_status_ui.gd
scripts/world.gd
shaders/殷红迷雾_血肉拖尾.gdshader
translations.csv
```
