# 录制命名：Mc小球与中英文数量格式（2026-09-26）

## 现行规则

仅修改录制名称生成，不改对战、画面标题 HUD、音频、帧率、编码和实时/离线时钟。实体分类属于系统/文本命名，未新增招式或伤害能力；仍复用唯一入口 `scripts/ui/battle_record_naming.gd`。

| 情况 | 中文完整标题 | 英文完整标题 |
| --- | --- | --- |
| 单个角色 | `Mc小球:钻石剑 vs 木剑` | `Diamond Sword vs Wooden Sword` |
| 同队多个同名角色 | `Mc小球:3个钻石剑 vs 2个木剑` | `Diamond Sword * 3 vs Wooden Sword * 2` |
| 混合队伍 | `Mc小球:3个牛 + 钻石剑 vs 木剑 + 牛` | `Cow * 3 + Diamond Sword vs Wooden Sword + Cow` |
| 随机选择 | `Mc小球:3个随机人物 vs 2个随机人物` | `Random Character * 3 vs Random Character * 2` |

- 数量大于1才显示数量，1个不写 `1个` / `* 1`。仅在同一阵营/队列内部合并同名角色；不能把对立双方合并。保留队伍和角色初次出现的顺序，混合角色以 ` + ` 连接，对立方以 ` vs ` 连接。
- 英文使用现有本地化目录的英文角色名，不再把中文对阵复制进英文文件名。格式化不切换用户语言。
- 普通、训练、计时、轮放、逐个挑战、Boss和盔甲架测试统一上述格式。移除旧 `中文_` / `英文_`、模式前缀、时长、Boss生命倍率和时间戳；生命倍率不能误当作角色人数。
- 保留原始阵容快照与随机选择来源；角色死亡、局中变化和随后显示的文本不会改掉本次已固定的录制名。随机选择不伪装成固定选中某个角色。
- 无角色信息时仍有明确回退：`Mc小球:自由对战` / `Free Battle`。

## Windows 文件名及防覆盖

Windows 文件名不允许半角 `:`、`*`，因此**实际文件名使用全角 `：`、`＊`**；MP4 内嵌完整标题仍使用用户要求的半角写法。例如：

```text
Mc小球：3个钻石剑 vs 2个木剑.mp4
Diamond Sword ＊ 3 vs Wooden Sword ＊ 2.mp4
```

- 首次不追加日期/时间。检测到同名成片时才追加 ` (2)`、` (3)` 等编号，保留旧文件；已存在的 `.video.mp4`、`.audio.f32` 和 `_frames` 也占用该名字，避免覆盖未完成录制。已存在的同名目录同样避让。
- 保留路径长度预算与截断哈希，过长目录拒绝保存；中文在最窄可用预算下也不能截断 `Mc小球：` 前缀。清理其他非法字符，并保护移除英文前缀后可能出现的 Windows 保留设备名。
- 只影响此后开始的录制，不批量重命名/删除既有录像，也不改用户保存目录。没有额外声称多进程在同一瞬间抢占同一新名字已做原子性验收。

## 已执行验证

环境：Windows，配套 Godot 4.7.2 离线引擎，真实 GPU、FFmpeg/FFprobe。不是仅修改显示示例或伪造文件名。

| 本轮通过的定向检查 | 结果 |
| --- | ---: |
| `test_recording_naming.gd`：精确格式、同队计数、100个、随机来源、全部模式、快照、Windows真实写文件、重名/临时文件/长路径/设备名 | 57/57 |
| `test_recording_bilingual.gd`：真实双语实时录制、三队3/2/1计数、冻结名称、共享世界/音轨/语言恢复 | 32/32 |
| `test_recording_offline.gd`：真实继续当前状态、双份文件与离线时钟 | 46/46 |
| `test_recording_paths.gd`：真实工具栏入口、Unicode目录、保存、续录、零帧取消 | 38/38 |
| `verify_recording_bilingual.py`：4对真实成片完整解码、语言/完整标题/实际文件名、音轨、同一战场时间线 | 63/63 |
| `verify_recording_names.py`：6对、12份实际MP4的文件名/内嵌标题/语言/1080×1920、60fps、H264+AAC，连续录制不覆盖 | 60/60 |
| **以上六组** | **296/296** |

- 新命名夹具在旧实现上的有效基线：55项中38项失败；修复后原55项全部通过，再补2项长路径中文前缀边界，共57项。首次入口使用过早 `preload` 导致自动加载顺序错误的试跑不是有效基线，已改为和既有测试一致的延迟 `load`。
- 6份相关 Python 源文件编译通过。Godot headless editor import 退出0、没有脚本错误。
- 实际数量录像文件为 `Mc小球：3个钻石剑 vs 2个木剑 vs 牛.mp4` / `Diamond Sword ＊ 3 vs Wooden Sword ＊ 2 vs Cow.mp4`；MP4 title 分别为 `Mc小球:3个钻石剑 vs 2个木剑 vs 牛` / `Diamond Sword * 3 vs Wooden Sword * 2 vs Cow`。逐文件大小、SHA256和路径见外部 `real_media_names.json`。
- 原媒体验证不再靠时间戳/旧语言前缀猜配对，基础夹具显式记录同次会话的两个输出路径；公共 `recording_filename_check.py` 对照真实MP4完整标题核验安全文件名。速度/标题媒体验证器仅同步命名断言并通过编译，**未在本轮重新执行这两套完整GPU/媒体流程**。

### 未通过项及边界

不能把上述定向通过误写成所有录制测试全绿：

- 额外 `test_battle_recording.gd`：43/44，`known sRGB chart preserves color without double gamma` 色彩断言未通过；输出文件仍完成且另经媒体检查。这不是命名断言，未修改其颜色阈值、渲染或编码逻辑，也未用修改前完整渲染基线证明其成因。
- 额外 `verify_recording_offline.py`：前6项通过后，在 `0.5 game-second flashes remain 0.5 seconds apart in exported video` 断言失败。本轮不修时序/采样、不放宽阈值；其GPU生命周期46项通过不等于这个媒体检查通过。
- 保留已有 `set_rgb_color.gdshader` UID/大小写警告，以及非法路径、暂停零帧等负向用例的预期提示。
- 不声称所有角色翻译、数小时录制、多进程抢名或所有录制性能问题已验收。

## 版本、证据和局部恢复

- 启动时主分支 HEAD：`3d8be2df82f20436b67d1d2a50493257b5a7a541`；当时有其他大量工作区修改，暂存区为空，未替换它。
- 修改前独立检查点：`1bab0944b317a55de359f8c94a6df32409bdee02`，分支 `checkpoints/recording-names-20260926`；涉及文件原字节另外保存在项目外 `E:/godot/polo-balls-checkpoints/recording_names_20260926/before/`。
- 最终前/后提交、独立更新分支、逐文件哈希、共享暂存区校验与反向补丁检查见同目录 `after.json`；所有通过/失败原始日志均保留，真实文件名和媒体标签记录在 `real_media_names.json`。
- 生产改动仅 `battle_record_naming.gd`；其他为直接相关测试/UID、媒体验证器和规则文档。`battle_recorder.gd` 与目录偏好脚本不改。原地形、光照、云层和角色逻辑不在本次差异中。
- 只创建独立局部Git更新，不移动主分支、不覆盖并行工作、不推送；不是整个工作区快照。恢复前检查并备份当前修改，对外部 `owned_update.patch` 先执行 `git apply --reverse --check` 再复核所需范围，不整文件强制恢复共享文档，不用 `reset --hard` 或 `clean`。
