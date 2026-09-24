# 硫方怪立体外壳与真实换块（增量说明）

本轮用户确认：使用 **实时三维模型**，保留原六种方块和既有战斗效果；继续仅处理硫方怪，不覆盖其他并行工作。

`scripts/characters/我的世界/sulfur_cube_model.gd` 将 Mojang Java 26.2 原版 18×18 外壳、16×16 内层 UV 分别贴在六个三维面上；中央是单独的六面方块，切换时缩放长入，岩浆块沿原版三帧流动。真实战斗使用 160×160 SubViewportTexture，不再按模式替换整张角色平面图。只有离树的菜单缩略图与无头 CPU 粒子/影子采样仍使用官方 UV 合成的备用图。

**用户提出“不像游戏内”后的视觉纠正：**对照 Java 26.2 客户端的 `SulfurCubeModel.createOuterBodyLayer`、`createInnerBodyLayer`、`SulfurCubeInnerLayer.submit` 及 Minecraft 官方实机截图（[Snapshot 6](https://www.minecraft.net/en-us/article/minecraft-26-2-snapshot-6)），确认原版外壳是 18³、空壳内层是 16³；**填入方块时不再绘制内层胶体，而是显示完整 16³ 方块**。旧实现在填块后仍画不透明内层并将方块缩小到约 12px，导致内部模糊；壳体着色器还篡改了原版的透明像素，脸上眼睛被错误覆盖。现已改为：外壳/方块严格 18:16 比例，空壳内层先绘制、外壳后绘制；填块时隐藏内层，`shaders/sulfur_cube_shell.gdshader` 直接保留官方贴图的 RGBA（包括瞳孔与透明孔）；不再让外壳与方块彼此反向旋转，按原版的纵向拉伸/横向倒数收缩一起变形。游戏战斗保留自身正面观察与技能机制，不能声称与原版不同场景的环境光照或物理判定逐像素相同。

木块弹跳、冰块滑行、岩浆灼伤、蜜脾减速、铁块减伤、TNT 倒计时爆炸及权威端联机伤害保留原数值。音效沿用现有、已经校验为 Minecraft 原声的硫方怪素材；没有新造音效/贴图。新增三张源 PNG（橡木顶面、TNT 顶/底面）直接从官方 Java 26.2 客户端 SHA-1 `2dc72797acbc1b63fc16a11c4ac393605f453754` 取得，其各自 SHA-1 及 jar 路径记在 `Images/characters/我的世界/sulfur_cube/sources.json`。

验证：先执行 Godot `--editor --headless --path . --import` 导入新 PNG，再运行 `tests/test_mc_sulfur_cube.gd`：**43/0** headless、**47/0** 真 GPU（实际帧像素包括空壳原版双眼、六种方块、TNT 警戒圈；六模式断言胶体不遮挡和方块/内层同比例）；`tests/test_mc_sulfur_cube_network.gd` 独立回环 ENet 双 peer **18/0**；`tests/verify_mc_sulfur_cube_assets.py` **45 原版文件 + 7 衍生备用图**通过。未进行两台电脑联机或多角色同屏 3D 视口压力测试。

**版本边界：**本轮开始时原有硫方怪场景/脚本/测试/资源整套仍是其他任务的未跟踪文件。因此只提交本轮可独立分离的三维模型、着色器和三张原版源纹理及本说明；现有未跟踪文件内已验证的接入、manifest、生成器与测试修改保留在共享工作区，待原任务将基线纳入 Git 后才能得到可由干净仓库独立重现的完整版本。不得为了制造干净状态而覆盖/整库暂存其他任务文件。
