# 我的世界药水／附魔信息框测试盔甲架

## 入口与边界

- 默认分类直接可选 `药水测试盔甲架`、`附魔测试盔甲架`；两者继承原来的移动盔甲架，仍是速度 100、无主动攻击／身体伤害的测试目标。仅显示模拟的药水/附魔**文字与图标**，不向角色施加实际增益、伤害或命中音效，也不创建新的伤害威胁。
- 药水框逐条显示原版图标、名称/可选等级和逐秒倒计时。附魔框首行黄色物品名、以下每行附魔名+罗马等级；空等级或自定义等级文案也可设。随机从场景的候选资源中无放回选 **2–4** 条（可编辑范围），每次重新出生再抽；设置 `randomize_on_spawn=false` 可显示候选池全部内容。
- 共用 `scripts/ui/mc_effect_tooltip.gd`：九宫格保持原版边角、扩展中心区域，不直接将整张像素贴图拉糊；宽高按最长内容和总行数计算，超过视口时整体等比缩小。信息框在盔甲架**右侧**跟随身体，放在独立屏幕空间 `CanvasLayer`，越过地图外沿/裁剪层仍可见；非常靠近视口右侧时优先将完整框收进屏幕，可能与角色位置重叠。角色隐藏、死亡、完全离屏或删除后不留旧框。

## 自定义方式

1. 打开 `scenes/characters/默认/药水测试盔甲架.tscn`：`potion_pool` 的每个 `MCPreviewPotionEffect` 子资源可改名称、任意 `Texture2D` 图标、等级、等级文案覆盖、持续秒数/时间文案覆盖、文字颜色。出生随机范围、像素倍数、右侧间隔、屏幕安全边距和字体/字号均在盔甲架根节点 Inspector 调整；可选提供新背景贴图及对应九宫格边距。
2. 打开 `scenes/characters/默认/附魔测试盔甲架.tscn`：根节点 `tooltip_title`/`tooltip_title_color` 配首行；`enchantment_pool` 每个 `MCPreviewEnchantment` 可改附魔名称、等级/文案覆盖、文字颜色。背景和描边贴图/九宫格边距也可替换。
3. 运行时可以调用盔甲架的 `set_displayed_potions(Array[MCPreviewPotionEffect])` 或 `set_displayed_enchantments(item_name, Array[MCPreviewEnchantment])`，立即重排整个原版边框。原版 PNG 无需重绘，动态换行、较长名称和多行高度都有检查。

## 资源来源

- `Images/UI/minecraft_tooltips/` 内的 **42 张 PNG** 均逐字节提取自 Mojang 官方 Minecraft Java 1.21.4 客户端 JAR（SHA-1 `a7e5a6024bfd3cd614625aa05629adf760020304`），包括 `effect_background_large.png`（120×32）、39 张 `mob_effect/*.png`（18×18）、`tooltip_background.png` 和 `tooltip_frame.png`（100×100，官方 `.mcmeta` 九宫格边距分别 9 与 10）。逐文件 SHA-256 和来源见同目录 `SOURCE.json`；提取命令 `python tools/extract_mc_tooltip_assets.py`，不加 `--force` 不覆盖自定义过的贴图。版权归 Mojang/Microsoft，项目不声明新许可。
- 已复用项目现有中文点阵字体与 Mojangles 数字字体。项目启用 `hdr_2d`；直接将 GPU 线性读回存 PNG 会显得过暗，人工预览时需按 sRGB 显示或做线性→sRGB 查看，**不应**为了修截图而擅自调亮游戏内原版纹理。

## 验证方式与本次结果

在工程根目录用具有 `--script` 的 Godot 4.7.2 编辑器构建运行（项目根的 `godot.exe` 是无该参数的运行模板，不用于脚本测试）：

```powershell
& ..\polo-balls-tools\offline-engine\runtime\Godot.4.7.2.offline.exe --headless --path . --editor --recovery-mode --import
& ..\polo-balls-tools\offline-engine\runtime\Godot.4.7.2.offline.exe --headless --path . --script res://tests/test_mc_effect_tooltips.gd
& ..\polo-balls-tools\offline-engine\runtime\Godot.4.7.2.offline.exe --path . --script res://tests/preview_mc_effect_tooltips.gd
```

- 静态/运行时夹具：**39 项检查、0 失败**（检查数随药水随机条目个数略有变化）；两场景加载并出现在默认分类索引，移动速度和无攻击属性、无重复随机、倒计时/暂停、字体及标题顺序、长文本九宫格自适应、异常长列表视口缩放、跟随/临屏回收/隐藏均已验证。
- **真实 D3D12/Forward+ GPU**：生成用户目录 `user://mc_effect_tooltips/preview.png` 的 1000×700 画面；两个盔甲架贴近一个实际启用了 `clip_contents=true` 的测试地图边缘。关闭信息框前后逐像素对比，地图外有 **7230 个像素**明确来自原版信息框，两个框均保持在角色右侧且越过地图边界。人工查看线性→sRGB 校正后的截图，药水/附魔背景、图标、标题/行色与参考形式吻合。
- 现存基线警告：`scenes/ball.tscn` 的 `set_rgb_color.gdshader` UID 无效、文件路径大小写不一致；与本改动无关。未做真实双客户端同步、录制画面或全地图逐一回归，不能将上述夹具/局部 GPU 结果冒充这些验证。
