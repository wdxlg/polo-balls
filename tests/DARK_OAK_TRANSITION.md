# 深色橡木双门：真实 3D 门轴、进出屏移动与原版音效（2026-09-27）

## 使用与当前效果

**设置 → 参数 → 测试双门转场**（`Test door transition`）。按钮仅演示，不重置对局、不切地图；未自动绑定重打/重置/换图。保留紧凑双语设置布局。重新运行游戏加载修改。

本版替代旧平面滑门：两扇有厚度的真正 3D 门板，初始在左右屏幕外，**整扇门从屏幕外面边旋转边移入**，绕各自外侧固定竖直门轴由 −90°/+90° 转到 0° 完全关闭；遮住画面并真实绘制后执行可选切换；开门时**边反向旋转边移出屏幕**，完全离屏后才隐藏，不会在画面边缘突然出现/消失。不是贴图平移、缩宽或伪透视，也不是只转铰链而让门轴凭空出现。关门 0.275 秒、全遮挡至少 0.20 秒、开门 0.30 秒（2026-09-27 起动作速度提高一倍，全遮挡停留时间不变，用于切换安全窗口）；回调较慢则保持关闭。

## 实现与公共接口

- `scripts/ui/dark_oak_transition.gd`：按需创建、根窗口持有的 CanvasLayer 4096 服务，跨 current_scene 替换存活。没有新增 autoload。
- `scripts/ui/dark_oak_doors_3d.gd`：独立 World3D/SubViewport、透视 Camera3D；每扇上下两个真实六面网格，原版 3/16 厚度比例及正反面/侧边 UV。右门镜像把手朝内，最近邻纹理、环境和方向光。整扇门挂在 `LeftCarriage`/`RightCarriage` 上：旋转只发生在本地固定门轴，位移由载具沿屏幕方向进出，动画不逐帧重建网格；空闲停用 3D 渲染。按宽高比调整相机与位移量（3/16 厚度 + 一半门宽再加 0.01 余量），关门时两者同时到达 0，开门结束回到屏幕外静止位；微量边界重叠防止中央漏缝。
- 设置按钮和转场服务登记为 system，3D 门板登记为 visual；无战斗伤害、碰撞、导航、阵营/主人或 RPC。
- `PROCESS_MODE_ALWAYS` 和单调真实时钟驱动，暂停/零速仍播放。转场不修改预览的暂停/速度；真实换场遵循新场景自身启动策略。
- 全屏输入盾拦截普通界面输入，重复请求被拒绝，完成/取消释放并恢复可用焦点；不声称屏蔽业务直接 Input 轮询或冻结整场战斗。

```gdscript
const DOORS = preload("res://scripts/ui/dark_oak_transition.gd")
func switch_with_doors() -> void:
    var overlay:Node = DOORS.ensure(get_tree())
    var accepted:bool = overlay.play(func():
        get_tree().change_scene_to_file("res://scenes/world.tscn")
    )
    if accepted:
        await overlay.finished
```

`play(change:Callable = Callable()) -> bool`：繁忙返回 false；无回调即预览。`covered` 在完全关闭且真实绘制后发出，随后调用切换；支持异步回调，切换后再等待场景树/绘制处理才开门。`is_busy()`、`cancel()`、`finished(completed:bool)` 保留。取消未执行回调，但不能撤销已发生业务；业务应自行检查加载返回值，不能把动画完成当作加载必然成功。

## 原版素材与音效

`assets/ui/dark_oak_transition/SOURCE.json` 记录来源、哈希与许可边界：Minecraft Java 1.21.1 本机 Bbs.jar 的两张原始深色橡木 PNG、`door_bottom_left.json` / `door_top_left.json`；Bbs.json 对应资产索引 **17** 的 `wooden_door/open1.ogg` / `close1.ogg`，原始文件未改，SHA1 与本机官方资产对象一致。运行时只适配屏幕比例和网格坐标。提取不授予 Mojang/Microsoft 素材自由再分发权。

关门到位播放一次 close，开始打开播放一次 open；每对门一次，不因两扇门重复叠播。两个常驻 AudioStreamPlayer 使用现有 **UI 总线/Audios 自动追踪及倍速音高补偿**，默认 0 dB，尊重现有音量设置；暂停/零速可播放，取消停止。没有修改全局音频或战斗音频队列。UI 总线按项目原策略不进入 GameplayRecord，不能将本次预览视为战斗录制器音轨验收。

## 本轮验证（真实 GPU，不是生成动画）

Godot 4.7.2 / D3D12 Forward+ / RTX 4060 Laptop（本轮速度加倍修正）：

