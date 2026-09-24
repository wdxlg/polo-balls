# 我的世界药水／附魔信息框测试盔甲架

## 入口与边界

- 默认分类直接可选 `药水测试盔甲架`、`附魔测试盔甲架`；两者继承原来的移动盔甲架，仍是速度 100、无主动攻击／身体伤害的测试目标。仅显示模拟的药水/附魔**文字与图标**，不向角色施加实际增益、伤害或命中音效，也不创建新的伤害威胁。
- 药水框逐条显示原版图标、名称/可选等级和逐秒倒计时。附魔框首行黄色物品名、以下每行附魔名+罗马等级；空等级或自定义等级文案也可设。随机从场景的候选资源中无放回选 **2–4** 条（可编辑范围），每次重新出生再抽；设置 `randomize_on_spawn=false` 可显示候选池全部内容。
- **中英双语**：默认两架盔甲架名称已进入角色选择器翻译表，8 条药水、8 条附魔以及黄色物品标题均有独立英文文案；例如药水「力量」显示 `Strength`，弓附魔「力量」显示 `Power`。切换 Game 语言时现有信息框即时重排，倒计时不重置；「仅局内翻译」开启时框内仍按战斗语言显示英文，不受外层界面中文设置影响。时间数字与罗马等级不变。
- 共用 `scripts/ui/mc_effect_tooltip.gd`：九宫格保持原版边角、扩展中心区域，不直接将整张像素贴图拉糊。药水背景**每条独立**贴合名称和时间两行中较宽的一行，文字后仅留约 6 个逻辑像素（默认 3 倍缩放为 18 屏幕像素）；原版 120×32 PNG 是素材尺寸，**不是最小显示宽度**。时间字数变化时行宽和整体定位随之刷新。附魔框仍按最长内容和总行数扩展；超出视口时整体等比缩小。信息框在盔甲架**右侧**跟随身体，以脱离父节点裁剪的 `top_level` 世界画布节点保持屏幕定位；不再用盖住全部战场的高层 `CanvasLayer`。越过地图外沿仍可见，非常靠近视口右侧时优先将完整框收进屏幕，可能与角色位置重叠。角色隐藏、死亡、完全离屏或删除后不留旧框。
- 真实角色**持续药水状态**单独显示并复用上述原版框；演示内容不代表实战生效。信标、女巫、凋零、潜影贝及双语录像的实装、额外角色审查和实时 GPU 回归见 `tests/MC_ACTIVE_POTIONS.md`。

## 自定义方式

1. 打开 `scenes/characters/默认/药水测试盔甲架.tscn`：`potion_pool` 的每个 `MCPreviewPotionEffect` 子资源可改中文 `effect_name` 和对应英文 `english_name`、任意 `Texture2D` 图标、等级、等级文案覆盖、持续秒数/时间文案覆盖、文字颜色。出生随机范围、像素倍数、右侧间隔、屏幕安全边距和字体/字号均在盔甲架根节点 Inspector 调整；可选提供新背景贴图及对应九宫格边距。
2. 打开 `scenes/characters/默认/附魔测试盔甲架.tscn`：根节点 `tooltip_title`/`tooltip_title_en`/`tooltip_title_color` 配双语首行；`enchantment_pool` 每个 `MCPreviewEnchantment` 可改中文 `enchantment_name` 和英文 `english_name`、等级/文案覆盖、文字颜色。背景和描边贴图/九宫格边距也可替换。英文名留空时尝试 `Game.t(中文名)` 的翻译表；无翻译则保留原文，不猜测自定义名称。
3. 运行时可以调用盔甲架的 `set_displayed_potions(Array[MCPreviewPotionEffect])` 或 `set_displayed_enchantments(item_name, Array[MCPreviewEnchantment], english_item_name="")`，立即重排整个原版边框。第三个可选参数给运行时自定义黄色标题配英文；原来的双参数调用保持可用。原版 PNG 无需重绘，动态换行、较长名称和多行高度都有检查。

## 资源来源

- `Images/UI/minecraft_tooltips/` 内的 **42 张 PNG** 均逐字节提取自 Mojang 官方 Minecraft Java 1.21.4 客户端 JAR（SHA-1 `a7e5a6024bfd3cd614625aa05629adf760020304`），包括 `effect_background_large.png`（120×32）、39 张 `mob_effect/*.png`（18×18）、`tooltip_background.png` 和 `tooltip_frame.png`（100×100，官方 `.mcmeta` 九宫格边距分别 9 与 10）。逐文件 SHA-256 和来源见同目录 `SOURCE.json`；提取命令 `python tools/extract_mc_tooltip_assets.py`，不加 `--force` 不覆盖自定义过的贴图。版权归 Mojang/Microsoft，项目不声明新许可。
- 已复用项目现有中文点阵字体与 Mojangles 数字字体。项目启用 `hdr_2d`；直接将 GPU 线性读回存 PNG 会显得过暗，人工预览时需按 sRGB 显示或做线性→sRGB 查看，**不应**为了修截图而擅自调亮游戏内原版纹理。

## 验证方式与本次结果

在工程根目录用具有 `--script` 的 Godot 4.7.2 编辑器构建运行（项目根的 `godot.exe` 是无该参数的运行模板，不用于脚本测试）：

