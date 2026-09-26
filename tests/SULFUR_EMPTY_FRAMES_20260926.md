# 硫方怪：出生即显示两个空物品展示框

日期：2026-09-26。用户纠正：展示框一开始就存在，不能等取得方块才出现。

## 修改范围

- 两个框在角色出生、尚未获取方块以及暂停时都显示，左右位置保持固定。
- 首次获取只显示左框的方块图标，右框仍为空框；第二次填右框，后续 FIFO 顺序不变。
- 空槽只隐藏内容图标，并清除旧贴图和方块元数据，不隐藏展示框。清空后不会留下上一次的方块。
- 为避免原版物品图标自带的斜向物品图案看起来像空槽已有内容，在框内复用原版空展示框背板。不是重新绘制或生成贴图。
- 未修改两种特性的计算、冷却、手控、威胁、体内最新块、TNT 消耗或既有死亡清理。

实际逻辑改动位于 `scripts/characters/我的世界/硫方怪.gd` 的框创建/刷新函数。`MCP_CONTEXT.md` 和双槽专题中的旧显示时机说明已纠正。

## 素材

新增 `Images/characters/我的世界/sulfur_cube/source/item_frame_back.png`，直接从项目已有的官方 Minecraft Java 26.2 客户端缓存提取，字节不变。

- 客户端 SHA-1：`2dc72797acbc1b63fc16a11c4ac393605f453754`
- 原始条目：`assets/minecraft/textures/block/item_frame.png`
- 图片 SHA-1：`7faef83b54adb6bbdd62baee551cc1ff1c721d18`
- 来源与许可说明补充在同目录 `ITEM_FRAME_SOURCE.json`；来源记录不代表可自由再分发。

## 本轮最终验证

Godot 4.7.2 offline 引擎；实际 GPU 为 OpenGL Compatibility / NVIDIA RTX 4060 Laptop。测试使用检查点内隔离 `APPDATA`，不修改用户实际设置。

| 夹具 | 模式 | 结果 |
| --- | --- | --- |
| `tests/test_sulfur_cube_dual.gd` | 无头 | 143/143，exit 0 |
| `tests/test_sulfur_cube_dual.gd` | 实际 GPU | 149/149，exit 0 |
| `tests/test_sulfur_cube_dual_network.gd` | 两个独立 SceneMultiplayer / ENet 端 | 36/36，exit 0 |

GPU 149 项包含无头夹具中的重复逻辑，不算成独立新增覆盖。六种实际画面状态都验证了两个框可见：空槽、仅左槽、两个槽、FIFO 后、旧紫晶配新铁块、再次清空。已读取并目视核对 `empty_spawn.png` 和 `first_ice.png`：两个空框从一开始都在；取得冰块后左边填充、右边仍为空框，没有装饰性物品图案冒充内容。

网络回归覆盖客端出生空框、第一块入左且右框不消失，以及同步清空后两端都保留框且不残留旧图标。双槽能力的原有组合回归仍包含在同一夹具中。

第一次 GPU 运行断言全通过，但退出时报告两个资源尚未释放；增加测试退出清理等待后，最终三次运行均无 `SCRIPT ERROR`、`ERROR:` 或失败断言。没有为此改动游戏战斗逻辑。工程既有 shader UID/大小写警告保留。这里的 ENet 是同进程双端，不是两台客户端人工实战；未重做视频编码或大规模性能压测。

## Git 与回退

- 任务开始提交：`25024ad4cda82e79b7cef0651e8a2d6ccc5c6ec5`。
- 修改前备份和本轮日志/截图：`E:/godot/polo-balls-tools/checkpoints/sulfur-empty-frames-20260926-081142`。
- 最终父提交与新提交记录在上述检查点 `commit_result.json`，并在回复中报告。
- 仅提交本次显示修正、对应原素材/来源、测试和说明。共享规则文件只提交本条差异，不混入其他任务修改，不推送远程。
- 独立回退补丁：`tests/patches/sulfur_empty_frames_20260926.patch`，提交前执行反向检查。只回退本次“空框常驻”修正，不撤销双槽特性本身；补丁自身留存。

```powershell
# 只检查是否可回退；实际回退前仍需备份当前改动。
git apply --reverse --check -- tests/patches/sulfur_empty_frames_20260926.patch
```

不是整个脏工作区的完整快照；不要覆盖整个共享规则文件或使用未授权的 reset/clean。
