# 硫方怪立体外壳与真实换块（增量说明）

本轮用户确认：使用 **实时三维模型**，保留原六种方块和既有战斗效果；继续仅处理硫方怪，不覆盖其他并行工作。

`scripts/characters/我的世界/sulfur_cube_model.gd` 将 Mojang Java 26.2 原版 18×18 外壳、16×16 内层 UV 分别贴在六个三维面上；中央是单独的六面方块，切换时缩放长入，岩浆块沿原版三帧流动。`shaders/sulfur_cube_shell.gdshader` 让壳体淡色区域半透明而原版深色表情保留，使内芯在外壳内可见。真实战斗使用 160×160 SubViewportTexture，不再按模式替换整张角色平面图。只有离树的菜单缩略图与无头 CPU 粒子/影子采样仍使用官方 UV 合成的备用图。

木块弹跳、冰块滑行、岩浆灼伤、蜜脾减速、铁块减伤、TNT 倒计时爆炸及权威端联机伤害保留原数值。音效沿用现有、已经校验为 Minecraft 原声的硫方怪素材；没有新造音效/贴图。新增三张源 PNG（橡木顶面、TNT 顶/底面）直接从官方 Java 26.2 客户端 SHA-1 `2dc72797acbc1b63fc16a11c4ac393605f453754` 取得，其各自 SHA-1 及 jar 路径记在 `Images/characters/我的世界/sulfur_cube/sources.json`。

验证：先执行 Godot `--editor --headless --path . --import` 导入新 PNG，再运行 `tests/test_mc_sulfur_cube.gd`：**43/0** headless、**46/0** 真 GPU（实际帧像素包括空壳、六种方块、TNT 警戒圈）；`tests/test_mc_sulfur_cube_network.gd` 独立回环 ENet 双 peer **18/0**；`tests/verify_mc_sulfur_cube_assets.py` **45 原版文件 + 7 衍生备用图**通过。未进行两台电脑联机或多角色同屏 3D 视口压力测试。

**版本边界：**本轮开始时原有硫方怪场景/脚本/测试/资源整套仍是其他任务的未跟踪文件。因此只提交本轮可独立分离的三维模型、着色器和三张原版源纹理及本说明；现有未跟踪文件内已验证的接入、manifest、生成器与测试修改保留在共享工作区，待原任务将基线纳入 Git 后才能得到可由干净仓库独立重现的完整版本。不得为了制造干净状态而覆盖/整库暂存其他任务文件。
