# 第二批 Minecraft 模型帧动画

延续第一批的来源与许可：Mojang/bedrock-samples，固定提交
736072450c26a7c67f07b1661f29d9a5ebaa14b1。
官方原始文件受 Minecraft EULA 约束，不是可自由商用的开源资产；未另取得独立游戏发行/商用许可。请同时阅读 README.md、LICENSE.md。逐文件校验见 sources_batch2.json。

## 原始动作与适配边界

- 女巫：继承官方 villager 几何，合并女巫帽子与鼻子上的疣；villager.general/move + witch.general。原版保持交叉双臂，持药时主要改变鼻子姿态，并没有第三方夸张挥手动作。继续使用本项目原有药瓶、三次饮用点动、抛物线投掷和效果时序；饮用嘴部锚点适配新模型。
- 烈焰人：官方 blaze.move 的十二根棒分三层绕行及高度变化；采用 10 秒 / 240 帧周期让三层水平轨道同时闭环，避免短周期循环时突然跳位；保留 AnimatedSprite2D、Graphics 朝向链、烟雾、连射及额外两根技能碰撞棒。原版没有独立攻击骨骼轨道，射击中仍保持这套环绕动作；没有将自创攻击动作冒称官方。
- 苦力怕：官方腿部摆动及 swelling 公式，蓄力进度直接映射现有引信累计值；取消/回退时不会重新从头播放。移除旧版重复整体放大，避免与模型膨胀叠加。闪白、引雷、取消引信、爆炸伤害及半径照旧。充能外壳使用官方 creeper_armor 皮肤和充能几何的膨胀量，UV 滚动及 alpha 合成是本烘焙器的简化适配，不是原引擎材质实现。
- 蠹虫：silverfish.move 七节身体按不同相位摆动，背部层跟随对应骨骼；不是整张图片旋转。官方控制器持续运行，因此待机也有分节摆动。保留孵化、石砖和阵营继承机制。
- 骷髅：humanoid.move/holding/bob/bow_and_arrow，弓的图标来自官方；弓放大到每 16 纹素对应 17 个模型单位，贴图转正；以握把像素而非整张图的中心锚定右手末端，并随 rightArm 骨骼运动。持物尺寸和平面朝向属于 2D 可读性适配。待机和行走时右臂自然下垂，弓在握把处放低并向下倾转；仅射击帧抬弓瞄准，射击结束回到放下的姿态。射击姿态在既有立即出箭入口触发，不增加新的蓄力等待、不改变箭速或攻速成长；没有把近战 skeleton.attack 冒用为弓箭动画。
- 唤魔尖牙：evocation_fang.bite、实体中 bite_amount/y_offset/shrink 公式和 bind_pose_rotation；地下部分按模型空间地面裁剪。现有伤害仍在 `_delay` 时刻结算，前至多 0.14 秒映射张口阶段，之后 0.34 秒映射闭合后收回阶段，闭口时刻正好是原伤害点。末帧透明是原缩回公式的结果，不是缺帧。

## 重建与验证

在已安装 Pillow/NumPy 的离线环境中，同目录保留 bake_native_mobs.py 与 resource_pack，运行 `python bake_native_batch2.py`，输出到 frames_batch2。

将输出的 PNG、SpriteFrames 和 manifest_batch2.json 放入 `Images/characters/我的世界/native_frames/`。驱动中的 BOUNDS、WITCH_MOUTH，以及尖牙的 DRAW_SCALE 与 GROUND_Y，来自该 manifest 和固定相机参数；改相机后必须一起更新。

运行游戏不需要 Python 或运行时 3D。新驱动与第一批驱动独立，不改变已完成的末影人、唤魔者、恼鬼、潜影贝动作资源。

低持弓绕握把翻正前后（-135°）；射击帧逐字节保持不变。资源在 World 中线程加载并保留缓存，离屏分帧预热，不预实例化战斗角色。

首次放置性能：World 线程加载八种可放置角色并持有场景缓存；只使用无脚本绘图节点分帧准备，不执行战斗角色初始化或消耗战斗随机数。提前点击按原顺序等待，重置取消等待请求。Minecraft 角色血量数字沿用原 900 字号、描边、布局，改用共享 MSDF 字体，避免每个数字首次出现时栅格化巨大描边位图。
