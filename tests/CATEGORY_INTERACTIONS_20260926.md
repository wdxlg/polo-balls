# 类别交互修复验证与恢复

日期：2026-09-26。此次为用户明确授权的行为修复，不再是只读审计。

## 新增确定性检查

`tests/test_category_interactions.gd`：**123/123**。

覆盖天陨主箭、落箭、旧 ball 子弹、`tests/category_projectile_fixture.gd` 全新协议弹体。后者没有 Ball/BattleTransient 组，也没有传统 direction/speed/Team/Master 字段，只声明公共类别和实现公共能力。

包括：公共候选发现、11个角色相关入口、镜子和觉醒凋零实际改向/归属、悦灵真实消耗音符与存货、原生返还及实际伤害、主箭返还后仍产生箭雨、火焰协议元数据不丢失、磁铁真实暂停/恢复弹体、铁丝网真实扣耐久且不重复、盾狗前后方与拦截收尾、剑客非ball弹反收尾、醉汉/极速者实际轨迹预测、快速新弹体扫掠捕获、落地阶段、暂停与非权威拒绝。

## 兼容回归

| 测试 | 最终通过 |
|---|---:|
| test_combat_classification | 2768 |
| test_combat_classification_regression | 6 |
| test_allay | 86 |
| test_allay_extended | 105 |
| test_allay_native_return | 87 |
| test_sheep_final_wool | 24 |
| test_heavenfall_contacts | 22 |
| test_heavenfall_arrow_pierce | 63 |
| test_mc_native_fire | 18 |
| test_mc_unified_status_effects | 137 |
| test_boat_onboard_control | 41 |
| test_void_projectile_contacts | 68 |

连同新增123项，共 **3548项最终通过断言**。注册规模为277场景、601运行脚本；测试和夹具不计入运行资源。

最终采用的各次日志均引擎退出0、SCRIPT ERROR计数0。日志仍有既有shader UID/文件名大小写警告和部分headless纹理环境消息，不能写成“日志完全无警告”。

调试过程曾出现入口预加载Game尚未初始化、入树前health尚未初始化、已释放Node延迟调用、原生火球速度被默认Speed覆盖等问题，均已修复或调整测试夹具，最终重新验证。原生返还测试另有一次缺少 `allay_launch_audio` 元数据而中断，随后相同代码重跑87/87通过；其精确时序原因未在本轮完全定位，不作为已证明永久消除的音频问题。未修改该旧测试以绕过断言。

## 运行方式

从项目根目录：

```powershell
& 'E:/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' --headless --path . --script res://tests/test_category_interactions.gd
python tests/verify_combat_classification_registry.py
```

SceneTree命令行夹具在run阶段动态加载依赖Game的脚本，避免早于autoload初始化预加载ball。新夹具路径使用tests根目录，不纳入角色资源。

## 未完成验证

- 真实双客户端、晚加入和录制回放的交互端到端验证；当前只有权威门控断言和既有相关接触回归。
- GPU视觉和实际音频听感。
- 高负载帧率基准、所有角色×所有弹体穷举、每种复杂曲线弹道的碰撞精度。
- 节肢附魔历史后备识别、凋零不同障碍破坏机制没有被粗暴合并；它们并非本轮确认的纯白名单故障。

## 回退范围

修改前已将classes/scripts/docs中的源码和UID、MCP_CONTEXT及Git状态保存到 `%TEMP%/arena_interaction_before_20260926.zip`。只备份源码不是整个项目完整快照。

最终使用独立索引创建本轮负责路径的前/后局部Git检查点，不移动main、不替换真实暂存区；具体提交ID由交付结果记录。新增依赖、测试、说明及其生成UID一并纳入本轮范围。不要用这些局部树覆盖其他对话尚未提交的整个工程。

回退先备份当前修改，生成两个检查点之间的binary patch并执行 `git apply --reverse --check`，确认无冲突后才反向应用。不得 `reset --hard`、`clean -fd`，也不得整个文件夹覆盖回旧快照。
