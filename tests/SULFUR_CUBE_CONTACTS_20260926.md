# 硫方怪：蜂蜜成对免碰撞、地面冰径与随机独立水晶

日期：2026-09-26。本记录是 `SULFUR_CUBE_POLISH_20260926.md` 之后的独立更新，不覆盖旧检查点或旧回退补丁。

## 行为与范围

- **蜂蜜**：按用户确认的 `source_only`，只排除硫方怪与被它黏住目标之间的双向身体碰撞。其他角色、墙和障碍、受击 Area、正常承伤都保留；没有清空碰撞层/掩码，没有给予无敌。大规模战斗软分离查询同一成对排除，避免物理穿透却仍被软推开。
- 公共入口为 `classes/body_collision_exclusions.gd`。每个 holder 的租约独立；释放自己的租约不会撤销别人的，也不删除原先已存在的单向例外。body/holder 离树自动清理；蜂蜜脱离、换形态、死亡也恢复。相对目标路径由权威端同步，客户端不自行决定吸附目标；晚生成的目标会重试解析。
- **冰径**：本体、裂纹使用绝对 `Z=-4`，位于地图底图 `-5` 之上、人物/障碍/投射物前景之下，不受父节点 Z 影响。融化碎片继续调用公共 `block_fragments.gd`，仅传入 `z_layer=-4`。原 4 秒寿命、2 秒开始裂纹及移速增益未改。
- **紫水晶**：每次进入该形态及每轮再生，由权威 RNG 生成 **3–8 根**。每根独立随机角度、根位置、尖位置；没有四向槽位、均分方向或同方向互斥。PackedVector3Array 的根/尖坐标随场景出生和状态变化复制，模型、真实威胁、齐射数量都读取同一布局。
- 每根**附着**水晶对每名敌人每轮生长只结算一次：同时接触两根可在同一扫描中分别伤害；持续贴住、离开再回来不会再次消耗该根的同一轮命中。不同敌人有独立记录，新一轮生长重置。保留每根 `attack_damage(2.0)`、原版有效伤害音效及权威伤害入口；不再共享人物级接触冷却。飞行晶体保留已有独立投射物机制。
- 保留原版穿出身体的交叉网格、0.24 秒无伤生长期和发射帧模型/姿态一致性。扩大正交相机余量并补偿图像缩放，避免随机尖端在最大挤压时被视口裁切，不扩大角色实体或修改身体碰撞形状。
- 手控左/右/中顺序不变：冲刺或铁块单砸／换块／当前随机晶簇齐射。手控停自动齐射，AI 齐射、0.8 秒再生和 2.4 秒准备时间保持。

## 最终验证

引擎：`E:/godot/polo-balls-tools/offline-engine/runtime/Godot.4.7.2.offline.exe`。GPU：NVIDIA RTX 4060 Laptop，OpenGL Compatibility；联网夹具使用真实 ENet、两个独立 SceneMultiplayer，但运行于同一进程。

| 夹具 | 最终结果 | 证据范围 |
| --- | --- | --- |
| `tests/test_sulfur_cube_contacts.gd`（GPU） | **34/34，exit 0** | 来源穿透、另一完整角色/静态墙实际移动碰撞、原层/掩码和承伤保留；软分离；逃离/换形态/双来源/删除/死亡；并发租约与原有例外；64 轮随机布局及中立/最大伸缩尖端边界；同一扫描双晶伤害、逐敌人记录、不重复、再生重置；实际冰径/裂纹脚本的 GPU 分层夹具与碎片参数。 |
| `tests/test_sulfur_cube_polish.gd`（GPU） | **35/35，exit 0** | 冰墙反弹、铁块水平移动/重力、TNT 充能、真实设置威胁显示、手控动作、随机数量本体/发射模型对齐；像素比较 **419 可见像素、0 差异**。 |
| `tests/test_sulfur_cube_redesign.gd`（headless） | **32/32，exit 0** | 六形态、原版素材与模型、真实伤害和碎片回归；固定四根断言改为实际布局数量。 |
| `tests/test_sulfur_cube_redesign_network.gd`（headless ENet） | **38/38，exit 0** | 布局逐坐标一致、客户端不能自行重抽、已生长场景出生/删除、齐射逐根权威姿态、随机再生、蜂蜜目标对应与脱离恢复；原 TNT 等同步/只结算一次回归。 |
| `tests/test_mc_fragment_contract.gd`（headless，未修改） | **18/18，exit 0** | 公共离场碎裂与落地方块粒子原有行为。 |

合计 **157 项断言通过**。最终日志：`tests/*_contact_final.log`（运行产物，不纳入提交）。新接触夹具在退出前等待延迟音效/粒子清理；最终硫方怪四套日志无 SCRIPT ERROR、无 FAIL。项目既有 `set_rgb_color.gdshader` UID/大小写警告仍在；未修改的碎裂夹具仍有 **194 个 ObjectDB 实例**的退出警告，不算作已解决。

### 可复跑命令

```powershell
$godot = 'E:/godot/polo-balls-tools/offline-engine/runtime/Godot.4.7.2.offline.exe'
& $godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/test_sulfur_cube_contacts.gd
& $godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/test_sulfur_cube_polish.gd
& $godot --headless --path . --script res://tests/test_sulfur_cube_redesign.gd
& $godot --headless --path . --script res://tests/test_sulfur_cube_redesign_network.gd
& $godot --headless --path . --script res://tests/test_mc_fragment_contract.gd
```

### 未验证边界

没有进行两个独立客户端的人工手控实战、双语录制编码或大规模性能压力测试。GPU 地面层使用隔离视口、真实冰径/裂纹脚本和测试遮挡物，不宣称逐张地图/所有自定义 Z 障碍均经人工观察。物理第三方碰撞使用另一完整硫方怪角色及静态墙；探索阶段的微型裸基类夹具不作为完整角色碰撞通过证据。

## Git / 回退

- 修改前独立检查点：`E:/godot/polo-balls-tools/checkpoints/sulfur-contact-20260926-034315`。
- 检查点基线：`19ad00f96559b12428405f3ca07dc2feb4800b37`。工作期间有其他任务正常提交，最终提交接在当时最新 HEAD 上，不回滚这些并发工作。
- 本次只提交相关角色/模型/场景、冰径、公共成对排除脚本及 UID、world 的成对软分离查询、专项测试及说明。`MCP_CONTEXT.md`、world 和手控清单的其他未提交内容不整体纳入。
- 独立反向补丁：`tests/patches/sulfur_cube_contacts_20260926.patch`。提交准备阶段执行 `git apply --reverse --check -- tests/patches/sulfur_cube_contacts_20260926.patch`；实际撤销前仍须重新检查并备份当前改动，不能在脏工作区盲目应用。
- 最终提交 ID 与实际父提交写入本检查点的 `commit_result.json`，并在交付回复列出。旧 `sulfur-polish-20260926-031019` 及旧回退补丁保持不变。不使用 reset/clean，不推送远程；局部提交不代表整个脏工作区的完整快照。
