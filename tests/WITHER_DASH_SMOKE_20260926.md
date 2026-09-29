# 凋零冲刺减速与烟雾（2026-09-26）

## 本次行为
- 用户选择：速度为修改前的 65%，黑灰烟雾。
- CHARGE_SPEED 500 → 325；保留距离相关 1.55 → 0.45 的减速曲线，因此起步 503.75、末段 146.25 世界单位/秒。冲刺距离、伤害、破障、威胁判定与 C 键中键动作不改。
- 每移动 12 世界单位在身体后方 30 单位发射两枚烟雾，寿命 0.65 秒；纯视觉，无伤害。停止移动不发射，余烟自然消散；暂停时冻结；BattleTransient 随清场清理。
- 复用 mc_visual_effects.gd 的公共入口 smoke_particle 和已有末影粒子运动/淡出实现。全局 256 枚上限，每次最多 48 组；authority RPC 只同步视觉点位，不附带伤害。
- 纹理复用 Images/characters/我的世界/wither/big_smoke_0.png，来源见同目录 SOURCE_MANIFEST.json：Minecraft Java 1.21.11 原版 particle/big_smoke_0.png。Mojang/Microsoft 资源，非自由再分发素材；未新增或生成图片。

## 验证
- tests/test_wither_dash_smoke.gd：离线 Godot 4.7.2 无头真实 World 场景，251 项、0 失败、引擎退出 0。覆盖 65% 实际位移、原版纹理、身后位置、暂停/寿命、扫掠破障、地图安全墙、单次伤害、威胁结束清理、重打地形恢复。
- 初次测试将伤害基准放在第一段移动之后，敌人已被扫掠半径命中而误报；改为整次冲刺前记录生命后通过，未修改伤害实现。
- tests/test_wither_dash_smoke_gpu.gd：D3D12 / RTX 4060 Laptop，2 项、0 失败、引擎退出 0；已读取 GPU 截图确认凋零后方黑灰粒子可见。截图及日志位于 .git/wither-dash-20260926/。
- 两个实现文件编辑器诊断均无返回错误/警告。运行仍有既存 shader UID / 大小写警告；无头运行另有 RendererDummy RID 错误，GPU 本轮日志未见该错误。不声称日志全干净。
- 未完成双客户端联机、录制成片、大规模压力及全角色手控回归。

## 局部版本与回退
- 原 main HEAD：19ad00f96559b12428405f3ca07dc2feb4800b37。
- 修改前局部检查点：a3a15b35d9bf143275ad6c6b20e20ee9db63c15c，refs/heads/checkpoints/wither-dash-20260926。
- 本次结果保存在 refs/heads/updates/wither-dash-20260926，以检查点为父提交；使用隔离 Git index，未改变 main、未动其他暂存内容、未推送。
- 检查点保存 wither.gd、mc_visual_effects.gd、MCP_CONTEXT.md 修改前实际内容。功能提交相对检查点仅包含本次实现、索引、两份新测试与本文。工作区其他大量未提交/未跟踪依赖不包含在内，因此不是整个项目完整可独立运行快照。
- 回退前检查并备份最新工作区，再对功能提交生成 git diff <检查点> <结果提交>，使用 git apply -R --check 确认可逆后才反向应用；若同文件有后续修改，先合并，不用 reset --hard 或 clean。
