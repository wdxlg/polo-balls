# 蜘蛛 / 溺尸：Minecraft 骨骼帧动画

> 这是初版动画改造记录。当前战斗机制已由 `MC16_REWORK.md` 中的连墙丝网 / 往返充电三叉戟替换；下文旧泼水、激流技能说明不再代表当前机制。当前新增独立手持层、渐显补发虚影、闪白弹性恢复，以及蜘蛛持续飞扑/命中/落地骨骼动作，见重做文档末节。

## 实现

沿用 `scripts/effects/我的世界/mc_native_animation.gd`，在原 Sprite2D 上播放完整 160×224 Texture2D 帧，不是整体图片摇摆，也不是两张立绘切换。保留着色器朝向、受击染色、残影、死亡快照及既有碰撞。菜单预览图仍为原静态缩略图。

- 蜘蛛：原版 `spider.default_leg_pose` / `spider.walk` 八足步态；吐网抬头/摆腿、扑击展腿使用同一原版模型的骨骼适配动作。
- 溺尸：原版 `humanoid.move` / `holding` / `bob`、`zombie.attack_bare_hand`、`drowned.attack.rotations`、`humanoid.brandish_spear`；持有原版三叉戟几何与贴图。
- 按实际位移选择行走，速度影响步频；停止后恢复待机。泼水、投掷和激流蓄力绑定现有技能入口。投掷优先于泼水，蓄力持续到技能状态结束，不受旧 0.4 秒换图逻辑影响。
- 游戏暂停、眩晕、死亡停止推进；复用已有权威端视觉状态同步，非权威端仍推进动画。
- 没有修改生命、伤害、冷却、弹道生成时序、技能判定、碰撞尺寸或场景注册。

## 来源与适配边界

固定 Mojang/bedrock-samples 提交 `736072450c26a7c67f07b1661f29d9a5ebaa14b1`。
原文件及逐文件 SHA-256 位于 `scripts/training/mc_native_assets/mc16_resource_pack` 和 `sources_mc16.json`。

骨骼、UV、贴图和基础动作曲线来自基岩版官方示例；这是离线正交烘焙到本项目 2D 战斗的适配，并非 Minecraft 引擎截图。蜘蛛吐网/扑击的额外姿态、三叉戟持物绑定及释放时刻、动作长度与游戏技能映射属于本项目适配。三叉戟伤害与弹道仍使用原有技能实现，不通过动画事件重新结算。

蜘蛛 TGA 红眼 alpha 是自发光标记，烘焙时不误当透明裁剪；溺尸保留外层皮肤透明区域。沿用固定相机和简化光照，不模拟原版自发光材质。

素材及衍生帧仍受 Minecraft EULA 和原权利人条款约束；参见同目录 LICENSE.md / README.md。公开可下载不代表独立游戏商业发行或再分发已获授权。

## 重建

Python 3.11 + Pillow + NumPy（只用于离线构建，运行游戏不需要）：

```powershell
$env:PYTHONPATH = (Resolve-Path .performance_tools/mc16_python).Path
py -3.11 scripts/training/mc_native_assets/bake_spider_drowned.py
# 仅第一次需要获取固定提交的源文件时加 --fetch
```

输出仅包括 `native_frames/spider_*`、`drowned_*`、两份 `.tres` 和 `manifest_mc16.json`；不会重建或覆盖其他角色帧及原 manifest。
修改相机/比例时，需要同步 `mc_native_animation.gd` 的 BOUNDS。所有帧烘焙时检查透明边缘，动作检查像素确实不同。蜘蛛按原图可见宽度拟合，溺尸按身体高度拟合，武器不参与身体缩放。

## 验证入口

- `tests/test_mc16_animation.gd`：实际场景动画、技能入口、状态恢复、暂停/眩晕/死亡、客户端呈现、朝向、固定碰撞和逐帧裁切检查。
- `tests/test_mc16_spider_drowned.gd`：原有蜘蛛/溺尸战斗机制回归。
- `tests/test_mc_native_animation.gd`：共享驱动及其他原版动画角色回归。

可使用已有 `tests/run_mc_frontier_checks.py --godot <Godot路径> --test test_mc16_animation --test test_mc16_spider_drowned --test test_mc_native_animation`。

本次 Godot 4.7.2 验证：3/3 脚本通过；新增动画 405 项检查、原战斗 39 项检查、共享动画 603 帧 / 1892 项检查，均为 0 失败。导入成功，修改脚本未报告编辑器错误。现有退出 ObjectDB 泄漏警告及着色器文件名大小写警告仍存在，不属于本次动画修改。

短动画测试结束前通过 `tests/mc_animation_test_cleanup.gd` 等待 World 已发起的后台资源加载结束，防止退出时中断其他角色资源解析；不屏蔽真实解析错误，也不改生产环境的预热逻辑。


## 后续手持层与扑击动作

当前运行时溺尸身体使用 `native_frames/hand_pounce/drowned_hand_layers.gd` 中的无武器帧，手中武器由 `trident_hand_visual.gd` 独立绘制；不再依赖旧整张角色帧里那把武器。新生成器 `bake_hand_pounce.py` 保留旧文件，另生成独立身体/物品层、手部握点与路径及 `spider_pounce.tres`。蜘蛛增加持续空中动画、攻击和落地，均沿用原版模型骨骼与贴图作游戏适配，不是整个 Sprite2D 的摇摆或缩放。补发与音效、动作参数和最新测试结果以 `MC16_REWORK.md` 为准。
