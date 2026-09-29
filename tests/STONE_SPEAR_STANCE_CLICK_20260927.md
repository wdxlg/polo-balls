# 石矛换阵声音改为机械咔嗒（2026-09-27）

用户不满意挥动破风声，并明确选择“短促的咔嗒声：像武器切换到位，干脆、有机械感”。

## 调整

- 换阵音源由7种随机横扫声改为固定原版发射器click，约0.279646秒。复用现有`audio/characters/我的世界/cactus_note/dispense.ogg`，不复制素材、不修改其字节或其他角色。
- 源记录` scripts/training/mc_music6_assets/sources.json`（路径无前导空格）对应`block.dispenser.dispense`，本轮文件SHA-1复核为`ec4f4d122ab7c5d44e48419de0e3de1b0922514d`，与原来源记录一致。
- 仍是每次成功切换一次、手控/自动共用；同阵/冷却/暂停/死亡/禁用等失败操作静音。固定音源不再抽音效随机数；原伸刺、命中、格挡音不改。
- 0dB、自然音高1、本体发声位置、可靠主客同步、公共安全队列与GameplayRecord总线、24声部预算及非伤害优先级全部保持。玩法数值和动作无变化。

## 验证

音频专项33/33、GPU及真实PCM36/36、双ENet63/63、核心132/132，各进程退出0；石矛diagnostics=0。减少的12个断言仅来自七种旧音源检查改为一种新音源（每种两项）；其余成功/失败、手控/自动、重复姿态、删除取消、预算等检查不减。

真实切换捕获GameplayRecord非零PCM7680帧，peak=0.491403。实际音源已下载为本地试听文件；未声称进行了主观听感验收。既有shader UID/大小写警告保留。未重复运行不受本轮纯音源替换影响的全部形态/伤害专项，也未声称修复历史格挡测试退出资源告警。

## 范围与回退

仅修改石矛脚本、现有音频专项、MCP石矛说明，新增本报告。历史音频报告保留。备份、四个测试日志与最小反向补丁保存在`E:/godot/polo-balls-checkpoints/stone_spear_stance_click_20260927/`。

隔离父提交`91978d50e0f38687b0ef9ed415ac81850aef403d`，引用`checkpoints/stone-spear-stance-click-20260927`→`updates/stone-spear-stance-click-20260927`，完整ID见checkpoint内`commit_ids.json`。不移动主HEAD/index，不覆盖共享并行修改。恢复前备份，执行`git apply -R --check --unidiff-zero <owned_update_minimal.patch>`检查后定向回退，不用reset --hard/clean。
