# Minecraft 角色视觉修订 · 第三轮

## 已部署
- 魔角猎人：过载与小爆弹的原有 RPC 回调改用共享 `MC爆炸.tscn`；伤害、半径、标记和网络权威逻辑不变。
- 苦力怕：主体继续使用共享效果，补齐此前遗漏的苦力怕头。视觉挂 `MCLocalEffects`，不会随角色死亡提前截断，也不会被 World MultiplayerSpawner 重复生成。
- 爆炸烟雾：初始高度 0–6 → 0–1.5，上抛速度 85–180 → 30–68。保留前后纵深、重力、随机灰度、大小及原帧消散，不做 alpha 淡出。固定种子 1234、半径 55 的测试峰值高度 9.041。
- 守卫者：原模型离线烘焙 64 方向 × 8 尾巴/刺动画帧，统一模型中心与 160×160 帧画布；不是旋转旧斜视图片。指数平滑追踪视线，`turn_response=12` 可调；激光起点采用同视图眼球投影。仍仅在四世界轴各 ±15° 锁定，断线与伤害机制不变。
- 史莱姆：起跳少量原纹理碎粒上抛落回；落地径向散粒回落，脚下椭圆绿圈扩大渐隐。按大/中/小缩放，脚点不随空中贴图上移。视觉与伤害分离，authority RPC 每端创建一次；没有重复落地伤害。

## 素材及复现
- 守卫者沿用已有 Mojang Bedrock 原模型、纹理及动作适配；64 方位为离线模型投影，游戏内不运行 3D。
- 史莱姆碎粒来自官方 slimeball 纹理的 2×2 裁片；来源及 SHA256 见 `slimeball_source.json`。绿圈是用户要求的程序性地面特效，不是替代角色素材。
- 上游固定版本：`Mojang/bedrock-samples@736072450c26a7c67f07b1661f29d9a5ebaa14b1`。素材仍受 Mojang 版权及 Minecraft EULA 约束。
- 生产存档：`scripts/training/mc_new5_assets/bake_guardian_views.py`；在保留同目录 `bake.py`、`resource_pack` 和既有相邻 `mc_native_assets` 的环境中，安装 Pillow/numpy 后运行，输出到 `assets`。包含全部 512 帧无裁切断言、眼球偏移元数据与静态预览图。
- 图集 10240×1280，RGBA 解码约 50 MiB；本轮在 RTX 4060 / D3D12 上确认未缩小、未裁切。未进行移动端纹理上限验证。

## 验证
| 测试 | 结果 |
|---|---:|
| `scripts/training/test_mc_round3.gd`（无窗口及 D3D12） | 3157 检查，0 失败 |
| `scripts/training/test_mc_new5.gd` | 104 检查，0 失败 |
| `scripts/training/test_mc_revision.gd`（D3D12） | 343 检查，0 失败 |
| `tests/test_mc_native_batch2.gd` | 2235 检查，0 失败 |
| `scripts/training/test_mc_new5_live.gd`（D3D12 实景） | 21 检查，0 失败 |

真实音频输出 PCM 24064 帧，峰值 0.3224。该次实景预热 3499 ms，预热后守卫者首次 ready 0.998 ms；这些是本次桌面运行的测量值，不是所有机器的性能保证。

`mc_round3_preview.gif` 是 Godot SubViewport 播放实际角色帧和生产特效脚本的 96 帧展示；为便于检查，使用专用背景和放大显示，并非完整对战录像。

仍有项目原有退出时 ObjectDB 泄漏警告，本轮日志为 98–107 个；未声称全项目零警告，也未进行双客户端或大规模压力测试。