- `tests/test_dark_oak_transition.gd` 连续两次 **87/87**（原 81 项加动作耗时实测），子进程均退出 0，无 ERROR / SCRIPT ERROR。覆盖真实设置按钮鼠标事件、中英文、暂停/零速、重复/取消/异步回调、真实 World 替换及原生启动状态对照。
- 检查真正 3D 网格厚度、透视相机、±90°端点、动画不重建、空闲停渲染；高层 4000 的品红夹具在关闭时 GPU 采样不漏底，含奇数尺寸与横竖屏适配。实机半开与全闭截图、逐帧动画已查看，门厚、透视、内侧把手与进出屏移动可见。
- 动作耗时实测：温暖运行状态下实测关门约 281–286 ms、开门约 304–305 ms，与 0.275/0.30 秒一致；合计动作时间低于 0.85 秒。**首次**转场会额外承担一次性 3D 视口/着色器准备，实测首次关门约 1.2–1.4 秒，这是冷启动开销而非速度设置，已如实记录，未作预热优化。
- 端点离屏检查：在 540×960、541×963、1280×720、2400×400 四种尺寸下，先数学验证八个顶点都在视口外，再读回 GPU 画面确认**门轴和门板像素为 0**（不靠 `visible=false` 作弊），并确认一半进度时可见、全闭时每像素都有门、开门结束仍为 0 像素且不重建网格。
- 原版音效顺序 close/open；在暂停且 time_scale=0 时从 UI 总线实际录到非零 PCM；2 倍游戏速度时验证现有 Audios 将 UI 音高补偿到正常速度。
- 最终 **43 张** GPU 逐帧读回，48kHz 双声道 PCM；MP4 使用真实截图时间戳相对 audio_start_ms 对齐。首次截图延迟 0.985 秒保留为设置画面，不把它删掉导致音画错位。视频编码为 H.264/AAC，GIF 仅作无声预览。
- 分类闸门当前为 **278 场景 / 610 脚本，0 缺项、失效项或非法身份/状态策略**（数量随其他并发任务增长，本轮只确认双门相关文件不在任何问题清单中）。服务、3D 辅助和测试脚本编辑器诊断为 0。

### 如实保留的边界

- 原始 close1.ogg 浮点解码峰值约 +0.180102 dBFS；最终 16-bit UI 录音 247808 个样本中有 34 个满幅样本（约 0.01372%）。没有增加播放增益，也不把自动 PCM 验证称为主观无失真听音验收。
- 完整 World 退出仍有 210 个 ObjectDB 实例警告及 shader UID/大小写提示。**headless editor import 退出 3221225477（访问冲突）**，故不宣称导入检查无错；两次图形运行功能测试均退出 0。未扩改该 shader 或全项目资源。
- 设置宽度在上一滑门版本两次 36/36，但退出有铁砧解析/加载及 EVENTS 错误；本版保留按钮/control，未重新执行该宽度测试，不将历史结果冒充本轮回归。
- 4096 层覆盖项目根窗口 UI，不覆盖 OS 原生对话框/桌面；未验收原生弹窗输入、多客户端联机或游戏录制器端到端。

## 证据、局部版本与恢复

- 当前预览：`tests/previews/dark_oak_transition.mp4`（有声）和 `dark_oak_transition.gif`（本版真实 3D，已替换旧滑门 GIF）；验证数据 `tests/dark_oak_transition_validation.json`。
- 本轮前置检查点：`c773595f25d8615e3b7cdeda8e953606e0c81aa7`（`checkpoints/dark-oak-fast-20260927`）；此前依次为 `ffdffab4e835e0fcc1dfb00d8384e233f64028d0`（`checkpoints/dark-oak-entry-20260927`）、`bb386d1295cd727de95d019ba387c00ddca77f31`（`checkpoints/dark-oak-hinged-3d-20260927`）、旧滑门 `d2f10f317206a0c0dd9341c216c62a7ad3e17a25`。
- 结果引用：`updates/dark-oak-fast-20260927`；主 HEAD 和共享 index 不移动/不覆盖，不推送。独立 index 仅保存本轮负责的转场代码/素材/测试/说明差异；共享 MCP_CONTEXT 只纳入本主题条目，不纳入其他会话的新修改。
- 外部证据/备份：`E:\godot\polo-balls-checkpoints\dark_oak_fast_20260927\`（本轮）；早期版本见 `...\dark_oak_entry_20260927\`、`...\dark_oak_hinged_3d_20260927\`。注意：accelerated-speed 调试期间测试输出目录一度指错，`dark_oak_entry_20260927` 的逐帧 PNG/WAV 被本轮运行覆盖；该版本的编码 MP4/GIF、日志、验证 JSON 和定向补丁仍完整，未受影响。本轮备份含 before、日志、原始 PNG/WAV、视频、结果 ID、路径清单和 `owned_update.patch`。不是全工作区快照。

恢复前备份当前修改，对 owned_update.patch 执行 `git apply -R --check`，确认后定向撤销；共享文件冲突必须合并，不盲目恢复整份 context/catalog，不 reset --hard/clean。
