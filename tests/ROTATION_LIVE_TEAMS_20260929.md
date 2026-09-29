# 轮换不停局、车轮入场与队伍胜利提示 — 2026-09-29 修订

## 用户本轮规则（覆盖上一版）

1. 非车轮轮换：上一局结束后继续像普通模式一样发展，胜利提示和关门过程中不冻结战斗；门完全关严后才停止旧局、加载下一局。完成后的经验条/成就退场与半开门开始下一局保持。
2. 车轮战不走门、不走加载条、不弹逐次换人的胜利成就；直接衔接，下一位从地图外连续走入，胜者实例、生命和原状态保留。图腾与家族重验仍保留，不因去掉动画而恢复误判。
3. 用户澄清：新的队伍胜利提示应用于**除轮换模式之外**的适用玩法。多人获胜方显示颜色队名及展示框中的同色羊毛；原本仅一人的获胜方仍显示人物。不是按结算瞬间剩几人决定：原多人队伍只剩一个幸存者，仍显示队伍。

## 实现与复用

- 只改 `scripts/world.gd`、`scripts/ui/duel_top_hud.gd` 两个业务脚本，没有复制门动画或另建胜利 HUD。
- 把“正在处理死亡/换局”的互斥标志与“加载期间禁止战斗”的 gate 分离。死亡重验、成就停留和门的 CLOSING 阶段不关战斗 gate；全覆盖加载回调才关，半开时释放。
- 旧胜者可能继续被旧投射物/状态打死；全覆盖时重新检查存续并合并晚到败方，挑战模式不把已经死亡的挑战者错记为成功。
- wheel 绕过门流程，保留原 0.28 游戏秒图腾/家族重验。换人只生成败方下一位，赢家照常活动。
- 入场参数化复用 `_animate_ball_back_inside_map`：车轮补位按距离/当前 Speed 计算 0.65–3 秒的线性物理帧入场，真实身体位置从地图外到原侧出生点，不是在场内直接出现。仅入场者暂时停止自身物理/状态机运动，防止 AI 和入场同时推位置；根深度临时高于场外裁剪，入场后恢复原深度/状态机/物理。
- 玩家暂停/公共战斗 gate 关闭时暂停入场；节点退出由绑定 Tween 清理，死亡取消剩余入场。其余地图救援仍保留原时长/缓动，没有给所有角色增加入场动画。
- 顶部同一 HUD 增加结果快照，按 setup/原家族身份记录参战成员，并以当前原胜负机制的胜者为准；不修改普通/Boss/计时的判胜或计分口径。
- 存续代数、退出/待删除检查阻止 reset 的旧成员在 deferred 清理窗口重新进入下一局名单。召唤物不计为独立参战成员。
- 多人胜者不需要先缩成 1v1 才能展示成就；正文按队伍颜色显示，物品框内以原版羊毛纹理画三面方块。第一/第二队沿用原蓝/红色；第三队及以后沿用原 VS 稳定颜色，再映射到最接近的原版 16 染色羊毛。单人和轮换原人物提示保持。
- 英文镜像仍用 `make_mirror` 读取同一个结果，显示如 `Blue Team won!`，不重新计算胜负。

## 素材

目录 `Images/UI/team_victory/`：16 张原版羊毛 PNG、对应导入配置与 `SOURCE.json`。

- 来自 Minecraft Java 1.21.1 官方客户端 JAR，完整下载长度 **26836906**，与官方元数据 SHA-1 **30c73b1c5da787909b2f73340419fdf13b9def88** 一致。
- 官方 URL：`https://piston-data.mojang.com/v1/objects/30c73b1c5da787909b2f73340419fdf13b9def88/client.jar`。
- PNG 原字节提取自 `assets/minecraft/textures/block/*_wool.png`，逐文件 SHA-256 在 SOURCE.json。没有 AI 重画或调色；三面投影/明暗为 HUD 绘制。
- 素材归 Mojang/Microsoft，不宣称获得再分发许可。曾检查旧检查点的 26.2 文件，但它不是有效 ZIP，未使用其内容；实际交付只使用上述已校验的 1.21.1 来源。

## 最终验证：614 检查，0 断言失败

| 测试 | 执行方式 | 结果 |
|---|---|---:|
| `test_rotation_live_team_victory.gd` | 真实 Windows GPU | 45/45 |
| `test_duel_top_hud.gd` | 真实 GPU，原回归 | 82/82 |
| `test_rotation_timed_flow.gd` | 真实 GPU，更新轮换契约 | 55/55 |
| `test_rotation_timed_boundaries.gd` | 真实 GPU，更新轮换契约 | 28/28 |
| `test_dark_oak_transition.gd` | 真实 GPU，24 抓帧 | 87/87 |
| `test_rotation_frames_challenge.gd` | headless | 97/97 |
| `test_battle_lifecycle.gd` | headless | 83/83 |
| `test_evoker_totem.gd` | headless | 41/41 |
| `test_slime_family_victory.gd` | headless | 63/63 |
| `test_rotation_timed_network.gd` | 两独立进程本机 ENet，改为 duel 门场景 | 12+21=33/33 |

新专项实际检查旧胜者在重验/成就/关门中的物理位移、全覆盖 gate、半开释放、晚到死亡、车轮场外连续位置/赢家继续移动/暂停与恢复、蓝红/第三队、多人队伍只剩一人、单人获胜、Boss/计时、召唤物排除、reset 清理和轮换排除。

最终 GPU 截图已目视：蓝羊毛/蓝队、红羊毛/红队、单人头像、车轮入场采样及完整 1080×1920 英文只读镜像。原测试地图云层遮挡保持，不能据此声称看清所有角色运动细节；入场连续位移另有真实身体坐标断言。

测试过程中：初次位移夹具受首帧 GPU 初始化影响，改等实际物理帧；增加 timed→manual reset 用例后发现旧成员残留，修正代数/待删除过滤后通过；镜像夹具改用正确 World2D API 和原录制逻辑分辨率，最终无截断。没有静音或屏蔽引擎错误来伪造通过。

MCP `get_diagnostics`：0 项。最终以上日志无新增 SCRIPT ERROR。历史 shader UID/大小写告警保留。全局分类仍有 **35 项范围外缺失**，本轮两个既有运行脚本均已登记，没有新增需分类的运行脚本。

**未验收**：公网延迟/断线/晚加入、所有特殊角色的入场组合、多人完整实战复制、root 门的录制合成和离线 MP4 成片。ENet 是既有生产 RPC/状态回归，不能当作新增队伍 UI/全角色公网验收；新镜像 GPU 抓帧也不等于成片验收。

## 备份与隔离恢复

检查点：`E:/godot/polo-balls-checkpoints/rotation_live_teams_20260929/`。

开工 HEAD：`f466e3a1886944368e746b10eb8c395b4752ff41`。保留上一轮改动与并行工作，不 reset/clean/push；本轮使用独立 index，最新 after 逆精确 hunks 重建 before，仅隔离本轮差异。

refs：`refs/checkpoints/rotation-live-teams-20260929-before`、`refs/checkpoints/rotation-live-teams-20260929-after`。确切 hash、主 HEAD/index 校验、范围清单、素材校验和逆补丁检查见检查点 `version.json`。

必要时先检查，不直接覆盖：

```powershell
git apply --reverse --check --unidiff-zero ../polo-balls-checkpoints/rotation_live_teams_20260929/rotation_live_teams.patch
```

确认后才去掉 `--check`；以后同区块有并行改动时冲突即停，手工合并。上一轮检查点仍保留，但回退本次应使用本次补丁，不整文件覆盖上一轮。
