# Minecraft 硫方怪 / Sulfur Cube（Java 26.2）

## 角色与操作

在「我的世界」分类选择 **硫方怪**。战斗中的人物现在是实时 SubViewport 三维模型：外层 18×18 原版 UV 六面壳、内层 16×16 原版 UV 六面胶体、中央独立的六面原版方块，使用真实前后遮挡与深度、整体弹跳变形和独立换块缩放。没有把木/冰/岩浆等七张合成正面贴图轮流贴到人物上。启动/切换方块时只替换立体内芯；原版岩浆三帧仍可流动，TNT 倒计时按既有规则闪烁。选角尚未加载战斗场景时使用原版 UV 合成的菜单缩略图；无头模式的受击粒子/阴影从同源缩略图采样，战斗画面仍使用实时模型。音效仍全是项目现有、校验过的 Minecraft 原声。首次开战约 0.65 秒装入木块。此后 AI 按现有 `Skill_Cooling=5.6` 秒循环；玩家控制时使用正常技能键切换。`Attack_Cooling=1.55` 秒时的普攻是短暂加速。初始生命 320、攻击 24、移动速度 112。

| 体内方块 | 本游戏玩法改编（不是原版的逐项数值） |
|---|---|
| 橡木原木 | 按真实身体碰撞半径接触：基础 28 伤害、弹跳击退；移动略快。 |
| 蓝冰 | 基础 20 接触伤害、短击退；速度叠加滑行惯性。 |
| 岩浆块 | **世界坐标半径 26** 的近身灼伤，基础 12 伤害，每目标间隔 0.82 秒。 |
| 蜜脾块 | 基础 8 接触伤害，并让目标速度 ×0.55 持续 1.1 秒；自身较慢。 |
| 铁块 | 基础 10 接触伤害，自身承受普通伤害 ×0.53。 |
| TNT | 锁定方块、点燃音效及红色预警圈 **2.4 秒**；世界坐标半径 72、基础 90 伤害并击退。结算一次后自动换回木块，角色继续战斗。 |

木、蓝冰、蜜脾、铁块接触判定使用当前 `CollisionShape2D` 的**世界半径**，不把场景的 43 本地单位误作世界单位；岩浆与 TNT 范围、实际伤害、设置中的威胁显示、TNT 红圈统一使用世界坐标。角色通用身体 hitbox 已关闭，伤害按对方阵营和每目标冷却分别结算，避免重复伤害。暂停冻结引信；昏眩后已点燃的 TNT 仍会爆炸，相应威胁不会被错误隐藏。多人由权威端改变方块与结算伤害，客户端接收贴图/引信复制以及单次声画 RPC。

> 原版依据：[Minecraft Java Edition 26.2 官方更新说明](https://www.minecraft.net/en-us/article/minecraft-java-edition-26-2)：硫方怪吸收方块，方块使它成为可推动物体，并对应 Bouncy（木）、Fast Sliding（冰）、Hot（岩浆）、Sticky（蜜脾）、Slow Flat（金属）、Explosive（TNT）。本游戏的自动技能循环、具体伤害/减速/减伤、TNT 爆炸后继续战斗，**是项目玩法改编**，不是声称 Minecraft 原版如此。

## 官方资源与复现

- 仅取 Mojang **Java 26.2** 客户端/资源索引：客户端 SHA-1 `2dc72797acbc1b63fc16a11c4ac393605f453754`，索引 SHA-1 `52695890153d94cf946455da532806db8c530831`，原版 `sounds.json` SHA-1 `9ac006d5537ed0fa4a7bcd1eccfc505155847686`。
- `Images/characters/我的世界/sulfur_cube/sources.json` 逐文件记载 **20 原始贴图 + 25 原始 OGG** 的源路径、官方哈希；这次直接从同一份 SHA-1 校验过的 Java 26.2 客户端取得橡木顶部、TNT 顶部/底部纹理，使立体方块的各面也用原版正确贴图。旧的 7 张角色合成图只供菜单缩略图和 CPU 粒子采样，战斗三维壳体/胶体/六面方块直接采样 `source/` 中原始 PNG。另存 8 张原版爆炸粒子帧；`.import`/`.gd.uid` 是 Godot 导入标记而非外来素材。有效伤害仍用 Java 26.2 原版玩家受伤/暴击声音（各 3 款），阈值严格 `>50`；不添加模型音效或非 Minecraft 像素素材。
- 下载与重新生成：`python scripts/training/mc_native_assets/fetch_sulfur_cube.py`（会访问 Mojang 清单和资源服务，需要 Pillow；完整客户端缓存只存在临时目录，不提交）。完全离线校验现有文件：`python tests/verify_mc_sulfur_cube_assets.py`，应显示 `45 original Minecraft files; 7 derived sprites`。战斗模型代码为 `scripts/characters/我的世界/sulfur_cube_model.gd`，仅通过 `shaders/sulfur_cube_shell.gdshader` 调整原版浅色壳体的透明度，不生成额外图像素材；实际模型受物理状态同步控制。

## 验证 / 范围

在项目根目录，使用项目配套 Godot 4.7.2 离线引擎：

```powershell
$godot = 'E:/godot/polo-balls-tools/offline-engine/runtime/Godot.4.7.2.offline.exe'
& $godot --editor --headless --path . --import
& $godot --headless --path . --script res://tests/test_mc_sulfur_cube.gd
& $godot --headless --path . --script res://tests/test_mc_sulfur_cube_network.gd
& $godot --path . --script res://tests/test_mc_sulfur_cube.gd  # 真 GPU；另查 TNT 圈的实际像素
python tests/verify_mc_sulfur_cube_assets.py
```

本次三维升级实测：主场景 headless **43/43**；相同测试真实 GPU **46/46**（从空壳开始的可见 GPU 像素、换块长入动画、外壳/胶体/真实六面内芯与橡木/TNT 顶底贴图、全模式战斗效果以及 72 世界单位 TNT 圈）。本机独立两个 `SceneMultiplayer` + ENet + 真正 `MultiplayerSpawner` / `MultiplayerSynchronizer` **18/18**，覆盖客机各自渲染立体内芯而不能改方块或引爆、宿主仅结算一次、客户端收到原版引信/爆炸音效、声画与复位；官方素材离线校验 **45+7**。历史基础行为与当前体内方块效果不变。**回环两 peer 不等同于两台电脑/两个独立客户端的实战验收**；当前单角色 160×160 实时视口未专门作大量同屏实例的录制性能压测。

Godot 运行仍报告原有 `scenes/ball.tscn` 引用 `set_rgb_color.gdshader` 时的 UID/文件名大小写警告；本次场景/脚本运行和独立网络测试无新增 `ERROR`。新增三张官方纹理后须先运行上述 `--editor --headless --import`，再执行 `--script` 测试；没有擅自改动共享基础场景。

## 版本隔离

硫方怪原始场景、脚本、资源、生成器与测试是另一项工作尚未提交的未跟踪文件；本轮只改硫方怪相关内容，并新增独立实时三维模型/着色器与三张官方方块顶底面纹理。若基线尚未入库，不擅自整批暂存原工作；独立 Git 提交将只包含本轮可分离的新文件，旧资源/脚本的对接改动保留在当前工作区，并在交付时说明版本无法从干净检出单独重现。`scripts/world.gd`、翻译文件及 `MCP_CONTEXT.md` 存在并行修改，本轮不覆盖或暂存。勿对含并行修改的工作区 `reset --hard` / `clean -fd`。