```powershell
& ..\polo-balls-tools\offline-engine\runtime\Godot.4.7.2.offline.exe --headless --path . --editor --recovery-mode --import
& ..\polo-balls-tools\offline-engine\runtime\Godot.4.7.2.offline.exe --headless --path . --script res://tests/test_mc_effect_tooltips.gd
& ..\polo-balls-tools\offline-engine\runtime\Godot.4.7.2.offline.exe --headless --path . --script res://tests/test_mc_effect_tooltips_locale.gd
& ..\polo-balls-tools\offline-engine\runtime\Godot.4.7.2.offline.exe --path . --script res://tests/preview_mc_effect_tooltips.gd
& ..\polo-balls-tools\offline-engine\runtime\Godot.4.7.2.offline.exe --path . --script res://tests/preview_mc_effect_tooltips.gd -- --english
```

- 静态/运行时夹具：此次运行 **46 项检查、0 失败**（检查数随药水随机条目个数略有变化）；两场景加载并出现在默认分类索引，移动速度和无攻击属性、无重复随机、倒计时/暂停、字体及标题顺序、长文本九宫格自适应、异常长列表视口缩放、跟随/临屏回收/隐藏均已验证。新增以「生命恢复」短标题、不同宽度的第二行和长时间文案检验每行独立伸缩、右边距，以及 `1:00:00` 倒数成 `59:59` 后的收缩。
- 语言回归：**40 项检查、0 失败**；逐项检验 8 种药水、8 种附魔的英文与资源原名对应、角色选择名称与黄色标题、导出安全翻译表、每行英文宽度/背景边角、实时中英切换后倒计时不重置、「仅局内翻译」、运行时自定义中英文文案及原双参数接口。
- **真实 D3D12/Forward+ GPU**：生成用户目录 `user://mc_effect_tooltips/preview.png` 的 1000×700 画面；两个盔甲架贴近一个实际启用了 `clip_contents=true` 的测试地图边缘。关闭信息框前后逐像素对比，地图外有 **7230 个像素**明确来自原版信息框，两个框均保持在角色右侧且越过地图边界。「生命恢复」行九宫格宽 **73 逻辑像素**（默认 3 倍即 219 屏幕像素），名字右侧留 **6 逻辑像素**；GPU 对比确认背景右侧取样处已恢复为背景色、没有继续绘制原来 120px 的宽度。人工查看线性→sRGB 校正后的截图，药水/附魔背景、图标、标题/行色与参考形式吻合。
- 英文 GPU 预览保存为 `user://mc_effect_tooltips/preview_en.png`：地图外实际变化 **7440 像素**；`Regeneration` 一行宽 **101 逻辑像素**（303 屏幕像素），右留 **6 逻辑像素**，`Enchanted Book` 附魔框宽 330 屏幕像素；两框均在角色右侧、地图边界外可见，实际帧后侧背景取样处无绘制。
- 本节原有截图夹具不等于全地图逐一回归；后续**真实双语视频**验证已追加在 `tests/MC_ACTIVE_POTIONS.md`，但仍未做双客户端联机状态节点同步。场景/渲染器现存的资源 UID 警告需以当前运行日志核对，不能擅自归因于本信息框。

## 2026-09-25 药水框／附魔框在战场对象之后

- 用户要求人物、投射物、障碍物等绘制在药水框与附魔框**之上**。演示框和真实持续状态框同用 `MCPreviewTooltip`：改为默认世界画布内的 `top_level` 节点、**绝对 Z=-3**；当前 World 地面/背景约为 -4/-5，常规角色、弹体和障碍物为 -2 或以上。每帧抵消各自视口相机矩阵，保留原屏幕右侧跟随、缩放、离屏隐藏、两框避让和像素画法；地图父节点的裁剪不影响框。更高层的模态 HUD 不属于本次战场前景层级。
- 地图外的 `MapClipBackBuffer` 改在信息框之后、普通战斗对象之前取样（World 子节点 Z=0，最终世界 Z=-2），外沿遮罩仍擦除越界单位/投射物，但不再擦除越界的信息框。真实 World GPU 测试 `test_mc_tooltip_world_edge.gd`：**4/4**，地图外信息框对比可见 **720** 个取样像素、同一区域的地图外前景仍被裁掉；`test_mc_tooltip_world_depth.gd`：**10/10**，实际盔甲架与角色/弹体/障碍物类节点颜色覆盖药水和附魔框，地图地面仍在框下，缩放相机仍跟随。遮挡截图分别保存在 `user://mc_tooltip_world_depth/world_edge_frame.png` 和 `foreground_above_frames.png`，非提交资源。
- 录像源视口与主世界共享 World2D，因此主画面原框仅用主画面可见位 19；录制的中/英文副本分别用可见位 17/18，相同 Z=-3 而不串画。离线录制版引擎 D3D12 下，`test_recording_mc_effect_tooltips.gd` 的实时和模拟录制合计 **45/45**，四份真实视频及两语三类框均通过逐像素检查；普通 Godot 原版引擎只支持实时录制，不可拿它宣称模拟模式通过。
- 相关 headless 回归：`test_mc_effect_tooltips.gd` **48/48**（随机条目数可改变检查数）、`test_mc_effect_tooltip_mirror.gd` **20/20**、`test_mc_effect_tooltips_locale.gd` **40/40**、`test_mc_active_potion_tooltips.gd` **47/47**、`test_mc_unified_status_effects.gd` **125/125**。D3D12 的中/英文原图 GPU 预览仍分别有 **7230 / 7440** 个地图外信息框像素，凋零真实 World 视觉回归 `test_wither_beacon_revision.gd` **47/47**。未做双客户端联机或所有地图主题的穷举检验；早期记录中的 CanvasLayer 层级与各期测试项数不等同于此次版本。
