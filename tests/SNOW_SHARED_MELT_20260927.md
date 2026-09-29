# 统一积雪融化：接手验收与收尾（2026-09-27）

## 结论与范围

用户选择“接着验收、补完”：保留已有实现，检查雪傀儡雪径、环境地面/墙雪、融化开关、伤害/威胁及联机，并完成局部回退归档。

接手时四个运行脚本已实现统一积雪，但本报告缺失，旧发育合并夹具仍访问已经退役的 `heads`。本轮**没有重写四个运行脚本，也没有改动已确认的20发概率连射、半血保证、左右斜向行走、16向攻击和动作声音**；追加修改集中在失配测试、可靠 GPU 截图/超时退出和文档。完整统一积雪改动与本轮追加改动分别留有补丁。

## 当前行为

| 项目 | 已验收规则 |
| --- | --- |
| 几何/纹理 | 雪径、环境地面和墙雪共用原版雪纹理及实际地图一方块网格，通常16×16；实例 `snow_cell_at/snow_point_at/snow_tile_at` 使用地图真实尺寸/起点，非均匀缩放和平移也跟随。 |
| 正常融化 | 保持完整占地8个融化秒，然后原占地快速淡出0.30融化秒；没有半格阶段，也不永久残留。 |
| 雪环境 | 仅 `_melt_clock` 按0.5倍推进，约16战斗秒保留+0.60秒淡出；接触伤害和寒冷时钟不减半。 |
| 开关 | 关雪立即停飘雪/生成，既有角色雪径、环境地面及墙雪按正常速度继续融化；重新开启不重置已有年龄。真正换图/重置/重打清理。 |
| 判定 | 淡出开始即停止本雪格伤害、积寒及危险区；不会抹掉受害者原有寒冷状态的独立生命周期。墙雪始终纯装饰。重叠地面仍共用目标冷却。 |
| 墙体 | 保留原版2/16厚真实3D雪层、门洞裁切、原相机/光照及阴影；淡出不缩几何，融尽释放雪网格和影子代理，不删共有墙渲染器。 |
| 网络/持续生成 | 权威同步带符号剩余融化时间、淡出时长和倍率；晚加入保留已有年龄/部分淡出，不从头续寿。客户端不结算伤害。融尽位置可以再次积雪。 |
| 原角色 | 雪傀儡寒冷免疫，雪球普通伤害/轻微击退/附加寒冷保留；不恢复落地南瓜、小雪人或旧24→12雪径。 |

实现入口：`snow_golem/snow_field.gd`、`snow_golem/snow_golem.gd`、`training/battle_conditions.gd`、`training/snow_wall_view.gd`，均位于 `scripts/` 下。仍复用已有公共寒冷、伤害、威胁、原版音频与墙渲染，不新增运行脚本或美术资源。

## 本轮补完的问题

1. **发育合并夹具过时**：接手时原归档 `verified/merge` 记录了访问 `snow_field.heads` 报错/超时；当前夹具也仍含这些访问。本轮改用真实方块 `tile/rects`、完整雪与截止时间，验证加替补重排、双分区合并、较新寿命保留及取消合并。轨道继续独立24单位，苔藓、蛛网和冰的原断言保留，不为使测试通过而恢复退役机制。
2. **截图等待依赖自然呈现帧**：本轮首轮 D3D12 融雪测试在第10项之后等待绘制超时；超时清理后旧协程还继续检查并访问已释放 field。共享 GPU `grab()` 改为等待逻辑帧后显式 `RenderingServer.force_draw(false)` 渲染真实视口，不推进战斗时间；融雪测试对每个异步捕获返回检查 `done`，指标写入退出码/超时标志。没有扩大像素容差、延长130秒期限或关闭暂停断言。
3. **headless 几何夹具错误等待画面**：首轮 `map_grid` 在7项后等待 `frame_post_draw`，以退出码2结束，不能算通过。它现于 headless 调用真实墙雪几何同步；GPU 模式继续实际渲染并检查像素。新增一轮真实 GPU 网格/全屏雪验证，不用 headless 结果冒充画面。
4. **文档失配**：公共复用索引不再称“永久环境雪”；环境说明的半格/永久措辞及旧验证描述已更新；角色历史章节明确不再代表当前规则。

首轮失败日志保留在本轮归档 `verified/melt_gpu`、`verified/map_grid`，没有覆盖或加入最终通过数。具体造成首次 D3D12 不再自然呈现的外部窗口条件未单独确证；修正的是测试对该信号无限等待的依赖，不据此宣称修复了游戏渲染驱动。

## 新执行的验证

每次引擎运行使用独立 `APPDATA`/`LOCALAPPDATA`，不复用用户设置。命令、退出码、完整日志和运行脚本 SHA-256 留在归档内。下表按脚本归并，不重复累计同一运行的多个汇总行；不同渲染后端/引擎的同一套断言另列复测。

| 测试脚本（`tests/`） | 模式 | 通过 |
| --- | --- | --- |
| `test_development_terrain_merge.gd` | headless | 42/42 |
| `test_snow_shared_melt.gd` | headless | 44/44 |
| `test_snow_shared_melt_network.gd` | headless / 实际ENet | 24/24 |
| `test_snow_shared_melt_gpu.gd` | D3D12 实际GPU | 16/16 |
| `test_mc_snow_golem.gd` | headless | 79/79 |
| `test_mc_snow_golem_fixes.gd` | headless | 61/61 |
| `test_mc_snow_golem_fixes_gpu.gd` | D3D12 实际GPU | 22/22 |
| `test_mc_snow_golem_burst.gd` | headless | 79/79 |
| `test_mc_snow_golem_burst_network.gd` | headless / 实际ENet | 27/27 |
| `test_mc_snow_golem_projectile_contacts.gd` | headless | 13/13 |
| `test_mc_snow_golem_ice.gd` | headless | 38/38 |
| `test_mc_snow_golem_hit_audio.gd` | headless | 59/59 |
| `test_snow_golem_action_audio.gd` | headless | 36/36 |
| `test_training_events_snow.gd` | headless | 58/58 |
| `test_training_events_snow_lifecycle.gd` | headless | 26/26 |
| `test_training_events_snow_network.gd` | headless / 实际ENet | 29/29 |
| `test_training_events_snow_gpu.gd` | D3D12 实际GPU | 97/97 |
| `test_environment_snow_grid.gd` | D3D12 实际GPU | 60/60 |
| `test_map_wall_camera_stability.gd` | D3D12 实际GPU | 10/10 |

