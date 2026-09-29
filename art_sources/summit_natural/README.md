# 山巅派生模型：自然峰顶／分层树雪

本目录由 `tools/build_summit_natural.py` 在独立 Blender 进程生成，保留 `.gdignore` 隔离。游戏引用 `assets/maps/summit/shandian_natural.glb`，不是直接导入本目录的 Blender 场景。

- `山巅.blend`：本次可编辑派生源场景；原版仍在 `../summit/山巅.blend`，未覆盖。
- `shandian.glb`：本派生源的导出结果，与运行目录 `shandian_natural.glb` 完全相同。
- `textures/`：逐字节复用原目录的 Minecraft Java 1.21.1 纹理；原版权和许可限制不变。
- `SOURCE.json`：来源哈希、原资源保护哈希、真实峰顶高度、62 棵树的积雪配置与实际雪块位置。
- `model_metrics.json`：17 个网格、199,280 三角形、748 块枝层薄雪；无雪／少雪／中雪／多雪为 17／11／16／18 棵。

在项目根目录重建前，先备份本目录内任何手工编辑。已有派生场景时，不带 `-- --rebuild` 会拒绝覆盖：

```powershell
& 'E:\steam\steamapps\common\Blender\blender.exe' --background --factory-startup --python-exit-code 7 --python tools/build_summit_natural.py -- --rebuild
python tests/test_summit_natural_model.py
```

生成器复用 `../summit/build_summit.py` 的高度、地形、森林及材质实现，通过可选参数取消强制 9×9 峰顶平台并启用枝层积雪；不复制另一套近似山体算法。原模型、原场景、区域外地形高度以及全部树干／树叶形状均保留。

实际验证、画面、未覆盖范围和局部回退见 `tests/SUMMIT_NATURAL_PEAKS.md`。这是视觉资源，不含可登山导航或新的战斗碰撞。
