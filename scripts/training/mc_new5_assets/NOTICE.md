# Minecraft 五角色资源说明

来源：Mojang/bedrock-samples，固定提交 736072450c26a7c67f07b1661f29d9a5ebaa14b1；每个原文件的 URL 与 SHA-256 见 sources.json。

Mojang AB 保留全部版权。原资源受 Minecraft EULA 约束，并非宽松开源资源；本转换不赋予额外分发权利。仓库许可：https://github.com/Mojang/bedrock-samples/blob/736072450c26a7c67f07b1661f29d9a5ebaa14b1/LICENSE.md

派生说明：使用 Bedrock 官方模型/贴图离线烘焙透明二维帧，不在运行时嵌入 3D。恶魂触须采用官方移动曲线；守卫者使用官方模型、setup 和尾部曲线并归一化旧模型坐标，并非全部原版眼球/刺动画的逐帧复刻。史莱姆内核及半透明外壳由原版模型烘焙，游戏跳跃与伸缩由机制驱动。活塞方块由原版贴图适配装配，不声称下载到了完整原版方块模型。末地烛使用原版 UV 片段装配，鱼钩从官方 fishhook 图集取面；钓竿、铁剑、火球为官方物品贴图。激光与钓线是程序化连接几何，不是随意绘制的角色替代素材。

get_assets.py 和 bake.py 保留获取与转换过程；bake.py 引用上一批 mc_native/bake_native_mobs.py 渲染器。