**主回归19组，共820/820项断言通过。** 另以更新后的同一夹具复测：OpenGL融雪16/16；网格headless子集36/36（包含于GPU版60项，不再叠加）。Steam原版引擎融雪44/44、真实ENet24/24、D3D12画面16/16，共84/84，属于跨引擎复测，不加成新的820项。

### 实际 GPU 证据

设备：NVIDIA GeForce RTX 4060 Laptop GPU；离线引擎 `4.7.2.stable.custom_build`，Steam 原版 `4.7.2.stable.steam.ed1daf0bf`。

| 后端 / 引擎 | 雪径半淡出像素能量 / 完整态 | 环境地面 | 墙雪 |
| --- | --- | --- |
| D3D12 / 离线 | 0.500025 | 0.500025 | 0.516242 |
| OpenGL / 离线 | 0.500002 | 0.500002 | 0.784918 |
| D3D12 / Steam | 0.500025 | 0.500025 | 0.516242 |

像素能量以无雪画面为参照、按同一实际矩形求色差；不是几何大小。墙受真实光照/色调映射影响，不要求数值与2D地面完全相同。三个后端运行都验证最终无残留及暂停稳定。

- `gpu_final/melt_gpu/{bare,full_blocks,fade_start,fade_1,fade_2,fade_3,fade_4,gone}.png` 为真实视口读回。对照验证完整雪、半淡出和融尽画面；不是生成图片或替代着色示意。
- 中间态同时检查两类地面像素、真实3D墙雪可见变化、墙网格实例/占地不变、暂停像素稳定；末态检查地面白片与墙雪/阴影均消失。
- 网格 GPU 复测覆盖七主题候选/真实方块、非均匀24×32地图、门洞/接触/威胁，以及小地图缩远、远移、蓝色云上和共享竖屏视口四角的飘雪。墙雪近景为可控生产几何夹具；其他测试另调用真实随机生成器，不把手工摆放冒充自然下雪。

### 边界

- ENet 为**单进程内独立 SceneMultiplayer、真实回环传输和独立物理世界**，不是两台机器/公网延迟实测。已检查重建客户端、不同本地时钟、部分淡出晚加入、倍率切换及可靠删除屏障。
- 本轮没有重新验收正式 BattleRecorder 编码或重录上轮450帧有声影片；历史连射644项、动作声音810项不计入本轮数量。
- 分类覆盖闸门：276个场景、600个运行脚本，missing/stale/invalid_kinds均为空。这是登记覆盖，不代表全角色逐招实战验收；本轮 VS Code error 诊断为0。
- 最终所列通过运行退出码均为0，无 `ERROR`/`SCRIPT ERROR`。既有 shader UID/文件名大小写警告及部分测试退出时的 ObjectDB 提示仍存在；不宣称全工程零警告/零泄漏。

## 局部 Git 与恢复

归档：`E:/godot/polo-balls-checkpoints/snow_melt_review_20260927/`

| 记录 | 版本 |
| --- | --- |
| 原统一融雪开始前检查点，保留不改 | `10c28cfcf7b28feb32eb9aa585fb44963df1214c` |
| 本轮接手现有实现的检查点 | `9d7b3b7e69f2986a912121613726dbe74d4e5918` |
| 保留并行共享文档的归档基线 | `d6e16f15717ae7db80afe016c4b90dd9db7facf8` |
| 完成版本 | `updates/snow-melt-unified-20260927`，完整SHA见同目录 `after.json` |

范围仅24个路径：4个运行脚本、4份规则/专题索引、9份更新的旧夹具、3份新融雪夹具及其3个UID、本报告。原 `MCP_CONTEXT.md` 的硫方怪等并行更新已纳入归档基线，完整雪补丁只带两段雪规则差异；公共复用索引只带雪这一行。四个运行脚本相对接手快照未改变。

- `owned_update.patch`：完整统一融化功能的正向补丁；反向应用才回到本次归档基线。
- `takeover_followup.patch`：仅本轮接手之后的测试/文档补完，用于只撤回本轮追加而保留已有统一融雪实现。
- `before/`、`takeover/`、`baseline.json`、`takeover.json`、`after.json`：原始文件、接手文件、范围和哈希；`verified/`、`gpu_final/` 保存本轮证据，原实现阶段日志仍在 `snow_melt_unified_20260927/`。
- 所有 Git 树/提交使用独立索引；共享 `main`、暂存内容和工作区文件不会因归档被切换。**这些是局部版本，不是完整工程镜像，禁止 `reset --hard` 或整树恢复。**

需要回退时先备份后续工作、阅读补丁，再仅检查对应补丁：

```powershell
git apply --reverse --check --ignore-space-change "E:/godot/polo-balls-checkpoints/snow_melt_review_20260927/owned_update.patch"
```

确认没有后续同文件修改且检查成功后，才在人工确认下去掉 `--check` 应用。任何冲突必须逐块合并，不以强制覆盖解决。本轮只执行反向**检查**，不实际撤销用户工作。
