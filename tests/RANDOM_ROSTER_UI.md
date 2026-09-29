# 随机抽取阵容 UI

人物方式紧凑布局、设置保留和点击排除人物见 `RANDOM_CHARACTER_SETTINGS.md`。

## 行为

- `configure_roster` 在首个抽取动画之前建立所有匿名席位，只保留席位 ID 和展示队伍，不缓存未揭晓人物名。
- 阵容面板上方有独立角色转盘：候选立绘横向滚动、减速并准确停在中央选框，随后在原席位揭晓。候选展示从开启分类的完整角色池中做最多 8 个预览的有界采样，不从整局秘密结果列表生成；本次落点始终为 authority 已选定角色，不重新抽签。预览缓存上限 32，不保留活跃战斗角色子树。
- 转盘继承暂停时仍运行的进程模式，使用实时时钟；揭晓时准确对齐本次权威结果，取消时随整个抽选层销毁。无可用预览纹理时仍展示角色名/首字。
- 动效链：面板短距离淡入 → 转盘中心放大/两侧淡出与流动轨道 → 金色选中框扫光和轻微弹动 → 角色带像素拖尾沿弧线飞入对应席位 → 卡片横向展开、边框扩散与队伍色粒子 → 队伍计数轻弹、经验段短闪及上浮 `+1`。背景使用低亮度慢速像素微粒，不使用全屏强闪或大幅震屏。
- 新增 `scripts/ui/random_character_draft_fx.gd`，所有特效归抽选层所有、随层销毁，无游离 Tween/Timer。上限为 4 个飞行物、8 组粒子、6 个边框波纹、4 个经验提示及 24 个席位过渡；预算溢出时旧席位立即恢复正常显示。完成时强制收尾，避免留下透明/缩扁的人物。
- 完成音效播放完毕后进入 **0.42 秒退场**：整层背景与内容平滑淡出，阵容/转盘缩小 2.5% 并轻微下移，露出已经生成的战场。经验条只随层淡出和像素对齐位移，不做小数缩放。
- 退场使用墙上时钟，不受战斗暂停、零倍速影响；淡出到完全透明后才移除抽选层、恢复原暂停状态与战斗闸门。重复退场请求幂等，窗口尺寸变化保留进度；重置/取消仍即时清理，不等待退场、也不会迟到恢复旧战局。
- 特效轨迹使用确定性公式，不调用全局随机数；原版经验条只叠加短暂光效，不参与弹缩，原像素比例与 N 人 N 段保持不变。
- 手动：队伍颜色分区；无队伍统一归入无队伍区；多队自适应网格。
- 计时：按队伍显示阵容；不再显示上方模式说明或装饰性标题。
- 轮放：上下双方队列、保留出场编号；空的对侧仍显示队伍面板。
- Boss：所选 Boss 队伍置顶并使用金色边框，另一侧标为挑战方；支持左右 Boss 配置。
- 未揭晓始终为 `?`。已揭晓名字和静态缩略图保留；预览冷资源不可用时显示人物名字/首字，不把已抽出结果继续画成问号。
- 缩略图保留 Sprite2D 的图集区域/帧裁剪，AnimatedSprite2D 使用当前帧，不保留大量活跃角色预览节点。
- 删除顶部“命运抽选”、模式副标题和底部说明文字，保留队伍、人物和人数进度；底部“加速揭晓”按钮及其信号、控制器加速状态已删除；使用不透明背景避免底层战斗 HUD 文字透出。
- 经验条使用 Mojang 官方 Minecraft Java 1.21.4 客户端中原样提取的 `experience_bar_background.png` / `experience_bar_progress.png`。客户端 SHA-1 已与官方元数据匹配，两张 PNG 的 SHA-256 在回归中再次校验；来源和权利说明见 `Images/UI/minecraft_xp/SOURCE.json`。
- 原 PNG 不修改。运行时对原贴图的段体、分隔列和端帽做切片重组，因此显示布局不是原版固定 18 段：N 人恰好 N 段，每揭晓一人立即填满一段，无半段缓动。超过 45 人自动换行，所有行的总段数仍为 N；不会把大量人物挤成不可辨认的亚像素线。
- 每行经验条始终为原版 **182×5** 比例：源像素按 1:1 复制/平铺组成宽段，严禁把 9×5 段体横向拉宽。显示绕过阵容面板的小数缩放，在实际窗口像素级做整数倍等比放大和位置对齐，因此低人数下也不会变成扁长的模糊色块。
- 原暂停恢复、取消、实例化和联机完成闸门不变；完成停留覆盖升级音效全长，`animation_scale=0` 仅作为测试路径保留。
- 展示队伍沿用战斗的左右半场判断，未指定队伍的轮放/Boss 席位不会错误归入无队伍区。

## Minecraft 音效

