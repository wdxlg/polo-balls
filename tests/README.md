# tests/ — 手工回归 / 基准 / 预览脚本

本目录中的脚本原位于 `scripts/training/`，均为 **不被任何场景引用、需要手工用 `--script` 运行** 的 `SceneTree` 脚本。
移到这里是为了与运行时代码（`scripts/training/` 中仍被场景/RL 引用的脚本）分开。

## 运行方式

```powershell
# Headless（大多数 test_* 脚本）
& <godot.exe> --headless --path . --script res://tests/test_performance_contracts.gd --quit-after 5

# 需要真实窗口/GPU 的（test_mc*_revision、benchmark_*、preview_*）
& <godot.exe> --path . --resolution 540x960 --script res://tests/benchmark_probe.gd
```

## 分类
- `test_*`：回归测试，进程退出码 0 表示通过
- `benchmark_*` / `profile_*`：百人性能基准与采样（见根目录 PERFORMANCE_*.md）
- `preview_*` / `live_*`：摆拍预览，不作为验证依据
- `pack_release_probe`：导出包探针

依赖的公共基类仍在 `scripts/training/`（`benchmark_100.gd`、`test_visual_equivalence.gd`、`live_sans_feedback.gd` 等），因为它们同时被场景引用。
