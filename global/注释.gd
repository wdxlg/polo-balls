extends Node

# =============================================================================
# polo-balls / 极速者 RL 开发备忘
# =============================================================================
# 本脚本只保存“可直接复制”的训练命令与必须注意的事项，不参与游戏逻辑。
# PowerShell 命令不能裸写在 .gd 中，否则 GDScript 会把它当代码解析并报错。
# 因此命令全部放在 r""" ... """ 原始多行字符串中。
# 复制三引号内部内容到 PowerShell 即可，不需要改任何字符。
# =============================================================================

# 【必须确认】
# 1. Python 使用 3.11 创建的 rl_env。
# 2. res://addons/godot_rl_agents/ 必须是完整插件，并在 项目设置 → 插件 中启用。
# 3. Python 训练器要先启动，再运行 res://scenes/training/SpeedsterRLWorld.tscn。
# 4. 看到 handshake complete 后才算正式连通。
# 5. 一次只运行一个训练 Python；不要开两个 trainer 抢同一个端口。
# 6. rl_env/.gdignore 与 rl_training/.gdignore 不要删除，否则 Godot 会扫描大量 Python/模型文件而卡顿。
# 7. 当前训练场建议只绑定一个极速者；敌人数量可以很多。
# 8. 如果 ESC 倍速负责 1x~32x，Sync.speed_up 建议保持 1，避免两套倍速系统叠加。
# 9. Observation / Action Space 尺寸一旦改变，旧模型通常不能 resume，必须重新训练。
# 10. Reward 数值改变但 Observation / Action Space 不变时，技术上通常可以继续训练，但训练目标已经改变。
# 11. .zip 是可继续训练的 Stable-Baselines3 PPO 模型；.onnx 是部署到 Godot 的推理模型。
# 12. 威胁调试显示不依赖极速者：红白 = 实际伤害区域（伤害越高越红），绿色 = 实际无伤害碰撞区域。


# =============================================================================
# 【环境检查】直接复制三引号内部全部内容
# =============================================================================
const POWERSHELL_CHECK_ENV := r"""
cd E:\godot\polo-balls
.\rl_env\Scripts\Activate.ps1
python --version
python -c "import godot_rl; import stable_baselines3; print('Godot RL + Stable-Baselines3 OK')"
"""


# =============================================================================
# 【新开一轮训练：100000 steps】
# 注意：不带 --resume = 从一个新的随机 PPO 模型开始。
# 旧文件仍在磁盘上，但不会自动被加载。
# =============================================================================
const POWERSHELL_TRAIN_FRESH_100K := r"""
cd E:\godot\polo-balls
.\rl_env\Scripts\Activate.ps1
python .\rl_training\train_speedster_dodge.py --timesteps 100000
"""


# =============================================================================
# 【继续上一次训练：100000 steps】
# 只有模型文件已经存在时才使用。
# =============================================================================
const POWERSHELL_TRAIN_RESUME_100K := r"""
cd E:\godot\polo-balls
.\rl_env\Scripts\Activate.ps1
python .\rl_training\train_speedster_dodge.py --timesteps 100000 --resume .\rl_training\runs\SpeedsterThreatCombat_v3\speedster_v3_final.zip
"""


# =============================================================================
# 【自动判断：有上次模型就继续，没有就新建】
# 这是日常训练最方便的一段。
# =============================================================================
const POWERSHELL_TRAIN_AUTO_100K := r"""
cd E:\godot\polo-balls
.\rl_env\Scripts\Activate.ps1
python .\rl_training\train_speedster_dodge.py --timesteps 100000 --auto-resume
"""


# =============================================================================
# 【删除 V3 训练结果，重新从零开始】
# 只删除模型/日志/检查点，不会删除 Python 环境或 Godot 项目代码。
# 请先停止 Python 训练器再执行。
# =============================================================================
const POWERSHELL_DELETE_V3_TRAINING_RESULTS := r"""
cd E:\godot\polo-balls
Remove-Item -Recurse -Force .\rl_training\runs\SpeedsterThreatCombat_v3 -ErrorAction SilentlyContinue
Remove-Item -Force .\rl_training\models\SpeedsterThreatCombat_v3.onnx -ErrorAction SilentlyContinue
Write-Host "V3 training results deleted. Next training will start from a fresh model."
"""


# =============================================================================
# 【训练结果位置】
# =============================================================================
# rl_training/runs/SpeedsterThreatCombat_v3/
#   speedster_v3_final.zip       ← 当前最终 PPO 大脑；可 resume
#   checkpoints/                 ← 每 50000 environment steps 保存一次
#   tb/                          ← TensorBoard 日志
#
# rl_training/models/
#   SpeedsterThreatCombat_v3.onnx ← 训练结束时导出的 Godot 推理模型
#
# 不带 --resume：不会读取上次模型，会创建新 PPO。
# 带 --resume：从指定 .zip 继续训练。
# 带 --auto-resume：若 final.zip 存在则自动继续，否则新建。
#
# 如果你从零训练却继续使用同一个 save-dir，最终 final.zip 会被新的训练结果覆盖。
# 因此想保留历史版本时，先复制/改名旧模型，或使用不同 --save-dir。


# =============================================================================
# 【Reward 原则】
# =============================================================================
# 单纯活着：0 分。
# 成功避开真实威胁：加分。
# 对敌人造成真实伤害：加分。
# 短时间高爆发：额外加分。
# 自己受到伤害：扣分。
# 死亡：大幅扣分；训练模式中角色随后由复活系统重新生成。
# 无效闪避 / 无意义能量消耗 / 高反制风险下错误进攻：小幅扣分。


# =============================================================================
# 【判断是否真的在学习】
# =============================================================================
# total_timesteps：必须持续增长。
# ep_rew_mean：长期趋势比单次 loss 更有意义。
# 同时应观察实际战斗统计：成功闪避率、平均受伤、DPS、爆发伤害、胜率、能量利用率。
# entropy_loss 很接近最大随机程度时，说明策略还在大量探索。
# explained_variance 越接近 1，Value Network 通常越能解释未来回报，但它不能单独代表角色已经变强。

# =============================================================================
# 【通用威胁系统 V3.3】
# =============================================================================
#
# CombatThreatAnalyzer 不属于极速者专用系统。
#
# 任意正常人物 ball 都可以调用：
#
#     analyzer.get_threats_for(人物)
#     analyzer.get_targets_for(人物)
#
# 获得“对这个人物而言”的敌方威胁与目标。
#
# 调试显示则使用：
#
#     analyzer.get_world_threats()
#
# 它扫描整个战场，不需要极速者，也不需要 Python/RL 握手。
#
# 【威胁调试显示的颜色/几何约定】
#
# 1. 白 -> 红：
#    必须是“当前真实能造成伤害的区域”。
#    优先直接读取运行时 CollisionShape2D 的真实 transform/尺寸；
#    没有物理 Shape 的脚本攻击，才使用 get_ai_attack_threats /
#    get_ai_hazard_info 声明的真实伤害几何。
#    颜色只按这一区域的伤害量变化：伤害越高越红，低伤害接近白色。
#
# 2. 绿色：
#    当前没有伤害、但真实参与物理碰撞的区域。
#    包括人物本体、普通障碍、无伤害地形、矿工石头等。
#    Hurtbox 只是“可被攻击区域”，不重复显示；人物本体碰撞已经用绿色表示。
#
# 3. 蓝色（低透明度）：
#    角色/机制真正用于“是否开始攻击、锁定、触发技能”的检测范围。
#    它不是伤害区域，也不改变物理碰撞。非标准几何优先实现：
#
#        get_debug_detection_regions() -> Array[Dictionary]
#
#    返回 circle / rect / segment 世界坐标几何。已有真实 Area2D 检测器也可在
#    Area2D 或 CollisionShape2D 上设置 meta：threat_debug_detection = true。
#    Analyzer 还兼容 attack_range / ranged_attack_range / enemy_notice_radius 等
#    明确的旧式圆形起手字段。
#
# 4. 禁止再用“角色半径兜底框”冒充威胁。
#    看不到伤害框意味着该机制没有被标准系统声明/标记，应修机制本身。
#
# 新角色优先复用以下标准机制：
#
#     标准 Ball 投射物
#     Has_Collision_Damage
#     正常 hitbox/CollisionShape2D
#     AI_Hazard + get_ai_hazard_info(receiver)
#     get_ai_attack_threats(receiver)
#
# 非 ball 的特殊 CollisionObject2D 如果自身碰撞会造成伤害，可以直接设置：
#
#     collision_object.set_meta("threat_debug_damage", 实际伤害)
#
# 值为 0 表示该碰撞区域是无伤害碰撞（绿色）。
# 这样棋子伤害 Sensor、地面石头等都能直接显示实际碰撞形状，
# 不需要在 CombatThreatAnalyzer 里按角色名字写特例。
#
# 近战/斩击如果本质上依赖空间命中，也必须优先建立真实 Area2D + CollisionShape2D，
# 由 overlap/body_entered 决定是否命中；不要只按“当前锁定目标”直接调用扣血。
# 这样实际命中、墙体/人物空间关系、威胁调试看到的是同一套几何。
#
# “威胁调试显示”关闭时会立即隐藏并清空旧图形；
# 再次开启时重新扫描全场。
#
# AI observation 仍使用抽象威胁数据；绿色碰撞调试层只用于可视化，
# 不增加/改变训练输入维度。
# =============================================================================


# =============================================================================
# 【V107 攻击力统一语义】
# =============================================================================
# 1. ball.Damage = 角色“整体基础攻击力”，绝对不是“身体碰撞攻击力”。
#    身体自然碰撞是否伤人只由 Has_Collision_Damage 决定。
#
# 2. 只有一种攻击时：该攻击最终基础值 = Damage × 1.0。
#    有多种攻击时：Damage 应保存该角色最低的基础/独立攻击值；其它攻击只保存倍率。
#    例如：Damage=20，重击倍率=3.0，则重击基础伤害=60。
#
# 3. 所有角色脚本、召唤物、投射物、持续伤害、范围伤害都应从攻击者当前 Damage 派生。
#    推荐统一调用 attack_damage(multiplier)，或在生成投射物/效果时传入 Damage × multiplier。
#    禁止新增与 Damage 脱钩的 attack_damage=50 / skill_damage=200 这类独立绝对伤害。
#
# 4. 攻击力 Buff/偷取/Boss 倍率修改 Damage 后，角色的所有攻击方式必须一起变化；
#    不能只改变身体碰撞、普通拳头，却让子弹、技能、DOT、召唤物仍保持旧固定伤害。
#
# 5. 动态机制（蓄力、转速、速度、成长、阶段、行情等）只能改变“伤害倍率”，
#    不应为了表现当前伤害而每帧覆写 Damage。Damage 始终保留为当前整体基础攻击力。
#
# 6. 纯规则阈值/自伤/环境惩罚不属于角色对敌攻击，可以保留独立数值；
#    但只要伤害归属于某个角色并用于攻击敌人，就必须遵守 Damage × 倍率。
#
# 7. 召唤物/随从如果属于角色攻击方式的一部分，默认继承主人的当前 Damage；
#    用 inherit_master_attack_power + master_attack_damage_multiplier，或显式 Master.attack_damage(倍率)。
#    只有“作为独立可配置战斗角色”的单位才允许维护自己的 Damage。
#
# 8. 子弹/地形/状态/特效脚本里的 damage_amount / tick_damage 等字段只能作为“本次实例的最终伤害载荷”。
#    它们必须在创建/setup 时由攻击者的 attack_damage(倍率) 写入，不能再被当成第二套角色基础攻击力。
#
# 9. 角色场景中的 Damage 应保存“最低的非零对敌基础攻击”。没有任何伤害能力的纯辅助角色才允许 Damage=0。
#    旧场景中的 xxx_damage=绝对值属性迁移后必须改成 xxx_damage_multiplier，禁止让旧绝对值继续覆盖新倍率。
#
# 10. 例外：自伤、反噬、生命百分比结算、环境固定惩罚、处决/必杀条件、单纯统计阈值不属于“对敌攻击力”；
#     这些可以保留规则值。但一旦伤害被归因给某个角色并作为其进攻输出，就必须回到 Damage × 倍率。
# =============================================================================

# =============================================================================
# 【V108 Boss 顶部 VS 单一显示规则】
# =============================================================================
# Boss 模式有两套“VS 表现”，但任何时刻只能显示其中一套：
#
# 1. Training_Boss_Wheel_Battle = true：
#    只显示 RotationVersusHUD（轮换名单 / 当前角色 / 历史角色的 VS）。
#    普通 versus_label 必须隐藏并清空，不允许两个 VS 同时出现。
#
# 2. Training_Boss_Wheel_Battle = false：
#    Boss 使用普通/手动式 versus_label，根据当前场上实际参战角色生成 VS。
#    RotationVersusHUD 必须隐藏。
#
# 3. 普通 rotation 模式仍只使用 RotationVersusHUD。
#    manual / timed / 非车轮 Boss 使用普通 versus_label。
#
# 4. 切换 Boss 车轮战开关后必须立即 refresh_versus_text() 并让另一套 VS 隐藏；
#    不允许依赖下一帧的特殊训练更新去“碰巧”把另一套 VS 藏掉。
# =============================================================================


# =============================================================================
# 【V109 ball 速度运动模糊】
# =============================================================================
# 1. 所有 Type == Ball_Type.Ball 的正常角色默认启用速度运动模糊；低速不显示，速度越高越明显。
# 2. 运动模糊是纯视觉：ball.gd 在 Graphics 下运行时创建 MotionBlurGhost，并使用
#    res://shaders/ball_motion_blur.gdshader。它不修改 CharacterBody2D、CollisionShape2D、Hitbox/Hurtbox。
# 3. 模糊层不替换角色自己的 ShaderMaterial。原人物保持清晰本体，模糊副本只复制当前 Sprite2D/
#    AnimatedSprite2D 的当前纹理与变换，因此人物专属染色、软体、技能 Shader 仍由原 image 负责。
# 4. 默认 motion_blur_start_speed=120；低于该值完全隐藏。motion_blur_full_speed=520 时达到完整强度，
#    更高速度封顶，避免高速角色无限拖长。
# 5. 默认最大采样拖影距离 motion_blur_max_pixels=22，最大透明度 motion_blur_max_alpha=0.52；
#    motion_blur_response=13 控制加速/减速时模糊强度追随速度的快慢。
# 6. 多人远端继续使用同步位置差分估算视觉速度；超过 motion_visual_teleport_threshold 的单帧位移
#    视为传送，不把传送误判成超高速运动模糊。
# 7. 大规模战斗下仍沿用原有视觉错峰更新；而且速度低于阈值时 MotionBlurGhost 完全不可见，
#    避免所有静止/普通慢速单位都额外支付 6 次纹理采样成本。
# =============================================================================

# =============================================================================
# 【V110 V109 运动模糊解析修复 + 醉汉躲弹速度上限】
# =============================================================================
# 1. GDScript 的 @export_category 只接受一个 name:String 参数。
#    V109 曾误写 @export_category("", "")，会使 classes/ball.gd 无法解析，继而让所有引用
#    class_name ball 的 world.gd / 角色脚本级联出现“Could not parse global class ball”。
#    以后不得用两个参数“关闭分类”；没有后续 export 时直接结束即可，需要退出 export_group 时才使用 @export_group("")。
#
# 2. 醉汉躲弹的 dodge_speed_multiplier 是“一次闪避期间的速度倍率”，不是“每物理帧累乘倍率”。
#    禁止把 _current_chaos_speed *= dodge_speed_multiplier 写回基础醉步速度，否则 60Hz 下会指数增长。
#
# 3. 正确规则：_current_chaos_speed 始终只由 chaos_speed_min/max 的醉步随机目标与 response 平滑维护；
#    躲弹时另算 movement_speed = max(_current_chaos_speed * dodge_speed_multiplier, dodge_min_speed)，
#    并以 max(chaos_speed_min, chaos_speed_max) * dodge_speed_multiplier（或 dodge_min_speed）作为机制自身硬上限。
#
# 4. Speed Buff 仍在上述机制速度之后按 buff_speed_ratio 正常同比生效；因此“上限”只防止躲弹自身无限叠乘，
#    不会把合法的速度 Buff、Boss 倍率或其它外部速度规则强行截断。
# =============================================================================

# =============================================================================
# 【V111 牛系 V107 攻击力迁移残留调用修复】
# =============================================================================
# 1. 牛/牛犊子的 Damage 必须继续遵守 V107：Damage = 整体基础攻击力，不能随 Speed 每帧改写。
#
# 2. 牛系的速度只负责提供“冲撞倍率”：
#       最终冲撞伤害 = attack_damage(return_damage_multiplier_from_speed(Speed))
#    因此 base_run_speed 时约为 Damage × 1.0，最高速时为 Damage × max_charge_damage_multiplier。
#
# 3. V107 删除了旧的 _refresh_damage_from_current_speed() 语义，但牛系在“冲撞重置”和“开始吃草”
#    两处仍遗留了对该已不存在函数的调用，会导致 GDScript 报：
#       Function "_refresh_damage_from_current_speed()" not found in base self.
#    以后修改攻击力统一系统时，必须同步清理所有旧方法调用，不能只删除方法定义。
#
# 4. 冲撞结束时只恢复/重算 Speed；开始吃草时只把 Speed 设为 0。两处都不得回写 Damage。
#    吃草期间因为 Speed == 0，return_current_impact_damage() 会自然返回 0，无需另设“当前伤害”。
# =============================================================================

# =============================================================================
# 【V112 运动模糊 Shader 编译与朝向修复】
# =============================================================================
# 1. res://shaders/ball_motion_blur.gdshader 的 TEXTURE / TEXTURE_PIXEL_SIZE / REGION_RECT
#    都是 CanvasItem fragment built-in。它们只能在 fragment() 可用的处理作用域中直接读取。
#    禁止在文件级自定义 helper 里直接 texture(TEXTURE, ...)，否则 Godot 4.7 会报：
#       Unknown identifier in expression: 'TEXTURE'
#       Shader compilation failed.
#    自定义 helper 只做纯数学/边界计算，真正 texture(TEXTURE, ...) 采样必须留在 fragment()。
#
# 2. MotionBlurGhost 只是纯视觉副本，不能改变/反向人物朝向。原 image 可以继续使用
#    Set_RGB_Color.gdshader 的 sprite_flip_h；Ghost 自己改用 Sprite2D.flip_h 复制最终朝向，
#    不再让运动模糊 Shader 再做第二次水平镜像。
#
# 3. Ghost 和 image 同为 Graphics 直接子节点，因此同步局部 transform，而不是每帧重写 global_transform。
#    这样 CharacterAutoFit / Graphics 缩放时不会出现一帧变换差，尤其避免牛高速移动时看到
#    “向右的清晰牛 + 向左的模糊牛”叠在一起。
#
# 4. Ghost 原生 flip_h 后，纹理 U 轴会反向；只对 blur_direction 的本地 X 分量做一次反转，
#    使拖影仍始终落在真实速度的反方向，不影响人物本身朝向。
#
# 5. 为了让普通移动也能看到效果，V112 默认 motion_blur_start_speed=70、
#    motion_blur_full_speed=360、motion_blur_max_pixels=26、motion_blur_max_alpha=0.58。
#    速度更快只增强到上限，不无限拉长；低于 start_speed 时仍完全隐藏 Ghost。
#
# 6. Shader 采样使用 REGION_RECT 裁切，Sprite2D 的 region/hframes/vframes 不得采到相邻帧。
#    运动模糊仍然只影响画面，不改变 ball 位置、碰撞、Hitbox/Hurtbox、攻击判定或训练威胁几何。
# =============================================================================

# =============================================================================
# 【V113 运动模糊定义修正：连续方向模糊，不是残影】
# =============================================================================
# 1. 用户要求的 motion blur 是“当前画面沿运动方向连续发糊/拉开”，不是保存旧位置、不是多张历史人物、
#    也不是在清晰人物背后叠一个半透明 Ghost。V109~V112 的 MotionBlurGhost 表述从本条开始作废。
#
# 2. ball.gd 仍可用一个运行时 Sprite2D 作为渲染载体，但它必须叫 MotionBlurLayer，始终与当前 image
#    同位置、同当前帧，不记录上一帧位置。该层画在当前人物上方，高速时接近不透明，从视觉上覆盖清晰本体，
#    让结果真正表现为“当前这一帧被运动方向揉开”。
#
# 3. res://shaders/ball_motion_blur.gdshader 的正确实现分两步：
#    - vertex(): 只把当前图片的运动方向前缘沿真实局部速度方向向前拉宽；
#    - fragment(): 沿该轴做密集、连续的多点 texture(TEXTURE, ...) 采样，从前方像素混入身后颜色。
#    禁止使用几张大间隔采样来模拟多个离散影子。
#
# 4. 几何方向与纹理 UV 方向必须分开。Sprite2D.flip_h 只反转纹理 U，不代表实体运动方向反转；
#    因此 vertex 的 blur_direction 始终使用真实局部运动方向，只有 fragment 的 blur_uv_direction
#    在 flip_h 时反转 X。禁止再次用同一个“翻转后的方向”同时驱动 vertex 和 UV，否则牛向右跑时会往左拉。
#
# 5. 图集帧隔离是硬规则。Sprite2D 使用 hframes/vframes 时，ball.gd 必须计算当前 frame 的实际
#    frame_uv_min/frame_uv_max 并传给 Shader；region_enabled 时按 region_rect / texture_size 计算。
#    fragment 的所有采样都只能落在这一帧范围，越界样本 alpha=0。禁止靠 REGION_RECT 猜 hframes 帧界，
#    否则横向模糊可能采到相邻帧，看起来像叠出另一朝向/另一动作的人物。
#
# 6. V113 默认：motion_blur_start_speed=30、motion_blur_full_speed=260、
#    motion_blur_max_pixels=22、motion_blur_max_alpha=0.96、motion_blur_response=16。
#    普通移动开始有轻微方向模糊，高速明显，但速度再高仍封顶，不允许无限拉长。
#
# 7. 运动模糊始终是纯视觉。不得修改 CharacterBody2D、CollisionShape2D、Hitbox、Hurtbox、
#    实际攻击/受伤几何、AI Hazard 或训练调试范围。
# =============================================================================
# V113 补充：运动模糊速度来源优先使用 ball 根 global_position 的逐物理帧真实位移 / delta；
# 只有 authority 刚出生、位置差分尚未形成的第一帧才允许用 direction * Speed + Repel 兜底。
# 禁止只根据 Speed 推测运动模糊，否则冲刺、击退、自定义 move_and_collide()/特殊移动可能方向或强度错误。

# =============================================================================
# 【V114 运动模糊强度自由调节】
# =============================================================================
# 1. 运动模糊的所有主要视觉参数必须暴露在 ball Inspector 的“运动模糊”分类中，不能把关键强度写死在 Shader：
#    - motion_blur_effect_strength：总体速度强度倍率；
#    - motion_blur_start_speed / motion_blur_full_speed：开始/满强度速度；
#    - motion_blur_strength_curve：速度到模糊强度的曲线；
#    - motion_blur_max_pixels：方向模糊长度；
#    - motion_blur_max_alpha：模糊层最大覆盖透明度；
#    - motion_blur_forward_stretch：运动方向前缘几何展开倍率；
#    - motion_blur_sample_spread：方向卷积采样展开倍率；
#    - motion_blur_core_sharpness：保留清晰核心比例；
#    - motion_blur_response：强度响应速度；
#    - motion_blur_force_strength：-1 自动；0~1 强制预览/调参。
# 2. 对需要大范围自由调整的数值使用 @export_range(..., "or_greater")：滑条提供常用范围，用户仍可手动输入超过上限的值。
# 3. V114 默认比 V113 明显：effect_strength=1.8、start_speed=10、full_speed=220、max_pixels=56、
#    max_alpha=1.0、forward_stretch=1.35、sample_spread=1.55、core_sharpness=0.05、response=20。
# 4. Shader 使用 16 个连续方向采样点；它仍然只处理当前帧，不保存历史帧/历史位置，不得退回“残影”实现。
# 5. motion_blur_force_strength 仅用于预览与调参；-1 才表示正常按真实移动速度自动计算。它只改视觉，不得影响实体速度/碰撞/伤害。
# =============================================================================

# =============================================================================
# 【V115 新角色：火车长 / 列车循环 / 边缘煤矿】
# =============================================================================
# 1. 素材固定放在既有 Images 大写目录：
#      res://Images/characters/人物/火车长/
#    使用用户本轮提供的 01~09 九张 PNG；禁止另建 images/、Train/、火车/ 等同义资源目录。
#
# 2. 火车长主体：
#      res://scenes/characters/人物/火车长.tscn
#      res://scripts/characters/火车长.gd
#    本人没有普通攻击/主动技能按钮；Damage 是“列车撞击的整体基础攻击力”，默认 45。
#    必须遵守 V107：列车最终伤害 = 火车长.attack_damage(train_damage_multiplier)，
#    禁止在列车脚本里重新维护一套和 Damage 脱钩的绝对攻击力。
#
# 3. 列车：
#      res://scenes/creatures/火车长_列车.tscn
#      res://scripts/creatures/火车长_列车.gd
#    车头 + 至少 2 节车厢 + 车尾动态拼接。初战默认 3 节车厢。
#    列车实际撞击区由每一节直属 Area2D + RectangleShape2D 提供；
#    Area2D 上的 threat_debug_damage 必须写当前真实伤害，因此训练威胁调试看的是同一套几何。
#    同一目标一趟列车有短冷却，避免连续车厢在极短时间把一次“被列车撞到”错误叠成多次爆伤。
#
# 4. 列车运动方向按素材朝向使用“从右往左”。战斗真正开始后立刻发第一趟；
#    车尾也完全越过当前地图真实 world rect 左边后，才算整列车完全出图。
#    完全出图后列车在地图下方重新排队：车头停在地图左侧，对应车厢/车尾依次等待在右边。
#    地图尺寸必须读取 World.return_map_world_rect()，绝不能使用 Camera2D zoom 后的屏幕尺寸猜地图大小。
#
# 5. 加煤/发车：默认每 8 秒自动发车一次；最少 2 节车厢，每加 1 煤就让下一趟 +1 节车厢。
#    停靠阶段必须立刻按当前煤量重建等待中的车厢，让玩家直接看到列车逐节变长；加煤不能重置固定发车计时。
#    默认 5 煤会得到 7 节车厢并立即发车；达到 5 煤不等固定间隔，发车后煤量清零。
#    火车长本人为了避免触发项目统一“出界淘汰”，只走到地图底边内侧的加煤交互点；
#    列车本体可以停在 map_rect 下方。不要让人物为了加煤长期跑到 map_rect 外。
#
# 6. 煤矿：
#      res://scenes/terrain/火车长_煤矿.tscn
#      res://scripts/terrain/火车长_煤矿.gd
#    只要场上有火车长，就共享生成一圈默认 10 个边缘煤矿；多名火车长不能各自再铺一整圈。
#    煤矿是交互 Area2D，不造成伤害、不阻挡人物。每个矿挖一次后默认 4.5 秒恢复，可循环采集。
#
# 7. 挖矿视觉顺序是硬规则：
#      正常图 -> 手持矿镐前摇 -> 挖矿图 -> 单独煤块抛物线旋转飞向火车长 -> 正常图。
#    挖下去的瞬间从煤矿位置发射一组与人物受击同语言的白色 HitBurstEffect 线；
#    白线和飞行煤块都只是视觉，不注册 damage hazard。
#    持到煤后火车长自动前往底边加煤点，使用“加煤”素材停留一小段时间后才真正给列车 +1 煤。
#
# 8. 列车运动模糊复用 res://shaders/ball_motion_blur.gdshader，但列车不是 ball：
#    每节车体自己创建当前帧 MotionBlurLayer，只有列车运行时启用，停靠时关闭。
#    这是 V113/V114 定义的“沿实际运动方向连续发糊”，不是历史残影；不能保存旧车体位置。
#
# 9. 列车撞人成功后复用项目标准 balls_hit1 命中音，并调用目标通用 apply_knockback()。
#    撞击、击退、伤害、车速、发车间隔、车体尺寸、运动模糊、煤矿数量、挖矿/加煤时间均导出可调。
# =============================================================================

# =============================================================================
# 【V116 火车长继承成员重名解析修复】
# =============================================================================
# 1. res://scripts/characters/火车长.gd 继承自 ball，因此不能再次声明与父类同名的类成员。
#    V115 曾重复声明：
#       const HIT_BURST_EFFECT_SCRIPT = preload("res://scripts/effects/hit_burst_effect.gd")
#    而 classes/ball.gd 已经存在同名常量，Godot 4.7 会直接报：
#       The member "HIT_BURST_EFFECT_SCRIPT" already exists in parent class ball.
#
# 2. V116 将火车长自己的别名改为 TRAIN_HIT_BURST_EFFECT_SCRIPT，并同步修改挖矿白线特效创建处。
#    只改标识符，不改 preload 路径、不改白线效果、不改火车长玩法/数值。
#
# 3. 以后新增任何 extends ball 的角色脚本时，新增 const / var / signal / enum 前必须先检查
#    classes/ball.gd 的类级成员名。函数可以按 GDScript 继承规则正常 override，但不能通过重复声明
#    同名常量/成员变量来“覆盖”父类成员。
# =============================================================================

# =============================================================================
# 【V117 火车长列车尺寸 / 地图下方停靠 / 永久煤矿修正】
# =============================================================================
# 1. 列车视觉尺寸：
#    - res://scripts/creatures/火车长_列车.gd 的 train_visual_height 默认从 48 提高到 96；
#    - 每节车厢的真实 RectangleShape2D 继续跟随同一 visual height/ratio 重算，不能只放大图片而让伤害框留在旧尺寸；
#    - train_visual_height 仍是 Inspector 可调参数，允许继续放大。
#
# 2. 地图下方停靠是硬状态，不是“刚出图就继续滑”：
#    - 必须等车尾也完全越过 World.return_map_world_rect() 左边界 + outside_margin 后才进入 STATE_STAGED；
#    - 进入 STATE_STAGED 时 _launch_elapsed 清零；固定发车时间只从真正停靠后重新累计；
#    - 停靠位置 _station_position 每个 physics tick 强制回写，列车不能因为重建车厢或其它 transform 继续漂移；
#    - 整节车体上边缘必须位于 map_rect.end.y 之下，默认 station_gap_below_map=6；车头位于地图左下方，后续车厢/车尾向右排队；
#    - 普通固定发车默认 12 秒，并至少停靠 minimum_station_dwell=2.5 秒；但达到 maximum_coal=5 仍按原机制立即发车。
#
# 3. 煤矿数量：
#    - 火车长共享边缘煤矿默认从 10 个降为 5 个；多名火车长仍只能共享同一组，不能重复铺矿。
#
# 4. 煤矿永久存在：
#    - 采集后禁止 queue_free、隐藏、降低 alpha 或 disabled CollisionShape2D；煤矿图片必须始终保持原样存在于地图边缘；
#    - consume_mine() 只把该矿设为“暂时不可再次采集”，默认 4.5 秒后重新可采；冷却是逻辑状态，不是矿体消失/枯竭状态；
#    - 煤矿 Area2D 仍只负责火车长采矿交互，不造成伤害、不阻挡普通角色。
#
# 5. V117 覆盖 V115 中“默认 10 个煤矿、采后视觉枯竭/再生、旧列车尺寸/旧发车默认”的数值说明；
#    V115/V116 其余火车长机制继续保留。
# =============================================================================

# =============================================================================
# 【V118 火车长停靠可见性 / 煤矿嵌墙修正】
# =============================================================================
# 1. V117 把列车中心直接放到 map_rect.end.y + 半车高以后，虽然逻辑上确实“在地图下方”，
#    但 World 的 MapOutsideVisualMask(z=90) 会遮住地图外 CanvasItem；同时 Camera2D 当前可见范围
#    也未必给地图底边之外留下一个完整车高，所以玩家可能完全看不到停靠列车。
#
# 2. V118 停靠规则：
#    - 列车运行时保持 z_index=9；进入 STATE_STAGED 后改为 z_index=95，压在 MapOutsideVisualMask(z=90) 上面，
#      但仍低于地图黑色边框 MapBorderSegments(z=100)；
#    - 理想站台仍是“地图正下方、车头在左、车厢/车尾向右”；
#    - 用 Viewport.get_visible_rect() + viewport.get_canvas_transform().affine_inverse() 求当前 Camera2D 下真正可见的 world rect；
#    - 如果当前屏幕底边能容纳整节车，就停在地图外下方；如果容纳不下，则只把 Y 夹到地图底边内侧，
#      保证等待列车一定可见，不能再为了字面上的“地图外”把整列车藏到屏幕之外；
#    - STATE_STAGED 仍每 physics tick 回写同一 _station_position，停靠时 collision/伤害与运动模糊全部关闭。
#
# 3. 煤矿“在墙里”与“墙内”必须区分：
#    - V117 的矿心使用 rect.position + inset / rect.end - inset，实际把整座矿摆进了可玩区域（墙内）；
#    - V118 保留 mine_edge_inset 旧变量名以兼容已有 Inspector/场景值，但语义改为“向边界外侧嵌入深度”，
#      四边矿心分别放到 left-inset / right+inset / top-inset / bottom+inset；
#    - 默认嵌入深度 14px，让矿体大部分处在墙/地图外侧，仅小部分伸入可玩区域；
#    - 煤矿视觉 z_index 继续低于 MapOutsideVisualMask，因此墙外的大部分会被遮住，黑色边框(z=100)压在最上层，
#      视觉上就是“矿体埋进墙里”，而不是一整块煤矿摆在墙内；
#    - mine_reach_distance 默认提高到 48，保证矿心在墙外时火车长仍能在地图内侧正常触发挖矿。
#
# 4. V118 不改变：煤矿永久存在/4.5秒逻辑冷却、默认5个共享矿、列车96高度、12秒普通发车、5煤立即发车、
#    火车真实 Area2D/CollisionShape2D 撞击、V107 Damage 攻击力规则与列车方向性运动模糊。
# =============================================================================

# =============================================================================
# 【V119 火车长煤矿随机外观 / 列车减速进站修正】
# =============================================================================
# 1. 煤矿外观变化：
#    - 墙内/嵌墙煤矿仍使用同一张 `08_煤矿矿体.png`，但每一块允许 360° 任意旋转；
#    - 每块矿允许小幅统一缩放，默认 0.90x ~ 1.10x；不得做夸张尺寸差异，避免交互距离和视觉提示失真；
#    - 使用 `RandomNumberGenerator` + 固定 seed（矿编号）生成变化，同编号在联机/回放中必须可复现，禁止客户端各自 randomize；
#    - 煤矿仍永久存在，采集只进入逻辑冷却，不隐藏、不删除。
#
# 2. 列车完全离开左侧后的回站流程：
#    - 禁止直接把列车瞬移到最终停靠点让它“突然出现”；
#    - 整列车（含车尾）完全出图后，可以在玩家看不到的区域重定位到“地图下方右侧、当前可见 world rect 右边界之外”的进站起点；
#    - 然后进入 `STATE_ARRIVING`，沿地图下方从右向左真实移动到站台；
#    - 进入 `station_brake_distance` 后按剩余距离连续减速，直到车头精确停在左侧站位；运动模糊强度跟随实际进站速度同步减弱；
#    - 只有真正停稳进入 `STATE_STAGED` 后，12 秒普通发车计时和加煤等待状态才开始。
#
# 3. V119 停靠高度：
#    - `station_gap_below_map` 的语义改为“列车中心比地图底边低多少像素”，不再是“整节车体上沿与地图底边的空隙”；
#    - 默认 8px，因此 96px 高的列车会紧贴地图下沿并部分压在地图边缘附近，不再整节车体远离地图；
#    - 仍受当前 Camera2D 可见 world rect 夹紧保护，不能因为停靠点在屏幕外导致完全不可见。
#
# 4. 可调进站参数：`station_approach_speed`、`station_min_approach_speed`、`station_brake_distance`、`station_entry_margin`；
#    调整这些值只能改变进站速度曲线/起点，不得重新引入最终站位瞬移。
# =============================================================================

# =============================================================================
# 【V120 火车长恢复正常移动 / 交互只由真实碰撞触发】
# =============================================================================
# 1. 火车长本人平时必须完全使用 ball 的普通移动/状态机逻辑：
#    - 禁止为了煤矿主动改写 direction 去寻路；
#    - 持有煤块时也禁止主动改写 direction 去追列车/加煤点；
#    - 除挖矿/加煤动作正在播放的短暂锁定外，tick_physics() 应直接交回 super.tick_physics(state,delta)。
#
# 2. 煤矿交互只由真实 Area2D 碰撞触发：
#    - res://scripts/terrain/火车长_煤矿.gd 的 Area2D.body_entered 检测火车长；
#    - 只有真正进入煤矿 CollisionShape2D 时才调用 notify_coal_mine_contact() 并开始“举镐 -> 挖矿”；
#    - mine_reach_distance 旧导出字段只为兼容旧场景/Inspector 保存值，V120 起不得再作为自动接近或距离触发条件。
#
# 3. 加煤同样只由真实碰撞触发：
#    - 停稳的列车车头上方创建 RefuelArea（Area2D + RectangleShape2D），只在 STATE_STAGED 时 monitoring=true；
#    - 火车长必须持煤并真实进入/重叠 RefuelArea，才调用 notify_train_refuel_contact() -> _begin_refuel()；
#    - 列车运行/进站时 RefuelArea 必须关闭，不能在攻击列车经过时误触发加煤；
#    - refuel_reach_distance 与 get_refuel_target_position() 不再作为自动导航/距离触发入口。
#
# 4. V120 明确覆盖 V115 的“持煤后自动前往底边加煤点”以及 V118 的 mine_reach_distance 主动接近语义。
#    V115~V119 的火车编组、撞击伤害、煤矿永久存在、随机旋转/缩放、减速进站、5煤立即发车等其它机制保持不变。
# =============================================================================

# =============================================================================
# 【V121 火车长音效接入 / 列车运动模糊低速退场与平滑过渡】
# =============================================================================
# 1. 用户提供的 4 个原始 MP3 正式放入：
#    res://audio/characters/火车长/喷气.mp3
#    res://audio/characters/火车长/火车运行.mp3
#    res://audio/characters/火车长/挖矿_[cut_0sec] (1).mp3
#    res://audio/characters/火车长/加煤.mp3
#    保持原文件名，不创建 Audio/Voices 等同义目录。
#
# 2. 列车音频时序：
#    - 每次 _launch_with_carriages() 发车时，喷气.mp3 只播放一次，表示蒸汽/喷气启动；
#    - 火车运行.mp3 使用独立 AudioStreamPlayer2D，并复制 AudioStreamMP3 后 runtime loop=true；
#      STATE_RUNNING 和 STATE_ARRIVING 只要列车仍在运动就持续循环，真正进入 STATE_STAGED 停稳后立即 stop；
#    - 运行循环不得依赖 finished 信号，因为 loop=true 的 MP3 不会在每轮末尾发 finished。
#
# 3. 火车长动作音效：
#    - 挖矿音必须在“举镐前摇结束、切到挖矿图片/真正落镐”的时刻播放，不能在刚碰矿时提前播放；
#    - 加煤音必须在进入加煤动作、切到加煤图片时播放；
#    - 动作音频使用独立一次性 AudioStreamPlayer2D，finished 后 queue_free，防止一个共享播放器把并发动作互相截断；
#    - 火车/角色动态播放器显式走 GameplayRecord 总线，继续符合 global/audios.gd 的录像声音规则。
#
# 4. 列车方向性运动模糊不再使用 speed/540 的瞬时硬映射：
#    - train_motion_blur_start_speed：低于该速度目标强度必须为 0（默认 125），解决“已经很慢仍然挂着模糊”；
#    - train_motion_blur_full_speed：达到该速度才是 1.0 满强度（默认 500）；
#    - train_motion_blur_strength_curve：控制 start~full 中间曲线；
#    - train_motion_blur_response：用指数平滑追随目标强度，默认 9；禁止直接一帧切换可见/不可见造成生硬过渡；
#    - STATE_ARRIVING 必须每物理帧把真实 _arrival_speed 喂给模糊目标；列车越接近站台、速度越低，模糊连续变弱；
#    - 低于 start_speed 后目标立即为 0，但当前视觉强度按 response 连续淡出；足够接近 0 后才隐藏 MotionBlurLayer。
#
# 5. 本轮只改音频与视觉反馈，不改变火车伤害、击退、车厢数量、煤矿、加煤触发、发车计时、进站轨迹。
# =============================================================================


# =============================================================================
# 【V122 火车长列车撞击频率 / 出现高度 / 永远置顶 / 再次发车真实离站】
# =============================================================================
# 1. 火车撞击命中声：
#    - 每次列车真实 Area2D/CollisionShape2D 对合法目标结算出生命伤害或格挡损失后，
#      必须播放项目标准碰撞伤害音 `balls_hit1`；不得只播火车运行声而没有命中反馈。
#    - 使用独立 playback voice（Audios.play_sfx(..., create_new_audio=true)）以允许高频连续命中声叠加，
#      不得因为前一声仍在播放就截断本次撞击声。
#    - `train_hit_audio_volume_db` 允许单独调列车命中声响度。
#
# 2. 火车攻击频率：
#    - `same_target_hit_cooldown` 是同一个目标再次被同一列火车伤害的硬冷却；V122 默认 0.18 秒，
#      明显快于 V121 的 0.42 秒。所有车头/车厢/车尾共享这个目标冷却，避免同一帧多节叠加爆伤。
#
# 3. 每次攻击列车从地图右侧重新出现时，Y 轴必须读取火车长“当时”的 `global_position.y`；
#    禁止再使用 28% / 50% / 72% 固定三车道轮换。火车长后来移动到哪里，下一趟列车就从同一 Y 高度进入。
#
# 4. 列车绘制层级是硬规则：
#    - 根节点 `z_as_relative=false`，统一 `z_index=120`；
#    - World 的 MapOutsideVisualMask 当前为 z=90，地图黑色边框为 z=100，因此列车必须始终压在两者上方；
#    - STATE_RUNNING / ARRIVING / STAGED / DEPARTING 全部使用同一个高 Z，禁止再出现运行时 z=9、停靠时 z=95
#      导致“有时被地图遮挡、有时不被遮挡”的状态差异。
#
# 5. 再次发车不得原地消失：
#    - 开局第一次列车仍可直接从地图右侧进入，因为此时还没有停靠列车；
#    - 后续从 STATE_STAGED 再次发车时必须先进入 STATE_DEPARTING；
#    - 停靠列车从当前站位由 0 速度开始，按 `station_departure_acceleration` 连续加速向左移动；
#    - 离站阶段关闭列车伤害区和加煤区，只保留列车视觉、启动音、运行循环音和按真实速度变化的运动模糊；
#    - 必须等“最后一个车尾也完全越过当前可见屏幕左边界 + outside_margin”之后，才允许在不可见处切到地图右侧；
#    - 切到右侧后才进入 STATE_RUNNING，并在那一刻重新读取火车长当前 Y；这一切发生在屏幕外，因此不能被玩家看到瞬移。
#
# 6. V122 不改变：Damage/攻击倍率、列车基础伤害、击退、车厢数量随煤变化、5煤立即触发发车、
#    进站减速、停靠高度、煤矿/挖矿/加煤交互以及 V121 音频时序。
# =============================================================================

# =============================================================================
# 【V123 火车长煤矿暴露 / 小加煤区 / 30秒煤加速发车 / 移动挖矿震波】
# =============================================================================
# 1. 煤矿嵌墙深度：
#    - `mine_edge_inset` 默认从 14px 降到 8px；仍然是“矿心在地图边界外侧”，不是把矿摆回可玩区域；
#    - 配合煤矿 0.90x~1.10x 随机缩放/任意旋转时，默认必须稳定露出足够可辨识面积，禁止出现只漏一两个像素的极深埋矿；
#    - 煤矿真实交互 CircleShape2D 本轮不扩大，维持原来约 22px 半径，因为用户确认煤矿判定基本合适。
#
# 2. 列车加煤互动框：
#    - `RefuelArea` 仍是停靠车头上的真实 Area2D + RectangleShape2D，只在 STATE_STAGED 启用；
#    - V123 默认交互框缩到约 42x26px，位置贴近车头上缘；不得再按整节 96px 高车体的 0.86/0.62 比例放大；
#    - 角色必须真的贴近车头才能开始加煤，不能隔很远触发。列车“撞击伤害框”与“加煤互动框”是两个独立几何，禁止混用。
#
# 3. 自动发车时间与煤：
#    - `launch_interval = 30s` 是 0 煤时的基础停靠等待；
#    - 每填入 1 个煤，当前这一趟的目标等待时间减少 `coal_launch_time_reduction = 4s`；
#    - 目标等待 = max(minimum_station_dwell, 30 - coal_count * 4)；煤在等待途中加入时应立即缩短同一趟剩余等待；
#    - V123 起 5 煤不再强制“立即发车”。默认 5 煤时目标等待为 10 秒；
#    - 0 煤普通发车只有 1 节车厢；每煤 +1 节。开局第一次列车同样遵守 0 煤 = 1 节，`initial_carriage_count` 默认改为1。
#
# 4. 煤矿永久重复开采：
#    - 煤矿不删除、不隐藏、不进入 4.5 秒不可采冷却；同一个矿可以重复挖；
#    - `claim_mine()` 只用于避免多个火车长同时占用同一矿，`consume_mine()` 只表示一次挖击成功，不改变矿的可用性；
#    - 煤矿必须连接 body_entered + body_exited：进入才开始挖，离开真实 Area 必须立即停止当前挖矿序列并释放 claim。
#
# 5. 挖矿期间移动与随机挖击：
#    - 火车长挖矿时不得把 direction 清零；继续走 ball 的正常移动/碰撞/状态机，只在 `move()` 中乘 `mining_move_speed_multiplier`（默认0.28）；
#    - 每批随机 2~4 下（Inspector 可调），举镐前摇 -> 落镐 -> 短间隔重复；只要还在矿区且携煤未满，可以继续下一批；
#    - 人物自己正常走出煤矿 Area 后立即停止挖矿并恢复正常图片/速度；重新进入同一煤矿可以再次挖；
#    - 每次有效落镐生成一个小煤块抛物线视觉，并把携煤 +1，默认最多携带5煤；在加煤区可按现有逐次加煤流程把煤送入列车。
#
# 6. 挖矿震波：
#    - 每次真正落镐都在矿点生成一个小范围白色描边圆，从小到大扩散并渐隐；视觉只是视觉；
#    - 真实伤害使用独立 `CircleShape2D` + `PhysicsDirectSpaceState2D.intersect_shape()` 查询，默认半径46px；禁止按 Line2D 圆圈像素猜伤害区；
#    - 基础伤害 = `Damage * mining_shockwave_damage_multiplier`，默认倍率0.65，因此必须低于列车默认 `Damage * 1.0`；
#    - 每个落镐震波只结算一次，并附带小幅击退（默认18距离/165速度）；继续遵守友伤、目标可攻击资格和 V107 整体攻击力规则。
# =============================================================================

# =============================================================================
# 【V124 火车长挖矿白线 / 煤矿弹性 / 加煤抛物线与列车弹性反馈】
# =============================================================================
# 1. 挖矿白线必须清楚且是 360° 多方向爆射：
#    - 禁止再以“矿点远离火车长”的单一 outward 方向只做一个扇形；每次落镐应围绕矿点完整 360° 分布多条白线；
#    - 默认 14 条，允许角度/长度/宽度小幅随机，但随机 seed 必须由 authority 生成/传递，联机端看到同一组方向；
#    - 线默认比 V123 更粗、更长、更亮，并把 HitBurstEffect 的 z_index 提到 122；煤矿在地图墙边，若继续用通用受击特效默认 z=46，
#      会被 MapOutsideVisualMask(z=90) 吃掉大部分视觉，导致“明明生成了但不明显”。
#    - 白线仍然只是视觉；真实挖矿震波伤害继续由 V123 的 CircleShape2D + intersect_shape() 负责。
#
# 2. 每次真正落镐时煤矿本体必须“弹一下”：
#    - 只 Tween `火车长_煤矿.gd` 的 Sprite2D.position/scale，做短促位移 + squash + BACK 回弹；
#    - 禁止移动煤矿 Area2D 根节点或 CollisionShape2D，否则真实采矿进入/退出范围会跟着视觉抖动；
#    - 连续挖击若上一次 Tween 尚未结束，先 kill 旧 Tween 并从保存的 base position/scale 重新开始，避免累计漂移/缩放。
#
# 3. 加煤必须有“煤块从火车长飞入车头”的过程：
#    - 进入 RefuelArea 后仍切换加煤图片/播放加煤音，但不能再只等待 refuel_duration 后直接 coal_count +1；
#    - 先做短前摇，再使用 09_单独煤块.png 从火车长当前位置旋转抛物线飞向列车真实 RefuelArea；
#    - 煤块飞行结束后才扣除 `_held_coal` 并调用列车 add_coal()，即视觉抵达和逻辑加煤时刻一致；
#    - 加煤煤块是视觉，不创建新的交互/伤害碰撞体。
#
# 4. 每个煤块真正加入停靠列车后，列车必须“弹一下”：
#    - `火车长_列车.gd::add_coal()` 在 STATE_STAGED 重建预览编组后播放一次短促上弹/挤压/回弹；
#    - 只 Tween 每节车体的 Visual / MotionBlurLayer，禁止 Tween 列车根 Node2D、TrainPart Area2D、撞击 CollisionShape2D 或 RefuelArea；
#    - 可给后续车厢极短 part delay 形成轻微传递感，但总间隔必须很短，不能像逐节播放的长动画。
#
# 5. 可调参数：
#    - 火车长：mining_white_line_count / distance_min/max / width_min/max / duration；
#      refuel_coal_fly_time / refuel_coal_arc_height / refuel_coal_visual_size。
#    - 煤矿：mining_bounce_distance / mining_bounce_squash / mining_bounce_out_time / mining_bounce_return_time。
#    - 列车：refuel_bounce_height / refuel_bounce_squash / refuel_bounce_out_time / refuel_bounce_return_time / refuel_bounce_part_delay。
# =============================================================================


# =============================================================================
# 【V125 火车长列车运行声随减速淡出 / 挖矿白线恢复人物受击式定向爆射】
# =============================================================================
# 1. 列车运行循环音不得在停车瞬间硬切：
#    - `train_run_volume_db` 仍表示高速运行时的最大基础响度；
#    - `train_run_audio_silent_speed`：低于该真实列车速度时目标音量为 0（默认24）；
#    - `train_run_audio_full_speed`：达到该速度后运行声达到完整 train_run_volume_db（默认260）；
#    - `train_run_audio_fade_curve` 控制中间速度到音量的曲线，`train_run_audio_fade_response` 控制追随速度变化的平滑程度；
#    - 每物理帧必须把 STATE_RUNNING / ARRIVING / DEPARTING 的实际列车速度送入音频目标；
#    - STATE_ARRIVING 减速时运行声必须随着速度连续变小；进入 STATE_STAGED 时只把目标速度设为0，
#      等线性音量平滑接近 `train_run_audio_silence_db` 后才真正 stop()，禁止在 `_finish_station_approach()` 直接停止；
#    - 音量插值优先使用 `AudioStreamPlayer2D.volume_linear`，不要对 dB 做简单线性 lerp，避免听感突兀。
#
# 2. 挖矿“白线”和 V123 的白色描边震波是两个不同视觉：
#    - 白色描边震波继续保留，它对应真实 CircleShape2D 的挖矿范围伤害视觉；
#    - “挖矿白线”必须改回与人物受击 `HitBurstEffect` 相同的定向爆射语义，禁止再做 V124 的 360° 一圈放射线。
#
# 3. 挖矿白线方向硬规则：
#    - 主方向 = `煤矿命中点 - 火车长落镐时的位置`，也就是镐从火车长朝矿点打过去的真实来源/受力方向；
#    - 白线从煤矿命中点生成，并沿上述方向继续射出；只允许在主轴附近做有限角度随机扩散；
#    - 默认约8条、±22°扩散，保持人物受击白线那种“细、短延迟、先长出再飞离并渐隐”的动画；
#    - authority 必须把落镐来源位置 + feedback seed 一起同步，远端客户端不得根据本地角色位置重新猜方向；
#    - 白线仍只负责视觉，真实挖矿震波伤害/击退继续由 V123 的 CircleShape2D + intersect_shape() 结算。
#
# 4. V125 明确覆盖 V124 第1条“360°多方向爆射”的白线规则；V124 的煤矿弹一下、
#    加煤煤块抛物线、列车加煤弹性，以及 V123 的白色描边震波和真实震波伤害全部继续保留。
# =============================================================================

# =============================================================================
# 【V126 多人联机 UI / ENet 连接诊断 / 联机入口规则】
# =============================================================================
# 1. 多人 UI 的输入框节点历史名字仍为 `Port`，但它从来实际传给 `Game.join_game(address)`：
#    - V126 起界面必须明确显示“服务器 IP / 地址”，禁止再写“端口”误导玩家；
#    - 游戏端口固定 `Game.port = 27018`，界面只展示该端口，不把同一个输入框同时当 IP 与端口；
#    - 空地址仅用于本机双开测试，默认解析为 127.0.0.1。
#
# 2. 多人面板竖屏布局硬规则：
#    - `MultiPlayer/Player_list` 不得再挂在多人面板右侧；旧版横向总宽超过 360 本地像素，720 竖屏必然出界；
#    - 玩家列表固定居中放在连接区下方，整个多人窗口本地宽度保持约 258px，继续随根 UI 使用 1x/2x/3x 整数缩放；
#    - 玩家列表不再调用 `Game.Set_Ui_drager()`，禁止用户把它拖到屏幕外；
#    - 改分辨率/旋转屏幕时 `apply_portrait_layout()` 必须再次调用 `_layout_multiplayer_panel()`。
#
# 3. ENet 初始化与断开：
#    - 主机使用 `ENetMultiplayerPeer.create_server(27018, max_player)`；客户端使用
#      `create_client(server_address, 27018)`，并把成功创建的 peer 赋给 `multiplayer.multiplayer_peer`；
#    - `create_server/create_client` 的 Error 返回值必须检查，禁止忽略失败后仍把 UI 当成已连接；
#    - 创建新主机/客户端前先切到 `OfflineMultiplayerPeer` 清理旧连接，避免重复点击导致 ERR_ALREADY_IN_USE；
#    - 必须监听 `connected_to_server / connection_failed / server_disconnected / peer_connected / peer_disconnected`。
#
# 4. V126 联机自检不是只看“ENet 显示 Connected”：
#    - 客户端连接成功后每约 2 秒向 Server ID 1 发送可靠 `_network_ping_request`；
#    - 服务器读取 `multiplayer.get_remote_sender_id()` 并用 `_network_ping_reply.rpc_id(sender)` 回包；
#    - 客户端收到对应 token 后才把 `network_rpc_verified=true`，UI 显示“双向 RPC 正常 + RTT(ms)”；
#    - 这条往返同时验证“客户端 -> 服务器 RPC”和“服务器 -> 客户端 RPC”路径，不能用本地函数调用冒充联机成功。
#
# 5. 当前项目角色同步链（V126 静态审计确认，后续不得随意拆掉）：
#    - `res://scenes/world.tscn` 的 MultiplayerSpawner `spawn_path = ".."` 指向 World；
#    - `res://scripts/world.gd` 启动时遍历 `res://scenes/` 并 `add_spawnable_scene()`，authority 在 World 直接 add_child 的白名单场景
#      会由 MultiplayerSpawner 自动复制给远端；
#    - 客户端放置人物不在本地直接生成，而是 `create_ball_in_server.rpc_id(1, ...)` 请求服务器创建；
#    - `res://scenes/ball.tscn` 的 MultiplayerSynchronizer 持续同步 `global_position`、Team、Type、主要视觉和血条等字段；
#    - 服务器 ID 固定为 1，普通战斗逻辑继续以服务器 authority 为准。
#
# 6. 地址显示与实际连接：
#    - 同局域网优先显示 `IP.get_local_addresses()` 中的私网 IPv4；公网 IP 的 HTTP 查询只是提示，不得成为创建/加入房间的前置条件；
#    - ENet 高层多人使用 UDP。跨公网时主机路由器需转发 UDP 27018；只转发 TCP 无效；
#    - 如果主机处于 CGNAT/运营商级 NAT，单纯填写公网 IP 通常仍无法被外网主动连接，需要可入站公网地址、VPN/虚拟局域网或中继方案。
#
# 7. V126 环境限制：当前维护环境没有 Godot 4.7.2 可执行文件，也没有用户完整 project.godot，
#    因此只能完成 GDScript/场景/Spawner/Synchronizer/RPC 的静态审计与诊断代码接入；
#    “两台真实设备已成功收发数据包”必须由用户本机用两个实例或两台设备实际验证，禁止在没有运行测试时声称已经实机联机通过。
# =============================================================================

# =============================================================================
# 【V127 多人房间发现 / 局域网与虚拟局域网房间列表】
# =============================================================================
# 1. “房间发现”与真正的 ENet 游戏连接必须分端口：
#    - 游戏仍固定使用 UDP 27018（ENetMultiplayerPeer）；
#    - 房间发现固定使用 UDP 27019（PacketPeerUDP），禁止尝试与 ENet 共用 27018，否则会发生端口占用冲突。
#
# 2. 房间发现只用于少量朋友处在同一真实 LAN / EasyTier / 蒲公英等虚拟 LAN 时找到正在开房的主机：
#    - 未连接时，多人面板下半区显示“找到的房间”；点击房间按钮会把该地址写入服务器地址并直接 join_game(address)；
#    - 连接成功后，同一区域切回当前房间的玩家列表，不再同时堆两套列表把竖屏 UI 撑出屏幕。
#
# 3. 发现协议必须是无对象反序列化的 JSON 文本，magic=`POLO_BALLS_ROOM_DISCOVERY`、protocol=1：
#    - 浏览端从临时 UDP 端口发送 discover；
#    - 主机只在 network_role == "host" 时监听 27019，并直接回复请求包真实来源 IP/端口；
#    - 浏览端以 UDP 包真实 sender IP 作为可加入地址，禁止相信数据包内部自己声称的 IP；
#    - 房间 6 秒收不到新回复就从列表过期删除。
#
# 4. 普通 LAN 使用 255.255.255.255 + 当前 IPv4 的 /24 定向广播；EasyTier / 虚拟网额外有 fallback：
#    - EasyTier 默认 DHCP 是 10.126.126.0/24，本项目发现器会对本机存在的 10.126.126.x 网卡做 /24 单播探测；
#    - 若系统网卡名称/friendly 能识别 EasyTier / Oray / Pgy / 蒲公英，也对该虚拟网卡所在 /24 做单播探测；
#    - 因此 EasyTier 即使没有开启 UDP broadcast relay，也能在默认网段通过单播发现房间；若使用自定义网段且无法识别网卡，优先开启 EasyTier 的 UDP broadcast relay / WinIPBroadcast。
#
# 5. 找房只是“发现入口”，不能替代 V126 的真实连接诊断：点击房间后仍必须走 ENet create_client(address,27018)，
#    并继续以“双向 RPC 正常 + RTT”作为 RPC 链真正可用的验证。能看到房间但进不去时，应检查 UDP 27018；
#    完全搜不到时，应检查 UDP 27019、Windows 防火墙以及虚拟组网的广播/互通设置。
#
# 6. 房间条目只公开最少信息：真实来源 IP、游戏端口、当前玩家数/上限和扫描 RTT；不广播电脑用户名、主机名、文件路径等隐私字段。
# =============================================================================

# ========================================================
# V128 多人房客权限 / C 键直接控制角色
# ========================================================
# 1. Game_Settings.Guest_Free_Permissions 是房间共享玩法设置，默认 false。
#    - 房主 / 单机永远拥有完整管理权限。
#    - 房客且该项关闭：只能选择已有队伍、选择角色、放置角色、打开“队伍/多人”；
#      禁止删除角色、重置、地图管理、创建/删除队伍、打开/修改游戏设置。
#    - 开启后房客可以修改共享玩法设置；修改请求必须先到 Server #1 验证，再由服务器广播结果。
#      不允许房客在该项关闭时靠 RPC 自行提权。
# 2. C 键控制：鼠标指向一个普通 Ball 后按 C 请求控制；再次按 C 解除。
#    同一个角色同一时间最多归一个 peer 控制。客户端只发送输入意图，服务器仍是玩法 authority。
# 3. 控制期间：
#    - WASD = 移动。ball.move() 最终优先使用 player_control_direction，AI 自己仍可计算 direction，
#      这样解除控制后无需重建 AI 状态。
#    - 左键 = 普通攻击；右键 = Skill；中键 = controlled_middle_action()（角色有专用钩子时）
#      否则优先尝试 Skill，再尝试 Attack。动作仍尊重原冷却、眩晕、禁攻和死亡规则。
#    - 禁止左键放置、右键删除和中键拖动地图；鼠标位于真实 UI 控件上时仍允许操作 UI。
#    - 被本机控制的角色脚下显示黄色描边圆；该圆纯视觉，不参与碰撞/伤害/AI。
# 4. Game_Settings.Follow_Controlled_Character 默认 false。
#    开启且本机正在控制角色时，Camera2D 强制以该角色为中心，忽略 Camera_Move 与 mouse_offset；
#    仍允许 Alt+滚轮使用现有 toolbar zoom。控制期间中键平移始终禁用。
# 5. 多人控制输入：客户端 -> Server 使用高频 unreliable_ordered 方向 RPC；攻击/技能/控制申请使用 reliable RPC。
#    服务器必须验证 sender_id 确实拥有目标角色的控制权后才应用输入，不能信任客户端直接上报位置。
# 6. V128 管理型操作补充：受限房客的删除 RPC 在服务器再次校验权限；Reset/地图切换在自由权限开启时
#    也必须先请求 Server #1，由服务器执行/广播，不能让某个客户端只改自己的本地 World 造成不同步。

# ========================================================
# V129 直接控制修正 / 控制圈地面化 / 全角色基础移速 0.6x
# ========================================================
# 1. C 键直接控制角色时，AI 不再因为 Attack_Cooling / Skill_Cooling 到点自动进入 Attack / Skill：
#    - 左键只触发普通攻击；右键只触发 Skill；中键保留角色专用 controlled_middle_action()，无专用钩子时才 Skill -> Attack 兜底；
#    - 已经由玩家点击启动的 Attack / Skill 仍允许完整执行；冷却、眩晕、禁攻、死亡和服务器 authority 规则继续保留；
#    - 决斗者、服务员、科学家原本有不完全经过 ball.get_next_state() 的自定义自动攻击分支，控制期间必须显式交回 ball 的手动控制分支；
#    - 不能通过永久把 Can_Attack / Can_Skill 改成 false 来禁止 AI，否则玩家点击也会一起失效。
# 2. 被本机控制的角色脚下黄圈改为真正“地面描边”：
#    - 只允许黄色细描边，不填充；Line2D 保持 scale=1，圆周点直接按目标半径生成，禁止再用 scale 放大单位圆导致线宽同步放大；
#    - 控制圈使用普通 World CanvasItem，z_index = -1，不使用高层 HUD/CanvasLayer，因此角色贴图可以遮住圈的经过部分，呈现角色站在圈上的空间感；
#    - 黄圈仍然纯视觉，不参与碰撞、伤害、AI、网络 authority。
# 3. 所有 Type == Ball 的普通角色基础移动统一为原来的 0.60 倍：
#    - 在 ball.move() 的最终实际位移速度层统一乘 CHARACTER_BASE_MOVE_SPEED_MULTIPLIER = 0.60；
#    - Shooter / Creature 不受该“角色基础移速”调整；击退 Repel 与 crowd separation 不额外乘 0.60；
#    - 不直接改写 Speed 属性和 default_properties["Speed"]，避免破坏牛系冲撞伤害、技能阈值等读取 Speed 的既有机制语义；
#    - 角色原有 Buff / Debuff / 冲刺等若最终仍走 ball.move()，其实际角色位移会在原结果基础上统一按 0.60 倍执行。
# ========================================================


# ========================================================
# V130 直接控制全角色自由瞄准 / 火车长烟囱烟雾
# ========================================================
# 1. 直接控制输入从 V129 的“WASD + 按键编号”升级为“WASD + 鼠标世界坐标 + 按键编号”：
#    - Game 每个物理帧把当前战场鼠标 world position 与 WASD 一起用 unreliable_ordered 发给 Server；
#    - 左/右/中键的 reliable 动作请求也必须携带点击当刻的鼠标 world position，服务器先更新 aim 再触发动作；
#    - 客户端仍只上报输入意图，不允许上报/强制角色世界位置，V126~V128 authority 安全规则继续保留。
# 2. ball 新增 player_control_aim_position / player_control_aim_valid 与统一 helper：
#    - 控制状态下 combat_target_position() 一律优先返回玩家鼠标点，combat_target_velocity() 返回 0，禁止旧锁敌/预判把攻击重新吸回 Nearest_Enemy；
#    - player_control_direction 仍只负责 WASD；鼠标瞄准与移动完全分离；点击出招前会把 direction 对齐鼠标，供仍使用 direction 的旧角色兼容。
# 3. “自由操控”硬规则：
#    - 有敌人时也必须允许朝任意鼠标方向攻击，不能因为 Nearest_Enemy 存在就强制瞄准；
#    - 没有敌人时，方向型攻击仍应允许向空地发动；需要目标才能结算的特殊效果可以没有目标效果，但不得因为“没有敌人”阻止方向型动作本身；
#    - 本轮显式补齐愤怒的普通人、矿工、猎人、决斗者、保安、科学家、拳击手、战斧重骑兵、键盘侠、凑企鹅、醉汉、小刀猎、蛇咬相生猎等旧脚本中的目标门槛/重新锁敌路径；
#    - 其它通过 combat_target_position()/direction 的角色自动继承统一鼠标瞄准。
# 4. 火车长列车烟囱：
#    - 直接复用 res://Images/characters/人物/炮兵/烟雾.png，禁止复制成新烟雾素材或新建同义图片目录；
#    - 车头烟囱持续生成 Sprite2D 烟团，烟团脱离列车根节点在世界中向上并向车尾方向漂移、放大、渐隐，因此列车高速移动时会自然留下烟迹；
#    - 烟雾纯视觉，不参与列车撞击、RefuelArea、煤、伤害、AI 或网络 authority。
# ========================================================

# V130 补充：全角色手动方向审计
# 1. set_player_control_aim_position() 同步更新 legacy direction；WASD 仍只走 player_control_direction，因此老角色不会因兼容而丢失自由移动。
# 2. continue_attack() 型角色也必须手动瞄准：背刺者、背刺鼠、夺舍狼、收债人、蜂群术士均允许无敌人朝鼠标方向发射/生成攻击，手动投射物不再绑定 AI Target_Enemy。
# 3. 拳击手直接控制时左键改为真正的固定拳路手动出拳，可向空地出拳并按真实拳路命中敌人；AI 的“身体接触触发拳击”机制不变。
# 4. 殷红迷雾直接控制时左键不再要求敌人：按鼠标方向量化到原有八方向，生成原有真实攻击体积；AI 处决/尸横遍野的自动选靶仅保留在非控制模式。
# 5. 伞夫直接控制时跳过 AI 可达目标扫描，技能袋顺序仍保留；攻击1/2真实 Area、攻击3冲刺与抓取均可按鼠标 360° 起手，没有敌人也可出招。
# 6. 时光客等使用公共 combat_target_position() 的角色自动继承鼠标世界坐标；手动投射物不保留 AI 目标锁定。
# 7. V130 最终全角色操控补充：
#    - 鼠标位置同步只更新 player_control_aim_position，不再每物理帧覆盖 legacy direction；
#      direction 继续允许 AI/真实碰撞维护，只有玩家点击出招时才把“本次起手方向”对齐鼠标，避免瞄准方向污染 WASD/反弹方向。
#    - player_control_action() 新增 controlled_attack_action()/controlled_skill_action() 特殊入口；
#      这是给 Can_Attack/Can_Skill=false、但自身维护攻击循环的角色使用，普通角色仍走 State.Attack/State.Skill。
#    - 背刺者、背刺鼠、夺舍狼、收债人原本会在 tick_physics() 自己把 Attacking 开/关；直接控制时这些自动开火条件全部暂停，
#      左键明确开启一次手动攻击窗口，方向使用鼠标；蜂群术士手动左键不再要求场上存在 enemy。
#    - 赌徒：操控时自动轮盘攻击循环暂停；左键对鼠标方向扣当前膛室，右键对自己扣当前膛室，转轮/实弹/空膛仍复用原机制。
#    - 锻刀师：锻造流程仍是角色被动阶段机制；刀完成进入 BLADE_READY 后不再自动找敌挥刀，左键按鼠标任意角度挥现有真实刀刃 Area。
#    - 战争女神：操控时自动法阵与自动普攻定时器不再自行起手；左键按鼠标方向普攻，右键手动施放原法阵。
#    - 极速者：操控时关闭自动找敌/自动撞墙攻击规划；左键切换原极速攻击状态，攻击期间真实运动完全由 WASD 控制，再次左键可主动结束。
#    - “所有角色自由操控”的定义是：所有具有主动方向的攻击，在控制模式下不得被 Nearest_Enemy/Target_Enemy 强制吸回目标，且能向空地起手；
#      大狗叫、磁铁等原本就没有普通方向攻击键的纯被动机制保持其角色设计，不伪造一套不存在的攻击动作。
# ========================================================


# ========================================================
# V131 控制圈真实占地 / 主动副技能手动化 / 列车烟雾速度驱动
# ========================================================
# 1. 控制圈半径禁止继续读取 get_crowd_separation_radius_world()：
#    - crowd separation 是大规模战斗防重叠参数，不代表角色脚下真实占地；部分角色会为机制主动放大该值。
#    - 黄圈改为优先读取角色 CollisionShape2D.shape.get_rect() 的真实边界，乘 CollisionShape2D.global_scale；
#      取较短轴作为脚下圆直径并留 3px 边距，最终只对提示圈做 12~34px 半径限制。
#    - 这一限制纯视觉，不得修改真实 CollisionShape2D、角色体型、crowd separation 或伤害范围。
#
# 2. “玩家直接控制”对主动副技能的硬规则补充：
#    - 控制期间，角色原本由后台 timer/loop 自动释放的主动副技能必须暂停；
#      玩家解除控制后，AI 才恢复原后台循环。被动、召唤物自身 AI、持续状态不因此被错误停掉。
#    - 鼠标映射继续使用 V128~V130：左键=主要攻击，右键=主要副技能/Skill，中键=第三动作或角色专用扩展。
#    - 猎人：trap loop 在控制期间禁止自动放夹子；右键手动放一次捕兽夹，继续使用 trap_place_interval 作为手动冷却。
#    - 科学家：portal loop 在控制期间禁止自动移动/生成传送门；右键放/移动下一扇门，
#      鼠标点会吸附到距离它最近的地图墙，沿墙位置跟随鼠标，继续按橙/蓝顺序交替。
#    - 军火商：weapon loop 在控制期间禁止自动放枪；右键在鼠标世界位置（经地图边界 clamp）手动放一把随机枪，
#      继续使用 gun_place_interval 作为手动冷却。
#    - 炮兵：artillery loop 在控制期间禁止自动呼叫炮击；右键以鼠标世界位置为绿色炮击区中心，
#      若鼠标太靠地图边缘则只把中心 clamp 到完整炮击区仍能留在地图内的位置，继续使用 barrage_interval 作为手动冷却。
#    - 赌徒等 V130 已经拥有 controlled_attack_action()/controlled_skill_action() 的角色继续沿用已有手动入口，不恢复自动循环。
#
# 3. 火车长烟囱烟雾：
#    - 仍只复用 res://Images/characters/人物/炮兵/烟雾.png，不新增图片资源。
#    - 默认烟团尺寸从 18~34px 提高到 28~48px，寿命提高到约 0.95~1.55s；
#      初始 alpha 改为约 0.18~0.34，并随低速进一步降低，禁止恢复 V130 的 0.46~0.72 高不透明度。
#    - 新烟只能在 STATE_RUNNING / STATE_ARRIVING / STATE_DEPARTING 且真实运动速度高于最小阈值时生成；
#      STATE_STAGED 停车状态不得继续冒新烟。
#    - 进站减速时 emission interval 随速度连续变长，拖尾距离也缩短；完全停车后不硬删除已有烟，
#      已有烟继续 Tween 上升/放大/淡出，因此视觉上是烟逐渐停掉。
# ========================================================


# ========================================================
# V132 水印默认关闭 / 导出首次启动默认中文
# ========================================================
# 1. 参数页继续复用既有内部 key：Show_Center_Watermark，禁止另建第二个同义水印设置。
#    - 玩家显示名称改为“开启水印” / “Enable Watermark”。
#    - Game_Settings 默认值从 true 改为 false；World 读取缺省值、UI 动态补 key 的缺省值也必须统一为 false。
#    - 水印仍是每台机器自己的表现设置，不加入多人房间共享设置；玩家手动开启/关闭后继续跨启动保存。
# 2. V131 及更早版本可能已经把旧的 true 默认值自动保存到 user://settings.cfg。
#    V132 使用 defaults_migration/v132_watermark_default_false 做一次性迁移：
#    - 第一次从旧版本升级到 V132 时把 Show_Center_Watermark 迁移为 false 并立即保存迁移标记；
#    - 迁移完成后不再强制覆盖，之后必须尊重玩家自己在设置页做出的开关选择。
# 3. 导出/首次启动语言默认中文：
#    - DEFAULT_LOCALE 固定为 "zh"，current_locale 初值和无 settings.cfg 时的初始语言都使用该常量；
#    - Game Autoload 在 _enter_tree() 先执行 TranslationServer.set_locale("zh")，避免导出程序启动最初一帧先跟随操作系统语言；
#    - 如果 user://settings.cfg 已存在且玩家明确保存过 English，_ready() 加载持久化设置后仍恢复该用户选择，不强制每次启动都改回中文。
# 4. 本轮不创建/修改 project.godot。当前会话没有提供 project.godot 源文件，继续遵守路径基准“未上传不等于不存在、禁止自行创建第二项目根”的规则。
# ========================================================


# ========================================================
# V133 物理查询 flush 报错修复 / 伪军延迟生成
# ========================================================
# 1. Godot 4.x 的 Area2D monitoring / monitorable 不能在 area_entered、area_shape_entered 等
#    物理查询正在 flush 的回调栈里直接修改；否则会报：
#    “Can't change this state while flushing queries” 或
#    “Function blocked during in/out signal. Use set_deferred(\"monitorable\", ...)”。
# 2. 本轮截图中的 ball.gd:1337 不是独立的第二个逻辑错误，而是伪军在物理 in/out 信号链里
#    被 world.add_child() 后立即执行 ball._ready()，导致 _ready() 里的 Hurtbox monitorable 初始化
#    也落在同一个 flush 回调栈中。不能简单把 ball 全局初始化永久 deferred：大量子类会在
#    super._ready() 返回后有意覆写 monitoring/monitorable，若基类延后再写会反过来破坏这些角色。
# 3. 因此 V133 在真正的源头修复：伪军头子原 _spawn_one() 不再直接 add_child(伪军)。
#    _spawn_one() 只增加 _pending_reinforcement_spawns 预留兵力名额，然后
#    call_deferred(_spawn_one_deferred)；等 PhysicsServer2D 查询完成后才实例化并 add_child。
# 4. 兵力 3 人硬上限计算必须包含 pending，防止同一物理帧两次受击/招募请求超上限；
#    deferred 执行前若名额被其它来源占用或实例化失败，需要退回本次已经扣除的 1 张钞票。
#    正常召唤的音效、金钱扣除、Team/Master/攻击力继承与 safe_spawn_position 保持原机制。
# ========================================================

# ========================================================
# V134 面包车实体碰撞 / 双向速度冲撞 / Boss 特殊化
# ========================================================
# 1. 面包车本体恢复真实 CharacterBody2D 碰撞：
#    - collision_mask 必须同时包含地图 layer 1 与角色 layer 2，不再周期性给所有 Ball 添加碰撞例外；
#    - CollisionShape2D 继续使用现有自动拟合形状，vehicle_wall_body_scale 默认从 0.76 提高到 0.90，让实体车身更接近可见本体；
#    - 刚从车尾下车的小弟仍可仅在 summon_collision_grace 内与面包车互相忽略，时间结束后恢复真实车身碰撞。
#    - 智能驾驶的 _body_clearance_ratio() 在 test_move 时必须临时只使用 wall_probe_mask，路径规划只把地图墙当障碍；
#      禁止因为恢复人物碰撞后把敌人当“墙”提前绕开，面包车仍应主动追撞敌人。
# 2. 车头/车尾冲撞统一使用真实速度绝对值：
#    - 低于 max(Speed * ram_min_speed_ratio, 35) 时完全没有冲撞伤害；ram_min_speed_ratio 默认 0.42；
#    - 从最低有效速度到 Speed 之间连续插值 ram_min_damage_multiplier -> ram_max_damage_multiplier，速度越高伤害越高；
#    - 车头使用完整冲撞倍率；车尾（主要为倒车命中）默认只造成 rear_ram_damage_ratio=0.55 倍伤害，击退也相应更弱；
#    - 半径预判必须确认车辆真实运动方向正在朝目标接近；真实 slide collision 可允许轻微车角擦碰，避免已经驶离目标仍凭半径扣血。
# 3. 普通面包车机动性提高：drive_acceleration 105->132、drive_brake 190->225、steering_rate 1.22->1.62、
#    steering_input_smoothing 5.2->6.4、steering_acceleration 3.8->5.2、minimum_steering_factor 0.62->0.76；
#    这是车辆自己的驾驶参数，不改所有角色的 V129 0.6x 基础移速规则。
# 4. 面包车正式实现训练 Boss 特殊化接口：
#    - has_training_boss_specialization() 返回 true；只有 Boss 模式中“Boss特殊化”开启且面包车位于 Boss 方才启用；
#    - prepare_training_boss_specialization() 将专属 Boss 的 Max_health 明确设为 1200；World 已应用的 Damage 等通用 Boss 数值倍率仍保留；
#    - 普通倒车随机召唤的 summon_interval 在专属 Boss 下乘 0.82（约提高 18% 频率）；
#    - Boss 额外提高转向、转向建立、加减速与脱困转向，默认 boss_mobility_multiplier=1.18。
# 5. 专属 Boss 第一次降到 50% Max_health 时触发“全员下车”：
#    - VAN_KNIFE / VAN_BATON / VAN_FIST 三种小弟各召唤 1 名，不要求当时正在倒车，也不消耗普通随机召唤冷却；
#    - 若某个下车点当帧因墙/角色拥挤无法安全生成，该类型必须保留 pending 并在后续物理帧继续尝试，直到三种都成功；
#    - 该 50% 波次每个 Boss 实例只触发一次，普通非特殊化面包车不拥有该阶段。
# ========================================================

# ========================================================
# V135 面包车 Boss 半血必触发 / 血条阶段标注 / 智能驾驶加强
# ========================================================
# 1. V134 半血“三人全下车”不能只依赖面包车 _physics_process() 的生命比例轮询。
#    ball.health setter 已统一在真实生命下降后调用 on_actual_health_damage_received()；
#    面包车 V135 覆写该回调，在 health 已写入新值后立即检查 50% 阈值，同时保留物理帧检查作为兜底。
#    这样无论伤害来自碰撞、技能、流血还是直接扣血，只要专属 Boss 首次降到 50% Max_health 或以下都登记阶段。
# 2. 半血波次登记后真正实例化/World.add_child() 必须 call_deferred 到 PhysicsServer2D 查询结束后，
#    继续遵守 V133 的物理 flush 安全规则。三种固定类型 VAN_KNIFE / VAN_BATON / VAN_FIST 各 1 名。
# 3. Boss 半血下车不得复用普通随机下车的“墙 + 所有人物都必须完全空旷”条件：
#    - V135 使用车尾三槽位 + 周围备用环形槽位；
#    - 只禁止生成进地图墙体，敌人正贴着 Boss 时也不能永久阻止阶段召唤；
#    - 某一槽位靠墙失败时保留 pending，在后续帧继续尝试直到三种小弟全部成功。
#    普通倒车随机下车仍保留原来的严格安全出生判定。
# 4. Boss 特殊化血条必须明确可读：classes/health_bar.gd 的通用生命阈值接口新增可选
#    get_health_threshold_label(threshold) / get_health_threshold_marker_color(threshold)。
#    面包车专属 Boss 在 50% 阈值使用橙色横线，并显示“50%  BOSS特化：全员下车”
#    （英文：Boss Spec: All Crew Out）；不能再只画一条难以辨认的黑线。
#    activate_training_boss_specialization() 必须主动 refresh_health_threshold_markers()，
#    因为 HealthBar 子节点 _ready() 早于角色 post-ready Boss 激活。
# 5. 面包车智能驾驶继续使用现有 CharacterBody2D + 墙体探针/车身 test_move 局部规划，
#    不凭空加入 NavigationAgent2D/NavigationRegion2D（当前项目未提供导航数据）。V135 加强：
#    - 普通车 acceleration 165、brake 280、steering_rate 2.25、steering_acceleration 8.0，Boss 再乘 1.30 机动倍率；
#    - 大角度转向先明显降速，低速/近身/大角度时提高实际 yaw 权重，减少高速画大圆；
#    - 候选绕障角从约 ±120° 扩到 ±150°，更容易在墙角主动挑可走方向；
#    - 目标移动预测的近距离基础提前量从 0.22s 降到 0.08s，避免贴脸追击时过度瞄向未来位置而绕圈；
#    - 目标处于车尾触发普通战术倒车时允许“车尾朝目标”转向，ram_reverse 撞后脱离仍保持直退。
# 6. V134 的其它面包车规则继续保留：专属 Boss Max_health=1200、普通召唤频率乘 0.82、
#    真实人物碰撞、车头/车尾速度伤害、低速无冲撞伤害；本轮不改角色/资源路径名称。
# ========================================================

# ========================================================
# V136 面包车 Boss 血条标记回归既有黑线
# ========================================================
# 1. V135 新增的 Boss 阈值文字“50% BOSS特化：全员下车”、橙色阈值线，以及
#    health_bar.gd 的 get_health_threshold_label()/get_health_threshold_marker_color() 扩展全部撤销。
#    这是 V136 对 V135 第 4 条的明确覆盖；禁止重新恢复文字标签或彩色 Boss 阈值线。
# 2. 继续复用项目原有 classes/health_bar.gd 的生命阈值机制：角色只需要实现
#    get_health_threshold_values()，HealthBar 就会在对应生命位置绘制既有纯黑色横线。
# 3. 面包车 Boss 继续让 get_health_threshold_values() 返回 Max_health * boss_all_minions_health_ratio；
#    默认 boss_all_minions_health_ratio=0.50，因此 1200HP Boss 在 600HP 对应位置只显示一条黑线。
# 4. V135 的半血真实伤害回调触发、deferred 三小弟下车、1200HP、召唤频率与智能驾驶加强全部保留；
#    本轮只撤销错误的额外 UI 标注，不改变 Boss 战斗机制。
# ========================================================

# ========================================================
# V137 面包车 Boss 50% 黑线绘制层修复 / 伪军头子死亡后小弟跑路
# ========================================================
# 1. V136 的“只复用既有纯黑生命阈值线”规则不变：禁止恢复文字、橙线或 Boss 专用标签。
#    本轮修的是黑线实际绘制层级：旧 health_bar.gd 把 HealthThresholdMarker 作为 Health(TextureProgressBar) 的子节点，
#    但同级 Block 护盾条 z_index=1 会盖在 Health/marker 上，因此实机可能完全看不到阈值线。
# 2. V137 仍由角色 get_health_threshold_values() 提供阈值；HealthBar 只把纯黑 ColorRect marker 改挂到
#    Health 与 Block 的共同父节点 TextureRect，并使用 z_index=4 放到两条 ProgressBar 之上。
#    marker 的 X/Y/宽度/厚度继续按 Health 的 position、size、scale 计算；面包车 Boss 1200HP 的 50% 线仍对应 600HP。
# 3. 伪军头子死亡后，自己拥有的 FakeArmySoldier 不再 force_surrender() 后直接 health=0/free。
#    伪军必须复用黑帮老大普通小弟的跑路语义：停止攻击/连射，播放 res://audio/characters/黑帮老大/跑路了兄弟.mp3，
#    关闭自身攻击碰撞，退出人物/墙实体碰撞，设置 submission_allow_map_escape，并朝最近地图边界外逃；越界后才删除。
# 4. 多名伪军同一帧跑路时继续复用 _gang_flee_sfx_last_msec 的 650ms 去重，避免同一句“跑路了兄弟”叠三层。
#    伪军头子死亡前已经 deferred 排队、但尚未真正生成的增援必须取消，禁止头子死后再刷出迟到小弟。
# 5. V133 的 PhysicsServer2D flush 安全规则继续保留：跑路时关闭 Hitbox monitoring 使用 set_deferred()，
#    不在 Area2D in/out 信号栈里直接切换监测状态。
# ========================================================


# ========================================================
# V138 面包车 Boss 环绕地图 / 降低速度强化 / 小弟边界保护
# ========================================================
# 1. V137 Boss 特殊化仍先经过 World 的通用 Boss 数值倍率；World 会把 Speed 也乘 Training_Boss_Multiplier
#    （默认 3.0）。面包车驾驶逻辑直接使用 Speed，不走普通 ball.move()，因此原始 Speed=135 会被推到 405，
#    速度过高会让局部探针、转弯半径和撞墙恢复都显得更笨。V138 在 prepare_training_boss_specialization()
#    中用传入的 boss multiplier 还原“通用倍率前车速”，专属 Boss 只保留 boss_speed_multiplier=1.05 的轻微速度强化。
# 2. boss_mobility_multiplier 从 1.30 降为 1.12；Boss 的优势重点改为转向、刹车、路线重判而不是最高速度。
#    wall_follow_min_time / wall_follow_clear_time / stuck_trigger_time 在特殊化时缩短，使旧沿墙路线更快失效并重新追踪目标。
# 3. Boss 特殊化新增地图边界环绕（edge wrap），普通面包车不拥有：
#    - 追敌时把地图看作可环绕平面，X/Y 两轴比较直线路径与跨边界路径，使用更短的 delta；
#    - 当更短路线需要从左/右/上/下边界离场，并进入 boss_wrap_approach_distance 时，边界墙探针不再强迫倒车/沿墙绕回；
#    - Boss 车身抵达安全内沿后只传送 Boss 本体到对侧对应位置，方向、前进/倒车速度保持连续；
#    - 左边出去 -> 右边回来、右边出去 -> 左边回来；上下同理；wrap 后清空旧 wall escape / wall follow / stuck 状态，
#      禁止带着上一堵墙的恢复状态在新位置继续犯傻。
# 4. 正常车辆移动与内部墙碰撞继续使用 CharacterBody2D.move_and_slide()；edge wrap 只是一瞬间的边界传送，
#    不把 Boss 的 collision_mask 改成穿透所有墙，也不让普通面包车获得穿墙能力。
# 5. 面包车小弟绝不能跟 Boss 一起环绕或卡在地图外：
#    - _spawn_van_minion_at() 对所有车载小弟最终出生点再次 clamp 到地图安全内沿；
#    - Boss 存活期间若自己拥有的 VAN_KNIFE / VAN_BATON / VAN_FIST 因碰撞/出生宽限被推出安全区，只在越界时拉回内沿并清空 Repel；
#    - 该保护明确忽略 submission_allow_map_escape=true 的跑路单位；面包车死亡后自身不再执行存活物理逻辑，
#      因此 V134/V137 已有“小弟在车死后跑路并越界删除”机制不受影响。
# 6. V134~V137 的其它规则继续保留：1200HP、50% 黑线与三人全下车、普通召唤频率略增、实体车身碰撞、
#    车头/车尾速度伤害、低速无冲撞伤害；本轮不移动/重命名任何项目资源。
# ========================================================


# ========================================================
# V139 面包车 Boss 边界环绕回弹修复 / 回场锁
# ========================================================
# 1. V138 的 edge wrap 存在触发带重叠：boss_wrap_trigger_margin=64，而传送落点 boss_wrap_exit_inset=56，
#    Boss 从一侧传送到另一侧后仍处于另一侧的 wrap 触发带内；原 cooldown 仅 0.20s，最短路线重新计算后可立刻反向 wrap，
#    实机表现为特殊化后在两侧边界持续“回弹”。
# 2. V139 将 wrap 改成真正的“到边缘才穿越”：默认 trigger margin 64->10，落点 inset 56->84，
#    cooldown 0.20->1.10。传送点与触发带不再重叠，禁止只靠接近边界就过早瞬移。
# 3. 新增 Boss wrap re-entry 单向回场锁：
#    - 每次传送后记录当时真实行驶方向；
#    - 默认 0.75s / 92px 内必须先沿原方向驶回战场，期间 _boss_route_to_goal() 禁止再次选择 wrap，
#      wall follow / smart avoidance / 战术倒车也不能把车辆立即推回刚才的出口；
#    - 左边驶出 -> 右边出现后先继续向左驶入场内；右/上/下同理；达到回场距离或时间后才恢复正常追击。
# 4. wrap 使用车辆真实前进/倒车方向而不是 Repel 混合后的 requested_velocity 判定；传送后清空 Repel、旧 wall escape / stuck 状态，
#    保持车身 heading 与实际运动方向连续，避免外部击退或旧墙恢复状态把车辆推回边界。
# 5. V138 其它规则全部保留：Boss 最高速度只轻微 1.05x、1200HP、50% 黑线与三小弟下车、边界环绕只属于 Boss 本体；
#    车载小弟继续锁在地图安全内沿，绝不能跟随 Boss wrap 或卡到地图外，死亡后的跑路越界机制不受影响。
# ========================================================

# ========================================================
# V140 面包车 Boss 血条只保留 50% 黑线 / 边界墙碰撞触发 wrap
# ========================================================
# 1. V139 Boss 血条会同时显示两条黑线，是因为面包车 get_health_threshold_values() 在 Boss 状态下
#    同时返回了 50% “全员下车”阈值和 18% cripple 阈值。V140 明确改为：
#    - Boss 特殊化：只返回 Max_health * boss_all_minions_health_ratio（默认 50%）这一条黑线；
#    - 普通面包车：仍可显示 cripple_ratio（默认 18%）黑线；
#    - 18% cripple 战斗机制本身没有删除，只是不再作为 Boss 的第二条血条阶段线暴露。
#    禁止重新给 Boss 血条追加第二条 cripple 黑线、文字或彩色标记。
# 2. V139 “中心点接近 map_rect 内沿 10px 才 wrap”在真实 TileMap 边界墙存在厚度时仍可能永远到不了触发点：
#    CharacterBody2D.move_and_slide() 会先被边界碰撞挡住，safe margin/碰撞恢复也可能让车中心停在更内侧。
# 3. V140 保留原几何 trigger，同时新增真实边界碰撞兜底：
#    - 只有 Boss 已明确提交 uses_wrap 路线，并且 move_and_slide() 的主碰撞法线与该 wrap 边界方向一致时才触发；
#    - 左出口要求碰撞法线朝右、右出口要求法线朝左、上/下同理，因此普通内部墙不会因为一次碰撞就任意传送；
#    - 命中边界墙后直接复用同一个 _complete_boss_edge_wrap() 传送到对侧安全内沿。
# 4. V139 的回场锁继续保留：wrap 后仍必须先沿原真实行驶方向驶入场内，cooldown / re-entry 期间禁止再次 wrap，
#    防止修复“无法穿墙”后重新出现 V138 的左右/上下连续回弹。
# 5. 小弟规则不变：只有 Boss 面包车本体允许 edge wrap；车载小弟仍 clamp 在地图安全内沿，不能跟车穿墙或卡出地图，
#    面包车死亡后 submission_allow_map_escape 的跑路小弟仍允许越界删除。
# ========================================================

# ========================================================
# V141 面包车冲撞判定 / 速度击退手感修复
# ========================================================
# 1. V140 以前冲撞虽然恢复了真实 CharacterBody2D 碰撞，但视觉车身旋转只作用在 Graphics；
#    根 CollisionShape2D / hurtbox 的矩形仍保持原朝向，斜着开时会出现视觉车角已经擦到敌人、实体矩形却没有对应接触。
#    V141 让车身 CollisionShape2D 与 hurtbox/CollisionShape2D 跟随 _vehicle_heading 旋转，并保留 AutoFit 原本的 position/rotation 基准；
#    车身碰撞缩放默认从 0.90 提到 0.96，使实体轮廓更贴近车辆视觉，但仍保留少量余量避免墙角过度卡死。
# 2. 冲撞不再只依赖 move_and_slide() 返回的 slide collision 或以角色中心为圆心的 ram_hit_radius：
#    每个物理帧在车辆移动后，按真实车身世界尺寸生成一个沿“上一位置 -> 当前位置”的旋转扫掠矩形，
#    使用 PhysicsDirectSpaceState2D.intersect_shape() 查询人物层；车侧/车角从敌人边缘擦过也能被检测。
#    原 slide collision 仍保留为真实接触兜底；同一目标继续用 ram_target_cooldown 去重，禁止一帧重复结算。
#    旧 _physics_process() 的第二次中心圆查询停用，避免大规模战斗时每台车每物理帧重复查询人物层。
# 3. 真实车身/扫掠接触对侧擦角度的容忍从旧 -0.12 放宽到 -0.35，只拒绝车辆已经明显驶离目标的情况；
#    命中区域分为车头 / 车侧 / 车尾：车头完整伤害，车侧默认 0.78 倍，车尾继续使用 rear_ram_damage_ratio（默认 0.55）。
# 4. 击退必须随速度明显增长，但整体比 V140 克制：
#    - 默认距离 34~118px 改为 8~70px；默认击退速度 360~840 改为 120~560；
#    - 使用 pow(speed_damage_ratio, 1.70) 的非线性曲线，刚超过最低冲撞速度只轻推，中高速才快速增加；
#    - 车侧击退再乘 0.82/0.86，车尾再乘 0.62/0.68；低于 ram_min_speed_ratio 的既有“0 冲撞伤害/0 击退”规则不变。
# 5. V138~V140 的 Boss 1200HP、50% 单黑线、半血三小弟、边界 wrap / 回场锁、小弟不得卡出地图等规则全部保留；
#    本轮不移动/重命名任何资源，不新增同义目录。
# ========================================================

# ========================================================
# V142 面包车血条/边界穿越撤销 / 普通小弟生命减半 / 下车随机音效
# ========================================================
# 1. 普通面包车不再暴露 cripple_ratio 作为血条阈值，因此普通模式血条外/下方不应再出现 18% 的额外黑线。
#    get_health_threshold_values() 在普通模式返回空数组；只有 Boss 特殊化继续返回 50% 半血阶段阈值，复用既有纯黑横线。
#    18% cripple 战斗机制仍保留，但不再作为普通或 Boss 的额外 UI 阶段标记。
# 2. V138~V141 的 Boss edge wrap / 边界穿越 / 回场锁全部删除并作废。Boss 特殊化驾驶时与普通面包车使用完全同一套
#    wall-follow / smart-drive / move_and_slide() AI，不再尝试穿地图边界、不再计算环绕最短路径，也不再拥有传送状态。
#    Boss 仍保留 1200HP、50% 三小弟全下车、略高召唤频率和轻度机动数值强化；V141 车体扫掠撞击/速度击退继续保留。
# 3. 车载小弟地图保护改为普通/Boss 都执行：只要母车仍存活，VAN_KNIFE / VAN_BATON / VAN_FIST 若被挤出安全内沿会拉回；
#    submission_allow_map_escape=true 的死亡跑路状态继续允许越界删除。
# 4. 普通面包车（非 Boss 特殊化）召出的三种车载小弟基础生命统一乘 0.50；Boss 的普通周期召唤和 50% 三人波次保持原生命。
#    该倍率通过 投稿随从.gd 的 spawn_health_multiplier 在 _enter_tree/_ready 的种类数值初始化后应用，避免出生后再扣血造成假伤害跳字。
# 5. 新增并正式接入用户提供的四段下车音效，固定放在 res://audio/characters/面包车/：
#    下车_[cut_1sec].mp3、下车_[cut_1sec] (1).mp3、下车_[cut_1sec] (2).mp3、下车_[cut_1sec] (3).mp3。
#    每次召唤事件随机播放其中一段；普通周期召唤每次都会播放，Boss 半血三人同帧下车使用 120ms 去重，只播一段避免叠音。
# ========================================================


# ========================================================
# V143 面包车 V142 Parser Error 热修 / 恢复 V141 非穿墙碰撞函数
# ========================================================
# 1. V142 删除 Boss edge wrap / 边界穿越代码时误把 V141 的三个“与穿墙无关”的车身冲撞函数一起删除，
#    但 _physics_process() 仍调用 _sync_vehicle_collision_orientation() 与 _process_ram_swept_contacts()，
#    因此 Godot 4.7.2 会在加载 res://scripts/characters/面包车.gd 时直接 Parser Error：Function not found in base self。
# 2. V143 只恢复 V141 已有的三个函数：
#    - _sync_vehicle_collision_orientation()：让根 CollisionShape2D 与 hurtbox 碰撞形状跟随车辆 heading；
#    - _vehicle_ram_half_extents_world()：计算真实世界车身半尺寸；
#    - _process_ram_swept_contacts()：使用旋转矩形 intersect_shape() 补足高速/擦边冲撞漏判。
# 3. V142 已明确删除并作废的 Boss edge wrap / 地图边界传送 / 回场锁函数继续保持删除，禁止因本次恢复 V141 函数而重新引入。
# 4. V142 的普通面包车无阈值黑线、Boss 仅 50% 黑线、普通小弟生命减半、四段下车随机音效等规则全部保持不变。
# ========================================================


# ========================================================
# V144 面包车直接控制接管 / 车载小弟恢复追击移动
# ========================================================
# 1. 面包车脚本自己覆写 tick_physics()，此前不会进入 ball.move() 的 player_control_direction 分支；
#    所以玩家 C 键接管以后，车辆仍然执行 _vehicle_target / roam / wall-follow / smart-drive 自动驾驶。
#    V144 在面包车 tick_physics() 最前面加入直接控制专用分支：
#    - 进入控制第一帧清空 AI 倒车、撞墙脱困、沿墙、卡死恢复等状态并停车；
#    - W/S 只控制前进/倒车油门，A/D 只控制方向盘；
#    - 手动模式完全不读取敌人位置、巡航点或智能驾驶候选方向；
#    - 手动撞墙只走 CharacterBody2D 正常物理，不触发 AI wall_escape / 自动倒车；
#    - 退出控制以后才恢复原普通/Boss 共用自动驾驶 AI。
# 2. 三种面包车车载小弟 VAN_KNIFE / VAN_BATON / VAN_FIST 以前没有自己的持续追敌方向更新，
#    主要依赖 World 对 direction==ZERO 的随机方向兜底；在最近的实体碰撞/地图保护改动后可表现为下车后原地不动。
#    V144 在其 _physics_process() 中、死亡跑路判断之后持续寻找全场最近合法敌人，
#    并把 direction 更新为朝敌方向；没有敌人时不强制清零，继续允许原随机巡游兜底。
# 3. 面包车死亡后的小弟“播放跑路了兄弟并逃出地图”逻辑优先级不变；一旦进入 _fleeing，
#    不再执行追敌更新。V142 普通模式小弟生命减半、Boss 小弟原生命、下车随机音效继续保留。
# 4. 玩家控制面包车时，正面撞人仍保留速度冲撞伤害，但禁止自动 _begin_ram_reverse()；
#    W+A/W+D 的归一化输入按按键轴恢复为满油门 + 满方向，避免对角操作自动降速。
# ========================================================


# ========================================================
# V145 车载小弟移动回退：恢复 V143/V142 原正常移动逻辑
# ========================================================
# 1. V144 对 VAN_KNIFE / VAN_BATON / VAN_FIST 新增的“每物理帧朝最近敌人更新 direction”属于错误改动，V145 全部撤销。
#    删除 _update_van_minion_chase_direction() 及其 _physics_process() 调用，不再人为把车载小弟方向锁到最近敌人。
# 2. 三种车载小弟恢复 V143/V142 之前项目已有的正常移动链：投稿随从只负责自身攻击/跑路时序，
#    正常战斗移动继续交给项目原有 ball / World 的标准 direction、move()、随机巡游/碰撞处理，不新增追敌移动 AI。
# 3. 本轮只撤销 V144 的小弟追敌方向改动；V144 面包车直接控制接管（W/S 油门、A/D 转向、控制时停用自动驾驶）继续保留。
# 4. V142 普通面包车召唤小弟生命 0.50 倍、Boss 小弟原生命、四段下车随机音效、母车死亡后跑路等规则全部继续保留。
# ========================================================


# ========================================================
# V146 车载小弟“走一会永久停住”修复：删除安全内沿每帧钳制
# ========================================================
# 1. V145 已撤销错误的追敌 AI，但小弟仍可能移动一段时间后永久停在地图内侧某条看不见的边界。
#    根因不是 投稿随从.gd，而是 V142 把 _keep_owned_van_minions_inside_map() 从 Boss 专用扩大到普通/Boss全局，
#    并在面包车自己的 _physics_process() 每帧把三种车载小弟强制 clamp 到 _van_minion_safe_rect()。
# 2. 当小弟随机 direction 持续朝地图外走时，它每帧先移动一点，再在真正地图墙之前被强行拉回同一个 safe_rect 边界点。
#    因为根本没有碰到实体墙，ball.when_collide() 无法得到碰撞法线并 bounce(direction)，于是 direction 永远朝外，
#    视觉结果就是“走一会后完全不动”。
# 3. V146 删除面包车 _physics_process() 对 _keep_owned_van_minions_inside_map() 的调用，并删除这套每帧钳制函数。
#    三种小弟恢复项目标准移动链：World 只在 direction==ZERO 时给随机方向，ball.move() 使用 direction 移动，
#    真正碰到地图墙后由 move_and_slide()/when_collide() 反弹，因此不会被一条不可见的内缩边界永久锁死。
# 4. 出生位置安全仍保留 _clamp_van_minion_spawn_to_map()，避免刚生成就嵌进边界；
#    若角色中心真的因为挤压越出地图，则继续交给 World 既有 _process_map_squeeze_protection() 救回。
#    面包车死亡后 submission_allow_map_escape=true 的跑路小弟仍可正常越界删除。
# 5. V145 的面包车直接控制、V142 普通小弟 0.50 生命、Boss 小弟原生命、四段下车随机音效及其它累计规则全部保持。
# ========================================================

# ========================================================
# V147 面包车自动驾驶减法重构
# ========================================================
# 1. V146 以前面包车自动驾驶同时叠加目标追踪、21 候选方向扫描、沿墙、提前避墙、目标在车后自动倒车、
#    撞墙脱困与卡住恢复，多层决策会在同一物理帧争抢方向，表现为频繁改主意、画圈、无意义倒车。
# 2. V147 明确做减法：
#    - 正常有敌人时直接追 combat_target_position()；目标速度预测只保留 0.04~0.26s 轻量提前量，近距离几乎不预判；
#    - 只有“目标直线路径被墙实际阻挡”时才进入 wall-follow；选定绕行侧后至少保持 wall_follow_min_time=0.85s，
#      并用两侧真实墙体/车身净空 + 目标对齐评分选更可行的一边，禁止每帧左右翻面；
#    - 未进入 wall-follow 时只叠加温和的边界/前保险杠排斥，旧 _choose_smart_drive_direction() 的 21 候选角不再参与主驾驶决策；
#    - 只有真正撞墙/移动卡死才进入 wall_escape。目标在车后不再远距离自动倒车；仅当目标距离 <=145px、
#      位于车尾约 132° 以上并且车尾真实净空 >=0.78 时，才允许一次短战术倒车。
# 3. 油门现在直接受车头与期望方向夹角控制：角度越大越先减速转正；大角度时保持很低爬行速度并提高低速转向，
#    禁止高速绕目标画大圆。wall-follow 与撞墙恢复阶段额外限速，不靠继续堆 Boss 速度解决机动问题。
# 4. 普通与 Boss 特殊化继续共用同一自动驾驶；Boss 不恢复 V138~V141 已删除的边界穿越/传送设定。
#    当前项目没有 NavigationRegion2D/NavigationPolygon 数据，禁止凭空创建导航网格；仍使用现有 CharacterBody2D、墙体物理查询与局部绕墙。
# 5. V144 手动操控车辆、V141 车体扫掠冲撞、V142 普通小弟 50% 生命与随机下车音效、V146 小弟原生移动规则全部保留。
# ========================================================

# V148 面包车驾驶油门规则（覆盖 V147 中“大角度主动减速”的部分）
# - 面包车自动驾驶的转向角不再直接降低目标车速：只要目标方向前方有实际净空，就持续向当前最高车速加速。
# - 转圈、追敌绕行、180° 调头时也保持油门；转向和刹车解耦，不因为 steering_error 大就主动降到爬行速度。
# - 真正允许主动减速的原因仍是：前方墙体/车身净空不足、换挡、撞墙脱困、wall recovery 等实际物理风险。
# - 沿墙绕行速度上限由 0.52×Speed 提高到 0.82×Speed；wall recovery 上限由 0.46×Speed 提高到 0.58×Speed。
# - 不提高 Speed 本身，不改变 Boss/普通面包车最高速度倍率、冲撞伤害、击退、小弟、半血阶段、手动 WASD 控制等其它累计规则。

# V149 面包车驾驶回退规则
# - 用户实机确认 V148“转向角不削油门、绕墙高油门”比 V147 更差，因此 V149 直接撤销 V148 的驾驶改动。
# - 面包车驾驶逻辑恢复 V147：转向误差重新参与目标车速；大角度时允许先降速转正；沿墙速度恢复为 0.52；撞墙恢复阶段速度恢复为 0.46。
# - V149 只回退 V148 的驾驶手感改动，不回退 V147 及更早版本已经累计确认的实体车身碰撞、扫掠冲撞、速度伤害/击退、手动 WASD、Boss 1200HP/50%三小弟、普通小弟半血、下车随机音效等机制。
# - 后续若继续优化面包车 AI，应从 V147 驾驶基线做小范围、可验证修改，不再用“转弯始终满油”作为默认原则。

# ========================================================
# V150 面包车多单位场景驾驶修复：队友不阻车 / 目标锁定滞回 / 敌群连续冲撞
# ========================================================
# 1. 用户实机确认：只有一个其它单位时尚可，但场上出现多个单位（包括面包车自己召出的同队小弟）后，
#    面包车会频繁修正、倒车、卡住或在多个目标之间摇摆。根因不是墙体路径本身，而是“人物实体碰撞 + 最近目标切换”叠加：
#    - CharacterBody2D.move_and_slide() 会被同层人物实体接触改变实际 velocity；
#    - 旧 _handle_vehicle_collision() 对任意 ball 接触都可能直接 _begin_ram_reverse()，同队单位也会触发；
#    - 多个距离接近的敌人会让最近目标在相邻物理帧来回变化，驾驶 desired_direction 因此持续翻转。
# 2. V150 队友碰撞规则：面包车定期扫描 Ball 组，对 Team 相同且存活的 PhysicsBody2D 建立双向 collision exception。
#    这包括自己召出的 VAN_KNIFE / VAN_BATON / VAN_FIST；小弟下车的短暂 grace 到期后，只要仍同队就继续保持例外。
#    结果是“车本体有实体碰撞”继续对敌人与地图成立，但队友不再成为车辆的动态路障，也不会触发换挡/脱困。
# 3. V150 目标锁定加入滞回：无显式 Target_Enemy 时，车辆会短时间保持当前合法敌人；锁定到期后也只有新候选明显更近
#    （默认距离 < 当前锁定目标约 68%）才切换。禁止两个距离接近的敌人让目标每帧来回跳。
# 4. V150 冲撞倒车统一入口：_handle_vehicle_collision() 遇到 ball 只做敌人接触反馈，不再直接倒车；真正的车头命中后倒车
#    只由 _try_apply_ram_to_target() 决定。单敌人仍保留原“撞中 -> 短倒车 -> 再冲”的节奏。
# 5. 当附近默认 220px 内存在 >=2 名敌人时进入敌群冲撞：第一次撞中不立刻倒车，并给刚命中的敌人约 0.20s 的
#    双向 collision exception。初次真实接触、伤害和击退仍照常发生，但下一物理帧车辆可以穿过已经命中的第一人继续撞后续敌人，
#    避免被敌群最前排一个 CharacterBody2D 永久截停。每目标原有 ram_target_cooldown 继续防重复伤害。
# 6. V147 驾驶基线、V144 手动 WASD、V141 扫掠判定/速度伤害击退、V142 普通小弟 50% 生命与下车随机音效、
#    V146 小弟原生移动规则、Boss 1200HP/50% 三小弟等其它累计机制全部保持不变。
# ========================================================

# ========================================================
# V151 面包车“顶人卡墙”解锁 / 召唤可靠性修复
# ========================================================
# 1. V150 的一个回归是把人物实体接触的倒车入口完全从 _handle_vehicle_collision() 移除，并要求
#    _try_apply_ram_to_target() 成功造成一次伤害以后才决定是否倒车。若车辆已经被人物实体顶慢到冲撞伤害阈值以下，
#    或该目标仍处于 ram_target_cooldown，伤害函数会直接返回 false；同时 primary slide collision 又一直是人物，
#    原 _update_stuck_recovery() 只在 collision==null 时执行，因此会形成“车一直往前顶人，把人顶到墙上后永久卡住”的死锁。
# 2. V151 新增独立于伤害成功与否的实体阻塞检测 _resolve_enemy_body_blocking()：
#    - 比较本帧 requested_velocity 理论位移与 move_and_slide() 真实位移；
#    - 真实位移连续低于默认 38%，同时 slide collision 中存在敌人时，认定人物正在实际阻车；
#    - 单敌人阻车约 0.14s 后强制短倒车并清除目标锁；敌人背后已经紧贴地图墙时直接进入现有 wall_escape，禁止继续把人顶墙；
#    - 该逻辑不依赖当前冲撞是否能再次扣血，所以伤害 cooldown/低速不会阻断车辆解卡。
# 3. 多敌人场景继续允许“撞穿前排”，但 V150 的临时 collision exception timer 改成每个目标唯一截止时间：
#    连续接触只延长截止时间，不再生成多个 timer 互相提前 remove_collision_exception，避免目标仍重叠在车身中时碰撞被过早重新打开并再次卡车。
#    默认宽限由 0.20s 调为 0.34s。若前排敌人背后已经是墙，则不盲目穿透，优先 wall_escape。
# 4. V150 目标锁定滞回继续保留，但人物阻车进入解卡时主动清除当前锁定，撤开后允许重新选择更合适目标，避免一直执着于墙边被顶住的同一个敌人。
# 5. 召唤仍保持原设计“真实倒车以后从车尾下人”，但不再依赖 AI 碰巧因撞击进入倒档。召唤冷却满以后，自动驾驶会在车尾墙体净空足够时主动请求一次约 0.78s 的短倒车；
#    真正形成负速度以后再尝试生成。多人连续冲撞即使不触发 ram_reverse，也不会再把普通周期召唤间接彻底关闭。
#    如果出生点暂时被单位占满，冷却不清零；扩大侧后方/更远后方候选点并继续等待合法位置，禁止直接丢失本次召唤。
# 6. V150 队友 collision exception、V147 驾驶基线、V144 手动 WASD、V141 车身扫掠/速度伤害击退、V142 普通小弟 50% 生命与随机下车音效、
#    V146 小弟原生移动、Boss 1200HP/50% 三小弟等其它累计规则全部保持不变。
# ========================================================


# ================================================================
# V152 面包车冲撞攻击碰撞 Inspector 可调
# ================================================================
# 1. 用户要求“面包车攻击碰撞有问题，可以自己调整”。V152 不再继续擅自放大/缩小默认判定；
#    V151 实机默认表现保持不变，只把原来写死在脚本里的攻击扫掠几何与方向过滤参数开放到 Inspector。
# 2. scripts/characters/面包车.gd 新增“冲撞攻击碰撞（可调）”分组：
#    - ram_attack_length_scale：攻击矩形前后长度倍率；
#    - ram_attack_width_scale：攻击矩形横向宽度倍率；
#    - ram_sweep_padding：原有四周基础外扩，默认 9px；
#    - ram_attack_front_extra / rear_extra / side_extra：只扩对应方向；
#    - ram_attack_forward_offset：整个攻击矩形沿当前行驶方向前后平移；
#    - ram_physical_min_approach_dot / ram_sweep_min_approach_dot：实体接触与扫掠命中的方向过滤；
#    - ram_front_zone_dot / ram_rear_zone_dot：车头/车侧/车尾伤害分段边界。
# 3. 上述参数全部只作用于“冲撞攻击命中范围/命中分类”，不修改 CharacterBody2D 的真实墙体/人物实体碰撞尺寸，
#    因此用户可以单独调攻击手感，不会因为扩大攻击框而让车更容易卡墙。
# 4. V152 默认值严格复现 V151：长度/宽度倍率 1.0、统一 padding 9px、额外扩展/偏移 0、
#    physical approach -0.35、sweep approach 0.08、前/后分段 +/-0.28。
# 5. V151 多单位解卡/可靠召唤、V150 队友 collision exception、V147 驾驶基线、V144 手动 WASD、
#    V142 普通小弟 50% 生命和下车随机音效、Boss 1200HP/50% 三小弟等累计规则全部保持。


# ================================================================
# V153 面包车冲撞攻击碰撞改为场景双碰撞箱（覆盖 V152）
# ================================================================
# 1. 用户明确要求：不要再通过脚本 Inspector 参数调整攻击范围；面包车必须在场景里直接有“车头 / 车尾”两个碰撞箱，
#    可以在 Godot 2D 编辑器中选中 CollisionShape2D 后直接拖动位置和尺寸。
# 2. scenes/characters/人物/面包车.tscn 新增：
#    - 冲撞攻击碰撞/车头攻击区域/车头碰撞箱（RectangleShape2D）；
#    - 冲撞攻击碰撞/车尾攻击区域/车尾碰撞箱（RectangleShape2D）。
#    两个 Shape2D 都 resource_local_to_scene=true，可独立修改；它们只负责攻击命中，不改变 CharacterBody2D 的真实车身碰撞。
# 3. scripts/characters/面包车.gd 删除 V152 的 ram_attack_length_scale、ram_attack_width_scale、ram_sweep_padding、
#    front/rear/side extra、forward_offset、approach dot、front/rear zone 等“脚本调攻击框”参数。
# 4. 冲撞伤害现在只由两个场景碰撞箱决定：车头箱命中=完整速度伤害；车尾箱命中=rear_ram_damage_ratio；
#    不再用目标中心点角度推断车头/车侧/车尾，也不再额外生成脚本矩形作为攻击框。
# 5. 为避免高速薄目标漏判，每物理帧使用同一个场景 Shape2D 检查上一位置、中点、当前位置三个采样；
#    采样只复用用户调整后的形状与 Transform，不改变碰撞箱尺寸。低于 ram_min_speed_ratio 仍然完全没有冲撞伤害。
# 6. V151 多单位解卡/召唤可靠性、V150 队友碰撞例外、V147 自动驾驶基线、V144 手动驾驶、
#    V142 普通小弟 50% 生命与随机下车音效、Boss 1200HP/50% 三小弟等其它累计规则全部保持。
# ================================================================


# ================================================================
# V154 面包车顶人延迟解卡修复
# ================================================================
# 1. 用户实机反馈 V153 仍存在“车头一直顶着敌人，过一会才走开”。根因是 V151 的 _resolve_enemy_body_blocking()
#    用 move_and_slide() 后的“总位移长度 / 理论位移长度”判断是否被人物堵住。车辆顶着敌人或墙时，move_and_slide()
#    可能产生明显横向滑动；横向滑动会把总位移长度抬高，但沿车辆真正请求运动方向的推进其实接近 0，因此旧逻辑会延迟解卡。
# 2. V154 改为只计算 actual_displacement.dot(requested_velocity.normalized()) 的前向有效推进比例；横向蹭墙、沿敌人侧面滑动
#    不再算作“前进正常”。
# 3. 当前向推进低于 enemy_blocked_motion_ratio 时开始判定人物阻车；若低到该阈值约 45%（上限 18%）则视为硬阻塞，
#    不再等待完整 enemy_blocked_reverse_delay，立即进入撤离：敌人背后紧贴墙时优先 wall_escape，否则短 ram_reverse。
# 4. 多敌人且前方无墙时继续保留 V150/V151 的短暂穿越前排逻辑；伤害 cooldown、V153 场景车头/车尾攻击碰撞箱、
#    V151 召唤可靠性、V150 队友碰撞例外、V147 驾驶基线、V144 手动驾驶及其它累计规则全部保持不变。
# ================================================================



# ================================================================
# V155 新角色：若叶睦 / 墨提斯 + 薇欧拉
# ================================================================
# 一、若叶睦 / 墨提斯
# 1. 新增 res://scenes/characters/人物/若叶睦.tscn 与 res://scripts/characters/若叶睦.gd。
#    角色使用同一实体切换“睦 / 墨提斯”两个人格；当前人格显示在角色右侧状态区。
# 2. 睦人格：
#    - 默认经过一段时间自动切换为墨提斯；
#    - 短时间内累计受到较多真实生命伤害时可提前切换；
#    - 无普通攻击，核心技能为种黄瓜。AI 按冷却自动种植；玩家直接控制时右键种植。
# 3. 黄瓜花盆实现为 res://scripts/terrain/若叶睦_黄瓜花盆.gd：
#    - 初始只有花盆，随后生长为藤蔓；藤蔓成熟后可连续长出多个黄瓜；
#    - 睦本人进入花盆交互范围会减速，同时视为浇水，显著提高藤蔓/黄瓜成长速度；
#    - 有黄瓜时睦会吃掉一个：立即回复一部分最大生命，并获得一段持续回血；
#    - 同时允许多个花盆存在，超过上限时删除最旧花盆；角色死亡时清理自己的花盆。
# 4. 墨提斯人格：
#    - 每次受到真实生命伤害都会把“未受伤回归计时”清零；连续一段时间未受伤后切回睦；
#    - 墨提斯累计获得足够回血也会提前切回睦；
#    - 敌人在近距离时使用一次两拳的拳击，小幅击退；
#    - 敌人在中距离时使用吉他挥击，冷却明显更长、伤害与击退更高；
#    - 直接控制时左键根据鼠标距离自动选择近拳/吉他，右键固定尝试吉他，攻击方向完全使用玩家鼠标瞄准。
# 5. 这轮没有收到若叶睦正式人物图片，不得擅自猜官方图片路径；运行时使用程序化占位视觉，之后提供图片可只替换视觉层。
#
# 二、薇欧拉
# 6. 新增 res://scenes/characters/人物/薇欧拉.tscn 与 res://scripts/characters/薇欧拉.gd。
# 7. 普通攻击“照相”：
#    - 朝当前攻击方向生成三角形范围；范围内敌人受到低倍率伤害并短暂眩晕；
#    - 每个真正命中的敌人都会小幅增加薇欧拉的“舆论”。
# 8. 技能“录音”：
#    - 录音持续期间薇欧拉不能照相或使用火焰攻击；
#    - 录音期间每次受到真实生命伤害都会按实际生命损失增加舆论；
#    - 录音结束后一次性消耗当前舆论，从地图四周边界之外生成文字弹追击敌人；舆论越高，生成文字越多；单个文字伤害较低。
# 9. 文字弹实现为 res://scripts/effects/薇欧拉_文字弹.gd。每次文字真正命中后会记录该目标累计受到的文字次数。
# 10. 火焰终结：敌人同时满足“累计受到足够多文字命中 + 当前生命低于 50%”后成为可用火焰目标；
#     AI 会自动使用，直接控制时使用中键。火焰不是斩杀：只造成一次高倍率普通伤害，目标仍可存活。
# 11. 火焰命中位置留下 res://scripts/effects/薇欧拉_火场.gd，持续对范围内敌人造成低额灼烧；
#     投射物由 res://scripts/effects/薇欧拉_火焰弹.gd 实现。
# 12. 直接控制：薇欧拉左键照相、右键录音、中键只在满足文字命中与低血条件时发射火焰。
# 13. 这轮没有收到薇欧拉正式人物图片，不得擅自猜官方图片路径；运行时使用程序化占位视觉，之后只替换视觉资源即可。
# 14. translations.csv 新增若叶睦 / Mutsumi Wakaba、墨提斯 / Mortis、薇欧拉 / Viola 及本轮机制标签翻译。
# ================================================================


# ================================================================
# V156 若叶睦 / 墨提斯、薇欧拉正式图片接入 + 薇欧拉胜利/道具视觉
# ================================================================
# 1. 用户本轮正式提供人物/道具图片，V155 的“程序化占位视觉”规则作废；不得再隐藏正式人物图或恢复占位圆/字母牌。
# 2. 若叶睦图片固定接入：
#    - res://Images/characters/人物/若叶睦/若叶睦.png
#    - res://Images/characters/人物/若叶睦/墨提斯.png
#    scenes/characters/人物/若叶睦.tscn 初始 Image 使用若叶睦.png；人格切换时同一个 Graphics/Image 在两张图之间切换，
#    每次切换只调用 CharacterAutoFit.apply_visual_fit_only() 重拟合视觉，不改已经稳定的实体碰撞框。多人联机时 authority 同步人格视觉。
# 3. 薇欧拉图片固定接入：
#    - res://Images/characters/人物/薇欧拉/薇欧拉(4).png（普通）
#    - res://Images/characters/人物/薇欧拉/胜利.png（完全胜利）
#    - res://Images/characters/人物/薇欧拉/手机.png（照相攻击道具）
#    - res://Images/characters/人物/薇欧拉/录音器.png（录音技能道具）
# 4. 薇欧拉普通状态使用薇欧拉(4).png。每次照相攻击时，手机 Sprite2D 在人物身侧显示约 0.34s；左右攻击会切到对应侧。
#    录音技能整个持续时间内显示录音器 Sprite2D，录音结束/胜利时立即隐藏。手机/录音器只属于视觉，不参与碰撞与伤害范围。
# 5. 薇欧拉胜利判定参考凑企鹅现有“先见过敌人 -> 场上再无合法敌人 -> 进入不可逆胜利状态”的规则：
#    只有已经实际见过敌人后，后续扫描确认没有任何合法敌人才切换胜利图，避免角色单独处在选择/预览场景时误触发。
#    胜利时取消录音/当前攻击、隐藏手机与录音器、Graphics/Image 换成胜利.png；联机 authority 同步胜利视觉。
# 6. 正式人物图由 CharacterAutoFit 继续按项目统一人物尺度处理；运行时人格/胜利换图只重拟合视觉，不因为图片宽高差异修改碰撞。
# ================================================================

# ================================================================
# V157 薇欧拉火焰正式图片 + 录音文字弹幕表现重做
# ================================================================
# 1. 用户正式提供薇欧拉使用火焰时的图片，固定接入：
#    res://Images/characters/人物/薇欧拉/火焰.png
#    满足原有“文字命中次数 + 目标低于50%生命”条件并发动火焰时，Graphics/Image 临时切换到火焰.png；
#    默认约 0.72s 后恢复薇欧拉(4).png。若期间已经进入胜利状态，胜利.png 优先且不可被火焰计时恢复覆盖。
#    火焰姿态只改变视觉，不修改火焰弹伤害、火场灼烧、碰撞或终结条件。
# 2. 录音结束后的文字攻击改为“横排文字”：Label 始终保持世界水平，不再跟随飞行方向旋转；
#    文字仍从地图外出现，但每发生成时锁定目标当时的当前位置，按该瞬间方向直线射出，不再在飞行中持续追踪/转向敌人。
# 3. 文字弹不再同帧一起生成。每发之间加入很小的随机累计延迟，默认 0.010~0.028s，形成快速连续射出的弹幕感；
#    每发真正生成时会重新确认目标仍合法，目标失效则重新选择当前最近合法敌人。
# 4. 舆论转换文字数量明显提高：默认 opinion_per_text 从 7 降为 3，text_projectile_cap 从 20 提高到 42；
#    满 100 舆论时默认约生成 34 条文字，而不是旧版约 15 条。单发 text_damage_multiplier 维持原低伤害规则不变。
# 5. V156 的手机照相、录音器持续显示、胜利图切换规则继续保留；V157 不改变薇欧拉照相三角形、短眩晕、录音受伤涨舆论、
#    火焰高伤非斩杀以及火场持续灼烧的既有机制。
# ================================================================


# ================================================================
# V158 薇欧拉文字弹字号/朝向修正
# ================================================================
# 1. 用户实机反馈 V157 文字看起来比键盘侠文字大，而且所有文字视觉都保持屏幕水平，没有朝目标方向。
#    V157 “Label 始终保持世界水平”的规则在本版本明确作废；不得再恢复。
# 2. 键盘侠原场景 res://scenes/shooter/键盘文字.tscn 的文字参数为 font_size=34、outline_size=3；
#    但它继承 res://scenes/ball.tscn，Ball 根节点 scale=0.2，因此实际战场视觉尺寸约为上述参数的 0.2 倍。
# 3. 薇欧拉文字弹现在严格复用该实际尺度：文字视觉容器 scale=0.2，内部 Label 使用与键盘侠相同的
#    240x72 布局、font_size=34、outline_size=3。文字仍保持单行排版，不自动换行。
# 4. 每发生成时仍锁定目标“当时当前位置”，travel_direction = (aimed_position - start_position).normalized()；
#    之后不追踪目标、不拐弯。整颗文字弹 Node2D 的 rotation 固定为 travel_direction.angle()，
#    因而一整行文字会沿实际弹道朝向敌人，而不是所有文字保持屏幕水平。
# 5. V157 的快速随机连续发射（0.010~0.028s）、提高文字数量、单发低伤害、火焰图及其它薇欧拉规则全部保持不变。
# ================================================================

# ================================================================
# V159 若叶睦 / 墨提斯正式道具图片 + 浇水弧线
# ================================================================
# 1. 用户正式提供动作道具图片，固定接入：
#    res://Images/characters/人物/若叶睦/拳头.png、吉他.png、浇水壶.png。
# 2. 若叶睦.tscn 新增 PunchVisual、GuitarVisual、WateringCanVisual 三个 Sprite2D；只改视觉，不改变攻击判定/人格/碰撞。
# 3. 墨提斯双拳每拳短暂显示拳头图并按实际攻击方向旋转；吉他重击显示吉他图并做一次短挥舞。
# 4. 睦进入自己花盆的原“浇水”范围时显示浇水壶；花盆在右侧时镜像整个壶节点，让壶嘴 Marker 一起翻转并始终朝花盆。
# 5. 水流使用两层蓝色 Line2D：起点为 WateringCanVisual/Spout，终点为花盆顶部；以二次曲线采样形成弧形水流并实时更新。
#    离开范围、切换墨提斯或死亡时立即隐藏。水流仅为视觉，成长加速/减速继续使用 V155 原有玩法条件。
# ================================================================

# ================================================================
# V160 薇欧拉文字可读朝向 + 若叶睦浇水粒化 + 墨提斯动作重做
# ================================================================
# 1. 薇欧拉文字：V158“整颗文字弹直接 rotation = travel_direction.angle()”会导致向左/左上/左下飞行时
#    整行字上下颠倒或出现阅读方向反转。V160 将“弹道”和“文字视觉旋转”拆开：弹道仍锁定生成瞬间的敌人位置直线飞行，
#    文字视觉角度折叠到 [-90°, 90°]，不使用 flip_h，不镜像字形，始终保持中文/英文从左到右正常阅读；斜向目标时仍保留相同斜率。
# 2. 睦浇水：V159 连续双层蓝色 Line2D 水弧作废。现在浇水时以短间隔持续生成很多独立的短蓝色 Line2D 水滴，
#    每滴沿“壶嘴 -> 盆栽顶部”的二次贝塞尔弧线运动；水滴自身按轨迹切线旋转，抵达盆栽时立即删除。
# 3. 每个水滴抵达盆栽时直接复用 res://scripts/effects/umbrella_hit_burst.gd（伤心的男人雨滴撞伞同款白线反馈），
#    白线绑定盆栽节点并从水滴落点短促喷出。该反馈只属于视觉，不改变浇水成长倍率/角色减速/黄瓜回血。
# 4. 墨提斯拳击：V159 “拳头图在固定位置短暂显示”作废。每一拳现在先从身体旁出现，再沿真实攻击方向快速刺出到前方，
#    到达伸出极限时才结算该拳伤害/击退，然后拳头收回并淡出；两拳分别完整执行一次刺出动作。
# 5. 墨提斯吉他：V159 “原地小幅旋转吉他图”作废。吉他现在以角色为中心在较大半径上从攻击方向一侧抡到另一侧；
#    挥到攻击方向中段时结算高伤害/大击退，再继续完成后半段挥击并淡出。拳头/吉他图显示尺寸也提高，使动作成为攻击主体而非小图标。
# 6. V155~V159 的人格切换、黄瓜种植/成长/回血、墨提斯攻击数值、薇欧拉文字数量/随机短延迟/低单发伤害等规则保持不变。
# ================================================================

# ================================================================
# V161 薇欧拉火场自伤修复 + 墨提斯吉他握持方向修正
# ================================================================
# 1. 薇欧拉火场必须永远排除施放者本人：res://scripts/effects/薇欧拉_火场.gd 的敌我判断
#    现在先显式检查 target == owner。该规则独立于 Have_Team_Damage；即使开启友伤，
#    薇欧拉也不会被自己发射火焰后留下的火场持续灼烧。
#    其它同队角色是否受火场影响仍继续服从项目原友伤设置，不扩大为“火场永不伤友军”。
# 2. 墨提斯吉他原图的琴身位于局部 +Y、琴颈/琴头位于局部 -Y。
#    V160 挥击视觉使用 swing_angle + PI/2，导致琴头朝外、琴身靠近角色，握持方向反了。
#    V161 改为 swing_angle - PI/2，使琴颈/琴头靠近墨提斯、琴身朝挥击外侧；
#    吉他挥击轨迹、接触时机、伤害、击退、冷却均保持 V160 不变。
# ================================================================

# V162 若叶睦黄瓜盆栽正式图片/Shader成长：
# 1. 用户提供的 01_黄瓜盆栽_空盆土壤.png、02_黄瓜盆栽_刚种下幼苗.png、
#    03_黄瓜盆栽_茂盛藤蔓_无黄瓜.png、04_黄瓜本体.png 正式接入
#    res://Images/characters/人物/若叶睦/，不得再恢复程序化矩形/线条盆栽。
# 2. 新增 res://scenes/terrain/若叶睦_黄瓜花盆.tscn；若叶睦种植必须实例化该场景，
#    不再用脚本 .new() 生成无子节点的花盆。
# 3. 场景内 VisualRoot_可手动调整 的 position/scale/rotation 及其三个阶段 Sprite2D
#    都由 tscn 保存，脚本禁止覆盖这些 Transform。若图片与玩法原点错位，应直接在 2D 编辑器
#    调整 VisualRoot_可手动调整；黄瓜1~黄瓜6 也可在 黄瓜挂点_可手动调整 下逐根手调位置/角度/大小。
# 4. 新增 res://shaders/若叶睦_盆栽生长.gdshader。空盆->幼苗->茂盛藤蔓必须由 vine_progress
#    连续驱动 Shader reveal/opacity，以自下而上的噪声揭示 + 相邻阶段交叠完成过渡，禁止硬切 texture。
# 5. 黄瓜必须使用 04_黄瓜本体.png 作为独立 Sprite2D 挂在藤蔓预设挂点；每根黄瓜在自身
#    cucumber growth 后半段开始通过同一 Shader 连续长出，成熟后保持。吃掉黄瓜时对应末端视觉
#    平滑退场；默认一藤蔓 3 根，但场景预留 6 个可手调挂点以兼容 Inspector 最大值。
# 6. V160 的多条蓝色浇水滴 + 到盆栽时复用 umbrella_hit_burst 白线规则继续保留，本轮不改。


# ================================================================
# V163 墨提斯图片实碰撞 + 吉他拖尾 + 拳头缩小
# ================================================================
# 1. V155~V162 中墨提斯拳头/吉他的攻击数值、双拳节奏、吉他冷却、击退与 V161 吉他握持方向继续保留。
# 2. V160 的“拳头到达伸出极限时结算、吉他挥到攻击方向中段时结算”时机继续保留，但旧的攻击判定方式作废：
#    - 拳头不再用 mortis_punch_range 推导出的圆形范围直接决定命中；
#    - 吉他不再用 mortis_guitar_max_range + mortis_guitar_arc_degrees 的距离/扇形直接决定命中。
# 3. 拳头.png 与 吉他.png 现在在角色 _ready() 时读取 Texture2D 图像 Alpha，通过 BitMap.create_from_image_alpha()
#    + opaque_to_polygons() + Geometry2D.decompose_polygon_in_convex() 生成缓存的凸多边形。真正结算攻击时，使用当前
#    PunchVisual / GuitarVisual 的 global_transform 对这些多边形做 PhysicsDirectSpaceState2D.intersect_shape() 查询，
#    只与 hurtbox 所在 collision layer 2 的 Area2D 相交；因此透明像素不再属于攻击范围，图片当前的位置/旋转/缩放就是实际攻击碰撞。
# 4. 如果某个平台/导入状态下 Texture2D.get_image() 无法建立 Alpha 多边形，为避免角色完全失去攻击，才允许临时回退到 V162 的
#    旧圆形/扇形判定，并输出 warning；正常资源可读时不得主动走回退判定。
# 5. 拳头视觉由 scale 0.17 调小为默认 0.145；图片碰撞同步使用该 Sprite2D 的真实 global_transform，因此视觉缩小后实际拳击碰撞也同步缩小。
# 6. 吉他新增 GuitarTrailRoot。挥击过程中按短间隔复制当前吉他 Sprite2D 的纹理、位置、旋转和缩放生成残影，快速淡出形成拖尾；
#    拖尾纯视觉，不附带碰撞、不追加伤害、不改变一次吉他挥击最多对同一目标结算一次的规则。
# 7. mortis_guitar_min_range / max_range / arc_degrees 继续可用于 AI 选招与“图片碰撞不可用”时的安全回退，不代表正常攻击的实际碰撞边界。
# ================================================================


# ================================================================
# V164 墨提斯 AI 攻击启动距离改为实际图片碰撞预检测
# ================================================================
# 1. 用户实机反馈：V163 虽然真正“命中”已经使用拳头/吉他图片 Alpha 碰撞，但 AI “决定是否开始攻击”仍沿用
#    mortis_punch_range / mortis_guitar_min_range / mortis_guitar_max_range 的角色中心距离，因此会在实际图片接触不到敌人时提前空挥。
# 2. V164 起，正常图片碰撞可用时，墨提斯 AI 的攻击启动条件也改为 V163 同一套图片 Alpha 碰撞：
#    - 拳头：把拳头预放到每一拳真正结算伤害的伸出极限姿态，按拳头.png Alpha 多边形查询当前目标 Hurtbox；
#      两拳任意一个结算姿态能实际碰到目标，才允许启动双拳。
#    - 吉他：把吉他预放到挥至攻击方向中段、真正结算伤害的姿态，按吉他.png Alpha 多边形查询当前目标 Hurtbox；
#      该姿态确实与目标相交，才允许启动吉他挥击。
# 3. 因此“攻击检测范围”和“真正伤害碰撞”现在共用同一张图片、同一缩放、同一攻击结算姿态；敌人尚未进入实际可命中范围时，
#    墨提斯不会消耗冷却或原地空挥，而是继续执行原移动/追敌逻辑靠近目标。
# 4. 拳头 V160 遗留的每拳随机 ±7px 横向抖动在本版本移除，避免预检测认为可命中、实际攻击帧却被随机偏移挪开；
#    两拳仍保留原 -0.08 / +0.08 弧度的左右方向差、双拳节奏、伤害与击退。
# 5. mortis_punch_range / mortis_guitar_min_range / mortis_guitar_max_range 只在图片 Alpha 碰撞构建失败时作为安全回退；
#    正常项目不得再用这些纯距离值决定 AI 是否出招。玩家直接控制时仍允许主动挥空，不强制要求鼠标方向已有敌人。
# ================================================================

# ================================================================
# V165 墨提斯也可吃黄瓜
# ================================================================
# 1. V155 的“有黄瓜时睦会吃掉一个”扩展为：若叶睦与墨提斯两个人格都可以吃自己花盆里已经成熟的黄瓜。
# 2. res://scripts/terrain/若叶睦_黄瓜花盆.gd 的浇水条件不变：只有睦人格进入 interaction_radius 才减速并提供
#    watering_growth_multiplier；墨提斯进入花盆范围不会浇水、不会获得浇水成长加速，也不会触发浇水壶/水滴视觉。
# 3. 吃黄瓜条件改为：拥有者处于睦或墨提斯人格、进入 interaction_radius、花盆已有成熟黄瓜、角色未满血。
#    吃掉后仍使用同一份 instant_heal_ratio + hot_heal_ratio / hot_duration，并消耗一根成熟黄瓜。
# 4. 墨提斯吃黄瓜产生的即时回血和持续回血都继续通过若叶睦.gd 的 heal() 结算，因此会正常累计
#    mortis_heal_return_ratio；累计回血达到原阈值时仍按 V155 规则提前切回睦，不为墨提斯建立独立回血旁路。
# 5. V163 图片实碰撞、吉他拖尾、拳头缩小与 V164 实际攻击范围触发规则保持不变。
# ================================================================


# ================================================================
# V166 薇欧拉 / 若叶睦 / 墨提斯角色音效接入
# ================================================================
# 1. 用户提供的五个音频正式按角色目录接入，不得放到 audio/ 根目录或创建同义目录：
#    - res://audio/characters/薇欧拉/拍照.mp3
#    - res://audio/characters/薇欧拉/开启录音器_[cut_0sec].mp3
#    - res://audio/characters/若叶睦/放置_[cut_0sec].mp3
#    - res://audio/characters/若叶睦/电吉他.mp3
#    - res://audio/characters/若叶睦/浇水_[cut_3sec].mp3
# 2. 薇欧拉每次真正执行照相时播放“拍照”；开始录音、录音器图显示时播放“开启录音器”。
#    照相三角形真正对目标结算成功，以及文字弹 receive_spatial_damage() 真正返回成功时，播放项目标准
#    res://audio/sfx/physics/balls_hit1.sfxr 碰撞伤害音。文字被格挡/未造成实际伤害时不得伪造命中音或累计文字命中。
# 3. 墨提斯每一拳开始刺出时复用拳击手“拳击手_挥拳.mp3”，每个实际命中的目标复用
#    “拳击手_命中.mp3”；音效触发必须跟随 V163 图片 Alpha 实碰撞的实际结果，不得仅因进入攻击动画就播放命中声。
# 4. 墨提斯吉他开始挥舞时复用矿工“挥舞.mp3”；吉他图片碰撞实际命中目标时播放本轮“电吉他.mp3”。
#    V163 吉他拖尾、V164 实际范围启动、原伤害/击退/冷却保持不变。
# 5. 若叶睦成功生成黄瓜花盆后播放“放置”；只有睦人格正在自己花盆 interaction_radius 内持续浇水时，
#    “浇水_[cut_3sec].mp3”以 AudioStreamMP3.loop 循环。离开范围、切换墨提斯或死亡时必须立即 stop，
#    不能让隐藏浇水壶后声音继续播放。墨提斯仍不会浇水，但 V165 吃黄瓜规则保持不变。
# 6. 上述角色音效均使用 AudioStreamPlayer2D、GameplayRecord 总线（存在时）并由 authority RPC 同步表现；
#    角色专属音效不得为接入方便而塞入全局 audios.tscn，也不得改动拳击手/矿工原音频文件。
# ================================================================

# ================================================================
# V167 若叶睦浇水蓝条残留修复
# ================================================================
# 1. 用户实机反馈：V160 起的短蓝色 Line2D 水滴偶发有几条不会消失。根因是旧实现把每滴水直接
#    add_child 到 get_tree().current_scene；水滴生命周期依赖若叶睦.gd 的 _update_existing_water_drops()
#    持续推进并在到达终点时 queue_free()。若角色被移除、authority/tick 中断，场景根中的水滴可能失去更新者而成为孤儿。
# 2. V167 起，每滴水改为若叶睦节点自己的 top_level Line2D 子节点：top_level 保持它继续按世界坐标飞行、
#    不继承角色移动；同时角色节点被释放时，Godot 会自动连同这些水滴子节点一起释放，不再把水滴挂在 current_scene 根部。
# 3. 每滴水创建时额外绑定独立安全 Tween，最长在本滴正常 travel duration + 0.20s 后自行 queue_free；
#    即使角色物理 tick 或联机 authority 意外中断，也不会永久留下蓝条。
# 4. 一旦 _find_watering_target_pot() 返回 null（离开花盆范围、切到墨提斯、死亡/失去有效浇水条件），
#    本版本立即 _clear_watering_drops()，不再让旧水滴继续飞完。_hide_watering_visual() 同样强制清理。
# 5. _clear_watering_drops() 除了清空跟踪数组，还扫描本角色直系、名称以“若叶睦_浇水滴”开头的 Line2D 兜底回收，
#    只处理本角色自己的子节点，不影响其它若叶睦实例。V166 浇水循环音效、V165 黄瓜、V163~V164 墨提斯攻击规则均保持不变。
# ================================================================

# ================================================================
# V168 薇欧拉语音 / 火焰倒计时无敌前摇 / 胜利笑声循环
# ================================================================
# 1. 用户提供的五段薇欧拉语音固定放在现有角色音频目录，保持文件名与扩展名大小写，不得改名或移到 audio 根目录：
#    - res://audio/characters/薇欧拉/薇欧拉轻笑.MP3
#    - res://audio/characters/薇欧拉/薇欧拉倒计时.MP3
#    - res://audio/characters/薇欧拉/薇欧拉开.mp3
#    - res://audio/characters/薇欧拉/薇欧拉笑开始.MP3
#    - res://audio/characters/薇欧拉/薇欧拉笑循环.MP3
# 2. 录制语音：开始录音时保留 V166 的“开启录音器”道具音，并同时播放一次“薇欧拉轻笑”；
#    正常结束/关闭录音器时再次播放一次“薇欧拉轻笑”。胜利状态强制中断录音时不叠加关闭轻笑，避免与胜利笑声同时重叠。
# 3. 火焰终结不再按下/AI 选中后立即生成火焰弹：进入火焰前摇时立刻显示 res://Images/characters/人物/薇欧拉/火焰.png，
#    停止旧 FirePoseTimer，并在整段“薇欧拉倒计时.MP3”播放期间持续保持火焰图片。authority 端优先等待
#    AudioStreamPlayer2D.finished 后发射；同时用 AudioStream.get_length()（当前附件约 8.673 秒）作为计时兜底，读取异常时才回退
#    8.673 秒，禁止另写与音频不一致的短倒计时。stop() 不会触发 finished，因此取消/胜利中断不会误发射。
# 4. 火焰倒计时期间薇欧拉处于无敌状态：hitbox 的 can_receive_hit_contact / 旧 can_receive_hit_from、
#    receive_positional_damage、receive_spatial_damage、take_damage 均拒绝伤害；on_actual_health_damage_received 再兜底恢复
#    绕过公共伤害入口直接修改 health 的旧脚本伤害。倒计时结束、取消或进入胜利状态后必须立刻解除无敌。
# 5. 倒计时自然结束时，同一帧播放“薇欧拉开.mp3”并生成原有薇欧拉火焰弹；伤害倍率、目标条件、火场半径/持续灼烧等
#    V155~V167 既有数值不变。火焰冷却和目标文字命中计数只在实际发射时结算，不得因为 8.673 秒前摇让冷却提前跑完。
#    锁定目标若在前摇中失效，可改选仍满足火焰条件的合法目标；完全没有合法目标时取消发射并恢复普通图片。
# 6. 前摇期间禁止照相、开始录音或再次使用火焰；AI/玩家原移动系统不被强制改写。发射后继续使用 fire_pose_duration
#    短暂保持火焰图，再恢复普通图；胜利图仍拥有最高视觉优先级。
# 7. 胜利语音：进入不可逆胜利状态时先播放一次“薇欧拉笑开始.MP3”；AudioStreamPlayer2D.finished 发出后，
#    把“薇欧拉笑循环.MP3”的复制资源设为 AudioStreamMP3.loop=true 并开始播放，之后持续循环到角色离树或胜利状态被显式取消。
#    两段胜利语音使用同一个角色子 AudioStreamPlayer2D，确保“笑开始”不会与“笑循环”重叠。
# 8. 火焰倒计时与胜利语音使用薇欧拉子 AudioStreamPlayer2D、GameplayRecord 总线（存在时）；火焰开始/结束视觉通过
#    authority reliable RPC 同步。V166 拍照/录音器/碰撞伤害音与 V157~V161 火焰图片、火场不自伤规则继续保留。
# ================================================================

# ================================================================
# V169 若叶睦阵亡演出 + 薇欧拉录音/拍照/音量修正
# ================================================================
# 1. 用户提供若叶睦阵亡图片，保持附件原文件名并正式接入：
#    res://Images/characters/人物/若叶睦/ChatGPT_Image_2026年8月31日_00_59_29.png
#    若叶睦/墨提斯生命归零进入 State.Die 时，必须先隐藏拳头、吉他、浇水壶与残余水滴，
#    Graphics/Image 切换到该阵亡图，再等待死亡音播放完成后才 queue_free；不得恢复“进入 Die 同帧直接消失”。
# 2. 本轮用户未提供新的若叶睦专属阵亡音频，因此 V169 暂时复用项目现有
#    res://audio/system/dead_bell.wav（DeadBell）。死亡播放器使用 GameplayRecord（存在时）和 2D 定位；
#    AudioStreamPlayer2D.finished 是正常删除触发，AudioStream.get_length()+0.15s 只作极端音频后端未发 finished 的保险。
# 3. 为兼容 ball.gd 的 V9 普通人物“无死亡动画立即释放”规则，若叶睦.gd 的 _has_death_animation() 在 V169
#    明确返回 true，由角色自己的 Die() 完成阵亡图/音效/最终删除；远端通过 authority reliable RPC 同步阵亡图与声音。
# 4. V168 “开始录音也播放轻笑”在本版本作废：薇欧拉开始录音只播放原有录音器开启音；
#    只有录音自然结束、真正关闭录音器时播放一次“薇欧拉轻笑.MP3”。胜利/火焰强制中断仍不额外播放关闭轻笑。
# 5. 录音期间，录音器下方必须同时显示红色“● REC”提示；录音结束、火焰前摇、胜利或其它强制隐藏录音器时，
#    REC 提示必须同步隐藏，不允许只剩红字悬在角色旁。
# 6. V169 为薇欧拉所有本角色音效/语音统一增加默认 +6 dB 可调增益 viola_audio_gain_db；
#    包括拍照、录音器、碰撞反馈、轻笑、倒计时、“开”和胜利笑声。不得通过修改源 MP3 文件本身来增大音量。
# 7. 薇欧拉拍照三角形的 apex/origin 从角色 global_position 改为 Graphics/手机 Sprite2D 的实际 global_position；
#    快门音也从该手机位置发出。camera_range、camera_end_width、伤害、眩晕与舆论收益保持原值。
# 8. V168 火焰倒计时无敌、倒计时结束“开”并攻击、胜利笑开始->笑循环，以及 V166~V167 其它音效/浇水规则继续保留。
# ================================================================


# ================================================================
# V170 若叶睦 / 墨提斯角色语音接入
# ================================================================
# 1. 用户提供的五段若叶睦语音正式放入现有角色音频目录，保持附件原文件名与扩展名大小写：
#    - res://audio/characters/若叶睦/若叶睦找我吗.MP3
#    - res://audio/characters/若叶睦/若叶睦真的吗.MP3
#    - res://audio/characters/若叶睦/若叶睦全都不会.MP3
#    - res://audio/characters/若叶睦/若叶睦哼1.MP3
#    - res://audio/characters/若叶睦/若叶睦尖叫.MP3
# 2. 每次人格真正从若叶睦切到墨提斯时播放一次“若叶睦找我吗”；每次墨提斯真正切回若叶睦时播放一次
#    “若叶睦真的吗”。初始出生为若叶睦不视为人格切换，不得在 _ready() 中误播“真的吗”。
# 3. 墨提斯吉他只有在 V163 图片 Alpha 实碰撞真正对至少一个目标 receive_spatial_damage() 成功后，
#    才播放“若叶睦全都不会”。一次吉他挥击即使同时打中多个目标也只播一次角色语音；原矿工挥舞音、
#    电吉他命中音、伤害、击退、拖尾和 V164 实际攻击范围启动规则全部保留。
# 4. 若叶睦每次从“未浇水”进入自己花盆的连续浇水状态时播放一次“若叶睦哼1”；V166 的
#    浇水_[cut_3sec].mp3 仍在整个浇水过程中循环，哼声不做 0.758 秒无缝死循环，避免短语音机械重复。
#    离开花盆再重新进入，可在新一轮浇水开始时再次播放。
# 5. V169 临时复用 dead_bell.wav 的若叶睦阵亡音规则在本版本作废。死亡进入 State.Die 后仍先切换 V169
#    阵亡图片并停留场上，但阵亡播放器改为“若叶睦尖叫.MP3”；authority 必须等待该语音自然 finished
#    后才 queue_free。AudioStream.get_length()+0.15s 只保留为音频后端异常未发 finished 时的保险。
# 6. 上述人格/攻击/浇花语音继续通过角色的 2D 定位音频和 GameplayRecord 总线（存在时）同步；
#    不得因为加入语音而移动现有资源目录、重命名中文文件或恢复 audio 根目录散放。
# ================================================================


# ================================================================
# V171 薇欧拉 REC/胜利语音修正 + 若叶睦盆栽缺水枯萎 + 多余状态文字清理
# ================================================================
# 1. 薇欧拉录音器下方唯一保留的额外文字为红色“● REC”。V169 的 RECIndicator 继续使用，
#    但相对录音器的 Y 偏移由 72px 上移到 38px，使提示紧贴录音器下方；录音结束/火焰/胜利时仍同步隐藏。
# 2. 薇欧拉、若叶睦脚本中的 side_status 临时/常驻文字全部取消：不再显示“照相”“录音中”“火焰终结”“舆论”、
#    “种黄瓜”“黄瓜回血”“人格”等额外状态文字。薇欧拉的文字弹属于攻击实体，不在本条删除范围；唯一角色附加 UI 文字为 ● REC。
# 3. V168 胜利语音强化为不可重复的两阶段：同一个薇欧拉实例第一次进入胜利只播放一次“薇欧拉笑开始.MP3”，
#    并强制该复制流 loop=false；自然 finished 后立即切到“薇欧拉笑循环.MP3”的复制流并设置 loop=true。
#    _victory_intro_played_once 一经置 true 不因重复胜利视觉/RPC 或停止函数而重置，因此之后只允许继续/重新进入循环段，
#    禁止再次播放“笑开始”。Godot 对 loop=true 的音频不会在每轮循环末尾发 finished，本版本依赖该行为持续循环。
# 4. 用户提供 res://Images/characters/人物/若叶睦/枯萎.png。盆栽场景新增 VisualRoot_可手动调整/枯萎藤蔓，
#    与健康藤蔓使用同一可手调视觉根，并默认复制健康藤蔓的 position/scale；需要美术微调时直接改 tscn，不在脚本硬改 Transform。
# 5. “完全长大”定义为 vine_progress 完成且成熟黄瓜达到 max_cucumbers。达到该状态后，如果若叶睦持续不在本盆浇水，
#    开始累计缺水时间；任意一帧重新浇水会立即清零。默认连续 10s 不浇水进入不可逆枯萎，可由若叶睦 Inspector 的
#    pot_wither_after_unwatered 调整。枯萎开始后停止继续生长/食用，并把健康藤蔓平滑交叉淡变为枯萎图。
# 6. 枯萎后成熟黄瓜按默认每 1.0s 一根从末端开始减少并沿原 Shader 平滑退场；间隔由
#    pot_wither_cucumber_interval 调整。最后一根黄瓜消失后默认再等待 2.0s，整盆 queue_free；延迟由
#    pot_wither_disappear_delay 调整。V165 墨提斯可吃健康黄瓜、V166~V170 浇水/语音等规则在未枯萎阶段保持不变。
# ================================================================

# ================================================================
# V172 墨提斯吃黄瓜可靠性修复 + 若叶睦死亡颤抖
# ================================================================
# 1. 用户实机反馈：V165~V171 虽然花盆脚本写了 is_mutsumi || is_mortis，但墨提斯状态仍可能出现成熟黄瓜不被吃掉。
#    V172 不再让花盆通过人格方法“反向猜测谁能吃”：吃黄瓜改为若叶睦角色 authority 在每个物理帧主动遍历自己拥有的花盆，
#    调用 try_consume_cucumber_by(self)。花盆只验证 owner_instance_id、interaction_radius、成熟黄瓜数量、枯萎状态与 eat_guard。
# 2. 若叶睦与墨提斯因此使用完全相同的 consume_cucumber_from_pot() 回复入口；只要未满血、进入自己健康花盆交互范围且存在成熟黄瓜，
#    两个人格都能吃。墨提斯所得即时/持续回复仍走 heal()，继续累计 mortis_heal_return_ratio 并可按既有规则切回若叶睦。
# 3. 每个角色物理帧最多主动吃一根黄瓜；花盆成功被吃后立即减少 cucumber_count、启动 eat_guard，并重置“完全成熟后缺水枯萎”计时。
#    浇水仍严格只属于若叶睦人格，墨提斯不会获得浇水减速、成长加速、浇水壶、水滴或浇水循环音效。
# 4. V170 的死亡流程继续保持“切阵亡图 -> 播放若叶睦尖叫.MP3 -> 尖叫 finished 后才真正 queue_free”，
#    V172 在整个尖叫等待期间增加阵亡图快速颤抖。颤抖只修改 Graphics/Image 的 Sprite2D.offset，不移动角色 global_position、
#    hitbox/hurtbox 或其它物理节点，因此不会在死亡演出中改变碰撞位置。
# 5. 颤抖默认幅度 6px、单步 0.045s，可由 Inspector 的 death_tremble_amplitude / death_tremble_interval 调整；
#    authority 和远端视觉都会颤抖，尖叫结束、角色离树或最终删除时必须 kill Tween 并恢复原 offset，禁止残留偏移。
# ================================================================


# ================================================================
# V173 若叶睦盆栽节奏调整 + 黄瓜进食演出 + 枯萎花盆碎裂
# ================================================================
# 1. 用户实机反馈 V172 放盆栽冷却过短、黄瓜生成过快、完全成熟后的枯萎过程过慢。
#    V173 默认 plant_cooldown 从 6.5s 提高到 12.0s；cucumber_growth_time 从 5.0s 提高到 10.0s。
#    watering_growth_multiplier 继续保留，因此持续浇水仍会明显加速，但不再几秒内快速刷满整盆黄瓜。
# 2. 完全成熟后的连续缺水枯萎阈值由 10.0s 缩短为 5.0s；枯萎后的黄瓜消失间隔改为 0.40s，
#    最后一根消失后的碎盆等待改为 0.65s。以上均仍由 Inspector 对应参数可调。
# 3. 新增若叶睦角色音效：res://audio/characters/若叶睦/eat1.mp3、eat2.mp3、eat3.mp3、碎裂.mp3。
#    吃一根黄瓜时不是瞬间完成：花盆先扣掉一根并由角色进入 _cucumber_eating 锁定状态，期间不能再拿第二根；
#    一根黄瓜 Sprite 在角色嘴边上下抖动，随机播放 3~5 次 eat1/eat2/eat3，每次间隔约 0.12~0.20s。
# 4. 吃黄瓜期间持续从黄瓜原贴图随机裁取小方块作为碎屑，向下散落并渐隐；不是使用通用方块颜色模拟。
#    演出默认约 1.15s，演出结束才真正执行即时回血和 HOT。墨提斯与若叶睦共用该演出，且 _cucumber_eating
#    是跨花盆的角色级锁，因此多个重叠盆栽也不能在同一轮进食期间继续拿黄瓜。
# 5. 枯萎盆栽黄瓜全部消失并经过 disappear delay 后，不再直接 queue_free。先播放“碎裂.mp3”，把当前枯萎盆栽
#    贴图按 3x2 切成 6 瓣视觉碎片；每瓣先向上抛，再受模拟重力式 Tween 向下掉出画面并旋转/渐隐，最后释放。
#    碎裂音播放器挂在 current_scene，避免盆栽本体开始消失动画后截断音效。
# 6. V172 墨提斯主动检查花盆的吃黄瓜可靠性修复继续保留；本版本只把“成功吃”的结算改为有时长的进食演出。
# ================================================================

# ================================================================
# V174 若叶睦盆栽成熟定义修正 + 吃黄瓜视觉增强
# ================================================================
# 1. 用户明确“完全成熟”不是黄瓜长满，而是藤蔓已经到达可以开始出现黄瓜的状态。
#    V171/V173 中“vine_progress 完成且 cucumber_count 达到 max_cucumbers 才算完全成熟”的定义在本版本作废。
#    从 V174 起，只要 vine_progress >= 0.999（即进入黄瓜可生成阶段）就开始适用缺水枯萎计时；是否已有黄瓜、
#    当前有几根黄瓜、黄瓜是否被吃掉，都不得让藤蔓退回“未成熟”。重新浇水仍会立即清零尚未完成的缺水计时。
# 2. 因上述定义变化，成功吃掉一根黄瓜不再重置 _fully_grown_dry_elapsed；枯萎计时只由成熟藤蔓是否持续浇水决定。
# 3. V173 嘴边黄瓜视觉偏小。V174 默认 cucumber_mouth_visual_size 从 30px 提高到 48px，Inspector 可调范围扩到 16~80px；
#    仍保持嘴边上下抖动、进食期间不可拿第二根、演出结束后才结算回血等 V173 规则。
# 4. V173 黄瓜碎屑不够明显。V174 默认每次碎屑 burst 从 4 提高到 6，并显著放大随机裁切方块；碎屑 z_index 提高到 50，
#    使用 CanvasItem.TEXTURE_FILTER_NEAREST 保持方块边缘清晰，延长下落/渐隐时间并扩大下落距离。碎屑仍必须直接裁自
#    res://Images/characters/人物/若叶睦/04_黄瓜本体.png，而不是纯色替代物。
# ================================================================

# ================================================================
# V175 若叶睦枯萎时间恢复 10s + 手动训练“血”投射/表面血迹测试
# ================================================================
# 1. 用户要求 V174 的成熟定义继续保持：vine_progress >= 0.999（已经进入可生成黄瓜阶段）即视为完全成熟；
#    但 V173 将缺水枯萎阈值缩到 5s 过快。本版本 pot_wither_after_unwatered / wither_after_unwatered
#    默认值恢复为 10.0s。只有重新浇水会重置尚未完成的缺水计时；黄瓜数量仍不参与“是否成熟”的判断。
# 2. 设置 -> 手动训练 -> 攻击目录新增 special://blood，显示名固定为“血”。它是纯视觉测试攻击，当前不造成角色伤害；
#    右键按住时仍复用 Manual_Attack_Interval 连发，并使用手动训练现有平滑瞄准方向，所以有目标时朝对应角色方向发射，
#    无目标时沿自由瞄准方向发射。当前飞行体按用户要求先使用红色小方块占位，不新增图片资源。
# 3. 血液飞行同时维护 ground_position 与独立 height：ground_position 沿瞄准方向前进，height 由 upward speed/gravity
#    形成先上升后下降的抛物线；屏幕显示位置 = ground_position + (0,-height)。height 回落到 0 且未撞障碍时，
#    在该 ground_position 生成不规则扁平地面血迹，并附带少量卫星血点。
# 4. 每个 physics tick 都用 PhysicsDirectSpaceState2D.intersect_ray() 检查本帧 ground_position 位移；查询排除所有 ball，
#    只把 TileMapLayer / StaticBody2D / AnimatableBody2D / wall_hit_surface 当成障碍表面。命中后使用返回的世界 position 与 normal
#    把血迹贴到障碍物；障碍节点可作为父节点时直接挂到该节点坐标系，移动障碍也会带着血迹一起移动。
# 5. 障碍物血迹禁止做成单层平片：V175 以“暗色贴面底层 + 沿表面法线凸出的主体 + 更外侧亮面 + 多颗凸起血珠”分层，
#    并用碰撞 normal 定向，使局部 +Y 朝表面外法线；这是当前无血液贴图阶段的体积感实现。地面血迹保持扁平，以符合落地映射。
# 6. 血液飞行/血迹节点加入 BattleTransient，重置战斗时会统一清理；血迹默认 24s 后渐隐释放，相关飞行速度、上抛速度、
#    重力、小方块尺寸、地面血迹半径、墙面血迹宽度/厚度、血迹寿命均暴露在 ManualTrainingController Inspector 便于测试。
# ================================================================


# ================================================================
# V176 手动训练血液视觉重做 + 障碍物贴面修复
# ================================================================
# 1. 用户实机反馈 V175 的血液仍过于几何化：飞行体像红色方块，地面血迹大多是相似椭圆；同时墙面血迹几乎没有体积感，
#    更重要的是视觉堆在障碍物前方，没有真正“映射”到障碍物表面。本版本只重做手动训练 special://blood 的视觉与贴面，
#    不改变其“当前纯测试、不造成角色伤害”的规则。
# 2. 飞行血不再使用 _blood_square_polygon() 红方块。每发改为朝运动方向拉长的不规则血滴主体 + 暗芯 + 小高光，并随机附带
#    2~4 颗落后的拖尾小滴；仍保持 V175 ground_position + height 的抛物线飞行，因此“飞出去后落地”的运动规则不变。
# 3. 地面血迹不再使用单一 irregular ellipse 模板。每次生成都会随机主血池轮廓、渗边、1~3 条顺入射方向的拖抹、
#    5~10 个随机卫星血滴/尖锐飞溅，半径、长宽、角度与数量均独立变化，使连续射击不会出现大量近似复制的血斑。
# 4. V175 墙血定位使用 holder.global_position = hit_position + normal * 0.7；intersect_ray() 返回的 normal 指向碰撞表面外侧，
#    因此该写法会把整块血向墙外推，造成“堆在障碍物之前”。V176 改为 hit_position - normal * inset，把贴面主体压进碰撞面内部，
#    并继续把血迹节点作为碰撞障碍物的子节点；移动障碍仍会携带血迹移动。blood_wall_surface_inset 暴露到 Inspector 可调。
# 5. 墙面血迹分为真正位于障碍物内/表面的渗色底、主贴面血斑、沿切线的擦痕，以及只少量沿 +normal 向外凸出的凝血块、
#    高光和独立血珠。holder 使用较高 absolute z_index 保证贴面层能覆盖多数障碍物图片；“立体感”只来自表面外的小范围凸出，
#    不再把整个血迹整体放在墙前。入射方向在墙切线上的分量还会生成额外擦痕，强化撞上表面的方向感。
# 6. 墙面检测仍使用 PhysicsDirectSpaceState2D.intersect_ray() 的世界 position/normal，并继续排除 ball；TileMapLayer、StaticBody2D、
#    AnimatableBody2D 和显式 wall_hit_surface 障碍规则保持 V175 不变。所有血液节点仍加入 BattleTransient 并按 blood_decal_lifetime 渐隐。
# ================================================================

# ================================================================
# V177 手动训练血液二次重做：真实接触时机 + 自然液滴 + 地面/墙面血迹优化
# ================================================================
# 1. V175/V176 的墙碰撞射线沿 ground_position（血滴在地面的投影）检查，而飞行视觉实际位置还额外减去 height；
#    因此当血滴仍在空中时，地面投影可能已经跨过墙，造成“血还没真正碰到障碍就消失并变成墙血”。V177 作废该方式：
#    每个 physics tick 先计算 previous_screen/next_screen（包含 height 的真实显示位置），只沿这段真实屏幕轨迹做 intersect_ray()。
# 2. 为了让“碰到”在视觉上准确，射线从血滴前端而不是中心发出：前端命中 result.position 后，把血滴中心停在
#    hit_position - velocity_dir * front_offset，使液滴鼻尖正好接触表面；至少保留一个 physics tick 后才转成墙面血迹。
#    因此禁止在未来轨迹被射线预测到时提前 queue_free 飞行血。
# 3. 飞行血改为前圆后尖的 teardrop 液滴，按真实屏幕速度（前进 + 上抛/下落）旋转，并仅保留 1~3 颗不规则分裂小滴；
#    默认 projectile size 由 9px 降为 7.5px，避免像粗大的红色几何子弹。
# 4. 地面血迹改为 2~4 个随机偏移血池融合、透明渗边、主拖抹/断裂拖痕，以及 8~15 个分成近圈大滴与远圈小滴的卫星飞溅；
#    每发尺寸、长宽、位置、角度与尖刺独立随机，禁止重新退回大量近似椭圆复制。
# 5. 墙面贴附以 intersect_ray() 的真实 hit position 为基准。V176 默认 blood_wall_surface_inset=4.5px 偏深，V177 降为 1.5px；
#    主 stain 跨在碰撞边界附近，仅凝血块/血珠沿外法线少量凸起。血迹仍作为 collider 子节点，从而真正随障碍物移动。
# 6. 墙血加入沿切线的撞击放射飞溅、中心凝血体积，以及把世界 Vector2.DOWN 转入墙血局部坐标后的重力流挂；
#    目的为表现“附着在表面并受重力影响”的血，而不是平面贴纸或整坨悬浮在障碍物前。
# ================================================================


# ================================================================
# V178 墨提斯击杀血液：拳头小力 / 吉他大力大扩散 / 统一朝敌人方向
# ================================================================
# 1. 用户要求若叶睦的墨提斯人格在“真正击杀”目标时产生血液；普通命中不额外喷出本条击杀血。
#    V178 在拳头/吉他 receive_spatial_damage() 前记录目标生命，只有伤害成功且本次把 health 从 >0 打到 <=0 时触发。
# 2. 击杀血主方向必须固定为“若叶睦/墨提斯 -> 被击杀敌人”的方向。所有随机扩散只允许围绕这个主轴形成窄锥形，
#    禁止出现平均方向无关、向攻击者身后大面积喷射的 360 度随机血。
# 3. 拳头击杀默认是小力效果：5 个血滴、中心扩散约 6.5 度、基础力度 170；血滴数量、距离与落地血迹都保持克制。
#    吉他击杀默认明显更强：11 个血滴、中心扩散约 14 度、基础力度 285；但脚本对扩散硬限制 <=18 度、力度 <=360，
#    因此即使 Inspector 调大，也不会形成过大的全屏喷射。以上参数可在若叶睦 Inspector 的“墨提斯 - 击杀血液”微调。
# 4. 新增 res://scripts/effects/若叶睦_击杀血液.gd，仅负责击杀血视觉，不造成二次伤害。
#    飞行血沿 V177 的“真实屏幕轨迹 + 液滴前端射线”规则检查障碍物：必须真实接触碰撞点后才转成墙血；
#    未撞障碍则受重力落地并形成方向性地面血迹。墙血继续以真实 hit position / normal 贴在障碍表面并附着 collider。
# 5. 多人联机下由墨提斯 authority 发送同一随机 seed、力度/扩散/数量参数，各端本地重建同一组视觉；
#    血液节点加入 BattleTransient，战斗重置时可统一清理。V177 手动训练“血”保持原实现，本版本不修改训练血参数。
# ================================================================


# ================================================================
# V179 血液飞行弹丸随机化 + 简化像素血滴
# ================================================================
# 1. 用户要求手动训练血与墨提斯击杀血的“飞行弹丸”更随机，但整体仍要一眼看成血滴；V177/V178 的真实碰撞时机、
#    地面血迹、墙面血迹、拳头/吉他击杀力度与统一朝敌人方向均不改。
# 2. 飞行主体不再使用平滑多边形血滴 + 椭圆内芯 + 椭圆高光。V179 改为 4 种阶梯式像素轮廓随机选择，
#    顶点按约 1px~2px 网格取整，轮廓保持“前端厚、尾部收窄”，但边缘明显方块化。
# 3. 每发独立随机基础尺寸、颜色、轮廓版本与 1.00~1.28 左右的长度拉伸；只允许沿飞行方向拉长，Y 方向只做统一缩放，
#    禁止再使用 V177 命中时 Vector2(1.12,0.78) 或按速度把 Y 压扁的做法。
# 4. 飞行弹丸内部层次简化为“单色主血滴 + 可选一个深色像素块”，分裂滴改为 0~3 个独立方块像素，
#    不再用多个平滑椭圆/高光堆出复杂子弹。这样连续喷血时轮廓、长短、大小和尾滴分布都会不同，但风格统一为低像素血滴。
# 5. 手动训练 special://blood 与 res://scripts/effects/若叶睦_击杀血液.gd 必须使用同一套像素弹丸视觉原则；
#    本版本不修改血液伤害规则（训练血仍纯视觉，击杀血仍只在墨提斯真正击杀时出现）。
# ================================================================

# ================================================================
# V180 血液弹丸速度曲线 + 高度表现 + 底层渲染
# ================================================================
# 1. 用户反馈 V179 血液弹丸整体速度偏慢。本版本将手动训练 blood_forward_speed 默认从 470 提高到 650，
#    并新增 blood_forward_deceleration / blood_min_forward_speed_ratio：水平速度不再恒定，而是“刚喷出最快，随后逐渐减速”，
#    默认最低保留初速的 40%。墨提斯击杀血同样使用该原则，V178 的拳头/吉他数量、扩散方向和力度差异仍保留。
# 2. blood 的 height 从本版本起是明确的独立状态：ground_position 只负责平面前进，height 负责离地高度；
#    screen_position = ground_position + Vector2(0,-height)。height 按上抛初速/重力积分，归零且已进入下落阶段才算真正落地并生成地面血迹。
# 3. 高度需要有画面反馈：除 Y 方向抬升外，血滴在接近最高点时会在基础尺寸上小幅等比放大（手动训练默认最高约 +18%，
#    墨提斯击杀血约 +16%），落回地面时恢复原尺寸。禁止通过压扁 Y 轴表现高度，继续遵守 V179“只允许沿飞行方向拉长”的规则。
# 4. V180 所有血液相关 CanvasItem（飞行血、地面血迹、墙面血迹）统一使用较低的 absolute z_index（BLOOD_RENDER_Z=-48），
#    目的是始终画在人物、角色攻击和普通子弹下面，禁止血滴/血迹遮住角色或投射物。墙血仍使用真实碰撞点与 collider 附着规则，
#    只改变绘制层级，不改变 V177 的真实接触时机与 V176/V177 的表面贴附逻辑。
# 5. 手动训练和墨提斯击杀血都必须使用同一“先快后慢 + 独立 height + 高处略放大 + 底层绘制”视觉原则，
#    后续修改任一实现时必须同步检查另一实现，避免两套 blood 再次出现明显不一致。
# ================================================================

# ================================================================
# V181 血液可见性修复 + 细像素动态血滴 + 途中提前落地
# ================================================================
# 1. V180 将 BLOOD_RENDER_Z 设为 -48，实机反馈手动训练血和墨提斯击杀血几乎/完全不可见。原因是项目 world 内已有
#    z_index=-2/-3 等背景层，绝对 -48 会把血液画到这些背景之后。V181 作废 -48，统一改成 absolute z_index=-1：
#    仍低于默认人物/普通投射物（通常 z>=0），但高于主要世界背景，从而做到“血在角色/子弹下面但必须看得见”。
# 2. V179 的像素血滴边缘在 7.5px 左右宽度时会按 width/4 取整到约 2px 一格，实机观感过粗。V181 主体尺寸略缩小，
#    像素轮廓固定按 1px 网格取整；可选内芯/分裂滴允许 1px 级小方块，禁止重新放大成粗大的红色像素砖。
# 3. 飞行血不能在整个弹道里保持完全固定形状。每滴新增 age / motion_phase / motion_stretch_strength：随当前前进速度与相位
#    在运动方向上小幅动态拉长，并叠加很轻的整体尺寸脉动；横向厚度只能保持或略增，禁止通过缩小 Y/厚度来“压扁”血滴。
#    height 的高处等比放大继续叠加在该动态动画上，碰撞前端长度同步更新，不能破坏 V177 的真实接触时机。
# 4. 一部分飞行血（手动训练默认约 28%，墨提斯击杀血约 25%）会在 0.12~0.34 秒附近提前进入下坠：垂直速度转为向下，
#    水平速度同步衰减，因此会在主喷射轨迹途中直接落地。此类血滴落地不生成大血池，而是生成 4~7 个 1px 级小方块组成的
#    “像素血点”，表现零散飞沫提前落地；其余血滴仍使用 V177/V178 的常规地面血迹。
# 5. 手动训练 special://blood 与 res://scripts/effects/若叶睦_击杀血液.gd 必须同步使用本规则。
#    V178 拳头小力/吉他大力大扩散、V180 先快后慢与独立 height、V177 真正碰到墙才转墙血等规则全部继续保留。
# ================================================================

# ================================================================
# V182 薇欧拉真实厚涂火焰素材：火焰箭 / 动态火场 / 火柱生命周期
# ================================================================
# 1. 用户提供“真实厚涂火焰素材包”，固定接入 res://Images/characters/人物/薇欧拉/：
#    01_箭形火焰箭.png；02~04_火柱_状态1~3.png；05~06_火场A_状态1~2.png。禁止再用代码 draw_line/draw_circle
#    模拟火焰箭或用纯色圆点代替火场火焰。
# 2. res://scripts/effects/薇欧拉_火焰弹.gd 的弹体直接显示 01_箭形火焰箭.png；主体 Alpha 降低，并叠一层更淡的
#    CanvasItemMaterial additive 副本做发光。飞行中只做小幅沿运动方向伸缩、摆动与 Alpha 呼吸，不改变真实追踪弹道/伤害。
# 3. 火焰弹命中后仍沿原逻辑结算一次直击伤害并创建 res://scripts/effects/薇欧拉_火场.gd。火场底层必须存在
#    一个低不透明度橙色圆形范围；圆内随机排列多组 05/06 两帧循环火场 Sprite，并以不同相位/轻微位移和摆动制造火焰运动。
# 4. 火场中央使用 02/03/04 三帧循环火柱。火柱初始很高、很粗；约经过前 38% 生命周期后开始逐步收束：宽度明显变窄，
#    高度仅小幅降低，Alpha 同时逐渐降低。火柱缩放时必须通过位置补偿保证底部锚点保持在火场原点，禁止从中心上下同时缩。
# 5. 火场进入最后约 28% 生命周期时，橙色范围和地面火焰整体渐隐，同时 X 方向逐渐变宽、Y 方向逐渐变矮；
#    这是火场收尾扩散，不得提前 queue_free。火柱与地面火焰在整个可见阶段都保持帧动画和轻微呼吸/摆动。
# 6. 所有火焰主体都使用较低不透明度；每个重要火焰 Sprite 同时拥有更淡的加法混合副本作为局部发光，
#    不依赖项目必须开启 WorldEnvironment Glow 才能看见。原 V168 的倒计时无敌、倒计时结束播放“开”并发射攻击、
#    V171 胜利语音、V169 手机拍照起点等规则保持不变。
# ================================================================


# ================================================================
# V183 删除墨提斯击杀血液 + 薇欧拉范围火焰爆炸 / 战争女神灼烧 / 火场视觉重做
# ================================================================
# 1. 用户要求删除若叶睦/墨提斯击杀血液。V178~V181 中“墨提斯拳头/吉他击杀后喷血”的全部规则从 V183 起作废：
#    若叶睦.gd 不再 preload/调用 res://scripts/effects/若叶睦_击杀血液.gd，也不再暴露对应 Inspector 参数。
#    手动训练 special://blood 仍保留，只有墨提斯击杀血功能被删除。
# 2. 薇欧拉火焰箭改为范围爆炸：飞行过程中每个 physics tick 用真实运动段做障碍/人物射线；只要碰到任意人物或障碍物，
#    就以 intersect_ray() 返回的真实 position 作为爆炸中心。爆炸伤害半径必须与 fire_field_radius 完全一致，范围内所有合法敌人
#    各结算一次 fire_damage_multiplier 伤害；爆炸中心随后生成同半径火场。禁止恢复“只伤锁定目标”的 V182 直击逻辑。
# 3. 薇欧拉火焰箭爆炸伤害和火场每次 tick 伤害都必须附加/刷新 res://scripts/status/战争女神_灼烧.gd，节点名继续使用
#    WarGoddessBurnStatus，参数默认完全对齐战争女神远程灼烧：duration=3.0s、tick_interval=0.5s、tick_damage=attack_damage(1.0)。
#    因为该状态会调用 source.play_war_burn_tick_sfx()，薇欧拉实现同名接口并复用 res://audio/status/debuff/烫伤.wav；
#    爆炸/火场直接伤害成功时也播放该火焰伤害音，保证即时伤害与后续 DOT 都有对应反馈。
# 4. V182 火柱“跟火场一起活到结束”作废。V183 火柱拥有独立约 1.35s 的短生命周期：初始宽度约 radius*1.84，几乎铺满火圈直径，
#    高度约 radius*4.15；出生后很快收窄到约 38%，高度仅小幅降到约 86%，并快速渐隐。火柱 root 原点固定在地面底部，
#    缩放时 position.y 始终为 0，保证底部不动；火柱消失后地面火场继续存在到 fire_field_duration 结束。
# 5. 地面火场火苗从 11 组提高到 34 组，使用黄金角近似均匀覆盖整个伤害圆，分布最远接近 0.96*radius，禁止再次集中在中心。
#    05/06 火场帧继续循环，每簇有独立相位/速度/位移/摆动；火场末段仍横向变宽、纵向变矮并渐隐。
# 6. V182 发光过弱。V183 提高火焰箭/火场/火柱 additive 副本的 Alpha 和尺寸，主火焰仍保持半透明；
#    发光必须依赖 CanvasItemMaterial.BLEND_MODE_ADD 本身可见，不要求项目必须开启 WorldEnvironment Bloom。
# ================================================================

# ================================================================
# V184 薇欧拉火焰扩容/音效 + 若叶睦击杀血恢复 + 全局击杀血液开关
# ================================================================
# 1. V183 删除若叶睦/墨提斯击杀血的规则从 V184 起撤销。res://scripts/effects/若叶睦_击杀血液.gd 恢复进入项目；
#    墨提斯拳头击杀继续使用小力/少量/窄扩散 profile，吉他击杀继续使用大力/较多/更宽但受限的扩散 profile，且始终以攻击者->目标为主轴。
#    若叶睦/墨提斯的这套专属击杀血不受全局“血液”设置影响：即使参数页“血液”关闭，拳头/吉他致死仍有血。
# 2. Game.Game_Settings 新增 Blood_Effects=false，对应设置->参数中的“血液”。开启后，除已生成专属若叶睦血的致死外，所有有有效人物击杀者的 combatant_died
#    都会从 killer->victim 方向生成通用中等力度击杀血；关闭时其它人物不生成通用击杀血。该设置按普通参数持久化并作为多人共享玩法设置同步。
# 3. 血液击杀声新增 res://audio/sfx/combat/血液1.mp3、血液2.mp3：每次真正生成击杀血随机播放一条。
#    血滴落地/撞墙新增 res://audio/sfx/combat/血滴1~4.mp3：每滴在真实落地或真实接触障碍后随机播放一条，小音量/轻微随机 pitch；
#    手动训练 special://blood 的落地/撞墙也复用血滴1~4，便于直接测试血液音效与视觉。
# 4. 薇欧拉 fire_field_radius 默认由 74 提高到 110；因为爆炸范围必须始终等于火场范围，所以火焰箭范围爆炸、火场持续伤害与视觉圆统一使用同一 110 默认半径。
#    火焰箭继续对人物和障碍物都爆炸；V184 射线同时检测 body/area，并递归排除薇欧拉自身及其 CollisionObject2D 子节点，避免刚发射就撞到自己的 hurtbox。
# 5. 火柱进一步放大：素材有透明留白，因此初始贴图数值宽度改为约 radius*2.85、高度约 radius*5.40；独立生命周期缩短到最多约 1.05s，
#    很快收窄/轻微变矮/渐隐，绝不等待整个火场结束。地面火苗提高到 58 组，分布最远可到约 1.02*radius，并扩大单簇尺寸，确保视觉铺满伤害圆。
# 6. V183 的 additive 发光继续加强：地面火、火柱增加更大一层 GlowOuter，加法层尺寸/Alpha 提高；火焰箭 glow 也扩大。
#    主体仍保持半透明，避免纯白过曝；发光不依赖 WorldEnvironment Bloom 才能看到。
# 7. 薇欧拉新增 res://audio/characters/薇欧拉/火焰爆炸_[cut_3sec].mp3 与 火焰燃烧_[cut_94sec].mp3。
#    火焰箭每次在人物/障碍物真实爆炸时播放爆炸音；火场存在期间播放燃烧环境音，AudioStreamMP3 副本 loop=true，火场释放时随父节点停止。
#    两者沿用 GameplayRecord 总线（若存在）并叠加薇欧拉现有 viola_audio_gain_db。
# 8. V183 的范围爆炸、战争女神完全同款灼烧（WarGoddessBurnStatus）、烫伤伤害音，以及 V182 素材帧动画/运动效果全部继续保留。
# ================================================================

# ================================================================
# V185 血雾 / 薇欧拉火焰视觉修正 / 乐队分类 / meme猪 / 三角洲盾狗与跑刀仔
# ================================================================
# 1. 凡是实际生成击杀血的死亡（若叶睦/墨提斯专属击杀血，或参数“血液”开启后的通用人物击杀血），
#    都在 victim 的真实死亡位置额外生成 2~4 团血雾。血雾直接复用炮兵已有 res://Images/characters/人物/炮兵/烟雾.png，
#    染为暗红、低不透明度；每团大小/旋转/初始偏移随机，向上缓慢漂移并向四周散开，轻微放大、轻微旋转后渐隐。
#    不新增同义 smoke 资源目录。
# 2. V184 对薇欧拉 fire_field_radius 从 74 增到 110 属于误解。V185 恢复默认伤害/火场半径 74；用户要求的是放大“火场素材图片”，
#    不是扩大实际范围。05/06 地火单簇显示宽度明显放大，并继续覆盖整个圆；火柱素材进一步放大到约 radius*4.65 宽、radius*7.10 高，
#    独立生命周期缩短到约 0.72s，快速收窄/小幅变矮/渐隐，绝不等待火场结束。additive glow 尺寸与 Alpha 再加强，确保不依赖 Bloom 也能看出光晕。
# 3. 若叶睦与薇欧拉从角色选择“人物”分类迁移到新分类 res://scenes/characters/乐队/；脚本同步迁移到 res://scripts/characters/乐队/。
#    为兼容直接覆盖更新后旧人物场景仍残留，scripts/world.gd 的索引层主动隐藏 人物/若叶睦 与 人物/薇欧拉，避免列表重复。
#    图片仍保持现有 Images/characters/人物/... 路径，因为本轮未提供完整原图目录，禁止猜测/搬空资源。
# 4. meme 新增“寸头没事沙漠溜达猪”：无攻击能力，继续使用 ball 普通移动；对附近人物、Shooter 等威胁只做小幅避让。
#    Skill 为短促飞扑：先高速、随后减速、短暂停滞，再缓慢恢复普通速度。被动按 Inspector 的可投射物人物场景表，
#    周期性在地图外随机生成一名人物，只锁定猪攻击一次，然后关闭继续攻击并朝地图外离场；该临时人物使用独立 Team，
#    因而其攻击允许误伤任何其它人物（包括猪的队友）。
# 5. 三角洲新增“盾狗”：朝向只保留 LEFT/RIGHT。伤害来自盾牌正面方向时应用 front_damage_reduction；技能在面前放置铁丝网。
#    铁丝网敌人进入立即受伤，网内移动持续受伤并减速；自身按间隔自然掉耐久。Shooter 穿过时不阻挡，只记一次耐久伤害，
#    名称判定为 bullet/子弹的耐久损耗为其它投射物的一半。脚本还暴露 notify_non_collision_attack() 给非碰撞攻击主动扣网耐久。
#    盾狗靠近敌人时仅做左右撞击；消耗体力、造成伤害/短距离击退/眩晕，击退方向会偏向最近铁丝网；斜向但略够不到时可消耗更多体力先横向接近再撞。
# 6. 三角洲新增“跑刀仔”：两条命。第一命禁用攻击；地图中随机生成物资，地图边缘随机生成保险。
#    靠近物资直接获得钱；进入保险交互范围后定身开锁，开完获得更多钱并删除保险，离开范围则进度中断重置。
#    第一命致死时不进入最终 Die，而是按钱购买 Damage/Block/Speed/MaxHealth 后满血进入第二命，同时清理剩余物资/保险；第二命恢复普通近战攻击并正常死亡。
# 7. 新增角色本轮没有用户图片素材，因此只使用脚本内简单 Polygon2D 占位视觉，禁止猜测 Images 路径。后续收到对应角色素材后再替换视觉，不改玩法接口。
# ================================================================


# ================================================================
# V186 血液绘制层修复：自由血液永不遮人物/投射物，墙血只覆盖所属障碍物
# ================================================================
# 1. V185 新增血雾时误将 Sprite2D 设为 absolute z_index=1；默认人物图片常见 z>=0，因此血雾会盖住人物。
#    V186 起血雾与飞行血、地面血统一使用 BLOOD_RENDER_Z=-1 且 z_as_relative=false：只允许显示在世界背景之上、人物/投射物之下。
# 2. 自由血液禁止通过 top_level、正 Z 或其它独立前景层绕过上述顺序；手动训练 special://blood 也继续遵守同一底层规则。
# 3. 墙面血是唯一例外：真正碰撞后生成的 wall decal 必须作为实际 collider 的 CanvasItem 子节点，z_as_relative=true、z_index=0。
#    这样它继承障碍物最终 Z，并利用子项默认绘制在父项上方的规则只覆盖自己的障碍表面；禁止再给墙血 absolute 正 Z。
# 4. 如果碰撞对象不能作为 CanvasItem 父级，墙血回退到世界 absolute z=-1，而不是冒险提高 Z 遮挡人物。
# 5. 本版本只修绘制顺序；V177~V181 的血液弹道/落地/墙面真实接触、V184 音效、V185 血雾运动全部保持不变。
# ================================================================

# ============================================================
# V187 累计规则：寸头猪避让/地图外袭击者 + 血液绘制层修复
# ============================================================
# 1) 寸头没事沙漠溜达猪的威胁避让不得每帧按全部威胁直接重算反向向量。
#    子弹避让采用“正常移动为主 + 侧向闪避 + 短时锁定左右侧”的方式；
#    同一威胁期间不允许左右反复翻转，避让结果必须保持在原前进方向的前半球，避免原地转圈。
# 2) 猪的地图外随机袭击者默认表只能放真正有主动投射物 Attack() 的人物。
#    袭击者流程固定为：地图外可见出生 -> 走到地图边界攻击点 -> 朝猪攻击一次 -> 转身走回地图外 -> 清理。
#    它们由猪脚本自己管理生命周期，必须带 pig_outside_guest_exempt / submission_allow_map_escape，
#    World 的通用地图外死亡和边界救回都不得在这段流程中把它们提前杀死/拉回。
# 3) 血液绘制层 V186 的 absolute z=-1 是错误的：World 根本身为 z=-2，absolute -1 反而在人物前面。
#    V187 起飞行血、落地血、血雾、手动训练血全部作为 World 子节点使用 relative z=-1，
#    即最终位于地图视觉之上、普通人物/投射物之下；不得遮挡任何人物或普通子弹。
#    墙血仍是实际障碍物的子 CanvasItem，relative z=0，只覆盖它映射到的障碍物表面。


# ============================================================
# V188 累计规则：寸头猪素材/语音 + 设置翻译/薇欧拉完整特效预览 + 数值与水印修正
# ============================================================
# 1) 设置 -> 参数中的 Blood_Effects 对外文字必须使用 SETTING_BLOOD_EFFECTS：中文显示“血液”，英文显示“Blood”。
#    translations.csv 与 Game._t_for_locale() 运行时兜底都必须保留该键，禁止再次显示裸英文设置名。
# 2) 设置 -> 特效新增“薇欧拉·完整火焰”预览项（快捷键 4）：必须展示完整 火焰箭飞行 -> 爆炸音 -> 动态火场/短时大火柱 -> 燃烧循环 的组合，
#    复用现有薇欧拉火焰素材和 res://scripts/effects/薇欧拉_火场.gd，不另造一套只用于设置的假视觉。
# 3) meme“寸头没事沙漠溜达猪”正式使用用户提供图片：普通状态 res://Images/characters/meme/寸头没事沙漠溜达猪/沙漠寸头没事瞎溜达猪.png，
#    飞扑状态切换到同目录 猪飞扑.png；平时每 4.75~9.25s 左右随机播放一次 猪哼.mp3，发动飞扑时播放 猪大叫.mp3。
#    V187 的稳定侧向避让和“地图外走到边界再攻击、再离场”流程保持不变。
# 4) 军火商 Max_health 默认由 760 下调为 600。伪军头子初始钱由 3 改为 2，money_recharge_seconds 由 4s 放慢到 6s。
# 5) 锻刀师成刀普攻：AI 攻击距离与真实 SwordHitArea 前向距离统一缩短为 82；基础 Damage=3 不变，
#    sword_damage_multiplier=33.3333333，对应未受其它倍率影响时单次成刀命中为 100；每次挥刀耐久消耗由 10 提高为 15。
#    禁止只缩 AI range 而保留 610px 的旧真实 SwordHitArea。
# 6) 墨提斯吉他真实图片碰撞成功伤到人时，除原有电吉他命中音和“全都不会”语音外，再播放标准碰撞伤害音 res://audio/sfx/physics/balls_hit1.sfxr。
#    未造成实际伤害时不得播放该碰撞伤害音。
# 7) World 中心水印属于地图背景装饰，不是前景 UI。CenterWatermark 必须相对 World 使用 z_index=-1，
#    让最终 Z 低于普通人物/投射物；禁止恢复 absolute z=95 等会遮挡角色的前景层设置。
# ============================================================


# ============================================================
# V189 累计规则：寸头猪体型 / 真实投射物闪避 / 地图外来客边界锁 + 血液更低绘制层
# ============================================================
# 1) V188 猪视觉 local height=96/106 在 ball.tscn 根 scale=0.2 下实机只有约 19~21px 高，明显小于正常人物。
#    V189 普通/飞扑目标 local height 改为 380/410；meme/寸头没事沙漠溜达猪.tscn 初始 Image scale 同步改为约 0.943，
#    让 CharacterAutoFit 子节点在父角色 _ready 前就能按正确体型重算碰撞，不允许只在父 _ready 后放大图片造成“图大碰撞仍小”。
# 2) V187 的避让主要扫描 group("Shooter")，但本项目大量真正投射物只是 group("Ball") + Ball_Type.Shooter/Shooter_with_Health，
#    因而猪实际上看不见大多数子弹。V189 以 Ball_Type 为主扫描，Shooter group 只做旧对象兼容；用相对速度预测 0.82s 内最近点，
#    只有弹道会进入危险半径才闪避。左右侧向选择在同一威胁期间锁定，避免原地转圈。
# 3) 飞扑修复：旧 Skill() 结尾把 Using_Skill=false，状态机同物理帧就退出 Skill，super.tick_physics() 最终走 Stand，导致飞扑速度被覆盖。
#    V189 飞扑期间必须保持 Using_Skill=true，结束时再 false；技能起手优先朝危险投射物侧向闪避，飞扑途中也允许小幅持续修正。
#    AI 遇到即将接触且技能冷却完成的危险投射物可直接触发一次紧急飞扑；玩家直接控制仍由玩家自己决定技能时机。
# 4) 地图外袭击者 V187 的 stage 点用了 rect 内侧 +6px，且子 state_machine 仍独立运行，会把部分人物继续带进地图。
#    V189 来客出生前 process_mode=DISABLED、collision_layer/mask=0，位置全程只由猪脚本 Tween 控制；攻击点改为地图边界外侧默认 24px，
#    从出生到攻击、离场始终保持在可玩 Rect 外。流程固定：更远地图外 -> 边界外侧 -> 朝猪 Attack() 一次 -> 转身更远地图外 -> 删除。
#    pig_outside_guest_exempt / submission_allow_map_escape 继续保留，World 不得用普通出界规则杀死来客。
# 5) V187 free blood relative z=-1 最终约 z=-3，实机仍有部分角色/子弹绘制层比它更低而被覆盖。
#    V189 飞行血、地血、血雾及手动训练血统一改成 World relative z=-2，最终约 z=-4：与地图 TileMap 表面层对齐且节点后生成，
#    因此仍能显示在背景/地面上，但严格低于普通人物与投射物。墙血继续作为实际障碍物子 CanvasItem relative z=0，只有墙血可覆盖对应障碍表面。
# ============================================================

# ============================================================
# V190 累计规则：薇欧拉火圈/火焰箭缩小 + PointLight2D 真发光 + 火柱底部中心爆发成长
# ============================================================
# 1) V185~V189 的 fire_field_radius=74 对当前视觉仍偏大。V190 默认改为 58；火焰箭显示长度由 92 改为 56。
#    爆炸伤害范围仍必须严格等于 fire_field_radius，火场持续伤害圆与视觉范围同步缩小；不得只缩图片却保留 74 的隐藏伤害半径。
# 2) V182~V189 使用“同一火焰贴图放大 + additive”作为 Glow/GlowOuter 的方案从 V190 起废止。
#    该方案视觉上容易像放大的残影/重影，不是用户要的普通发光。火焰箭与火场改用真正 PointLight2D + 径向 GradientTexture2D，
#    Light2D.BLEND_MODE_ADD、橙色光、轻微 energy 呼吸；主火焰只保留单份 AnimatedSprite2D/Sprite2D，不得再复制贴图做光晕。
# 3) 火场圆只保留低 Alpha 橙色 Polygon2D 范围底色；地火仍使用 05/06 帧循环并铺满实际 58 半径，但单簇尺寸随半径同步收敛，
#    禁止因为火场缩小而继续使用 V185 的超大火苗尺寸造成视觉重新溢出。
# 4) 火柱 root 原点必须固定为火场圆心，也就是火柱底部锚点。PillarAnimated 的纹理中心放在 -final_height/2，
#    所有成长/收束仅缩放 root，root.position 永远 Vector2.ZERO；允许极小绕底部旋转，但禁止左右位移底部。
# 5) 火柱出生动画改为“快速爆发成长”：高度从约 10% -> 100% 用 cubic ease-out 约 0.16s 完成；宽度从约 20% -> 100%
#    用同样先快后慢的 cubic ease-out 约 0.28s 完成，因此高度明显先于宽度到位。约 0.34s 后才开始快速收窄、轻微变矮并渐隐；
#    火柱仍独立于地火生命周期，不得等整个火场一起消失。
# 6) 设置 -> 特效 -> 薇欧拉完整火焰预览同步使用更小的火焰箭和火场，并改成 PointLight2D 真光源，不得继续展示旧 Glow Sprite 残影。
# ============================================================


# ============================================================
# V191 累计规则：寸头猪体型回调 / 墙体绕行 / 地图外袭击频率提高
# ============================================================
# 1) V189 普通/飞扑 local height=380/410 对实际普通人物 205 左右的统一视觉基准过大。V191 调整为 245/260，
#    普通状态大约只比标准人物略大；meme/寸头没事沙漠溜达猪.tscn 的普通图预览 scale 同步从 0.943 改为约 0.608。
#    CharacterAutoFit 仍以标准角色尺寸计算碰撞，禁止再把碰撞体跟着图片一起放大到 380 级别。
# 2) 猪不能在 direction 正对墙时继续被“保持前进方向前半球”的避让规则压回墙里。每次公共 move_and_slide() 后读取真实 slide collision，
#    非 ball 的碰撞作为墙体候选：用碰撞 normal 计算“沿墙切向 + 少量朝墙外法线”的逃离方向，并锁定约 0.46s。
#    墙体逃离期间跳过普通 avoid_min_forward_dot 限制，优先沿墙绕开；飞扑中撞墙也允许向该逃离方向修正，避免持续顶墙。
# 3) 地图外袭击者 V189 的“始终在边界外侧走到攻击点 -> 攻击一次 -> 离场”流程不变。仅提高出现频率：
#    outside_attacker_interval_min/max 默认由 6.5~11.5s 改为 3.25~5.25s；不得通过让多个来客进地图来伪造频率。
# ============================================================


# ============================================================
# V192 累计规则：寸头猪再缩小 / 地图外来客多次攻击 / 弹丸入场 / UI 与胜利隔离
# ============================================================
# 1) V191 的猪 normal/pounce local height=245/260 仍偏大。V192 调整为 218/232；场景普通图初始 scale 同步约 0.541。
#    猪只略大于普通人物，CharacterAutoFit 仍维持标准角色碰撞尺寸，不允许图片尺寸继续无上限放大碰撞体。
# 2) 地图外袭击者默认人物表只保留已经确认能直接从 Attack() 生成飞行投射物且不依赖额外前置条件的猎人、键盘侠。
#    科学家需要传送门、背刺者 Attack 依赖直接控制、裁判普通 Attack 不是投射物，因此从默认表移除；用户仍可在 Inspector 自行扩展表。
# 3) 每名来客不再只攻击一次。到地图边界后随机攻击 2~4 次，每次之间随机短暂停顿，全部攻击结束才转身离场。
#    来客自身始终停在地图外：stage 位置按实际 Sprite 世界半宽/半高计算，让图片内缘刚好停在地图边界外，不允许角色中心或视觉主体进入可玩 Rect。
# 4) 为解决“部分子弹从地图外出生后被边界/障碍挡住，根本射不进来”，每次来客攻击时短时间扫描其新生成投射物。
#    识别 Master==来客 或 Master_name==来客后，将仍在地图外的投射物放到同侧边界内约 5px，并把方向/已有 velocity 校正为朝猪。
#    只有投射物可以越过边界，来客人物本身不进入地图；投射物继续使用原伤害/误伤规则。
# 5) pig_outside_guest_exempt 来客是纯演出角色，必须从 _is_primary_battle_character() 排除，因此不得进入顶部 VS、胜利阵营统计或手动胜利武装。
#    来客离场/queue_free 不得改变真实存活阵营数，也不得因为“来客离开后只剩一队”触发胜利铃声。
# 6) 来客 health_bar 必须在生成后立即隐藏并禁用；World housekeeping 继续根据 pig_outside_guest_hide_ui 强制隐藏，避免其自身血条脚本再次恢复可见。
# ============================================================

# ============================================================
# V193 累计规则：寸头猪来客死亡清理 / 持续正常冷却攻击 / 智能弹道避让
# ============================================================
# 1) 猪死亡或离开场景时，所有由该猪生成且仍存活的 PigOutsideGuest 必须立即清理；
#    同一被动仍在场上的 PigOutsideGuestProjectile 也一并结束。不得再依赖来客攻击协程下一次醒来后才发现猪已死亡，
#    否则会出现“猪已经死了，地图边界外的人还一直留着”的残留。
# 2) V192 的“随机攻击 2~4 次后离场”废止。V193 来客到边界外攻击位后，随机停留约 5~8 秒，
#    整段停留期间持续瞄准猪，并严格使用该人物自己的 Attack_Cooling 作为下一次普攻冷却；攻击窗口结束才转身离开。
#    state_machine 仍保持禁用，防止人物自己的移动 AI 把本体带进地图；普通 Attack() 本身及其异步前摇/投射物生成继续允许运行。
# 3) 来客投射物护送从只扫描 current_scene 直属子节点改为扫描 Ball / Shooter group，兼容投射物挂在子容器的角色。
#    被识别的来客投射物必须记录 pig_outside_guest_owner_id，并加入 PigOutsideGuestProjectile，供猪死亡时精确清理。
# 4) V192 的猪避弹仍过于机械：只按一颗主威胁固定选左右侧且保留过多原前进方向，会出现“看见子弹但还是往弹道里走”。
#    V193 对左右候选闪避方向分别评分：预测猪自己移动后的弹道最近距离，同时看最多 3 颗额外危险投射物，
#    并用 PhysicsDirectSpaceState2D 射线探测候选方向前方是否是静态/地形障碍。真正危险时闪避方向优先级高于保持原前进方向。
# 5) 同一颗主要威胁仍保留短时左右锁定以防抖动，但如果当前锁定方向明显撞墙、另一侧评分显著更高，允许主动换边；
#    紧急飞扑与飞扑中途转向复用同一评分结果。默认探测距离/危险半径/预测时间提高到 320 / 76 / 1.05s，转向响应提高。
# ============================================================

# ============================================================
# V194 累计规则：地图外来客不可锁定 / 来客弹丸出生即入场 / 寸头猪避弹与飞扑加强
# ============================================================
# 1) PigOutsideGuest 属于地图外演出攻击者，不是战斗目标。生成时必须设置 ignore_combat_targeting=true；
#    classes/ball.gd::is_combat_targetable() 统一读取该 metadata 并返回 false。World 最近敌人刷新也必须遵守公共契约，
#    若旧 AI 曾把不可锁定来客写进 Target_Enemy，要主动清空。不得只隐藏血条/VS，却仍允许人物把来客当敌人锁定。
#    来客 add_child 后还要从 group("Ball") 移除，兼容那些历史角色里绕过 is_combat_targetable()、直接遍历 Ball group 的旧索敌代码。
# 2) V193 来客弹丸只靠 Ball/Shooter group 后续轮询仍会漏掉不进这些组的 Area2D 投射物（典型：猎人霰弹），
#    且轮询到下一 physics frame 才搬运时可能已经撞到地图边界。V194 寸头猪监听 SceneTree.node_added：
#    只要新节点 Master==来客 或 Master_name==来客，就在进入树的同一时刻把投射物放到对应地图边缘内侧。
# 3) 来客弹丸入场位置必须保留原投射物在边界切线方向的坐标，只修正穿越哪一侧边界；方向/已有 velocity 统一重定向到猪。
#    若投射物存在 max_distance（例如猎人霰弹默认只有 150），来客版本至少扩展到“当前入场点 -> 猪距离 + 96px”，
#    并重置已行进距离，避免“成功进场但因为角色原始短射程仍飞不到猪”。来客人物本体仍不得进入可玩 Rect。
# 4) V193 猪避弹只扫描 Ball/Shooter group，仍会漏 Area2D 霰弹等。V194 建立全局投射物注册表：
#    Ball_Type.Shooter/Shooter_with_Health、Shooter/HunterPellet group，以及具备 direction + speed/Speed + damage_amount/Damage 的 Area2D
#    都可进入真实弹道预测。初始场景递归种子一次，之后用 SceneTree.node_added 增量维护，禁止每物理帧全树递归扫描。
# 5) 猪闪避在危险弹道下不能只修改 direction；V194 还在该物理帧通过 Repel 叠加真实侧向横移速度，
#    并把默认探测距离/危险半径/预测时间提高到 430 / 96 / 1.35s、转向响应提高到 26。
#    同一威胁左右锁定、墙体候选评分和多弹预测仍保留，避免恢复成“每帧左右翻转”的原地转圈。
# 6) 飞扑距离 V193 偏短。V194 默认 pounce_speed_multiplier=3.85，fast/slow/stall/recover=0.22/0.38/0.14/0.50s；
#    紧急飞扑触发预测窗口提高到 0.78s，飞扑中对子弹的方向修正提高。仍要求先快后慢 -> 短暂停滞 -> 慢慢恢复普通速度。
# ============================================================

# ============================================================
# V195 —— 寸头没事沙漠溜达猪：纯威胁规避 + 地图外来客弹丸穿界修复
# ============================================================
# 1. 猪的普通 AI 移动不再使用“原前进方向 / 普通追人 / 随机游走”作为基准。
#    存活且非眩晕时强制走公共 Move 物理链，但 direction 与额外 Repel 只由本角色的纯威胁规避器产生。
# 2. 纯规避器每个物理帧从多个候选方向（含原地停止）里评分未来安全性：
#    - 投射物：按相对速度预测未来最近距离；
#    - 人物/生物：不分敌我，距离过近都作为空间威胁；
#    - 墙体：候选方向先做即时射线探测，避免选中会撞墙的路线；
#    - 地图边缘：越接近边缘惩罚越高；
#    - 只保留很弱的“上一帧安全方向”惯性以防左右抖动，不再保留普通移动方向偏好。
#    无任何威胁时允许停下，不为了“看起来在移动”而随机走。
# 3. 紧急飞扑仍可由高危来弹触发，但飞扑起始方向与飞扑过程中的修正都改用同一个纯威胁规避器，
#    不再朝普通目标或原移动方向飞扑。V194 加长的飞扑倍率/持续时间继续保留。
# 4. 地图外来客本体继续保持不可锁定、无血条、无 VS/胜负统计，只停在地图边界外攻击。
# 5. V194 的固定 projectile_entry_inset 对较厚地图边界碰撞体仍可能把弹丸放进墙里。
#    V195 改为：来客投射物进入 SceneTree 时，从对应地图边界向内逐步探测，找到第一个周围没有非角色物理体的安全点，
#    再把投射物放到该点并重新指向猪；即使投射物坐标已经“进图”但还嵌在边界墙内，也会重新放置。
# 6. 对旧投射物兼容：若其 Master/Master_name 在 add_child 后才填写，只要它在来客攻击窗口内出生于来客附近且具有投射物特征，
#    也会被认定为来客弹丸并立即执行入场修复。常见 travelled/max_distance 字段同时重置/补足。
# 7. 不允许以后为了简化再次退回“固定 5px 入场点”“只扫描 Shooter/Ball group”“普通移动方向 + 侧向微调”的旧实现。

# ============================================================
# V195 热修 —— 猪纯威胁规避脚本解析错误
# ============================================================
# 1. `_projectile_threat_info()` 禁止再引用 V194 已删除的 `avoid_radius`。
# 2. 投射物筛选距离统一使用 V195 现有字段：`projectile_detect_radius` 与 `projectile_danger_radius`。
# 3. 本修复只修正变量引用，不回退 V195 的纯威胁规避、来客不可锁定、来客弹丸安全穿界等机制。
# ============================================================

# ============================================================
# V196 —— 寸头没事沙漠溜达猪：恢复正常移动 + 仅在真实威胁时接管闪避
# ============================================================
# 1. 用户确认 V195“无威胁允许停下”不符合该角色设计。V196 起：
#    没有真实威胁时，猪必须完全遵循普通 ball 的移动逻辑，不允许角色脚本主动把 direction 清零，
#    也不允许强制把公共 Stand/Move 状态改成 Move。World 的随机移动方向、Ball_Can_Move 开关、
#    公共 move_and_slide()/when_collide() 碰墙反弹等规则全部照常生效。
# 2. 只有真正存在威胁时，角色专属规避器才临时接管 direction/Repel：
#    - 真正敌对且可锁定的人物进入 pure_avoid_character_radius 时作为近身空间威胁；同队角色不触发专属规避；
#    - 投射物必须通过 _projectile_threat_info() 的相对速度/最近点预测，确认轨迹会进入危险区后才算威胁；
#      不能因为探测半径内存在一颗正在远离或明显打不中的弹，就取消正常移动。
# 3. 一旦威胁成立，继续使用 V195 的多候选方向评分，并保留墙体射线、地图边缘惩罚、人物分离、
#    多弹预测和 V194 的额外 Repel 横移速度，确保不是“看见威胁但只改朝向、身体仍躲不开”。
# 4. 紧急飞扑、飞扑过程中的安全方向修正、V194/V195 的全局投射物注册、
#    地图外来客不可锁定/不参与胜负，以及来客弹丸出生即安全穿界全部继续保留。
# 5. V196 明确覆盖 V195 第 1、2、7 条中“普通移动完全废止 / 无威胁可停 / 禁止恢复普通移动基准”的部分；
#    其它 V195 规则继续有效。
# ============================================================


# ============================================================
# V197 —— 寸头没事沙漠溜达猪：威胁时保证真实移动 / 飞扑禁止迎弹
# ============================================================
# 1. 修复 V196 的状态链漏洞：V196 虽然在威胁成立时写入了 direction/Repel，但最后仍把原公共 state
#    原样传给 ball.tick_physics()。如果该帧处于 Stand 等不使用 direction 的状态，就可能出现“方向算了但实体不走”。
#    V197 起，无威胁仍完全遵循普通公共 state；只有本帧已经确认存在真实威胁或正在飞扑时，才临时把物理移动分支
#    当作 Move 执行，保证 direction + Repel 必须进入 ball.move()/move_and_slide()。死亡/眩晕不强行移动。
# 2. 威胁成立后，纯规避候选不再包含 Vector2.ZERO。即使四周都不理想，也必须选择当前评分最高的实际移动方向；
#    若评分器异常未给出方向，则先按主要来弹做 90° 横切兜底，再退到远离最近敌人的方向，禁止再次原地站住。
# 3. 投射物候选只把 `_projectile_threat_info()` 已确认会进入危险区的弹丸送入规避评分；附近但正在远离/明显打不中的弹丸
#    不再干扰本帧逃生方向。人物威胁仍只认敌对且可锁定目标，同队与地图外来客不触发专属规避。
# 4. 紧急飞扑新增硬约束：主要来弹的 motion 是弹丸实际飞行方向。飞扑候选若与该 motion 明显反向（dot < -0.10），
#    等价于朝弹丸来源迎头冲，直接淘汰；允许 90° 横切弹道或顺弹道方向拉开。普通规避也对迎弹方向施加强惩罚。
# 5. 飞扑过程中每帧继续看当前最危险来弹；如果旧 `_pounce_dir` 已经与来弹 motion 明显反向，不再缓慢 lerp，
#    而是立即切换到安全候选，修复“已经飞扑却继续朝子弹撞”的情况。墙体/地图边缘评分仍继续参与安全方向选择。
# 6. V197 只修改 `scripts/characters/meme/寸头没事沙漠溜达猪.gd` 与本注释；角色 Speed/血量/技能冷却、
#    V194~V196 的全局投射物注册、地图外来客不可锁定/不参与胜负、来客弹丸安全穿界均保持不变。
# ============================================================

# V198 —— 寸头没事沙漠溜达猪“有威胁仍不躲”最终位移链修复
# 1. V197 仍把规避拆成 direction 基础速度 + Repel 补差，最终依赖公共 Move 状态；实测仍可能出现已算出规避方向但实体没有产生有效逃生位移。
# 2. V198 增加每物理帧专属 _escape_velocity_override。只要本帧存在真实威胁或正在飞扑，完整逃生速度直接写入该 override。
# 3. 威胁帧不再强制 State.Move，而是把 Repel 设为完整逃生速度后调用公共 ball.tick_physics(State.Stand)。ball.stand() 会真实执行 move_and_slide()、实体接触与墙体反馈，但不会混入普通 direction * Speed，因此普通 AI/World 随机方向/Move-Stand 状态无法再覆盖逃生速度。
# 4. 普通规避速度 = 角色公共 0.6x 基础速度 * pure_avoid_move_multiplier；飞扑速度 = 角色公共 0.6x 基础速度 * 当前飞扑阶段 multiplier。数值本身不改，只修最终速度落地方式。
# 5. 无威胁时 _escape_velocity_override 每帧清零，并继续调用原 state 的公共 tick_physics，完全恢复正常随机移动逻辑。
# 6. V197 的危险投射物预测、飞扑禁止迎头冲弹、横切弹道 fallback、墙体/地图边缘评分继续保留。

# ============================================================
# V199 —— 训犬师血量 / 猎犬基础伤害平衡调整
# ============================================================
# 1. 训犬师场景 res://scenes/characters/人物/训犬师.tscn：Max_health 从 850 调整为 700。
# 2. 训犬师自身 Damage 保持 50，不改攻击力统一规则、标记、召狗频率、猎犬 AI、碰撞或其它数值。
# 3. 训犬师猎犬场景 res://scenes/creatures/训犬师_狗.tscn：Damage 从 0 明确调整为 50。
# 4. 猎犬现有咬击仍遵守 V107 统一攻击力规则：bite_damage_multiplier = 1.0；由训犬师召唤时继续
#    inherit_master_attack_power = true、master_attack_damage_multiplier = 1.0，因此训犬师基础 Damage=50 时，猎犬基础咬击伤害为 50。
#    猎犬自身 Damage=50 同时作为场景 Inspector/脱离主人时的基础攻击力一致值，不新增第二套绝对咬击伤害字段。
# 5. 本轮不修改训犬师/猎犬脚本，不恢复已废止的持续咬伤 Buff，也不改变狗血量、移速、咬击冷却、追猎速度或生成间隔。
# ============================================================

# ============================================================
# V200 —— 寸头没事沙漠溜达猪：恢复锁边闪避 / 修复投射物漏注册 / 最终 velocity 直驱
# ============================================================
# 1. 用户实测确认 V198 仍表现为“有敌人时原地转圈、子弹完全不躲、飞扑也不躲”。
#    根因之一是 V195~V198 的多候选方向方案仍然每物理帧重新评分大量方向，违反 V187 已明确的
#    “同一威胁期间锁定左右侧、禁止左右逐帧翻转，避免原地转圈”规则。V200 起废止这段每帧 20 方向重评分链。
# 2. 来弹规避改成硬优先级：危险投射物 > 飞扑侧闪 > 近身敌人 > 普通移动。
#    对每颗主要危险投射物，只取其实际飞行方向的两个 90° 侧向候选；首次按多弹最近距离、墙体和地图边缘选一侧，
#    随后按 projectile instance_id 锁边默认约 0.55s。同一主要威胁未更换且锁定侧可走时禁止换边；只有撞墙/出界或主要威胁更换才重新选侧。
# 3. 修复 V194 起投射物注册仍可能漏对象的问题：SceneTree.node_added 在节点进入树时就会触发，部分投射物会到自身 _ready()
#    才设置 Ball_Type.Shooter 或加入 Shooter/专属 group，因此 node_added 当帧一次判断可能把它当普通节点后永久漏掉。
#    V200 node_added 先即时尝试，再 call_deferred 到 ready 后二次注册；已有场景仍保留 ready 后递归种子扫描。
# 4. 非 ball 飞行物识别不再限制 Area2D。项目现有 Node2D 剑气、CharacterBody2D 凑企鹅石头等对象，只要同时具备
#    direction/velocity + speed/Speed/travel_speed + damage_amount/Damage/impact_damage 等运动/伤害字段，也进入投射物追踪。
#    _threat_motion_vector() 同步支持 travel_speed，避免“注册到了但速度仍算成 1px/s”导致威胁预测失真。
# 5. V198 的 Repel + ball.stand() 间接落地再次废止。V200 威胁帧先让公共 ball 以 Stand 更新视觉/公共副作用但不移动，
#    然后猪脚本直接把最终逃生速度写入 CharacterBody2D.velocity 并调用 move_and_slide()；实体接触、墙体爆点与公共碰撞反馈继续补齐。
#    因此威胁移动不再依赖 State.Move/Stand、World direction 或 Repel 是否在后续被清零。
# 6. 紧急飞扑和飞扑途中同样复用“按具体来弹锁定一个侧向”的结果。飞扑若当前方向迎弹或明显偏离锁定侧，立即切到侧闪；
#    否则只做小幅转向。飞扑期间不再每帧被敌人位置/20 方向评分器拉回迎弹方向。
# 7. 没有危险投射物时：若 235px 左右存在敌对且可锁定人物，猪直接按完整最终速度远离该敌人；完全没有威胁时不碰 direction，
#    继续使用普通 ball/World 随机移动、Ball_Can_Move 和公共碰墙反弹。角色 Speed=92、Max_health=520、Skill_Cooling=5.5、
#    飞扑阶段时长/倍率、地图外来客机制均不修改。
# 8. V200 明确覆盖 V195~V198 中“每帧全方向重评分 / 通过 direction+Repel 或 Stand+Repel 间接实现威胁位移”的部分；
#    V194 之后的地图外来客不可锁定、来客弹丸安全穿界、投射物友军过滤等其它规则继续有效。
# ============================================================

# ============================================================
# V201 —— 训犬师吹哨降频 / 拳击手中距离冲刺触发带
# ============================================================
# 1. 训犬师当前存在两类吹哨：周期召狗会吹哨，新标记敌人也会吹哨。旧版 dog_spawn_interval=8s，
#    且开局立即召狗后标记系统又可能很快再次吹哨，实际听感比“8 秒一次”更频繁。
# 2. V201 起训犬师新增统一 whistle_action_cooldown，默认 10.0s。任何一次召狗或新标记吹哨都会刷新该冷却；
#    标记系统在冷却未结束时只继续正常移动/扫描，不得再次建立新标记并吹哨。已有标记/猎犬围猎本身不受影响。
# 3. 训犬师周期召狗间隔从 8.0s 调整为 14.0s；开局原有“立即召第一只狗”保持不变。
#    训犬师 Max_health=700、Damage=50，以及 V199 猎犬 Damage=50、咬击继承、狗血量/移速/追猎规则均不修改。
# 4. 拳击手旧 dash_trigger_min_distance=130。Map10x10 使用 10×10 个约 16px 网格，地图边长约 160，
#    130 已超过地图边长的 80%，导致普通对战里敌人很少处在可触发距离，因此技能冷却即使就绪也经常被距离门槛压住。
# 5. V201 将 AI 冲刺触发改为明确距离带：dash_trigger_min_distance=55、dash_trigger_max_distance=80，
#    即约为 10x10 地图边长的 1/3～1/2。敌人太近(<55)不冲，太远(>80)也不冲；进入 55～80 后，
#    只要公共 Skill_Cooling 已就绪即可正常进入 Skill。距离门槛不再消耗/重置尚未实际释放的技能冷却。
# 6. 直接控制拳击手时仍允许按玩家鼠标方向手动使用冲刺，不强制套 AI 的 55～80 距离带。
#    dash_distance=260、dash_speed=920、Skill_Cooling=4.2、拳击伤害/Combo/音效/冲刺撞实体停止规则均保持不变。
# 7. V201 修改：res://scripts/characters/训犬师.gd、res://scenes/characters/人物/训犬师.tscn、
#    res://scripts/characters/拳击手.gd、res://scenes/characters/人物/拳击手.tscn 与本注释。
# ============================================================

# ============================================================
# V202 —— 训犬师继续削弱：猎犬上限 / 无标记警戒范围 / 轻微咬击击退
# ============================================================
# 1. 训犬师同时存活猎犬上限固定为 3。新增 dog_max_count=3；每次周期生成前先清理死亡/失效狗引用，
#    若当前仍有 3 条存活狗则直接跳过本次生成。达到上限时不得播放召唤吹哨，也不得刷新 whistle_action_cooldown；
#    后续有狗死亡后，下一次正常 DogSpawnTimer timeout 才允许补到上限。V201 的 14s 周期和统一 10s 吹哨动作冷却保持不变。
# 2. 猎犬“未被训犬师标记派去围猎”的自动护主检测范围 guard_notice_radius 从 50px 缩小为 36px。
#    该削弱只作用 FOLLOW/GUARD 自动找附近敌人的分支；训犬师已经吹哨并 assign_hunt_target() 后的 HUNT 追猎仍可跨更远距离追标记目标，
#    不允许用 guard_notice_radius 限制标记追猎。
# 3. 猎犬咬击基础伤害仍为 50，bite_damage_multiplier=1.0、V107 主人攻击力继承继续有效；bite_range=42、bite_cooldown=1.0 不改。
# 4. 每次咬击实际造成生命伤害后，追加一次通用轻微击退：默认 bite_knockback_distance=10px、bite_knockback_speed=240px/s。
#    击退方向从狗指向被咬目标，只负责轻推开；wall_bounce=0、stun=0、collision_damage=0、max_wall_bounces=0，禁止借此附加眩晕或撞墙伤害。
#    必须走 ball.apply_knockback() 统一控制器，不要直接写一帧 Repel。
# 5. 本轮不改：训犬师 Max_health=700 / Damage=50、狗 Max_health=75 / Damage=50、跟随/追猎速度、标记红线、吹哨音效、
#    V201 拳击手 55~80 中距离冲刺，以及 V200 寸头猪闪避规则。
# 6. V202 修改/纳入累计更新：res://scripts/characters/训犬师.gd、res://scenes/characters/人物/训犬师.tscn、
#    res://scripts/creatures/训犬师_狗.gd、res://scenes/creatures/训犬师_狗.tscn 与本注释。
# ============================================================


# ============================================================
# V203 —— 训犬师流动虚线标记 / 冷却隐藏 / 猎犬前置咬击 Hitbox / 75 伤害
# ============================================================
# 1. 训犬师 MarkLine 继续使用 res://shaders/训犬师标记线.gdshader，但 V203 把虚线间隔改得更明显：
#    dash_count=16、dash_fill=0.38、flow_speed=1.35；Shader 使用 UV.x + TIME 持续推进虚线相位，禁止退回静态实线。
# 2. 红色扫描线最低透明度从 4% 提高到 10%。只统计训犬师当前朝向前方、仍有 health/Max_health 的真实敌人；
#    透明度按敌人到训犬师的实际距离连续增加，默认 line_reveal_distance=360：越靠近越亮，最远/无人时保持 10%。
# 3. 红线只在“没有现存 marked_target 且 whistle_action_cooldown 已结束”时显示。吹哨动作冷却期间、已有标记期间、死亡后都隐藏；
#    冷却只影响这条扫描线的显示与建立新标记资格，不删除已经建立的标记图标，也不取消已经派出的猎犬追猎。
# 4. 猎犬身体仍保留 Layer2 实体碰撞用于挡路/滑动，但 Has_Collision_Damage 必须始终为 false；普通身体接触、狗挤人、狗与狗碰撞不得结算生命伤害。
# 5. 旧 BiteArea 以狗为圆心的 42px 圆形直接伤害判定废止。bite_range=42 现在只决定 AI 何时尝试咬；真正伤害来自咬击瞬间开启的
#    嘴前 RectangleShape2D Hitbox，默认 48x30、前移 22px、持续 0.12s。只有目标真实进入这个前置矩形框才结算咬击。
# 6. 猎犬基础 Damage 从 50 提高到 75。为继续遵守 V107“召唤物从主人整体攻击力派生”，训犬师召狗时
#    master_attack_damage_multiplier 从 1.0 改为 1.5；训犬师基础 Damage=50 时狗咬基础为 75，主人攻击力变化仍按同倍率继承。
#    狗脱离主人时自身 Damage=75 作为一致的基础值；bite_damage_multiplier 仍为 1.0，禁止再叠第二套绝对伤害。
# 7. V202 的轻微击退保留：10px / 240px/s，无 stun、无 wall collision damage、无第二段伤害；只在前置咬击 Hitbox 真正造成生命伤害后触发。
# 8. V202 的狗上限3、无标记 guard_notice_radius=36、V201 的 14s 召狗/10s 吹哨冷却、训犬师700血，以及其它角色规则均不改。
# ============================================================

# ============================================================
# V204 —— 训犬师标记红线：固定虚线 / 段内流动 / 禁止整线闪烁
# ============================================================
# 1. 用户实测确认 V203 的 MarkLine 仍显示为实线，并且不接受“整条线一闪一闪”的流动表现。
#    V203 使用 UV.x 作为 Line2D 长度坐标的方案废止；训犬师 MarkLine 没有贴图，不能继续依赖该 UV 展开来生成 dash。
# 2. res://shaders/训犬师标记线.gdshader 改为在 vertex() 阶段记录 Line2D 本地 VERTEX.x，取 abs() 后作为沿线真实像素距离。
#    fragment() 只用这个稳定长度坐标生成固定 dash/gap：默认每段 10px、间隔 6px。TIME 不参与 dash_mask，
#    所以虚线段的位置、长度和透明度不会随时间整体闪烁或向前滚动。
# 3. “流动”只发生在每一小段虚线内部：TIME 仅推动 RGB 亮带在 dash 内从一端循环到另一端；
#    alpha 只由静态 dash_mask × MarkLine.self_modulate.a 决定。禁止用 TIME 调整整条线 alpha，禁止恢复呼吸/闪烁效果。
# 4. V203 的显示资格继续有效：已有 marked_target、whistle_action_cooldown 尚未结束、训犬师死亡时 MarkLine 都完全隐藏；
#    可扫描时最低 self_modulate.a=10%，前方仍有血量的敌人越靠近越亮，最高约 95%。
# 5. 本轮不改训犬师/猎犬数值、狗上限、咬击 Hitbox、75 伤害、轻击退、吹哨冷却、拳击手或寸头猪机制。
# ============================================================

# ============================================================
# V205 —— 训犬师猎犬身体零伤害 / 6秒吹哨 / 开局无冷却 / 扫描虚线整体循环流动与首人物截断
# ============================================================
# 1. 用户实测确认 V203/V204 后猎犬身体接触仍会造成伤害。根因不是场景 Has_Collision_Damage 没设 false，
#    而是公共 ball.has_collision_damage() 对 Type != Ball_Type.Ball（包含 Creature）会直接返回 true。
#    V205 训犬师_狗.gd 必须覆写 has_collision_damage()->false，并在 super._ready() 后关闭继承 $hitbox 的 monitoring、
#    monitorable、collision layer/mask 与其 CollisionShape2D。CharacterBody2D Layer2/Mask3 实体身体碰撞保留，只负责阻挡/滑动，绝不扣血。
#    猎犬唯一主动生命伤害来源继续是 BiteArea 嘴前 48x30 矩形框；75 伤害与 V202 轻击退保持。
# 2. V201 的统一吹哨动作冷却 10s 被用户确认过长。V205 whistle_action_cooldown 调整为 6.0s；14s 周期召狗、狗上限3保持。
# 3. 开局立即生成第一条狗继续保留，但该“出生初始化生成”不再刷新 whistle_action_cooldown。
#    因此比赛开始时 _whistle_action_ready() 为 true，扫描线立即可见并可立刻建立首次标记；之后周期召狗/建立标记正常进入 6s 冷却。
# 4. V204“固定 dash + 段内亮带流动”废止。V205 标记线为纯红色，RGB 永远 (1,0,0)，不做亮暗变化、不做 alpha 闪烁。
#    dash/gap 整体按 TIME 以 flow_speed_pixels 沿训犬师朝向前方平移；超过当前最大长度的部分通过 mod(line_length_px)
#    从线起点循环重新出现，形成连续传送带式流动。alpha 仍只由静态 dash mask × 距离透明度控制。
# 5. MarkDetector 继续保持完整 line_length=360 的目标发现范围；MarkLine 视觉长度独立计算。每物理帧在当前朝向的水平检测带中
#    找第一个仍有 health/Max_health、Type==Ball 且存在 Health_Bar 的人物，视觉线在其前方默认 14px 停止，
#    并把该距离传给 Shader 的 line_length_px 作为本帧循环最大长度。Creature 猎犬不会截断扫描线。
# 6. 冷却期间/已有 marked_target/死亡时红线继续完全隐藏；可扫描时最低 alpha=10%，扫描带内存活敌人越靠近越亮，最高约95%。
# 7. V205 修改：res://scripts/characters/训犬师.gd、res://scenes/characters/人物/训犬师.tscn、
#    res://scripts/creatures/训犬师_狗.gd、res://shaders/训犬师标记线.gdshader 与本注释。
# ============================================================

# ============================================================
# V206 —— 猎犬撕咬范围恢复 / 训犬师动态虚线相位稳定
# ============================================================
# 1. 用户要求猎犬“撕咬范围恢复之前的”。V202 在改成前置 Hitbox 前使用 bite_range=42px 的圆形 BiteArea；
#    V203~V205 的前置矩形只有 48x30，横向覆盖明显缩小。V206 保留“只有咬击瞬间嘴前碰撞箱才伤人”的新规则，
#    但把实际咬击箱覆盖尺度恢复到旧 42px：RectangleShape2D 改为前向深度42px、横向总宽84px，中心前移21px，
#    因此从狗中心只覆盖前方0~42px，不恢复身体后方/四周圆形伤害。bite_range=42、guard_notice_radius=36、75伤害、轻击退均不改。
# 2. V205 把每帧变化的 _current_line_visual_length 传入 Shader，并用 mod(..., line_length_px) 作为虚线循环基准。
#    第一个有血条人物正常移动时，line_length_px 会连续变化，导致整条 dash/gap 同时改变取模基准并重新排相位，出现跳动/压缩/错位。
# 3. V206 废止“动态视觉长度参与 Shader 循环周期”。训犬师标记线 Shader 不再接收 line_length_px；
#    虚线固定按 dash_length + gap_length 的世界像素周期和 TIME 平移，RGB始终纯红。动态人物距离只修改 Line2D 两点的终点，
#    因此距离变化只会裁掉/露出末端，整条已有虚线不会重新排布。
# 4. 为避免人物远离时终点突然大幅拉长，视觉长度增加时默认以 line_extend_speed=720px/s 平滑延长；
#    人物靠近时仍立即缩短到人物前 line_stop_before_character=14px，保证任何一帧都不会让红线穿过第一个有血条人物。
# 5. 虚线“整体向前流动并循环”继续保留：固定周期图案按 f(x - TIME*speed) 向前移动；超过当前 Line2D 终点的像素被几何裁剪，
#    同一固定周期的新 dash 从起点持续进入。禁止再次用动态线长作为 mod 基数，禁止段内亮度动画和整线闪烁。
# 6. V205 的猎犬身体零碰撞伤害、训犬师6秒吹哨冷却/开局无冷却、狗上限3、14秒召狗，以及其它角色规则继续有效。
# ============================================================

# ============================================================
# V207 —— 训犬师扫描带扩大 / 红线按垂直接近渐显 / 猎犬空间感知跟随
# ============================================================
# 1. 用户确认 V206 的标记检测带仍偏小。V207 将 line_detector_half_height 从 18px 扩大到 80px；
#    MarkDetector 仍是训犬师朝向前方的水平长条，长度 line_length=360 不改。扩大的是红线上下的检测宽度，不扩大水平射程。
# 2. V203~V206“按敌人到训犬师的总距离决定红线透明度”的规则废止。V207 红线透明度只由
#    “前方存活敌人的真实身体边缘到水平红线还差多少垂直距离”决定。默认 line_reveal_distance=80：
#    gap>=80 时保持最低 10%；gap 从 80 向 0 连续缩小时透明度连续升高；敌人身体边缘真正碰到红线(gap=0)时必须为 100%。
#    水平距离只决定敌人是否位于 line_length 前方范围内，不参与 alpha 强弱。
# 3. 红线仍只在无标记且 6s 吹哨动作冷却结束时显示；虚线固定 10px dash + 6px gap、纯红、整体向前循环流动。
#    V206 的固定世界像素相位继续有效，动态终点只裁剪 Line2D，不得再次影响 dash 相位。
# 4. “第一个检测到的有血条人物前停止”继续保留，但检测人物是否进入扫描带时改用人物真实身体边缘到线的 gap，
#    不再只看人物中心 y。人物靠近时线立即缩短，人物远离时平滑延长。
# 5. 猎犬 FOLLOW/RETURN 新增空间感知恢复：理想跟随点仍是主人后方，但如果上一帧撞到 Layer1 墙、
#    理想后方点被墙/其它角色占住、或狗到理想点的直线路径被墙挡住，则进入临时 recovery。
# 6. recovery 时狗不会立即硬拐回固定后方，而是在主人附近约 58px 环带内，从当前所在侧、后侧、左右侧等候选中
#    选择“自身约24px净空且狗到候选无墙阻挡”的可达接近位置。该位置只是临时落脚，实体 CharacterBody2D 碰撞仍正常。
# 7. 理想主人后方必须连续约0.55s同时满足“点位有空间 + 当前狗到该点无墙阻挡”，才允许退出 recovery 回归正常后方跟随；
#    这样狗撞墙/反弹后会先在有空间的位置靠近主人，等真正有足够空间再回后面，不会立即贴墙硬转。
# 8. 本轮不改：狗上限3、无标记警戒36、咬击范围42、前置42x84咬击框、75伤害、轻击退、
#    训犬师700血/14s召狗/6s吹哨，以及拳击手、寸头猪等其它累计规则。
# ============================================================


# ============================================================
# V208 —— 训犬师水平线吹哨判定 / 扫描范围扩大 / 猎犬连续空间跟随
# ============================================================
# 1. 用户实测 V207 猎犬空间恢复不够丝滑，并会出现直接停住。根因是 _pick_follow_staging_target() 在所有候选都因墙/角色净空失败时
#    返回 global_position；随后 _steer_toward() 认为已到目标，直接 Speed=0、direction=ZERO。V208 禁止以“原地等待”作为 recovery 失败兜底。
# 2. FOLLOW/RETURN 的空间恢复改为每物理帧连续求目标：主人后方有空间时仍以原理想跟随点为目标；撞 Layer1 墙、理想点被占或直线路径被墙挡时，
#    在主人附近多半径/多方向寻找可达接近位，并用 follow_target_response=7.5 的指数响应平滑目标点，取消 V207 每0.30s 离散重选导致的折线/顿挫。
# 3. 若当前没有任何满足净空+直线路径的临时点，必须继续移动：有最近墙法线时把“朝理想点”的向量投影到墙切向并沿墙滑；没有墙法线时持续朝主人附近接近。
#    真正墙体碰撞继续交给 CharacterBody2D.move_and_slide()；禁止返回自身位置导致停住。recovery 时 stop radius 缩到3px、近距离最低速度比例提高到0.32。
# 4. 为降低“明明有路却被24px净空判死”的概率，临时位置净空半径从24px调为18px；主人附近 staging 半径约62px；
#    理想后方连续有空间约0.45s后才退出 recovery，仍遵守“撞墙后先到接近且有空间的位置，等后方真正空出来再回去”的设计。
# 5. 训犬师扫描范围“再加一点”：水平 line_length 360->420px；红线渐显/视觉截断使用的上下检测带从 ±80px 扩到 ±100px，
#    line_reveal_distance 同步为100px。该宽带只负责视觉渐显和第一个有血条人物的视觉截断，不再直接代表吹哨命中。
# 6. V207“进入宽 MarkDetector 就可吹哨”的判定废止。真正 _closest_detected_enemy() 改为沿当前朝向左/右水平线扫描：
#    目标必须在前方0~420px内，且人物真实碰撞身体边缘到红线的垂直 gap <= whistle_line_vertical_tolerance=4px 才能建立标记。
#    因此 y 轴相差很大的敌人可以使红线按距离渐显，但绝不能触发吹哨；只有真正靠到训犬师左/右这一条线上才标记。
# 7. 红线 alpha 规则保持 V207：按敌人身体边缘到线的垂直 gap 从最低10%连续升到碰线100%；纯红固定像素虚线整体流动、动态终点相位稳定等规则不改。
# 8. 本轮不改：训犬师700血/6s吹哨/14s召狗/狗上限3、猎犬75伤害/42px咬击范围/42x84前置咬击框/轻击退、拳击手与寸头猪其它累计规则。
# ============================================================

# ============================================================
# V209 —— 训犬师猎犬护主检测扩大 / 实体接触必咬
# ============================================================
# 1. 用户实测 V208 猎犬无标记检测仍偏小，并出现“身体已经撞到敌人却不攻击”。
#    V209 将 guard_notice_radius 从36px提高到56px，但不恢复成无限追猎；标记后的 HUNT 规则仍完全独立。
# 2. 旧 FOLLOW/GUARD 使用 TOOLS.nearest_enemy(self,guard_notice_radius) 的中心点距离判定废止。
#    V209 改成以猎犬为中心创建真实 CircleShape2D 物理感知圈，collision_mask=2；只要该感知圈与敌人 CharacterBody2D
#    的实体碰撞体重叠就进入护主锁定。大型角色因此按身体边缘进入范围，而不是必须等中心点进入56px。
# 3. bite_range=42px 与 V206 的42x84嘴前咬击 Hitbox保持不变，不扩大实际撕咬伤害范围。
#    但“允许开始咬”的触发新增实体接触兜底：上一轮 move_and_slide() 已确认撞到目标，或双方 CollisionShape2D
#    按连心线方向的真实支撑半径已经接触（额外3px安全余量）时，必须允许启动咬击。
#    因此禁止再次出现“狗已经物理撞住敌人，却因为两个中心距离>42而不咬”的情况。
# 4. 真正生命伤害仍只能由 BiteArea 前置矩形 Hitbox 真实覆盖后结算75伤害；猎犬身体碰撞仍为0伤害，
#    V202轻击退、狗上限3、训犬师700血/6s吹哨/14s召狗、V208水平线吹哨与连续跟随规则均不改。
# ============================================================


# ============================================================
# V210 —— 猎犬攻击取消额外冷却 / 训犬师红线不被友军截断
# ============================================================
# 1. 用户要求猎犬攻击不应存在额外 cooldown：只要敌人仍在当前护主感知/追猎范围内，且猎犬此刻没有正在执行一口咬击，
#    当前咬击动作一结束就允许立刻开始下一口。V209 的 bite_cooldown=1.0 与 _bite_cooldown_left 计时链全部废止。
# 2. “不在攻击”按这一口自身动作时间判定，而不是攻击后的等待时间：默认取 bite_visual_duration=0.22s 与
#    bite_hitbox_active_time=0.12s 的较大值。BiteArea 仍只在0.12s有效窗内造成一次75伤害；动作结束后没有额外冷却。
# 3. 无标记 GUARD 状态咬出一口后不再强制切 RETURN；只要敌人仍被56px真实物理感知圈检测到/实体接触并满足咬击触发，
#    猎犬会继续追近并在上一口动作结束后再次咬。敌人离开感知范围后才恢复正常 FOLLOW。
# 4. 标记 HUNT 状态同样不再“咬中一次就立即结束追猎”；hunt_timeout 与目标有效性仍是追猎结束条件，
#    因此标记期间目标持续在咬击范围内时可以连续攻击，但同一时刻绝不会重叠开启两次咬击动作。
# 5. 训犬师红线视觉截断修复：_first_healthbar_character_forward_distance() 只允许 TOOLS.is_enemy(self,candidate)==true
#    的存活有血条 Ball 截断扫描线。己方普通角色即使站在红线上也不缩短 MarkLine、不遮挡后方敌人；
#    红线透明度与真正吹哨判定原本就只统计敌人，继续保持。
# 6. 本轮不改：猎犬75伤害、42px咬击范围、42x84前置咬击框、56px无标记物理感知、身体0伤害、轻击退、
#    狗上限3；训犬师700血/6s吹哨/14s召狗、V208水平线吹哨、V209实体接触必咬及其它累计规则均继续有效。
# ============================================================


# ============================================================
# V211 —— 猎犬极短攻击冷却 / 仅训犬师周围允许持续连咬
# ============================================================
# 1. 用户要求在 V210“完全无额外攻击冷却”的基础上恢复一个很短的攻击间隔。V211 新增 bite_cooldown=0.12s。
#    bite_visual_duration 默认约0.22s、bite_hitbox_active_time约0.12s；本次冷却按“本口动作时长 + 0.12s”计时，
#    所以不是与攻击动作重叠消耗，而是当前一口结束后再等待约0.12s才允许下一口。
# 2. 新增 continuous_attack_owner_radius=96px。只有猎犬自身仍在训犬师96px范围内时，GUARD/HUNT 才允许在短冷却后持续连咬。
# 3. 猎犬如果追敌追出训犬师96px范围，仍允许完成已经满足条件的当前这一口，但随后必须结束远距离持续压制：
#    GUARD 立即切 RETURN；HUNT 调用 _finish_hunt(true) 结束本狗追猎并回主人。禁止在远离训犬师的位置无限连咬。
# 4. 标记机制仍可以把狗派出去追猎；限制的是“持续重复攻击”，不是禁止远距离追猎本身。狗在远处接触目标最多打一口后回归。
# 5. V209 的56px真实物理感知、实体接触必咬、42px撕咬触发、42x84嘴前Hitbox、75伤害、身体0伤害、轻击退继续有效。
# 6. 本轮不改训犬师700血、红线/水平吹哨、6s吹哨动作冷却、14s召狗、3狗上限，以及拳击手/寸头猪其它累计规则。
# ============================================================

# ============================================================
# V212 —— 训犬师红线只按真实水平阻挡截断 / 猎犬攻击前主人范围硬门槛 / 每口必回
# ============================================================
# 1. 修复 V211 红线“前方看似没有东西却偶尔提前截断”：V208~V211 的 _first_healthbar_character_forward_distance()
#    仍使用 line_detector_half_height=100px 的宽渐显带作为视觉截断条件，因此敌人即使与水平红线还有明显 Y 轴空隙，
#    只要进入 ±100px 渐显带也会把 MarkLine 提前截短。V212 明确废止“宽渐显带参与截断”。
# 2. line_detector_half_height=100px / line_reveal_distance=100px 继续只用于红线透明度渐显；视觉截断只允许真正敌方、存活、
#    有 Health_Bar 的普通 Ball，且其真实碰撞身体边缘到水平红线的 gap <= whistle_line_vertical_tolerance（默认4px）时发生。
#    己方单位继续完全不截断；上下仍有明显空隙的敌人也不截断。真正吹哨判定仍沿用同一4px水平线容差。
# 3. 修复 V211“狗仍会在不在训犬师边上时攻击”：旧逻辑先 _try_bite()，开咬后才检查96px主人范围，因此远处第一口仍可发生。
#    V212 将 continuous_attack_owner_radius=96px 改成所有咬击的前置硬门槛；_try_bite() 自身也二次校验，狗不在训犬师96px内绝不开始攻击。
# 4. HUNT 追猎如果狗已经离开主人96px范围，立即结束本狗追猎并 RETURN；FOLLOW/GUARD 如果因碰撞/移动暂时离开96px，
#    即使脚边有敌人也先回主人，不允许开启新咬击。这样主人范围限制不再只是“限制连咬”，而是限制所有主动咬击的开始。
# 5. 用户要求“每次攻击都要回去”。V212 新增每口必回状态：任何 GUARD/HUNT 咬击一开始就记住本口来源，等本口约0.22s动作与
#    0.12s BiteArea 有效窗完整结束后，GUARD 强制切 RETURN；HUNT 调用 _finish_hunt(true) 并切 RETURN。无论是否实际命中，
#    都必须先回到训犬师后方跟随位附近（默认距理想跟随点<=18px），之后才可能再次出击。禁止站在敌人旁边连续循环咬击。
# 6. V211 的 bite_cooldown=0.12s 仍保留，但它不再允许原地连续攻击；短冷却只是在每口攻击节奏上的下限，真正下一口还受“已回主人附近”约束。
# 7. 本轮不改：猎犬75伤害、56px无标记物理感知、42px撕咬触发、42x84嘴前Hitbox、身体0伤害、轻击退、3狗上限；
#    训犬师700血、420px扫描长度、100px渐显带、6s吹哨/14s召狗，以及其它累计角色规则均保持。
# ============================================================

# ============================================================
# V213 —— 寸头没事沙漠溜达猪：实测弹道追踪 / 持续侧移闪避 / 单次物理落地
# ============================================================
# 1. 用户再次实测确认 V200~V212 的寸头猪仍几乎不会实际躲弹，表现为看到子弹后只转向/行为异常但没有形成可见侧移。
#    V213 废止“主要依赖投射物公开 direction/Speed/velocity 字段判断真实轨迹”的前提：项目里存在 Area2D/Node2D 直接改
#    global_position、私有 _velocity、曲线/自定义运动等 shooter，公开字段不能代表所有实际飞行速度。
# 2. V213 对已确认 shooter/BattleTransient/项目 scripts/shooter/ 与 scenes/shooter/ 节点持续记录 global_position；从连续物理帧
#    的真实世界坐标差计算 measured velocity。真实采样速度优先于公开字段；刚出生尚无第二帧样本时才使用 velocity/direction+Speed/speed/
#    travel_speed/move_speed 作为首帧兜底。这样猎人霰弹、军火商弹、CharacterBody2D 石头、Node2D 剑气以及私有速度旧弹都能统一进入弹道预测。
# 3. 投射物发现不再只依赖 node_added 瞬间：每帧补扫 Shooter/BattleTransient/HunterPellet/ArmsDealerProjectile/CouPenguinRock 等现有 group，
#    并按 projectile_rescan_interval 低频递归现有场景，识别 res://scripts/shooter/ 与 res://scenes/shooter/ 既有资源；不得创建新 shooter 目录。
# 4. 旧威胁预测把“猪上一帧自己的 velocity”混进 relative_velocity，猪一旦侧移一帧，下一帧就可能被算法判定为已经避开并立刻取消，
#    肉眼表现成只转一下方向。V213 威胁判定改为以投射物实际运动轨迹相对猪当前所在区域求最近点，不再用猪上一帧速度抵消来弹。
# 5. 一旦确认真实来弹并选定左右侧，新增 projectile_dodge_commit_time，默认至少约0.34s持续沿该侧实际移动；同一段承诺期间禁止因为
#    下一帧预测轻微变化立刻回普通移动。只有锁定方向真实撞墙/出界才允许提前取消/换边。dodge_side_lock_time 原锁边规则继续有效。
# 6. V200 的“先 super.tick_physics(State.Stand) 再自行第二次 move_and_slide()”双移动时序在 V213 废止。威胁/飞扑本帧的完整逃生速度
#    直接写入 Repel，且只调用一次公共 ball.tick_physics(State.Stand)->stand()->move_and_slide()；实体碰撞、墙反馈、crowd separation 继续走公共链。
# 7. 友军弹识别同时兼容 Team 与 team 小写字段；同队投射物不得触发闪避。已经停止移动的投射物会清除旧 measured velocity，禁止残留旧速度造成假威胁。
# 8. V213 不改角色基础数值：Speed=92、Max_health=520、Skill_Cooling=5.5、飞扑倍率/阶段时间、地图外袭击者机制继续保持；无真实弹道威胁时
#    仍交回普通 ball/World 移动，敌对人物只作为次级空间威胁。后续如再调整寸头猪，V213 的“真实轨迹优先 + 至少一段可见侧移”是新的基线。
# ============================================================

# ============================================================
# V214 —— 寸头没事沙漠溜达猪：威胁显示同源 / 全局锁向 / 禁止原地转圈
# ============================================================
# 1. 用户实测 V213 仍会在有子弹时原地左右转向，且要求“所有威胁检测必须和 设置 中的威胁显示一致”。
#    根因是 V213 猪脚本仍维护独立 projectile tracker / shooter 猜测链，而设置里的威胁显示来自
#    res://scripts/training/combat_threat_analyzer.gd；两套来源不同，显示与实际规避天然可能不一致。
# 2. V214 起猪本体规避禁止再使用 _find_best_projectile_threat() / _projectile_threat_info() 作为主动规避数据源。
#    旧 projectile tracker 只允许继续服务“地图外来客投射物出生即入场”兼容流程，不得再决定猪往哪躲。
# 3. CombatThreatAnalyzer 新增 get_display_damage_threats_for(receiver)：直接复用威胁调试层 _debug_threats 中
#    与设置威胁显示完全相同的 debug_role=damage（或按 damage 推导为 damage）的白/红真实伤害几何；
#    蓝色 detection 和绿色 collision 不属于伤害威胁，不进入猪规避。Training_Debug_Mode 只控制绘制开关，
#    不改变这份同源数据，因此关闭显示时猪仍按同一套几何工作。
# 4. 对同源 damage 几何只做 receiver 敌我过滤；CollisionShape2D 精确 polygon 会附带稳定 debug_shape_id，
#    猪用同一几何中心连续采样得到真实运动速度，兼容 Area2D/Node2D/CharacterBody2D 直接改位置的旧飞行物。
# 5. 猪对 circle / rect / segment / polygon 四类显示几何统一计算“当前及未来最近距离”；移动红框按真实采样速度预测，
#    静态/前摇伤害区按显示几何本身避让。也就是说以后新增一种能在设置威胁显示中画成白/红 damage 的机制，
#    猪会自动把它纳入同一套规避，不再为角色名或 shooter 文件单独写识别表。
# 6. V213 的“按当前最强一颗弹切左右侧”进一步废止。V214 对当前全部危险显示几何同时给候选方向评分，
#    最终逃生方向使用全局锁：默认至少约0.72s内只要该方向没有真实撞墙/出界，就禁止因为另一颗弹成为最高威胁而翻到另一侧。
#    锁结束后也只有其它方向明显更安全（默认优势>=24）才换向；禁止逐物理帧左右反转造成原地转圈。
# 7. 普通闪避与紧急飞扑必须调用同一个 _select_display_dodge_direction()。飞扑期间也遵守同一个全局锁，
#    不得另取“主子弹”方向重新纠偏；真正位移仍通过一次公共 ball.tick_physics(State.Stand)->Repel->move_and_slide() 落地。
# 8. 当前没有任何同源 damage 几何在预测窗口内逼近时，猪完全交回普通 ball/World 移动；不再额外把普通敌人距离
#    当成另一套“隐藏威胁”。因此设置威胁显示看不到的普通人物本体（且没有碰撞伤害/活动Hitbox）不会让猪凭空躲避。
# 9. 本轮不改寸头猪 Speed=92、Max_health=520、Skill_Cooling=5.5、飞扑阶段数值、地图外袭击者频率/入场规则；
#    V212 训犬师/猎犬、V201拳击手等其它累计规则保持不变。
# ============================================================

# ============================================================
# V215 —— 三角洲跑刀仔：真实物资图 / 品质价格 / 大小价值 / 无限钱 / 保险贴图
# ============================================================
# 1. 用户提供 三角洲物品.zip 共32张物品图，以及 保险.png。现有角色文件继续保持
#    res://scripts/characters/三角洲/跑刀仔.gd / res://scenes/characters/三角洲/跑刀仔.tscn，禁止为了“跑刀鼠”口语称呼改名。
# 2. 新素材统一接入 res://Images/characters/三角洲/跑刀仔/，保持用户原文件名；保险.png 只作为地图边缘保险的视觉贴图。
#    不创建 images/、scripts/Characters/ 等同义目录，不生成 .import 源包缓存。
# 3. 第一命普通物资不再使用绿色矩形占位；每个物资节点显示真实 Sprite2D，并用轻量品质底板区分白/蓝/紫/金/红。
#    用户明确只要这5档，不新增绿色档。生成先抽品质再抽该品质图片，默认概率约：白38%、蓝27%、紫18%、金10%、红6%、无限1%。
#    因此素材数量多不会反向把红色/无限钱刷率放大。
# 4. V215 跑刀仔内部钱单位属于本项目成长点，不等同实时交易行哈夫币。各图片保持不同价值：
#    白=5/6/7/8/9；蓝=12/14/16/18，子弹零件(大)=26；
#    紫=22/25/28/31，咖啡豆=34，大紫=42、大紫2=48；
#    金=40/45/50/55；
#    小红=65/70/75/80，中红=90，大红=115/125/135，大大红=185。
#    同品质大件必须高于小件；大大红必须高于所有普通大红。
# 5. 无限钱.png / 无限钱2.png 为独立极稀有档。第一命捡到任意一个后 has_infinite_money=true，money 对外显示可用“∞”；
#    GDScript int 没有数学无穷，因此第二命购买链用独立无限钱布尔 + 100000 虚拟预算结算，避免直接拿20亿参与倍率造成溢出/显示异常。
#    捡到无限钱后其它普通物资/保险不再增加有限 money，但无限钱状态不会丢失。
# 6. 保险仍按旧机制随机生成在地图边缘、进入 interact_radius 后定身开锁、离开范围清零进度；视觉从金色 Polygon2D 占位改成用户的保险.png。
#    safe_money 默认由60调为100，使保险继续明显高于常见白/蓝/紫小件，但大红/大大红仍可以成为更高价值 jackpot。
# 7. 物资显示大小按小/中/大/大大做视觉尺度；真正拾取仍沿用 interact_radius，不给物资添加伤害/实体碰撞，不改变第一命跑刀移动逻辑。
#    第一命致死后的第二命购买公式、恢复攻击、清理残余物资/保险、第二命正常死亡等 V185 规则继续保留。
# 8. V215 新增/修改：res://scripts/characters/三角洲/跑刀仔.gd、
#    res://Images/characters/三角洲/跑刀仔/（32张物品 + 保险.png）以及本注释。跑刀仔场景路径与文件名不改。
# ============================================================

# ============================================================
# V216 —— 跑刀仔：保险左右墙与高层级 / 物资持续刷新 / 无背景 / 品质爆闪回弹出生
# ============================================================
# 1. 用户要求保险视觉不能被地图背景/边界墙遮住。V216 的跑刀保险根 Node2D 使用 z_as_relative=false、z_index=120，
#    不再继承 World 的负 Z；保险因此稳定绘制在普通地图 TileMap/边界墙视觉之上。保险仍无实体伤害/碰撞，仅用于第一命开锁交互。
# 2. 保险只允许生成在地图左墙或右墙，不再生成在上/下墙。safe_count 仍是整局固定保险数量；偶数数量默认左右均分，
#    奇数时只会多出一侧。用户提供的保险.png 默认朝右，因此左墙保持 flip_h=false 朝地图内，右墙必须 flip_h=true 朝左、同样朝地图内。
# 3. V215 的普通物资“开局一次性生成 supply_count 个”废止。supply_count 从 V216 起表示场上普通物资软上限，
#    开局普通物资为0，首次随机延迟约0.9~1.8s后开始生成；之后默认每1.4~2.8s生成1个，场上未拾取数量达到软上限时暂停，
#    被拾取后会继续补刷。因此普通物资整局总数不固定，只有保险数量固定。第一命结束时仍统一清理所有残余物资/保险。
# 4. 所有真实物资 Sprite2D 删除 V215 的品质 Polygon2D 背景板；正常静止时只显示用户原物资贴图，不加白/蓝/紫/金/红底色。
# 5. 新物资出生必须播放“突然变大并回弹”：初始约0.28倍尺寸，约0.13s快速冲到1.38倍，随后约0.09s回到0.90倍，
#    最后约0.11s回弹到正常1.0倍。使用 Godot Tween 过渡，不改变物资拾取半径、价格或品质概率。
# 6. 新增 res://shaders/跑刀仔物资出生闪光.gdshader。出生瞬间 Sprite 保留原贴图 alpha 轮廓，但 RGB 100%替换为当前品质纯色；
#    约0.055s闪一下后，在约0.18s内快速恢复原贴图颜色。白/蓝/紫/金/红/无限均使用各自 _quality_color；正常状态不持续染色。
# 7. V215 的物资价值、品质抽取概率、大小价值关系、大大红最高于普通大红、无限钱语义、保险100钱/2.4s开锁等规则继续有效。
#    本轮不改跑刀仔第二命购买公式、人物数值、拾取 interact_radius，也不改其它角色累计规则。
# 8. V216 新增/修改：res://scripts/characters/三角洲/跑刀仔.gd、res://shaders/跑刀仔物资出生闪光.gdshader、res://global/注释.gd。
#    已有32张物资图与保险.png 继续沿用 V215 的 res://Images/characters/三角洲/跑刀仔/ 原路径和原文件名。
# ============================================================

# ============================================================
# V217 —— 跑刀仔：物资搜索/拾取分品质音效 / 保险开启音效时长同步
# ============================================================
# 1. 用户提供 5 个三角洲音效并要求正式接入跑刀仔：
#    res://audio/characters/三角洲/搜索紫以下.MP3（约0.914s）、搜索金以上.MP3（约2.011s）、
#    紫以下拾取(1).mp3（约0.180s）、金以上拾取.mp3（约2.000s）、三角洲开保险.MP3（约6.687s）。
#    素材保持用户原文件名和扩展名大小写，不另建 Audio/Voices 等同义目录。
# 2. 普通物资每次真正刷新出生时播放“搜索”音效：白/蓝/紫统一使用 搜索紫以下.MP3；金/红/无限统一使用 搜索金以上.MP3。
#    搜索音效从该物资的世界位置使用 AudioStreamPlayer2D 一次性播放；多个物资刷新允许各自自然播放，不把音频绑在随后会被拾取释放的物资节点上。
# 3. 物资真正拾取时播放“拾取”音效：白/蓝/紫统一使用 紫以下拾取(1).mp3；金/红/无限统一使用 金以上拾取.mp3。
#    无限钱仍属于“金及以上”音效组；是否已获得无限钱只影响钱数，不影响拾取反馈音效。
# 4. 保险节点新增 OpenAudio，使用 三角洲开保险.MP3。进入 interact_radius 并开始开保险时从0秒开始播放；离开范围、切换保险或中断时
#    音效立即 stop 且开锁进度归零；重新靠近后音效和开锁进度都从头开始，禁止声音继续播但进度重置或反过来不同步。
# 5. 保险实际开锁耗时不再固定依赖旧 safe_open_time=2.4s。正常运行时直接读取 OpenAudio.stream.get_length() 作为本次开锁总时长，
#    因此当前用户音效约6.687s就需要持续开约6.687s，音效结束与保险开启在同一时长边界完成。safe_open_time=6.687只作为音频加载失败时兜底。
# 6. V216 的保险只左右墙/右墙翻转/高Z、物资持续刷新、无品质背景、出生爆发回弹和品质纯色闪光；V215 的品质价值/无限钱/第二命购买规则均保持。
# 7. V217 新增/修改：res://scripts/characters/三角洲/跑刀仔.gd、res://global/注释.gd，以及上述5个 res://audio/characters/三角洲/ 原名音效文件。
# ============================================================

# ============================================================
# V218 —— 跑刀仔：分层刷新概率 / 保险高价值1~3格搜索 / 拾取吸附 / 物资与保险尺寸调整
# ============================================================
# 1. 地面普通物资从 V218 起使用更陡的品质概率：白45%、蓝30%、紫17%、金6.5%、红1.4%、无限0.1%。
#    无限钱.png / 无限钱2.png 仍在同一“无限”池内等权抽取，因此单张约0.05%，是所有素材里最低刷新概率。
#    同品质内部也按尺寸降权：中约0.78、大约0.52、大大约0.22；所以高价值大件不会和普通小件等概率。
# 2. 用户明确“不会出子弹零件和咖啡豆”。V218 将 子弹零件.png / 咖啡豆.png 从 ITEM_POOLS 可生成项移除；
#    两张素材文件仍保留在 Images/characters/三角洲/跑刀仔/，禁止删除或改名，但地面与保险均不再随机生成它们。
# 3. 保险不再固定直接给 safe_money。开始开启某个保险的第一刻就一次性确定本保险最终战利品，避免中途取消后反复重抽；
#    每个保险随机1~3件（默认约50%/35%/15%），保险专用品质池保底紫色：紫54%、金30%、红15.8%、无限0.2%。
#    因此保险相对地面显著提高高价值概率，但无限钱仍保持极低概率；同一保险尽量避免重复同名图片。
# 4. 保险继续使用 V217 的 三角洲开保险.MP3 实际音频长度作为持续开启时间。开锁完成的同一刻保险实体直接消失，
#    然后在原保险位置更靠地图外的一侧显示1~3个竖向格子。格子内容早在开锁开始时已经确定，但搜索结束前保持隐藏。
# 5. 保险搜索显示中央使用代码绘制的放大镜 Line2D 图标，搜索期间左右晃动约1.05s；结束后格子中的真实物资贴图逐个显现，
#    并继续使用品质纯色爆闪/回弹出生视觉。格子短暂停留后，物资自动飞向跑刀仔并结算，避免墙外展示结果成为不可拾取死物。
#    三角洲原版“保险按格子展示搜索结果”的观感只作布局参考；本项目掉落数量、概率、价值仍以本注释和用户要求为准。
# 6. 普通地面物资拾取从“接触后立刻消失/结算”改为吸附动画：进入 interact_radius 后从地面池移除，物资每物理帧追踪
#    跑刀仔当前 global_position 飞过去并持续缩小，约0.34s或进入3px内才真正播放拾取音效、结算钱并释放；跑刀仔移动时物资会跟随弯曲吸附。
# 7. 地面物资整体缩小：普通小件约18px目标边长，中件约21px；只有素材明确标注“大”的约29px，“大大”约36px。
#    出生爆大/回弹动画仍按这个新的最终基准比例播放，不重新加入品质背景。
# 8. 保险视觉从约48px缩到约36px，并从左右边界内侧8px改为墙外约18px；safe_interact_radius 独立提高到52px，
#    确保保险更靠地图外但仍可从墙内持续开启。保险仍只出现在左右墙、右墙水平翻转、绝对高Z显示规则不变。
# 9. V218 修改：res://scripts/characters/三角洲/跑刀仔.gd、res://global/注释.gd。V217音效、V216出生Shader和全部物资/保险原图继续沿用原路径。
# ============================================================

# ============================================================
# V219 —— 跑刀仔：保险搜索UI原位覆盖 / 保险缩小渐隐转场
# ============================================================
# 1. V218 的保险已经位于左右边界墙外约18px，但搜索结果 display 又按左右墙额外向地图外偏移46px；
#    这会产生“二次外推”，使搜索格/放大镜在部分分辨率或镜头位置下完全跑出屏幕。V219 废止这层额外偏移。
# 2. 从 V219 起，保险搜索 display.global_position 必须严格等于保险完成开启时的 global_position；
#    搜索格、放大镜和随后显示的战利品都以保险本体位置为中心，不再生成在保险旁边或更靠墙外的位置。
# 3. 保险开启完成时不再瞬间 queue_free。搜索 display 先以更高绝对 Z 覆盖到保险同一位置，随后保险本体在原地约0.20s内
#    缩小到约0.56倍并渐隐到 alpha=0；淡出结束后才释放保险节点。搜索框因此会视觉上“盖住正在消失的保险”。
# 4. V218 已确定的保险1~3件提前抽取、格子搜索、放大镜晃动、保底紫及高价值概率、结果自动吸附结算等规则不变；
#    本轮只修保险->搜索UI的空间锚点和转场表现，不改保险生成位置、交互半径、音效时长或掉落概率。
# 5. V219 修改：res://scripts/characters/三角洲/跑刀仔.gd、res://global/注释.gd。
# ============================================================

# ============================================================
# V220 —— 跑刀仔：保险搜索框深灰渐变美化 / 放大镜丝滑摆动与小角度变化
# ============================================================
# 1. V219 的保险搜索UI空间锚点继续保持：搜索 display 必须严格覆盖保险原 global_position，禁止再次向墙外偏移。
# 2. 用户要求搜索框视觉改为“灰白色描边 + 深灰色填充 + 填充有渐变效果”。V220 不新增外部图片或同义 UI 目录，
#    直接在跑刀仔脚本运行时绘制：外层柔和黑色投影；主面板由上部稍亮、下部更深的12级深灰纵向渐变组成；
#    外框使用接近冷灰白的高不透明描边，内部再加一层低透明冷白细线和顶部高光。1~3个战利品格子使用低对比深灰内框，
#    保持物资图片本身是视觉主体，不用品质色污染保险搜索框。
# 3. V218/V219 的旧放大镜动画仅快速把 rotation 在 ±0.34rad 间每0.09s来回切换，视觉上会机械抖动；该实现从V220废止。
# 4. V220 放大镜使用 Godot Tween 的 TRANS_SINE + EASE_IN_OUT，半周期约0.38s：X约在 -4.4~+4.4px 间平滑摆动，
#    Y只做约 -1.1~+1.3px 的轻微浮动，rotation 同步在约 -5°~+5.5°之间缓慢变化。循环首尾使用同一位置和角度，
#    因此循环连接处不会瞬间跳角或跳位置；搜索完成后立即 kill Tween 并移除放大镜。
# 5. 放大镜本体改为冷灰白描边，并在右下方增加轻微暗色轮廓阴影，使其在深灰渐变搜索框上更清楚；
#    不改变 V218 已确定的1~3件战利品、保底紫/高价值概率、结果显示和自动吸附结算流程。
# 6. V220 修改：res://scripts/characters/三角洲/跑刀仔.gd、res://global/注释.gd。V219及之前全部累计机制继续保留。
# ============================================================

# ============================================================
# V221 —— 跑刀仔：保险3x3真实占格 / 指定掉落池 / 搜索UI简化缩小
# ============================================================
# 1. V220 搜索UI过度装饰（投影、双描边、顶部高光、逐格独立框）从本版废止。保险搜索面板固定为3x3背包，
#    视觉只保留：深灰纵向渐变填充、与填充接近的单层灰描边、四条低对比3x3分隔线。禁止再叠额外高亮内框/逐格描边。
# 2. 面板固定3x3，每格约13px，整体约43px见方，明显小于V220按1~3件纵向拉长的搜索框；仍严格覆盖保险原global_position。
# 3. 保险可出物资从V221起严格限制为用户点名列表：大紫.png（大紫1）、大紫2.png、小红.png（小红1）、小红2.png、
#    大红2.png、大红3.png、无限钱.png（无限钱1）、无限钱2.png、紫2.png、金.png（金1）、金2.png、金3.png、金4.png。
#    其它白/蓝/紫3/紫4/小红3/小红4/中红/大红1/大大红等不再进入保险池；地面刷新池不受本条影响。
# 4. 保险3x3占格固定：大紫1=3x2，大紫2=2x3，大红2=3x2，大红3=2x3，紫2=1x2，其余均1x1。
#    “横向格子数x纵向格子数”按用户定义解释。每个保险最多占用3x3共9格，所有结果在开锁开始时即完成抽取和排布。
# 5. 排布按3x3从左上到右下顺序寻找第一块可用矩形区域；候选物品若当前剩余空间放不下则重新抽取，不允许互相重叠或超出3x3。
#    紫2允许在必要时由1x2旋转为2x1。例如已有一个3x2占据前两行时，后续1x2会横放到剩余底行，而不是越界或遮住前物品。
#    大紫/大红的大型2x3或3x2保持用户指定默认朝向，不为了硬塞而随意旋转；放不下时改抽其它可放物资。
# 6. 搜索结束后物资贴图按各自真实占格矩形居中缩放显示；被旋转的紫2贴图同步旋转90°，不只改逻辑占格。
# 7. 保险内部仍保持“高价值更常见、无限钱最低”的既有方向；本轮仅把可出清单和空间规则硬化。1~3件提前确定、放大镜搜索、
#    保险缩小渐隐、结果最终吸附到跑刀仔、开保险音效同步等V217~V220规则继续有效，除非与本V221明确覆盖内容冲突。
# 8. V221 修改：res://scripts/characters/三角洲/跑刀仔.gd、res://global/注释.gd。未新增项目图片、Shader、音效或同义目录。
# ============================================================

# ============================================================
# V222 —— 跑刀仔：主人删除/死亡清场 / 保险逐件品质搜索 / 未搜索问号条纹遮罩 / 保险音量提高
# ============================================================
# 1. 用户反馈跑刀仔人物被删除或最终死亡后，之前生成在 current_scene 下的地面物资、保险和保险搜索UI仍会残留。
#    根因是这些节点不是跑刀仔的子节点，释放跑刀仔不会自动级联释放。V222 新增统一 _cleanup_runner_loot()：清理普通物资、保险、
#    正在吸附拾取的物资和仍在运行的保险搜索display，并停止当前保险音频、清空引用。第一命购买复活继续调用这份清理；最终 Die() 在死亡时
#    立即清理；_exit_tree() 作为手动删除/换场景/queue_free 的最后兜底，禁止留下无主 BattleTransient 战利品。
# 2. V221 的“整个保险只跑一次统一搜索时长，然后一次性揭开全部物品”从本版废止。保险内容仍在开始开启时一次性确定且3x3排布不变，
#    但开启完成后的搜索UI改为逐件处理：放大镜先在第一件物品占格上搜索，完成后只揭开第一件，再移动到下一件，直到全部搜完。
# 3. 每件保险物资搜索耗时从 V222 起按品质递增，默认：紫约0.68s、金约0.96s、红约1.34s、无限钱约1.72s。
#    safe_search_duration=1.05仅保留为未知品质/旧数据兜底。品质越高必须越慢，不允许一个保险内所有物品使用同一搜索时间。
# 4. 尚未搜索到的每件物资占格必须被深灰遮罩完整覆盖。遮罩按该物品在3x3中的实际矩形 footprint 绘制，底色比主面板更深，叠加低透明
#    斜向条纹杂色，中间显示“?”。大紫/大红等3x2或2x3使用整块占格遮罩；紫2若实际旋转为2x1，则遮罩也跟随实际占格方向。
#    当前物品搜索完成后对应遮罩快速淡出，真实贴图才执行原品质闪光/回弹显现；其它未轮到物品的“?”遮罩必须继续保留。
# 5. 保险开启音效仍使用 res://audio/characters/三角洲/三角洲开保险.MP3，开启耗时继续严格读取 stream.get_length() 同步；
#    仅将 OpenAudio 的基础 volume_db 默认提高到 +7dB，解决保险声音明显偏小。AudioStreamPlayer2D 的2D位置和距离衰减继续保留。
# 6. V221 的保险指定掉落池、3x3真实占格、紫2必要时旋转、搜索框简化渐变风格、V219保险原位覆盖/缩小渐隐、V218概率/拾取吸附、
#    V217分品质音效以及所有既有物资价值均保持，除非与本V222明确覆盖内容冲突。
# 7. V222 修改：res://scripts/characters/三角洲/跑刀仔.gd、res://global/注释.gd；未新增图片、音频、Shader或同义目录。
# ============================================================

# ============================================================
# V223 —— 跑刀仔：保险问号/放大镜按真实占格居中 / 放大镜按短边占格等比缩放 / 交互范围收紧
# ============================================================
# 1. 用户要求保险搜索UI中的“?”和放大镜都必须以当前这件物品在3x3背包中的真实 footprint 几何中心为锚点，
#    禁止按整个面板中心、默认1格中心或贴图中心猜位置。V223 的 search_entries 显式携带 safe_grid_size_actual，中心仍由
#    safe_grid_pos + safe_grid_size_actual/2 计算；问号遮罩根节点和放大镜搜索基准点都直接使用这个 local_center。
# 2. 问号从“Label铺满整个长方形footprint”改成以 footprint 几何中心为原点的居中正方形Label，避免1x2、2x3、3x2等长方形中
#    字体基线/Control矩形造成视觉偏心。问号大小仍受该占格短边限制，不跨到相邻物品格。
# 3. 放大镜大小从V222固定尺寸改为按该物品占格的短边格数等比缩放：1x1和1x2短边都是1格，因此放大镜约为1格大小；
#    2x2、2x3、3x2短边都是2格，因此放大镜约为2格大小。比例统一缩放，不分别拉伸X/Y，禁止把1x2做成长条放大镜。
# 4. 放大镜仍保留V220以来的丝滑小幅摆动和角度变化，但摆动必须围绕真实footprint中心发生；摆动幅度也按短边物理尺寸缩放，
#    不允许大物品仍使用固定±3.8px导致看起来偏在一侧，也不允许摆动脱离当前物品占格区域。
# 5. 保险位于左右墙外时V218把safe_interact_radius提高到52px，用户反馈范围偏大。V223默认收紧到44px；保险生成位置、左右墙规则、
#    右墙flip_h、开启音效长度同步和开启搜索流程不变。该改动只影响“人物离保险多近才算正在交互”。
# 6. V222的逐件品质搜索、未搜索深灰条纹遮罩、V221的3x3真实占格/指定保险掉落池、V219原位覆盖和此前所有物资价值/音效规则保持。
# 7. V223修改：res://scripts/characters/三角洲/跑刀仔.gd、res://global/注释.gd；未新增图片、音频、Shader、场景或同义目录。
# ============================================================


# ========================================================
# V224 —— 工具栏关闭后仍可缩放 / 保险分离摆放 / 搜索图标真实居中与尺寸收紧
# ========================================================
# 1. 战场 Alt+滚轮缩放与顶部工具栏 visible 状态彻底解耦：工具栏打开/关闭都允许继续调整 toolbar_zoom_multiplier；
#    关闭工具栏只隐藏UI，不复位倍率，也不再禁止新的缩放输入。回放期间仍禁止手动缩放。
# 2. Game._input 与 World.toolbar_zoom_at_screen_position 两层旧的“工具栏必须打开”门槛同时删除；
#    不能只删其中一层，否则另一层仍会让关闭工具栏后的滚轮看起来失效。
# 3. 跑刀仔保险仍固定只生成在左右墙，但同一侧不再完全随机Y后互相叠放；按该侧保险数量分段取点，
#    保险视觉之间保留可见间隔并只加入很小随机偏移。
# 4. 未搜索物品问号不再使用Label字体排版。字体ascent/side-bearing会造成视觉偏心；V224改为围绕footprint原点绘制矢量“?”，
#    因此1x1、1x2、2x3、3x2等真实占格都以自己的几何中心为问号中心。
# 5. 搜索放大镜重新校准自身矢量包围盒并按占格短边等比缩放；1格目标可见跨度约0.76格，2格约1.52格，
#    给描边与摆动留出余量，禁止1x1放大镜视觉超过单格。摆动幅度同步缩小，并始终围绕真实footprint中心。
# ========================================================

# ========================================================
# V225 —— 跑刀仔：人物右侧实时钱数显示 / 纯数字金色微光
# ========================================================
# 1. 用户要求跑刀仔当前钱数直接显示在人物右侧。V225 在跑刀仔根节点下运行时创建 MoneyValue Label，
#    使用人物本地右侧约 x=34px、y=-8px 的固定偏移，因此数字会随人物移动和人物整体缩放一起变化，不额外创建屏幕HUD。
# 2. 显示内容严格只有数值本身：普通钱显示十进制数字；取得“无限钱”后沿用既有 get_money_text() 显示“∞”。
#    禁止添加“钱”、货币符号、图标、底板、边框或其它说明文字。
# 3. 主文字使用金色 Color(1.0,0.78,0.18)，仅使用0偏移、低透明金色 font_shadow + 2px shadow_outline 做轻微光晕，
#    再用1px深金轮廓保证复杂战场背景上的可读性；不能做强烈霓虹或大范围发光。
# 4. 钱数文本只在数值实际变化时重写；拾取普通物资、拾取无限钱都会立即刷新。跑刀仔第二命仍显示本局累计得到的钱。
# 5. V225 修改：res://scripts/characters/三角洲/跑刀仔.gd、res://global/注释.gd。V224及之前全部累计规则继续保留。
# ========================================================

# ========================================================
# V226 —— 跑刀仔：三首专属音乐 / 第一命与复活BGM切换 / 大红以上稀有物资音乐
# ========================================================
# 1. 用户提供三首音乐并指定用途，全部保留原文件名放入 res://audio/characters/三角洲/：
#    - 哈哈基米 P1 🎵曼波 𝑵𝒐 𝑴𝒐𝒓𝒆🎵不再曼波.mp3：跑刀仔第一命/常态背景音乐，附件实际约53.888秒；
#    - TAKEDISKRUSH! P1 TAKEDISKRUSH!.mp3：跑刀仔第一命死亡、购买装备进入第二命后的复活背景音乐，附件实际约162.168秒；
#    - 三角洲行动BGM P1 《得吃の小曲》《78の小曲》《舔包の小曲》《鼠鼠の小曲》.mp3：拾取或保险逐件搜到“大红及以上/无限钱”时的一次性稀有物资音乐，附件实际约117.214秒。
# 2. 第一命 No More 与第二命 TAKEDISKRUSH 都使用非定位 AudioStreamPlayer，并复制 imported MP3 resource 后将副本 loop=true；
#    禁止直接修改共享音频 Resource 的 loop，以免其它播放器引用同一资源时被连带改成循环。音乐走 GameplayRecord 总线（存在时），否则回退 Master。
# 3. 第一命 _ready() 后立即开始 No More。life_index 从1切到2的 _buy_equipment_and_revive() 同帧立即切到 TAKEDISKRUSH；
#    第二命最终死亡/人物被手动删除/_exit_tree 时必须停止全部跑刀仔音乐，禁止留下无主人BGM。
# 4. “大红及以上”严格解释为：品质=红且 size=大/大大（大红、大红2、大红3、大大红）以及 runner_infinite_money=true 的无限钱。
#    小红/中红不触发稀有物资音乐。地面物资在真正吸附到人物并结算拾取的瞬间触发；保险物资在逐件搜索揭开真实贴图的瞬间触发。
# 5. 保险揭示时已经触发过稀有曲的物品写 runner_rare_music_triggered=true；随后自动飞到人物结算时禁止再次重播。
#    同一保险若连续揭示多个大红/无限钱，而稀有曲仍在播放，不得每件都从头重启；继续当前这一首即可。
# 6. 稀有物资音乐属于一次性事件音乐，不循环。播放时暂停当前第一命/第二命BGM，完整自然播放结束后恢复被暂停的当前阶段BGM；
#    但“死亡进入第二命”的 TAKEDISKRUSH 优先级高于稀有物资音乐：若复活发生时稀有曲仍在播，立即停止稀有曲并切到复活BGM。
# 7. 三份源音频平均电平差异很大，本版用独立默认 volume_db 做听感补偿：No More=-8dB、TAKEDISKRUSH=-14.5dB、稀有曲=-0.5dB；
#    三者仍作为 export 暴露，后续若实机需要可直接在 Inspector 微调，不修改原音频文件本身。
# 8. V226 修改/新增：res://scripts/characters/三角洲/跑刀仔.gd、res://global/注释.gd，以及上述3个原名MP3。
#    V225及之前物资、保险、音效、3x3搜索、钱数显示、工具栏缩放等累计规则继续保留，除非与本V226明确覆盖内容冲突。
# ========================================================

# ========================================================
# V227 —— 跑刀仔：重置释放实例修复 / 三首音乐全局互斥 / 保险品质渐变背景
# ========================================================
# 1. 用户在训练场点击“重置”时出现 `Trying to assign invalid previously freed instance`，截图停在旧版
#    `_cleanup_runner_loot()` 的 `for n:Node2D in _supplies.duplicate()`。根因是物资/保险节点挂在 current_scene，
#    World reset 可能先释放其中部分节点；Object 引用被 free 后不会自动变 null，而旧清场代码会先把失效引用赋给
#    Node2D 强类型循环变量，尚未进入 is_instance_valid() 就触发运行时错误。
# 2. V227 将 _supplies / _safes / _safe_search_displays 与 _opening_safe 的外部节点引用改为 Variant/非强类型容器；
#    清场、拾取扫描、保险扫描都必须先 is_instance_valid(raw_ref)，确认有效后才 `as Node2D/Node` 并访问或 queue_free。
#    _safe_audio_player/_start_safe_open_audio/_stop_safe_open_audio/_safe_open_duration 同样先接收 Variant 再检查。
#    因此 reset、手动删除、死亡、第一命转第二命、_exit_tree 可以重复清场，不得再因为旧失效实例报错。
# 3. V226 的“两播放器：阶段BGM + 稀有曲播放器，阶段BGM用 stream_paused 暂停”从 V227 废止。
#    每个跑刀仔只创建一个 AudioStreamPlayer，max_polyphony=1；No More、TAKEDISKRUSH、稀有物资曲全部通过同一个
#    player 执行 stop -> 换 stream -> play，节点层面不允许同一跑刀仔同时播放两首。
# 4. 为避免战场上存在多个跑刀仔时各自再叠一首，所有跑刀仔专属音乐播放器加入 RunnerExclusiveMusic 组；
#    任意一首开始或恢复前先停止组内其它播放器。故这三首专属音乐在整个战场任意时刻最多只允许一条播放链。
# 5. 稀有物资曲开始前记录当前第一命/第二命BGM的 playback position，然后用同一播放器切到一次性稀有曲；
#    稀有曲自然 finished 后恢复当前阶段BGM并从记录位置继续。第一命转第二命仍具有更高优先级，直接 stop 稀有曲并切 TAKEDISKRUSH。
# 6. 保险已搜索物资从 V227 起按品质给“真实占据 footprint”增加背景颜色，同时保留渐变：紫/金/红/无限分别使用
#    对应品质色与原深灰面板色混合，上部略亮、下部更深，不做纯色平涂。未搜索阶段仍由 V222 的深灰条纹问号遮罩完整覆盖，
#    因此在真正搜出之前不能通过背景颜色提前看出品质；揭示时品质渐变背景与物资一起出现。
# 7. V227 修改：res://scripts/characters/三角洲/跑刀仔.gd、res://global/注释.gd。V226 的三份音乐源文件、
#    V225 钱数显示、V224 工具栏缩放、V223/V222/V221 保险搜索与3x3占格等累计规则继续保留，除非被本版明确覆盖。
# ========================================================

# ========================================================
# V228 —— 跑刀仔：保险逐件揭示补齐物资搜索音效
# ========================================================
# 1. V217 已规定物资“刷新/搜出”的搜索音效分档：白/蓝/紫使用 `搜索紫以下.MP3`，金/红/无限使用 `搜索金以上.MP3`；
#    但 V222 起保险改为逐件搜索后，逐件揭示路径只播放出生动画/稀有音乐，遗漏了 `_play_loot_sfx(..., true, ...)`，因此保险搜出东西时没有搜索音效。
# 2. V228 在保险 `_run_safe_search_animation()` 每件物资真正揭示（item_root.visible=true + 出生动画）同一时刻，
#    直接复用地面刷新物资使用的 `_play_loot_sfx(quality, true, item_root.global_position)`。禁止复制一套新的品质判断。
# 3. 所以保险每揭示一件：紫及以下播放 `搜索紫以下.MP3`；金/红/无限播放 `搜索金以上.MP3`；
#    之后该物资自动吸附到跑刀仔并真正结算拾取时，仍继续播放原有“紫以下拾取/金以上拾取”音效，两者职责不混用。
# 4. V226/V227 的大红以上稀有物资音乐仍在“揭示”瞬间触发；搜索音效属于2D位置SFX，不改变三首跑刀仔专属音乐全局互斥规则。
# 5. V228 修改：res://scripts/characters/三角洲/跑刀仔.gd、res://global/注释.gd；未新增、移动、重命名任何项目源文件。
# ========================================================


# === V229 三角洲角色正式图片接入（2026-08-31） ===
# 1. 跑刀仔第一命不再使用灰色 Polygon2D 占位图，固定使用：
#    res://Images/characters/三角洲/跑刀仔/跑刀鼠.png
# 2. 跑刀仔第一命死亡并完成第二命复活时，角色主体 Sprite2D 立即切换为：
#    res://Images/characters/三角洲/跑刀仔/吴彦祖.png
#    仅改变角色视觉，不改变两条命、钱、物资、保险、BGM、第二命购买成长等既有机制。
# 3. 三角洲“盾狗”角色不再使用蓝色 Polygon2D + 盾牌占位图，固定使用：
#    res://Images/characters/三角洲/盾狗/深蓝.png
# 4. 三张角色图片均直接写入现有 Graphics/Image Sprite2D.texture，并按贴图最长边等比缩放；
#    禁止拉伸变形。跑刀仔最长边目标约58px，盾狗约62px。
# 5. 本轮新增图片路径只使用现有 Images/（大写 I）和 characters/三角洲 分类；
#    不创建 images/、Audio/ 等同义目录，不改任何原角色/脚本/场景名称。


# === V230 跑刀仔第一命死亡 -> 直升机绳降复活（2026-08-31） ===
# 1. 第一命 health<=0 时不再立刻原地切第二命。死亡当帧直接隐藏跑刀仔视觉，
#    清零 velocity/direction/Repel，并临时关闭 CharacterBody2D、本体 hitbox/hurtbox 的碰撞/检测；
#    整个空降过程 is_combat_targetable() 返回 false。
# 2. TAKEDISKRUSH 从第一命死亡开始播放；第二命购买成长可以提前计算 Max 属性，
#    但 life_index=2、health=Max_health、Can_Attack=true、Has_Collision_Damage=true
#    必须等绳降人物真正落地后才恢复。
# 3. 新增 res://Images/characters/三角洲/跑刀仔/直升机.png。
#    直升机从当前 Camera/Viewport 可视世界矩形的左或右屏幕外飞入，在第一命死亡位置上方悬停；
#    原图机头向左，从左侧飞入时自动 flip_h，使机头始终朝飞行方向。
# 4. 悬停后用 Line2D 从机腹向落点放下深色绳子；临时“吴彦祖.png”Sprite2D 从绳顶
#    沿绳平滑下降。落地瞬间隐藏临时 Sprite，真实跑刀仔在同一位置显示第二命图片并恢复实体。
# 5. 人物落地后绳子收回，直升机沿原飞行方向飞出另一侧屏幕并删除。
#    若第一命死在屏幕最上缘，会把落点向地图内轻微下移，保证至少约68px可见绳长。
# 6. 复活过场根节点挂在 current_scene，因此 reset/换场景/手动删除跑刀仔时，
#    _exit_tree() 必须调用 _cleanup_revive_cinematic()，禁止残留无主直升机/绳子。
# 7. 本轮只改变第一命->第二命的复活表现与复活时机；钱、保险、物资、购买成长公式、
#    No More/TAKEDISKRUSH/稀有物资音乐互斥规则以及第二命战斗数值不改。


# === V231 三角洲角色尺寸 / 局内预览 / 钱数字修正（2026-08-31） ===
# 1. 修正 V229 的尺寸单位错误：ball 根节点自身 scale=0.2，V229 用 58/62 作为 Graphics/Image
#    本地最长边会导致实际世界画面只有约11~12px。V231 改为与 CharacterAutoFit 同一量级：
#    跑刀仔第一命本地最长边约235、第二命吴彦祖约270、盾狗约240。
# 2. V230 直升机过场中的临时吴彦祖 Sprite 挂在 top_level 世界节点，不吃 ball 的0.2缩放；
#    因此另设约64世界像素的绳降视觉尺寸，禁止因为人物本体放大而把空降人物放大4~5倍。
# 3. 跑刀仔.gd / 盾狗.gd 新增 get_preview_texture()。World.create_ghost_ball() 的局内 Ghost
#    不会执行角色 _ready()，会优先读取该接口；因此局内放置预览现在直接使用跑刀鼠/深蓝正式贴图，
#    不再复制 ball.tscn 默认图片。
# 4. res://scenes/characters/三角洲/跑刀仔.tscn 与 盾狗.tscn 同步把 Graphics/Image.texture
#    保存为正式 PNG，并设置 CharacterAutoFit.visual_size_multiplier，使编辑器场景预览也不再显示默认ball图。
# 5. 跑刀仔金色钱数字此前 font_size=11 也会随 ball 根0.2缩小；V231 改为本地 font_size=48，
#    位置同步移到放大后人物右侧，仍然只显示数字/∞、金色、轻微发光，无背景框和货币图标。


# === V232 盾狗冲撞纯图片蓄力/前冲反馈（2026-08-31） ===
# 1. 三角洲盾狗每次进入真实 _ram(target,cost) 冲撞结算时，新增 Graphics/Image 专属 Tween。
#    该 Tween 只修改 Sprite2D.position / scale；严禁修改盾狗 CharacterBody2D.global_position、
#    velocity、direction、碰撞形状、ram_range、伤害、击退、眩晕或体力结算。
# 2. 图片动画固定顺序：先沿面朝方向反向小退约15本地像素，同时横向压扁到约82%、
#    纵向轻微撑到约108%；随后沿面朝方向快速前窜约30本地像素并恢复正常比例；
#    最后使用 BACK/SPRING 缓动回到原图片位置和原始比例。
# 3. 动画总时长默认约0.29秒（0.075后退蓄力 + 0.085前冲 + 0.13回弹）。
#    连续触发时必须 kill 上一次 Tween，并先恢复保存的 base_position/base_scale 再重播，
#    禁止累积偏移、累积缩放或图片永久变形。
# 4. _apply_shield_dog_texture() 完成正式深蓝.png 等比尺寸适配后保存图片基准位置/缩放；
#    V231 的局内预览、盾狗正式图片尺寸和其他盾狗机制全部保持。


# === V233 盾狗走路 / 刺网 / 冲撞 / 概率语音音效接入（2026-08-31） ===
# 1. 用户本轮提供9条MP3，全部保持原文件名并放入：
#    res://audio/characters/三角洲/盾狗/
#    撞击语音1.MP3、撞击语音2.MP3、撞击语音4.MP3、
#    走路循环(1).MP3、刺网1(1).MP3、刺网2(1).MP3、刺网3.MP3、撞击1.MP3、撞击2.MP3。
# 2. 实测素材长度：走路循环约5.02s；撞击实体音效约0.68~0.76s；
#    撞击语音约0.76~0.79s；刺网动作音效约0.91~1.23s。
# 3. 盾狗新增3个 AudioStreamPlayer2D：
#    WalkLoop 独立循环走路声；ActionSFX 播放刺网/冲撞实体音效；VoiceSFX 独立播放冲撞语音。
#    三者分开，保证走路不会被动作音效切断，撞击实体声与概率语音也能同时存在。
# 4. 走路循环只在 health>0 且 State.Move 时播放，离开 Move 或死亡立即停止。
#    MP3 运行时 duplicate 后设置 loop=true，不修改共享导入资源。
# 5. Skill() 放置铁丝网时每次从刺网1/2/3随机播放一条对应动作音效。
# 6. 每次真实 _ram() 冲撞时必从撞击1/2随机播放一条实体撞击声；
#    同时以默认42%概率从撞击语音1/2/4随机触发一条语音。
#    VoiceSFX 正在播放时禁止重启/抢断，避免短时间多次冲撞造成语音碎裂。
# 7. 本轮只接入音频反馈；V232 的纯图片后退/压扁/前冲动画以及盾狗全部战斗数值不改。


# === V234 盾狗刀片陷阱投掷 + 正面120°钩爪（2026-08-31） ===
# 1. 新增4条用户音效，保持原文件名并放入 res://audio/characters/三角洲/盾狗/：
#    扔刀片.MP3、刀片落地.MP3、钩爪.MP3、钩爪收回.MP3。
#    实测时长约0.627s / 0.914s / 0.627s / 1.149s。
# 2. 原陷阱 Skill 改为投掷刀片：施法瞬间播放“扔刀片”，小型金属刀片视觉在约0.24s
#    飞到前方约58px；落地瞬间播放“刀片落地”，随后才创建三角洲铁丝网。
# 3. 新增钩爪自动副技能：默认有效距离72~220px、冷却5.2s；只锁盾狗正面120°扇区
#    （面朝中轴左右各60°）内敌人；PhysicsRayQueryParameters2D 使用 collision_mask=3，
#    墙体或其他角色挡住时不可穿透钩人。
# 4. 钩爪伸出播放“钩爪.MP3”；约0.13s后到达目标，再次检查120°、距离和直线无遮挡。
#    真正钩中固定造成5点伤害，真实扣血后播放与冲撞共用的撞击受伤音效。
# 5. 钩中后播放“钩爪收回.MP3”，并用项目统一 target.apply_knockback() 将目标朝
#    盾狗正前方约42px位置拉回，默认拉速520；不直接写目标global_position，保留墙体安全。
# 6. 三角洲铁丝网 enter/move damage 每次真实扣血后也调用盾狗
#    play_wire_damage_impact_audio() 播放同一套撞击受伤音效；同目标持续伤害音效默认0.34s节流。
# 7. V233 走路循环、冲撞实体声、概率撞击语音继续保留；陷阱的旧刺网随机声不再作为
#    “扔/落地”主反馈，新两条刀片音效承担施法时序反馈。


# === V235 盾狗刺网 / 刺网子弹正式图片接入（2026-08-31） ===
# 1. 用户本轮提供两张透明PNG并保持原文件名：
#    res://Images/characters/三角洲/盾狗/刺网.png
#    res://Images/characters/三角洲/盾狗/刺网子弹.png
# 2. V234 刀片陷阱的飞行阶段废止临时 Polygon2D 菱形占位，
#    改为 Sprite2D.texture=刺网子弹.png；默认视觉宽约38世界像素，
#    按 facing_sign 水平翻转并只做约34°小幅翻滚。扔出/落地时序和两条音效不改。
# 3. res://scripts/effects/三角洲_铁丝网.gd 的手绘横纵 Line2D 网格视觉废止，
#    _build_visual() 改为直接显示刺网.png。默认视觉宽约134世界像素；
#    真实 radius=58、durability、enter/move damage、slow_ratio、弹丸耐久消耗均不改。
# 4. 刺网图片只替换视觉；V234 的刺网真实命中受伤音效、钩爪、120°限制、
#    5点钩爪伤害和拉到盾狗正前方机制全部保留。
# 5. 本轮额外输出 V233→V235 增量覆盖包：它包含 V234 + V235 的全部最终变化，
#    用户从 V233 可以直接一次覆盖到 V235，不需要先安装 V234。


# === V236 盾狗 _rng 未声明 Parse Error 修复（2026-09-01） ===
# 1. 修复 res://scripts/characters/三角洲/盾狗.gd 的解析错误：
#    V233 音效随机选择新增了 _rng.randi_range() / _rng.randf()，
#    但盾狗脚本及 ball 基类都没有声明名为 _rng 的成员，因此 Godot 报：
#    Identifier "_rng" not declared in the current scope。
# 2. 本轮把盾狗脚本内全部3处 _rng 调用改为 Godot @GlobalScope 原生随机函数：
#    randi_range(from,to) 与 randf()。这些函数不需要 RandomNumberGenerator 实例，
#    因而不会再产生未声明成员错误。
# 3. 三处分别覆盖：
#    - _play_random_shield_audio() 的随机音效数组索引；
#    - _try_play_ram_voice() 的概率语音判定；
#    - play_wire_damage_impact_audio() 的随机撞击受伤音效索引。
# 4. V235 刺网/刺网子弹正式图片、V234 钩爪、刀片陷阱、V233 全部盾狗音效与战斗参数均不改。


# === V237 盾狗音频缺文件自包含修复（2026-09-01） ===
# 1. 用户实测 V236 后出现 Resource file not found：
#    res://audio/characters/三角洲/盾狗/走路循环(1).MP3、撞击1.MP3 等。
#    根因不是 Godot 不支持 MP3，也不是代码路径拼写错误；V236完整累计包实际包含这些文件，
#    但此前 V233→V236 哈希增量包默认“V233的9条盾狗音频已经在用户项目里”，因此只带V234新增4条。
#    当前用户项目没有那9条旧音频，造成盾狗 _ready()/动作播放时缺资源。
# 2. V237 的“本次最小修复包”改成自包含盾狗当前全部13条音频；
#    即使之前缺失V233音频，直接覆盖V237最小包也会补齐，不依赖历史包。
# 3. V233→V237 增量包同样改为“自包含依赖”模式：除V234~V237真正差异外，
#    强制额外携带V233的9条盾狗音频。
# 4. 盾狗.gd 新增 _load_shield_audio(path)：先 ResourceLoader.exists(path)，
#    再 ResourceLoader.load(path)。未来某条音频若被误删，只给明确warning，不让裸load()
#    在每次走路/冲撞/刺网/钩爪时反复刷 Resource file not found 红错。
# 5. 本轮不改V233~V236盾狗玩法与数值。


# === V238 盾狗刺网子弹抛物线旋转 + 冲撞正面限定（2026-09-01） ===
# 1. 刺网子弹不再直线Tween。使用 tween_method() 提供0~1 progress：
#    linear_pos = start_pos.lerp(land_pos,t)
#    arc_y = -4 * wire_throw_arc_height * t * (1-t)
#    因此起点/落点回到基准高度，中点达到最高点；默认弧高42世界像素、飞行0.34s。
# 2. 同一progress同步更新rotation，默认完整抛射旋转约1.35圈，方向随facing_sign。
#    刺网子弹.png、扔刀片/刀片落地音效和落地后生成刺网的时机均保留。
# 3. 盾狗冲撞从“只判断目标X在面朝一侧”改为点积正面锥形判定：
#    默认 ram_front_angle_degrees=120，即面朝中轴左右各60°。
#    目标在侧面/背后时不允许攻击。
# 4. 接近式冲撞在小幅接近之后会二次检查正面锥形；_ram()本身也再做同样硬门槛，
#    防止未来其他调用路径绕过正面限制。
# 5. 钩爪原本已经正面120°，继续保持；已落地刺网是独立陷阱，不受当前朝向限制。
# 6. V237自包含13条音频与安全加载、V235正式刺网图片、V232图片冲撞反馈均保留。


# === V239 盾狗正面/图片朝向统一为移动方向（2026-09-01） ===
# 1. 根因：公共 ball 默认 `dir_left=true`，含义是“角色原始素材默认朝左”。
#    盾狗旧 Polygon2D 占位图的盾牌凸出在右侧，原机制一直把 facing_sign=+1 当作右侧正面；
#    V229 换成 Graphics/Image 正式图片后没有覆盖 dir_left，公共 ball.move() 因而会把图片左右镜像反掉。
# 2. V239 在 res://scenes/characters/三角洲/盾狗.tscn 保存 `dir_left=false`，
#    并在盾狗 `_ready()` 的 super._ready() 之前再次设置 dir_left=false：
#    正式深蓝.png 统一解释为“默认朝右”；向右移动不翻图，向左移动才水平翻转。
# 3. 新增 `_sync_facing_from_movement()`：
#    - AI：正面读取当前 direction.x；
#    - 直接控制：正面读取公共 ball.move() 真正使用的 player_control_direction.x；
#    - 没有输入时才允许用上一帧真实 velocity.x 兜底。
#    facing_sign 不再代表任何反向/图片朝向约定，只代表“当前真实移动正面”的X符号。
# 4. 新增 `_sync_shield_dog_image_facing()`，通过公共 set_character_visual_flip_h()
#    同步图片，不直接依赖 Sprite2D.flip_h；这样兼容项目 Shader 的 sprite_flip_h。
#    规则固定为：facing_sign>0 右移 -> 不翻；facing_sign<0 左移 -> 翻。
# 5. 冲撞正面120°、钩爪正面120°、正面减伤、刀片投掷方向、钩爪拉回位置、
#    V232冲撞图片后退/前冲方向都继续使用同一个 facing_sign，因此“移动方向就是正面”。
# 6. 本轮不改V238抛物线刀片、V237音频、V235刺网图、V234钩爪数值。


# === V240 盾狗铁丝网真实踩中伤害/减速 + 普通冲撞缩距（2026-09-01） ===
# 1. 修复“敌人已经踩在刺网图片上但不掉血/不减速”的两个根因：
#    - V239及之前用 global_position.distance_to(ball.global_position)<=radius，
#      只比较两个中心点，不是真实身体重叠；大角色身体/图片已经接触网边时中心仍可能在58px外。
#    - 旧减速只做 b.velocity*=slow_ratio，但公共 ball.move() 每帧会重新用 direction*Speed 计算velocity，
#      所以下一帧立即覆盖，看起来完全没有减速。
# 2. res://scripts/effects/三角洲_铁丝网.gd 新增真实 DamageArea：
#    Area2D(collision_mask=Layer2角色) + CircleShape2D(radius=58)，
#    每物理帧使用 get_overlapping_bodies() 读取真正与刺网物理区域重叠的 CharacterBody2D。
#    因此判定会考虑角色自己的碰撞形状，不再要求角色中心点走进刺网中心。
# 3. 减速改为项目原生 Speed Buff：
#    Buff.Buff_types.Speed + Algorithms.mul，默认倍率0.52、刷新持续0.16s，来源为当前刺网实例；
#    只要身体仍在DamageArea里就持续cover刷新，离开/刺网删除时立即delete本来源Buff。
#    当帧仍额外压一次velocity，保证刚踩入时立刻有反馈。
# 4. 伤害改为稳定脉冲：
#    - 初次真实进入：固定 enter_damage=7；
#    - 在网里移动累计约3px，且间隔>=0.34s：固定 move_damage=5；
#    不再使用 move_damage*delta*2 的极小分数伤害，避免整数/取整生命体系长期看起来不掉血。
#    wire_ignore_block 默认true，使脚下刀片伤害直接形成生命损失；命中音效仍只在真实伤害成功时触发。
# 5. 盾狗普通冲撞攻击范围缩小：
#    ram_range 从58降到40；删除旧 ram_range*1.75（约101.5px）的远距离接近后同帧直接_ram结算。
#    现在只有目标中心距离已经<=40px且仍在移动正面120°时才允许普通冲撞伤害。
#    approach_ram_stamina_cost 字段为旧版本兼容保留，但V240普通冲撞不再使用远距离立即命中分支。
# 6. 钩爪是独立技能，V240不改其72~220px射程；V239移动方向=正面、V238抛物线刀片、
#    V237全部13条音频、V235刺网图片与V234钩爪5伤害/拉人机制全部保留。


# === V241 盾狗钩爪实用化 + 刺网距离伤害/流血稳定修复（2026-09-01） ===
# 1. 修复“完全不使用钩爪”：
#    - 钩爪最小距离 72 -> 48，超过普通冲撞40px后很快进入钩爪可用区；
#    - 钩爪从“仅State.Move尝试”改为 Stand/Move 均可尝试；
#    - 仍禁止 Attack/Skill 中途抢动作；
#    - 钩爪直线遮挡 collision_mask 从3改为1，只检查地图墙体。
#      旧mask=3会让Layer2任何角色都挡住钩爪，拥挤战场很容易导致永远没有可用目标。
#    - 正面120°和220px最大距离保持。
# 2. 刺网判定不再只依赖 Area2D.get_overlapping_bodies()：
#    第一层仍使用真实Area2D物理重叠；第二层扫描Ball组并结合
#    target.get_crowd_separation_radius_world() 估算角色真实身体半径。
#    角色身体边缘只要进入 radius=58 的危险圆就算“进入范围”，避免碰撞层动态优化/物理迭代更新时机导致漏判。
# 3. 进入危险范围的第一帧固定造成 enter_damage=7；这次进入不需要角色移动。
# 4. 在刺网里面改成“纯距离伤害”：
#    每累计移动10世界像素就固定造成 move_damage=5，不再额外要求0.34秒冷却；
#    一帧极端位移最多结算3次，避免瞬移类机制一次爆死。
# 5. 每次“移动满10px”的真实伤害成功后叠1层流血，最多3层，默认持续5秒。
#    流血直接复用原项目 res://scripts/status/剑客_流血.gd：
#    每层行动触发伤害1、移动tick约0.60s伤害1，并保留原脚本红色染色/内部伤害语义。
#    本轮把该脚本作为更新包自包含依赖一并带上，避免项目分支缺文件。
# 6. 刺网减速继续使用Speed Buff 0.52倍，离开范围立即删除本刺网来源减速。
# 7. V240普通冲撞40px、V239移动方向=正面、V238抛物线刀片、V237音效、V235正式图片均保留。


# === V242 盾狗钩爪/刺网空Team误判根因修复（2026-09-01） ===
# 1. 用户连续实测“钩爪完全不用、刺网完全没伤害/减速”后，确认共同根因不是Area2D、
#    距离、流血或钩爪冷却，而是 V234~V241 新代码自己写错了 Team 判定。
# 2. 项目公共 World._refresh_one_nearest_enemy() 的真实阵营规则是：
#    只有 `b.Team != "" && b2.Team != "" && b2.Team == b.Team` 才算同队并跳过。
#    因此训练场常见的 Team="" 对 Team="" 仍然会互相视为敌人。
# 3. 旧钩爪 `_find_hook_target()` 错误写成 `if candidate.Team == Team: continue`。
#    当盾狗 Team="" 且敌人 Team="" 时，全场候选都会被误判为队友，结果永远 target=null，
#    所以用户看到“完全不使用钩爪”。
# 4. 旧刺网 `_valid_wire_target()` 同样错误写成 `if target.Team == Team: return false`。
#    因此训练场 Team="" 的敌人即使真实踩进刺网，也会在伤害/减速前直接被过滤掉，
#    后面的 Area2D、进入伤害、移动距离伤害、流血和Speed Buff全部没有机会执行。
# 5. V242 两处都改成公共规则：
#    `not Team.is_empty() && not target.Team.is_empty() && target.Team == Team`
#    时才认为同队。任何一方Team为空时不按同队过滤。
# 6. V241 的进入7伤、每移动10px造成5伤并叠流血、0.52倍减速、钩爪48~220px、
#    正面120°、只被墙阻挡等机制全部保留，本轮只修真正阻断这些机制的阵营过滤。


# === V243 盾狗刺网碰撞伤害音效 + 钩爪真实延伸命中即拉回（2026-08-31） ===
# 1. 修复盾狗刺网伤害音效错误：
#    V234~V242 的三角洲_铁丝网.gd 在真实扣血后调用盾狗 play_wire_damage_impact_audio()，
#    但该函数错误随机播放 SHIELD_DOG_RAM_SFX_PATHS（撞击1.MP3 / 撞击2.MP3），
#    这两条是盾狗自身冲撞动作音，不是项目公共“碰撞伤害命中”音。
# 2. V243 改为复用 ball.gd 的标准 Hit_Audio 链：
#    默认 Hit_Audio=balls_hit1，对应 Audios/Sfx/balls_hit1 -> res://audio/sfx/physics/balls_hit1.sfxr。
#    如果角色以后配置 Unique_Hit_Audio，也会优先沿用独特命中音。
#    刺网进入伤害/移动伤害仍只在真实造成伤害后播音，原0.28s同目标限频保持。
# 3. 钩爪不再把 Line2D 直接Tween到“施放瞬间记录的目标位置”，再等整段延伸动画结束才判定。
#    现在钩尖在盾狗 tick_physics 的真实物理帧中从手前向瞄准方向逐段延伸，默认总延伸时长仍使用hook_extend_time。
# 4. 每一小段延伸都会检查：
#    - Layer1地图墙体；
#    - 钩尖线段与当前有效敌人的真实身体中心/估算碰撞半径。
#    先碰到墙则在墙面停止并收回；先碰到有效敌人则该物理帧立即停止继续延伸。
# 5. 命中敌人的同一阶段立即结算原有5点hook_damage，并立刻调用项目统一apply_knockback()
#    把目标拉到盾狗正前方hook_pull_front_offset位置；不再存在“已经勾到了还继续往前延伸”的视觉/逻辑延迟。
# 6. 拉回期间钩绳两端实时跟随“盾狗手前锚点 -> 被钩目标当前位置”，目标越靠近绳子越短；
#    未命中时的收回动画也修正为始终从盾狗手前锚点向钩尖收短，不再出现旧逻辑从目标点反向长回来的视觉。
# 7. V242空Team规则、V241刺网进入7伤/移动10px伤5+流血/0.52减速、V240冲撞40px、
#    V239移动方向=正面以及V237自包含音频规则全部保持，本轮不改这些数值。



# === V244 盾狗刺网禁止自伤 + 下方黄色体力条 + 正面子弹格挡（2026-08-31） ===
# 1. 修复铁丝网会伤到盾狗自己：
#    res://scripts/effects/三角洲_铁丝网.gd 的 _valid_wire_target() 现在第一时间读取 owner_ref，
#    无条件排除真实投掷者实例。不能只依赖 Team，因为训练场常见 Team=""，V242 的空Team规则会把
#    空Team owner 与空Team敌人都视为可互相攻击单位；陷阱自己的 owner 必须单独排除。
# 2. 盾狗新增专属体力显示，不改公共 health_bar.tscn：
#    运行时在角色根节点下创建一条细黄条，默认局部宽260、高12、Y=150；考虑 ball 根节点0.2缩放后，
#    实际约52px宽、2.4px高，位于人物图片下方。黄色部分按 stamina/stamina_max 从左到右缩短/恢复，
#    冲撞扣体力同帧刷新，平时每物理帧随 stamina_regen 刷新；角色死亡时隐藏。
# 3. 正面枪械子弹改为真正格挡，不再只是85%正面减伤：
#    - 普通 ball 型子弹通过 can_receive_hit_from() 在 hitbox 结算前拒绝；
#    - 军火商普通子弹、猎人霰弹这类逐帧射线 Area2D 会直接调用 receive_positional_damage()，
#      因此盾狗同时覆写 receive_positional_damage()/receive_spatial_damage()，避免只修一种弹道后另一种仍穿盾。
# 4. “正面”继续与 V239 的 facing_sign（真实移动方向）统一：命中/子弹来源位于面朝的水平半平面时格挡；
#    背后子弹仍正常受伤。raw_health 特殊伤害入口保持公共语义，不被盾牌截断。
# 5. 格挡成功播放公共 Block_Audio（盾狗未配置独特音时默认 BlockAtk1，
#    对应 res://audio/sfx/防御/BlockAtt.ogg），并使用项目公共 notify_block_burst_feedback() 白色格挡火花。
#    同时保留0.08秒音效限频，避免霰弹/同帧多颗子弹把格挡声叠爆。
# 6. 军火商脚本同时承载普通子弹和火箭，因此只格挡 projectile_kind=0；
#    小丑综合投射物只格挡 ProjectileMode.SNIPER，锤子/火箭/回旋镖不按“子弹”处理。
# 7. V243刺网碰撞伤害音效与钩爪命中立即拉回、V242空Team规则、V241刺网流血/减速等全部保留。


# === V245 盾狗二维移动/全投射物格挡 + 盾击刺网导向 + 铁丝网耐久完整化（2026-08-31） ===
# 1. 修复盾狗“只能横向移动”的直接根因：
#    V244 盾狗 `_sync_facing_from_movement()` 会在 AI 情况下每帧强制 `direction=Vector2(facing_sign,0)`，
#    把公共 ball.gd 原本支持的二维 direction 直接压成水平轴。V245 删除这段改写；移动继续完全走
#    公共 `ball.move()` -> `CharacterBody2D.move_and_slide()`，盾狗可以正常向任意二维方向移动。
#    图片仍只按 X 分量做左右翻转，不用图片翻转反向污染真实移动方向。
# 2. `_movement_forward_vector()` 同步升级为真实二维前向：AI 使用 direction，直接控制优先使用真实移动输入，
#    没有有效方向时才退回 facing_sign 水平向量。钩爪正面扇区、盾击正面扇区、正面防御都因此支持上下/斜向。
# 3. V244“子弹格挡”按用户澄清改为“所有投射物格挡”：
#    - ball 型 Shooter / Shooter_with_Health 全部属于可格挡投射物；
#    - `res://scripts/shooter/` 下的非 ball 投射物也统一识别；
#    - 火箭、砖块、石头、飞刀、酒瓶、电球、剑气、时钟、彩带、收债人钱等不再被排除；
#    - 正面命中完全拒绝伤害/附带击退/状态，并继续播放公共 Block_Audio + 白色格挡火花；背面仍正常命中。
# 4. 为 source 不是弹体本身、或自己做射线/扫掠命中的特殊投射物新增盾狗 `try_block_projectile_hit()` 入口，
#    并在军火商子弹/火箭、猎人霰弹、伪军子弹、建筑工人砖块、战争女神火焰剑气、凑企鹅石头、
#    炸弹客炸弹、时光客时钟、收债人钱、小丑彩带等命中入口主动调用；因此不会再出现“伤害被拒绝但击退/状态仍生效”。
# 5. 盾击击退方向重做：基础方向始终是当前真实攻击/移动前向，不再固定 Vector2(facing_sign,0)。
#    新增 `ram_wire_redirect_range=150` 与 `ram_wire_redirect_angle_degrees=120`：只有目标前方扇区、限定距离内的刺网
#    才允许把击退方向改成“朝该刺网”。例如基础向右、右上有网时可以右上击退；侧后方/身后的网完全忽略。
# 6. 任何刺网只要已经包含被盾击目标，就完全禁用“朝刺网导向”，保持基础击退方向；
#    这避免目标已经在网里时为了找网把敌人反向拉出刺网，或因最近网在身后产生倒吸效果。
# 7. 铁丝网耐久系统完整化：默认 durability=12，继续每 passive_decay_interval=2.2 秒自然损失 passive_decay=1；
#    每次自然损耗都会让刺网图片做短促左右颤抖，耐久 <=0 后 queue_free()，因此会稳定随时间消失。
# 8. 铁丝网新增运行时“耐久受击区”：它使用 hurtbox 类型和角色受击层2，只负责被攻击 Hitbox 检测；
#    classes/hitbox.gd 识别 DeltaBarbedWire 后只调用 `receive_attack_hitbox()`，随后返回 false，不发角色 hurt 信号，
#    所以刺网绝不会挡住/吃掉原攻击，近战和投射物都继续自己的原轨迹。
# 9. 直接身体碰撞伤害明确不伤刺网：Has_Collision_Damage 角色的本体 self_hitbox 被耐久受击区识别后直接忽略。
#    普通攻击 Hitbox 命中刺网默认损失1耐久；所有投射物形式统一乘 `projectile_durability_multiplier=0.5`，即默认只损失0.5耐久。
# 10. 非 ball 投射物不再依赖旧的 `Shooter` 组：刺网会按 Ball_Type、`res://scripts/shooter/` 脚本路径和现有
#     BattleTransient/专用投射物组统一收集；建筑工人砖块、收债人钱、小丑彩带补入 BattleTransient，确保穿过刺网也会扣0.5耐久。
# 11. 同一投射物只会让同一张刺网损失一次耐久；Hitbox命中与物理帧投射物扫掠共用 `_projectile_seen` 防重复，
#     避免一颗弹同时触发两条检测链导致耐久被重复扣两次。
# 12. V244铁丝网owner自伤过滤/黄色体力条、V243刺网碰撞伤害音效/钩爪碰到立即拉回、V242空Team规则等全部保留。

# === V246 盾狗刀片刺网耐久破坏音效（2026-08-31） ===
# 1. 用户提供5条刀片刺网破坏音效，保持原文件名并放入：
#    res://audio/characters/三角洲/盾狗/
#    刀片破坏1.MP3、刀片破坏2.MP3、刀片破坏3.MP3、刀片破坏4.MP3、刀片破坏5.MP3。
# 2. res://scripts/effects/三角洲_铁丝网.gd 在每次“实际损失耐久且仍未被摧毁”时，
#    从刀片破坏1~4中等概率随机播放一条位置音效；自然衰减、普通攻击和投射物半额耐久伤害
#    全部共用同一入口，因此任何有效耐久损失都有对应破坏反馈。
# 3. 某次耐久损失令 durability <= 0 时，不再播放1~4，只播放刀片破坏5作为完全破坏音效。
# 4. 最终破坏音效的 AudioStreamPlayer2D 挂到当前战斗场景而非刺网节点自身，
#    因此刺网随后 queue_free() 也不会截断约0.52秒的完全破坏声。
# 5. 五条音频均通过 ResourceLoader.exists() 安全加载；缺失时只警告并跳过，
#    不会因单个资源缺失导致铁丝网脚本解析或运行中断。
# 6. V245二维移动/全投射物格挡/盾击刺网导向/铁丝网耐久，V244自伤过滤与黄色体力条，
#    V243刺网碰撞伤害音效和钩爪命中立即拉回等全部保留。

# === V247 盾狗铁丝网投射物枚举作用域解析修复（2026-09-01） ===
# 1. 修复 V245 引入、V246 仍保留的 GDScript Parser Error：
#    res://scripts/effects/三角洲_铁丝网.gd 的 _is_projectile_node() 属于 extends Node2D 脚本，
#    却直接使用 `Ball_Type.Shooter / Ball_Type.Shooter_with_Health`。Ball_Type 实际是 class_name ball
#    内部定义的具名 enum，并不是 Node2D 当前类成员，因此编辑器报 `Identifier "Ball_Type" not declared in the current scope`。
# 2. V247 改为显式通过全局类访问：
#    `ball.Ball_Type.Shooter` / `ball.Ball_Type.Shooter_with_Health`。
#    这与项目其他非 ball 脚本（world.gd、军火商_子弹.gd、小丑投射物等）的既有写法一致。
# 3. 只修枚举作用域，不改变 V245 的“所有投射物使铁丝网掉半额耐久”判定规则，也不改 V246 的
#    刀片破坏1~4随机/5完全破坏音效规则。
# 4. 该解析错误会使三角洲_铁丝网.gd 整个脚本无法编译，并可能导致预加载/依赖它的脚本产生大量连锁错误；
#    修复源文件后应先让 Godot 重新解析脚本，再检查错误面板中是否仍有独立错误。


# === V248 盾狗竖向背后体力条 + 铁丝网抛物线碎屑（2026-09-01） ===
# 1. 盾狗专属体力条从 V244 的横向下方黄条改为竖向黄条：默认宽12、高180；
#    黄色填充按 stamina/stamina_max 从底部向上显示，体力消耗时顶部向下收缩，恢复时重新向上增长。
# 2. “永远保持在他身后”同时按空间位置与绘制顺序实现：
#    - 每次同步盾狗真实二维正面时，缓存 `_facing_direction`，并取 `_movement_forward_vector()` 的反方向，
#      按 stamina_bar_back_distance=132 把竖条中心放到人物身后；停下时继续沿用最后有效二维朝向，
#      因此向上/向下/斜向移动或停住后都不会突然跳回固定水平侧；条本身保持屏幕竖直不旋转。
#    - holder.show_behind_parent=true、最终Z保持与人物相同，并 move_child(holder,0) 放到角色子节点最前；
#      同Z的 Graphics/Image 会在它之后绘制，因此体力条稳定在人物图片后层，同时不会因负Z掉到地图地板下面。
# 3. 铁丝网每次“实际扣耐久”都会生成程序化方块碎屑，不需要新增图片资源；自然衰减、普通攻击、投射物半额
#    耐久伤害都会走同一个 `_damage_durability()` 入口，因此只要耐久真的下降就一定出现碎屑。
# 4. 普通扣耐久默认喷3个小方块；彻底破坏时默认喷13个小方块 + 4个明显更大的方块，强化完全崩解反馈。
# 5. 每块碎屑由 Polygon2D 生成冷灰金属方块，出生点在刺网范围内随机分布；横向随机向左/右抛出。
#    轨迹使用“线性落点 + -4*h*t*(1-t) 抛物线拱高”，并强制 h >= 总下落距离*0.45，保证起步导数先向上，
#    经过最高点后再向下，最终目标Y位于当前 Camera2D 可见屏幕下缘之外，确保真正掉出屏幕。
# 6. 碎屑飞行期间同步做轻微旋转（总旋转约±1.15rad以内）与尺寸动画，scale按 t² 从初始大小持续缩到约8%；
#    飞出屏幕后 queue_free()，碎屑挂在战斗场景而不是铁丝网子节点下，因此铁丝网彻底 queue_free() 时碎屑仍会继续飞完。
# 7. 当前可见世界范围使用 CanvasItem.get_canvas_transform().affine_inverse() 把 Viewport 四角转换回世界坐标，
#    与项目现有保安可见范围算法一致，兼容 Camera2D 的平移、缩放及以后可能的旋转。
# 8. V247 Ball_Type 作用域修复、V246 破坏音效、V245 全投射物格挡/二维移动/刺网耐久、V243~V244 等全部保留。


# === V249 盾狗短攻击冷却 + 体力条完整置后 + 铁丝网致命碎屑修复（2026-09-01） ===
# 1. 盾狗普通盾击新增很短的独立攻击冷却：`ram_attack_cooldown=0.22` 秒。
#    `_try_ram()` 与 `_ram()` 都检查 `_ram_attack_cooldown_left`，真正发起盾击时开始计时，
#    每物理帧递减；用于避免贴身目标时原先每个 physics tick 连续重复结算盾击伤害。
#    钩爪自身 5.2 秒冷却、技能冷却和体力恢复均不受影响。
# 2. 修复 V248 竖体力条“中心点在后面，但条本身仍压进人物中间”的空间问题：
#    旧实现固定 `stamina_bar_back_distance=132`，而竖条高度180，朝上/朝下时自身半长90会向人物方向伸回。
#    V249 改为按 `人物视觉半径 + 竖条沿当前前向的投影半径 + stamina_bar_back_gap(默认24)`
#    动态计算所需后退距离，并与旧132最低距离取最大值。这样无论上下、左右还是斜向，整根竖条都在人物后方。
#    V248 的最后二维朝向缓存、竖向自下而上填充和绘制层位于人物图片后方继续保留。
# 3. 修复铁丝网耐久归零时“没有任何碎屑”的直接生命周期根因：
#    V248 使用 `piece.create_tween().tween_method(_set_debris_progress.bind(...))`，但 `_set_debris_progress()`
#    属于铁丝网实例。致命扣耐久后铁丝网同帧 `queue_free()`，Tween 后续无法继续调用已释放母体的方法。
# 4. V249 删除碎屑对母体方法的运行时依赖：每个 Polygon2D 碎屑直接创建自己的 Tween，
#    第一段从出生点向上飞到 apex，第二段从 apex 向屏幕下缘外下落，形成明确的先上后下抛物线观感；
#    另一个绑定在碎屑自身的并行 Tween 同时把 scale 缩到约8%并做小幅旋转。
#    因此完全破坏时即使铁丝网立即 queue_free()，13个小块+4个大块仍能独立飞完整段动画。
# 5. V248 普通扣耐久3个小碎屑、完全破坏13小+4大、V246破坏音效1~4/5、V247枚举作用域修复等全部保留。


# === V250 盾狗纯竖直固定背侧体力条 + 刺网真实纹理碎屑（2026-09-01） ===
# 1. 修复 V248~V249 体力条仍会随左右移动产生上下漂移的问题：
#    根因是旧 `_update_stamina_bar_transform()` 使用完整二维 `_movement_forward_vector()` 计算“身后”。
#    AI direction 即使主要向左/右，只要带少量Y分量，反方向位置就会连带改变Y，所以用户看到条上下跑。
# 2. V250 明确“盾狗身后”按其素材真实表现定义为水平翻面背侧，不再使用二维移动向量：
#    - facing_sign>0（朝右）时，体力条固定在角色左后侧；
#    - facing_sign<0（朝左）时，体力条固定在角色右后侧；
#    - Y 永远固定为角色局部中心高度，不因 direction.y 改变；
#    - 停止时继续使用最后左右朝向；
#    - holder.rotation 每次显式归零。
# 3. 体力条不是“把横条旋转90°”：仍由 Control 根 + 两个 ColorRect 直接创建，
#    默认尺寸就是 width=12、height=180 的原生竖矩形；黄色填充只修改自身 height 和 y，从底向上增减。
# 4. 修正铁丝网碎屑材质语义：V248~V249 使用冷灰色 Polygon2D 方块，只模拟金属颜色，
#    用户要求碎屑必须真的是铁丝网的一部分。V250 完全删除该单色方块方案。
# 5. 每个碎屑现在是 Sprite2D，直接复用 `res://Images/characters/三角洲/盾狗/刺网.png`，
#    开启 region_enabled + region_filter_clip_enabled，并通过 region_rect 从原刺网纹理裁出一小块真实图像。
#    因此飞出的可见内容就是原铁丝网图片中的铁丝/刀片纹理，而不是人为指定的某个灰色像素块。
# 6. `_build_visual()` 首次加载刺网纹理时缓存一次 Texture2D.get_image()；碎屑生成时最多随机72次寻找
#    alpha>=0.12 的真实不透明刺网像素，并以该像素为中心裁切，降低裁到PNG透明空白区导致“看不见碎屑”的概率。
#    如果某运行平台拿不到Image数据，也只回退到“随机裁同一张刺网纹理”，绝不回退成单色方块。
# 7. 小/大碎屑仍沿用 V248~V249 的数量与轨迹：普通扣耐久3小；完全破坏13小+4大；
#    先上抛到apex再落出屏幕，同时缩小并轻微旋转；Tween仍绑定碎屑自身，母体刺网删除不会截断动画。
# 8. V249 0.22秒盾击短冷却、V247枚举作用域修复、V246破坏音效、V245全投射物格挡/刺网耐久等全部保留。


# === V251 盾狗竖体力条贴近人物 + 当前训练画面观感复核（2026-09-01） ===
# 1. 用户实机截图确认 V250 的竖体力条方向逻辑已稳定，但视觉上仍离人物偏远。
# 2. 根因是 V250 用 `SHIELD_DOG_VISUAL_LONGEST_SIDE*0.5` 当水平视觉半径；该常量是贴图“长边”适配到240的目标值，
#    而盾狗原图是高大于宽，因此把长边的一半当水平半宽会系统性高估人物左右边界。
# 3. V251 改为优先读取当前 Sprite2D 的真实 texture 宽度 × 当前 scale.x / 2 作为水平半宽，
#    这样体力条会贴近实际人物轮廓，而不是贴近一个假想的240×240方框。
# 4. 默认 `stamina_bar_back_gap` 从24缩至8；`stamina_bar_back_distance` 默认改为0，
#    表示默认完全由“人物真实水平边缘 + 条半宽 + 8px间隔”决定。导出项仍保留，之后可手动设更大值把条拉远。
# 5. 仍严格保持 V250 语义：体力条本体就是 width=12 / height=180 的原生竖直 Control+ColorRect，rotation=0；
#    Y固定在人物局部中心，不读direction.y；朝右在左后、朝左在右后；黄色从底部向上变化。
# 6. 本轮只调整体力条横向距离计算，不改盾击、钩爪、全投射物格挡、刺网耐久、碎屑或破坏音效。


# === V252 全人物头顶十字血条视觉优化（2026-08-31） ===
# 1. 用户要求人物头顶生命UI整体缩小10%，并把四角缺口加大，轮廓更接近明显十字。
# 2. 本轮只修改真正人物/角色：health_bar.gd 通过 owner.scene_file_path 仅接受
#    `res://scenes/characters/`；若运行时 scene_file_path 为空，只对 `res://scripts/characters/` 做保守兜底。
#    `scenes/shooter/` 下的子弹、飞刀、牌、电球、时钟等即使继承 ball.tscn 并拥有 Health_Bar，
#    也不会获得本轮缩放或十字Shader，避免把投射物误当人物。
# 3. 人物 Health_Bar 根节点在运行时将自己现有 scale 乘0.9，因此是“在各角色已有尺寸基础上缩小10%”，
#    不会覆盖军官等场景里已有的自定义位置/尺寸。生命数字、护盾、生命阈值线和能量条跟随整体一起缩小。
# 4. 新增 `res://shaders/ui/角色十字血条.gdshader`，继续复用原 `Images/未标题-1.png`，
#    不创建同义图片或替代资源。Shader以UV中心为基准，仅保留中央竖臂或横臂区域，
#    默认 arm_half_width=0.19，使四角透明区明显扩大，外框/生命填充/护盾共用同一十字Mask。
# 5. 投射物和其他非人物对象的 Health_Bar 外观保持原样；V243~V251 盾狗累计行为全部保留。
# 6. 用户本条消息在“然后所有人物（必须是人物，投射物等各种东西不算）”后截断，
#    因此 V252 不猜测其未发送完整的后续功能，只落实已完整表达的血条优化和人物范围限制。


# === V253 全人物脚底椭圆阴影补全（2026-08-31） ===
# 1. 用户实机反馈人物脚底仍没有看到此前建议的椭圆阴影；V252 只完成了人物头顶十字血条，确实没有实际创建脚底阴影。
# 2. V253 在 `res://classes/ball.gd` 公共角色基类中统一运行时创建脚底阴影，但严格限制“真正人物”：
#    - Type 必须为 Ball_Type.Ball；
#    - scene_file_path 必须位于 `res://scenes/characters/`；
#    - 极少数运行时 scene_file_path 为空时，只允许 `res://scripts/characters/` 作为保守兜底。
#    因此 `scenes/shooter/` 投射物、`scenes/creatures/` 召唤物/生物等不会获得本轮人物阴影。
# 3. 不修改 `scenes/ball.tscn`，避免共享基场景让非人物对象也继承阴影；所有人物只需继续继承现有 ball 即自动生效。
# 4. 阴影使用两个半透明 Polygon2D 椭圆叠加，不新增图片资源、不产生碰撞、不会参与 Hurtbox/Hitbox。
#    外层较宽且透明，内层更窄稍深，形成轻微软边；默认宽度约为人物实体宽的82%，高度约为实体高的13%。
# 5. 位置优先按 CharacterAutoFit 已拟合后的 CollisionShape2D 实体范围计算，并在碰撞底边下方再偏移约10%高度，
#    使椭圆真正压在人物脚底。没有有效碰撞体时才回退到当前 image 的视觉矩形。
# 6. 阴影与人物保持同一最终Z，不使用负Z；运行时 move_child(holder,0) 放到 Graphics 之前绘制，
#    并设置 show_behind_parent=true，因此人物图片会覆盖在阴影上，而阴影不会因为Z过低掉到地图地板后面。
# 7. 创建使用 call_deferred()，确保盾狗这类在 super._ready() 后才替换正式贴图的角色也能在最终视觉准备完毕后建立阴影。
# 8. V252 人物十字血条、V251 盾狗竖体力条距离、V243~V250 的盾狗/铁丝网累计行为全部保留。


# === V254 人物脚底阴影主体核心算法 + 位置上移（2026-08-31） ===
# 1. 用户实机反馈 V253 阴影位置偏下，并指出阴影大小不能直接跟整张人物图/完整包围盒走：
#    例如人物伸长手臂、举长武器时，视觉横向范围会突然增大，但脚底影子应该仍主要反映躯干/身体本体大小。
# 2. V254 不再把完整 CollisionShape2D 宽度直接乘比例作为首选阴影宽度，而是新增“Alpha 主体核心采样”算法：
#    - 在当前人物视觉矩形中按 64×64 网格采样真实纹理 Alpha；
#    - 在人物约 8%~92% 高度范围内统计每一列的不透明占比；
#    - 以固定最低密度 + 相对最密列比例形成动态阈值；
#    - 选择最长连续高密度列作为身体核心。
#    因为伸出的手臂、刀剑、枪、飘带等横向突出物通常只占很少几行，其列密度明显低于躯干，
#    所以不会再把阴影宽度一起拉长。
# 3. 阴影宽度按身体核心宽度×0.90计算，并限制在54~138本地单位；阴影高度改为宽度×0.19，
#    限制在10~24，保持稳定的扁椭圆观感，而不是跟整个人物高度/动作幅度一起变化。
# 4. 脚底位置也改为主体核心列内不透明像素Y的92%分位，避免一两个向下伸出的细尖/武器像素把锚点拖低。
#    V253 原先是“碰撞底边 + 约10%高度”把阴影继续往下推；V254 改成以主体脚底为锚点，
#    再把椭圆中心向上压入脚底约自身高度的28%，因此实机位置会明显更贴脚。
# 5. Alpha采样失败时才回退到 CollisionShape2D；回退宽度仍使用 min(碰撞宽, 碰撞高×0.78) 做上限，
#    避免超长横向动作在极端情况下重新把影子拉得过宽。
# 6. 阴影仍只对 scenes/characters/ 的真正人物启用；投射物/creatures 不受影响。
#    V252 十字血条、V251 盾狗体力条、V243~V250 盾狗/铁丝网累计行为全部保留。


# === V255 人物阴影 Y 中心锁定最低有效像素行（2026-08-31） ===
# 1. 用户明确要求：人物脚底阴影的 Y 轴中心位置必须等于人物图片最底下“真正有内容”的位置；PNG 透明空白不算，
#    同时不能让只有一个像素点/极少数孤立像素的噪点、细线或武器尖端决定脚底。
# 2. V254 使用主体核心像素 Y 的92%分位，并再把阴影中心向上压入约自身高度28%；这与用户本轮要求不一致，V255 删除该语义。
# 3. V255 保留 V254 的“Alpha主体核心宽度”算法来决定影子大小；只重做脚底 Y：
#    - 在已识别的主体核心横向范围内，从视觉矩形最底部逐行向上扫描；
#    - 纵向扫描分辨率约为当前视觉矩形每1本地像素一行；
#    - 每行横向采样96点；
#    - 候选行至少要有5个不透明采样点，并至少覆盖主体扫描宽度的6%；
#    - 同时至少要出现3个连续不透明采样点，单个孤立像素不会被承认为脚底。
# 4. 找到的第一条满足条件的最低有效行就是 foot_y；阴影 holder 的中心Y直接设置为该 foot_y，
#    不再向上或向下加任何视觉偏移。也就是说：有效图片最底边 == 椭圆阴影的水平中轴线。
# 5. 如果纹理 Alpha 无法读取或找不到任何满足条件的有效底边，才回退 CollisionShape2D 底边；
#    阴影宽度仍使用 V254 身体核心算法/受限碰撞回退，伸长手臂和长武器不会把阴影横向拉大。
# 6. 阴影仍只作用于 scenes/characters/ 真正人物；投射物、creatures 等不受影响。V252十字血条、V251盾狗体力条、
#    V243~V250盾狗/铁丝网累计行为全部保留。


# === V256 meme新增“野生狗奶 / 不坏煎饼”双人物（2026-08-31） ===
# 1. 新增两个真正人物场景，固定沿用项目既有 meme 路径，不创建同义目录：
#    - res://scenes/characters/meme/野生狗奶.tscn
#    - res://scenes/characters/meme/不坏煎饼.tscn
#    对应脚本固定在 res://scripts/characters/meme/；不坏煎饼的永久弹体使用既有
#    res://scenes/shooter/ + res://scripts/shooter/，不会把投射物误放进 characters。
# 2. 新增原创项目内视觉资源（不直接复制网络 meme 图片）：
#    - res://Images/characters/meme/野生狗奶/野生狗奶.svg
#    - res://Images/characters/meme/不坏煎饼/不坏煎饼.svg
#    - res://Images/shooter/meme/不坏煎饼弹.svg
#    三个资源都保持项目 Images/ 大写 I 规则；角色场景另放名称 Label，保证训练/战斗里可读。
# 3. 野生狗奶不做普通攻击/主动技能，核心为周期性“时间加速”：第一次约4秒后启动，之后每次结束约7.5秒再启动；
#    每次持续约5.5秒。实现不另造一套全局时间系统，而是复用 global/game.gd 已有
#    Game.request_time_scale_override()/release_time_scale_override()：世界倍率从约0.78逐渐压到0.24，
#    从野生狗奶视角等价于自己越来越快、整个世界越来越慢；并继续兼容项目速度滑条及其它时间覆盖。
# 4. 野生狗奶自身不被自己时间场拖慢：其阶段计时使用 delta / 当前自身时间倍率；公共移动前在 world.gd 已结算完
#    Buff 的 Speed 上再除当前自身倍率，因此其真实移动节奏基本保持正常，而其它人物/投射物/基于delta的世界逻辑
#    会随 Engine.time_scale 正常减速。多人时 authority 通过 RPC 同步同一时间覆盖；结束/死亡/退树可靠释放覆盖，避免残留慢速。
# 5. 时间加速期间所有“敌方人物”持续衰老，真实同队永不衰老；衰老百分比写入目标 meta
#    wild_dog_milk_age_percent，并跨多次时间加速永久累计。每次加速越到后段：
#    - 世界倍率越低；
#    - 衰老脉冲间隔从约0.72秒缩短到0.18秒；
#    - 单次衰老增长从约2%提高到4%；
#    因此低伤害的触发频率与衰老速度都会越来越快。
# 6. 衰老按百分比实时降低敌人的核心战斗属性：Damage、Speed 按同一倍率下降；Attack_Cooling、Skill_Cooling
#    按倒数倍率变长。默认从100%逐渐衰退到最低约32%，通过 world.new_buff() 的永久 cover Buff 实现，
#    不直接永久篡改目标 default_properties。每个脉冲另造成低额 raw health damage；衰老达到100%时直接造成足量
#    raw health damage 触发“老死”，绕过护盾但仍走公共伤害/死亡归因入口。
# 7. 野生狗奶使用左侧永久状态显示当前“时间 x倍/时间蓄积”，被衰老目标使用右侧状态显示“衰老N%”；
#    自身时间加速期间只做轻微视觉脉冲/偏黄绿，不新增额外贴图或粒子目录。
# 8. 不坏煎饼本体无普通攻击，自带且只维持一枚永久反弹弹体：
#    res://scenes/shooter/不坏煎饼弹.tscn。弹体继承 ball、Type=Shooter，使用圆形物理/Hitbox，
#    沿公共 move_and_slide()/when_collide() 真实碰撞法线持续反弹；受到盾狗等“投射物格挡”时只反弹离开盾牌，
#    覆写 on_projectile_blocked_by()，不执行普通投射物被格挡后销毁逻辑。即使异常被伤害到0血，进入Die前也会恢复。
# 9. 不坏煎饼弹初始速度约460、伤害倍率1.0、对同目标重复命中锁约0.24秒；默认24秒逐渐完全腐烂：
#    - 速度平滑下降到约170；
#    - 伤害倍率下降到约0.36；
#    - 同目标命中锁逐渐变长到约0.78秒，等价于攻速/有效命中频率下降。
#    Damage 本体由 Master 的整体攻击力继承，继续服从不坏煎饼自己的 Damage Buff/Debuff。
# 10. 新增 res://shaders/不坏煎饼腐烂.gdshader。弹体运行时为自己创建独立 ShaderMaterial，
#     使用 set_shader_parameter("rot_amount") 驱动：颜色从金黄逐步变成深绿色并整体变暗；腐烂阶段分批开启多个
#     透明缺口，后期再从外缘不规则缺失，形成“逐渐腐烂、被吃掉/烂掉产生缺口”的连续视觉，而非瞬间换图。
# 11. 煎饼弹腐烂达到70%后，每次真正造成生命伤害都会给目标追加一层“不坏煎饼_无限腐毒”：
#     使用项目现有 Buff.Buff_types.poison + Algorithms.add + duration=INF，重复命中没有层数上限；
#     每层默认增加2点/秒的公共毒伤，旧层不会被新层覆盖，因此腐烂后虽然本体伤害/速度/攻速更低，长期中毒会越来越重。
# 12. 不坏煎饼技能为“完全刷新自身状态”，默认32秒冷却（必须长于弹体进入腐毒阶段所需约16.8秒，
#     避免AI自动施法导致煎饼永远还没腐烂到中毒就被刷新）。技能触发时：
#     - Buff_Dic.clear() 删除自身一切正/负 Buff；
#     - 把开局保存的 default_properties 与 Damage/Speed/Max_health/Attack_Cooling/Skill_Cooling/Health_Restore/
#       Damage_reduction/max_block/max_energy 等当前值重新写回；
#     - health/block/energy 回满到开局最大值；
#     - 清除野生狗奶衰老meta、全部侧边永久状态、状态图、通用眩晕/击退控制、红牌禁伤时间、Hurt闪白；
#     - Attacking/Using_Skill/continue_attack_time 与 StateMachine 所有 last_state_dis 冷却累计恢复到开局0；
#     - 不恢复地图位置，避免“刷新状态”变成传送回出生点。
# 13. 完全刷新同步刷新永久煎饼弹：若弹体正常存在，则 rot_elapsed/rot_ratio、速度、伤害阶段、命中锁、视觉缺口/
#     深绿色腐烂全部恢复0%；若弹体因场景异常缺失则自动重新生成。角色死亡/离开场景时才主动清理其永久弹体。
# 14. 不坏煎饼弹只在实际战斗运行时由 authority 创建，布阵阶段不提前乱飞；加入 BattleTransient 以兼容回合/场景清理。
# 15. translations.csv 新增“野生狗奶 / 不坏煎饼 / 不坏煎饼弹”的中英文条目；world.gd 本身会递归扫描
#     res://scenes/characters/meme/ 的 .tscn，所以不需要给角色列表另写硬编码注册。
# 16. V255人物阴影最低有效像素Y、V252人物十字血条、V243~V251盾狗/铁丝网累计改动全部保留。


# === V257 翻译表补全 / 三角洲黑话英文名（2026-09-01） ===
# 1. 本轮系统扫描当前已上传 scenes/characters/ 中的分类名、人物场景名，以及角色/召唤物/投射物场景里的
#    Type_Tags / Negative_Tags；translations.csv 补齐当前缺失项，避免英文模式继续显示中文标签。
# 2. 三角洲相关人物名按“官方英文名优先，中文社区黑话保留语义”处理：
#    - 跑刀仔 -> Knife Runner；
#    - 盾狗 -> Sineva (Shield)，因为“盾狗”是深蓝/Sineva 的中文玩家黑话，不采用生硬的 Shield Dog 作为正式显示名；
#    - 夺舍狼 -> Body-Snatcher D-Wolf，用 D-Wolf 明确对应红狼并保留“夺舍流”黑话含义；
#    - 背刺鼠继续使用既有 Backstab Rat。
#    既有红狼/D-Wolf、蜂医/Stinger、露娜/Luna、牧羊人/Shepherd、威龙/Vyron、骇爪/Hackclaw、
#    乌鲁鲁/Uluru、深蓝/Sineva、蛊/Toxik、疾风/Tempest、无名/Nox、银翼/Raptor、比特/Gizmo 等映射保留。
# 3. 新增当前场景遗漏的人物/分类翻译：乐队、战斧重骑兵、寸头没事沙漠溜达猪等；同时补齐铁丝网、方向减伤、
#    两条命、搜刮、永久弹体、衰老、腐烂、流血、反伤等当前场景已实际使用的玩法标签。
# 4. 补齐玩家可见的动态状态文字片段：回血、煎饼腐烂、腐毒、腐毒持续叠加、时间蓄积、状态完全刷新等，
#    继续复用 character_side_status_ui.gd 的 Game.translate_game_text()，不新增第二套状态翻译系统。
# 5. 重女随机漂浮文字原来逐字直接显示 text_pool 中文，本轮只把 scripts/effects/重女文字.gd 的 setup() 改为
#    Game.t(p_text)，并在 translations.csv 加入“别走/看着我/为什么/回来/你在哪/不要丢下我/一直在一起/听我说”。
#    不修改重女伤害、生成频率、黑洞、文字抖动或任何战斗数值。
# 6. 本轮不改任何已有资源文件名/目录名/res:// 引用；V256 meme 双人物、V255 阴影最低有效像素 Y、
#    V252 十字血条以及更早累计规则全部保留。


# === V258 翻译英文简化（2026-09-01） ===
# 1. 根据用户反馈，V257 新补英文统一改为更短的游戏 UI 风格；旧翻译不做全表重写。
# 2. 三角洲人物优先使用官方英文名：盾狗显示为 Sineva；跑刀仔保留简短黑话译名 Knife Runner；夺舍狼简化为 Possessed D-Wolf。
# 3. 角色/机制标签尽量压到 1~3 个词，例如 Directional DR、Needs Ally、Full Reset、Axe Cavalry、Buzzcut Pig。
# 4. 本轮仅修改 res://translations.csv 与本注释；V257 的 res://scripts/effects/重女文字.gd 翻译入口继续累计保留，不改玩法数值、场景、资源路径或文件名。


# === V287 菊花茶重力速度线主体锚定/像素取色/按主体缩放重做（2026-09-02） ===
# 1. 用户实机截图确认 V286 仍然错误：速度线像随机铺在地图/屏幕上的长线，没有明确“长在主体上”的感觉，
#    人物线也过粗/过长；本轮只重做 `res://scripts/effects/菊花茶重力视觉.gd` 的视觉算法，不改菊花茶重力数值、伤害、水滴或音效。
# 2. 新规则严格按“主体 -> 起点 -> 方向 -> 线段”生成：每一条线先绑定一个真实主体，再在主体上确定起点；
#    人物/投射物优先从 Sprite2D 的真实不透明像素中挑选起点，且优先挑重力轴两侧更靠外的像素，避免从透明框/空气中起线。
# 3. 起点颜色直接读取该 Sprite2D 像素的纹理颜色，并继续叠加 Sprite modulate/self_modulate；
#    地图线的起点固定选当前地图矩形在重力轴两侧的真实边界点，颜色取重力触发前干净 Viewport 快照中该起点像素。
# 4. 速度线不再全部朝同一个屏幕方向漂走。同一主体的线分布在重力轴两侧：起点位于哪一侧，就沿该侧向主体外延伸；
#    同时允许按主体尺寸向反方向（主体内部）回拖一小截，因此视觉上是“从主体像素长出去的一条线”。
# 5. 跟随方式改为保存局部锚点：人物/投射物保存 Sprite2D local_point，地图保存当前 map_node local_point；
#    `_draw()` 每帧重新 to_global()，所以人物移动、翻转、旋转/缩放或地图变换后，速度线起点仍跟着主体，不会留在旧世界坐标。
# 6. 线长/线宽改为按主体真实视觉尺寸计算，不再用统一 28~105 / 1~2.8 的人物常量：
#    - 人物/小投射物按 Sprite2D 四角转换后的世界尺寸缩放，默认线宽约主体长边的0.6%~1.4%，并限制为0.32~2.25世界单位；
#    - 线长约主体长边24%~68%，仅允许很小的向内回拖；因此小人物会得到明显更细、更短的线；
#    - 地图按地图矩形长边缩放，线长约8%~24%、线宽约0.18%~0.42%，上限仍有限制，因此地图主体会自然得到远大于人物的速度线。
# 7. 地图不再在矩形内部随机撒起点；若重力轴主要竖直，只从地图上/下边界取点；主要水平则只从左/右边界取点。
#    这对应用户参考图中“黑色地图轮廓像素作为起点，长线从轮廓向外伸出”的效果，也避免蓝色背景中央凭空冒线。
# 8. 图案仍约每0.22~0.36秒重抽一次，但重抽的是各主体上的锚点、长度、回拖量和宽度；V286 的干净快照取色、
#    菊花茶 gravity direction 动态跟随、RPC 同步、重力音效与屏幕震动全部累计保留。


# === V288 菊花茶新图片 / 吸管枪口瞄准 / 重力速度线尺寸修正（2026-09-02） ===
# 1. 使用用户本轮提供的新菊花茶包装图替换 res://Images/characters/meme/菊花茶/菊花茶.png；
#    新增用户提供的透明吸管图 res://Images/characters/meme/菊花茶/吸管.png。两张图均保持项目 Images/ 大写 I 规则。
# 2. 菊花茶场景新增 Graphics/StrawPivot/StrawSprite。吸管 z_index 低于菊花茶本体 Image，
#    因此旋转后的长管会自然被茶盒遮挡；茶盒仍由既有 CharacterAutoFit 控制尺寸，脚本每帧同步吸管与茶盒 Sprite scale。
# 3. 吸管以原图长管右下端作为隐藏在茶盒内的旋转轴，以短管开口作为真实发射口。
#    StrawPivot.rotation 每帧跟随当前玩家瞄准/AI目标的大致子弹方向；子弹出生点不再取人物头顶，而是实时读取吸管开口世界坐标。
#    旧头顶出生逻辑只作为吸管节点/资源损坏时的安全兜底。
# 4. res://scripts/effects/菊花茶重力视觉.gd 的人物/投射物速度线进一步缩小：每个主体2~5条，
#    线长约主体长边8%~18%并硬限制3~24世界单位，线宽约0.25%~0.50%并硬限制0.22~0.95；
#    不再出现人物线与地图线接近同等长度/粗细的情况。
# 5. 地图速度线只从 return_map_world_rect() 的真实两侧边界取起点；颜色固定纯黑 Color.BLACK，
#    不再读取地图/Viewport像素颜色。地图内部不生成速度线，保持“只有边界黑色速度线”。
# 6. 菊花茶的重力数值、周期、音效、屏幕震动、水滴伤害、抛物线与多人同步规则全部保持 V287 之前累计实现不变。


# === V289 菊花茶吸管拆分：长管固定 / 上方弯头有限旋转（2026-09-02） ===
# 1. 根据用户反馈，V288“整根吸管围绕茶盒内插入点旋转”取消。吸管现在拆为两层：
#    - `Graphics/StrawBody`：只显示原吸管的长直管，和菊花茶图片保持同画布位置/缩放，rotation 永远为 0；
#    - `Graphics/StrawHeadPivot/StrawHeadSprite`：只显示上方 U 形弯头与短管，围绕原图顶部接点单独旋转。
# 2. 两个拆分 PNG 都只来自用户原始 `吸管.png` 的透明像素裁切/遮罩，没有生成新美术内容，也不改变原图颜色、比例或纹理。
# 3. 长直管不读取玩家瞄准或 AI 目标方向，因此不会再随着子弹大角度左右甩动；它只随角色/茶盒整体移动和 CharacterAutoFit 缩放。
# 4. 上方弯头的接点固定在原图约 UV(0.319,0.105)，始终位于茶盒上方。弯头按当前水滴大致发射方向旋转，默认最大角度限制 ±48°，避免头部翻到茶盒下方。
# 5. 水滴出生点继续使用短管真实开口世界坐标，但 V289 默认把水平/垂直出生随机偏移降为 0，保证视觉上确实从管口射出；抛物线本身的弧度随机仍保留。
# 6. 茶盒本体仍 z_index=1，固定长管和可旋转弯头均 z_index=0，因此插入茶盒内部的部分继续被茶盒遮挡。
# 7. V288 的人物/投射物小速度线与地图纯黑边界速度线、重力数值、音效、屏幕震动、多人同步全部不变。


# === V289 菊花茶吸管拆分：长直管固定 / 弯头独立瞄准（2026-09-02） ===
# 1. 根据用户反馈，V288 整根吸管随瞄准方向旋转不符合需求。V289 把视觉拆成两部分：
#    - StrawStem：长直管，固定插在茶盒后方，只跟随菊花茶整体位置/缩放，禁止跟着子弹方向整根大幅摆动；
#    - StrawHeadPivot/StrawHead：顶部弯头与短管口，只这一部分绕顶部连接点旋转。
# 2. 两部分继续直接复用用户提供的 res://Images/characters/meme/菊花茶/吸管.png；使用 Polygon2D 的 polygon/uv
#    在运行时显示原图不同区域，不生成新的吸管图片、不改原图片文件名。
# 3. 长直管根部仍隐藏在菊花茶 Image 后方，z_index 关系保持“吸管在后、茶盒在前”，所以插入部分继续由茶盒遮挡。
# 4. 顶部弯头旋转基准使用原图中的真实管口方向；当前玩家瞄准/AI目标方向只更新 StrawHeadPivot.rotation。
#    水滴出生点改为该旋转弯头的实时管口世界坐标，因此管口大致朝哪，子弹就从哪一方向射出。
# 5. V288 的人物速度线缩小、地图只保留纯黑边界速度线，以及更早所有重力/伤害/多人规则全部保留不变。


# === V290 菊花茶 V289 吸管脚本解析错误修复（2026-09-02） ===
# 1. 用户实机报错：res://scripts/characters/meme/菊花茶.gd 在 V289 的 _projectile_spawn_anchor() 中引用
#    straw_head_joint_uv，但类成员声明区残留的是另一版命名 straw_head_pivot_uv，导致 GDScript Parser Error：
#    Identifier "straw_head_joint_uv" not declared in the current scope。该首个解析错误会让菊花茶脚本整体无法加载，并可能造成编辑器级联显示大量错误。
# 2. 根因是 V289 吸管拆分重构时混入了两套未统一的节点/变量命名：脚本顶部残留 StrawBody/StrawHeadSprite 的 Sprite2D
#    声明，但实际场景是 Graphics/StrawRig/StrawStem(Polygon2D) 与 Graphics/StrawRig/StrawHeadPivot/StrawHead(Polygon2D)；
#    函数体同时还引用 _straw_rig/_straw_stem/_straw_head、straw_head_joint_uv、straw_mouth_inner_uv 等另一套名字。
# 3. V290 统一为实际场景结构：_straw_rig:Node2D、_straw_stem:Polygon2D、_straw_head_pivot:Node2D、_straw_head:Polygon2D，
#    并补齐/统一 straw_canvas_center_uv、straw_head_joint_uv、straw_mouth_uv、straw_mouth_inner_uv、straw_body_offset、
#    straw_head_anchor_offset、straw_visual_scale_multiplier、straw_head_max_rotation_deg。删除所有已不存在的 straw_insert_*、
#    _straw_body_sprite、_straw_head_sprite、straw_head_pivot_uv 引用，避免后续继续出现同类未声明标识符。
# 4. 长直管继续保持 rotation=0，只跟随茶盒整体位置/缩放；上方弯头继续围绕固定顶部接点独立旋转。
#    本轮额外把 straw_head_max_rotation_deg 真正用于 clamp，默认仍为 ±48°，确保弯头有角度变化但不会把整根长管甩动或把头翻到茶盒下方。
# 5. 水滴出生点仍使用旋转后的短管真实开口世界坐标；不恢复人物头顶作为正常发射点，头顶只在吸管节点/纹理损坏时兜底。
# 6. V288/V289 的人物小速度线、地图纯黑边界速度线、新菊花茶图片、吸管遮挡、重力数值/音效/多人规则全部不变。
# 7. 本轮不生成图片、不新增图片文件、不移动/重命名任何项目资源；仅修复 res://scripts/characters/meme/菊花茶.gd 的解析与吸管变量一致性，
#    并同步更新本注释与 PROJECT_PATH_MAP_FOR_AI_V34.md。


# === V291 菊花茶本体视觉下移 / 吸管整体上提（2026-09-02） ===
# 1. 根据用户实机反馈，V290 的吸管虽然已经拆成固定长管 + 可旋转弯头，但整体位置仍偏低，
#    顶部弯头大部分落在茶盒图片后面；同时茶盒本体顶部距离 Health_Bar 太近，吸管向上露出后容易继续被血条挡住。
# 2. 本轮调整 `res://scripts/characters/meme/菊花茶.gd` 与 `res://scenes/characters/meme/菊花茶.tscn` 的视觉构图，
#    不改攻击、伤害、重力、血条、真实碰撞、图片资源或路径。
# 3. 新增 `tea_body_visual_offset = Vector2(0,12)`。该偏移在 `super._ready()` 之后才写入 Graphics/Image.position；
#    CharacterAutoFit 子节点已经先完成初始视觉/碰撞拟合，所以这里只把茶盒图片向下移，不把角色根、Health_Bar、
#    CollisionShape2D、hitbox、hurtbox 一起向下拖，避免为了给吸管留空间而改变真实战斗几何。
# 4. 菊花茶场景把 `straw_body_offset` 覆盖为 `Vector2(0,-38)`。`_sync_straw_to_tea_sprite()` 仍以
#    `tea_sprite.position + straw_body_offset` 同步整套 StrawRig，因此茶盒视觉下移后，吸管会相对茶盒明显上提；
#    顶部 U 形弯头能露出更多，但长直管仍保持 rotation=0，不跟随瞄准整根摆动。
# 5. `StrawHeadPivot` 仍只负责顶部弯头有限旋转，V290 的 ±48° 限制、真实管口发射点与茶盒前/吸管后的 z_index
#    关系全部不变；插入茶盒内部的管身仍被茶盒遮挡。
# 6. 本轮不生成图片、不改图片、不移动/重命名资源；V288~V290 的人物小速度线、地图纯黑边界速度线、吸管拆分、
#    菊花茶重力数值/音效/多人同步与水滴抛物线全部继续保留。


# === V292 菊花茶吸管改为场景手动编辑（2026-09-02） ===
# 1. 用户明确要求停止继续由脚本猜吸管区域/位置，改为让用户在 Godot 2D 编辑器里手动调整。
#    本轮修改 res://scripts/characters/meme/菊花茶.gd 与 res://scenes/characters/meme/菊花茶.tscn；
#    不生成图片、不改现有菊花茶/吸管 PNG，不改攻击、重力、速度线、伤害或多人规则。
# 2. V291 的 _sync_straw_to_tea_sprite() 每物理帧会重写 StrawStem/StrawHead 的 polygon/uv、
#    StrawHeadPivot.position，因此用户即使在场景里改区域/接点也会被运行时覆盖。V292 删除这些运行时写死操作。
# 3. 吸管场景现在直接保存可编辑几何：
#    - Graphics/StrawRig：整套吸管的手工总位置/静态旋转/手工缩放基值；
#    - StrawStem：固定长管 Polygon2D，polygon 与 uv 直接保存在 .tscn，可用 Polygon2D UV 编辑器重画；
#    - StrawHeadPivot：改为 Marker2D，十字就是可旋转头的真实转轴，position 可手工拖动；
#    - StrawHead：可旋转头 Polygon2D，polygon/uv 同样由 .tscn 保存，脚本不再覆盖；
#    - StrawMouthInner / StrawMuzzle：两个 Marker2D 分别定义管口内侧方向点与真实发射口。
# 4. 水滴正常出生点直接读取 StrawMuzzle.global_position。用户把 StrawMuzzle 十字拖到哪里，水滴就从哪里出生；
#    Marker 被误删/损坏时才回退人物头顶，projectile_spawn_* 随机偏移规则继续保留。
# 5. 吸管头 rotation=0 时的基础朝向由 StrawMouthInner -> StrawMuzzle 两点向量确定；运行时把当前子弹/瞄准方向
#    转到 StrawRig 局部角度，只修改 StrawHeadPivot.rotation。straw_head_max_rotation_deg 继续限制最大摆角；
#    新增 straw_aim_angle_offset_deg，若整套视觉朝向与实际子弹存在固定角差，可在根节点 Inspector 手工微调。
# 6. StrawRig 的场景 position/scale/rotation 在 _ready() 只读取一次作为 authored 基值；后续只叠加茶盒 Image 的
#    CharacterAutoFit 运行时 scale 与 tea_body_visual_offset 的视觉位置。用户在 .tscn 手动摆好的位置不会再被脚本参数覆盖。
# 7. V288~V291 的茶盒前/吸管后 z_index、人物小速度线、地图纯黑边界速度线、本体视觉下移、重力数值/音效/
#    屏幕震动/多人同步与水滴抛物线全部累计保留。


# === V293 菊花茶吸管编辑器/局内尺寸一致 + 用户场景作为新基线（2026-09-02） ===
# 1. 用户上传并手工修改了 res://scenes/characters/meme/菊花茶.tscn；本轮明确以该上传场景为新基线继续更新，
#    不恢复 V292 旧 Polygon2D 区域、Pivot/Marker 坐标或旧节点构图。用户当前保存的 StrawStem/StrawHead polygon/uv、
#    StrawHeadPivot、StrawMouthInner、StrawMuzzle 位置全部原样保留。
# 2. 根因：V292 场景里的 StrawRig.scale=1，但运行时 _sync_straw_to_tea_sprite() 又乘 Graphics/Image.scale≈0.11570553。
#    因此 2D 编辑器中吸管会比菊花茶大约 8.6 倍，只有进入游戏后才被脚本缩小，导致手动编辑完全不是所见即所得。
# 3. V293 把当前实际运行尺寸直接烘焙到场景：StrawRig.scale=Vector2(0.11570553,0.11570553)。
#    同时删除运行时“再次乘 Image.scale”的二次缩放；straw_visual_scale_multiplier 默认1时，编辑器尺寸就是局内尺寸。
# 4. 为消除位置上的同类隐藏差异，V291 的 tea_body_visual_offset=(0,12) 也烘焙到 Graphics/Image.position=(0,12)，
#    根参数改为 tea_body_visual_offset=Vector2.ZERO；原先运行时得到的 StrawRig 最终位置 (0,-26) 直接保存到场景。
#    所以茶盒下移/给血条留空间的 V291 构图效果保留，但不再等进入游戏后才发生。
# 5. _sync_straw_to_tea_sprite() 现在只恢复 StrawRig 在 .tscn 中保存的 authored position/rotation/scale，并可选叠加
#    straw_visual_scale_multiplier；不再读取 Image.position/scale 做二次变换。StrawHeadPivot.rotation 仍是唯一随瞄准动态变化的吸管变换。
# 6. 水滴仍从用户手工摆放的 StrawMuzzle.global_position 出生；长管/吸管头 Polygon2D 区域、转轴、管口仍完全由场景手调。
#    V288~V292 的地图纯黑边界速度线、人物/投射物小速度线、重力、伤害、多人规则全部保留。


# === V294 菊花茶用户场景续作 / 吸管左右镜像 / 连续实时瞄准（2026-09-02） ===
# 1. 用户再次上传并手工修改了 res://scenes/characters/meme/菊花茶.tscn；V294 以这份场景作为新的唯一构图基线。
#    本轮不回退用户手工修改：Graphics.position、StrawRig.position/scale/skew、StrawStem/StrawHead polygon/uv、
#    StrawHeadPivot、StrawMouthInner、StrawMuzzle、CollisionShape2D/hitbox/hurtbox 当前保存值全部继承。
# 2. 修复“人物左右反转但吸管不反转”。项目公共 ball 的人物图片朝向可能由 Shader 的 sprite_flip_h 完成，
#    因而单独的 StrawRig 不会自动跟着 Image 镜像。V294 每帧读取 is_character_visual_flipped_h()，
#    对用户 authored StrawRig Transform2D 在 Graphics 父空间做水平反射。反射同时作用于整套吸管几何与 position.x，
#    因此角色换边时吸管位置也会左右对称，不只是纹理本身翻转。
# 3. 用户当前 StrawRig 含 skew。V293 用 position/rotation/scale 分拆恢复基础变换会丢失/误解释这类完整矩阵信息；
#    V294 改为 _ready() 时直接保存 StrawRig.transform，并在运行时基于完整 Transform2D 做镜像，避免破坏用户手调 skew。
# 4. 修复“吸管角度不是实时变化、到一定角度才突然跳”。V294 新增 _process(delta) 渲染帧视觉更新，
#    StrawHeadPivot 不再只依赖物理帧/AI预算更新；每个渲染帧都会重新读取当前玩家瞄准或既有目标的实时世界位置。
# 5. 吸管方向换算不再只使用 StrawRig.global_rotation。由于用户当前场景有 scale + skew，且运行时还可能水平反射，
#    单一 rotation 无法表示完整基变换。V294 使用 StrawRig.global_transform.affine_inverse().basis_xform()
#    把世界瞄准方向准确转换到 StrawRig 局部空间，再计算 StrawHeadPivot 的目标角。
# 6. StrawHeadPivot 使用 lerp_angle() + 指数响应连续逼近目标角，新增 straw_aim_follow_response（默认30）。
#    没有角度分档/阈值；每帧都移动。开火时也不强制 snap 到新角度，避免攻击瞬间出现视觉跳变。
# 7. straw_head_max_rotation_deg 默认 ±48°、用户手调管口 Marker、真实 StrawMuzzle.global_position 发射点、
#    茶盒遮挡关系、水滴数值、重力/速度线/多人规则全部继续累计保留。本轮不生成图片、不改图片资源。


# === V295 菊花茶吸管真正逐渲染帧跟踪 / 速度线不再被地图外背景遮挡（2026-09-02） ===
# 1. 用户实机继续确认 V294 吸管仍有“到一定角度才突然变一下”的阶梯感。根因不是 lerp_angle 本身，
#    而是本机直接控制瞄准的 player_control_aim_position 由 Game._process_control_movement() 在 _physics_process() 中更新；
#    即使菊花茶自己的 _process() 每个显示帧都运行，读取到的仍是上一物理 Tick 的鼠标世界坐标。
# 2. V295 对“本机正在直接控制的菊花茶”走纯视觉专用实时路径：在菊花茶._process() 中直接调用
#    CanvasItem.get_global_mouse_position()，用当前鼠标世界位置 - 角色 global_position 得到方向。
#    该路径只改变 StrawHeadPivot 视觉，不改变公共 Game 输入同步、网络 authority、真实子弹伤害或移动规则。
# 3. StrawHeadPivot.rotation 现在只有 _process() 一个正常运行时写入者。tick_physics() 只在 super.tick_physics() 后
#    同步 StrawRig 左右镜像，不再把 60Hz 缓存瞄准重新写回弯头；_spawn_tea_droplet() 也不再在攻击物理帧额外改弯头角度。
#    这样可避免“渲染帧刚跟到鼠标 -> 物理帧又退回旧角 -> 下一显示帧再追上”的微回跳/阶梯。
# 4. 正常吸管视觉每个渲染帧直接写当前目标角，不再通过 straw_aim_follow_response 做指数滞后；该 export 仅为旧场景
#    兼容保留，避免删除字段造成已有 .tscn 属性丢失。±48° 默认弯头最大摆角、左右镜像、用户 Polygon/Pivot/Marker 手调值均不变。
# 5. 用户同时反馈重力速度线伸到地图边界外后会被“地图外背景”遮掉。World 当前 MapOutsideVisualMask 用于在地图外
#    重新绘制 BackBuffer 背景，root z_index=90 且继承 World z=-2，最终约为88；真实 MapBorderSegments z=100，最终约为98。
# 6. 菊花茶重力视觉原来 z_as_relative=false / z_index=40，必然先于地图外遮罩绘制，因此线段在地图外部分会被覆盖。
#    V295 把速度线绝对 z_index 提到97：高于地图外遮罩、低于最终约98的黑色地图边框。地图边界线仍压在最上面，
#    但速度线向外延伸部分不会再被背景恢复遮罩吃掉。
# 7. V288 的地图速度线“只取真实边界、固定纯黑”、人物/投射物线明显小于地图线、重力数值/音效/水滴/多人规则全部保留。
#    本轮不生成图片、不改用户场景、不移动/重命名任何资源。


# === V296 菊花茶吸管取消 ±48° 死区 / 鼠标事件 + 渲染帧实时跟踪（2026-09-02） ===
# 1. 用户实机继续反馈 V295 “吸管还是没实时跟踪”。重新按用户当前手调场景数值检查后确认，V295 只解决了鼠标数据刷新频率，
#    但仍保留 `straw_head_max_rotation_deg = 48` 的硬夹断，这才是当前最明显的“到一定角度才变化”来源。
# 2. 用户当前 StrawMouthInner=(-66.449,213.44)、StrawMuzzle=(-11.96,340)，因此 rotation=0 的基础管口方向约为 66.7°。
#    当鼠标/子弹大致水平向右时，Pivot 实际需要约 -66.7° 才能把管口对准右方；旧版却把它夹在 -48°。
#    结果是从水平、右上直到一大段右下方向，目标角都会被压成同一个 -48°，视觉上必然像“鼠标移动了但吸管不动，跨过阈值才突然动”。
# 3. V296 将 `straw_head_max_rotation_deg` 的可调范围扩展到 0~180°，当前场景默认保存为 180°。
#    180° 对 wrapf(-PI,PI) 后的目标角等价于不额外截断，因此 StrawHeadPivot 会连续对应完整鼠标角度；
#    固定长管 StrawStem 仍完全不旋转。若以后用户确实想限制弯头机械摆幅，可在 Inspector 主动把该值调低。
# 4. 本机直接控制时新增 `_input(InputEventMouseMotion)` 路径：鼠标运动事件到达就缓存当前世界鼠标坐标并立即更新一次 StrawHeadPivot；
#    `_process()` 仍每个显示帧再次直接调用 get_global_mouse_position() 采样，形成事件 + 渲染帧双保险。
#    不修改 Game 的公共物理帧输入同步，也不全局关闭 Input.use_accumulated_input，避免给其它角色/输入系统引入副作用。
# 5. 本轮只改变吸管头视觉跟踪；用户 V294/V295 当前场景的 StrawRig position/scale/skew、Polygon2D 区域、Pivot/Marker 位置、
#    左右镜像、水滴真实 StrawMuzzle 出生点全部保留。攻击伤害、重力、水滴抛物线、速度线 Z 层与多人 authority 规则不变。
# 6. 本轮修改：res://scripts/characters/meme/菊花茶.gd、res://scenes/characters/meme/菊花茶.tscn，
#    并同步更新 res://global/注释.gd 与 PROJECT_PATH_MAP_FOR_AI_V34.md；不生成图片、不改图片、不移动/重命名资源。


# === V297 菊花茶重力持续伤害 / 吸管单侧 180° 攻击限制（2026-09-02） ===
# 1. 菊花茶周期重力在 active 阶段新增持续伤害。默认 gravity_damage_tick_interval=0.25s、
#    gravity_damage_multiplier=0.10；每个 tick 使用 attack_damage(multiplier) 从角色当前 Damage 动态派生，
#    严格继承 V107 攻击力统一语义，攻击力 Buff/Debuff 会同步改变重力持续伤害，不新增绝对 damage 常量。
# 2. 重力持续伤害只由 multiplayer authority 现有 _update_gravity_cycle() 路径结算；扫描 Ball 组中的合法
#    is_combat_targetable() 角色，排除自己/死亡目标，并尊重 Game.Game_Settings.Have_Team_Damage 与
#    Ignore_Team_Damage_Setting。伤害通过 receive_spatial_damage(...,{source=self,shape="all"}) 进入公共伤害链。
# 3. 重力本身原有 register_directional_gravity 全图方向力、持续时间、周期、音频、震动和速度线保持不变；
#    本轮只是让“正在承受该全局重力效果的战斗角色”同时承受周期性角色伤害，不把投射物当作 DOT 生命目标。
# 4. 菊花茶水滴攻击新增“吸管所在侧 180° 半平面”硬规则。攻击侧不从人物 flip 标志猜，而优先读取
#    StrawHeadPivot（兜底 StrawRig）的实际世界 X：吸管在人物左侧 => 仅允许目标/鼠标位于左半平面；
#    吸管在右侧 => 仅允许右半平面；正上/正下处于 180° 边界，允许攻击。
# 5. 角色左右反转时 V294 已会把整套 StrawRig 的 position.x 一起镜像，所以本轮半平面自动随吸管换边。
#    玩家把鼠标放到禁区一侧时不生成水滴；AI 的公共 Nearest_Enemy 若在禁区，则额外扫描 Ball 组，
#    自动选择吸管半平面内最近的合法敌人，不会隔着角色向吸管背面射击。
# 6. 最终 _resolve_attack_direction() 再做一次 dot>=0 半平面校验，防止缓存目标、远端同步瞄准或旧逻辑绕过限制。
#    本机玩家实际发射方向与 V296 实时吸管视觉共用当前 get_global_mouse_position()/缓存实时鼠标点，
#    不再为了本轮 180° 限制退回物理帧旧鼠标位置。
# 7. V296 的吸管实时跟踪、180° 弯头可转范围、用户手调 Polygon/Pivot/Marker、左右镜像、真实 StrawMuzzle
#    出生点，以及 V295 的速度线 Z 层修复全部累计保留；本轮不生成图片、不移动或重命名资源。

# === V298 菊花茶吸管渐进弯曲 / 水滴严格沿真实管口初速度（2026-09-02） ===
# 1. 用户指出 V297 的 StrawHead 仍是整块刚体旋转，不符合“根部不动、越靠近管头旋转越大”的软管表现。
#    V298 不再写 StrawHeadPivot.rotation。StrawHeadPivot 保持用户场景 authored Transform2D，作为固定根部/弯曲参考点。
# 2. 进入场景时读取并保存用户当前 StrawHead.polygon/uv、StrawHead.position、StrawMouthInner.position、
#    StrawMuzzle.position。运行时只基于这些 authored 值做视觉变形，不改用户场景里手调的基础区域/位置。
# 3. StrawHead 多边形边界运行时做默认 4 段细分，再按“点到 Pivot 根部的距离”计算旋转权重：
#    straw_bend_root_hold_ratio 默认 0.24，根部约前 24% 半径完全不动；之后 smoothstep + exponent 逐步增加，
#    到 StrawMuzzle 参考半径附近权重为 1，因此越靠近管头旋转越大，不再整块一起甩。
# 4. StrawMouthInner 与 StrawMuzzle 也使用同一距离权重弯曲。由于两个 Marker 权重不同，V298 用少量 Newton 数值迭代
#    反解总 bend，使弯曲后的真实 Inner -> Muzzle 出口向量与当前目标方向精确一致；左右镜像、scale、skew 仍通过
#    固定 Pivot 的 global_transform.affine_inverse() 正确换算。
# 5. 水滴发射前强制刷新一次当前渐进弯曲，随后 launch_direction 直接读取弯曲后
#    StrawMouthInner.global_position -> StrawMuzzle.global_position 的真实世界向量；出生点仍是 StrawMuzzle.global_position。
# 6. res://scripts/shooter/菊花茶水滴.gd 的 configure_parabolic_launch() 新增尾部兼容参数 exact_initial_direction=false。
#    菊花茶调用时传 true：仍保留旧抛物线算法算出的速度大小和后续重力下坠，但真实初速度方向强制使用管口方向。
#    因此“管头指向”和“子弹离开管口的瞬间方向”完全一致；后续轨迹仍可被 projectile_gravity 与全局重力弯折。
# 7. V297 的重力持续伤害、吸管所在侧 180° 攻击限制，V295 的速度线 Z 层修复，以及用户当前 StrawRig/Polygon/Pivot/Marker
#    场景构图全部累计保留。本轮不生成图片、不改图片、不移动/重命名资源。

# === V299 菊花茶管口首帧严格出膛 / 管口后恢复随机小散射（2026-09-02） ===
# 1. 用户实机确认 V298 仍然出现“水滴看起来没有沿真实管口方向射出”，并且原来的随机小散射消失。
#    重新检查实际调用链后定位到两个独立原因：V298 虽把 ballistic_velocity 初值强制设成管口向量，
#    但 菊花茶水滴.gd::tick_physics() 在调用 ball.tick_physics() 真正移动之前就先把 projectile_gravity 加进 velocity；
#    同时 ball.tick_physics() 还会在 move() 之前叠加场景 directional gravity。于是“第一段真实位移”已经被重力改角。
# 2. V299 把顺序改成：configure 时仍严格使用 StrawMouthInner -> StrawMuzzle 世界向量作为 ballistic_velocity 方向；
#    第一物理帧先按该方向完成真实 move_and_slide() 位移，第一帧期间临时跳过公共 directional gravity；
#    第一段位移完成后，才开始加入 projectile_gravity，并从第二帧起恢复公共场景重力。
#    因而只看水滴真正离开 StrawMuzzle 的第一小段轨迹，其方向与当时真实管口中心线严格一致。
# 3. 随机小散射恢复，但不再在出生瞬间直接旋转发射向量。新增 projectile_post_muzzle_scatter_deg，默认 3°；
#    每次攻击由 authority 用 randf_range(-3°, +3°) 产生一次随机偏角，传给水滴。水滴先沿管口走完第一物理帧，
#    然后一次性把 ballistic_velocity 旋转这个小角度，再继续受自身重力/全局重力影响。
#    这样可以同时满足“真正出膛方向沿管头”和“离开管口后有随机小散射”，而不是二者互相覆盖。
# 4. V298 的 target/arc 算法仍只用于决定速度大小与远距离弧线尺度；exact_initial_direction=true 时不会重新决定方向。
#    projectile_arc_time_variation 继续保留，因此不同水滴除 3° 后置散射外，速度/弧高仍可有原有随机差异。
# 5. 水滴出生点仍严格使用用户手调 StrawMuzzle.global_position；projectile_spawn_horizontal_jitter/vertical_jitter 继续为 0，
#    不通过随机出生坐标伪造散射，避免出现“水滴不是从吸管口出来”的视觉错误。
# 6. V297 的单侧 180° 攻击限制与重力持续伤害、V298 的渐进弯曲、V295 的速度线 Z 层修复均累计保留。
#    本轮不生成图片、不移动/重命名资源，也不重置用户手调 StrawRig/Polygon/Pivot/Marker。


# === V300 菊花茶管头摆幅增强 / 可见直线出膛段（2026-09-02） ===
# 1. 用户实机继续反馈 V299 两点：视觉管头摆幅仍偏小；水滴虽然首个 physics frame 的请求速度沿管口，
#    但肉眼仍看不出“完全从管口方向射出”。V300 不再把“精确出膛”只定义为一个物理帧，而改成可见世界距离。
# 2. 吸管渐进弯曲权重从“点到 Pivot 的圆形半径”改为“点在 Pivot -> authored StrawMuzzle 主轴上的投影进度”。
#    圆形半径会让弯管侧边/回折区域在离 Pivot 很远时过早获得高权重；主轴投影能更稳定地满足：根部不动，越靠近管头旋转越大。
# 3. 当前默认 straw_bend_root_hold_ratio 从 0.24 调为 0.18，straw_bend_curve_exponent 从 1.25 调为 2.0：
#    前段仍有明确固定区，中段更克制，接近管口后旋转增长更快，视觉上不再像整段只有一点点变化。
# 4. 新增 straw_aim_rotation_gain，默认 1.35。目标角不再直接映射成 1:1 管口转角，而是以 authored 基础管口方向为中心，
#    将相对目标角放大 1.35 倍后再交给数值反解。该增益只增强管头摆幅；固定根部 Pivot/长直管不随之旋转。
# 5. 子弹仍不读取鼠标/敌人方向作为最终发射方向。开火前先完成当前吸管变形，然后唯一 launch_direction 继续读取
#    真实 StrawMouthInner.global_position -> StrawMuzzle.global_position 世界向量，所以“视觉管头最终指向”和“真实弹丸中心线”仍是同一份数据。
#    角度增益若把最终管口推到人物背面半平面，发射会被拒绝，继续遵守 V297“吸管侧 180°”硬规则。
# 6. 新增 projectile_muzzle_straight_distance，默认 40px。水滴出生后不再只保证第 1 个 physics frame 沿管口；
#    而是在实际移动累计至少 40 世界像素前，每帧都重新强制 direction/ballistic_velocity 为出生时真实管口方向，
#    同时临时跳过公共 directional gravity、自己的 projectile_gravity 与随机散射。真实碰撞仍可正常阻止水滴，不做穿墙。
# 7. 40px 直线段完成后的下一阶段才一次性应用原 ±3° 随机小散射，之后恢复水滴自身重力与世界定向重力。
#    因此近枪口的可见轨迹会明确沿管头，离开管口后仍保留用户要求的小随机散射和弧线/重力玩法。
# 8. V297 的单侧 180° 攻击限制与重力持续伤害、V295 的速度线 Z 层修复、用户手调 StrawRig/Polygon/Pivot/Marker
#    以及左右镜像全部累计保留。本轮不生成/修改图片，不移动/重命名资源。

# === V301 菊花茶吸管头消失修复 / GPU 渐进弯曲（2026-09-02） ===
# 1. 用户实机确认 V300 在较多瞄准角度下 StrawHead 会整块消失。V298~V300 的实现会每帧重建并写回
#    Polygon2D.polygon，同时对 authored 轮廓做渐进旋转；大角度时轮廓可能自交/折返，导致 Godot 的 Polygon2D
#    三角剖分失效，最终表现就是吸管头偶发整块不可见。
# 2. V301 完全停止运行时修改 StrawHead.polygon/uv。用户在 .tscn 里手调的 8 点 Polygon 和 UV 永久保持原值，
#    不再做 CPU 边界细分、不再逐帧重排顶点，因此不会因为动态轮廓变成无效 polygon 而让整个头消失。
# 3. 新增 res://shaders/菊花茶吸管弯曲.gdshader。渐进弯曲搬到 CanvasItem vertex shader：VERTEX 仍使用
#    StrawHead 的原始静态三角网格，只在 GPU 顶点阶段根据“固定根部 -> 管口主轴”进度修改显示位置。
#    root_hold_ratio 内权重为 0；越靠近管头权重越高，继续保持“根部不动、越靠近管头旋转越大”的方向。
# 4. 每个菊花茶实例运行时创建独立 ShaderMaterial，避免多只菊花茶共享一个材质参数导致互相覆盖瞄准角度。
# 5. StrawMouthInner / StrawMuzzle 仍使用与 shader 同一套 authored 根部/主轴/权重数学在 CPU 更新 Marker；
#    真实出生点与出膛方向逻辑仍读取两个 Marker 的世界位置，不恢复到鼠标方向或固定方向。
# 6. V300 的 40px 直线出膛段、±3° 后置小散射、V297 重力 DOT/单侧 180° 攻击、左右镜像与速度线修复全部保留。
#    本轮不生成/修改图片，不重置用户手调 StrawRig/Polygon/Pivot/Marker。

# === V302 菊花茶回归 V297 水滴 / 旋转轴对齐真实起射角（2026-09-02） ===
# 1. 用户明确要求：撤销 V298~V301 对“子弹必须先沿管口直线飞、后置 ±3° 散射、渐进弯曲/Shader”的方向。
#    水滴本体恢复 V297 的原始发射方式：res://scripts/shooter/菊花茶水滴.gd 恢复 V297/原项目版本，
#    configure_parabolic_launch() 回到原 11 参数；没有 exact_initial_direction、没有 40px 直线出膛段、没有后置 ±3° 散射。
# 2. V297 原随机感完整恢复：每发仍由 projectile_arc_time_center / projectile_arc_time_variation 随机 arc_time_scale，
#    再由原 V284/V297 抛物线公式计算 vx/vy；水滴随后按原 tick_physics() 逐帧叠加 projectile_gravity，
#    并继续让公共 ball.tick_physics() 叠加场景 directional gravity。子弹运动算法不再为了吸管视觉被强行改写。
# 3. “沿管口”的实现方向反过来：不是让子弹迎合管头，而是先算出这一发 V297 真正的 ballistic_velocity，
#    再让 StrawHeadPivot 旋转到该初速度方向。StrawHead、StrawMouthInner、StrawMuzzle 都是 Pivot 子节点，
#    因此整个可旋转弯头与真实枪口 Marker 一起刚体转过去；StrawStem 长直管仍保持用户 authored Transform 不转。
# 4. Pivot 转动会轻微改变 StrawMuzzle.world_position，而 V297 抛物线又使用 start 位置计算 vx/vy。
#    开火时做最多 20 次很小的固定点迭代：当前枪口 -> V297 初速度角 -> Pivot 对齐 -> 新枪口 -> 再算，
#    直到“当前真实 StrawMouthInner->StrawMuzzle 世界方向”和“用当前真实枪口位置计算的 V297 初速度方向”收敛。
#    随后仍把同一个最终 start / target / arc_time_scale 交给原 V297 configure_parabolic_launch()。
# 5. 实时视觉也不再把管头直接指向鼠标/敌人直线。每个渲染帧使用 V297 原公式、以 arc_time_center 作为稳定预览弧度，
#    计算当前预计起射角并旋转 StrawHeadPivot；真正开火时再使用该发随机 arc_time_scale 做精确对齐。
# 6. V298~V301 的渐进 bend、CPU Polygon 重排和 V301 菊花茶吸管弯曲.gdshader 均不再被运行时代码引用。
#    Shader 文件可作为累计更新历史兼容资源留在完整包中，但 V302 场景/脚本不会加载或使用它。
# 7. V297 的吸管侧 180° 攻击限制、重力持续伤害，V294 左右镜像/用户手调场景构图，以及 V295 地图边界速度线 Z 层修复继续保留。
#    本轮不生成/修改图片，不改用户手调 StrawRig/StrawStem/StrawHead/Pivot/Marker 的 authored 位置和 Polygon/UV。

# === V303 菊花茶重力速度线密度提高（2026-09-02） ===
# 1. 用户实机反馈当前速度线数量偏少，尤其人物身上的线不够明显。本轮只提高“条数密度”，不改变 V288 已经收敛的
#    人物线长度/宽度上限，也不改变 V295 的 Z=97 层级，因此人物线仍然短小，地图外背景也不会重新盖住速度线。
# 2. 地图边界纯黑速度线由 18~34 条提高为 28~48 条；仍只从当前真实地图矩形边界长出，不恢复地图内部随机线。
# 3. 人物/战斗主体（Ball）从原 2~5 条提高为 8~14 条，并把尺寸达到高密度的参考尺度从 150px 收紧到 120px，
#    普通尺寸人物也能明显看到更多附着在身体像素上的速度线。
# 4. BattleTransient 投射物/临时主体只适度提高为 3~7 条，避免为了人物观感把场上所有小投射物也提升到人物同等密度。
# 5. 每条人物线仍从 Sprite2D 的真实不透明像素采样并保存局部锚点，颜色仍取对应像素；主体移动/翻转/旋转/缩放后线继续跟随。
# 6. V302 的 V297 水滴发射方式、旋转轴对齐起射角、V297 重力持续伤害/单侧 180° 攻击、V295 速度线遮挡修复全部保留。
#    本轮不生成/修改图片，不修改菊花茶场景构图，不移动/重命名任何资源。

# === V304 野生狗奶生命/时间加速伤害频率/回血/低血量衰老与基础速度削弱（2026-09-02） ===
# 1. res://scenes/characters/meme/野生狗奶.tscn 的 Max_health 从 760 调整为 400；Damage=34、Speed=88、
#    无普通攻击/无主动技能、时间加速无敌窗口等既有设定不改。
# 2. 时间加速期间的衰老/低额 raw health damage 仍共用同一 pulse，但默认频率明显提高：
#    aging_pulse_interval_start 从 0.72s 调为 0.48s，aging_pulse_interval_end 从 0.18s 调为 0.09s。
#    因此加速越深入，伤害与衰老结算都会更密；每次低额伤害仍使用 attack_damage(aging_damage_multiplier)，
#    不改 V107 Damage 统一攻击力语义。
# 3. 野生狗奶在自己的时间加速 active 阶段新增持续回血：默认每“自身补偿后的真实阶段秒”恢复 Max_health 的 2.5%/s。
#    因 health 为整数，脚本用浮点 accumulator 累计不足 1 点的回血，达到整数后再调用 ball.heal()，避免高帧率下小数被截断。
#    满血时清空 accumulator；加速开始/结束/强制停止时也清零，不把上一轮余量带到下一轮。
# 4. 敌人当前血量百分比越低，单次衰老增长越快。基础 aging_gain 仍随加速阶段从 2% -> 4%；在此基础上再按
#    missing_health_ratio 乘 1.0x -> aging_low_health_max_multiplier（默认 2.0x）。默认线性曲线：满血 1.0x、
#    半血约 1.5x、25% 血约 1.75x、濒死接近 2.0x。参数 aging_low_health_curve_power 可调曲线。
# 5. “衰老削弱速度”改为真正削弱目标的基础速度 default_properties["Speed"]，而不是只挂一个永久 Speed Buff。
#    第一次衰老时把未衰老基础速度存入 wild_dog_milk_age_base_speed meta；之后按衰老百分比从 100% 降到最低
#    aging_min_stat_multiplier（默认 32%）直接写回基础 Speed。当前帧 Speed 按“新基础/旧基础”比例同步缩放，
#    以保留同帧其它 Speed Buff/Debuff 已经结算出的倍率，避免把其它角色机制覆盖掉。
# 6. Damage、Attack_Cooling、Skill_Cooling 的衰老仍继续通过既有永久 cover Buff 实现；仅 Speed 改为基础属性路径，
#    并清除旧名“野生狗奶_衰老_速度”Buff 以避免基础速度与 Speed Buff 双重扣速。
# 7. 不坏煎饼的“完全刷新”原本就会把 default_properties 从开局快照恢复并删除 wild_dog_milk_age_percent，
#    因此仍能恢复被衰老压低的基础 Speed；下一次从 0% 衰老开始时会重新记录当时的基础 Speed。
# 8. V303 菊花茶速度线密度、V302 菊花茶水滴/吸管，以及野生狗奶 V269~V280 的时间无敌、老死判定等累计规则全部保留。

# === V305 野生狗奶衰老骷髅显现 / 80%颤抖 / 100%老死（2026-09-02） ===
# 1. 用户提供新视觉 `头(1).png`，按原文件名放入既有角色图片目录：
#    `res://Images/characters/meme/野生狗奶/头(1).png`。不生成替代图片、不创建同义 Images/images 目录。
# 2. 新增 `res://scripts/effects/野生狗奶衰老骷髅.gd`。每个被野生狗奶衰老的敌人只维持一个运行时骷髅视觉节点，
#    节点以 top_level 世界坐标直接跟随目标 `global_position`，不继承目标角色图片的翻转/缩放/旋转，避免不同人物尺寸把骷髅拉伸。
# 3. 骷髅透明度与衰老进度线性对应：0% 衰老时不可见，衰老越高越明显；默认世界显示尺寸约 96px。
#    野生狗奶脚本新增可调参数 `aging_skull_world_size`，只影响视觉，不影响衰老数值与真实伤害。
# 4. 当骷髅实际 opacity 达到 0.80 时开始颤抖；80%~100% 间颤抖位移/旋转逐步增强。
#    默认最大世界位移约 5px、最大轻微旋转约 3°，使用 `Time.get_ticks_msec()` 驱动，因此即使全局时间被野生狗奶减慢，临终颤抖仍保持可见节奏。
# 5. 衰老达到 100% 时，骷髅先立即隐藏/释放，然后目标通过既有 OLD_AGE_DEATH_* 标记和 raw health damage 入口执行“老死”。
#    为保证“100% 才衰老死亡”的语义，V304 之前每个衰老 pulse 的低额时间伤害改为非致死：100% 前最多把目标压到 1 HP，
#    不再允许低额 pulse 在骷髅完整显现前抢先造成普通伤害死亡。达到 100% 后仍一次性处决剩余生命。
# 6. 敌人血量越低衰老越快、基础 Speed 随衰老下降、时间加速 pulse 频率、野生狗奶自身加速回血、400 Max_health 等 V304 规则全部保留。
# 7. 多人模式下由 authority 广播目标 NodePath + 衰老百分比：普通进度使用 unreliable RPC 更新透明度；100% 清除使用 reliable RPC，
#    确保所有客户端都在老死时移除骷髅。视觉节点只跟随目标，不参与 Hitbox/Hurtbox、索敌、碰撞或伤害。

# -----------------------------------------------------------------------------
# V306 野生狗奶：衰老节奏放慢 / 骷髅缩小并置于人物之上
# -----------------------------------------------------------------------------
# 1) V305 的 aging_gain_percent_start/end 原本是“每次 pulse 增加 2%~4%”。
#    由于 V304 又把 pulse 间隔提高到 0.48s -> 0.09s，后段每秒可触发约 11 次，
#    导致衰老速度随着伤害频率一起爆炸。V306 将这两个参数统一解释为“每秒衰老百分比”。
# 2) 每次 pulse 实际增加量 = 当前每秒衰老率 * 当前 pulse_interval，再乘低血量加速倍率。
#    因此加速后段仍维持高频持续伤害，但衰老累计不再因为 pulse 变密而成倍加速。
#    默认仍是 2%/s -> 4%/s，敌人缺血时继续按 V304 规则最高加速到 2x。
# 3) 这意味着满血敌人在一次 10 秒时间加速中通常只累计约数十%的衰老；
#    低血量敌人会更快，但不再轻易一轮直接 100%。
# 4) 衰老骷髅默认世界尺寸从 96px 降到 48px，保持“提示”而不是盖住人物本体。
# 5) 骷髅使用 top_level + z_as_relative=false，绝对 z_index 改为 96：
#    高于普通人物本体与地图外遮罩(90)，低于菊花茶速度线(97)、血条(99)、地图边框(100)，
#    因此视觉明确覆盖在人物上方，但不会盖住主要 HUD/边界。
# 6) V305 的 80% opacity 开始颤抖、100% 骷髅消失后衰老死亡、100% 前低额伤害非致死继续保留。
# 7) V304 的 400 HP、时间加速回血、高频伤害 pulse、低血量加速衰老、基础 Speed 衰减继续保留。

# -----------------------------------------------------------------------------
# V307 野生狗奶：400血量运行时强制 / 小骷髅 / 95%颤抖 / 残血强加速衰老
# -----------------------------------------------------------------------------
# 1) Max_health 继续明确为 400。除 scenes/characters/meme/野生狗奶.tscn 保存 Max_health=400 外，
#    scripts/characters/meme/野生狗奶.gd 新增 WILD_DOG_MILK_MAX_HEALTH=400 并在 _ready() 运行时再次纠正。
#    这是为了防止旧场景实例/旧 Inspector 保存值 760 继续覆盖脚本预期；纠正时临时 suppress_floating_text，
#    不把出生时的上限纠正显示成受伤跳字，并同步 default_properties["Max_health"]=400。
# 2) 衰老仍与高频伤害 pulse 解耦，aging_gain_percent_start/end 继续表示“每秒基础衰老率”，
#    但基础值从 V306 的 2%/s -> 4%/s 降为 0.45%/s -> 0.90%/s：满血敌人的基础衰老非常慢。
# 3) 敌人血量百分比越低，衰老倍率改为强非线性：
#    missing_health_ratio ^ 2.40 再在 1x -> 18x 之间插值。
#    默认约：100%血=1.0x，75%血=1.61x，50%血=4.22x，25%血=9.52x，10%血=14.20x，濒死接近18x。
#    因此“基础慢、残血突然老得很快”；低额时间伤害仍会逐步压低敌人血量并自然触发这一加速。
# 4) 骷髅头默认世界尺寸从 48px 进一步降到 28px；仍使用 top_level、z_as_relative=false、绝对 z_index=96，
#    保持明确位于人物本体之上，同时不覆盖 z=97 速度线、z=99 血条、z=100 地图边框。
# 5) 骷髅颤抖阈值从 opacity 0.80 改为 0.95。0%~94.99% 仅随衰老逐渐显现，不抖；
#    95%~100% 才进入临终颤抖，100% 仍先隐藏/释放骷髅，再按 OLD_AGE_DEATH_* 路径让敌人衰老死亡。
# 6) V304 的时间加速期间自我回血、高频伤害 pulse、衰老削弱基础 Speed，V305 的100%前时间伤害非致死，
#    以及后续菊花茶累计规则全部继续保留。



# -----------------------------------------------------------------------------
# V308 野生狗奶：残血衰老倍率继续提高 / 时间加速持续时间小幅延长
# -----------------------------------------------------------------------------
# 1) 用户反馈 V307 衰老仍偏慢。本轮不提高满血时的基础衰老率：
#    aging_gain_percent_start/end 继续保持 0.45%/s -> 0.90%/s，基础仍然很慢。
# 2) 只继续提高“敌人血量百分比降低后的衰老倍率”：
#    aging_low_health_max_multiplier 从 18x 提高到 32x；curve_power 继续保持 2.40。
#    约为：100%血=1.0x、75%血=2.11x、50%血=6.87x、25%血=16.54x、10%血=25.07x、濒死=32x。
#    因此高血目标仍慢，但进入半血后衰老会明显加速，残血阶段会非常快。
# 3) time_acceleration_duration 从 10.0s 小幅延长到 12.0s。阶段 progress/curved、世界减速、
#    自身回血、高频时间伤害与衰老 pulse 都自然使用新的 12 秒时长；冷却仍保持 15 秒不变。
# 4) scenes/characters/meme/野生狗奶.tscn 同步显式保存 duration=12.0 与 low_health_max_multiplier=32.0，
#    避免旧 Inspector/场景覆盖脚本默认值。
# 5) V307 的 400 Max_health 双保险、28px 小骷髅、95% 才开始颤抖、100% 衰老死亡，
#    V304 的加速回血/高频伤害/基础 Speed 衰退，以及 V305 的100%前时间伤害非致死全部保留。

# -----------------------------------------------------------------------------
# V309 野生狗奶老死残骸 MultiplayerSpawner 保留名称报错修复
# -----------------------------------------------------------------------------
# 1) 用户实机截图确认红色运行时报错来自 global/game.gd::_rpc_spawn_wild_dog_old_age_remains()：
#    `Unable to auto-spawn node with reserved name: @StaticBody2D@...`。根因不是菊花茶场景，而是老死残骸。
# 2) world.tscn 的 MultiplayerSpawner.spawn_path=".." 指向 World；world.gd 又把 res://scenes/ 下的 tscn
#    全部注册为 spawnable scene。因此“野生狗奶老死残骸.tscn”若直接 scene_root.add_child()，会进入
#    MultiplayerSpawner 的直接子节点自动出生路径。
# 3) 该残骸本身已经通过 Game 的 authority/call_local/reliable RPC，把 origin、seed、size_multiplier
#    发送到各 peer 后手动实例化；若继续放在 World 根，又会同时触发 MultiplayerSpawner 自动复制，属于重复同步路径。
# 4) V309 新增运行时二级容器 `World/野生狗奶老死残骸容器`。RPC 在每个 peer 确保该容器存在，
#    所有残骸改为该容器的子节点。MultiplayerSpawner 只复制 spawn_path 的“直接子节点”，因此残骸不再二次触发自动 Spawn。
# 5) 容器与残骸的 add_child() 均显式使用 force_readable_name=true；即使同时存在多个同名残骸，
#    Godot 也生成普通可读唯一名称，不再生成 `@StaticBody2D@xxxx` 这类保留自动名。
# 6) 残骸的 configure(seed,size)、global_position、StaticBody2D 实体碰撞、散架逻辑与 V281~V308 玩法均不改。
#    本轮只修生成父节点/命名与 MultiplayerSpawner 重复路径；截图中的 ignore_block shadowing / narrowing conversion 为黄色警告，
#    与本次红色 Runtime Error 不同，本轮不顺带改动公共 ball 参数语义。

# -----------------------------------------------------------------------------
# V310 野生狗奶基础衰老小幅提速 / 拳击手突进距离加长
# -----------------------------------------------------------------------------
# 1) 野生狗奶的“基础衰老”在 V308/V309 基础上小幅提高：
#    aging_gain_percent_start 从 0.45%/s -> 0.60%/s，aging_gain_percent_end 从 0.90%/s -> 1.20%/s。
#    这两个值仍表示“每秒基础衰老率”，每次 pulse 继续乘当前 pulse_interval，因此不会重新与高频伤害结算次数绑定。
# 2) 敌人低血量的强非线性加速保持 V308 的 aging_low_health_max_multiplier=32x、curve_power=2.40 不变。
#    因此只是把高血量阶段的基础积累稍微加快；半血以下仍由低血量倍率主导，不改“血越少衰老越快”的核心曲线。
# 3) res://scenes/characters/meme/野生狗奶.tscn 同步显式保存 aging_gain_percent_start=0.60、end=1.20，
#    避免旧 Inspector/场景保存值覆盖脚本默认。
# 4) 拳击手突进最大尝试距离 dash_distance 从 260 -> 360 世界像素；dash_speed 仍为 920，不改变冲刺速度本身。
# 5) AI 的冲刺触发最远距离 dash_trigger_max_distance 从 80 -> 120；最短距离仍为 55。
#    仅增加 dash_distance 而不放宽 AI 触发距离时，AI 通常会在离敌人 55~80px 时才发动，并在撞到敌人后立刻停止，
#    实际可见突进不会明显变长。因此同步把触发带放宽到 55~120，使 AI 也能真正从更远处突进。
# 6) 冲刺依旧通过公共 CharacterBody2D 移动/碰撞路径执行，撞到墙或实体仍停止，不穿墙、不穿人；拳击伤害、Combo、冷却不改。
# 7) V309 老死残骸 MultiplayerSpawner 修复、V308 12秒时间加速/32x 残血倍率、V307 400HP/28px骷髅/95%颤抖全部保留。

# -----------------------------------------------------------------------------
# V311 新角色：数学老师 / 领导（公式弹道、掉落经济、说教控制）
# -----------------------------------------------------------------------------
# 1) 新增可选角色 `res://scenes/characters/人物/数学老师.tscn` 与
#    `res://scripts/characters/数学老师.gd`。不创建新的角色分类目录，继续使用既有 `人物/`。
#    默认 Max_health=650、Damage=28、Speed=96、Skill_Cooling=2.7；无普通攻击，核心行为在 Skill。
# 2) 数学老师发动技能时，在人物下方显示一个 top_level Label，并通过 Label.visible_characters 逐字揭示。
#    算式由 authority 一次性随机并同步，包含 1~3 个数字；示例包括 `1=1`、`1+1=2`、`3*1+1=4`，
#    也会生成加法/乘法/三项混合式。公式完全出现并短暂停留后才发射公式弹。
# 3) 新增 `res://scenes/shooter/数学老师公式弹.tscn` / `res://scripts/shooter/数学老师公式弹.gd`。
#    公式弹沿另一条数学曲线运动，随机使用抛物线 `A*4p(1-p)`、`A*sin(pi*p)` 或 `A*sin(2*pi*p)`；
#    曲线幅度/跨度由 authority 随机并随 spawn config 同步。真实移动每 physics tick 沿曲线取新位置。
# 4) 数学公式弹对人物可穿透：同一目标最多命中一次，命中后继续飞；墙体/地图实体按项目既有 Layer1
#    做连续 raycast，第一次撞到障碍物即消失。伤害来自数学老师 `attack_damage(projectile_damage_multiplier)`，
#    并继续尊重 `effective_outgoing_damage()`、Team / Have_Team_Damage 和 `is_combat_targetable()`。
# 5) 新增可选角色 `res://scenes/characters/人物/领导.tscn` 与 `res://scripts/characters/领导.gd`。
#    默认 Max_health=1800、Damage=24、Speed=78、Attack_Cooling=1.25，定位为高血量射手/控制/掉落/召唤角色。
#    本轮用户没有提供正式角色图片，因此数学老师和领导，以及其新投射物/掉落/房产业主，均只使用程序化占位视觉；
#    不生成图片，不猜测 Images 路径。后续收到正式素材时再按现有目录规则替换视觉，不改玩法路径。
# 6) 领导普通攻击默认 80% 发射 `领导处分文件`，20% 发射 `领导小领导`。
#    - 处分文件：`res://scenes/shooter/领导处分文件.tscn`，默认 340px/s 中速；每一发 damage multiplier 在
#      0.55x~4.50x 大范围随机，最终仍先走 `attack_damage(multiplier)`；命中第一个合法敌人或 Layer1 障碍后消失。
#    - 小领导：`res://scenes/shooter/领导小领导.tscn`，不查询 Layer1 障碍，直线穿过墙体；碰到合法敌人后
#      `apply_stun(1.45s)` 作为“说教控制”，显示短暂说教文字并消失；飞出当前地图矩形或达到安全寿命后消失。
# 7) 领导每次真正损失 health 后由 `on_actual_health_damage_received()` 触发掉落判定；默认 24% 几率、0.18s
#    最小间隔，避免同一高频伤害事件刷出大量掉落。掉落权重默认：金币 58%、车钥匙 24%、房产证 18%。
# 8) 新增 `res://scenes/effects/领导掉落物.tscn` / `res://scripts/effects/领导掉落物.gd`。掉落物使用
#    `4*A*t*(1-t)` 的视觉抛物线，从领导位置先升高再落到地图内随机地面点，落地后才允许拾取。
#    - 领导本人/同 Team 队友拾取：直接给拾取者回血；默认金币35、车钥匙90、房产证145。
#    - 敌人拾金币/车钥匙：物品转为飞回领导的 hostile return，抵达时伤害领导；默认金币18、车钥匙68，
#      保持“金币伤害少、车钥匙伤害多”。该反伤过程设置 suppress 标记，不会再次触发领导掉落形成递归。
#    - 敌人拾房产证：房产证立即消失，并在拾取者位置生成一个 `领导房产业主` 攻击领导。
# 9) 新增 `res://scenes/creatures/领导房产业主.tscn` / `res://scripts/creatures/领导房产业主.gd`。
#    房产业主不是 Ball、不会进入普通索敌；只追击对应领导，近身使用拳头攻击，默认伤害约为领导 Damage 的0.8倍，
#    并施加约8px/105px/s的小幅击退。领导死亡/失效后单位立即进入逃跑状态，向地图外移动并在离开边界后释放；
#    另有5秒逃跑兜底，避免无有效地图矩形时残留。
# 10) V311 新的 shooter/effect/creature 都加入 BattleTransient。多人时只由角色 authority 决定随机、伤害、拾取和控制；
#     spawn config 使用 authority/call_local/reliable RPC 在各端创建相同视觉。手动 RPC 创建的 PackedScene 不直接挂在
#     World 的 MultiplayerSpawner spawn_path 下，而统一放在二级 `World/V311运行时对象/` 容器，继承 V309 的
#     “手动 RPC 与 MultiplayerSpawner 不走两套重复 spawn”规则。处分文件/小领导命中时再由 authority 可靠广播释放节点。
# 11) `translations.csv` 新增数学老师/领导及其新对象的中英键：Math Teacher、Leader、Formula Projectile、
#     Disciplinary Notice、Mini Leader、Leader Drop、Property Owner、Coin、Car Key、Property Deed、Lecture、Formula 等。
# 12) V107 Damage 统一攻击力语义、Have_Team_Damage、多人 authority、V309 二级运行时容器规则，以及 V310 之前所有
#     菊花茶/野生狗奶/拳击手累计修改继续保留。本轮不移动、不重命名任何既有资源。

# -----------------------------------------------------------------------------
# V312 数学老师/领导正式图片接入 / 白色公式轨迹 / 命中音效 / 房产业主同款面包车拳头
# -----------------------------------------------------------------------------
# 1) 用户正式提供数学老师与领导相关图片，本轮不生成新图，保持上传文件名不变并放入既有 `Images/characters/人物/`：
#    数学老师：`老师(2).png`、`老师扔(2).png`、`粉笔(2).png`；
#    领导：`领导本体(2).png`、`领导生气(2).png`、`领导笑(2).png`、`处分 - 副本.png`、`金币(2).png`、
#    `车钥匙 - 副本.png`、`房产证 - 副本.png`。不创建新的同义 Images/images 目录。
# 2) 数学老师本体正式使用 `老师(2).png`；施放公式技能期间切到 `老师扔(2).png`，公式发射后恢复正常图。
#    两张图片都按同一目标世界高度缩放，CharacterAutoFit 仍关闭，V311 已保存的手工碰撞尺寸不被图片切换重新计算。
# 3) 数学公式弹正式改用 `粉笔(2).png`。V311 的随机抛物线/sin/双周期sin运动、可穿透人物、撞 Layer1 障碍消失继续保留。
#    每一发公式弹生成时额外建立一条 top_level 白色 Line2D，按本发真实 curve_span / amplitude / curve_kind 采样 73 个点，
#    把数学公式实际使用的弹道提前标出来；白线与该投射物同寿命，投射物撞墙/超时释放时一起消失。
# 4) 粉笔真正碰到合法人物时播放既有 `res://audio/sfx/physics/balls_hit1.sfxr` 作为位置命中音效；
#    authority 负责真实命中判定，并通过数学老师 RPC 在各客户端的相同世界位置播放 AudioStreamPlayer2D。
# 5) 领导本体正式使用 `领导本体(2).png`。`领导生气(2).png` 与 `领导笑(2).png` 明确只作为“小领导”子弹图片：
#    每一发小领导由 authority 随机 0/1 variant 并通过 spawn config 同步，飞行时保持人物正立，只做轻微摆动；
#    小领导仍无视 Layer1 障碍、命中后说教眩晕、出地图/超时消失。
# 6) 处分文件正式使用 `处分 - 副本.png`；金币、车钥匙、房产证掉落分别使用本轮同名正式图片。
#    V311 的处分随机大伤害、掉落抛物线、友军回血、敌人拾取后回飞/召唤房产业主规则全部保留。
# 7) 领导处分文件命中人物时播放既有 `res://audio/sfx/战斗/子弹打人.mp3`；敌人拾取金币/车钥匙后物品飞回并真正撞到领导时，
#    金币复用 `res://audio/characters/收债人/金币1.mp3`，车钥匙复用 `res://audio/characters/面包车/铁棍打人.mp3`。这些声音均由领导 authority 通过 RPC 在命中世界位置同步播放。
# 8) `领导房产业主` 的拳头改为复用面包车拳头小弟的正式拳头图片 `res://Images/characters/人物/面包车/拳头.png`，
#    使用同样的 12 physics-frame、sin(t*pi)*12.8 伸出再收回节奏，并以约 30.4px 的拳头长度显示。
#    挥拳音效与面包车拳头小弟完全复用 `拳头挥舞.mp3`，真实打到领导时复用 `拳头命中.mp3`；小幅击退仍使用领导原 V311 参数。
# 9) V311 `领导.gd` 末尾曾残留重复的 `_rpc_spawn_property_unit()` 函数声明，本轮在重写正式视觉/音效入口时一并消除该重复声明，
#    保留唯一的 authority/call_local/reliable 房产业主生成 RPC，避免后续 Godot 解析器因重复函数声明报错。
# 10) 新声音没有复制/改名原音频文件，全部复用路径基准已确认存在的项目资源；AudioStreamPlayer2D 优先走 GameplayRecord 总线。
#     V311 公式/处分/掉落/说教/召唤玩法，V310 及之前的菊花茶、野生狗奶、拳击手累计规则继续保留。

# -----------------------------------------------------------------------------
# V313 领导1000HP / 数学公式速度 / 人物放大 / 粉笔缩小 / 小领导命中后愤怒贴身说教
# -----------------------------------------------------------------------------
# 1) 领导 Max_health 从 V312 的 1800 调整为 1000。`scenes/characters/人物/领导.tscn` 显式保存 1000，
#    `领导.gd::_ready()` 也在 super 前固定 Max_health=1000，并在 ready 后把当前 health 限制到新上限，避免旧场景缓存造成高血量残留。
# 2) 数学老师公式弹撤销固定 projectile_speed=430。每发根据本次真实 curve span=L 计算：
#       v = L / (t0 + L / D)
#    默认 t0=0.62、D=520，最后限制在 150~260 px/s。典型 L=150 时约165px/s、L=220时约211px/s、
#    L=360 时受上限限制为260px/s，显著慢于 V312。该速度公式文本也追加显示在公式弹旁，便于直接确认本发速度来源。
# 3) V312 的白色 Line2D 数学轨迹继续使用相同 curve_kind/span/amplitude，速度公式只改变沿 X 前进速度，不改变白线与实际弹道几何一致性。
# 4) 数学老师正式视觉高度从142提高到190；领导正式视觉高度从158提高到215。只放大人物 Sprite，
#    不擅自改 V311 手工 Collision/Hitbox/Hurtbox，避免单纯视觉反馈牵连战斗判定。
# 5) 粉笔正式图片的场景 scale 从0.018降到0.0105，约从28x11px缩到16x6px；真实 projectile_hit_radius 不改，保持玩法判定稳定。
# 6) 小领导子弹飞行阶段固定使用 `领导笑(2).png`；命中合法敌人时 authority 先 apply_stun，随后通过可靠 RPC
#    让所有端同名小领导进入 `begin_lecture()`：停止飞行、切换 `领导生气(2).png`，并持续跟随在该敌人身边直到说教控制结束。
#    这实现“命中时在敌人身边出现愤怒领导”的表现；说教结束后再统一释放，不再命中瞬间直接消失。
# 7) V312 的正式图片、处分/掉落/拳头命中音效、数学白线轨迹，以及 V311 的掉落/召唤/无视障碍小领导基础规则继续保留。

# -----------------------------------------------------------------------------
# V314 领导受伤掉落触发修复 / 处分命中改标准碰撞受伤音 / 小领导始终正立
# -----------------------------------------------------------------------------
# 1) 用户实测领导真实受伤后完全没有金币/车钥匙/房产证掉落。V311~V313 只依赖
#    `领导.gd::on_actual_health_damage_received()` 触发概率；V314 改为在领导 ready 后直接连接公共
#    `Health_Bar.health_changed(last_health, health, max_health, if_tween)`，只要 new<old 就进入领导自己的掉落概率链。
#    `ball.health` setter 对真实生命下降会统一 emit 该信号；block/护盾变化使用独立 block_changed，不会误触发掉落。
# 2) 为避免同一次扣血被 HealthBar 信号和 ball 的角色覆写钩子各滚一次概率：HealthBar 正常存在时只使用信号；
#    只有异常场景缺少 HealthBar 时，才回退到 `on_actual_health_damage_received()`。原 24% hit_drop_chance、0.18s 成功掉落间隔、
#    金币58%/车钥匙24%/房产证18% 权重与抛物线落地规则不变。
# 3) 领导处分文件命中人物的声音从 V312 错接的 `audio/sfx/战斗/子弹打人.mp3` 改为项目标准
#    “碰撞造成真实生命伤害”音 `res://audio/sfx/physics/balls_hit1.sfxr`。仍只有 receive_spatial_damage() 返回真实伤害成功时播放，
#    继续由领导 authority RPC 到所有端并从真实命中世界位置使用 AudioStreamPlayer2D 播放。
# 4) 小领导飞行与说教愤怒状态的图片始终保持人物头朝上，Visual.rotation 固定为0。
#    飞行左右朝向只根据 travel_direction.x 设置 Sprite2D.flip_h；贴在敌人身边说教时，如果位于敌人右侧则 flip_h，
#    让人物朝回目标。禁止再用正负旋转让人物逐渐倒下或越过90°后上下翻倒。
# 5) V313 的领导1000HP、数学公式速度/白线、粉笔尺寸，以及 V312 的正式图片、掉落物图片、房产业主拳头/音效全部保留。

# -----------------------------------------------------------------------------
# V315 领导受伤掉落最终触发修复 / 小领导命中文字移除 / 愤怒图保持原始角度
# -----------------------------------------------------------------------------
# 1) V314 改成监听 Health_Bar.health_changed 后，用户实测领导仍然没有掉落。V315 不再把 UI 信号当玩法触发源：
#    `ball.health` setter 在真实生命下降时本来就会同步调用 `on_actual_health_damage_received(actual_loss,before_health)`，
#    因此领导重新以该公共生命损失钩子作为主触发链。这样掉落逻辑直接依赖真实 health 变化，不依赖血条 UI 是否连接/刷新。
# 2) 额外在领导 tick_physics() 中保存 `_last_drop_observed_health` 做最终兜底。正常 health setter 钩子会立即同步 observed 值，
#    因此不会重复滚概率；只有某个特殊脚本异常绕过钩子、但生命确实下降时，下一物理帧才补一次同一掉落判定。
# 3) 为让“挨打有几率爆东西”在实战中稳定可见，默认单次真实生命损失掉落概率从24%提高到35%，并新增 `hit_drop_pity_hits=3`：
#    连续真实受伤事件若前两次都未成功，第3次在成功掉落间隔允许时必定掉落一次；成功后计数清零。金币58%/车钥匙24%/房产证18%
#    的种类权重、抛物线落地、友军回血、敌人拾取反伤/召唤规则均保持不变。
# 4) 领导自身因敌人拾取金币/车钥匙回飞造成的反伤仍由 `_suppress_drop_trigger` 屏蔽，不能递归触发新的领导掉落。
# 5) 小领导命中敌人后不再创建“好好听领导讲话！”文字。控制/眩晕本身仍按原 lecture_stun 生效，只保留愤怒领导图片贴在目标身边的视觉。
# 6) 命中后的 `领导生气(2).png` 强制使用用户上传图片的正常角度和正常朝向：根/Visual rotation=0、flip_h=false；
#    说教跟随期间也不再因为位于敌人左右侧而镜像。飞行中的笑脸小领导仍可只用 flip_h 表达左右飞行方向，禁止上下翻转。
# 7) V314 的处分文件标准碰撞受伤音、V313 的1000HP/公式速度/尺寸调整、V312 正式图片与房产业主拳头音效全部保留。

# -----------------------------------------------------------------------------
# V316 领导攻击节奏放慢 / 数学老师移动目标命中率提高
# -----------------------------------------------------------------------------
# 1) 用户反馈领导普通攻击频率过快。`scenes/characters/人物/领导.tscn` 的 Attack_Cooling
#    从 1.25s 调整为 2.0s；处分文件/小领导 80%/20% 分支、伤害、速度、掉落和控制机制不改。
# 2) 数学老师公式弹继续保持 V313 的数学速度公式 `v=L/(t0+L/D)` 和 V312 的白色 Line2D 真实轨迹，
#    不改成追踪弹，也不把曲线改回直线。
# 3) AI 数学老师在公式逐字显示完成后重新索敌，并读取目标当前 CharacterBody2D velocity。
#    用当前公式弹速度估算飞行时间，做两次预测迭代；默认 target_lead_strength=0.90、
#    target_lead_max_time=1.10s、target_lead_max_distance=110px。这样公式的“目标落点”提前到移动敌人的未来位置，
#    但发射以后仍完全按既定数学公式飞，不持续追踪敌人。玩家直接控制时仍严格射向玩家瞄准位置，不自动修正鼠标。
# 4) 数学公式弹真实命中半径从 10px 提高到 16px，仍会再叠加目标自身真实 crowd/body 半径；
#    用于减少白线已经擦过人物边缘但因为离散物理步进没有判中的情况。
# 5) projectile_lifetime 从 2.8s 提高到 3.6s，让 V313 降速后的远距离粉笔仍有足够时间走完整段公式轨迹；
#    撞 Layer1 障碍立即消失、穿透人物且同目标一发只命中一次、粉笔命中音效等规则全部保持。
# 6) `scenes/characters/人物/数学老师.tscn` 同步显式保存 lifetime=3.6、hit_radius=16 与三项预测参数，
#    避免旧 Inspector 场景值覆盖脚本默认。V315 领导掉落保底、V314 标准碰撞受伤音、V313 正式尺寸与
#    小领导愤怒图、V312 正式图片/音效等累计规则继续保留。


# -----------------------------------------------------------------------------
# V317 数学老师攻击节奏加快 / 算式答案决定公式弹伤害
# -----------------------------------------------------------------------------
# 1) 用户实测 V316 数学老师整体攻击节奏偏慢。数学老师没有普通 Attack，实际攻速由 Skill_Cooling 与
#    “公式逐字显示 + 完整后停留”共同决定。V317 将 Skill_Cooling 从 2.7s -> 1.75s；
#    formula_character_interval 从 0.075s/字 -> 0.045s/字；formula_hold_after_reveal 从 0.18s -> 0.08s。
#    公式仍必须逐字完整出现后才发射，不删除角色核心演出。
# 2) V311~V316 的算式文字虽然会得到不同答案，但 projectile damage 始终写成
#    attack_damage(projectile_damage_multiplier)，所以默认 Damage=28 时每一发都实际造成 28 基准伤害。
# 3) V317 把算式生成结果改为 {text,result} 同步保留：未受攻击力 Buff/Debuff 时，算式右侧答案就是本发基准伤害；
#    例如 1+1=2 -> 2伤害、3*4=12 -> 12伤害。三项减法生成时保证结果至少为1，避免显示0但又产生非0伤害的不一致。
# 4) 仍严格遵守 V107“特殊攻击统一从 Damage/attack_damage() 读取”的规则：不建立独立绝对攻击力字段。
#    具体做法是以 default_properties["Damage"]（数学老师默认28）为参考，把答案换算为 multiplier 后再调用 attack_damage()。
#    因此默认攻击力下答案=实际伤害；若 Damage 被 Buff/Debuff 改变，答案伤害也按同一比例缩放。
# 5) V313 的公式速度 v=L/(t0+L/D)、V316 AI提前量/16px命中半径/3.6s寿命、V312 白色真实轨迹线与粉笔命中音效全部不改。


# -----------------------------------------------------------------------------
# V318 领导掉落物全程地图内限制 / 小领导命中后严格左右双方向
# -----------------------------------------------------------------------------
# 1) V317 之前领导只在生成 `ground_position` 时把最终落地点 clamp 到地图矩形；抛物线中途仍会向上抬高，
#    因此领导贴近地图上边缘受伤时，金币/车钥匙/房产证的飞行最高点仍可能越出地图背景。
# 2) `res://scripts/effects/领导掉落物.gd` 现在在 configure 时缓存当前 `return_map_world_rect()`，
#    并把 start / ground、每个抛物线物理帧、落地坐标以及敌人拾取后的回飞位置全部限制在地图安全矩形内。
#    MAP_SAFE_MARGIN=22px 按最大 31px 掉落图及 1.22 倍抛物线视觉放大预留，使“整张掉落图”而非仅中心点留在地图内。
# 3) 该限制只改变视觉/位置边界，不改变掉落概率、种类权重、抛物线时长/高度、拾取半径、友方回血、敌方回飞伤害或房产证召唤。
# 4) `res://scripts/shooter/领导小领导.gd` 命中敌人后的愤怒状态现在只有左右两个离散方向：
#    从左向右命中就固定在敌人左侧，从右向左命中就固定在敌人右侧；Y 偏移固定为 0，不再出现斜上/斜下贴点。
# 5) 愤怒图始终 rotation=0 保持人物正立。用户原 `领导生气(2).png` 朝右指：位于敌人左侧时 flip_h=false 朝右，
#    位于敌人右侧时 flip_h=true 朝左；因此只通过水平镜像得到左右两种方向，绝不按 travel_direction.angle() 连续旋转。
# 6) 飞行阶段、说教 stun 时长、无视障碍物、出地图删除、V315 取消命中文字、V316 领导攻速与 V317 数学老师改动全部保留。

# -----------------------------------------------------------------------------
# V319 领导敌方拾取反伤提高 / 掉落物抛物线自转并落地停止
# -----------------------------------------------------------------------------
# 1) 用户要求敌人拾取领导掉落物后，对领导造成的反伤更高。V319 将金币回飞命中领导的基础伤害
#    从 18 -> 36，车钥匙从 68 -> 120；金币仍明显低于车钥匙。房产证仍按原规则召唤房产业主，不改成直接伤害。
# 2) `scenes/characters/人物/领导.tscn` 显式保存 enemy_coin_damage=36、enemy_car_key_damage=120，
#    避免旧 Inspector 场景值覆盖脚本新默认。领导自身反伤仍由 `_suppress_drop_trigger` 屏蔽，不能递归再次爆掉落物。
# 3) 领导每次真实生成金币/车钥匙/房产证时，由 authority 随机一个带正负方向的自转角速度，默认绝对值 7~12 rad/s，
#    并随掉落 config 可靠同步到所有端。同一个掉落物在各端使用完全相同的旋转速度/方向。
# 4) `scripts/effects/领导掉落物.gd` 在抛物线尚未落地时按 `rotation += spin_speed * delta` 连续旋转，
#    不再使用 V318 以前 `sin(...)` 的小幅左右摆动。落地瞬间只停止继续修改 rotation，保留最后落地角度，不强制回正。
# 5) V318 的全程地图安全边界、V315 的35%掉落+3次保底、友军回血、敌方拾取回飞/房产证召唤、
#    V312 正式金币/车钥匙/房产证图片和命中音效全部继续保留。



# -----------------------------------------------------------------------------
# V320 小领导飞行防倒立 / 愤怒说教仅左右 / 掉落物缩小且按图片不透明区域拾取 / 数学发射后公式上浮渐隐
# -----------------------------------------------------------------------------
# 1) `res://scripts/shooter/领导小领导.gd`：飞行阶段恢复按真实 travel_direction.angle() 旋转，
#    但当飞行方向进入左半平面（direction.x<0）时同时启用 Sprite2D.flip_v，避免整个人物因为180°附近旋转上下倒立。
#    飞行阶段不使用 flip_h；垂直翻转只用于修正旋转导致的上下反转。
# 2) 小领导真正碰到敌人后，立刻退出飞行旋转语义：根 rotation=0、Visual.rotation=0、flip_v=false，
#    只根据停在敌人左/右侧使用 flip_h。愤怒领导因此严格只有“朝左/朝右”两张镜像姿态，不允许斜角、倒角或其它旋转角。
# 3) `res://scripts/effects/领导掉落物.gd`：金币/车钥匙/房产证视觉进一步缩小到最大边约12/17/19px；
#    `scenes/effects/领导掉落物.tscn` 的默认金币预览 scale 也同步缩小，避免编辑器/未configure预览仍显示旧大尺寸。
# 4) 掉落物落地拾取不再使用固定 pickup_radius 圆形距离作为主判定。现在先做宽相位距离检查，再把人物中心以及实体半径0.5x/1.0x两圈共24个采样点
#    通过 Sprite2D.to_local() 转到图片局部空间，用 get_rect()+is_pixel_opaque() 检查真实不透明像素。旋转后的金币/钥匙/房产证也按图片当前角度判定，
#    使拾取范围跟随实际图片范围，而不是“图片很小、碰撞圈很大”。图片/纹理异常时才回退旧半径判定。
# 5) V319 的抛出阶段连续自转和落地停止保持；由于视觉缩小，地图安全余量从22px同步收紧为15px，但出生/抛物线/落地/回飞仍全程不得出地图。
# 6) 数学老师公式弹不再把“轨迹公式 + 速度公式”Label绑在粉笔子弹上。白色 Line2D 真实轨迹仍完全保留。
#    发射瞬间由数学老师 authority 可靠RPC生成一条公式文字，出现在数学老师侧边（与发射方向相反的一侧），默认约1.10s内向上漂42px并渐隐后释放。
#    文字内容仍来自该发真实 curve_kind/amplitude/span 和真实速度公式 v=L/(t0+L/D)，不是装饰性的假公式。
# 7) V319领导掉落反伤、V318地图内限制、V317答案决定伤害、V316数学命中辅助、V315领导掉落保底与此前正式图片/音效全部保留。

# -----------------------------------------------------------------------------
# V321 领导掉落物可见性修复
# -----------------------------------------------------------------------------
# 1) 用户实测 V320 将金币/车钥匙/房产证缩到 12/17/19px 后，局内几乎完全看不见。
#    V321 不恢复 V319 的偏大尺寸，而取中间值：金币18px、车钥匙25px、房产证28px（均为图片最大边）。
# 2) 掉落物运行时绝对 z_index 从84提高到92；敌方拾取后回飞阶段从90提高到93。
#    这样掉落图稳定显示在普通人物本体上方，同时仍低于血条/重力速度线等高层提示，不再被人物贴图遮住。
# 3) V320 的按图片真实不透明像素拾取判定完整保留：尺寸变大后，碰撞仍跟随 Sprite2D 当前旋转/缩放后的真实图片范围，
#    不恢复固定大圆碰撞。
# 4) 因最大视觉从19px提高到28px，地图安全边距从15px同步提高到18px；V318 的出生/抛物线/落地/回飞全程不能出地图继续有效。
# 5) V319 的抛出阶段自转并落地停止、V315 的35%掉落+3次保底、友军回血/敌方反伤/房产证召唤等玩法均不改。

# -----------------------------------------------------------------------------
# V322 数学老师发射后双公式定位 / 房产证召唤“愤怒的人”独立角色
# -----------------------------------------------------------------------------
# 1) 数学老师 V320 的发射后公式虽然使用教师世界坐标偏移，但此前把 Label 左上角直接当锚点；长公式文字框会向单侧展开，
#    实战看起来并不贴在数学老师边上。V322 改为以 176x42 文字框的“中心点”锚在老师侧边，默认侧向76px、Y=-16px。
# 2) 发射后的两条信息严格分成两排：第一排显示该发真实轨迹公式，第二排显示该发真实速度公式 v=L/(t0+L/D)=...；
#    两排作为同一个 Label 一起向上漂并渐隐。白色 Line2D 真实轨迹、施法前逐字算式和答案决定伤害均保持。
# 3) 用户提供 `愤怒的人.png`，正式放入 `res://Images/characters/人物/愤怒的人/愤怒的人.png`，不生图、不改原文件名内容。
# 4) 房产证被敌方角色捡到后，不再实例化旧 `scenes/creatures/领导房产业主.tscn` 的“只追领导”Node2D。
#    现在实例化 `res://scenes/characters/人物/愤怒的人.tscn`：它直接 instance `res://scenes/ball.tscn`、extends ball，是真正独立可受伤角色。
# 5) 愤怒的人固定 Max_health=200，拥有自己的标准 HealthBar/Hurtbox/实体碰撞/死亡流程；Team 复制“实际捡到房产证的人”的 Team，
#    不设置领导为 Master；脚本只保存拾取者引用用于无队伍模式下避免立即反打拾取者，也不再随领导死亡而逃出地图。
# 6) 愤怒的人作为普通 Ball 独立寻找合法敌人并近战；拳头视觉、12物理帧伸缩节奏、挥舞音效、真实命中音效继续复用
#    `Images/characters/人物/面包车/拳头.png`、`audio/characters/面包车/拳头挥舞.mp3`、`拳头命中.mp3`，并保留小幅击退。
# 7) 多人模式仍由领导 authority 可靠RPC在各端创建同名愤怒的人实例，并把该实例 multiplayer authority 递归设置为领导 authority；
#    Team/出生点/攻击参数从同一 config 同步，避免各端随机不同。
# 8) 旧 `scenes/creatures/领导房产业主.tscn` / `scripts/creatures/领导房产业主.gd` 作为历史累计文件保留但 V322 不再运行时引用，
#    用户直接覆盖完整包无需手动删除旧文件。


# -----------------------------------------------------------------------------
# V323 新分类“动漫” / 新角色“菜月昴” / 盘旋拳 / 死亡回归战场时间轴
# -----------------------------------------------------------------------------
# 1) 新增规范角色分类 `res://scenes/characters/动漫/` 与脚本分类 `res://scripts/characters/动漫/`；
#    World 继续使用既有 DirAccess 动态分类索引，不硬编码分类表。新增角色 `菜月昴.tscn/.gd`，不移动、不改名旧资源。
# 2) 菜月昴固定 Max_health=67、Damage=67、Speed=104。关闭身体碰撞伤害、普通 Attack 与主动 Skill；
#    其攻击由角色自身的“盘旋拳”机制持续驱动，死亡回归属于被动核心技能。
# 3) 盘旋拳没有 Area2D/CollisionShape2D/PhysicsBody2D，不产生任何物理碰撞。拳头冷却后从人物中心出现，
#    默认在人物前方约38px处小幅盘旋；118px内出现合法敌人时，拳头沿目标方向伸长，最远约138px，
#    到达攻击点后用距离判定结算一次 `attack_damage(1.0)`，因此默认真实基础伤害严格等于 Damage=67，再缩回人物身边并消失等待下一轮。
# 4) 新增 `死亡回归时间轴.gd`。时间轴由菜月昴运行时挂到当前 World，不修改 world.gd 的分类/出生主链。
#    开战瞬间保存一份全战场开局快照；第一次死亡记录“开局 -> 首次死亡”的真实时长，并必定恢复开局快照。
# 5) 第一次死亡回归完成后才启用 0.10s 默认采样间隔的滚动历史。后续死亡从当前历史向前恢复，
#    最大可回归时间以“首次死亡时长”为基准逐次缩短，默认每次减少首次时长的18%，并硬限制最低0.10s。
#    该18%是 V323 的默认平衡值，保留为 `rewind_shrink_ratio_per_return` Inspector 参数，后续可按实测直接调整。
# 6) 战场快照覆盖现存 Ball 与 BattleTransient 的存在性、场景路径、父节点、authority、Transform、CharacterBody2D velocity，
#    以及 Ball 的 health/block/direction/Repel/Team/state/state cooldown；同时保存可安全序列化的脚本变量。
#    回归时删除目标时间点之后才出现且已经登记的对象，并尝试从 scene_file_path 重建目标快照中已死亡/已释放的对象。
# 7) 每次死亡回归后，菜月昴恢复为 Move，清空击退/攻击/技能运行标记，并把“开局移动方向”按每次47°继续旋转，
#    因而其它单位尽量按恢复后的历史状态延续，而菜月昴自己的初始走向明确改变。47°同样保留为 Inspector 参数。
# 8) 当前没有用户提供的菜月昴正式人物贴图，因此 V323 不猜测或盗用 `Images/` 路径；场景先使用内嵌 Polygon2D/Line2D
#    的黑白橙简化人物视觉，不创建同义 images/Anime 等目录。后续用户提供正式图片后，再按当前路径基准正式接入。
# 9) `translations.csv` 新增：动漫/Anime、菜月昴/Natsuki Subaru、死亡回归/Return by Death、盘旋拳/Orbiting Fist。
# 10) V107 Damage 统一攻击力语义、V126 以后 multiplayer authority/RPC 约束、V309 二级运行时对象原则及 V322 之前累计规则继续保留。


# -----------------------------------------------------------------------------
# V324 菜月昴死亡回归 flushing queries 修复 / 最短回归0.5秒
# -----------------------------------------------------------------------------
# 1) 用户实测菜月昴死亡回归时大量报错：`ball.gd::_normalize_collision_shape_node()` 在 PhysicsServer2D
#    正在 flushing queries 时直接写 `CollisionShape2D.shape`。根因不是拳头碰撞（盘旋拳仍然没有任何碰撞体），
#    而是 V323 在致死伤害的物理回调栈里同步恢复整场快照；恢复过程中重建许多 ball，触发它们的 `_ready()`，
#    随后公共 ball 又同步改 Shape/Area 监听状态。
# 2) `res://scripts/characters/动漫/菜月昴.gd` 的死亡回归改为两阶段：致死钩子只设置 `_returning`、停掉
#    菜月昴物理处理并临时把生命保到1，随后用 `call_deferred()` 进入 `_perform_death_return_deferred()`；
#    真正的整场快照删除/重建/恢复发生在当前物理查询结束后的安全阶段。这样状态机不会抢先进入 Die/queue_free，
#    同时不再在 Area2D/body 查询回调内增删带物理形状的角色。
# 3) 公共 `res://classes/ball.gd::_normalize_collision_shape_node()` 额外把 `CollisionShape2D.shape/scale`
#    改为 `set_deferred()`；`_validate_combat_areas()` 的 Area2D `monitorable/monitoring` 也改为 deferred。
#    这是通用保险：未来即使其它逻辑在物理回调中生成 ball，也不会在该 helper 内立即改动物理查询状态。
# 4) 菜月昴死亡回归的最短可回归时间从 V323 的0.10秒调整为0.50秒。
#    `菜月昴.gd::rewind_min_seconds` 默认/Inspector下限改为0.50，`死亡回归时间轴.gd` 的硬下限同步改为0.50，
#    `菜月昴.tscn` 显式保存 `rewind_min_seconds = 0.5`，因此后续每次缩短最多只会缩到0.5秒，不再到0.1秒。
# 5) V323 的首次死亡必回开局、后续以首次死亡时间为基准每次默认缩短18%、每次回归改变菜月昴初始方向、
#    盘旋拳67基础伤害/无碰撞体、动漫分类动态发现等规则全部保留；本轮不修改拳头攻击间隔。
# 6) V324 覆盖 V323 中“最短回归0.10秒”和“在致死伤害回调中同步恢复战场”的旧实现；其它未冲突累计规则继续有效。

# -----------------------------------------------------------------------------
# V325 菜月昴正式图片 / 死亡回归随机音频 / 三次后音乐 / 回归卡顿分帧修复
# -----------------------------------------------------------------------------
# 1) 用户提供菜月昴正式本体图片 `昴.png` 与死亡回归后短时显示图 `死亡回归.png`。正式路径固定为
#    `res://Images/characters/动漫/菜月昴/昴.png`、`res://Images/characters/动漫/菜月昴/死亡回归.png`；
#    `菜月昴.tscn` 删除 V323 的 Polygon2D/Line2D 临时简化人物，Graphics/Image 直接使用正式 `昴.png`。
# 2) 每次死亡回归完整恢复结束后，Graphics/Image 临时切换为 `死亡回归.png`，默认持续1.8秒后恢复 `昴.png`。
#    两张图宽高比差异很大，因此代码按两张图最长边比例调整临时图 scale，避免1229x790的回归图直接把人物视觉放大数倍；
#    该视觉仅替换 Sprite2D 纹理/scale/offset，不改碰撞体，也不参与战场快照存在性。
# 3) 用户提供 `叫.zip` 共14个音频，全部按原文件名放入 `res://audio/characters/菜月昴/`。每次死亡回归后由
#    authority 随机选一个索引，再用 reliable + call_local RPC 把同一个索引广播给各端；本地使用 AudioStreamPlayer2D 播放。
#    新回归发生时会 stop 上一次仍在播放的叫声再播放新随机音频，避免最长约44秒的叫1与后续回归无限叠加。
# 4) 用户提供 STYX HELIX mp3，保持上传原文件名放在 `res://audio/characters/菜月昴/`。死亡回归次数达到3次时
#    开始本地 AudioStreamPlayer 音乐；流复制后设 AudioStreamMP3.loop=true，因此第三次以后持续循环且第四次回归不会从头重启。
# 5) V324 已解决 PhysicsServer2D flushing queries 报错，但整场恢复仍在一次 deferred 回调里同步做全部状态恢复与 PackedScene.instantiate，
#    因此实测死亡回归仍会“卡一下”。V325 的 `死亡回归时间轴.gd::_restore_world_snapshot()` 改为约2.2ms主线程预算分片：
#    删除额外对象、恢复现存对象、重建缺失对象分阶段执行，超预算就 `await get_tree().process_frame`，把大批节点工作摊到数帧。
# 6) `_apply_node_state()` 原先对每一个脚本变量都重新扫描 node.get_property_list()；现在每个节点只建立一次属性名 Dictionary，
#    把恢复脚本变量的热点从重复全表扫描改为字典 has 查询。第一次回归恢复开局后也不再立即重复 capture 整个战场，直接复用 initial snapshot。
# 7) `菜月昴.gd::_perform_death_return_deferred()` 对时间轴恢复使用 await，只有完整恢复完成后才重新打开菜月昴 physics、重置盘旋拳、
#    改变回归方向并触发图片/叫声/音乐，避免分帧恢复尚未完成时角色提前行动。V323/V324 的67生命、67攻击、首次回开局、
#    后续回归窗口按18%缩短且最低0.5秒、每次方向+47°、盘旋拳无物理碰撞等规则全部继续保留。


# -----------------------------------------------------------------------------
# V326 菜月昴影之手区域规划 / 拳击音效 / 回归叫声增益 / 第三次音乐单次触发 / 回归误杀修复
# -----------------------------------------------------------------------------
# 1) 用户提供新的紫黑影之手图片，保持上传原文件名：
#    `res://Images/characters/动漫/菜月昴/ChatGPT_Image_2026年9月3日_04_38_31.png`。
#    `菜月昴.gd` 不把图片切成多个新文件；同一 Texture2D 通过两个 AtlasTexture 区域分别作为“手臂”和“手”。
#    默认手臂区域 Rect2(0,0,1580,682)，手区域 Rect2(1480,0,568,682)，均为 Inspector 可编辑参数，后续可直接重划区域。
# 2) 手臂视觉改为带纹理 Line2D，并使用 LINE_TEXTURE_STRETCH 沿多点规划路径拉伸；手部是独立 Sprite2D，位于曲线末端并沿末端切线旋转。
#    `fist_arm_control_points` 两个 Vector2 使用“x=沿手臂长度比例、y=侧向长度比例”定义三次贝塞尔控制点，配合
#    `fist_arm_curve_samples` 与 `fist_dynamic_bend`，手臂可以拉长、弯曲和动态扭曲，而拳头本身不会被弯曲压扁。
# 3) 攻击结算仍只有“手区域”产生真实伤害；其命中规划半径由 `fist_hand_hit_radius` 独立控制。手臂区域仅是可变形视觉，
#    不新增 Area2D/CollisionShape2D，不制造身体/手臂自然碰撞伤害。默认触发距离138、最大伸长178，仍以 `attack_damage(1.0)` 结算67基础攻击力。
# 4) 盘旋拳挥出时复用项目现有 `res://audio/characters/拳击手/拳击手_挥拳.mp3`；只有真实命中造成 health/block 损失时
#    才播放 `res://audio/characters/拳击手/拳击手_命中.mp3`。不复制、不改名拳击手原音频。
# 5) 死亡回归随机叫声默认从 -2dB 提高到 +6dB，AudioStreamPlayer2D 最大距离从1400提高到2400；仍然每次随机14个叫声之一，
#    新回归会先 stop 上一个叫声，避免长叫声叠加。
# 6) STYX HELIX 的触发条件从“return_count >= 3”改为“return_count == 3”，并新增本地 `_return_music_started` 一次性门闩。
#    只有第三次死亡回归完成后会启动并循环；第四次及以后死亡回归绝不再次调用启动逻辑，也不会从头重播。
# 7) 修复死亡回归会直接杀掉敌人的问题：时间轴历史不再采集 health<=0 / State.Die 的 Ball；恢复状态时即使旧快照残留0HP/Die，
#    也强制至少1HP且禁止写回 Die。目标快照中不存在的 Ball 不再 queue_free，避免稍后出生/召唤的合法敌人被“回归”当成击杀释放；
#    仍只清理目标时间之后出现的 BattleTransient（投射物/临时效果）。
# 8) 菜月昴自身 `_return*` 运行态与时间轴/拳头节点引用不再进入安全脚本变量快照，避免旧快照把 `_returning`、
#    `_return_music_started` 等一次性运行标志写回旧值。V325 的约2.2ms分帧恢复、V324 deferred物理安全处理继续保留。


# -----------------------------------------------------------------------------
# V327 菜月昴完整战场回溯 / 不可视之手真实拳头碰撞 / 死亡回归固定音效
# -----------------------------------------------------------------------------
# 1) 时间轴从战斗开始就持续采样；第一次死亡前若发现其他 Ball 晚于菜月昴生成，使用角色数量更多的完整快照升级开局快照。
# 2) Ball 与 BattleTransient 都恢复存在性：快照外对象移除，快照内缺失对象按原场景、父节点、authority 和 key 重建；
#    生命、状态、位置、速度、阵营、格挡、击退和安全脚本变量按目标时间点原样恢复。V326 的不删除额外 Ball 临时策略被覆盖。
# 3) 不可视之手始终在人物朝向正前方小幅晃动，不再转到背后；回拳时手臂缩短、拳头回到身前，不会消失。
# 4) 出拳开始时锁定敌人当时的位置，之后不追踪。只有拳头拥有 Area2D + CircleShape2D；手臂仅视觉。
#    伤害只由拳头命中 hurtbox 的 area_entered 触发，删除旧终点距离直扣血；真实命中后附加默认48的轻微击退。
# 5) 用户音效命名为 `res://audio/characters/菜月昴/死亡回归.mp3`，峰值归一化；每次死亡回归固定播放。
#    固定音效与随机叫声都改用非空间 AudioStreamPlayer，默认分别 +8dB / +10dB，避免距离衰减导致音量过小。
# 6) authority/RPC、deferred物理安全、分帧恢复、第三次音乐和影之手纹理区域规划等不冲突规则继续保留。

# -----------------------------------------------------------------------------
# V331 基于 V327 完全回退后的定向修复（V328/V329/V330 作废）
# -----------------------------------------------------------------------------
# 1) 本版代码基线完整恢复为 V327；不继承 V328/V329/V330 对菜月昴、死亡回归时间轴、拳头视觉/尺寸的任何改动。
# 2) 只调整死亡回归音量：随机叫声 return_scream_volume_db 从 V327 的 +10dB 提高到 +18dB；
#    固定“死亡回归.mp3” return_sound_volume_db 从 V327 的 +8dB 降低到 -8dB。音频播放结构、音频文件名与其它规则不改。
# 3) 不可视之手的手掌大小、手臂宽度、Atlas 区域、Line2D 纹理模式、碰撞半径等全部保持 V327 原值。
#    仅取消两层距离上限：寻找最近合法敌人时不再受 fist_trigger_radius 限制；出拳时不再用 fist_attack_reach 截断长度。
#    因此手臂可按敌人在出拳瞬间的位置无限延伸；拳头本身不随距离放大，出拳后仍不追踪敌人。
# 4) V327 的完整战场回溯、真实拳头 Area2D 碰撞、轻微击退、回拳缩短回身前等行为原样保留。

# -----------------------------------------------------------------------------
# V332 菜月昴不可视之手无限延伸坐标修复（继续以 V327/V331 为基线）
# -----------------------------------------------------------------------------
# 1) 用户实测 V331 仍只伸出很短距离。根因不是拳头/手臂尺寸，也不是 fist_attack_reach 仍在截断，
#    而是锁定目标使用世界坐标，Line2D 与拳头节点却使用本地坐标；旧代码把 world_position-global_position
#    直接作为本地端点，在角色或父节点存在缩放/变换时会再次缩短实际世界伸长距离。
# 2) 出拳终点改为 `_fist_root.to_local(locked_target_world)`，即把“出拳瞬间敌人的固定世界位置”正确转换为
#    不可视之手根节点的本地坐标。不减敌人半径、不读取 fist_attack_reach，因此不存在最大伸长距离。
# 3) 出拳和回拳阶段 Line2D 路径直接使用 `[Vector2.ZERO, fist_local_position]`：手臂就是从人物身前到拳头
#    直接拉长/缩短。待机时仍保留 V327 的前方小幅弯曲晃动。
# 4) fist_arm_width=34、fist_hand_visual_size=48、fist_hand_hit_radius=20、Atlas 区域、纹理模式、碰撞逻辑、
#    0.18s出拳/0.20s回拳、音量、死亡回归时间轴等全部不改；本轮只修无限延伸的坐标与攻击阶段直线拉长。


# -----------------------------------------------------------------------------
# V333 菜月昴大量动态对象回溯稳定性 / 不可视之手待机姿势与自然收拳
# -----------------------------------------------------------------------------
# 1) 修复“先让大量兔子繁殖，再创建菜月昴，死亡回归时 Trying to assign invalid previously freed instance”：
#    V327 的恢复过程会按约2.2ms预算跨帧 await，但 current_by_key 之前直接长期保存 Node 引用；兔子/召唤物数量多时，
#    某些节点可能在等待期间被其它战斗逻辑 queue_free，Dictionary 内旧引用不会自动变 null，随后赋给 typed Node 就报错。
# 2) current_by_key 改为只缓存 get_instance_id() 的 int。每次真正使用前先 is_instance_id_valid()，再 instance_from_id()；
#    已经释放的对象直接按“缺失节点”处理并依照 V327 快照重建，不再把失效 Object 引用跨帧保存。
# 3) 不可视之手待机姿势改为明确的 S 形：从菜月昴根部先几乎竖直向上一小段，再向下大幅弯曲并推进到身前，
#    最后再向上弯一点，拳头接在末端上扬方向。拳头仍位于人物正前方。
# 4) 待机手臂使用三组不同频率的轻微正弦摆动分别作用于上段、下弯和末端，让手和手臂持续自然晃动，
#    不再是整条手臂机械地绕人物盘旋。
# 5) 攻击时待机曲线立即拉直，然后保持无限延伸规则直线打向“出拳瞬间敌人的固定世界位置”；不追踪敌人。
#    收拳时约按原 fist_return_time 的0.78倍快速缩回，并从直线连续过渡回待机 S 形，避免最后一帧突然折回。
# 6) fist_arm_width=34、fist_hand_visual_size=48、fist_hand_hit_radius=20、真实拳头 Area2D 伤害、48轻微击退、
#    +18dB叫声、-8dB死亡回归固定音效、V327完整战场回溯语义均保持，不额外修改其它系统。


# -----------------------------------------------------------------------------
# V334 菜月昴不可视之手明确转角 / 平滑随人物转向
# -----------------------------------------------------------------------------
# 1) 用户反馈 V333 初始待机手臂的节点视觉上叠在一起，并且看不到“先上、再大幅向下、最后上扬”的明确转角。
#    根因是 V333 仍把四个待机控制点送进三次贝塞尔采样；贝塞尔会主动平滑控制点而不是经过中间控制点，
#    再叠加默认 fist_rest_radius=38 与 fist_arm_width=34，短距离弯曲很容易被线宽盖成一团。
# 2) V334 待机路径改为真正的 Line2D 分段折线，直接使用 4 个点：根部 -> 竖直上小段 -> 大幅下折 -> 前上方末端。
#    不再对待机路径调用 cubic 采样，因此两个转角是实际线段连接点；Line2D 仍使用 ROUND joint，只圆润拐角边缘，不抹掉折向。
# 3) 为避免 34px 宽度把转角完全遮住，只把待机“骨架节点间距”拉开（pose_scale 至少42），不改变
#    fist_arm_width=34、fist_hand_visual_size=48、fist_hand_hit_radius=20、Atlas 区域、拳头 scale 或碰撞大小。
# 4) 新增仅用于视觉的 _fist_visual_angle。人物 direction 变化时，以 fist_turn_degrees_per_second=300°/s 通过 rotate_toward
#    逐帧把不可视之手当前朝向转向新朝向，不再每帧直接用 direction 重算并瞬间翻面。待机折线和拳头作为同一姿势自然转过去。
# 5) 攻击仍然直接拉直、无限延伸到出拳瞬间锁定的位置；收拳仍快速回收，但现在从直线逐渐恢复成“有真实转角”的折线，
#    不改变 V333 的死亡回归、兔子大量繁殖稳定性修复、+18dB叫声、-8dB死亡回归音效及其它系统。

# -----------------------------------------------------------------------------
# V335 菜月昴不可视之手悬垂惯性 / 死亡回归禁止回血跳字
# -----------------------------------------------------------------------------
# 1) 按用户手绘示意重做待机骨架：不可视之手根部固定在人物身体前侧略偏上，随后明显向下悬垂，
#    在底部形成回钩，再向前上方抬起，拳头接在最后上扬的末端；不再使用 V334 的“上-下-上折线”轮廓。
# 2) 新增逐段阻尼跟随链。第一个骨架点直接跟随根部，越靠近拳头的节点弹簧刚度越低、响应越慢，
#    因此转向时根部先转、后段逐级跟上、拳头最后到位，不再整条手臂同步旋转。
# 3) 人物平移也加入世界空间拖尾补偿：每帧把人物位移的反向局部量按节点序号逐渐施加到后段，
#    所以人物移动时根部先走、后面的手臂与拳头会带着惯性拖后再自然追上，而不是整条线焊死在人物身上。
# 4) 攻击规则不变：出拳时将当前悬垂链直接拉直，仍可无限延伸到“出拳瞬间敌人位置”；拳头不追踪。
#    收拳时快速从直线缩回并连续恢复悬垂形状，完成后继续由逐段阻尼链接管自然晃动。
# 5) 拳头视觉大小48、手臂宽度34、碰撞半径20、真实 Area2D 命中、48击退、+18dB叫声、-8dB死亡回归音效均不改。
# 6) 修复死亡回归时大量绿色 +N 回血跳字：时间轴写回快照 health 前临时设置角色现有
#    health_bar.suppress_floating_text=true，写回后恢复原值；菜月昴死亡时临时保活 health=1 也同样静默处理。
#    死亡回归是状态回溯而非治疗，因此只禁止浮动治疗文字，不修改生命 setter、伤害系统或正常治疗表现。
# -----------------------------------------------------------------------------
# V336 数学老师四类粉笔音效 / 轨迹与速度公式扩充 / 公式文字翻倍
# -----------------------------------------------------------------------------
# 1) 用户提供四个数学老师正式音效，保持原文件名并放入角色专属目录：
#    `res://audio/characters/数学老师/移动.mp3`、`写字.mp3`、`扔笔.wav`、`打到墙.mp3`。
#    不放到 audio 根目录，也不创建 Audio/Audios/Voices 等旧同义目录。
# 2) 数学老师在人物下方逐字揭示“决定本发伤害的算式”时播放 `写字.mp3`；
#    音效只覆盖逐字书写阶段，公式完整后的短暂停留不继续播放。新一轮书写会先 stop 旧声，死亡也会立即停止。
# 3) 每一枚粉笔公式弹生成后，本地 AudioStreamPlayer2D 播放并循环 `移动.mp3`，音源随粉笔位置移动；
#    粉笔撞墙、寿命结束或被释放时，移动音随投射物一起停止，不创建长期残留播放器。
# 4) 公式弹实际发射瞬间播放 `扔笔.wav`；authority 以可靠的投射物生成结果为准并通过位置音效 RPC
#    在各客户端同一世界坐标播放。粉笔第一次 raycast 命中 Layer1 墙体/地图实体时播放 `打到墙.mp3` 后消失。
#    命中人物仍继续使用 V312 既有 balls_hit1.sfxr，不把撞墙声误用于人物命中。
# 5) 真实轨迹类型从 3 种扩充到 8 种：4p(1-p)、sin(πp)、sin(2πp)、sin(3πp)、sin(4πp)、
#    16p²(1-p)²、4p(1-p)cos(2πp)、sin(2πp)sin(πp)。白色 Line2D 和粉笔位置都调用同一个
#    `_curve_y()`，发射后显示的轨迹公式也来自同一个 curve_kind，不是装饰性假公式。
# 6) 真实速度公式从 1 种扩充到 5 种：原 v=L/(t0+L/D)、线性插值、平方根插值、平方插值、
#    正弦缓入插值。每发先随机 speed_kind，再用同一个 speed_kind 做 AI 提前量估算、实际 travel_speed
#    与发射后速度公式文字；所有结果仍受 speed_formula_min/max 限制，避免新增公式破坏原速度上下限。
# 7) 施法前伤害算式字号从 14 -> 28，发射后“轨迹公式 + 速度公式”字号从 11 -> 22；
#    两个 Label 的文字框、描边和行距同步扩大，严格为原字号 2 倍，避免只放大字体后被旧矩形裁切。
# 8) V317 答案决定伤害、V316 移动目标提前量/16px命中半径/3.6s寿命、V320/V322 发射后双公式定位、
#    V312 白色真实轨迹及人物命中音效、V335 之前其它累计规则全部保持。


# -----------------------------------------------------------------------------
# V337 数学老师公式字号纠正：仅轨迹/速度公式翻倍
# -----------------------------------------------------------------------------
# 1) 用户澄清 V336 的“文字太小，大小翻倍”只指发射后显示的“轨迹公式 + 速度公式”，
#    不指施法前决定本发伤害的算式。V336 第7条中“伤害算式 14 -> 28”的部分作废。
# 2) `res://scripts/characters/数学老师.gd` 的 `formula_font_size` 恢复为原始 14；
#    伤害算式 Label 的 170x28 文字框与 2px 描边也恢复原值，不再跟随轨迹/速度公式放大。
# 3) 发射后 `shot_formula_font_size` 继续保持 22，即原始 11 的严格 2 倍；该 Label 的扩大文字框、
#    两行“轨迹公式 + 速度公式”的显示位置与上浮渐隐逻辑保持 V336。Godot 的本地主题字号覆盖彼此独立。
# 4) V336 新增的四类正式音效全部保留：移动.mp3=粉笔飞行移动声，写字.mp3=伤害算式逐字书写声，
#    扔笔.wav=粉笔发射声，打到墙.mp3=粉笔撞墙声；命中人物仍使用原 balls_hit1.sfxr。
# 5) V336 的真实轨迹 8 类与真实速度公式 5 类全部保留，不回退、不减少；真实运动、AI 提前量、
#    白色轨迹线以及发射后显示文字继续使用同一 curve_kind / speed_kind。
# 6) 本版只纠正“哪一类公式文字翻倍”的误解；数学老师伤害计算、公式答案决定伤害、角色数值和其它累计规则均不改。

# -----------------------------------------------------------------------------
# V338 数学老师删除轨迹/速度文字显示
# -----------------------------------------------------------------------------
# 1) 按用户最终要求，直接删除数学老师发射后“轨迹公式 + 速度公式”的文字显示，不再创建对应 Label，
#    也不再进行相关 RPC、上浮、渐隐、字号或定位处理。V337 中关于发射后双公式显示/22px字号的规则作废。
# 2) 删除 `数学老师.gd` 中仅服务于文字显示的轨迹公式字符串生成、速度公式字符串生成、发射后公式 Label 创建与 RPC 调用链，
#    同时删除场景里的 shot_formula_world_offset / float_distance / fade_duration / font_size 覆盖。
# 3) 真实战斗逻辑完全保留：8 类 curve_kind 轨迹、5 类 speed_kind 速度模型、AI 提前量、白色真实轨迹线、实际粉笔位置/速度均不减少。
# 4) 施法前“决定本发伤害的算式”仍按 V337 保持 14px，并继续播放 `写字.mp3`；它不是本轮删除对象。
# 5) V336 四类正式音效继续保留：移动.mp3=粉笔飞行，写字.mp3=伤害算式书写，扔笔.wav=发射，打到墙.mp3=撞墙。

# -----------------------------------------------------------------------------
# V339 数学老师粉笔图片范围碰撞箱 / 四类正式音效可听性修复
# -----------------------------------------------------------------------------
# 1) 用户明确要求粉笔碰撞箱就是粉笔图片范围。删除 V316/V338 沿用的 projectile_hit_radius=16 圆形粉笔命中判定；
#    数学公式弹场景新增 ChalkHitbox/CollisionShape2D，运行时通过 Visual(Sprite2D).get_rect() 与 Visual.scale
#    计算 RectangleShape2D 的真实宽高。CollisionShape2D 自身 scale 始终保持 (1,1)，尺寸直接写入 RectangleShape2D.size。
# 2) 粉笔撞 Layer1 墙体不再只用“中心点 raycast”；正常路径改用同一个图片矩形 Shape2D 做 cast_motion 连续扫掠，
#    因此图片边缘先碰到墙时就会撞墙。仅在形状尚未完成配置的极端首帧保留旧 raycast 作为兼容兜底。
# 3) 粉笔穿过人物时也不再用“目标中心 + 16px 粉笔圆半径”的近似。每帧用同一个图片矩形 Shape2D
#    collide_with_motion() 扫过敌人的真实 CharacterBody2D/Hurtbox CollisionShape2D；敌方主动攻击 Hitbox 不算人物占据区域。
#    少数没有正常 CollisionShape2D 的特殊 Ball 才回退到目标自身占据半径，但粉笔侧仍严格保持图片矩形。
# 4) 四类用户正式音效做可听性修复。实测素材：移动.mp3 峰值约 -9.1dB，旧代码又额外 -10dB，明显过轻；
#    V339 将移动声提高到 +4dB、max_distance=1800、attenuation=0.35。写字声改 0dB / 1800 / 0.35。
#    扔笔声改 +2dB / 1800 / 0.35；撞墙声改 0dB / 1800 / 0.35。仍全部走 GameplayRecord（若该总线存在）。
# 5) 用户素材写字.mp3 开头约0.08秒、扔笔.wav开头约0.055秒、打到墙.mp3开头约0.075秒接近静音。
#    V339 分别从 0.08 / 0.06 / 0.08 秒位置开始播放，避免很短的伤害算式或瞬时事件只播到静音头。移动.mp3无此前导静音。
# 6) 扔笔/撞墙的 TeacherActionSfx RPC 从 unreliable 改为 reliable；粉笔命中人物位置音效 RPC 也同步改 reliable，
#    避免联机时偶发丢包造成“明明触发但这一声没听见”。音频触发语义不变：写字=伤害算式书写，扔笔=实际发射，
#    移动=粉笔飞行循环，打到墙=真实墙体碰撞。V338 已删除的轨迹/速度文字不恢复。



# -----------------------------------------------------------------------------
# V340 数学老师高级伤害公式池 / 粉笔轨迹跨地图显示到屏幕外
# -----------------------------------------------------------------------------
# 1) 用户反馈数学老师伤害偏低，但明确要求不要直接修改伤害数值。Damage=28、projectile_damage_multiplier=1.0、
#    V317“公式右侧答案直接决定本发基准伤害”的机制全部保持；本轮只重做出题公式，让答案通过数学结构自然提高。
# 2) 伤害公式从旧的小整数等式/加减乘混合升级为15类公式池：括号复合运算、平方、立方、平方根、阶乘、绝对值、
#    求和Σ、组合数C(n,2)、最小公倍数lcm、2x2行列式det、多项式代入、log₂、勾股根式、排列P(n,2)、二次判别式Δ。
#    每一条显示公式都由同一次实际整数计算得到右侧答案，不是装饰文字；答案仍通过 V317 原伤害换算链进入 attack_damage()。
# 3) 为避免高级公式文字被旧170px文本框裁切，只把施法前公式 Label 宽度扩到360px；formula_font_size仍为V337规定的14，
#    不恢复 V336 误改的28px，也不恢复 V338 已删除的“轨迹/速度文字”。
# 4) 粉笔白色轨迹线删除旧 `min(...,720)` 固定长度上限，不再按地图矩形截断。运行时把 Viewport 可见矩形经
#    Canvas transform 逆变换成世界坐标，沿本发真实 _curve_y() 轨迹采样直到“当前屏幕外约140屏幕像素”的位置。
# 5) World 现有地图外视觉遮罩 z=90 会擦掉普通角色/特效的越界部分；数学老师白色轨迹线单独使用 z=91，
#    因此能越过地图边界继续画到屏幕外围。只豁免这条轨迹线：粉笔实体的墙体碰撞、人物命中、地图安全框、角色裁剪均不改。
# 6) V339 粉笔图片范围矩形碰撞与四类正式音效、V338 删除轨迹/速度文字、8类真实轨迹和5类真实速度模型全部保留。

# -----------------------------------------------------------------------------
# V341 数学老师轨迹恢复地图外遮挡 / 粉笔完整越界后销毁
# -----------------------------------------------------------------------------
# 1) 用户纠正 V340：白色粉笔轨迹不应该显示在地图外。V340 第4~5条中“轨迹线 z=91 压过
#    MapOutsideVisualMask 并跨出地图可见”的规则作废。轨迹 Line2D 仍按真实 _curve_y() 生成，
#    但 z_index 改回80，位于 World 的 MapOutsideVisualMask(z=90) 下方，因此地图 Rect2 外的轨迹由外侧背景遮掉。
# 2) 粉笔实体本身同样保持 z=80，所以穿过地图边界时会被同一个地图外遮罩逐步盖住：先遮一部分，
#    再随着整张粉笔图片越界越来越少，直到整张图片完全离开地图可见矩形后才 queue_free。
# 3) 销毁判定严格使用 V339 已建立的“粉笔图片范围矩形”：把 RectangleShape2D 四个角按粉笔当前旋转变换到世界坐标，
#    取旋转后的世界 AABB；只有该 AABB 与当前地图真实 world Rect2 完全不相交时才销毁，而不是中心点一出界就删。
# 4) 为实现“粉笔真正穿过地图外墙”，当前地图最外沿的碰撞只在粉笔图片下一步确实跨出地图、且碰撞点位于对应外边界
#    并且运动方向朝外时放行；地图内部墙体仍使用 V339 的图片矩形 cast_motion 正常碰撞、播放打到墙.mp3 并销毁。
# 5) 有有效地图 Rect2 时不再用 projectile_lifetime 提前删除粉笔，避免尚未完全被地图外遮罩盖住就突然消失；
#    只有异常场景拿不到地图 Rect2 时才保留旧 lifetime 作为泄漏保护。
# 6) V340 的15类高级伤害公式、V339 图片范围碰撞与四类音效、V338 删除轨迹/速度文字显示全部保持。

# -----------------------------------------------------------------------------
# V342 数学老师粉笔完全无视阻挡 / 仅地图外或路径终点销毁
# -----------------------------------------------------------------------------
# 1) 用户确认 V341 仍会碰墙消失，不符合预期。V341 第4条“只放行地图最外沿、内部墙体仍正常碰撞并销毁”作废。
# 2) `res://scripts/shooter/数学老师公式弹.gd` 完全删除墙体/地形 `_terrain_hit()` ShapeCast/RayCast 检测链，
#    也删除 `_is_outward_map_border_hit()` 外墙特判。粉笔移动直接写入本发真实曲线位置，因此所有墙、地形、静态体和其它
#    物理阻挡都不会停止、反弹或销毁粉笔；V339 的 `打到墙.mp3` 资源与教师侧播放函数为兼容累计包继续保留，但数学公式弹
#    已不再产生“撞墙事件”，所以正常情况下不会播放该声音。
# 3) “无视阻挡”不删除人物伤害：authority 仍每物理帧使用 V339 的粉笔图片 RectangleShape2D，沿 previous->next_pos 做
#    `collide_with_motion()` 连续扫过 Ball/Hurtbox 的真实 CollisionShape2D；同一目标仍由 hit_ids 保证每发只结算一次。
# 4) 新增 `path_end_distance`。`_build_trajectory_line()` 计算白色真实路径的 max_distance 后，同时把同一距离记录为粉笔实体的
#    路径终点；因此视觉轨迹终点与实际投射物寿命终点一致，不会出现线已经结束、粉笔继续无限直飞。
# 5) 粉笔现在只有两个销毁条件：A) V341 的旋转后图片世界 AABB 与当前地图真实 Rect2 完全不相交；B) traveled_x 到达
#    path_end_distance。任一成立即 queue_free。取得地图矩形时不看 lifetime；取不到地图矩形的异常场景也只用路径终点，
#    不恢复墙体碰撞或时间销毁。
# 6) V341 的地图外视觉遮罩仍保持：白色轨迹和粉笔 z=80，World MapOutsideVisualMask z=90，所以越出地图的部分会被遮住，
#    直到整张粉笔图片完全离开地图才满足条件A。V340 的15类高级伤害公式、V339 图片范围人物命中和四类音频资源、
#    V338 删除轨迹/速度文字显示均继续有效。



# -----------------------------------------------------------------------------
# V343 数学老师粉笔命中恢复人物受击白线
# -----------------------------------------------------------------------------
# 1) 用户反馈粉笔已经能正常穿过阻挡并造成伤害，但命中人物时缺少项目通用的“受击白线/背后爆射线”。
#    根因是数学公式弹使用自定义 RectangleShape2D 连续扫掠后直接调用 receive_spatial_damage()，
#    没有经过普通 hitbox 的命中反馈链，也没有像军火商子弹/猎人霰弹一样显式调用 notify_hit_burst_feedback()。
# 2) V343 在每个目标真实结算前记录 health/block，receive_spatial_damage() 后重新计算 health_loss/block_loss；
#    只有 dealt=true 且 health_loss>0 时才调用目标现有 notify_hit_burst_feedback()，因此无敌、取消伤害、
#    纯格挡而没有掉血时不会凭空出现“受伤白线”。
# 3) 白线 incoming_direction 使用粉笔本帧真实曲线运动方向（to_pos-from_pos），而不是固定水平；
#    因此通用 HitBurstEffect 会从人物被粉笔穿过后的背侧沿真实入射方向爆射。
# 4) coverage_width 不使用旧固定半径，而是把 V339 的粉笔图片 RectangleShape2D 沿入射方向的垂直轴做真实投影，
#    让受击白线扩散/密度继续服从项目公共“攻击横截面 + 实际伤害”规则。
# 5) V342 的“粉笔完全无视墙/地形，只在整张图片完全出地图或走到路径终点时消失”全部保持；
#    V340 的15类高级伤害公式、V339 图片范围命中、V338 删除轨迹/速度文字显示和现有音频机制均不改。


# -----------------------------------------------------------------------------
# V344 领导删除小领导子弹 / 处分按目标累计次数递增随机伤害
# -----------------------------------------------------------------------------
# 1) 用户明确删除“领导射出来的领导子弹”。领导普通攻击从 V311~V343 的
#    “处分文件 + 小领导概率分支”改为 100% 只发 `领导处分文件`。
#    `领导.gd` 删除 MINI_LEADER_SCENE preload、mini_leader_* 导出参数、生成 RPC、说教 RPC 和全部运行时调用。
# 2) 累计更新包同时移除：
#    `res://scenes/shooter/领导小领导.tscn`
#    `res://scripts/shooter/领导小领导.gd`
#    `res://scripts/shooter/领导小领导.gd.uid`
#    `translations.csv` 中的“领导小领导 / Mini Leader”键也删除。V344 起禁止重新恢复这套投射物。
# 3) 处分文件不再在“发射瞬间”决定最终伤害。真正命中目标时，由领导 authority 根据该目标自己的累计处分次数滚伤害。
#    每个目标使用独立 Dictionary 计数：A 吃了很多处分不会抬高 B 的处分伤害。
# 4) 默认第一档 multiplier 随机范围为 1.15~1.55；每成功吃到一次处分，下一档上下界都 +0.50。
#    因为每档宽度只有0.40而档间步进0.50，在领导攻击力不变时，相邻两次处分的随机区间不重叠：
#    同一个人物后一次成功处分一定比前一次的可能伤害区间更高，同时每一档内部仍保持随机。
# 5) 只有 `receive_spatial_damage()` 真正接受该次处分后才 +1 层；完全无敌/被拒绝的命中不增加处分层数。
# 6) 领导 `Damage=24`、Attack_Cooling=2.0、处分速度/生命周期、处分图片与命中音效、受伤掉落经济、
#    房产证召唤“愤怒的人”等累计机制均不直接修改。


# -----------------------------------------------------------------------------
# V345 领导处分伤害下调 / 挨打掉落稳定可见
# -----------------------------------------------------------------------------
# 1) 用户实测 V344 处分伤害成长过高。本轮不修改领导基础 Damage=24，也不取消“同一个人物吃处分越多伤害越高”。
#    仅把处分倍率首档从 1.15~1.55 降到 0.45~0.65，每次成功处分后的目标专属成长步进从 +0.50 降到 +0.20。
#    以未受其它攻击力倍率影响的 Damage=24 为例：首档约10.8~15.6，第二档约15.6~20.4，第三档约20.4~25.2；
#    后续仍随同一目标的成功处分次数逐步抬高，但不会像 V344 那样很快跳到四五十伤害。
# 2) 用户反馈仍没看见领导挨打掉东西。掉落触发链本身已经在 ball.health setter 的真实 health loss 钩子上，
#    但掉落落地后立即进入拾取判定，而领导自己也是合法拾取者；落点又离领导很近，因此可能刚落地第一帧就被领导自己捡回，
#    实战视觉上像“没有掉落”。
# 3) V345 掉落概率从35%提高到60%，连续真实受伤保底从3次改为2次，成功掉落最小间隔从0.18s降到0.12s。
#    仍然只有真实 health 下降触发，护盾损失不会触发，领导自身 hostile return 反伤仍由 suppress 标记禁止递归掉落。
# 4) 掉落抛物线时间改为0.84s、高度52~92px、落地点离领导40~90px；落地后新增0.70s强制展示时间，
#    展示期任何人物（包括领导自己）都不能拾取。之后才恢复原有真实图片不透明像素拾取规则。
# 5) 金币/车钥匙/房产证最大边从18/25/28px提高到24/32/36px，z_index提高到104（回飞105），
#    让混战中更容易确认“挨打爆东西”。掉落种类权重、友军回血、敌人拾金币/钥匙回飞反伤、
#    敌人拾房产证召唤“愤怒的人”等规则全部保持。
\n\n# -----------------------------------------------------------------------------\n# V346 领导掉落物真实边界反弹 / 房产证队伍修复 / 新增“小弟”角色分类\n# -----------------------------------------------------------------------------\n# 1) V345 的金币/钥匙/房产证 24/32/36px 实战过大；V346 缩为 14/18/22px。\n# 2) 掉落物场景根从 Node2D 改为 CharacterBody2D，collision_layer=0、collision_mask=1，并用与当前图片缩放后矩形一致的 RectangleShape2D。\n#    飞行阶段不再每帧 clamp 到地图内，而由 move_and_collide() 获取真实地图/TileMap 碰撞；命中边界或地图实体墙后，\n#    使用 velocity.bounce(collision.get_normal()) * 0.72 反射，并对 remainder 再补一次反射位移。落地后仍钳制回安全地图范围。\n# 3) 房产证敌方拾取生成“愤怒的人”时，V345 是 add_child() 后才写 Team，错过 ball._ready() 的召唤身份初始化。\n#    V346 在 add_child() 前解析 picker_path，预先写入 Team、Master、Master_name；configure_from_property_deed() 入树后再次确认并同步 default_properties[Team]。\n#    因此愤怒的人从第一帧开始就是实际拾取者队伍，不再默认留在 Ball/领导侧。\n# 4) 新建 res://scenes/characters/小弟/，角色分类 UI 会按 world.gd 的一级目录索引自动出现“小弟”分类。\n#    愤怒的人从 人物/ 迁移到 小弟/；领导的 PROPERTY_UNIT_SCENE 引用同步更新。world 索引额外隐藏用户旧工程可能残留的 人物/愤怒的人.tscn。\n# 5) 新分类加入可独立上场的召唤型战斗单位：愤怒的人、国王守卫、国王将军、黑帮小弟、黑帮持枪小弟、功夫小弟、\n#    持刀小混混、铁棍小混混、拳头小混混、NC步枪兵、NC坦克、伪军。\n#    投稿随从/伪军脚本新增 standalone_selection，仅角色选择页包装场景启用；原角色召唤出来的版本保持原 Master/跑路/寿命规则。\n# 6) 墙、捕兽夹、武器、门手、列车等非独立人物装置不进入“小弟”分类，避免把机关/装备伪装成人物。\n

# -----------------------------------------------------------------------------
# V347 修复领导掉落物 PhysicsServer flushing queries 报错
# -----------------------------------------------------------------------------
# 1) 用户实机截图显示 V346 在 `领导.gd::_rpc_spawn_drop()` 的 `_runtime_container().add_child(node,true)`
#    连续报错：
#    `Can't change this state while flushing queries. Use call_deferred() or set_deferred()...`
#    同一生成链随后进入 `领导掉落物.gd::_apply_visual()` 并给 CollisionShape2D 写新 RectangleShape2D，
#    因此一次真实受伤掉落可能连续产生多条相同 PhysicsServer 错误。
# 2) 根因不是掉落反弹算法，而是生成时序：领导的掉落由 `ball.health` 真实生命损失钩子同步触发，
#    该钩子可能发生在 Area/Body/Shape 查询仍处于 flush 的物理回调内部。
#    V346 此时立即把一个 CharacterBody2D + CollisionShape2D 加入场景树，再立刻 configure 修改 shape，
#    等于在 PhysicsServer 正处理查询时改变物理世界。
# 3) V347 的 `_rpc_spawn_drop()` 不再立即实例化/入树/配置，而只
#    `call_deferred("_spawn_drop_after_physics", config.duplicate(true))`。
#    真正的 DROP_SCENE.instantiate()、add_child()、configure() 在 deferred 阶段统一完成，
#    确保 CharacterBody2D 注册与 CollisionShape2D 尺寸修改都发生在 PhysicsServer 安全阶段。
# 4) 联机 RPC 语义保持 `authority + call_local + reliable`；每一端收到同一 config 后各自延迟生成，
#    不改变掉落 id、种类、起点、速度、反弹、拾取、房产证队伍或同步逻辑。
# 5) V346 的 14/18/22px 掉落尺寸、真实地图边界反弹、0.70s 展示期、房产证按拾取者 Team/Master
#    生成“愤怒的人”、以及 `scenes/characters/小弟/` 分类全部保持。
# 6) 截图中的 `seed` 与 built-in function 同名属于 GDScript warning，不是本次红色 PhysicsServer 错误来源；
#    V347 不为修复领导掉落而批量改动无关脚本。


# -----------------------------------------------------------------------------
# V348 领导回飞 freed-object 报错 / 房产证队伍强制一致 / 掉落视觉平滑
# -----------------------------------------------------------------------------
# 1) 用户实机截图显示 `领导掉落物.gd::_update_return()` 到达领导时调用
#    `owner_leader.call("_on_hostile_drop_arrived", kind, return_picker)`，
#    报 `Object-derived class of argument ... (previously freed) is not a subclass of expected argument class`。
#    原因是 V346~V347 把拾取者以 `return_picker:ball` 保存整段回飞时间；拾取者期间死亡/queue_free 后，
#    typed `picker:ball` 参数在函数体进入前就拒绝这个 freed Object。
# 2) V348 不再保存 return_picker Object，只保存 `return_picker_path:NodePath`。
#    掉落回到领导的那一刻重新 get_node_or_null；拾取者仍存在才传当前 ball，否则传 null。
#    `_on_hostile_drop_arrived()` 参数改为 Variant，并在函数体内安全验证/转为 ball，彻底消除 stale typed Object 报错。
# 3) 房产证生成“愤怒的人”也改为 deferred 入树，避免从掉落物 `_physics_process` 中同步 add_child 一个完整 ball。
#    authority 在拾取瞬间写入 config["team"]；V348 把这份 team snapshot 在 add_child 前写入愤怒的人，
#    即使客户端暂时解析不到 picker_path，也不会回退到场景默认 Team="Ball"。
# 4) `愤怒的人.gd` 新增 `prime_property_deed_identity()` 与 `_enforce_property_deed_identity()`：
#    保存 `_deed_team` / `_deed_picker_path`，每个物理帧检查 Team；拾取者仍存在则跟随其当前 Team，
#    拾取者不存在则继续保持拾取瞬间的 team snapshot。这样网络同步或 ready 时序把 Team 临时改错后也会自动拉回。
# 5) 掉落物“物理根”和“图片视觉”分离：CharacterBody2D 根仍只在 `_physics_process()` 内用 move_and_collide()，
#    `RenderPivot/Visual` 在 `_process()` 中以指数平滑追随物理根位置/旋转，碰撞准确性不变但渲染更顺滑。
#    抛飞时视觉缩放只作用于 RenderPivot，不再缩放 CharacterBody2D 根和碰撞箱。
# 6) 单个 physics tick 的边界碰撞由最多4次 remainder 反弹迭代处理，角落/连续碰撞不再只处理一次后顿一下；
#    arc_duration 到点时也取消旧 `_clamp_to_map(global_position)` 的二次硬钳，避免落地瞬间位置跳变。
# 7) V346 的 14/18/22px 尺寸、地图真实碰撞反弹、0.70s 展示期、小弟分类以及 V347 deferred 掉落生成继续有效。


# -----------------------------------------------------------------------------
# V349 房产证愤怒的人固定阵营 / 原领导死亡后跑路
# -----------------------------------------------------------------------------
# 1) 用户实测 V348 后“愤怒的人”仍偶发被算成敌人。根因找到：
#    V348 `_enforce_property_deed_identity()` 在 picker 存在时会执行
#    `_deed_team = deed_picker.Team`，但项目 ball 基类/网络生成早期会存在 Team 暂时为历史默认 `"Ball"` 的时序。
#    `"Ball"` 非空，因此会把本来正确的房产证 Team 快照反向污染成 `"Ball"`，之后才真正出现偶发错队。
# 2) V349 规定房产证 `config["team"]` 是拾取瞬间的 authority 阵营快照。
#    `_deed_team` 一旦拿到非空且非 `"Ball"` 的有效值后永久保持；后续只重新解析 picker 对象，
#    禁止再用 picker.Team 覆盖快照。只有初始 config 本身没有有效 Team 时，才允许从一个已经有效的 picker.Team 补一次。
# 3) 愤怒的人同时把该快照写入 metadata `forced_combat_team`。
#    `投稿角色工具.gd::effective_team()` 与公共 `classes/hitbox.gd::_effective_team()` 都优先读取这份稳定 Team，
#    所以即使某个网络帧普通 Team 属性再次短暂被同步成默认值，AI 敌我判断和真正 Hitbox 伤害仍不会先误判。
# 4) 愤怒的人自己的 `_is_legal_enemy()` 改用 `SubmissionCharacterTools.same_side()`：
#    作为“小弟”语义，它永远不主动把同主人/同召唤链/同有效 Team 单位当敌人，不再让全局友伤开关污染自己的 AI 目标池。
# 5) 用户要求“召唤它的领导死了以后像面包车召唤的小弟一样逃跑”。
#    V349 在房产证 config 新增 `summoner_leader_path`，它与 `Master` 完全分离：
#    - Master 继续是实际拾取房产证的人，用于队伍/主人身份；
#    - summoner_leader_path 只表示这张房产证来自哪一个领导，用于领导死亡跑路条件。
# 6) authority 每个物理帧检查原领导：health<=0、queue_free、路径已失效任一成立即进入跑路。
#    跑路时立刻停止攻击/拳头动作，Can_Attack/Can_Skill=false，Hitbox 停止监听，
#    CharacterBody2D collision_layer/mask 清0，设置 `submission_allow_map_escape=true`，
#    Speed=190，选择最近地图边界并跑到边界外约80px，真正越出地图后 queue_free。
# 7) 跑路语音复用面包车/黑帮普通小弟的 `res://audio/characters/黑帮老大/跑路了兄弟.mp3`，
#    并共用 `_gang_flee_sfx_last_msec` 650ms 防叠计时，避免多人同时跑路时人声叠加。
# 8) 从 `scenes/characters/小弟/愤怒的人.tscn` 直接选择的独立人物没有 `summoner_leader_path`，
#    因此不会因为不存在领导而自动跑路；只有“领导房产证召唤版本”使用这条生命周期。
# 9) V348 的回飞 freed-object 修复、掉落物 RenderPivot 平滑和 V346 的掉落反弹/小弟分类继续有效。


# -----------------------------------------------------------------------------
# V350 领导掉落改为按本次实际伤害决定概率与数量
# -----------------------------------------------------------------------------
# 1) 用户要求领导掉落和“这一次受到的伤害”直接相关：每次受击都有独立掉落概率，
#    伤害越高，掉落概率越高；一旦成功掉落，伤害越高，本次同时掉出的物品数量也越多。
# 2) V345~V349 的固定 `hit_drop_chance=60%`、`hit_drop_pity_hits=2`、`hit_drop_min_interval=0.12s`
#    机制全部作废。V350 不再累计“几次受伤保底”，也不会因为短时间连续受击跳过某一次掷骰；
#    `on_actual_health_damage_received(actual_health_damage)` 每收到一次真实 health loss 就独立进入一次掉落判定。
# 3) 默认概率参数：
#    - drop_base_chance = 0.18
#    - drop_damage_reference = 80
#    - drop_damage_chance_bonus = 0.72
#    - drop_damage_chance_cap = 0.90
#    概率公式为 `base + bonus * (1 - exp(-damage/reference))`，最后限制到 cap。
#    这是一条饱和曲线：小伤害仍有基础概率，大伤害提升明显，但不会无限超过100%。
#    以默认参数近似：10伤≈26%、25伤≈37%、50伤≈51%、100伤≈69%、200伤≈84%、极高伤趋近90%。
# 4) 默认数量参数：
#    - drop_damage_per_extra_item = 120
#    - drop_max_items_per_hit = 5
#    掉落成功后至少1个；每满120点本次实际伤害稳定多1个，
#    剩余不足120的部分按比例再掷一个额外物品，因此数量随伤害平滑增长。
#    例如50伤成功掉落时为1个并有约42%概率变2个；120伤稳定2个；
#    200伤稳定2个并有约67%概率变3个；240伤稳定3个；最终最多5个。
# 5) “实际伤害”严格使用 ball.health setter 传入的 `actual_health_damage`（真实生命损失），
#    不是攻击面板原始 damage；被护盾/减伤吃掉而没有造成对应生命损失的部分不会虚增掉落率或数量。
# 6) 每个物品仍单独使用原 `coin_weight/car_key_weight/property_deed_weight` 抽种类；
#    V346 的14/18/22px尺寸、真实地图碰撞反弹、V348视觉平滑、V349房产证固定队伍/领导死亡跑路全部保持。
# 7) `_suppress_drop_trigger` 继续阻止领导自己的敌方掉落物回飞反伤递归触发新掉落。


# -----------------------------------------------------------------------------
# V351 数学老师固定发射攻速 / 子弹寿命与下一发完全解耦
# -----------------------------------------------------------------------------
# 1) 用户要求数学老师的攻速固定：真正射出一颗粉笔以后，只等待固定冷却就能射下一颗，
#    无论上一颗粉笔是否仍在地图里、是否还没走到路径终点、是否命中过目标，都不能阻止下一发。
# 2) 旧实现使用公共 ball State.Skill 冷却：
#    - 进入 Skill -> 写完整道伤害公式 -> 发射 -> Using_Skill=false；
#    - 公共 state_machine 只有 Using_Skill=false 后才开始累计 Skill_Cooling。
#    因此真实“发射到发射”间隔会变成 `公式书写时长 + Skill_Cooling`，不同公式长度还会让攻速轻微变化。
#    这与“射出一个子弹，冷却后就可以射出下一个”的要求不符。
# 3) V351 把 `Skill_Cooling` 保留为现有 1.75 秒，但语义改成唯一的“粉笔发射间隔”。
#    `_spawn_formula_projectile()` 真正生成一颗公式弹时立刻把 `_formula_shot_cooldown_remaining = Skill_Cooling`。
#    这个计时在 `tick_physics(delta)` 中独立下降，即使 Using_Skill=true、上一颗粉笔仍存在也照常计时。
# 4) 公共 `Can_Skill` 对数学老师关闭，避免公共状态机再叠一层动作结束后的 Skill_Cooling。
#    AI 由 `数学老师.gd::tick_physics()` 自己调度：上一发射出后的下一物理帧就开始书写下一道公式；
#    公式写完后如果1.75秒还没到，就只等待剩余发射冷却；冷却归零立即发射。
#    当前15类伤害公式的书写时长都低于默认1.75秒，因此连续战斗时发射间隔稳定为1.75秒。
# 5) 公式弹本身的 `projectile_lifetime`、地图外消失、路径终点、穿墙、命中等逻辑完全没有参与冷却判断。
#    V351 不保存“当前活动公式弹”引用，也不查询运行时还有几颗粉笔，所以允许多颗粉笔同时存在于地图中。
# 6) 玩家直接控制新增 `controlled_skill_action()`：右键可以在上一发冷却期间提前开始写下一道公式，
#    但真正发射仍严格等到固定发射冷却归零；玩家若主动晚按，则只会人为降低自己的实际攻速。
# 7) V340~V343 的高级伤害公式、8类轨迹/5类速度、删除轨迹/速度文字、图片范围命中与受击白线，
#    V342 的无视阻挡以及后续所有数学老师音效规则全部保持。


# -----------------------------------------------------------------------------
# V352 数学老师“伤害公式真实计算完毕后才发射”
# -----------------------------------------------------------------------------
# 1) 用户指出 V351 视觉上仍会出现“一边攻击一边计算”，要求当前这发伤害公式完整计算结束后才攻击。
# 2) V351 的顺序表面上是先公式后发射，但实际上 authority 使用
#    `formula.length() * formula_character_interval + formula_hold_after_reveal`
#    估算公式结束时间；真正逐字显示却由 `_rpc_show_formula()` 内的 `call_deferred("_play_formula_visual", ...)`
#    异步启动。deferred 调度、帧率、Timer/RPC 时序都可能让实际显示比估算稍晚，
#    从而出现粉笔已经生成但最后几个字符仍在继续写的视觉竞态。
# 3) V352 删除这条“估算秒数决定发射”的关系。每一道伤害公式由 authority 分配唯一
#    `_formula_sequence_serial`，相同 serial 通过 reliable + call_local RPC 发送到所有客户端。
# 4) authority 本机的 `_play_formula_visual()` 必须真实执行完：
#    - 最后一个字符已显示；
#    - 写字.mp3 已停止；
#    - `formula_hold_after_reveal` 短暂停留已结束；
#    然后才调用 `_mark_formula_visual_finished(serial)`。
# 5) `Skill()` 使用 `_wait_for_formula_calculation_finished(serial)` 等这个真实完成握手；
#    完成以后再 `_wait_for_formula_shot_cooldown()` 检查 V351 的固定发射间隔。
#    因此当前一发的严格顺序变为：
#    `生成伤害公式答案 -> 逐字显示完整公式 -> 短暂停留 -> 公式完成 -> 等剩余发射冷却 -> 生成粉笔`。
# 6) V351 的“上一颗粉笔是否还活着完全不影响下一发”继续有效。
#    上一颗粉笔可以仍在地图里飞；那是上一发已经完成的攻击。
#    下一颗粉笔仍必须等“自己的伤害公式”完整计算完才能生成。
# 7) 固定攻速的含义是最短发射间隔仍为 `Skill_Cooling=1.75s`：
#    如果下一道公式在冷却结束前已经算完，则1.75s到点发射；
#    如果某个未来新增公式本身计算/显示超过1.75s，则绝不会为了追赶攻速而提前射击，而是等公式真的算完再射。
# 8) V340~V351 的高级伤害公式、粉笔轨迹/速度、穿墙、命中白线、音效和多颗粉笔并存规则均不改。


# -----------------------------------------------------------------------------
# V353 愤怒的人拳头/移动与面包车拳头小混混统一
# -----------------------------------------------------------------------------
# 1) 用户要求“愤怒的男人的拳头应该和面包车的拳头混混一样，移动逻辑也一样是正常的”。
# 2) V349~V352 的愤怒的人拳击是自己实现的一套简化版：
#    `Graphics/Fist` 静态 Sprite 跟随人物根 scale，命中只用一条 30.4px 线段 + 目标近似半径判断；
#    同时 tick_physics 每帧主动把 direction 指向最近敌人，因此会表现为专属直追 AI，不是拳头小混混的普通移动。
# 3) V353 删除场景中的 `Graphics/Fist` 静态节点。每次挥拳都和
#    `res://scripts/creatures/投稿随从.gd` 的 VAN_FIST 一样，在世界坐标创建独立 Area2D：
#    - 使用同一 `res://Images/characters/人物/面包车/拳头.png`；
#    - `BitMap.create_from_image_alpha(..., 0.08)` + `opaque_to_polygons(..., 3.0)` 读取 PNG 真实不透明轮廓；
#    - 素材 -90° 手柄方向校正到本地 +X；
#    - 拳头真实长度统一 30.4px；
#    - 12 physics frame，`sin(t*PI)*12.8` 伸出再收回；
#    - Area2D 每物理帧读取 overlapping area/body，同一次挥拳对同一目标只结算一次。
# 4) 拳头击退同步 VAN_FIST：14px / 230 speed / lock_control=true / stop_on_character=true；
#    挥拳和命中继续使用同一面包车拳头声音，音量/可听距离/衰减也完全一致。
#    愤怒的人自己的 Damage=20 仍保留，没有把人物本身伤害强行改成拳头小混混的 Damage=12。
# 5) Attack_Cooling 从0.82调到拳头小混混相同的0.78；近战攻击范围同步41.6。
# 6) 正常战斗移动删除“每帧锁最近敌人并直追”的专属 direction 控制。
#    愤怒的人现在只调用 `ball.gd::tick_physics()` 的公共移动：
#    direction -> ball.move() -> CharacterBody2D.move_and_slide() -> 公共墙体/人物碰撞处理，
#    与拳头小混混/其它普通 ball 角色保持一致。
# 7) 房产证版本的 Team 固定、forced_combat_team、原领导死亡后跑路仍保留；
#    只有进入跑路状态时才像面包车小弟一样主动把 direction 指向最近地图出口。


# -----------------------------------------------------------------------------
# V354 领导敌方拾取掉落物撞回时追加通用碰撞伤害声
# -----------------------------------------------------------------------------
# 1) 用户要求“捡到的掉落物打到领导也要播放碰撞伤害声音”。
# 2) 旧逻辑在金币/车钥匙被敌方拾取并回飞撞到领导时，只播放：
#    - 金币：`res://audio/characters/收债人/金币1.mp3`
#    - 其它物件：`res://audio/characters/面包车/铁棍打人.mp3`
#    然后调用 receive_spatial_damage()，缺少项目统一的“碰撞伤害真正扣血”音效。
# 3) V354 保留上述物品自身撞击声；同时在伤害结算前记录 before_health，
#    receive_spatial_damage() 后计算 actual_health_damage。
#    只有 accepted=true 且 actual_health_damage>0 时，再播放
#    `res://audio/sfx/physics/balls_hit1.sfxr` 作为第二层“领导实际受伤”声音。
# 4) 纯格挡、无敌、伤害被拒绝或没有真实生命损失时，不播放 balls_hit1，避免假受伤反馈。
# 5) balls_hit1 使用独立 AudioStreamPlayer2D 在领导实际撞击位置播放；
#    reliable + call_local RPC 保证联机所有客户端都收到这一层伤害声。
#    独立 player 允许它和金币/物件撞击声同时存在，不会因为同一个播放器 max_polyphony=1 互相截断。
# 6) 音量按真实生命损失缩放：`clamp(actual_health_damage - 12, -18, 0) dB`；
#    小伤较轻、大伤更明显，但不会超过0dB。
# 7) V350 的伤害关联掉落、V348 回飞稳定性、V349 房产证阵营/领导死亡跑路、
#    V353 愤怒的人拳头与正常移动均保持不变。


# -----------------------------------------------------------------------------
# V355 领导处分新增“扔纸”发射音效
# -----------------------------------------------------------------------------
# 1) 用户提供 `DM_20260904003458_001_[cut_0sec].mp3`，要求命名为“扔纸”，作为领导扔出处分文件的声音。
# 2) V355 将原始用户音频保持 MP3 格式并重命名/放入规范角色音频目录：
#    `res://audio/characters/领导/扔纸.mp3`
#    不创建 Audio/Audios/Voices 等历史错误目录。
# 3) `领导.gd` 新增 `DOCUMENT_THROW_SFX` 与 `LeaderAudioCue.DOCUMENT_THROW`。
#    `_spawn_document()` 在真正生成处分文件之前，于领导当前位置播放一次扔纸声。
# 4) “扔纸”只代表发射动作，不替代处分命中声：
#    - 发射处分：`扔纸.mp3`
#    - 处分命中/实际碰撞伤害：继续使用原有 `balls_hit1.sfxr`
# 5) 用户音频约0.36秒，属于很短的动作提示；播放音量设为 +3dB，
#    继续走领导现有 AudioStreamPlayer2D / GameplayRecord / 1350px 位置音频链。
# 6) V354 的回飞掉落物碰撞伤害音、V353 愤怒的人拳头/移动、以及更早累计规则均保持不变。


# -----------------------------------------------------------------------------
# V356 领导高级掉落物爆率降低
# -----------------------------------------------------------------------------
# 1) 用户要求领导高级掉落物更稀有，掉落种类顺序固定为：
#    金币最高 > 车钥匙其次 > 房产证最低。
# 2) V355 及之前默认种类权重为：
#    coin_weight=0.58 / car_key_weight=0.24 / property_deed_weight=0.18。
#    V356 改为：
#    coin_weight=0.78 / car_key_weight=0.17 / property_deed_weight=0.05。
#    三者默认总权重仍为1.0，因此对应默认种类概率就是约78% / 17% / 5%。
# 3) `_roll_drop_kind()` 的累计权重算法不变，只调整权重；金币显著成为主掉落，
#    车钥匙属于较少见高级物品，房产证成为真正稀有掉落。
# 4) V350 的“每次真实受伤独立判定掉落；伤害越高掉落概率越高且单次掉落数量可能增加”完全不改。
#    也就是说高伤害仍可能一次爆出多个物品，但每一个物品都独立按78/17/5选择种类。
# 5) 领导场景显式保存这三个权重，避免旧 Inspector 保存值覆盖脚本默认。
# 6) 房产证召唤、车钥匙/金币回飞、物理反弹、碰撞音效、V355扔纸音效等机制均保持不变。


# -----------------------------------------------------------------------------
# V357 跑刀仔第二命“猛攻哥”9格真实装备 / 跑刀鼠左右修正
# -----------------------------------------------------------------------------
# 1) 用户指出跑刀仔第一命正式图片左右反了。V357 不修改原 PNG 文件，
#    `跑刀仔.gd::_apply_runner_character_texture()` 对 `跑刀鼠.png` 固定 `flip_h=true`，
#    `scenes/characters/三角洲/跑刀仔.tscn` 编辑器默认 Image 也同步 flip_h=true；
#    第二命 `吴彦祖.png` 与直升机绳降临时人物不强制翻转。
# 2) 用户提供 `三角洲.zip` 与独立 `60血.png`。V357 新增规范素材目录：
#    `res://Images/characters/三角洲/跑刀仔/猛攻装备/`
#    并保持用户文件名：250.png、350血包.png、800血包.png、aug.png、awm.png、g18.png、
#    m7.png、psg.png、甲修.png、紫甲.png、红甲.png、蓝甲.png、金甲.png、60血.png。
#    其中 250.png 作为 M250 通用机枪图片。
# 3) V185~V356 的“第一命死亡后按 budget 直接增加 Damage/max_block/Speed/Max_health”作废。
#    第二命购买改为真实 3x3 = 9 格装备系统；所有购买物（枪、护甲、药、甲修、通用备弹）都必须实际塞进九格，
#    并复用保险 `_safe_find_grid_fit()` 的逐格排布/旋转逻辑。最多两把枪。
# 4) 项目内价格（仅跑刀仔 money，不冒充实时交易行）：
#    G18=70、PSG-1=150、AUG=175、M7=230、M250=320、AWM=380；
#    蓝甲=80、紫甲=150、金甲=260、红甲=260；
#    60血=30、350血包=90、800血包=150、甲修=110、通用子弹包60发=45。
# 5) 九格体积：
#    60血=1x1；350血包=1x3；800血包=2x2；甲修=2x2；通用子弹=1x1；
#    G18=1x1；PSG/AUG/M7=2x1；M250/AWM=3x1；四种护甲均2x1。
#    购买顺序会预留最低护甲/备弹预算，优先保证至少一把枪，然后先买一包通用备弹、再买护甲、再尝试第二把枪；
#    剩余空间继续按800血包->甲修->350血包->通用子弹->60血的可放入最高价项填充；没有枪时不会购买无用的通用子弹，
#    直到九格没有空间或剩余钱低于可买物价格。无限钱仍受九格空间限制。
# 6) 护甲直接显示在人物 Graphics 上，且真实控制公共 block：
#    蓝甲90、紫甲160、金甲260护盾；红甲护盾=max(Max_health)。
#    红甲 money 花费与金甲完全相同260，但必须第一命捡到“高级咖啡豆”；购买红甲后消费这份资格材料。
#    红甲后续若 Max_health 被外部 Buff 修改，max_block 跟随新的 Max_health，但不会凭空补满当前 block。
# 7) V218 曾把 `咖啡豆.png` / `子弹零件.png` 从刷新池移除。V357 为装备门槛重新开放为极低概率特殊物资：
#    地面各0.85%独立门槛；保险点名池也加入极低权重。
#    它们不兑换 money：咖啡豆解锁红甲，高级子弹零件解锁 AWM；成功购买对应装备后资格被消费。
# 8) AWM 只有 `has_advanced_ammo_part=true` 才能购买/使用。其它枪无需专属材料。
# 9) 武器弹匣容量/射速/项目基础伤害参考 2026-09 当前《三角洲行动》公开数据：
#    G18 17发/1172RPM/22，AUG 30/679/29，M7 20/649/40，
#    PSG-1 10/300/50，M250 125/550/55，AWM 5/35/100。
#    项目内所有枪共享同一种“通用子弹”备弹池；通用子弹包每格60发。
#    第一发弹匣随枪装满，后续所有换弹都从这一个共享备弹池扣除。
# 10) 最多两把枪的换枪/换弹顺序固定：
#     第一把弹匣打空 -> 如果第二把还有弹立即切第二把；
#     第二把也打空 -> 切回第一把并从共享备弹换弹；
#     之后第一把再次空 -> 切到第二把并给第二把换弹，如此循环。
#     单枪则弹匣空后直接给自己换弹。每把枪都有独立 reload 时间。
# 11) 第二命真正射击使用公共 `res://scenes/shooter/子弹.tscn`，Master/Team 仍属于跑刀仔；
#     每发 Damage 按当前枪基准伤害换算进 `attack_damage()`，继续吃项目统一增伤/减伤 Buff。
#     当前持枪图片显示在人物身旁，并按人物 direction 旋转；用户枪图枪口朝左，因此显示时补 PI 对齐真实射击方向。
#     第二命 `Has_Collision_Damage=false`，不再同时保留旧近战碰撞伤害。
# 12) 血药是真实耐久：60/350/800 的 `remaining` 总和就是该件药最多能恢复的生命总量；
#     每次实际 heal 多少就扣多少耐久，满血会暂停并保留剩余耐久，耐久用尽才消失。
#     默认70%以下开始自动找药；优先用能覆盖当前缺血量的最小血药。
# 13) 甲修每件 `remaining_uses=1`，护甲低于约38%时使用，约0.85s后一次性把 block 修到 max_block，
#     随即消耗该甲修。没有护甲时不会浪费甲修。
# 14) 使用血药、甲修、换弹时会在人物旁边显示完整3x3装备格，实际按购买时排布展示全部未消耗装备，
#     正在使用的格子用浅金色高亮。UI挂 current_scene 世界坐标、绝对高Z。
#     默认显示在人物右侧；若人物靠近左/右/上/下任一地图墙约76px内，
#     UI会自动显示到该墙的反方向，避免被地图边界遮挡。
# 15) V229~V231 的第一命/第二命正式角色图、V230直升机绳降复活、第一命搜刮/保险/BGM、
#     V216~V228 保险3x3搜索等规则继续有效；只替换第二命旧“抽象数值购买”为本装备系统。


# -----------------------------------------------------------------------------
# V358 猛攻哥枪/护甲不占九格 / 删除弹药物品 / 无枪使用匕首
# -----------------------------------------------------------------------------
# 1) 用户纠正 V357：枪和护甲都不应该占人物的3x3九格。
#    V358 将 weapon/armor 定义为“身上装备”：仍计入购买花费、最多两把枪、护甲只装备一件，
#    但 `_berserker_add_packed_item()` 对 weapon/armor 不再调用 `_safe_find_grid_fit()`，
#    不写 grid_pos/grid_size，也不标记 occupied。3x3九格只给血药和甲修。
# 2) 删除“通用子弹”背包道具以及60发备弹池。V358 不存在购买弹药/弹药占格/剩余备弹耗尽。
#    每把枪仍保留自己的弹匣容量和换弹时间；弹匣打空后照旧按双枪规则切枪，
#    需要换弹时等待该枪 reload 秒数后直接补满该枪弹匣。
# 3) 用户说“每个枪的子弹都是和夺舍狼射的一样的子弹”，项目里夺舍狼正式使用
#    `res://scenes/shooter/子弹.tscn`。猛攻哥继续且明确统一使用同一个 PackedScene：
#    `BERSERKER_BULLET_SCENE = preload("res://scenes/shooter/子弹.tscn")`。
#    枪的伤害/射速/弹匣/弹速仍用于各枪差异，但投射物节点、贴图、基础碰撞与夺舍狼完全同源。
# 4) 购买顺序改成“枪绝对第一优先”：不为护甲/血药预留钱，先用当前全部预算购买满足资格的最好枪；
#    然后买最好护甲，再尝试第二把枪，最后用真正的3x3空格购买800血包/甲修/350血包/60血。
# 5) 如果第二命的钱连最便宜G18（70）都买不起，角色不会空手不能攻击，而是使用免费匕首。
#    用户本轮图片正式保存为：
#    `res://Images/characters/三角洲/跑刀仔/猛攻装备/匕首.png`
# 6) 匕首只在“0把枪”时启用，不占格、不花钱。攻击时在世界坐标生成 Area2D，
#    用匕首 PNG alpha (`BitMap.create_from_image_alpha + opaque_to_polygons`) 生成真实碰撞多边形，
#    10个物理帧从-55°挥到+55°，实际刀长约36px；单次挥砍每个目标只结算一次。
#    默认匕首伤害24、范围43、冷却0.72s，并带12px/185的小击退。
# 7) 九格装备UI只显示 heal/repair；枪和护甲继续通过人物身上的枪械Sprite/护甲Sprite显示，
#    换弹时也不再把枪假装成背包格子。
# 8) V357 的60血1格、甲修/800血包2x2、350血包1x3、血药剩余治疗耐久、甲修一次性、
#    红甲需要高级咖啡豆且护盾=Max_health、AWM需要高级子弹零件、最多两把枪、靠墙反向显示九格均保留。


# -----------------------------------------------------------------------------
# V359 跑刀鼠方向纠正 / 第一命死亡后隐藏金钱文字
# -----------------------------------------------------------------------------
# 1) 用户反馈 V357/V358 把第一命跑刀鼠图片左右翻反了。
#    V357 曾显式加入 `sprite.flip_h=(texture_path==RUNNER_FIRST_LIFE_TEXTURE_PATH)`，
#    场景 `跑刀仔.tscn` 也保存了 `Image.flip_h=true`。
#    V359 两处都撤销：第一命跑刀鼠与第二命猛攻哥均保持图片原始左右方向，不做强制水平镜像。
# 2) 用户要求“死了后就不应该有金钱文字”。
#    V359 金钱 Label 只在 `life_index==1 && health>0 && !_revive_airdrop_active` 时 visible=true。
# 3) 第一命 health<=0 后进入 `_prepare_first_life_airdrop()` 的同一时刻立刻刷新并隐藏 MoneyValue；
#    空降动画期间不显示，第二命 `life_index=2` 落地后仍保持隐藏，最终死亡也强制隐藏。
# 4) `money`/`has_infinite_money` 内部数值不会因为隐藏而清零，因为第一命死亡后的
#    `_buy_equipment_and_revive()` 仍必须读取这笔钱来购买 V358 猛攻哥枪、护甲、血药/甲修。
#    所以本轮只删除死亡后的“可视金钱文字”，不破坏装备预算。
# 5) V358 的枪/护甲不占3x3、删除通用子弹物品、所有枪复用夺舍狼 `子弹.tscn`、
#    买不起枪时使用匕首等规则全部保持。


# -----------------------------------------------------------------------------
# V360 跑刀鼠改用 dir_left 纠正朝向 / 猛攻哥双枪摆放
# -----------------------------------------------------------------------------
# 1) 用户明确指出 V359 仍然左右反，并要求“修改它的 dir left 开关”。
#    根因是公共 `classes/ball.gd` 的普通人物朝向不是直接依赖 Sprite2D.flip_h：
#    `ball.move()` 会根据 `dir_left` + effective_direction 计算 desired_flip_h，
#    然后 `set_character_visual_flip_h()` 通过人物 Shader 参数 `sprite_flip_h` 做最终镜像。
#    因此 V359 单纯 `sprite.flip_h=false` 会被下一次公共移动朝向更新覆盖。
# 2) V360 第一命跑刀鼠正式使用 `dir_left=false`，场景也显式保存该值。
#    跑刀鼠原图按“天然朝右”处理：向右不镜像，向左才镜像。
# 3) 第二命切换到吴彦祖/猛攻哥贴图时，`_apply_runner_character_texture()` 自动把 `dir_left=true`，
#    保持第二命此前正常的普通人物朝向。贴图切换当帧还会按当前 direction 立即调用
#    `set_character_visual_flip_h()`，不必等下一次移动才刷新。
# 4) 猛攻哥装备视觉从“只显示当前一把枪”改成同时存在两把枪：
#    - `BerserkerGun`：当前正在使用的枪，固定显示在人物右边 `Vector2(58,8)`；
#      位置不再随 aim 绕人物移动，但枪自身 rotation 仍对准真实射击方向。
#    - `BerserkerBackGun`：另一把非当前枪，z_index=-2，位置 `Vector2(-8,7)`，
#      rotation=-68°，作为接近竖直的斜背枪显示在人物背后。
# 5) 切枪时不绑定“第一把永远手持/第二把永远背着”：
#    当前 active weapon 始终在右侧，另一把始终在背后。
#    因此打空切第二把后，第二把自然进入右手，第一把移动到背后，视觉和实际 active slot 一致。
# 6) 背枪使用与手持枪相同的正式装备图片，但目标显示长度缩小到82%，减少遮挡人物。
# 7) V358~V359 的枪/护甲不占九格、无弹药背包物品、匕首兜底、死亡后隐藏金钱文字等规则保持。


# -----------------------------------------------------------------------------
# V361 猛攻哥护甲缩放 / 药品耐久UI / 枪械属性与AWM绝对伤害
# -----------------------------------------------------------------------------
# 1) 护甲视觉从V360的最长边178px缩小到126px；护盾数值完全不改。
# 2) 血药/甲修使用期间，3x3装备面板强制一直保持 visible=true，直到本次使用真正结束才关闭。
#    血药剩余治疗总量通过10Hz unreliable RPC同步，单机/authority本机则即时刷新。
# 3) 3x3道具品质颜色：
#    - 甲修：红
#    - 60血：绿
#    - 350血包：紫
#    - 800血包：金
#    每个物品实际占格矩形带对应品质色底/边框。
# 4) 每个血药占格矩形右下角显示剩余治疗耐久整数；甲修右下角显示剩余使用次数。
# 5) V357公开枪械数据作废。V361完全按用户描述重做：
#    G18：33发、快射/快换、低伤、中速弹、中幅偏差；
#    AUG：30发、中偏快射/快换、中伤、中偏快弹、小偏差；
#    PSG-1：30发、中偏慢射、中等换弹、高伤、快弹、0偏差；
#    M7：30发、快射/快换、中伤、快弹、0偏差；
#    M250：60发、较快射、慢换、高伤、小偏差；每次停止射击后重新开始的第一发前腰0.34s，
#          连续两发间隔小于0.42s视为同一段连射，不重复前腰；
#    AWM：1发、2.30s中等换弹、极高伤260、快弹1100、0偏差。
# 6) AWM AI瞄准复用军火商狙击枪同类二次方程拦截：
#    |relative + target_velocity*t| = projectile_speed*t，解正的最早拦截时间并预判目标位置。
# 7) AWM仍实例化夺舍狼同一个 `res://scenes/shooter/子弹.tscn`。
#    仅该颗子弹写入 `berserker_raw_health_damage` metadata。
#    `scripts/shooter/子弹.gd` 检测该标记后直接 `target.health -= Damage`，
#    不经过 receive_positional_damage / receive_spatial_damage / take_damage，
#    因而无视护甲block、Damage_reduction以及角色覆写的伤害免疫入口；
#    health setter仍正常负责真正扣血、死亡、第二命等生命周期。
# 8) 当前手持枪枪口始终对准实际瞄准方向。所有源图枪口朝左，所以 rotation=aim.angle()+PI；
#    当aim.x>0时额外 `Sprite2D.flip_v=true`，用上下镜像保持枪身正立，避免180度旋转后整把枪倒置。
# 9) V358枪/甲不占九格、无弹药背包物品、匕首兜底，V360当前枪右侧/第二枪背后规则继续有效。


# -----------------------------------------------------------------------------
# V362 猛攻哥枪械前侧位置 / M250连续射击会话 / 全枪降伤
# -----------------------------------------------------------------------------
# 1) 用户要求手持枪永远在人物前面，而不是V360/V361固定在人物右边。
#    V362根据真实武器瞄准方向维护 `_berserker_gun_front_sign`：
#    aim.x>0 -> 枪在人物右侧 x=+58；aim.x<0 -> 枪在人物左侧 x=-58；
#    纯上下瞄准时保留最近一次左右朝向。枪口rotation仍对准真实目标，
#    `flip_v`规则继续只负责防止枪身视觉完全倒置。
# 2) 护甲Sprite位置从(0,10)下移到(0,22)，并继续使用V361缩小后的126px最长边。
# 3) 用户反馈V361 M250“每一发都像有长前腰”。V361通过“距离上一发时间”临时判断，
#    在状态机/受击/输入间隔下仍可能把连续攻击拆成多段。
# 4) V362改为明确的 M250 连续射击会话：
#    - 第一次射击：session=false -> 0.28s前腰 -> 射出第一发 -> session=true；
#    - session=true 的后续子弹完全不再前腰，只按900RPM正常Attack_Cooling连续射击；
#    - 最后一发后真正停火>=0.28s才结束session；
#    - 换弹开始、眩晕、State.Hurt受击硬直、使用血药/甲修、禁攻、死亡、切枪都会立即结束session；
#    - 下一次重新开始M250射击才重新有一次0.28s前腰。
# 5) 前腰协程支持真正取消：如果0.28s等待期间发生上述中断，
#    `_berserker_m250_windup_active`会被清掉，旧协程醒来后不会补射。
# 6) M250射速从680RPM提高到900RPM，60发与慢换弹规则保持。
# 7) 用户要求全部枪伤害下调、AWM固定200。V362基准伤害：
#    G18 8、AUG 14、PSG-1 24、M7 16、M250 22、AWM 200。
#    其它弹匣、弹速、偏差、AWM预判与AWM绝对生命伤害规则保持V361。


# -----------------------------------------------------------------------------
# V363 猛攻哥全枪提速 / 枪位与人物实际朝向同帧同步
# -----------------------------------------------------------------------------
# 1) 用户反馈V362所有枪仍然太慢，并说明“中等/中偏慢”只是六把枪之间的相对射速，
#    不是要把PSG等武器做成现实意义上的低射速半自动节奏。
# 2) V363保持V362伤害完全不变，只整体提高RPM，并保留相对速度层级：
#    - G18：1800 RPM（最快）
#    - M7：1500 RPM（很快）
#    - M250：1350 RPM（较快，首发前腰后高速持续射击）
#    - AUG：1250 RPM（中偏快）
#    - PSG-1：900 RPM（六枪中相对偏慢，但实战仍是高速连续射击）
#    - AWM：180 RPM；因1发弹匣，实际连续攻击节奏仍主要受2.30s换弹控制。
# 3) Attack_Cooling的最低限制从35ms放宽到25ms，避免1800RPM G18被旧下限硬截断；
#    最终出手时机仍由Godot physics tick离散执行。
# 4) M250前腰从0.28s缩到0.24s，停止射击判定窗口从0.28s缩到0.22s。
#    连射session规则不变：只有重新开始一段射击的第一发前腰，连续子弹不前腰。
# 5) V362枪位按aim.x决定左右，会出现“人物已经转身，但敌人仍在另一边，
#    枪还挂在旧侧”的情况；并且枪位只在_process更新时，公共ball.move()本physics tick刚改完
#    dir_left/Shader朝向后可能要到下个渲染帧才跟上。
# 6) V363枪挂点改为直接读取 `is_character_visual_flipped_h()` + `dir_left` 推导人物实际视觉朝向：
#    人物实际朝左 -> 手持枪x=-58；人物实际朝右 -> x=+58。
#    枪自身rotation仍由真实武器aim控制，所以“挂在哪一侧”和“枪口瞄哪里”彼此独立。
# 7) `跑刀仔.gd::tick_physics()` 现在在 `super.tick_physics()` 后同一个physics tick
#    立即再次 `_update_berserker_equipment_visual_transform()`：
#    公共move刚更新完Shader人物朝向，枪马上读取新朝向换边，不等待下一次_process。
# 8) V362全枪降伤（G18 8 / AUG14 / PSG24 / M7 16 / M250 22 / AWM200）、
#    AWM绝对生命伤害/预判、护甲位置、药品UI、第二把背枪等规则全部保留。


# -----------------------------------------------------------------------------
# V364 猛攻哥六枪使用用户提供的正式枪声音效
# -----------------------------------------------------------------------------
# 1) 用户本轮提供六段枪声音效：
#    - 250.mp4 -> `res://audio/characters/三角洲/跑刀仔/猛攻枪声/250.mp3`
#    - aug.mp4 -> `.../aug.mp3`
#    - g18.mp4 -> `.../g18.mp3`
#    - m7.mp4 -> `.../m7.mp3`
#    - psg.mp4 -> `.../psg.mp3`
#    - DM_20260904052700_001.mp3 -> 正式命名 `.../awm.mp3`
#    五个MP4只抽取原音轨并转MP3，不保留视频，不做降噪/音色替换。
# 2) 素材时长静态检查约：
#    250=13.64s / AUG=4.23s / G18=1.33s /
#    M7=6.22s / PSG=1.52s / AWM=2.25s。
# 3) 用户明确要求除PSG和AWM以外全部“循环播放”：
#    G18、AUG、M7、M250第一次真正射出子弹时启动对应AudioStreamPlayer2D，
#    MP3 duplicate设置 `loop=true`；后续每一颗子弹只刷新last_shot时间，不会重新从头触发录音。
# 4) 连续枪声停止条件：
#    - 真正停止射击超过约3个当前武器正常射击间隔；
#    - 换弹开始；
#    - 眩晕/State.Hurt受击硬直；
#    - 切枪；
#    - 使用血药/甲修；
#    - is_damage_output_disabled；
#    - 死亡/离开场景树。
#    这些明确中断会立即stop，避免枪已经停了但录音继续响。
# 5) PSG-1与AWM严格按“每射一发子弹播放一次”：
#    `_fire_berserker_weapon()`真正实例化子弹以后才发送单发音频RPC。
#    每一发创建独立AudioStreamPlayer2D，因此PSG高速连射时允许单发尾音重叠，
#    不会用新一发硬截断上一发。
# 6) 联机：循环开始/停止用authority reliable + call_local RPC；PSG/AWM单发用unreliable + call_local RPC。
#    声音播放器均使用GameplayRecord（存在时）与2D距离衰减。
# 7) V363的全枪射速、V362伤害、M250首发前腰session、AWM预判/绝对生命伤害、
#    枪位转向同步、药品UI、护甲等规则不改。


# -----------------------------------------------------------------------------
# V365 猛攻哥真实独立RPM / 正式枪声强制可听 / 移除公共发射状态声音
# -----------------------------------------------------------------------------
# 1) 用户实测V364“射速完全没看见改变”。根因不是V363 RPM表没写进去，而是第二命仍依赖
#    公共 StateMachine：last_state_dis.Attack >= Attack_Cooling -> State.Attack -> Attack() -> Stand。
#    每颗子弹都必须经历公共状态切换；高RPM时实际节奏会被physics tick和状态往返量化，
#    RPM数值与真正子弹生成间隔没有形成一条独立、直接的时钟。
# 2) V365第二命永久 `Can_Attack=false`，禁止自动进入公共 State.Attack。
#    这同时保证 ball.gd::transition_state(State.Attack) 不会为猛攻枪械播放任何公共 Unique_Attack_Audio。
# 3) 新增 `_berserker_fire_cooldown_remaining`：
#    - authority physics tick直接 `-= delta`；
#    - AI冷却<=0就直接 `_try_berserker_fire_now()`；
#    - 成功发射后按 `60/rpm` 加回下一发间隔；
#    - 使用 `+= interval` 而不是 `= interval`，保留本帧的负余量，避免0.04s间隔在60Hz下永远被取整成0.05s。
#    因此长期平均子弹生成率会真正逼近武器RPM，而不是公共Attack状态频率。
# 4) 玩家直接控制新增 `controlled_attack_action()`，同样绕过公共Can_Attack/State.Attack。
# 5) M250规则继续保持：每段第一发0.24s前腰；前腰成功射出第一发后，
#    再按M250的1350RPM独立时钟调度后续连射；换弹/眩晕/硬直/切枪等继续结束session。
# 6) 用户实测V364“完全没听到对应枪声”。V364通过字符串path运行时load。
#    V365改为六个 `preload()` 常量，使Godot在脚本解析/资源依赖阶段就明确加载：
#    g18.mp3 / aug.mp3 / psg.mp3 / m7.mp3 / 250.mp3 / awm.mp3。
# 7) G18/AUG/M7/M250仍是MP3 duplicate后 `AudioStreamMP3.loop=true`，一段连续射击只启动一次，
#    停火/换弹/眩晕/切枪/用药/死亡时stop；每颗子弹不重启录音。
# 8) PSG/AWM仍是每颗真正生成的子弹播放一次完整单发音效。
# 9) 为排除项目AudioListener2D/距离衰减导致“文件存在但听不到”，V365正式枪声改用
#    非定位 `AudioStreamPlayer`：循环枪声+2dB，PSG单发+5dB，AWM单发+3dB。
#    命中/撞墙声音仍由通用 `子弹.gd` 自己负责，和“发射枪声”分开。
# 10) V363射速表、V362伤害、AWM200绝对生命伤害、枪位/护甲/药品等其它规则不改。


# -----------------------------------------------------------------------------
# V366 猛攻哥切枪动画 / 枪口平滑跟随 / 子弹严格沿枪管方向 / 再降伤
# -----------------------------------------------------------------------------
# 1) 用户反馈V365伤害仍然太高。V366进一步按高RPM重新压低单发伤害：
#    G18=2 / AUG=4 / PSG-1=8 / M7=4 / M250=7 / AWM=120。
#    AWM仍远高于其它枪，并继续无视护甲/减伤/普通免疫；其它RPM/弹匣/换弹不改。
# 2) 护甲Sprite从V362的 y=22 继续下移到 y=30，尺寸仍为V361缩小后的126px最长边。
# 3) 新增每枪“枪口跟随速度”：
#    G18=900°/s（最快）；
#    M250=240°/s（最慢）；
#    PSG-1=420°/s（中等）；
#    AUG=620°/s、M7=680°/s、AWM=560°/s（中等偏上）。
# 4) `_berserker_weapon_attack_direction()` 现在只提供“希望瞄向哪里”的desired方向。
#    `_tick_berserker_gun_aim(delta)` 用wrapf最短角+最大角速度逐帧移动 `_berserker_gun_aim_angle`，
#    不允许枪瞬间吸到敌人方向。
# 5) `_try_berserker_fire_now()` 与M250首发前腰结束后的真正发射均改为
#    `_berserker_current_gun_direction()`；也就是说子弹始终沿“枪此刻真实指向”的方向生成。
#    目标突然横移时，如果枪口还没跟过去，子弹就会按落后的枪口角度射出。
# 6) AWM的预测只决定desired aim point；枪口仍需按AWM自己的560°/s逐渐转向预测点，
#    不再出现预测位置一变化枪立刻瞬移到新角度。
# 7) 切枪动画V366：
#    - duration=0.32s；
#    - 新切出的手持枪枪口从“真实aim再向下压28°”开始，随后抬回真实aim；
#    - 使用 cubic ease-out `1-(1-t)^3`，视觉节奏为开始快、结束慢；
#    - 动画期间 `_berserker_switch_animation_active=true`，`_try_berserker_fire_now()`直接拒绝攻击；
#      必须动画完成后才能射出第一发。
# 8) 被切换掉的旧枪刷新为BerserkerBackGun后，不会瞬间出现在最终背枪位置：
#    从(-8,-20)较高位置、-48°开始，用同一ease-out移动到正常(-8,7)、-68°斜背姿态。
# 9) `_rpc_set_berserker_active_weapon()` 在所有客户端记录old/new slot并启动同一切枪动画；
#    authority额外受到攻击锁，客户端只负责视觉同步。
# 10) V365独立RPM与正式枪声、V364枪声素材、V363枪位跟人物朝向、V361药品UI等规则继续保留。


# -----------------------------------------------------------------------------
# V367 猛攻哥射速轻微回调 / PSG单发伤害小幅提高
# -----------------------------------------------------------------------------
# 1) 用户反馈V366射速“现在快了点”，因此本轮不再大幅调整系统，
#    只对六把枪目标RPM做轻微回调，让整体仍明显快于V362，但比V366稍稳：
#    G18 1800 -> 1650
#    M7 1500 -> 1380
#    M250 1350 -> 1250
#    AUG 1250 -> 1150
#    PSG-1 900 -> 840
#    AWM 180 -> 170（实际持续节奏仍主要受1发弹匣+2.30s换弹限制）
# 2) 相对射速顺序保持：
#    G18最快 > M7 > M250 > AUG > PSG；AWM为单发狙击。
# 3) PSG-1伤害从8提高到10，只做小幅增强；其30发弹匣、0偏差、900弹速、
#    420°/s中等枪口跟随和中等换弹都不改。
# 4) V365独立RPM时钟继续使用 `_berserker_fire_cooldown_remaining += 60/rpm` 的负余量累计，
#    本轮没有恢复公共State.Attack控速，因此RPM调整仍会真实反映到子弹生成节奏。
# 5) V366的切枪0.32s ease-out动画、动画完成前禁攻、枪口平滑跟随、
#    子弹严格沿当前枪管方向、护甲y=30，以及其它伤害数值均保持不变。


# -----------------------------------------------------------------------------
# V368 AWM大击退 / 更长换弹 / 军火商同款狙击红线 / 护甲继续下移
# -----------------------------------------------------------------------------
# 1) 用户要求AWM有“大击退”。项目军火商狙击枪当前基准为92px / 860speed；
#    V368让猛攻哥AWM更强：knockback_distance=145、knockback_speed=1150。
# 2) AWM仍走V361的“绝对生命伤害”特殊分支；V368在该分支真实扣血成功后，
#    `scripts/shooter/子弹.gd` 从 projectile metadata读取击退参数并调用 `target.apply_knockback()`。
#    使用 direction 作为击退方向，lock_control=true、stop_on_character=true。
#    其它角色复用同一个 `res://scenes/shooter/子弹.tscn` 时没有这些metadata，因此不会获得AWM击退。
# 3) AWM换弹从2.30s增加到3.40s；1发弹匣、120伤害、1100弹速、0偏差、
#    560°/s枪口跟随、移动预判以及无视护甲/减伤/普通免疫保持不变。
# 4) 用户再次反馈护甲仍高。BerserkerArmor位置从V366的(0,30)下移到(0,42)；
#    最长边仍为126px，不改护盾数值。
# 5) AWM新增红色瞄准线，参数直接参考军火商
#    `res://scenes/creatures/军火商_枪.tscn::SniperAimLine`：
#    width=1.4、default_color=(1,0.12,0.08,0.78)、圆形首尾端帽、antialiased=true。
# 6) 红线视觉逻辑也参考军火商：
#    - 当前不是AWM/没有目标时隐藏；
#    - AI时用AWM二次方程预判点决定线长，玩家控制时用鼠标瞄准点；
#    - 长度最多440px（军火商狙击gun_range同值）；
#    - 起点使用16*0.72的枪口偏移；
#    - pulse=`0.68 + sin(Time.get_ticks_msec()*0.010)*0.16`，
#      alpha夹在0.45~0.90，与军火商狙击线同样轻微呼吸。
# 7) 红线的角度不直接瞬间指向敌人，而是严格读取 `_berserker_current_gun_direction()`。
#    所以V366的慢速枪口跟随仍然是真实视觉：枪没转到目标，红线也没转到目标；
#    子弹继续沿同一当前枪管方向射出。
# 8) 红线用动态Line2D并set_as_top_level(true)，避免继承角色/Graphics缩放；
#    仍作为跑刀仔节点的子节点，因此角色死亡/释放时自动清理。


# -----------------------------------------------------------------------------
# V369 猛攻哥护甲改为真正ball原生护盾 / 新增独立随机装备猛攻哥
# -----------------------------------------------------------------------------
# 1) 用户实测猛攻哥护甲只有图片，没有真正护盾，并明确要求使用 ball 自带护盾。
#    根因在 `scripts/world.gd::set_ball_properties_to_dafault()`：
#    World每个physics tick都会遍历 `ball.default_properties` 恢复 max_block 等基础属性。
# 2) 跑刀仔初始max_block=0，所以ball._ready()记录的default_properties["max_block"]也是0。
#    V357~V368穿甲只运行时改 `max_block=护甲值; block=max_block`，没有改default_properties，
#    导致下一physics tick max_block立刻被公共World恢复回0。
# 3) V369新增 `_set_berserker_native_ball_shield()`，穿甲时同时维护：
#    `default_properties["max_block"]`、`max_block`、`block`。
#    这不是新护甲HP系统，而是直接使用ball.gd原生block/max_block。
#    普通伤害继续由 `ball.take_damage()` 原生逻辑优先扣block。
# 4) 蓝甲90、紫甲160、金甲260保持；红甲max_block仍等于Max_health。
#    红甲跟随生命上限变化时会同步default max_block，但不会免费回满已损失block。
# 5) 甲修继续 `block=max_block`，现在修的就是ball原生护盾。
#    AWM仍按旧要求属于绝对生命伤害，明确绕过护甲/block；其它普通伤害受block保护。
# 6) 新增可独立选择角色 `res://scenes/characters/三角洲/猛攻哥.tscn`。
#    World已有DirAccess动态扫描三角洲目录，无需修改world.gd硬编码注册。
# 7) 猛攻哥.tscn继承跑刀仔.tscn，只保存standalone_berserker=true、吴彦祖贴图/朝向/标签；
#    所有枪械、护甲、药品、九格、切枪、枪声、AWM红线仍只有跑刀仔.gd一个实现源。
# 8) 独立猛攻哥跳过第一命、金钱UI、物资/保险、第一命音乐和直升机复活，直接life_index=2出生。
# 9) authority每次生成独立猛攻哥时随机：
#    - 1~2把不重复枪：G18/AUG/PSG-1/M7/M250/AWM；
#    - 必有1件随机甲：蓝/紫/金/红；
#    - 随机2~6件60血/350血/800血/甲修，仍严格3x3九格排布。
#    独立角色没有第一命捡材料的阶段，所以随机池允许直接抽到AWM/红甲。
# 10) get_preview_texture() 按standalone_berserker切换：跑刀仔预览跑刀鼠，猛攻哥预览吴彦祖。


# -----------------------------------------------------------------------------
# V370 猛攻哥提亮 / 物品栏直接复用保险九格 / 用药完整收枪与人物物品显示
# -----------------------------------------------------------------------------
# 1) 猛攻形态使用现有Set_RGB_Color Shader，default_color=WHITE、
#    defualt_color_mix=0.18，仅提亮吴彦祖/猛攻哥；跑刀鼠保持0混合。
# 2) 猛攻哥9格直接调用跑刀鼠保险 `_make_safe_search_panel(cell)`，不再维护第二套底板。
# 3) 药品品质背景直接调用保险 `_make_safe_quality_background()`：
#    60血绿、350血紫、800血金、甲修红，使用保险同款渐变。
# 4) 正在使用格额外叠22%白色填充和1.65px白色描边。
# 5) 右下角显示剩余耐久；血药remaining随真实治疗持续下降，V361 10Hz同步继续保留。
# 6) 使用期间9格一直开启；新增BerserkerUsedItem把正在使用的药/甲修显示在人物身上。
# 7) 使用期间所有枪收背后：当前枪偏右(13,7,-64°)，备用枪偏左(-13,7,-116°)，都z=-2；
#    AWM红线同时隐藏，攻击继续由using_item锁住。
# 8) 使用结束后先隐藏物品/关闭九格，再重新启动V366切出枪动画，动画完成以后才恢复攻击。


# -----------------------------------------------------------------------------
# V371 V370保险九格高亮层Node2D类型修复
# -----------------------------------------------------------------------------
# 1) 用户截图运行时报错：
#    `Trying to assign value of type 'Node2D' to a variable of type 'Polygon2D'.`
#    位置在 `_ensure_berserker_inventory_visual()`：
#    V370创建 `highlight:=Node2D.new()`，随后赋给 `_berserker_inventory_highlight`。
# 2) 根因是成员声明仍残留V357/V361旧实现：
#    `_berserker_inventory_highlight:Polygon2D=null`。
#    V370为了让“正在使用格子”同时拥有白色半透明填充和白色Line2D描边，
#    已经把highlight改成容器Node2D，因此旧静态类型不兼容。
# 3) V371把成员声明改为：
#    `_berserker_inventory_highlight:Node2D=null`。
#    这样容器下可以同时挂：
#    - white_fill: Polygon2D
#    - white_border: Line2D
#    并继续统一控制visible/queue_free children。
# 4) 本轮不改变V370视觉和战斗规则：
#    - 九格底板仍直接复用跑刀鼠保险 `_make_safe_search_panel()`；
#    - 品质背景仍复用 `_make_safe_quality_background()`；
#    - 使用格仍白色提亮+白色描边；
#    - 右下角耐久仍实时下降；
#    - 用药时两把枪仍全部挂背后，药品显示在人物身上；
#    - 用完仍播放切出枪动画后才恢复攻击；
#    - V369 ball原生block/max_block护盾逻辑保持。


# -----------------------------------------------------------------------------
# V372 猛攻哥亮度回调 / 切枪动画根因修复 / 枪位与人物朝向统一
# -----------------------------------------------------------------------------
# 1) 用户反馈V370/V371猛攻哥“太白”。第二命Shader白色混合从18%降到8%：
#    `defualt_color_mix=0.08`。仍然只作用于猛攻哥，不修改吴彦祖PNG，不影响跑刀鼠。
# 2) 用户反馈“完全没有之前要求的切枪动画”。根因确认在
#    `_handle_empty_berserker_weapon()`：
#    V366~V371在 `_call_berserker_weapon_switch(other_slot)` 前就先执行了
#    `_berserker_active_weapon_slot=other_slot`。
# 3) `_rpc_set_berserker_active_weapon()` 本来会先读取old_slot，再计算new_slot，
#    只有old_slot!=new_slot才启动 `_begin_berserker_weapon_switch_animation()`。
#    因为旧代码已经提前把槽位改成new，RPC里old==new，动画条件永远不成立。
# 4) V372删除RPC前的提前slot赋值。现在自动打空切第二把时：
#    old slot保持旧枪 -> RPC切到new slot -> old!=new -> 正常启动切枪动画。
# 5) 为提高可读性，切枪视觉稍微加强但保持原规则：
#    duration 0.32s -> 0.40s；
#    新枪起始下压 28° -> 36°；
#    旧枪背枪起始位置 y=-20 -> -28，起始角 -48° -> -42°；
#    仍使用 cubic ease-out `1-(1-t)^3`，开始快、结束慢；
#    `_berserker_switch_animation_active`期间仍禁止攻击。
# 6) 用户反馈“枪位置反了”。V363~V371通过 `is_character_visual_flipped_h()+dir_left`
#    反推人物方向，但吴彦祖源图/Shader的视觉语义与这层反推并不可靠。
# 7) V372新增 `_berserker_character_facing_sign`：
#    - 有水平移动：move.x>0记为+1(朝右)，move.x<0记为-1(朝左)；
#    - 停止移动：保持最后一次左右朝向；
#    - 玩家控制使用player_control_direction，AI使用direction。
#    这与公共ball.move()决定人物转向使用的是同一份有效移动方向。
# 8) 手持枪位置现在只读取这个sign：
#    朝左 -> x=-58；朝右 -> x=+58。
#    因此人物转向的同一physics tick，枪也在对应一侧，不再用Shader flip推断。
# 9) 用户要求“没有敌人的时候默认朝向也是人物朝向”。
#    `_tick_berserker_gun_aim()`在没有敌人/没有玩家瞄准时，
#    立即把真实枪口角重置到人物最后朝向，不再慢慢保留上一名敌人的旧角度。
# 10) 有敌人时V366的每枪平滑瞄准速度继续有效；子弹仍严格沿当前真实枪管方向射出。
#     V370保险九格/用药收枪、V369原生ball护盾、V368 AWM红线等规则保持。


# -----------------------------------------------------------------------------
# V373 猛攻哥人物图片左右朝向修复
# -----------------------------------------------------------------------------
# 1) 用户实测V372猛攻哥人物图片左右完全反了。
# 2) 根因：V360起第二命被设为 `dir_left=true`，等价于把吴彦祖/猛攻哥原图解释成“默认朝左”。
#    但实际猛攻哥原图应和跑刀鼠一样按“默认朝右”处理。
# 3) V373在 `_apply_runner_character_texture()` 中统一使用 `dir_left=false`：
#    - 人物向右：不镜像原图；
#    - 人物向左：公共ball Shader执行水平镜像。
# 4) 猛攻哥无移动时的 `_berserker_character_facing_sign` 初始值由-1改为+1，
#    所以刚出生且没有敌人/没有移动时，人物和枪都默认朝右。
# 5) `res://scenes/characters/三角洲/猛攻哥.tscn` 的 `dir_left=true` 同步改为false，
#    避免独立猛攻哥实例化到脚本_ready之前的初始帧也是反向。
# 6) V372已有规则继续保持：
#    人物真正向左时facing_sign=-1，枪位x=-58；向右时facing_sign=+1，枪位x=+58；
#    无敌人时枪口默认朝人物方向；有敌人时再按各枪转向速度平滑追踪。
# 7) 本轮不改射速、伤害、切枪动画、保险九格、用药收枪、原生block护盾、AWM红线等其它规则。


# -----------------------------------------------------------------------------
# V374 手持枪继续前移 / 护甲随人物朝向水平翻转
# -----------------------------------------------------------------------------
# 1) 用户要求手持枪继续往人物前方移动。
#    V373手持枪水平挂点为±58；V374改为常量 `BERSERKER_HAND_GUN_FRONT_X=70`：
#    人物朝左 -> 枪x=-70；人物朝右 -> 枪x=+70。
# 2) 用户反馈护甲没有随人物朝向改变，并说明护甲原图目前默认朝左。
# 3) BerserkerArmor是独立Sprite2D，不会自动继承人物Image节点Shader里的水平镜像，
#    因此V374明确单独控制护甲Sprite2D.flip_h：
#    - 人物朝左（facing_sign<0）：armor.flip_h=false，保持原图朝左；
#    - 人物朝右（facing_sign>0）：armor.flip_h=true，把朝左原图水平翻到朝右。
# 4) `_refresh_berserker_equipment_visuals()` 刚加载/换护甲时立即同步一次flip，
#    `_update_berserker_equipment_visual_transform()` 后续每次视觉刷新持续同步，
#    避免人物转向后护甲仍留在旧方向。
# 5) 本轮不修改护甲y=42位置、护盾block数值、人物dir_left、枪口瞄准、
#    切枪动画、保险九格、用药收枪、AWM等其它规则。


# -----------------------------------------------------------------------------
# V375 手持枪继续前移
# -----------------------------------------------------------------------------
# 1) 用户要求枪再往前一点。
# 2) V374手持枪前侧水平距离为70；V375保持同样递进幅度，改为82：
#    - 人物朝左：手持枪 x=-82；
#    - 人物朝右：手持枪 x=+82。
# 3) 只调整手持枪相对人物的本地X挂点，不修改：
#    - 枪口当前瞄准角；
#    - 子弹沿枪管方向发射；
#    - 各枪平滑跟随速度；
#    - 0.40s切枪动画；
#    - 用药时双枪背后位置；
#    - 护甲位置与护甲朝向翻转；
#    - AWM红线、原生block护盾、保险九格等其它规则。


# -----------------------------------------------------------------------------
# V376 350血包横向 / 耐久数字锁格内 / 猛攻哥前方180°攻击限制
# -----------------------------------------------------------------------------
# 1) 用户反馈350血包被竖起来。素材 `350血包.png` 本身是横向3:1，
#    此前定义 `grid=Vector2i(1,3)` + allow_rotate=true 会产生竖向占格/旋转显示。
# 2) V376把用户原先“1x3”按“1行×3列”落实到Godot坐标：
#    `grid=Vector2i(3,1)`，并为350血包写入 `allow_rotate=false`。
#    `_berserker_definition_for_consumable()` 不再强制所有药 `allow_rotate=true`，
#    而是尊重每个药品自己的定义，因此350血包始终保持原图片正常横向角度。
# 3) 用户反馈药品右下角数字跑出对应格子。旧版使用固定偏移
#    `center + (size*cell/2 - 22.5/-12)`，对于16px的1格物品会让Label左边越过格子边界。
# 4) V376改成先计算物品真实占格矩形：
#    occupied_width=size.x*cell、occupied_height=size.y*cell，
#    再根据该矩形的right/bottom减去1px margin和Label自身宽高，
#    所以60血1格、350血3格横排、800/甲修2x2的数字都会完整留在各自右下角内部。
# 5) 用户要求猛攻哥只有敌人在“人物前方180°范围”时才可攻击。
#    V376新增 `_berserker_direction_is_in_front_180()`：
#    facing使用V372已有 `_berserker_character_facing_sign`（左/右）；
#    `facing.normalized().dot(target_direction.normalized()) >= 0` 才算前方。
#    这表示目标与人物面朝方向夹角最多±90°，合计正前方180°半平面。
# 6) 前方180°规则同时用于：
#    - 无枪/匕首 `_berserker_attack_direction()`；
#    - 所有枪 `_berserker_weapon_attack_direction()`；
#    - AWM瞄准红线 `_berserker_awm_aim_target_point()`。
#    身后目标不会被枪追踪、不会出现AWM红线，也不会触发攻击；
#    人物移动/转身把该目标纳入前半圆后才恢复瞄准和攻击。
# 7) 玩家直接控制仍尊重手动鼠标瞄准，不把“敌人在前方”的AI索敌限制强行套到玩家输入上。
# 8) V375枪位x=±82、V374护甲翻转、V372切枪动画、V370保险九格、
#    V369原生ball护盾等其它规则全部保持。

# -----------------------------------------------------------------------------
# V377 菜月昴死亡回归兔子重复重建修复
# -----------------------------------------------------------------------------
# 1) 用户实测：场上兔子长期维持3只，多余兔子会被敌人打死；菜月昴死亡回归后偶尔直接出现4只兔子。
# 2) 根因确认在 `死亡回归时间轴.gd::_recreate_node_from_state()` 的实例化顺序：
#    旧实现 PackedScene.instantiate() 后先 add_child()，兔子的 `_ready()` 会立即按场景默认
#    `spawn_initial_pair=true` 执行，并 call_deferred("_spawn_initial_partner")；时间轴随后才通过
#    `_apply_node_state()` 写回历史 `_initial_pair_spawned/spawn_initial_pair/is_baby`。
#    因为伙伴生成已经进入 deferred 队列，后写回历史变量无法撤销，所以“目标快照3只”可能恢复成4只。
# 3) 这也是问题只偶发的原因：只有目标快照中的兔子在当前时间线已经死亡、需要重新 instantiate 时才走重建；
#    当前仍存活的兔子只做状态写回，不会再次触发 `_ready()` 的初始双兔逻辑。
# 4) V377给死亡回归重建新增可选入树前钩子 `prepare_death_return_recreate(state)`。
#    时间轴在 `add_child()` 之前调用；没有实现该方法的其它角色/临时对象完全沿用原恢复流程。
# 5) `兔子.gd` 实现该钩子：入树前先恢复历史 `Team/direction/is_baby`，并临时
#    `spawn_initial_pair=false`、`_initial_pair_spawned=true`，确保回归重建绝不会再次自动补第二只兔子。
#    `_ready()` 的初始双兔条件再增加 `not has_meta("v323_rewind_recreating")` 作为第二层硬保险。
# 6) 时间轴完成 `_apply_node_state()` 后移除临时 `v323_rewind_recreating` metadata；
#    历史中的 spawn_initial_pair/_initial_pair_spawned 等正式值仍会完整写回，因此普通繁殖规则不被永久修改。
# 7) 对历史幼兔，`is_baby` 在 add_child() 前恢复，使其 `_ready()` 按幼兔贴图/生命/缩放初始化；
#    回归重建时重新开始一次成长计时，避免旧版“幼兔先按成年兔_ready，再事后只改is_baby”的错误状态。
# 8) 不修改兔子的 max_rabbits_per_team、碰撞繁殖条件、繁殖冷却、成长数值，也不通过强制删除第4只来掩盖问题；
#    修复点是死亡回归恢复存在性的实例化副作用，目标快照有几只就只重建到几只。

# -----------------------------------------------------------------------------
# V378 导出版本中文被英文覆盖 / 翻译资源导出安全修复
# -----------------------------------------------------------------------------
# 1) 用户反馈：编辑器/项目内语言设置为中文，但导出后的程序里很多原本中文的 UI 会变成英文。
# 2) 根因一：`Game.load_runtime_translations()` 过去直接用 FileAccess 读取
#    `res://translations.csv`。Godot 的导入资源在编辑器里保留原始源文件，但导出 PCK 时
#    原始 CSV 不保证继续存在；官方明确建议导出后不要依赖 FileAccess 访问被导入资源原文件。
#    因此编辑器可以建立 `_translation_table`，导出版本却可能在启动时找不到 CSV。
# 3) V378新增 `res://global/translation_catalog.gd`：
#    它是由当前 `translations.csv` 生成的编译期中/英文翻译镜像，随 GDScript 依赖一起进入导出包。
#    `translations.csv` 仍是人工维护的权威源；以后新增/修改翻译时同步再生成 catalog。
# 4) `Game._init()` 现在在节点进入 SceneTree 之前执行 `_bootstrap_localization_before_tree()`：
#    - 默认中文；
#    - 立即读取 user://settings.cfg 中已保存的 ui/locale；
#    - 同步读取 Only_In_Game_Translation；
#    - 安装编译翻译表；
#    - 在任何 Control 首帧自动翻译之前调用 `_apply_translation_server_locale()`。
# 5) V132旧逻辑只在 `_enter_tree()` 无条件写 `TranslationServer.set_locale("zh")`，
#    仍存在“翻译表尚未安装/导出 CSV 不存在”的空窗。V378把 `_enter_tree()` 改为重申
#    `_init()` 已恢复的真实 UI locale，不再制造一次错误首帧。
# 6) `_ready()` 仍会调用 `load_runtime_translations()`：
#    - 编辑器或明确保留原始 CSV 的导出包：继续直接解析最新 translations.csv；
#    - 导出 PCK 中没有原始 CSV / CSV 无法打开 / CSV 为空或格式损坏：自动退回编译翻译表，
#      不再让 `_translation_table` 为空。
# 7) `translations.csv` 本轮按 Godot 官方 CSV 翻译要求重新保存为 UTF-8 无 BOM；
#    不改任何 key、中文、英文内容，只去掉文件头 BOM并触发正常重新导入。
# 8) 不修改玩家当前语言选择逻辑：中文仍为 zh，English 仍为 en；
#    “仅局内翻译”规则保持原意，多人房间也继续使用每台机器自己的本地语言。


# -----------------------------------------------------------------------------
# V379 大量人物 / 多人同步性能优化（不改玩法数值）
# -----------------------------------------------------------------------------
# 1) 用户反馈：人物数量增加后明显卡顿，并且多人模式比单人更容易卡。
# 2) 审计确认 `res://scenes/ball.tscn` 的 MultiplayerSynchronizer 过去有 6 个
#    REPLICATION_MODE_ALWAYS 属性：AnimatedSprite2D.frame、animation、Ball.global_position、
#    Graphics.global_position、Image.global_position、AnimatedSprite2D.global_position。
#    Godot 的 ALWAYS 会持续发送；Synchronizer 的 replication_interval/delta_interval 默认为0时
#    会在每个网络处理帧检查/同步。角色数和远端Peer数增加时，这部分成本按“角色×Peer”放大。
# 3) V379把角色同步改为：
#    - Ball.global_position 保持 ALWAYS，继续作为权威真实位置；
#    - Graphics.global_position 改成 Graphics.position + ALWAYS，只同步眩晕等真实局部视觉偏移，
#      不再把父 Ball 的世界位移重复编码一次；
#    - Image.global_position、AnimatedSprite2D.global_position 改为 NEVER，二者本来就是
#      Graphics 子节点，世界位置可由父级变换+自身局部变换直接推导；
#    - AnimatedSprite2D.animation 从 ALWAYS 改成 ON_CHANGE，动画名只有真正切动画时才发送；
#    - AnimatedSprite2D.frame 继续 ALWAYS，避免远端动画帧机制改变。
# 4) MultiplayerSynchronizer 新增 replication_interval=1/30、delta_interval=1/30：
#    连续位置/动画帧最高约30Hz；其它 ON_CHANGE 属性也按约30Hz合并检查/发送。
#    这不会降低服务器权威物理频率、攻击判定频率、AI频率或本地渲染FPS，只降低网络复制频率。
# 5) 以60Hz网络处理为参考，单个Ball原先6个 ALWAYS 属性约产生 6×60=360 次持续属性更新/秒；
#    V379剩3个 ALWAYS并限制30Hz，约3×30=90次/秒，持续复制项理论量下降约75%。
#    Peer越多、角色越多，节省越明显；实际字节量仍取决于Godot序列化与属性变化。
# 6) 本地/服务器CPU同时优化 `World.set_ball_properties_to_dafault()`：
#    旧版每个角色每个physics tick遍历 default_properties，并执行 `b[str(i)]` 动态属性写入。
#    V379新增 `ball.restore_default_runtime_properties_fast()`，固定恢复9个同名字段，只有值真正偏离
#    default_properties 时才写回。default_properties 仍每帧读取，所以角色运行时修改默认值的兼容性保留。
# 7) Buff热循环过去每处理一个Buff都会调用 `Buff.Buff_types.keys()`；V379改成一次创建的
#    BUFF_RUNTIME_PROPERTY_NAMES 固定表，避免大量角色/Buff时不断构造短命Array。
# 8) 本轮不改：Damage/Speed/血量/护盾/冷却/Buff计算顺序、Nearest_Enemy规则、碰撞层、
#    大规模战斗空间网格、服务器authority、输入RPC语义、角色技能、兔子繁殖、死亡回归、翻译系统。
# 9) 这一轮主要针对最通用且确定的热点；后续若仍有极端大规模卡顿，应优先用Godot Profiler查看
#    Frame Time / Physics Time / Script，以及 Performance中的2D碰撞对、节点数，再按实际热点继续拆分。

# -----------------------------------------------------------------------------
# V380 直接控制动作键长按连发 / 多人低开销 hold 同步
# -----------------------------------------------------------------------------
# 1) 用户要求直接控制时“按住一个动作键就等于一直点击”，例如键盘侠按住左键应持续发射文字子弹。
# 2) 旧版 Game._input() 只有 InputEventMouseButton.pressed 的瞬间调用一次 _send_control_action()；
#    因此即使键盘侠 Attack_Cooling=0.075s，长按也只会打第一发，之后必须玩家手动反复点击。
# 3) V380不使用操作系统 InputEventKey.echo/鼠标系统重复。Godot官方说明键盘echo的延迟/频率由系统设置决定，
#    可能被修改或关闭；游戏连发不能把玩法节奏绑定到系统键盘重复设置。
# 4) 左/右/中三个直接控制动作现在统一记录 hold mask：
#    - 按下发生在战场空白区域：立即触发第一下，并进入保持状态；
#    - 保持超过45ms后，authority每个physics tick继续“尝试点击”；角色自身原有冷却、Attacking、Using_Skill、
#      眩晕、死亡、禁伤害等条件仍是最终门槛，所以不会绕过角色射速/技能CD；
#    - 松开即停止；松开即使发生在UI上也会清状态，防止拖过UI后出现卡住连发。
# 5) 多人不把长按实现成高频 reliable RPC：客户端只在 press/release 时各发一次
#    _controlled_action_hold_request；服务器保存 peer 的 hold mask，并利用原 V130 每物理帧已有的
#    unreliable_ordered WASD+aim 同步取得最新瞄准点，再在服务器本地持续尝试出招。
#    因此键盘侠0.075s这类高射速角色也不会额外制造约60个可靠动作包/秒。
# 6) 解除控制、换控制目标、玩家断线、目标失效都会清空对应hold状态，不允许角色在无人控制后继续自动攻击。
# 7) ball新增 player_control_action_hold_repeat_allowed(action_index) 扩展点，默认三键都允许长按。
#    已知极速者左键属于“点击开启极速攻击 / 再次点击关闭”的切换动作；V380覆写为左键只响应按下沿，
#    避免长按时每个物理帧把极速状态反复开关。其它普通攻击/技能继续按用户要求长按连发。
# 8) 本轮不修改角色 Attack_Cooling/Skill_Cooling、实际伤害、弹丸速度、authority、WASD和鼠标自由瞄准规则；
#    键盘侠继续使用原0.075s攻击冷却，长按只负责在冷却一到时自动触发下一发。


# -----------------------------------------------------------------------------
# V381 新角色：占卜师 / 四牌抽取 / 命运之轮 / 弧线追踪攻击牌
# -----------------------------------------------------------------------------
# 1) 新增可选角色 `res://scenes/characters/人物/占卜师.tscn` 与
#    `res://scripts/characters/占卜师.gd`；继续使用既有“人物”分类，不创建新的角色分类目录。
# 2) 占卜师每次攻击固定抽4张牌：攻击/防御/恢复各30%，命运之轮10%，四次独立随机。
# 3) 抽牌视觉新增 `res://scripts/effects/占卜师卡牌.gd`，卡牌完全程序化绘制，不依赖本轮未提供的图片目录：
#    - 从人物位置出现并移动到人物下方4个横向槽位；
#    - 通过反复压缩/展开scale.x模拟绕Y轴正反面翻转，最终停在正面；
#    - 卡背为紫色星纹，正面分别显示攻/防/愈/轮。
# 4) 命运之轮在普通组合中先结算：所有命运之轮统一替换成“当前数量最多”的普通牌；若普通牌并列，
#    按本轮抽牌从左到右最先出现的并列最高类型决定，不暗中偏向某一种牌。
# 5) 若四张全部是命运之轮，则进入大奖：四牌金色放大闪烁，并对全部敌对Ball施加越过block的致死raw-health伤害；
#    同队单位永远不计入“敌人”。特殊角色自带死亡回归/复活规则仍由其自身逻辑决定。
# 6) 命运之轮替换完成后，全部牌先按最终类型变色并放大，再用Back/Elastic补间恢复；随后按
#    攻击 -> 防御 -> 恢复顺序重排，同种牌自动相邻。
# 7) 攻击牌会从人物下方独立飞向最近敌人，真实视觉轨迹使用二次Bezier弧线，并缓慢吸附目标当前坐标形成小幅追踪；
#    结算时若原目标已死/失效，会重新选择最近敌人。多张攻击牌交错左右弧线，并按attack_launch_stagger真正错开发射；视觉飞行与authority命中使用同一时间轴。
# 8) 同类牌越多，数值超线性增强：
#    - 攻击牌每张的Damage倍率默认分别为1张1.00、2张1.35、3张1.75、4张2.20；
#    - 防御总量 = 70×张数×[1+0.25×(张数-1)]，加入ball原生block，角色max_block=600；
#    - 恢复总量 = 80×张数×[1+0.25×(张数-1)]，默认3.2秒分段恢复，恢复总量始终略高于同数量防御。
#    上述参数均为export，可直接在占卜师场景Inspector继续平衡。
# 9) 防御/恢复牌结算时先放大、按灰白/绿色高亮后缩小渐隐；卡牌消失后才真正加入block/启动恢复，恢复随后按tick完成。
# 10) 多人模式中抽牌、命运之轮替换、重排、消耗与攻击牌飞行都通过authority可靠RPC在各端复现；
#     真实随机、伤害、护盾和治疗只由authority结算，避免客户端重复计算。
# 11) 用户本轮未提供占卜师正式立绘。为遵守路径基准，不猜测/新建 `Images/characters/人物/占卜师/`；
#     场景暂用简洁的程序化紫色披风/星辉占位视觉。以后用户提供正式图片时再在既有Images路径接入。
# 12) translations.csv 与 global/translation_catalog.gd 同步新增“占卜师 / Fortune Teller”。

# -----------------------------------------------------------------------------
# V384 占卜师卡牌布局收紧 / 全流程音效
# -----------------------------------------------------------------------------
# 1) 占卜师四张牌原默认中心间距34，而牌宽约10，空隙明显过大；V384把card_spacing改为13，
#    四张牌只保留约3单位小缝。card_slot_y由54改为29，使牌阵更贴近占卜师。
# 2) 新增角色专属音频目录 `res://audio/characters/占卜师/`，接入用户提供的洗牌、出牌、
#    决定牌、扔牌、治愈五个MP3；统一注册到Audios/Sfx并进入GameplayRecord总线。
# 3) 抽牌开始立即播放一次洗牌音效；四张牌分别在各自appear_delay开始出现时各播放一次出牌音效，
#    与draw_stagger完全共用时间轴，不会四声挤在同一帧。
# 4) 普通组合在confirm动画34%峰值、牌面真正切换最终类型/颜色时播放决定牌音效；
#    四命运之轮大奖在金色确认开始时同样播放决定牌音效。
# 5) 每张攻击牌按自己的attack_launch_stagger实际起飞时播放一次扔牌音效；真正造成伤害后，
#    使用公共 `balls_hit1` 碰撞伤害音效，未造成伤害则不误播命中声。
# 6) 恢复牌在持续治疗正式启动时播放治愈音效；防御牌在block真实增加时复用锻剑储君的
#    `Mc锻造` 获取防御音效。多人模式下结算音效由authority广播，视觉阶段音效随已有表现RPC在各端各播一次。
# 7) 延迟出牌/决定/扔牌音效绑定本地牌阵序号；牌阵提前清除或角色死亡后，旧序列的延迟音效不会残留误播。


# -----------------------------------------------------------------------------
# V386 占卜师实效时点修正 / 新角色魔角猎人
# -----------------------------------------------------------------------------
# 1) 占卜师防御牌、恢复牌现在在对应卡牌进入“使用/消耗”动画的第一帧就立即生效，
#    不再等整段utility_consume_duration动画结束后才加block/启动治疗；恢复仍保留原持续tick总疗量。
# 2) 新增“游戏”分类角色魔角猎人：scenes/characters/游戏/魔角猎人.tscn 与
#    scripts/characters/游戏/魔角猎人.gd；角色选择系统本就按分类目录扫描，因此不修改world.gd。
# 3) 正式人物、武器、标记1/2/3图片进入 Images/characters/游戏/魔角猎人/，严格保持Images大写。
# 4) 普攻发射程序化圆形黑色像素弹：纯黑像素描边、深灰棋盘内部；默认速度430、射程520、
#    Attack_Cooling=1.15s。武器图独立叠加并持续朝实际瞄准方向旋转。
# 5) 黑弹命中推进同一目标的魔角标记，最多3层；标记1/2/3依次替换，并使用紫/金橙/红发光轮廓，
#    每次叠层有抖动+弹性放大；标记默认4.5s，存在期间每0.5s灼烧一次，每层默认5点/tick。
# 6) 三层标记再次被命中时不进入第4层，而是约0.26s黄橙强光抖动后爆炸：默认2.4倍攻击伤害，
#    使用ball.apply_knockback()击退；爆炸后开启默认4s爆弹窗口。
# 7) 爆弹窗口内主黑弹命中会从命中点抛出默认4枚程序化小爆弹，落点距24~58；落地颤抖0.42s后
#    范围爆炸，并可继续给范围内敌人叠加魔角标记；小爆弹本身不额外击退，击退只属于三层标记过载爆炸。
# 8) 标记灼烧音效不新增文件，直接复用 res://audio/status/debuff/烫伤.wav；爆炸复用现有通用爆炸音效。
# 9) translations.csv 与 global/translation_catalog.gd 新增 魔角猎人 / Magic Horn Hunter。


# -----------------------------------------------------------------------------
# V389 新角色：户山香澄 / 乐队分类
# -----------------------------------------------------------------------------
# 1) 新增可选角色 res://scenes/characters/乐队/户山香澄.tscn 与
#    res://scripts/characters/乐队/户山香澄.gd；严格加入现有“乐队”分类，不创建动漫同义目录。
# 2) 官方资料确认户山香澄属于 Poppin'Party，担当 Gt.&Vo.，因此场景标签加入
#    “乐队 / Poppin'Party / 吉他 / 音乐”，方便角色信息与后续机制扩展。
# 3) 用户本轮未提供正式立绘和具体技能设定；为避免擅自抓取/绑定第三方版权素材，暂使用
#    res://Images/characters/乐队/户山香澄/户山香澄_占位.png 作为可替换占位图。
# 4) 当前角色先使用 ball 标准攻击链：Max_health=500、Damage=45、Speed=105、Attack_Cooling=1.0；
#    不启用碰撞伤害与专属技能。后续用户指定吉他攻击、技能、音效或正式图片时直接扩展，不改分类路径。
# 5) translations.csv 与 global/translation_catalog.gd 同步新增“户山香澄 / Kasumi Toyama”。

# V390 户山香澄正式立绘 / 循环攻击音效 / 落星普攻
# 1) 正式人物图：res://Images/characters/乐队/户山香澄/户山香澄.png；上一版占位图不再被场景引用。
# 2) 每次普攻按 popipa1 -> popipa2 -> popipa3 -> popipa1 顺序循环播放，三段音频均来自用户本轮素材。
# 3) 每次普攻锁定一个落点：AI 取当前最近敌人的攻击目标位置；玩家直接控制时取鼠标世界坐标。
# 4) 落点显示用户提供的 res://Images/characters/乐队/户山香澄/警告.png，颜色持续红 -> 黄 -> 红循环，直到星星落地。
# 5) 星星由 res://scenes/effects/户山香澄_星星坠落.tscn + 对应脚本程序化绘制，从落点上方加速坠落；坠落开始即播放用户提供的 星星.mp3。
# 6) 默认 0.92 秒后落地，半径 34 范围伤害，倍率 1.0；这些参数均直接暴露在户山香澄场景 Inspector，可后续自由调整。
# 7) 联机中 authority 只负责真实伤害，警告/落星视觉及音效通过 RPC 在各 peer 本地生成，避免重复结算伤害。

# -----------------------------------------------------------------------------
# V391 户山香澄 MultiplayerSpawner 报错修复 / 左右上旋转落星 / Popipa音量形变
# -----------------------------------------------------------------------------
# 1) 修复 V390 截图中的红色错误：旧版 _rpc_spawn_star_strike() 把星星视觉 PackedScene 直接
#    add_child 到 World，而 world.tscn 的 MultiplayerSpawner.spawn_path 正是 World；Godot 会尝试
#    自动复制该直接子节点，并因运行时默认保留名 @Node2D@xxxx 报 Unable to auto-spawn node with reserved name。
# 2) V391 让落星视觉作为户山香澄角色的子节点创建，使用 add_child(effect,true) 生成可读名称，并设
#    top_level=true 保持世界坐标独立；该视觉已经由角色 RPC 在各 peer 本地创建，因此不再走第二套 Spawner 自动复制。
# 3) 星星入口改为每次由 authority 在左上/右上两个范围随机选择：默认水平偏移 110~220，垂直高度约210并带18%抖动；
#    入口偏移通过同一 RPC 发给所有 peer，因此多人端看到同一条坠落路线。
# 4) 星星不再垂直落下，而是从所选左上/右上入口斜向落点加速，并在整个坠落期间默认旋转约2.35圈；
#    左右入口使用相反旋转方向，落地伤害逻辑与 V390 不变。
# 5) 警告图标取消 V390 的 pulse scale；现在 scale 固定，仅以默认0.16秒完整周期快速执行红->黄->红颜色循环。
# 6) popipa1/2/3 仍按1->2->3循环且允许3秒片段自然重叠。V391 将临时 AudioStreamPlayer2D 改挂在角色子节点，
#    不再作为 World 的直接运行时子节点，并保留 GameplayRecord 总线与2D距离衰减。
# 7) 为实现“声音大时变细变高、声音小时变宽变扁”，本轮对用户提供的三段 MP3 以20ms窗口预计算50Hz RMS音量包络；
#    运行时用 AudioStreamPlayer2D.get_playback_position()+AudioServer.get_time_since_last_mix() 定位当前包络位置，不需要额外录音总线。
# 8) 人物形变只修改 Graphics/Image 的非等比 scale 和补偿 position：默认安静有声段约宽1.18/高0.82，响亮段约宽0.76/高1.30；
#    每帧根据可见Alpha范围计算的“人物最下面中心点”反算 Sprite2D.position，因此底部中心锚点始终保持在初始位置；角色根、碰撞和血条不缩放。


# -----------------------------------------------------------------------------
# V392 菜月昴第5次死亡死档修复 / CRT失真恢复 / 暗角扩张 / 莎缇拉逐字颤抖
# -----------------------------------------------------------------------------
# 1) 菜月昴死亡回归死档触发阈值由20次改为5次；脚本默认值与菜月昴.tscn显式值同步为5，
#    避免以后场景序列化值与脚本默认值不一致。
# 2) 死档CRT保留独立的最终BackBufferCopy(COPY_MODE_VIEWPORT)，并明确放在CRT ColorRect之前；
#    这是因为World本身更早已有地图裁剪BackBufferCopy，死档必须在最高后处理层重新复制当前完整窗口。
#    Shader继续使用Godot 4的hint_screen_texture + SCREEN_UV读取这份最终画面。
# 3) CRT强度整体提高：桶形弯曲、RGB色差、扫描线、动态颗粒、横向抖动和偶发撕裂均更明显；
#    新增effect_strength，黑屏完全淡出后约0.58秒渐入，避免从全黑直接硬切失真。
# 4) 新增vignette_progress。黑屏hold+淡出结束后才开始，约3.2秒从边缘向画面中心持续扩大暗角；
#    中心保留可读区域，不把“愛してる”和人物演出立即压成纯黑。
# 5) 新增 scripts/effects/重女式逐字颤抖.gd。它使用RichTextEffect逐glyph复刻重女文字的视觉参数：
#    约0.15秒一拍、像素级-1/0/1位置跳变、约±5度独立旋转，并保留部分拍不移动。
# 6) 死档顶部“愛してる”不再使用Godot内建[shake]，改为上述重女式逐字效果；底部“サテラ”
#    新增独立RichTextLabel并使用同一个效果。原底部Label仍透明保留，只用于维持既有水印布局尺寸。
# 7) SceneTree在死档处决期间仍会暂停；顶部与底部死档文字均使用PROCESS_MODE_ALWAYS，
#    因此暂停期间逐字效果仍持续。除死档触发次数与视觉表现外，不修改死亡回归时间轴、伤害、速度、拳头或音乐规则。
# V393 菜月昴死档修复：
# - 修复 CRT shader 在 fragment() 中使用 return 导致 Godot 4.7 编译失败的问题；
# - 移除整张地图的深紫 Polygon 覆盖，地图外死档底色改为近黑，解决地图下方大块紫色；
# - 死档背景持续生成日文“愛してる”，逐字显现/抽帧颤抖/旋转复刻重女文字，且暂停演出时仍继续。


# V394 菜月昴死档地图后背景 / CRT时序修复：
# - “愛してる”背景不再生成在 map_rect 内部；改为在当前窗口可见区域中随机取地图矩形外的点。
# - 新增四块近黑 BehindMap Polygon，只覆盖地图外世界区域；视觉等价于整张窗口底层被地图遮挡，地图内部不被改色。
# - 死档期间临时关闭 World 原蓝色 map_outside_grid，结束时恢复原 enabled/颜色，避免背景重新露出蓝色。
# - 背景爱字改回 World 相对 z=-2，保证先于 MapClipBackBuffer(z=-1) 绘制并被地图外遮罩复制，不会被遮罩盖没。
# - CRT effect_strength 从黑屏开始第一帧就是1.0；暗角仍在黑屏完全结束后再按原3.2秒向中心扩大。
# - CRT shader 增加轻微正向静电/扫描线底光，使输入纯黑时也能看见CRT，而不是只有画面恢复后才显现。


# -----------------------------------------------------------------------------
# V395 菜月昴死档红色爱字 / 深紫地图底 / 黑底烟雾素材接入
# -----------------------------------------------------------------------------
# 1) 背景随机“愛してる”统一固定红色，不再按概率混入白字；顶部“愛してる”和底部“サテラ”
#    继续沿用 V392 的重女式逐 glyph 颤抖与红色样式。
# 2) 死档背景从 V394 的“地图外近黑、地图内仍露原蓝色 Background”改为统一深紫：
#    map_rect 内新增 MapDeepPurpleFill，地图外四块 BehindMap 同步使用同一深紫色；原蓝色 map_outside_grid
#    在死档期间仍关闭，结束时恢复。
# 3) 用户提供的 3 段 1920x1080 MP4 烟雾均转为 Godot 4 核心原生支持的 Ogg Theora(.ogv)，
#    为降低实时 CPU 解码开销，视觉素材统一转为 960x540 / 12fps / 无音频；原 MP4 不写入项目。
# 4) 新增 shaders/ui/菜月昴死档烟雾去黑.gdshader：按视频亮度 soft-key 黑底为透明，
#    不使用矩形黑底；剩余烟雾染成黑灰~深紫随机色，保持 blend_mix alpha 叠加。
# 5) 死档激活时同时创建 4 个 VideoStreamPlayer，z=95（地图外遮罩 z=90 之上、莎缇拉手 z=96
#    与底部文字 z=98 之下）。每团随机素材、播放时间、尺寸、位置、轻微旋转、移动速度、透明度和灰/紫色；
#    约 8~15 秒重新随机一次，因此可在整个窗口不同位置持续叠加漂动。
# 6) CRT 时序保持 V394：黑屏第一帧即启用完整 CRT；暗角仍在黑屏 hold+淡出结束后才开始 3.2 秒扩大。

# V396 菜月昴死档修复：修正 res://scripts/effects/动漫/菜月昴背景爱字.gd 中 glyph.modulate 的缩进错误。
# 该错误会使背景爱字脚本解析失败，并导致菜月昴死档效果.gd 的 preload 报 Could not resolve script。
# V395 的红色愛してる、深紫地图/地图后背景、随机去黑烟雾、黑屏起始 CRT 与黑屏后暗角扩张逻辑全部保持不变。


# V397 菜月昴死档可读性修复：CRT 大幅减轻噪点/色差/撕裂/弯曲，仍从黑屏第一帧生效；
# 地图外视差网格恢复并改成深紫系，深紫底放到网格后方；烟雾改为屏幕 CanvasLayer 随机叠加并提高可见度；
# 全体 Ball 从进入死档第一帧即开始颤抖，莎缇拉手仍延迟伸出；死亡回归死档音效在 SceneTree 暂停后显式保持 stream_paused=false。


# -----------------------------------------------------------------------------
# V398 菜月昴死档 CRT 几何扭曲恢复 / 超大低透明左侧烟雾
# -----------------------------------------------------------------------------
# 1) CRT 不再靠提高噪点/花屏来表现强度；桶形几何扭曲独立增强，并增加轻微行场波浪偏移。
#    色差、扫描线、颗粒、横向抖动与撕裂继续维持低强度，优先保证深紫地图和视差网格可读。
# 2) CRT 仍从黑屏第一帧生效；黑屏结束后暗角按既有约3.2秒时序继续扩大。
# 3) 4路烟雾尺寸提高为约窗口宽度1.55~2.35倍；不再为了纵向窗口强行缩小，允许雾层超出窗口。
# 4) 每团烟雾的左边界固定生成在屏幕外（负X），垂直位置/素材/颜色/起播时间继续随机；
#    之后以较慢速度向右漂，并只保留轻微上下浮动。
# 5) 因烟雾整体放大，不透明度从V397约0.46~0.74大幅降到约0.16~0.30，避免遮住地图与网格。


# -----------------------------------------------------------------------------
# V399 菜月昴死档 CRT 层次恢复 / 斜向纹理单独减弱 / 任意旋转超大烟雾
# -----------------------------------------------------------------------------
# 1) CRT 恢复桶形弯曲、RGB 色差、扫描线、动态颗粒、水平同步抖动、偶发撕裂、滚动亮带、亮度漂移和轻微重影；
#    不再像 V397/V398 那样为了减少花屏把其它效果也一起压得很低。
# 2) 用户指出的“斜着一直动的纹理花屏”拆成独立 diagonal_interference_strength，默认仅 0.0045；
#    只减少这层斜向持续移动纹理，其它 CRT 层次恢复。CRT 仍从初始黑屏第一帧生效，暗角时序不变。
# 3) 4 路烟雾尺寸进一步提升到窗口宽度约 2.8~4.4 倍，透明度降到约 0.055~0.125。
# 4) 烟雾初始角度完整随机 -PI~PI，并持续慢速自由旋转；不再只允许几度倾斜。
# 5) 新增原始左缘几何约束：素材 local -X 左边缘经过旋转后，每帧放到 viewport 对应方向 support line 外侧。
#    因此 0° 时左边缘永远在屏幕左侧外；朝下(约90°)时这条边旋转成上缘并永远在屏幕顶部外；任意角度同理。
# 6) 雾只沿该外侧边界做切向缓慢滑动，不向屏幕内部推进，保证素材原始左边缘整个生命周期都不会进入窗口。


# -----------------------------------------------------------------------------
# V400 菜月昴死档：移除纵向扫光 / 全窗口随机爱字层级 / 超大低透明烟雾可见度修复
# -----------------------------------------------------------------------------
# 1) CRT 删除从上到下滚动的 rolling bright bar；桶形弯曲、RGB色差、扫描线、颗粒、
#    横向同步抖动、偶发撕裂、亮度漂移、轻微重影与极弱斜向纹理继续保留。
# 2) 背景“愛してる”的随机坐标改为覆盖整个可见窗口，不再排除 map_rect。
#    绘制层级改成：地图外深紫底 z=-4 -> 爱字 z=-3 -> 地图内部深紫填充/外部视差网格 z=-2 -> MapClipBackBuffer z=-1。
#    因此随机到地图内部的爱字确实会生成，但会被地图深紫底遮挡；地图外随机字仍可见。
# 3) 烟雾宽度提升到窗口宽度约5.2~7.6倍；透明度进一步降低到约0.025~0.055。
#    同时降低亮度抠黑阈值并强化低亮度mask，让极低alpha下的淡雾丝仍能看见，而不是整段视频被抠除。
# 4) 原始左边缘约束继续保留并缩小外侧margin：0度时左缘在屏幕左外；旋转朝下时原左缘变成上缘并保持在屏幕上外。
#    雾体可360度缓慢旋转并沿外侧边界切向移动。
# 5) VideoStreamPlayer除PROCESS_MODE_ALWAYS外，每帧额外确保 paused=false，避免SceneTree暂停后烟雾视频停在黑帧。


# -----------------------------------------------------------------------------
# V401 菜月昴死档：烟雾渲染链修复 / 原蓝背景清除 / 黑屏镜头解跟随 / 全屏持续微颤
# -----------------------------------------------------------------------------
# 1) V400 烟雾“完全看不到”的实现改为解码与显示分离：VideoStreamPlayer 只负责持续解码 Ogg Theora，
#    TextureRect 每帧读取 get_video_texture() 的当前帧并应用去黑 Shader。这样 Shader 明确作用在普通 CanvasItem 纹理上。
# 2) 烟雾数量由4路提高为6路，尺寸继续保持约窗口宽5.4~7.8倍；单层 alpha 仍只有约0.045~0.072，
#    但去黑 Shader 提高烟体核心与透明背景的对比，因此保持低透明同时能实际看见黑灰~深紫雾形。
# 3) 修复地图后背景/棋盘出现蓝色：world.tscn 原 Background 是蓝色 Gradient Sprite2D(z=-3)，V400 的深紫底在它后面会被蓝底覆盖。
#    死档期间现在暂时隐藏该 Background，退出死档时恢复；视差棋盘浅格为深紫、深格改为接近纯黑且不透明，不再混出蓝色方块。
# 4) 黑屏出现同一帧直接把 Camera2D 切到 world.gd 在 Follow_Controlled_Character=false 时的普通视角：
#    Camera_Move 开启时看战斗中心，否则看地图中心，并保留已有中键平移；随后再暂停 SceneTree，因此不会冻结在受控人物特写上。
# 5) 最终 CRT 后处理新增约1px持续微颤，通过最终 screen_texture 的 UV 统一偏移，因此地图、人物、烟雾、UI和文字作为整屏一起轻微颤抖。
#    不使用 Camera2D 单独抖动，避免只抖世界层而屏幕 UI 不动。V400 已删除的纵向滚动扫光仍保持删除。


# -----------------------------------------------------------------------------
# V402 菜月昴死档：烟雾改透明序列保证可见 / 背景爱字层级与坐标修复
# -----------------------------------------------------------------------------
# 1) V401 的 VideoStreamPlayer -> get_video_texture() 烟雾链在用户实机仍完全不可见。
#    V402 不再依赖运行时视频纹理：把用户原始 3 段 MP4 离线 soft-key 黑底为透明，生成 3 组 WebP 帧序列
#    + SpriteFrames(.tres)，运行时改用 AnimatedSprite2D 播放。WebP RGB 统一提亮为中性白灰，alpha 保留烟体形状，
#    再由 sprite.modulate 随机染成黑灰~深紫，避免“原视频暗RGB × 深色tint × 低alpha”三重相乘后肉眼不可见。
# 2) 烟雾提高到 7 层、宽度约窗口 8~12 倍，整体 alpha 约 0.055~0.095；仍可 360° 慢速自由旋转。
#    素材原始左边缘继续按当前旋转方向永远约束在屏幕对应外侧：朝右时左边在屏幕左外，朝下时原左边
#    旋成视觉上边并始终在屏幕顶部外，其它角度同理。
# 3) 背景“愛してる”消失的两个风险同时修复：先把文字节点 add_child 到 World 后再写 global_position，避免未入树时
#    global_position 被当成局部坐标；同时把外部视差网格 z 从 -2 临时降到 -4。
# 4) 死档背景最终顺序固定：外部深紫 -5 -> 视差网格 -4 -> 红色愛してる -3 -> 地图深紫 -2 ->
#    MapClipBackBuffer -1。文字随机点仍覆盖整个窗口；地图内生成的字会被地图深紫底遮住，地图外生成的字可见。
# 5) 背景爱字密度提高：初始 24 组、约每 0.20 秒继续生成、最多 60 组；退出死档时恢复视差网格原 z_index。


# -----------------------------------------------------------------------------
# V403 菜月昴死档：进入状态清理当前伤害跳字 / 地图紫底提亮
# -----------------------------------------------------------------------------
# 1) activate() 在启动死档音效后立刻清理 __damage_text_runtime 中当前已有的负号伤害跳字；
#    先 visible=false 确保本帧直接消失，再 queue_free() 安全释放。绿色“+N”回血跳字不在本轮清理范围。
# 2) 地图内部死档紫色底由 Color(0.115,0.012,0.17) 提亮为 Color(0.185,0.038,0.255)，
#    保留深紫氛围但不再压得过黑；地图外视差网格与其它死档效果保持 V402 逻辑不变。

# -----------------------------------------------------------------------------
# V404 菜月昴死档：真正锁定“关闭屏幕跟随”相机分支
# -----------------------------------------------------------------------------
# 1) 修复 V401~V403 只在 activate() 时写一次 Camera2D.global_position 的问题。Game Autoload 在暂停期间仍会
#    每帧调用 world.process_always(delta)，旧逻辑下一帧会再次读取 Follow_Controlled_Character 并锁回受控角色。
# 2) World 新增 _dead_save_force_non_follow_camera 与 set_dead_save_camera_follow_override(active)。死档激活时只临时
#    覆盖运行时 follow_controlled 判定，不修改 Game_Settings，因此整个死档期间每一帧都等价于关闭屏幕跟随。
# 3) 黑屏创建前先打开该 override，再立即把 Camera2D 切到普通非跟随视角：Camera_Move 开启时看战斗中心，
#    否则看地图中心，并保留中键平移。退出死档时自动关闭 override，恢复玩家原来的跟随设置。
# 4) V403 的伤害跳字清理、提亮紫底，以及 V402 的烟雾/爱字、CRT、整屏微颤均保持不变。



# V405 菜月昴死档镜头语义修正：
# 1) 用户所说“关闭镜头跟随”对应 Game_Settings.Camera_Move=false，而 V404 只关闭了 Follow_Controlled_Character。
#    当场上只有一个活角色时，_battle_primary_center 与该角色位置相同，所以旧版看起来会一直跟着人物，直到人物死亡后才回地图中心。
# 2) 死档覆盖期间 world.process_always() 现在直接固定为“地图中心 + 现有 mouse_offset”，完全绕过 Camera_Move 战斗中心、
#    Follow_Controlled_Character 与 cinematic focus 中心覆盖；黑屏第一帧前的即时切镜也使用同一规则。
# 3) 死档期间暂时忽略 cinematic focus 的 zoom multiplier，但保留玩家 toolbar_zoom_multiplier；退出死档后恢复正常相机逻辑。

# -----------------------------------------------------------------------------
# V406 菜月昴死档：状态持续期间新放角色也会被再次处决
# -----------------------------------------------------------------------------
# 1) 第一次全体莎缇拉处决完成后，死档视觉/CRT/UI 本来就会继续存在；V406 在该状态存续期间持续检查 Ball 组。
# 2) 只要玩家又放入新的 Ball，立即重新启动同一套“进入即颤抖 -> 手伸出缠绕 -> 雾中沉没 -> 强制死亡”流程，
#    而不是让新角色在死档状态下正常存活。多名新角色同时放入时会同一轮一起处决。
# 3) 每轮处决仍会在演出期间暂停 SceneTree，并在该轮结束后恢复；死档音效继续保持 PROCESS_MODE_ALWAYS / stream_paused=false。
# 4) 已经打上 satella_dead_save_forced_death 元数据、等待联机 authority despawn 的旧目标会被过滤，避免被下一轮重复抓取。

# -----------------------------------------------------------------------------
# V407 菜月昴死档：处决长矩形移除 / 只有手掌位于人物前景
# -----------------------------------------------------------------------------
# 1) 删除旧版 _draw() 中用于“下沉遮挡”的超长 BACKGROUND_PURPLE draw_rect；该矩形高度按角色高度再额外
#    向下延伸 100~180px，在靠近画面底部时会明显冲出屏幕，并形成用户看到的长条紫色色块。
# 2) 死档效果根节点 z_index 从 96 降到 -1：黑色曲线手臂和脚边局部雾现在统一在人物后方绘制，
#    不再与人物身体争前景层级。
# 3) 三只莎缇拉手掌 Sprite2D 改为 z_as_relative=false、z_index=97，因此只有手掌本身可以压在人物前面。
#    地图边框/高层 UI 仍保留原有更高层级，不受本轮影响。
# 4) 脚边局部雾从 11 团缩减为 7 团并降低 alpha，只保留环境提示；不再承担人物吞没遮挡。
# 5) _draw() 的 pull/retract 时间轴补上 GRAB_START_DELAY，和真正的伸手/缠绕/拖拽阶段完全对齐，
#    避免辅助视觉比手掌动作提前进入拖拽阶段。

# -----------------------------------------------------------------------------
# V408 Sans 龙骨炮音效响度 / 屏幕外距离衰减修复
# -----------------------------------------------------------------------------
# 1) 修复 Sans 龙骨炮“出现.ogg”和“龙骨炮射.ogg”整体偏小：原实现两路 AudioStreamPlayer2D 基础音量都只有 -1dB，
#    且龙骨炮按设计长期停在地图/屏幕外，因此还会继续受到默认 attenuation=1.0 的距离衰减。
# 2) 出现声改为 +3.0dB，开火声改为 +4.5dB；两路 attenuation 均降到 0.35，max_distance 分别提高到 3600/4000。
# 3) 仍使用 AudioStreamPlayer2D，不改成无定位 AudioStreamPlayer，因此左右/上下方位感与多炮空间分离继续保留。
# 4) 龙骨炮视觉、时长、pitch_scale、伤害、KARMA、生成位置与联机逻辑均未修改。
