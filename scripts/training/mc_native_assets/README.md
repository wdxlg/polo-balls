# Minecraft 原版模型动作 → 本项目 2D 帧动画

## 来源与许可

资源来源是 Mojang 官方 `Mojang/bedrock-samples`，固定提交：
`736072450c26a7c67f07b1661f29d9a5ebaa14b1`。

https://github.com/Mojang/bedrock-samples/tree/736072450c26a7c67f07b1661f29d9a5ebaa14b1

这是 **Bedrock / 基岩版** 的模型、皮肤和骨骼动作数据，不是 Java 版动画导出，也不是 Fresh Animations 等第三方动作包。官方原始文件缓存、逐文件 SHA-256 和 LICENSE.md 随烘焙工具保留。

官方 LICENSE.md 声明 `(c) Mojang AB. All rights reserved.`，这些文件受 Minecraft EULA 约束：
https://www.minecraft.net/en-us/eula

**公开下载不等于开源、可任意商用或可在独立游戏中自由再分发。此处未取得另外的商用/发行授权；对外发布、商业使用或再分发前，必须核实适用条款并取得所需许可。不应将这次资源获取描述为已经完成法律授权审查。** Minecraft 素材及衍生渲染帧仍保留原权利归属，本文件不授予额外权利。

## 实际使用的动作

- 末影人：humanoid.move / bob / attack.rotations，enderman.arms_legs 的限幅，scary_face 的头/下颚相对移动；普通和怒态分别采样待机、行走与接触攻击。
- 唤魔者：evoker.general / move / casting；humanoid.celebrating。交叉双臂与施法时独立双臂按控制器切换。
- 恼鬼：当前 vex.v1.8 几何和匹配皮肤，vex.idle 的双臂关键帧及扇翅公式，vex.charge；依据官方控制器顺序先 charge 再 idle。携带的铁剑使用原版 iron_sword.png。
- 潜影贝：shulker.facing / move；实体定义中的 PeekAmount → LidPositionFactor / LidRotationFactor 公式。盖子既升降又旋转，并非两张开/关图互换。

## 转换边界（不能宣称是 Minecraft 引擎原样运行）

- 离线软件渲染，固定三分之四正交镜头、Y-up 旋转坐标转换、简化固定光照和像素采样；没有嵌入 Minecraft 渲染器。材质、光照、持物投影和最终像素不是游戏引擎截图。
- Enderman 旧 humanoid 几何的头部 bind Y=24 与长肢模型肩 Y=38 不一致，导入时将头部基准平移 14 个模型单位，下颚保留其已写入的绑定坐标。动作采样时不重复叠加引擎专用的 humanoid base_pose。动画曲线本身取自官方数据。
- Enderman TGA 的 alpha 存的是自发光信息，不按透明裁剪读取，避免眼睛消失。这里使用简化光照，不模拟原引擎发光材质。
- 铁剑通过官方 rightItem 骨骼挂接原始图标，持物平面和尺寸属于烘焙适配；没有冒称来自官方独立剑网格。
- 循环采样长度、投影比例、状态映射及开壳/关壳 0.5 秒过渡适配现有 2D 战斗。不会修改原有伤害、碰撞、射击延迟、召唤时序和重力。
- 保留原有 Sprite2D，逐帧换完整 Texture2D，而非 AtlasTexture 共享 UV，兼容既有朝向着色器、染色、残影和死亡快照。禁止用整体平移/摆动代替骨骼动作。角色的果冻形变在动画播放时关掉，保留方块形状。
- 所有帧具有固定画布/脚底基准；潜影贝换重力仍由 Graphics 统一旋转，不重新缩放和重新锚定。暂停/死亡停止推进。视觉状态按权威端周期同步，客户端不调用仅权威可执行的 mc_live() 门禁。

## 重建

在此目录建立 Python 虚拟环境，安装 `pillow` 和 `numpy`（仅离线工具依赖），运行：

```text
python bake_native_mobs.py --output <项目目录>/Images/characters/我的世界/native_frames
```

脚本只读取已固定提交的本地 `resource_pack` 缓存，不自动追踪 main。输出 PNG、四个 SpriteFrames .tres 和 manifest.json。运行游戏/导出游戏不需要 Python、NumPy、Pillow 或运行时 3D。

`mc_native_animation.gd` 内的 BOUNDS 来自 manifest.json 的 neutral_bounds；变更摄像机/画布后须同步更新并运行 `test_mc_native_animation.gd`。画布固定 160 × 224；如改画布也须同步驱动中的半高。菜单的原静态预览图暂时保留，不改角色索引和已有翻译。
