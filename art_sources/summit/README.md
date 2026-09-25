# 山巅 · SUMMIT

独立的 Minecraft 方块高山模型，2026-09-26 制作。**本轮仅建模，没有替换或注册 Godot 的正式战斗地图。**

## 打开与文件

- `山巅.blend`：Blender 5.2.2 LTS 原生可编辑场景，包含分组网格、原版贴图、灯光和主相机；实际使用的 14 张纹理已打包。
- `shandian.glb`：自包含 glTF 2.0 模型，包含几何、UV、14 种材质及原版 PNG。无相机、灯光、体积雾、碰撞和导航。
- `summit_hero.png`：1800×1400 主视角实机 Cycles 渲染。
- `summit_detail.png`：1400×1100 峰顶与岩壁近景实机渲染。
- `build_summit.py` / `render_summit.py` / `validate_summit.py`：生成、渲染和回读验证脚本。
- `SOURCE.json`、`textures/`：本机 Minecraft Java 1.21.1 原版资源来源、客户端与逐图 SHA256、权利说明。
- `model_metrics.json` / `validation_report.json`：实际模型统计和 133 项检查结果。

目录的 `.gdignore` 有意阻止 Godot 在制作过程中自动导入 Blender 源文件。将来接入游戏时，应明确选择 GLB 的正式导入目录，而不是直接删除隔离标记并导入整个源目录。

## 构图与结构

不对称高耸主峰、侧峰与锐脊、深切山谷、分层岩壁、雪线、局部冰脉、62 棵方块云杉、折返石径及峰顶石堆。以西南斜视角强调主峰和深峡，暖色直射光与冷色环境光形成明暗对比。

地形采样网格为 144×144，1 Blender 单位对应 1 方块。地形自身最大高差 102 格；包括峰顶石堆的完整网格包围盒为 `(-71,-66,-5)` 至 `(72,67,99.5)`，即 **143×133×104.5** 单位。

有效导出网格 17 个，原生顶点 381,192，三角形 190,596。按地形、树林、峰顶地标和材质批处理，不是每块一个 Blender 对象；面与 UV 保留方块边缘和一格一纹理。可在编辑模式修改网格，或备份后调整脚本重建。

原生场景还保留 `RENDER ONLY - cloud sea` 可选低云体积对象；视觉检查后默认关闭，以免大片雾遮住岩壁和原版纹理。它不进入 GLB。编辑视口默认使用材质预览，光照与正式 Cycles 渲染不同。

## 原版材质与可移植性

15 张源 PNG 从用户本机已安装的 Minecraft Java 1.21.1 客户端提取，字节未修改；其中 `grass_block_side.png` 保留在来源目录，当前模型实际使用其余 14 张。草、云杉叶及部分岩石在材质中乘以色调，不绘制或生成替代贴图。

Blender 5.2 的 glTF 导出器对本场景 `MixRGB MULTIPLY` 节点保留贴图但漏掉常量染色。生成脚本在导出后写入标准 glTF `baseColorFactor`，并断言所有嵌入 PNG 与源文件完全一致。GLB 的纹理放大采用 NEAREST。已回读渲染检查，避免草和树叶变成灰色。

原版资源版权属于 Mojang Studios / Microsoft。用户本机使用和来源记录不构成自由再分发许可；公开发布模型、打包游戏或转售前，需另行核对 Minecraft EULA 与 Usage Guidelines。

## 本轮实际验证

- Blender 5.2.2 LTS：生成、保存、GLB 导出、原生文件重新打开均完成；最终生成子进程退出码 0。
- Cycles / OptiX / NVIDIA GeForce RTX 4060 Laptop GPU：1800×1400 主图 64 samples，1400×1100 近景 48 samples，完成且子进程退出码 0；两张实际图已人工检查。
- 独立回读：133 项检查通过，验证子进程退出码 0。覆盖网格有效性、非退化面、UV、所有源纹理 SHA256、原生文件打包纹理、GLB 原始 PNG 字节、最近邻采样、染色因子、17 网格与 190,596 三角形及世界包围盒一致性。
- 回读 GLB 后另做 900×700 / 24 samples GPU 渲染，人工检查了材质与构图，未见缺贴图或丢失叶片染色。
- **已知提示**：本机 Cycles 输出 `Driver version is too old` 警告，但本次 OptiX 渲染及回读均正常完成；不宣称驱动无警告，也没有擅自更新驱动。脚本在 Blender 5.2 有 `use_nodes` 的未来弃用提示。

验证是 Blender 本机 GPU 与 GLB 回读范围，不是 Godot 运行、导航、碰撞、联机、录制或帧率验收。没有为该资产运行不相关的战斗测试，也不把旧任务测试算作本次验证。

## 再生成和渲染

在独立 Blender 进程运行；不要在含未保存作品的场景里直接执行生成脚本。重建会重新生成本目录的模型和统计。已有 `山巅.blend` 时脚本拒绝覆盖，只有明确添加 `-- --rebuild` 才允许：**先备份所有手工编辑**。

```powershell
$blender = 'E:\steam\steamapps\common\Blender\blender.exe'
# 首次生成（目录已有模型时会拒绝）
& $blender --factory-startup --python build_summit.py
# 备份后有意重建
& $blender --background --factory-startup --python-exit-code 7 --python build_summit.py -- --rebuild
# 在本目录中执行下面命令
& $blender --background '山巅.blend' --python-exit-code 7 --python render_summit.py
& $blender --background '山巅.blend' --python-exit-code 7 --python validate_summit.py
```

## 将来接入游戏的边界

这是静态三维美术资产，不是已经能让现有 2D 角色攀登的关卡。石径是视觉路径，不保证每步可走。峰顶 `SUMMIT_ANCHOR` 空对象仅在原生场景中提供参考位置 `(8.5,15.5,96.25)`。

接入时仍应沿用此前讨论的“固定 3D 环境 + Godot 动态适配地图”分层，明确处理动态区域的重复地面、遮挡、比例、光照/昼夜同步及现有 2D 碰撞。GLB 不携带本场景的天空、灯光和色彩管理，不能把导入后的默认光照当作这里的效果图。

## 版本与恢复范围

建模前项目 HEAD：`0ebb11fb48cec6accb618684ebd3d06424bc02f3`。
检查点：`E:\godot\polo-balls-checkpoints\summit_model_20260926\`，包括原始规则备份、已有未提交规则差异、初版模型、构建/渲染/验证日志和完成时的提交记录。

本任务提交仅负责 `art_sources/summit/` 的必要资产、脚本、说明、预览和 MCP_CONTEXT 中的一条索引。共享工作区存在大量其他修改，且期间其他任务产生了新提交；这不是整个项目的干净快照。回退前再次检查并备份当前编辑，优先撤销本任务提交或恢复其明确文件，勿使用全局破坏性重置。