- `scripts/ui/random_character_draft_audio.gd` 拥有 4 个非空间 UI 播放器（每种事件最多一个播放声部），跟随抽选层释放，不创建游离定时器、不消耗全局随机数。
- 转盘跨格：原版 `random/click.ogg`，-8 dB（较初版提升 20 dB），最短间隔 100 ms；减速时点击随跨格自然变疏，揭晓即停。
- 权威结果揭晓：原版 `random/orb.ogg`，-3 dB（提升 12 dB），最短间隔 220 ms。
- 头像实际飞入完成：原版 `random/pop.ogg`，-6 dB（提升 14 dB），最短间隔 170 ms；没有飞入动作时不伪造落位声。
- 全部抽取完成：原版 `random/levelup.ogg`，-3 dB（提升 13 dB），每轮仅一次，压住低优先级音效；正式流程至少保留音效全长加 60 ms 后才释放界面。
- 使用现有 `Audios` 的 UI 总线和时间补偿，不修改用户总线音量/静音。战斗暂停时仍可播放，2 倍游戏速度不加快 UI 声音。取消关闭所有声部并拒绝迟到事件。
- 官方 Minecraft Java 1.21.4 资产索引及 CDN 原文件经过 SHA-1/SHA-256 核验，保存在 `audio/ui/random_draft/originals/`。为规避本机初次 OGG 导入异常，运行时采用原采样率、原声道的 PCM16 `AudioStreamWAV` 原生 `.tres` 资源（内嵌样本），不再引用外部 WAV 导入缓存，不改音调、时序或增益；原文件目录用 `.gdignore` 排除重复导入。来源、原文件与播放文件的哈希见 `audio/ui/random_draft/SOURCE.json`。素材仍属于 Mojang/Microsoft/相应作者，来源记录不授予额外使用权。

- 音量反馈后检查发现，旧的 4 个 WAV 播放文件已变成约 556–604 字节的静音短文件，无法通过原哈希验证；现已从核验过的原音频重建原生资源，并将本地增益提高 12–20 dB。回归录音峰值检查提高为 18000–32000，避免“文件加载成功但实际上静音”被误判通过。

## 验证

使用项目的 **Godot 编辑器可执行文件**（不是 `.performance_tools/godot_release.exe` 导出模板）：

```powershell
& $godot --headless --editor --path . --import
& $godot --headless --path . --script res://tests/test_random_character_draft.gd
& $godot --headless --path . --script res://tests/test_random_roster_ui.gd
& $godot --path . --resolution 540x960 --audio-driver Dummy --script res://tests/test_random_roster_ui.gd -- --visual
& $godot --path . --resolution 540x960 --audio-driver Dummy --script res://tests/preview_random_character_draw.gd
& $godot --headless --audio-driver Dummy --path . --script res://tests/test_random_draft_audio.gd -- --record
& $godot --path . --resolution 540x960 --audio-driver Dummy --script res://tests/preview_random_character_exit.gd
```

- 音效专项：`RANDOM_DRAFT_AUDIO checks=41 failures=0`，检查原版/运行时文件哈希、声部上限、限频、完成幂等、暂停/2 倍速、静音继承、随机流、取消与释放；`--record` 通过实际 UI 总线 `AudioEffectRecord` 生成 `tests/random_draft_sound_preview.wav`（本轮约 3.72 秒，PCM16 峰值 21336，无削波）。录音是阶段音效演示，不是整局游戏录像。
- GPU UI 测试退出前留出音频缓冲清理时间，避免立即退出时尚未混音完成的声部被误报泄漏。
- 最终独立资源导入退出码为 0；验证需等待导入完成，不与导入过程并行启动游戏。
- 原流程回归：`RANDOM_CHARACTER_DRAFT checks=66 failures=0`。
- UI/GPU 回归：`RANDOM_ROSTER_UI checks=12259 failures=0`，其中大部分为逐席位几何与源像素比对；另包含转盘真实位移、精确停靠、权威确认与四阶段音效事件、官方 PNG 哈希、整数屏幕像素缩放、逐人整段填充、动态段数、换行布局与标题删除检查。
- 动效补充检查：飞入/经验粒子被触发、卡片恢复全尺寸可见、经验条像素缩放不变、40 人同帧快速揭晓的预算上限、完成强制收尾、粒子全部过期、全局随机流不被消耗、抽选层销毁时特效子层同步释放。
- 覆盖四模式、问号不泄露候选、连续揭晓保留、重复揭晓幂等、缺失预览、经验条完成、1/17/128/1024 席位、1024 队伍、三队不均衡、空阵容、空对侧、左右 Boss、横竖屏及英文 UI。
- 退场补充：UI 检查透明度中间态、零倍速/暂停、收缩位移、XP 像素不变、重复调用、缩放窗口、完全透明终态及状态复用；流程测试分别验证退场期间战斗锁定、结束恢复和退场中重置无迟到回调。实际 GPU 退场序列为 `tests/random_character_exit_XX.jpg`，本轮 19 帧，预览日志 `EXIT_FRAMES=19`。
- GPU 截图为 `tests/random_roster_*.png`；实际游戏抽取截图为 `tests/random_character_draw_preview.jpg`。截图脚本对 HDR 2D 读回做线性到 sRGB 转换，避免截图错误偏黑。
- 实际游戏转盘序列为 `tests/random_character_roll_XX.jpg`，使用剑客、保安、猎人、军官、矿工组成的测试池；帧数由日志 `ROLL_FRAMES` 标记。
- 动效演示采样延长到首次揭晓后约 0.68 秒，以覆盖飞入、卡片展开与经验反馈；本轮采集 35 帧（以日志 `ROLL_FRAMES` 为准）。演示脚本使用 `animation_scale=2.5` 便于检查，不修改正式抽取的默认时长。
- 保留项目原有 `set_rgb_color.gdshader` UID/路径大小写警告；本轮未改动无关着色器资源。
- 未穷举全人物资源、未进行双客户端联机或跨平台导出验证。超大阵容会缩小格子并隐藏小格文字，可通过悬停查看已揭晓角色信息。
