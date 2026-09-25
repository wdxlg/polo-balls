# VS 标题随地图尺寸缩放（2026-09-24）

> 2026-09-25 更新：普通 VS 已改为固定在屏幕顶部；下文“位置始终在地图边框上方”是历史版本行为，不再适用。现行规则与验证见 `tests/VS_SCREEN_TITLE_20260925.md`。

## 规则与范围

- `Map10x10` 继续使用原来的 VS 字号上下限 **12 / 6**。以同一视口里参考地图与当前地图的 `_fit_zoom_for_map()` 比值作为世界字号倍率，并限制在 **0.5–8 倍**；不把用户手动缩放或战斗镜头动画误当成地图尺寸变化。切换地图会从参考字号重新计算，不会累乘。
- 普通对战的 `RichTextLabel` 继续先按**实际标题宽度**选择字号；长中文、英文、多人标题放不下时缩小或换行，标题高度随内容增长，位置始终在地图边框上方。描边及动画留白在大地图同步增大。运行时的有效字号仍发布到原有 `versus_font_min_size` / `versus_font_max_size` 属性，现有双语录制镜像据此分别排版中英文，无需在录制器逐帧增添独立缩放。
- Boss 车轮战使用另一套名单 VS：整个旧名单 HUD（字号、左右名单、滚动和点击区域）随地图一起缩放，宽度仍锁定地图；长名字先缩小字号，极窄地图在保留文字高度的同时只压缩横向，避免侵入 VS 列。轮换训练的新地图格子头像框 HUD 不使用这套缩放；从旧名单切换回头像框时重置其根节点倍率。

## 本机实际结果

- 新增 `tests/test_vs_map_scaling.gd`：独立 Godot 4.7.2 实际 GPU 场景 **66 项检查全部通过**。覆盖 `Map2x2`、`Map10x10`、`Map30x30`、`Map50x50` 的长/短名字、地图边界、字号单调变化，切回小地图、Boss 车轮战名单与长英文名，以及双语录制镜像的缓存重排。检查 GPU 实际像素中的标题，不仅检查节点属性；独立截图在 `user://recordings/vs_map_scaling/`（测试运行产物，不纳入 Git）。
- 实测 `Map50x50` 倍率 **4.333**，字号上限 **52**；长中文标题实际选用 **52**，主镜头下约 **66 屏幕像素**。`Map10x10` 长标题实际 **11 × 5 ≈ 55** 屏幕像素；小地图 `Map2x2` 上限为 **6**，避免挤出地图。Boss 大图 VS 约 **55** 屏幕像素，基准图约 **50**。已人工查看无工具栏的实际 GPU 小/大地图及 Boss 截图，标题不越过地图边框。
- 现有 `tests/test_recording_titles.gd` 用 `TITLE_TEST_CASE=duel_only` 跑真实双语 1080×1920 视频：**24/24**，中英文颜色、换行高度、地图上方锚点、录制画面边界和两份 MP4 均通过。现有 `tests/test_rotation_frames_challenge.gd`：**83/83**，包含新头像框隐藏旧 VS、Boss 保留旧名单。两份现有测试属于工作区其他任务的未跟踪文件，本次不提交。
- `scripts/world.gd` 和新增测试的编辑器错误/警告诊断均为 **0**。运行时仍有原有 `ball.tscn` 的 shader UID 与路径大小写警告；本次未修改相关素材。

## 执行和版本范围

在工程根目录使用 `E:/godot/polo-balls-tools/offline-engine/runtime/Godot.4.7.2.offline.exe --script res://tests/test_vs_map_scaling.gd`（需要 GPU，不能用 headless 做截图）。双语回归运行同引擎加 `--script res://tests/test_recording_titles.gd`，环境变量 `TITLE_TEST_CASE=duel_only`；头像框回归使用 `--script res://tests/test_rotation_frames_challenge.gd`。

修改前 HEAD：`cbaf83d9735b9a52bfddb561aae8af2d12b3b8da`。修改前 `scripts/world.gd` 与 `MCP_CONTEXT.md` 的完整工作副本另外备份于 `%TEMP%/polo_vs_map_before_20260924_133445/`。这两份文件在修改前已有其他任务的未提交变更；本次 Git 版本仅收录 VS 缩放的局部修改及新增测试/说明，其余工作区状态不属于本次回退范围。不要用 `git reset --hard` 回退整棵工作区。
