# 凋灵骷髅验证记录（2026-09-27）

> 长期说明见 `docs/WITHER_SKELETON.md`；回退见 `.backups/wither_skeleton_20260927/REVERT.md`。
> 运行器：`tools/run_wither_skeleton_checks.py`（一次性子进程，不触碰用户现有 Godot 进程）。基线提交 `8afe73510f7bcc75c286534344d53a320c6bd7af`（main）。

## 专项夹具 `tests/test_wither_skeleton.gd`

- **headless（Godot 4.7.2）：46/46，失败 0**；**GPU（gl_compatibility，真实渲染帧）：47/47，失败 0**（第二轮体型/挥剑返工后复跑）。
- 覆盖：基线属性（420/24/88）；手控动作表恰好一个左键；两刀各实际扣 24 且同刀同敌仅一次；第一刀凋零 I、两刀叠到 II 且第二刀把本来源刷新为 3.0 秒；外部来源 IV 被提升到 V 且其 9 秒寿命不被抹除、3 秒后回落 IV；255 级公共上限；负效果免疫拒凋零不拒剑伤；零有效伤害不施加；当前攻击属性改变真实伤害；冷却拒绝连发；暂停冻结不补刀；眩晕/禁攻取消余刀；手动左键用鼠标瞄准、右键/中键空、手控期间 AI 不出手；重复可靠状态包不叠级；过期视觉包不复活连砍；真实采样剑段暴露且结束后清空；AI 在范围内自动起手两连砍；攻击者与目标之间放 StaticBody2D 墙后两刀均不命中；挥剑音计数 2（原版横扫）、静止不踏步、真实位移触发一步且同流不重叠、死亡原生音仅一次；GPU 下待机/第一刀/第二刀三帧互不相同并保存 `tests/wither_skeleton_gpu_*.png`。

## 预览帧 `tests/preview_wither_skeleton.gd`

- GPU：身体全局缩放 0.17（可见高约 25 世界单位，与共享人型足迹一致），四帧（待机/第一刀/第二刀/收招）互异 1666/1639/1091 像素；保存 `tests/wither_skeleton_preview_0..3.png`。人工核对：体型与碰撞盒匹配、石剑比例正常、收招回待机平滑无硬切。

## 第二轮返工（同日）

用户反馈：体型过大、挥剑不好看、挥剑回待机无过渡。核实根因：根节点 0.2 倍全局缩放下旧 `Image` 缩放 2.68 使可见体高达约 120 世界单位（约 4.7 倍标准足迹），且手锚按同倍放大导致剑脱手；收招时刀角从随势角硬切回待机角。

- 体型：`Image` 局部 0.85（可见约 25 单位），碰撞 40×126 / 受击 38×122，脚部仍对齐碰撞盒底。
- 石剑：`blade_length` 38→14、半径 3→2，挥砍突进 2 单位，握把始终贴手锚。
- 挥剑：全缓动曲线（备→砍→收摆→砍→随势），起势自持剑角起步无跳变。
- 收招：0.74–0.98 秒刀角 `lerp_angle` 回待机角、握把滑回待机手；身体末砍帧 0.12 秒残影淡出（`BodyFade` 子精灵，同步 flip_h）。
- 战斗数值未变：窗口/伤害/叠凋零/冷却/索敌 58 全部保持；仅 `RECOVER_END=0.98` 影响连砍总时长与客户端位姿时钟。
- 测试同步更新：体型/碰撞断言、收招过渡断言（0.97s 刀角与待机角差 <0.06rad）、GPU 四帧互异；AI 起手用例将受害体移远避免抢占最近敌。

## 公共回归

- `tests/test_all_character_manual_control.gd`：exit 0（历史 31/31）。
- `tests/test_manual_control_roster_extensions.gd`：exit 0（历史 67/67，含新角色场景装载与动作入口）。
- `tests/test_manual_roster_runtime_audit.gd`：exit 0（全场景普查含新场景）。
- `tests/verify_combat_classification_registry.py`：missing/stale/invalid_kinds/invalid_status_policies/missing_buff_polarity 全空（278 场景 / 610 脚本）。
- `get_diagnostics` 对 `scripts/characters/我的世界/wither_skeleton` 与 `scripts/effects/我的世界/mc_creature_voice.gd`：0 error / 0 warning。

## 未验证（如实）

- 未做双客户端联机实战：状态/位姿同步仅有可靠 RPC 去重与快照恢复的进程内断言，晚加入快照路径同样只在单机夹具验证。
- 音频未做 PCM 人工听验，只验证事件计数、通道 busy 与队列安全；实际音量手感需局内确认。
- 未进行真实对局手感/平衡验收（420/24/1.2s 为参考现有近战的基线）。
- 夹具退出时的 ObjectDB leak 警告来自 SceneTree 夹具自身（音频播放器排队节点），与角色运行时代码无关。
