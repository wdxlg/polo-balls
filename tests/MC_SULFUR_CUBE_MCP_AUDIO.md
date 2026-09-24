# 硫方怪：MCP 原版音效规则（2026-09-25）

对照 `MCP_CONTEXT.md` 第 1、2、4、6 条后，仅调整硫方怪音效，不改玩法与其他角色。原版检索：Minecraft Java **26.2** 官方资源索引 `32.json` SHA-1 `52695890153d94cf946455da532806db8c530831` 中 `minecraft/sounds.json` SHA-1 `9ac006d5537ed0fa4a7bcd1eccfc505155847686`；`entity.sulfur_cube.jump`（11 变体）、`squish`（11）、`hurt`（4）、`death`（1）存在，但 **没有 `entity.sulfur_cube.step` 或 `ambient`**。项目现有已校验为该版本原版的 jump1/2、squish1/2、hurt1/2、death 已足够本轮使用；缺失的原版脚步/待机事件不以其他生物或自制音效冒充。

当前行为：只在上一物理帧**真实位置有变化**时循环播放原版 jump/landing squish，排除原地、高速度但未移动和传送位移；停战/死亡/暂停不触发。每次播放取实际所选 Ogg 的 `stream.get_length()`、`pitch_scale` 和全局播放速度算最短间隔，同时用 `playing` 保护动态变速；jump 与 squish 共用不重叠的位移声道。由于 jump 变体长约 0.84–0.93 秒，可等它结束再发落地挤压声，不因 0.43 秒动作时刻直接放弃落地声。没有单独呼吸/待机循环，原因见资源检索，不宣称已实现不存在的原版素材。

实际受伤继承 `mc_mob_base.gd` 的 45% 概率原版 hurt，仅有效生命损失且未死亡才播；死亡仍只播一次原版 death，同时另播项目默认 `DeadBell`，而不是用原版声替换默认声。向敌人真正扣血后依照现有公共 `hit_audio_gain.gd`：`actual <= 50` 普通 Minecraft 受击、`actual > 50` 原版暴击，默认基线 **0 dB / 1x**，随实际生命损失平滑增益，上限 +6 dB；保留每次结算仅一次反馈，木/冰/岩浆/蜜脾/铁/TNT 机制、原版专属接触声和爆炸声不变。

专项验证：`tests/test_mc_sulfur_cube.gd` 无头 **54 checks / 0 failures**，真实 GPU **58 / 0**（含真实战场角色渲染和原声钩子），`tests/test_mc_sulfur_cube_network.gd` ENet 双 peer **19 / 0**，包含权威端真实移动时 host/guest 各播一次原版 jump。校验了静止/传送静音、真实位移、所选音频时长/音高、不同位移声不叠、落地声可延迟、50 阈值、0dB 基础、高伤增益、有效受伤声、原版 + 默认死亡声。`python tests/verify_mc_sulfur_cube_assets.py`：**45 原版文件 + 7 原贴图衍生图**。测试将上一段跳声停止来确定性模拟结束，不声称做了真实世界连续跑动听感录制或两台电脑的系统音轨验收。

**并行与回退边界：**原硫方怪脚本、音频表、测试均属于另一未跟踪基线，本轮先备份修改前/后：Arena 工作区 `/home/user/硫方怪_音效修改前检查点.zip`、`/home/user/硫方怪_音效修改后检查点.zip`，只改了硫方怪脚本与两项对应测试；这三文件的唯一增量在 `tests/patches/sulfur_cube_mcp_audio.patch`，已用 `git apply --reverse --check --no-index` 在当前工作区验证可逆。Git 只提交本轮可分离的补丁和说明，不冒领/覆盖原基线或共享 `MCP_CONTEXT.md`；干净检出需先合并原基线、再应用补丁。恢复前请先核对当前工作区，勿直接 `reset --hard`/`clean`。
