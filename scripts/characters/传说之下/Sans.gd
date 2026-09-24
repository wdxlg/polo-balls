extends ball

# Sans V49
# - 1 HP / 1 点逐物理帧伤害。
# - 普通状态最多 14 次闪避；Boss 特殊化时保持原始数值不变，仅把闪避上限提升到 30。
# - 三类攻击：四向重力砸墙、固定面积随机长宽骨头墙、龙骨炮。
# - V181：闪避后的完全无敌保护缩短到 0.1 秒。
# - V181：任何 Sans 的重力砸在推动阶段都会让目标穿过其它战斗单位，只与墙/障碍碰撞；撞墙后恢复原碰撞。
# - V181：每次重力砸都会把目标后续重力方向永久切到本次砸击方向，并旋转目标根节点，使人物、血条等整体同步转向。
# - V181：Boss 特殊化新增深蓝状态；V185 已把其运动改为标准重力 + 落地随机起跳。
# - V182：持久重力目标曾改为本地左右轴 + 重力轴速度预算。
# - V183：KARMA 闪紫改为保留原贴图颜色的半透明混合叠加。
# - V185：持久重力改回标准 v += a*delta；Boss 深蓝改为落地后随机等待再起跳。
# - V186：深蓝改为更浅的半透明叠加色；重力积分保持 V185。
# - V191：Boss 深蓝起跳力度调整为 Speed 的 2.0~4.0 倍线性随机；标准重力加速度保持不变。
# - V191：修复重力碰撞例外在目标释放后留下空 PhysicsBody2D 引用造成的 Parameter "body" is null 报错。
# - V192：低闪避不再自动触发“大风车”；大风车改为仅 Boss 特殊化使用的独立特殊技能。
# - V192：Boss 特殊化新增“重力整墙骨头”：先把目标重力改到安全方向，再从目标会落向的整面墙伸出一排低矮骨头。
# - V192：所有新重力方向会避开目标已经特别靠近的墙；例如贴底且靠左时只会选向右或向上。
# - V193：所有从墙/地面刺出的骨头完全伸出后只抖视觉一次；判定框保持不动。
# - V193：重力砸真正撞墙时触发方向性整屏冲击，主方向跟随砸击方向并混少量侧向/随机抖动。
# - V49：大风车改为龙骨炮一个接一个沿外围连续绕圈，并固定攻击地图中心；滚动骨头改为根部插墙、沿墙从地图外滚入的三类原版风格骨列。
# - V50：大风车改成细、小、短寿命、高密度的连续炮圈；单炮快速闪入/开火/消失，保持五圈并固定瞄准地图中心。
# - V51：大风车改为近乎整圈持续覆盖，只保留一个固定扇形缺口；龙骨炮不再等比缩小，只压窄本体宽度与激光宽度，并延长单炮驻留时间。
# - V52：大风车炮体加粗；曾尝试把激光截到地图中心。
# - V53：大风车恢复激光贯穿；地图中心只作为瞄准方向。安全区改为贯穿中心的一条双向扇形走廊，并且跳过缺口角度时不消耗生成间隔，避免每圈出现“打一会停一会”。
# - V54：大风车改为真正连续旋转的环形生成轨迹：炮位沿圆环逐门推进，每转过一圈都会自然错开相位，不再重复同一批固定位置。
# - V55：移除人为“缺口角度/跳过炮位”。每个连续角度都生成龙骨炮；唯一缺口只由旧激光消失与新激光亮起的时间差自然形成，并随炮圈持续旋转。
# - V56：把炮圈转速/出场速度整体放慢：72 门/圈保持不变，生成间隔 0.030s、出现 0.34s、激光约 1.80s；一圈约 2.18s，自然形成约 60° 的移动时间缺口。
# - V57：大风车不再靠“理论寿命差”硬挤缺口；每门炮完全出现后额外停留待发，再统一延迟开火。激光驻留缩到略低于半圈覆盖，让待发的新炮与刚熄灭的旧炮之间形成真实旋转缺口。
# - V58：大风车炮体略加粗、空间密度略降低，但保持单圈总推进时间接近 V57；持久重力若一段时间未再次刷新，会平滑恢复角色原朝向/蓝色状态，并快速衰减残余重力速度回正常移动。
# - V59：大风车进一步加粗炮体与激光、明显降低每圈炮数；同步拉长生成间隔以保持单圈旋转时间接近 V58，不改变自然缺口/延迟开火机制。
# - V62：修正 V61 未真正落实的问题：大风车音效直接按炮体宽度改变 pitch；滚动骨头进一步缩短并固定同墙统一尺寸；滚动骨头期间封锁普通骨墙/普通单炮，避免同墙多种骨头效果叠加。
# - V50：骨头完全刺出抖动与重力砸墙方向性震屏显著增强。
# - 骨头/龙骨炮叠加 KARMA；KARMA 自身不能击杀。
# - 视觉严格从用户提供的 Sans 精灵图 AtlasTexture 裁切，不整张显示。
# - V151：正常静止插兜；闪避短暂摊手+闭一只眼；只有重力攻击播放身体动画。
# - V151：身体帧按“脖子锚点”对齐，避免 Right Strike 等宽帧让身体/头部横向漂移。
# - V152：头部下移少许；龙骨炮尺寸随机，激光宽度随炮宽；骨头改为从墙内平移冒出而非长度缩放。
# - V153：所有身体动画改用脚底公共锚点对齐；头部继续下移。
# - V153：闪避高/中/低对应普通/快速/慢速攻击节奏；攻击时蓝/黄眼脸循环并带真实发光。
# - V153：低闪避时叠加原图三档流汗头顶；骨头四个墙面统一由圆头朝场内冒出。
# - V154：死亡复用项目 Minecraft 人物的红色倒下 + 延迟死亡烟雾演出，演出完成后才真正释放。
# - V155：接入用户提供的 Sans 音效；KARMA 扣血闪紫；MISS 改为留在闪避原地的黑字灰白描边跳字。
# - V155：闪避优先从地图内挑选远离敌人、AI_Hazard 与阻挡的安全位置，找不到时再退化为普通随机闪避。
# - V156：修正左右重力挥击各帧的躯干水平锚点，避免视觉上像头部被甩到左边。
# - V156：龙骨炮“出现→开火”总时长以出现音效原始长度为基准小幅随机；“开火→完全消失”以射击音效原始长度为基准，
#          并按本次龙骨炮宽度缩放：越宽持续越久。
# - V157：闪避摊手图重新直接从原图保留全部内部黑色；MISS 缩小并加粗描边；扣血音提高音量。
# - V157：Right Strike 以躯干中心而不是脚部视觉边缘对齐 Face；Sans 帧伤/KR 恢复伤害跳字（短时间合并避免每帧刷节点）。
# - V158：闪避摊手改用完整 72px Torso，并仅剔除外部黑底；不再裁掉双手。
# - V159：左重力改为四向随机中的独立攻击；左砸从 Right Strike 最后一帧直接倒放。
# - V159：闪避摊手图重新按白色轮廓判定内部区域，完整保留衣服/裤子内部黑色，同时清除外部黑底。
# - V160：攻击只在“下达攻击/召唤”这一刻占用 Attack 状态；龙骨炮后续开火、骨头后续刺出、重力后续位移都不再拖住下一次攻击冷却。
# - V160：快攻阶段蓝/黄眼只在每次召唤/砸起手时短促闪几下，不再跟着已生成的龙骨炮/骨头持续闪。
# - V160：骨头与龙骨炮召唤也驱动 Sans 身体方向动画：下方来源=抬手、上方来源=放手、左方来源=右挥、右方来源=左挥倒放。
# - V160：骨头固定面积继续保留，但允许更宽的长宽比例；骨头排列保证不重叠，并让攻击带两端都落一根骨头。
# - V161：Right Strike 六帧以待机身体为绝对基准重新配准；修正整套横挥相对待机统一向右约 2.64px 的素材原点偏差，正放/倒放共用同一套锚点。
# - V162：左挥严格只做 Right Strike 帧序倒放，不做水平镜像；六帧横挥统一使用相同躯干 X 锚点，消除倒放从末帧起手时的横向跳位。
# - V163：禁用 ball 基类的“角色朝移动方向自动镜像”对 Sans 主体的影响；不仅关闭 Sprite2D.flip_h，也强制主 Shader 的 sprite_flip_h=0。
#          左挥始终只是 Right Strike 的 5→4→3→2→1→0 帧序倒放，绝不做左右反转；这同时消除镜像后造成的巨大横向位移。
# - V158：骨头/龙骨炮/KR 的伤害跳字只显示单次 1 点，不再把多个帧伤合并成大数字；蓝黄眼仅快攻阶段闪。
# - V165：快攻阶段冷却回调到中间值；移除文字闪避提示，改为脚下 20 段白色闪避条，仅在次数变化时显示后渐隐。
# - V165：图集中新增正常插兜+正常脸的单图预览区域，供 World 放置 Ghost 使用，修复选择 Sans 后没有半透明人物预览。
# - V168：恢复“被攻击后留在原地的 MISS 跳字”；仍删除人物身上的常驻闪避文字，次数继续用脚下分段条显示。
# - V169：最大闪避次数改为 14，并把高/中/低三档按 10~14 / 5~9 / 0~4 重新分段。
# - V170：闪避成功后在新位置短促闪白，并以整个人视觉中心为固定支点纵向拉长；随后使用弹性 Tween 恢复原比例。
# - V172：修复运行时 Sans Sprite 未继承 hit_white_color 导致闪黑；闪避后增加短暂无敌保护，同一波密集命中只消耗 1 次闪避。
# - V179：闪避改为真正的投射物穿透式闪避；直线/射线子弹在触发闪避后继续原轨迹，不被 Sans 消耗、停止或改向。

const SANS_ATLAS:Texture2D = preload("res://Images/characters/传说之下/Sans/Sans_spritesheet.png")
const BONE_ATTACK_SCRIPT:Script = preload("res://scripts/effects/传说之下/Sans骨头攻击.gd")
const ROLLING_BONE_SCRIPT:Script = preload("res://scripts/effects/传说之下/Sans滚动骨头.gd")
const GASTER_ATTACK_SCRIPT:Script = preload("res://scripts/effects/传说之下/Sans龙骨炮.gd")
const KARMA_SCRIPT:Script = preload("res://scripts/effects/传说之下/Sans业力.gd")
const DEATH_SMOKE_FRAMES:SpriteFrames = preload("res://scenes/effects/我的世界/蠹虫死亡烟雾.tres")
const DEATH_POSE_DURATION:float = 0.90
const SFX_DAMAGE:AudioStream = preload("res://audio/characters/传说之下/Sans/扣血.ogg")
const SFX_SLAM:AudioStream = preload("res://audio/characters/传说之下/Sans/砸.ogg")
const SFX_GASTER_APPEAR:AudioStream = preload("res://audio/characters/传说之下/Sans/龙骨炮出现.ogg")
const SFX_GASTER_FIRE:AudioStream = preload("res://audio/characters/传说之下/Sans/龙骨炮射.ogg")
const KARMA_FLASH_COLOR:Color = Color(0.88,0.22,1.0,1.0)
# V183：闪紫不是纯色覆盖。Set_RGB_Color 的 hit_white 最终用 mix(original,purple,power)，
# 因此只给部分 power，让原贴图/阵营色/明暗仍然透出来。
const KARMA_FLASH_OVERLAY_POWER:float = 0.42

const BODY_IDLE:Rect2 = Rect2(5,127,54,48)
# V165：给角色放置 Ghost 使用的完整“正常插兜 + 正常脸”单图，写在 Atlas 空白区。
const BODY_PREVIEW:Rect2 = Rect2(550,900,60,80)
# V151 由原图 Torso 第 2 帧（双手摊开）+ Legs 第 1 帧在图集空白区重组，
# 仍然只使用用户给出的精灵图内部部件。
const BODY_DODGE:Rect2 = Rect2(540,120,72,49)
const BODY_HAND_DOWN = [
	Rect2(5,198,64,73), Rect2(74,198,64,73), Rect2(144,198,63,73),
	Rect2(212,198,64,73), Rect2(282,198,63,73),
]
const BODY_HAND_UP = [
	Rect2(5,294,64,73), Rect2(74,294,64,73), Rect2(144,294,63,73),
	Rect2(212,294,64,73), Rect2(282,294,63,73), Rect2(351,294,63,73),
]
const BODY_RIGHT_STRIKE = [
	Rect2(5,390,97,55), Rect2(107,390,97,55), Rect2(209,390,97,55),
	Rect2(311,390,97,55), Rect2(413,390,97,55), Rect2(515,390,97,55),
]

# V153：动画帧不再按裁图中心/脖子猜位置，而是把每一帧脚底中心锁到同一世界局部点。
# 这些锚点来自当前透明图集中每帧最下方 9px 的实际像素中心；Right Strike 的画布再宽也不会横漂。
const BODY_IDLE_FEET:Vector2 = Vector2(27.82,47.0)
const BODY_DODGE_FEET:Vector2 = Vector2(36.21,48.0)
const BODY_HAND_DOWN_FEET = [
	Vector2(30.77,69.0), Vector2(30.77,69.0), Vector2(29.77,69.0),
	Vector2(30.77,69.0), Vector2(29.77,69.0),
]
const BODY_HAND_UP_FEET = [
	Vector2(30.77,69.0), Vector2(30.77,69.0), Vector2(29.77,69.0),
	Vector2(30.77,69.0), Vector2(29.77,69.0), Vector2(29.77,69.0),
]
# V156：Right Strike 每帧的身体核心在 97px 画布里的 authored X 本来就不同。
# 之前把 6 帧脚底锚点 X 全写成同一个值，会让身体核心在横挥过程中左右漂，
# 而 Face 固定在世界 X，于是视觉上就像“头突然偏到左边”。
# 下面按 frame0 的躯干核心做模板对齐，补偿各帧约 -2/-3/+3/+1/+1 px 的 authored 偏移。
const BODY_RIGHT_STRIKE_FEET = [
	# V162：Right Strike 六帧下半身（y>=30）的实际躯干中心几乎完全一致，约 x=33.13。
	# 左挥只是同一组六帧从最后一帧倒放，不能使用按“伸手轮廓”变化的 X 锚点，
	# 否则倒放从 frame5 起手会把整个人明显推向右侧。六帧统一锁定同一躯干轴。
	Vector2(33.13,47.0), Vector2(33.13,47.0), Vector2(33.13,47.0),
	Vector2(33.13,47.0), Vector2(33.13,47.0), Vector2(33.13,47.0),
]
# 保留 V152 idle 的实际脚底世界局部位置作为全动画公共目标点。
const SANS_BODY_FEET_POINT:Vector2 = Vector2(2.15,105.74)

const BOSS_FACES = [
	Rect2(5,519,32,30), Rect2(42,519,32,30), Rect2(79,519,32,30),
	Rect2(116,519,32,30), Rect2(153,519,32,30), Rect2(190,519,32,30),
	Rect2(227,519,32,30), Rect2(264,519,32,30), Rect2(301,519,32,30),
	Rect2(338,519,32,30), Rect2(375,519,32,30), Rect2(412,519,32,30),
	Rect2(449,519,32,30), Rect2(486,519,32,30), Rect2(523,519,32,30),
]
# 原图 Faces (Boss) 下方两张完整攻击脸：左为蓝眼、右为黄眼。
const ATTACK_GLOW_FACES = [Rect2(5,556,34,32), Rect2(44,556,34,32)]
# 原图再下一排只画头顶/汗珠，作为独立覆盖层，不替换眼睛/嘴巴。
const SWEAT_TOP_OVERLAYS = [Rect2(5,593,32,32), Rect2(42,593,32,32), Rect2(79,593,32,32)]

const SANS_VISUAL_SCALE:float = 2.62
# Face 仍使用固定头部基准；V153 身体动画已经改为统一脚底锚点。
const SANS_NECK_POINT:Vector2 = Vector2(0.0,-17.4)
# V153：在 V152 基础上再向下 2px；现在 Face 总计向下 4 个原始像素。
const SANS_FACE_DOWN_PX:float = 4.0
const NORMAL_FACE_INDEX:int = 0
const DODGE_FACE_INDEX:int = 3 # Boss Faces 中闭着左眼、另一只眼睁开的表情。

# V165：脚下闪避次数条，视觉结构沿用苦力怕的“近黑外框 + 灰白描边”。
# 内部每一个白色格代表 1 次剩余闪避；格子之间用黑线分隔。
const DODGE_BAR_RECT:Rect2 = Rect2(-55.0,112.0,110.0,14.0)
const DODGE_BAR_OUTER_PAD:float = 4.0
const DODGE_BAR_BORDER_WIDTH:float = 2.5
const DODGE_BAR_OUTER_COLOR:Color = Color(0.02,0.02,0.025,0.92)
const DODGE_BAR_BACKGROUND_COLOR:Color = Color(0.10,0.10,0.115,1.0)
const DODGE_BAR_BORDER_COLOR:Color = Color(0.78,0.82,0.88,0.90)
const DODGE_BAR_FILL_COLOR:Color = Color(1.0,1.0,1.0,1.0)
const DODGE_BAR_SEPARATOR_COLOR:Color = Color(0.01,0.01,0.012,1.0)

enum SansVisual { IDLE, DODGE, GRAVITY_UP, GRAVITY_DOWN, GRAVITY_RIGHT, GRAVITY_LEFT }
enum SansAttack { GRAVITY, BONES, GASTER }
enum WallSide { TOP, RIGHT, BOTTOM, LEFT }

@export_category("Sans / 闪避")
@export_range(1,30,1) var max_dodge_count:int = 14
@export_range(0.5,30.0,0.5) var dodge_recovery_delay:float = 8.0
@export_range(0.5,10.0,0.25) var dodge_recovery_interval:float = 2.5
@export_range(4.0,80.0,1.0) var dodge_map_margin:float = 22.0
@export_range(0.0,240.0,4.0) var dodge_min_distance:float = 72.0
@export_range(4.0,64.0,1.0) var dodge_clearance_radius:float = 18.0
@export_range(1,32,1) var dodge_position_attempts:int = 16
@export_range(24.0,280.0,4.0) var dodge_enemy_safe_distance:float = 118.0
@export_range(0.0,100.0,2.0) var dodge_hazard_padding:float = 22.0
@export_range(0.10,2.0,0.05) var dodge_visual_duration:float = 0.55
@export_range(1.05,2.20,0.05) var dodge_stretch_y:float = 1.48
@export_range(0.45,1.00,0.05) var dodge_stretch_x:float = 0.82
@export_range(0.02,0.20,0.01) var dodge_stretch_out_duration:float = 0.06
@export_range(0.08,0.80,0.01) var dodge_stretch_return_duration:float = 0.30
@export_range(0.03,0.30,0.01) var dodge_flash_duration:float = 0.10
@export_range(0.05,0.80,0.01) var dodge_post_success_grace:float = 0.10
@export_range(0.10,3.0,0.05) var dodge_bar_hold_duration:float = 0.80
@export_range(0.10,2.0,0.05) var dodge_bar_fade_duration:float = 0.55

@export_category("Sans / 攻击")
@export_range(0.2,8.0,0.05) var attack_post_cooldown:float = 1.25
# V169 默认 14 闪避：10~14 普通攻速、5~9 快攻、0~4 慢攻。
@export_range(1,30,1) var attack_high_dodge_min:int = 10
@export_range(0,29,1) var attack_medium_dodge_min:int = 5
@export_range(0.05,1.00,0.01) var attack_medium_cooldown_multiplier:float = 0.28
@export_range(1.00,3.00,0.05) var attack_low_cooldown_multiplier:float = 1.55
@export_range(0.04,0.30,0.01) var attack_eye_flash_interval:float = 0.065
@export_range(2,10,1) var attack_eye_flash_count:int = 4
@export_range(0.10,1.50,0.05) var attack_eye_glow_strength:float = 0.80
@export_range(0.04,0.30,0.01) var damage_text_batch_interval:float = 0.10
@export_range(0,20,1) var sweat_start_dodge_count:int = 4
@export_range(100.0,2400.0,25.0) var gravity_acceleration:float = 1250.0
@export_range(200.0,1800.0,25.0) var gravity_terminal_speed:float = 980.0
@export_range(0.4,4.0,0.05) var gravity_max_duration:float = 1.85
@export_range(20.0,250.0,5.0) var gravity_damage_speed_step:float = 95.0
@export_range(1,40,1) var gravity_damage_max:int = 14
@export_range(0.0,100.0,1.0) var gravity_slam_screen_shake:float = 92.0
@export_range(0.0,1.0,0.01) var gravity_slam_screen_shake_direction_bias:float = 0.80
@export_range(0.04,0.20,0.005) var gravity_anim_frame_duration:float = 0.085
@export_range(0.0,1.0,0.05) var gravity_left_followup_chance:float = 0.50
@export var gravity_target_color:Color = Color(0.34,0.55,1.0,1.0)
# 深蓝只是叠加层，不覆盖原角色颜色；0.30 会明显偏蓝但仍保留原贴图/阵营色。
@export_range(0.05,0.80,0.01) var gravity_target_overlay_strength:float = 0.30
# 砸击结束后仍保留的“蓝魂方向重力”。不再使用砸击瞬间的 1250 强加速度，
# 避免普通目标撞墙后一直被过强外力锁死；下一次砸会直接覆盖为新的方向。
@export_range(80.0,1600.0,10.0) var gravity_persistent_acceleration:float = 520.0
@export_category("Sans / 重力自动恢复")
# 目标最后一次被本 Sans 改变/刷新重力后，超过这个时间就自动解除持久重力并恢复原朝向。
@export_range(0.50,10.0,0.10) var gravity_idle_restore_delay:float = 3.0
# 朝向不是瞬间弹回，而是在很短时间内平滑回到第一次受重力前的角度。
@export_range(0.05,0.80,0.01) var gravity_restore_rotation_duration:float = 0.24
# 清掉重力源后，残余重力速度用更高减速度快速衰减；正常移动速度会自然重新占主导。
@export_range(200.0,5000.0,50.0) var gravity_restore_velocity_deceleration:float = 1800.0

# 骨头矩形“面积”恒定；每次随机深度，再由 area/depth 反求跨度。
@export_range(1000.0,30000.0,100.0) var bone_attack_area:float = 7600.0
@export_range(12.0,320.0,1.0) var bone_min_depth:float = 20.0
@export_range(20.0,320.0,1.0) var bone_max_depth:float = 101.0
@export_range(0.10,1.5,0.02) var bone_warning_duration:float = 0.44
@export_range(0.04,0.6,0.02) var bone_rise_duration:float = 0.16
@export_range(0.15,2.5,0.05) var bone_active_duration:float = 0.82

# V156：龙骨炮时长不再用固定 0.28/0.72 秒硬压音频。
# 出现阶段基准 = “龙骨炮出现.ogg”的原始时长；攻击阶段基准 = “龙骨炮射.ogg”的原始时长。
# 两段都只做小幅随机，攻击阶段额外随炮体宽度变化：越宽越久。
@export_range(0.80,1.20,0.01) var gaster_appear_duration_scale:float = 1.00
@export_range(0.80,1.30,0.01) var gaster_attack_duration_scale:float = 1.00
@export_range(0.00,0.12,0.005) var gaster_duration_randomness:float = 0.05
@export_range(0.00,0.40,0.01) var gaster_width_duration_influence:float = 0.18
# 龙骨炮每次在这个范围随机缩放；激光宽度按炮体实际宽度比例计算。
@export_range(0.40,2.50,0.05) var gaster_size_min:float = 0.85
@export_range(0.40,2.50,0.05) var gaster_size_max:float = 1.55
@export_range(0.15,0.80,0.01) var gaster_beam_width_ratio:float = 0.42
@export_range(20.0,260.0,5.0) var gaster_map_outside_offset:float = 46.0
@export_range(80.0,600.0,10.0) var gaster_spawn_extra_distance:float = 180.0

@export_category("Sans / Boss特殊技能 / 大风车")
# 原版 Sans 最终攻击：细龙骨炮以很短寿命、高密度一个接一个沿战斗框外围连续绕圈，并始终朝地图中心开火。
# V49：不再逐个追踪敌人位置，也不再“每圈重置/错位一组炮”；整段攻击是一条连续角度轨迹。
@export_range(1,8,1) var windmill_round_count:int = 3
# V60：实机反馈 48 门/圈仍有大量炮体互相重叠；降到 30 门/圈，并把间隔同步拉长，
# 让单圈仍保持约 2.16 秒，因此只是明显降低空间密度，不会让大风车重新加速。
@export_range(18,120,1) var windmill_blaster_count_per_round:int = 30
@export_range(0.010,0.20,0.001) var windmill_spawn_interval:float = 0.072
@export_range(2.0,30.0,0.5) var windmill_cooldown:float = 10.0
@export_range(0.0,20.0,0.25) var windmill_initial_delay:float = 6.0
# 兼容旧 Inspector 数据：V51 大风车不再使用这个值做等比缩放，炮体纵向/整体尺度固定 1.0。
@export_range(0.30,1.20,0.05) var windmill_size_scale:float = 1.0
# 只压缩龙骨炮贴图的局部 X（宽度），不压缩高度/长度。
@export_range(0.20,1.50,0.01) var windmill_body_width_scale:float = 1.18
@export_range(0.05,0.60,0.01) var windmill_beam_width_ratio:float = 0.36
# V56：出场动画明显放慢；激光寿命略短于完整转一圈的时间，因此会留下随炮圈移动的自然缺口。
@export_range(0.10,0.60,0.01) var windmill_appearance_duration:float = 0.34
# V57：炮体完全出现后先保持待发一段时间，再开始出激光。
# 缺口来自“新炮已经出现但尚未开火”与“旧炮已经熄灭”的时序差，不跳过任何角度。
@export_range(0.00,1.50,0.01) var windmill_prefire_delay:float = 0.55
@export_range(0.30,2.50,0.05) var windmill_attack_duration:float = 0.85
# V63：大风车开始时解除本 Sans 留在敌人身上的定向重力。
# 普通移动逻辑立即恢复；这里只控制“残余重力速度”消退得多快，不会硬切速度。
@export_range(400.0,8000.0,100.0) var windmill_gravity_release_velocity_deceleration:float = 3600.0
@export_category("Sans / Boss特殊技能 / 滚动骨头")
# V49：这里的“滚动”是 Undertale 风格的“骨头根部插在墙里，沿墙从地图外滚进来”，不是整根骨头在场内自由旋转。
# 三种随机图案：单墙连续小骨、单墙统一长度骨列、相对双墙反向统一骨列。
# V61：同一面墙一次技能只能有一种骨头长度/样式，禁止在同一墙面混合多个长短变体。
@export_range(2,24,1) var rolling_bone_count:int = 8
@export_range(0.03,0.80,0.01) var rolling_bone_spawn_interval:float = 0.18
@export_range(2.0,30.0,0.5) var rolling_bone_cooldown:float = 7.5
@export_range(0.0,20.0,0.25) var rolling_bone_initial_delay:float = 5.0
@export_range(80.0,900.0,10.0) var rolling_bone_speed_min:float = 160.0
@export_range(80.0,900.0,10.0) var rolling_bone_speed_max:float = 230.0
@export_range(0.50,1.80,0.05) var rolling_bone_size_min:float = 0.90
@export_range(0.50,1.80,0.05) var rolling_bone_size_max:float = 1.08
@export_range(20.0,180.0,2.0) var rolling_bone_offscreen_margin:float = 54.0
@export_range(6.0,64.0,1.0) var rolling_bone_small_length_min:float = 8.0
@export_range(6.0,80.0,1.0) var rolling_bone_small_length_max:float = 14.0
@export_range(10.0,120.0,1.0) var rolling_bone_row_length_min:float = 14.0
@export_range(10.0,140.0,1.0) var rolling_bone_row_length_max:float = 24.0
@export_range(10.0,120.0,1.0) var rolling_bone_train_spacing:float = 54.0
# 相对双墙反向骨列需要明显更大的可穿行间隙，单独使用更疏的数量/间距。
@export_range(2,12,1) var rolling_bone_opposite_count:int = 4
@export_range(40.0,240.0,2.0) var rolling_bone_opposite_spacing:float = 132.0
# V62：旧的同墙长短混合参数保留仅为场景兼容，但不再参与生成。
@export_range(0.0,0.60,0.01) var rolling_bone_variant_chance:float = 0.0
@export_range(0.35,0.95,0.01) var rolling_bone_variant_short_ratio:float = 0.58
@export_range(1.05,1.90,0.01) var rolling_bone_variant_long_ratio:float = 1.38

@export_category("Sans / Boss特殊技能")
# 不改 Sans 原来的 Skill_Cooling / Can_Skill 数值；Boss 专属技能使用自己的冷却计时。
@export_range(1.0,30.0,0.5) var boss_special_skill1_cooldown:float = 8.0
@export_range(0.0,10.0,0.25) var boss_special_skill1_initial_delay:float = 2.5
@export_range(1.0,30.0,0.5) var boss_special_skill2_cooldown:float = 8.5
@export_range(0.0,20.0,0.25) var boss_special_skill2_initial_delay:float = 4.0
@export_range(0.05,1.50,0.05) var boss_gravity_wall_bone_delay:float = 0.22
@export_range(10.0,96.0,1.0) var boss_gravity_wall_bone_depth:float = 28.0
@export_range(16.0,180.0,2.0) var gravity_direction_avoid_wall_distance:float = 72.0
@export_range(0.10,2.00,0.05) var boss_special_global_lock:float = 0.75
@export_range(80.0,1600.0,10.0) var boss_blue_gravity_acceleration:float = 520.0
# 兼容旧场景/状态恢复接口；V185 起不再用该比例限制标准重力。Boss 起跳 V190 仍不受它限幅。
@export_range(0.10,0.95,0.01) var gravity_motion_axis_ratio_max:float = 0.80
# Boss 深蓝：落地后随机等待；V191 起跳力度直接按 Speed 的 2.0~4.0 倍线性随机。
@export_range(0.0,3.0,0.05) var boss_blue_jump_min_interval:float = 0.40
@export_range(0.0,4.0,0.05) var boss_blue_jump_max_interval:float = 1.20
@export_range(0.05,10.0,0.05,"or_greater") var boss_blue_bounce_min_ratio:float = 2.0
@export_range(0.05,10.0,0.05,"or_greater") var boss_blue_bounce_max_ratio:float = 4.0

var _dodge_count:int = 0
var _dodge_grace_remaining:float = 0.0
var _time_since_incoming_attack:float = 0.0
var _recovery_accumulator:float = 0.0
var _dodge_rng:=RandomNumberGenerator.new()
var _attack_rng:=RandomNumberGenerator.new()

var _sans_body:Sprite2D = null
var _sans_face:Sprite2D = null
var _sans_sweat:Sprite2D = null
var _sans_eye_glow:Sprite2D = null
var _visual_mode:int = SansVisual.IDLE
var _visual_elapsed:float = 0.0
var _visual_frame:int = -1
var _face_frame:int = -1
var _current_face_region:Rect2 = Rect2(-999.0,-999.0,0.0,0.0)
var _current_body_region:Rect2 = Rect2(-999.0,-999.0,0.0,0.0)
var _sweat_frame:int = -2
var _attack_face_active:bool = false
var _attack_face_elapsed:float = 0.0
var _attack_face_remaining:float = 0.0
var _gesture_serial:int = 0
var _dodge_visual_remaining:float = 0.0
var _dodge_stretch_scale:Vector2 = Vector2.ONE
var _dodge_stretch_pivot:Vector2 = Vector2.ZERO
var _dodge_stretch_tween:Tween = null
var _dodge_bar_alpha:float = 0.0
var _dodge_bar_hold_left:float = 0.0
var _dodge_bar_fade_left:float = 0.0
var _death_sequence_started:bool = false
var _death_visual_started_local:bool = false

var _active_gravity_key:String = ""
var _active_gravity_target:ball = null
var _active_gravity_old_terminal:float = 420.0
var _active_gravity_direction:Vector2 = Vector2.DOWN

var _boss_specialized:bool = false
var _last_trial_used:bool = false
var _last_trial_active:bool = false
var _last_trial_controller:Node = null
var _last_trial_launch_queued:bool = false
var _boss_special_skill1_cooldown_left:float = 0.0
var _boss_special_skill2_cooldown_left:float = 0.0
var _boss_special_global_lock_left:float = 0.0
var _boss_gravity_wall_sequence_serial:int = 0
var _rolling_bone_cooldown_left:float = 0.0
var _rolling_bone_sequence_serial:int = 0
var _rolling_bone_active:bool = false

# Boss 特殊化大风车只由 authority 驱动；具体龙骨炮仍通过现有 RPC 在所有端生成。
var _windmill_active:bool = false
var _windmill_cooldown_left:float = 0.0
var _windmill_serial:int = 0
# target instance_id -> {target_ref,key,direction,rotation,original_rotation,original_up_direction,original_terminal}
var _persistent_gravity_targets:Dictionary = {}
# target instance_id -> WeakRef；这里只记录“本 Sans 的 Boss 深蓝弹跳层”，用于避免重复叠 tint/refcount，并标记落地随机跳跃状态。
var _boss_blue_targets:Dictionary = {}


# Boss 特殊化：Sans 不接受 World 的通用 Boss 数值倍率。
# 开启特殊化时恢复 Sans 场景里的原始战斗数值，只额外把闪避上限提升到 30。
func has_training_boss_specialization() -> bool:
	return true


func prepare_training_boss_specialization(_boss_multiplier:float) -> void:
	Max_health = 1
	Damage = 1
	Speed = 112.0
	Health_Restore = 0
	max_block = 0
	max_energy = 0
	Attack_Cooling = 1.0
	Skill_Cooling = 999.0
	max_dodge_count = 30


func activate_training_boss_specialization(_boss_multiplier:float) -> void:
	_boss_specialized = true
	_boss_special_skill1_cooldown_left = maxf(boss_special_skill1_initial_delay,0.0)
	_boss_special_skill2_cooldown_left = maxf(boss_special_skill2_initial_delay,0.0)
	_windmill_cooldown_left = maxf(windmill_initial_delay,0.0)
	_rolling_bone_cooldown_left = maxf(rolling_bone_initial_delay,0.0)
	_boss_special_global_lock_left = 0.0


func _ready() -> void:
	_build_sans_visual()
	Has_Collision_Damage = false
	Can_Attack = true
	Can_Skill = false
	Health_Restore = 0
	Max_health = 1
	Damage = 1
	super._ready()

	health = mini(maxi(health,1),Max_health)
	var seed_value:int = Game.battle_rng_seed_or("scripts/characters/传说之下/Sans.gd:seed_value",maxi(abs(int(Time.get_ticks_usec()) ^ int(get_instance_id())),1))
	_dodge_rng.seed = seed_value
	_attack_rng.seed = seed_value ^ 0x51A45
	_dodge_count = maxi(max_dodge_count,1)
	_time_since_incoming_attack = 0.0
	_recovery_accumulator = 0.0
	_set_visual_mode_local(SansVisual.IDLE)
	# 初始满闪避不显示次数条；只有之后次数真的变化才短暂显示。
	_dodge_bar_alpha = 0.0
	_dodge_bar_hold_left = 0.0
	_dodge_bar_fade_left = 0.0
	call_deferred("_refresh_dodge_status")


func get_preview_texture() -> Texture2D:
	# World.create_ghost_ball() 在角色未进树、_ready() 尚未执行时调用。
	# Sans 正式视觉是 Body + Face 两个 Sprite，因此必须提供一张已经合成的单图预览。
	return _atlas_texture(BODY_PREVIEW)


# Sans 的 Right Strike 是一套固定朝右绘制的原始素材。
# “左砸”只允许把同一套帧从最后一帧倒放，不能让 ball 基类根据移动/AI 朝向自动镜像角色。
# ball 的公共朝向系统在有主 Shader 时不会改 Sprite2D.flip_h，而是写 instance shader uniform
# `sprite_flip_h`；因此只写 `_sans_body.flip_h = false` 不够，V162 才会仍然看起来被左右翻转，
# 并因为 Atlas 帧的非对称留白把身体整体推向右侧。
func set_character_visual_flip_h(_flipped:bool) -> void:
	# 仍调用父类，让其公共缓存/原生 flip 状态保持一致，但 Sans 永远请求“不翻转”。
	super.set_character_visual_flip_h(false)
	if _sans_body != null and is_instance_valid(_sans_body):
		_sans_body.flip_h = false
		_sans_body.flip_v = false
		_sans_body.set_instance_shader_parameter("sprite_flip_h",0.0)


func _process(delta:float) -> void:
	if _death_sequence_started or _death_visual_started_local:
		return
	var safe_delta:float = maxf(delta,0.0)
	if _attack_face_active:
		_attack_face_elapsed += safe_delta
		_attack_face_remaining = maxf(_attack_face_remaining - safe_delta,0.0)
		if _attack_face_remaining <= 0.0:
			_attack_face_active = false
			_attack_face_elapsed = 0.0
	if _visual_mode == SansVisual.DODGE:
		_dodge_visual_remaining = maxf(_dodge_visual_remaining - safe_delta,0.0)
		if _dodge_visual_remaining <= 0.0:
			_set_visual_mode_local(SansVisual.IDLE)
	_update_sans_visual(safe_delta)
	_update_dodge_bar_visual(safe_delta)


func _build_sans_visual() -> void:
	var legacy_image:Sprite2D = get_node_or_null("Graphics/Image") as Sprite2D
	var legacy_animated:AnimatedSprite2D = get_node_or_null("Graphics/AnimatedSprite2D") as AnimatedSprite2D
	if legacy_image != null:
		legacy_image.visible = false
	if legacy_animated != null:
		legacy_animated.visible = false

	_sans_body = Sprite2D.new()
	_sans_body.name = "SansBodyAtlas"
	_sans_body.centered = true
	_sans_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sans_body.scale = Vector2.ONE * SANS_VISUAL_SCALE
	_sans_body.z_index = 0
	if legacy_image != null and legacy_image.material != null:
		_sans_body.material = legacy_image.material.duplicate()
	graphics.add_child(_sans_body)
	# V172：per-instance uniform 不会随 ShaderMaterial 复制。显式设白，避免 power=1 时默认混成黑色。
	_sans_body.set_instance_shader_parameter("hit_white_color",Color.WHITE)
	_sans_body.set_instance_shader_parameter("power",0.0)

	_sans_face = Sprite2D.new()
	_sans_face.name = "SansFaceAtlas"
	_sans_face.centered = true
	_sans_face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sans_face.scale = Vector2.ONE * SANS_VISUAL_SCALE
	_sans_face.z_index = 1
	if legacy_image != null and legacy_image.material != null:
		_sans_face.material = legacy_image.material.duplicate()
	graphics.add_child(_sans_face)
	_sans_face.set_instance_shader_parameter("hit_white_color",Color.WHITE)
	_sans_face.set_instance_shader_parameter("power",0.0)

	_sans_sweat = Sprite2D.new()
	_sans_sweat.name = "SansSweatTopAtlas"
	_sans_sweat.centered = true
	_sans_sweat.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sans_sweat.scale = Vector2.ONE * SANS_VISUAL_SCALE
	_sans_sweat.z_index = 2
	_sans_sweat.visible = false
	graphics.add_child(_sans_sweat)

	_sans_eye_glow = Sprite2D.new()
	_sans_eye_glow.name = "SansEyeGlow"
	_sans_eye_glow.centered = true
	_sans_eye_glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sans_eye_glow.texture = _make_eye_glow_texture()
	_sans_eye_glow.z_index = 3
	_sans_eye_glow.visible = false
	var glow_material:=CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_sans_eye_glow.material = glow_material
	graphics.add_child(_sans_eye_glow)

	# 公共受击闪白、阵营颜色等继续以 body 作为主要 image 节点。
	image = _sans_body
	_apply_face_frame(NORMAL_FACE_INDEX)
	_set_visual_mode_local(SansVisual.IDLE)
	_update_sans_visual(0.0)


func _atlas_texture(region:Rect2) -> AtlasTexture:
	var atlas:=AtlasTexture.new()
	atlas.atlas = SANS_ATLAS
	atlas.region = region
	atlas.filter_clip = true
	return atlas


func _body_feet_anchor(region:Rect2) -> Vector2:
	if region == BODY_IDLE:
		return BODY_IDLE_FEET
	if region == BODY_DODGE:
		return BODY_DODGE_FEET
	for i:int in range(BODY_HAND_DOWN.size()):
		if region == BODY_HAND_DOWN[i]:
			return BODY_HAND_DOWN_FEET[i]
	for i:int in range(BODY_HAND_UP.size()):
		if region == BODY_HAND_UP[i]:
			return BODY_HAND_UP_FEET[i]
	for i:int in range(BODY_RIGHT_STRIKE.size()):
		if region == BODY_RIGHT_STRIKE[i]:
			return BODY_RIGHT_STRIKE_FEET[i]
	return Vector2(region.size.x * 0.5,region.size.y - 1.0)


func _apply_body_region(region:Rect2,_mode:int) -> void:
	if _sans_body == null or not is_instance_valid(_sans_body):
		return
	# V163：左挥绝不是左右镜像，只是 Right Strike 的帧序倒放。
	# Sans 的基类还可能通过主 Shader 的 `sprite_flip_h` 做角色朝向镜像，
	# 所以这里同时锁死原生 flip_h 与实例 Shader 参数，避免 5→0 倒放时再次被镜像并产生大幅横移。
	_sans_body.flip_h = false
	_sans_body.flip_v = false
	_sans_body.set_instance_shader_parameter("sprite_flip_h",0.0)
	if region != _current_body_region or _sans_body.texture == null:
		_current_body_region = region
		_sans_body.texture = _atlas_texture(region)
	var feet_anchor:Vector2 = _body_feet_anchor(region)
	var base_position:Vector2 = SANS_BODY_FEET_POINT - (feet_anchor - region.size * 0.5) * SANS_VISUAL_SCALE
	_apply_common_visual_stretch(_sans_body,base_position,Vector2.ONE * SANS_VISUAL_SCALE)


func _apply_common_visual_stretch(sprite:Sprite2D,base_position:Vector2,base_scale:Vector2) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	var stretch:Vector2 = _dodge_stretch_scale
	sprite.position = _dodge_stretch_pivot + (base_position - _dodge_stretch_pivot) * stretch
	sprite.scale = base_scale * stretch


func _face_bottom_world_point() -> Vector2:
	return SANS_NECK_POINT + Vector2.DOWN * SANS_FACE_DOWN_PX * SANS_VISUAL_SCALE


func _position_face_like(sprite:Sprite2D,region:Rect2) -> void:
	if sprite == null:
		return
	var bottom_center:=Vector2(region.size.x * 0.5,region.size.y)
	var base_position:Vector2 = _face_bottom_world_point() - (bottom_center - region.size * 0.5) * SANS_VISUAL_SCALE
	_apply_common_visual_stretch(sprite,base_position,Vector2.ONE * SANS_VISUAL_SCALE)


func _apply_face_region(region:Rect2) -> void:
	if _sans_face == null or not is_instance_valid(_sans_face):
		return
	if region != _current_face_region or _sans_face.texture == null:
		_current_face_region = region
		_sans_face.texture = _atlas_texture(region)
	_position_face_like(_sans_face,region)


func _apply_face_frame(index:int) -> void:
	var safe_index:int = clampi(index,0,BOSS_FACES.size() - 1)
	_face_frame = safe_index
	_apply_face_region(BOSS_FACES[safe_index])


func _make_eye_glow_texture() -> Texture2D:
	var size:int = 32
	var center:=Vector2(float(size - 1) * 0.5,float(size - 1) * 0.5)
	var radius:float = float(size) * 0.5
	var image_glow:=Image.create(size,size,false,Image.FORMAT_RGBA8)
	for y:int in range(size):
		for x:int in range(size):
			var distance:float = Vector2(float(x),float(y)).distance_to(center) / radius
			var alpha:float = pow(clampf(1.0 - distance,0.0,1.0),2.2) * 0.92
			image_glow.set_pixel(x,y,Color(1.0,1.0,1.0,alpha))
	return ImageTexture.create_from_image(image_glow)


func _sweat_index_for_current_dodge() -> int:
	var start_count:int = clampi(sweat_start_dodge_count,0,maxi(max_dodge_count,1))
	if start_count <= 0 or _dodge_count > start_count:
		return -1
	var heavy_max:int = int(floor(float(start_count) / 3.0))
	var medium_max:int = int(floor(float(start_count) * 2.0 / 3.0))
	if _dodge_count <= heavy_max:
		return 2
	if _dodge_count <= medium_max:
		return 1
	return 0


func _update_sweat_visual() -> void:
	if _sans_sweat == null or not is_instance_valid(_sans_sweat):
		return
	var next_index:int = _sweat_index_for_current_dodge()
	if next_index < 0:
		_sans_sweat.visible = false
		_sweat_frame = -1
		return
	_sans_sweat.visible = true
	if next_index != _sweat_frame or _sans_sweat.texture == null:
		_sweat_frame = next_index
		var region:Rect2 = SWEAT_TOP_OVERLAYS[next_index]
		_sans_sweat.texture = _atlas_texture(region)
		_position_face_like(_sans_sweat,region)


func _update_attack_eye_glow(face_region:Rect2,phase:int) -> void:
	if _sans_eye_glow == null or not is_instance_valid(_sans_eye_glow):
		return
	if not _attack_face_active or _visual_mode == SansVisual.DODGE:
		_sans_eye_glow.visible = false
		return
	_sans_eye_glow.visible = true
	var eye_source_px:=Vector2(25.0,12.5)
	_sans_eye_glow.position = _sans_face.position + (eye_source_px - face_region.size * 0.5) * SANS_VISUAL_SCALE
	var glow_color:Color = Color(0.30,0.96,1.0,1.0) if phase == 0 else Color(1.0,0.96,0.12,1.0)
	_sans_eye_glow.self_modulate = glow_color
	var pulse:float = 1.0 + sin(_attack_face_elapsed * TAU * 7.0) * 0.12
	_sans_eye_glow.scale = Vector2.ONE * (0.92 + attack_eye_glow_strength * 0.38) * pulse
	_sans_eye_glow.modulate.a = clampf(0.52 + attack_eye_glow_strength * 0.36,0.2,1.0)


func _update_face_visual() -> void:
	if _last_trial_active:
		_apply_face_frame(5) # Boss Faces 第六帧：双眼全黑，不是蓝/黄眼或闪避闭眼。
		if _sans_eye_glow != null:
			_sans_eye_glow.visible = false
		if _sans_sweat != null:
			_sans_sweat.visible = false
		return
	if _visual_mode == SansVisual.DODGE:
		_apply_face_frame(DODGE_FACE_INDEX)
		if _sans_eye_glow != null:
			_sans_eye_glow.visible = false
	else:
		if _attack_face_active:
			var interval:float = maxf(attack_eye_flash_interval,0.03)
			var phase:int = int(floor(_attack_face_elapsed / interval)) % ATTACK_GLOW_FACES.size()
			var region:Rect2 = ATTACK_GLOW_FACES[phase]
			_apply_face_region(region)
			_update_attack_eye_glow(region,phase)
		else:
			_apply_face_frame(NORMAL_FACE_INDEX)
			if _sans_eye_glow != null:
				_sans_eye_glow.visible = false
	_update_sweat_visual()

func _visual_animation_frames(mode:int) -> Array:
	match mode:
		SansVisual.GRAVITY_UP:
			return BODY_HAND_UP
		SansVisual.GRAVITY_DOWN:
			return BODY_HAND_DOWN
		SansVisual.GRAVITY_RIGHT, SansVisual.GRAVITY_LEFT:
			return BODY_RIGHT_STRIKE
	return []


func _update_sans_visual(delta:float) -> void:
	if _sans_body == null or not is_instance_valid(_sans_body):
		return
	_visual_elapsed += delta
	if _visual_mode == SansVisual.IDLE:
		_apply_body_region(BODY_IDLE,_visual_mode)
	elif _visual_mode == SansVisual.DODGE:
		_apply_body_region(BODY_DODGE,_visual_mode)
	else:
		# 只有重力攻击会逐帧切换身体；骨头/龙骨炮保持正常插兜。
		var frames:Array = _visual_animation_frames(_visual_mode)
		if frames.is_empty():
			_apply_body_region(BODY_IDLE,SansVisual.IDLE)
		else:
			var frame_duration:float = maxf(gravity_anim_frame_duration,0.02)
			var raw_index:int = mini(int(floor(_visual_elapsed / frame_duration)),frames.size() - 1)
			var display_index:int = raw_index
			if _visual_mode == SansVisual.GRAVITY_LEFT:
				display_index = frames.size() - 1 - raw_index
			if display_index != _visual_frame or _sans_body.texture == null:
				_visual_frame = display_index
				_apply_body_region(frames[display_index],_visual_mode)
	_update_face_visual()

func _reset_dodge_stretch() -> void:
	if _dodge_stretch_tween != null and _dodge_stretch_tween.is_valid():
		_dodge_stretch_tween.kill()
	_dodge_stretch_tween = null
	_dodge_stretch_scale = Vector2.ONE
	_dodge_stretch_pivot = Vector2.ZERO


func _capture_dodge_stretch_pivot() -> void:
	# 先用未拉伸的闪避姿势求 Body + Face 的真实组合包围盒中心。
	# 后面的拉长只围绕这个点展开，所以视觉中心不会上下漂。
	_dodge_stretch_scale = Vector2.ONE
	_update_sans_visual(0.0)
	var body_size:Vector2 = BODY_DODGE.size * SANS_VISUAL_SCALE
	var face_region:Rect2 = BOSS_FACES[clampi(DODGE_FACE_INDEX,0,BOSS_FACES.size() - 1)]
	var face_size:Vector2 = face_region.size * SANS_VISUAL_SCALE
	var body_rect:=Rect2(_sans_body.position - body_size * 0.5,body_size)
	var face_rect:=Rect2(_sans_face.position - face_size * 0.5,face_size)
	_dodge_stretch_pivot = body_rect.merge(face_rect).get_center()


func _set_dodge_stretch_scale(value:Vector2) -> void:
	_dodge_stretch_scale = value
	_update_sans_visual(0.0)


func _play_dodge_stretch_and_flash() -> void:
	if _sans_body == null or _sans_face == null:
		return
	_reset_dodge_stretch()
	_capture_dodge_stretch_pivot()

	# 闪避成功后只做视觉闪白，不进入 Hurt 状态。
	# V172：KR/其它效果可能临时改过 hit_white_color；闪避反馈必须强制使用纯白。
	if _sans_body != null and is_instance_valid(_sans_body):
		_sans_body.set_instance_shader_parameter("hit_white_color",Color.WHITE)
	if _sans_face != null and is_instance_valid(_sans_face):
		_sans_face.set_instance_shader_parameter("hit_white_color",Color.WHITE)
	if hit_white_tween != null and hit_white_tween.is_valid():
		hit_white_tween.kill()
	hit_white_method(1.0)
	hit_white_tween = create_tween().bind_node(self)
	hit_white_tween.tween_method(hit_white_method,1.0,0.0,maxf(dodge_flash_duration,0.03))

	var stretched:=Vector2(clampf(dodge_stretch_x,0.45,1.0),maxf(dodge_stretch_y,1.05))
	_dodge_stretch_tween = create_tween().bind_node(self)
	_dodge_stretch_tween.tween_method(
		_set_dodge_stretch_scale,
		Vector2.ONE,
		stretched,
		maxf(dodge_stretch_out_duration,0.02)
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_dodge_stretch_tween.tween_method(
		_set_dodge_stretch_scale,
		stretched,
		Vector2.ONE,
		maxf(dodge_stretch_return_duration,0.08)
	).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _set_attack_face_active_networked(active:bool,duration:float = 0.0) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_set_attack_face_active.rpc(active,duration)
	else:
		_rpc_set_attack_face_active(active,duration)


func _trigger_attack_eye_flash_burst_networked() -> void:
	if not _is_fast_attack_phase():
		_set_attack_face_active_networked(false,0.0)
		return
	var duration:float = maxf(attack_eye_flash_interval,0.03) * float(maxi(attack_eye_flash_count,2))
	_set_attack_face_active_networked(true,duration)


@rpc("authority","call_local","reliable")
func _rpc_set_attack_face_active(active:bool,duration:float = 0.0) -> void:
	_attack_face_active = active
	_attack_face_elapsed = 0.0
	_attack_face_remaining = maxf(duration,0.0) if active else 0.0
	_update_face_visual()


func _set_visual_mode_networked(mode:int) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_set_visual_mode.rpc(mode)
	else:
		_rpc_set_visual_mode(mode)


@rpc("authority","call_local","reliable")
func _rpc_set_visual_mode(mode:int) -> void:
	_set_visual_mode_local(mode)


func _set_visual_mode_local(mode:int) -> void:
	_visual_mode = clampi(mode,SansVisual.IDLE,SansVisual.GRAVITY_LEFT)
	_visual_elapsed = 0.0
	_visual_frame = -1
	_current_body_region = Rect2(-999.0,-999.0,0.0,0.0)
	if _visual_mode == SansVisual.DODGE:
		_dodge_visual_remaining = maxf(dodge_visual_duration,0.1)
	else:
		_dodge_visual_remaining = 0.0
	_update_sans_visual(0.0)


func hit_white_method(power:float):
	super.hit_white_method(power)
	if _sans_face != null and is_instance_valid(_sans_face):
		_sans_face.set_instance_shader_parameter("power",power)


func tick_physics(state:State,delta:float) -> void:
	if _last_trial_active:
		velocity = Vector2.ZERO
		Repel = Vector2.ZERO
		if not _last_trial_used and not _last_trial_launch_queued and is_multiplayer_authority():
			_last_trial_launch_queued = true
			_launch_last_trial.call_deferred()
		return
	if is_multiplayer_authority() and state != State.Die and health > 0:
		var safe_delta:float = maxf(delta,0.0)
		_dodge_grace_remaining = maxf(_dodge_grace_remaining - safe_delta,0.0)
		_boss_special_global_lock_left = maxf(_boss_special_global_lock_left - safe_delta,0.0)
		_update_dodge_recovery(safe_delta)
		_update_boss_special_skill1(safe_delta)
		_update_boss_special_skill2(safe_delta)
		_update_boss_windmill(safe_delta)
		_update_boss_rolling_bones(safe_delta)
		_maintain_persistent_gravity_targets(safe_delta)
	super.tick_physics(state,delta)


# ========================================================
# 攻击入口
# ========================================================
func Attack() -> void:
	if _last_trial_active:
		Attacking = false
		return
	if not is_multiplayer_authority() or health <= 0 or state_machine == null or state_machine.current_state == State.Die:
		Attacking = false
		return
	if is_damage_output_disabled():
		Attacking = false
		return

	var target:ball = _resolve_attack_target()
	if target == null:
		Attacking = false
		return

	# V63：大风车是完全独占攻击阶段。进行期间 Sans 不再追加任何普通攻击，
	# 包括此前 V62 仍允许的重力砸；这样炮圈中途不会夹进别的攻击。
	if _windmill_active:
		Attacking = false
		return

	# 滚动骨头期间继续沿用 V62 规则：普通骨墙/普通单龙骨炮被封锁，
	# 但仍允许单独使用重力控制，避免滚动骨头占墙时叠出第二种骨头效果。
	if _rolling_bone_active:
		if _active_gravity_target != null and is_instance_valid(_active_gravity_target):
			Attacking = false
			return
		Attacking = true
		_trigger_attack_eye_flash_burst_networked()
		_start_gravity_attack_background(target)
		if state_machine != null:
			state_machine.last_state_dis["Attack"] = Attack_Cooling - _attack_post_cooldown_for_current_dodge()
		Attacking = false
		return

	# V160：Attack 状态只代表“下达一次攻击指令”。
	# 已经召唤出去的骨头/龙骨炮，以及已经开始的重力位移，都作为独立后续效果继续运行，
	# 不再把 Sans 锁在 Attack 状态直到整套演出结束。
	Attacking = true
	_trigger_attack_eye_flash_burst_networked()

	var attack_kind:int = _pick_attack_kind_for_launch()
	match attack_kind:
		SansAttack.GRAVITY:
			_start_gravity_attack_background(target)
		SansAttack.BONES:
			_summon_bone_attack(target)
		SansAttack.GASTER:
			_summon_gaster_attack(target)

	# 冷却从“召唤/砸的起手”这一刻开始。后续射击、刺出、砸落过程不算新的攻击动作。
	if state_machine != null:
		state_machine.last_state_dis["Attack"] = Attack_Cooling - _attack_post_cooldown_for_current_dodge()
	Attacking = false


func _pick_attack_kind_for_launch() -> int:
	# 同一个 Sans 当前已经有一个重力砸在执行时，不再开启第二套会互相覆盖的 directional-gravity key；
	# 快攻期间仍可继续召唤骨头或龙骨炮。
	if _active_gravity_target != null and is_instance_valid(_active_gravity_target):
		return SansAttack.BONES if _attack_rng.randi_range(0,1) == 0 else SansAttack.GASTER
	return _attack_rng.randi_range(SansAttack.GRAVITY,SansAttack.GASTER)


func _is_fast_attack_phase() -> bool:
	var high_min:int = clampi(attack_high_dodge_min,0,maxi(max_dodge_count,1))
	var medium_min:int = clampi(attack_medium_dodge_min,0,high_min)
	return _dodge_count >= medium_min and _dodge_count < high_min


func _attack_post_cooldown_for_current_dodge() -> float:
	var high_min:int = clampi(attack_high_dodge_min,0,maxi(max_dodge_count,1))
	var medium_min:int = clampi(attack_medium_dodge_min,0,high_min)
	var multiplier:float = 1.0
	if _dodge_count < medium_min:
		multiplier = maxf(attack_low_cooldown_multiplier,1.0)
	elif _dodge_count < high_min:
		multiplier = clampf(attack_medium_cooldown_multiplier,0.10,1.0)
	return maxf(attack_post_cooldown * multiplier,0.05)


func _resolve_attack_target() -> ball:
	var reusable:Node = return_reusable_combat_target()
	if reusable is ball and _is_valid_enemy(reusable as ball):
		return reusable as ball

	var nearest:ball = null
	var nearest_distance_sq:float = INF
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var candidate:ball = raw as ball
		if not _is_valid_enemy(candidate):
			continue
		var distance_sq:float = global_position.distance_squared_to(candidate.global_position)
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest = candidate
	return nearest


# ========================================================
# V50：Boss 特殊化“大风车”（细炮 / 短寿命 / 高密度）
#
# 原版式表现：不是一圈同时摆很多门炮，也不是追着某个敌人瞄准。
# 整段只有“一门接一门”的细龙骨炮轨迹沿地图外围高速刷出；单炮很快消失，密度靠高生成频率形成，所有炮固定瞄准地图中心。
# 默认 5 个完整圆周；V63 起技能期间 Attack() 完全锁定，不再追加重力、骨墙或普通单龙骨炮。
# ========================================================
func _update_boss_windmill(_delta:float) -> void:
	pass # 大风车仅由最后一次闪避终幕的共享时间线生成，不再自动/手动独立施放。


func _release_gravity_for_windmill() -> void:
	# V63：进入大风车前，把“这个 Sans”施加的持久重力全部撤掉。
	# _expire_persistent_gravity_target() 会立刻恢复普通 locomotion / up_direction / 蓝色状态，
	# 同时开始平滑恢复人物朝向；随后再提高一次残余重力速度的衰减率，让速度快速回归正常。
	if _persistent_gravity_targets.is_empty():
		return
	var released_ids:Array[int] = []
	for raw_id:Variant in _persistent_gravity_targets.keys():
		var target_id:int = int(raw_id)
		var state:Dictionary = _persistent_gravity_targets.get(target_id,{})
		var target_ref:WeakRef = state.get("target_ref",null)
		var target:ball = (target_ref.get_ref() as ball) if target_ref != null else null
		if target != null and is_instance_valid(target) and target.is_inside_tree():
			_expire_persistent_gravity_target(target,state)
			if target.has_method("begin_external_directional_gravity_release"):
				target.call(
					"begin_external_directional_gravity_release",
					maxf(windmill_gravity_release_velocity_deceleration,gravity_restore_velocity_deceleration)
				)
		released_ids.append(target_id)
	for target_id:int in released_ids:
		_persistent_gravity_targets.erase(target_id)
		_boss_blue_targets.erase(target_id)


func _start_windmill() -> void:
	pass # 保留旧接口兼容旧引用，但独立施放入口已经关闭。


func _run_windmill_sequence(serial:int,map_rect:Rect2) -> void:
	var rounds:int = maxi(windmill_round_count,1)
	var per_round:int = maxi(windmill_blaster_count_per_round,12)
	# V57：原版式“大风车”不人为挖掉任何角度。
	# 每一门炮都沿同一条连续圆周轨迹依次出现；炮体先出现并停在待发状态，
	# 过 windmill_prefire_delay 后才开始出激光。这样旋转前端会是一段“已经看得见但还没开火”的新炮，
	# 旋转尾端则是刚刚熄灭的旧炮，二者之间自然形成随圆环移动的安全缺口。
	# V60：当前 30 门/圈、0.072s 间隔，一圈仍约 2.16s；炮位间角度明显增大，
	# 避免大量炮体彼此覆盖，同时保留 V57 的待发/自然时间缺口机制。
	# 继续使用轻微非整数等效槽位数，让跨圈时不会出现明显“回到同一批像素点”的卡槽感，
	# 但角度本身始终单调连续推进，不跳过任何炮位。
	var effective_slots_per_turn:float = float(per_round) + 0.61803398875
	var angular_step:float = TAU / effective_slots_per_turn
	var total_angle:float = TAU * float(rounds)
	var total_steps:int = maxi(int(ceil(total_angle / angular_step)),1)
	var start_angle:float = _attack_rng.randf_range(-PI,PI)
	# 原版最终炮圈按逆时针顺序推进；Godot 2D 屏幕坐标下负角速度对应视觉逆时针。
	var spin_sign:float = -1.0
	var spawn_delay:float = maxf(windmill_spawn_interval,0.010)

	for step_index:int in range(total_steps):
		if not _is_windmill_sequence_valid(serial):
			_finish_windmill_sequence(serial)
			return
		var swept_angle:float = minf(float(step_index) * angular_step,total_angle)
		var angle:float = start_angle + spin_sign * swept_angle
		_spawn_windmill_gaster(map_rect,angle)
		if step_index < total_steps - 1:
			await get_tree().create_timer(spawn_delay).timeout

	_finish_windmill_sequence(serial)


func _is_windmill_sequence_valid(serial:int) -> bool:
	return (
		serial == _windmill_serial
		and _windmill_active
		and is_inside_tree()
		and health > 0
		and not _death_sequence_started
		and is_multiplayer_authority()
		and not is_damage_output_disabled()
	)


func _finish_windmill_sequence(serial:int) -> void:
	if serial != _windmill_serial:
		return
	_windmill_active = false


func _cancel_windmill() -> void:
	_windmill_serial += 1
	_windmill_active = false


func _spawn_windmill_gaster(map_rect:Rect2,angle:float) -> void:
	if not _last_trial_active or not is_instance_valid(_last_trial_controller):
		return
	if _last_trial_controller.elapsed < _last_trial_controller.WIND_START or _last_trial_controller.elapsed >= _last_trial_controller.wind_end:
		return
	var center:Vector2 = map_rect.position + map_rect.size * 0.5
	var outward:=Vector2.RIGHT.rotated(angle).normalized()
	var half:Vector2 = map_rect.size * 0.5
	# V54：大风车不再把炮“钉”在矩形四条墙的固定边缘点。
	# 原版这一段是 ring/circle：这里使用真正的圆环半径，让炮位按角度连续绕中心
	# 一圈圈出现，而不是沿四条墙形成固定矩形槽位。半径取地图半对角线再加外侧留白，
	# 保证整个圆环都在地图外。
	var ring_padding:float = maxf(gaster_map_outside_offset,20.0)
	var ring_radius:float = half.length() + ring_padding
	var park:Vector2 = center + outward * ring_radius
	# V51：大风车不再整体缩小龙骨炮。高度/长度保持正常，仅由龙骨炮脚本压窄局部 X。
	var size_scale:float = 1.0
	var body_width_scale:float = clampf(windmill_body_width_scale,0.20,1.50)
	var spawn_distance:float = _gaster_required_offscreen_distance(park,outward,size_scale)
	var spawn:Vector2 = park + outward * spawn_distance

	# 大风车永远以地图中心作为“瞄准点”，这里只用于决定发射方向。
	# V53/V57：激光保持普通龙骨炮的贯穿长度，会穿过中心继续射向另一侧窗口外；
	# 不再人为跳过任何角度，安全缺口只由“待发延迟 + 旧激光熄灭”的时序自然产生。
	var aim_point:Vector2 = center
	var appearance_duration:float = maxf(windmill_appearance_duration,0.10)
	var prefire_delay:float = maxf(windmill_prefire_delay,0.0)
	# V62：大风车的“宽度→音色”改由 Sans龙骨炮.gd 直接根据 body_width_scale 调整 pitch。
	# 不再用宽度偷偷改 attack_duration，否则既难听出对应关系，也会破坏大风车自然缺口的时序。
	var attack_duration:float = maxf(windmill_attack_duration,0.30)
	var beam_ratio:float = clampf(windmill_beam_width_ratio,0.05,0.80)
	var stop_beam_at_center:bool = false
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_gaster.rpc(spawn,park,aim_point,"",map_rect,size_scale,appearance_duration,attack_duration,beam_ratio,body_width_scale,stop_beam_at_center,prefire_delay)
	else:
		_rpc_spawn_gaster(spawn,park,aim_point,"",map_rect,size_scale,appearance_duration,attack_duration,beam_ratio,body_width_scale,stop_beam_at_center,prefire_delay)


# ========================================================
# V49：Boss 特殊技能 3：Undertale 风格“滚动骨头”
#
# “滚动”不是让完整双头骨在场内自转飞行，而是让骨头根部始终插在墙线上，
# 整根骨头沿墙的切线方向从地图外滚进来，再从另一端滚出去。
# 随机三种图案：
# 1) 单墙连续小骨头；
# 2) 单墙一排统一长度骨头；
# 3) 两个相对墙同时出骨头，两边移动方向相反；每面墙各自统一一种长度。
# ========================================================
func _update_boss_rolling_bones(delta:float) -> void:
	if not _boss_specialized:
		return
	_rolling_bone_cooldown_left = maxf(_rolling_bone_cooldown_left - maxf(delta,0.0),0.0)
	if is_player_controlled():
		return
	if _rolling_bone_active or _windmill_active or _rolling_bone_cooldown_left > 0.0 or _boss_special_global_lock_left > 0.0:
		return
	if not is_combat_runtime_active() or is_damage_output_disabled():
		return
	if state_machine == null or state_machine.current_state == State.Die:
		return
	if _active_gravity_target != null and is_instance_valid(_active_gravity_target):
		return
	if _resolve_attack_target() == null:
		return
	_start_rolling_bone_skill()


func _try_cast_boss_rolling_bones() -> bool:
	if not _boss_specialized or _rolling_bone_active or _windmill_active:
		return false
	if _rolling_bone_cooldown_left > 0.0 or _boss_special_global_lock_left > 0.0 or is_damage_output_disabled():
		return false
	if _resolve_attack_target() == null:
		return false
	_start_rolling_bone_skill()
	return _rolling_bone_active


func _has_active_own_wall_bone_effect() -> bool:
	# V62：滚动骨头开始前必须等这个 Sans 之前的地刺/整墙骨头完全退场。
	# 否则即使滚动技能内部只有一种图案，同一面墙仍可能和上一发普通骨墙叠在一起。
	for raw:Node in get_tree().get_nodes_in_group("BattleTransient"):
		if raw == null or not is_instance_valid(raw) or str(raw.name) != "Sans骨头攻击":
			continue
		var effect_source:Variant = raw.get("source")
		if effect_source == self:
			return true
	return false


func _start_rolling_bone_skill() -> void:
	if not _boss_specialized or _rolling_bone_active or _windmill_active:
		return
	if _has_active_own_wall_bone_effect():
		return
	var map_rect:Rect2 = _current_map_world_rect()
	if map_rect.size.x <= 1.0 or map_rect.size.y <= 1.0:
		return
	_rolling_bone_active = true
	_rolling_bone_cooldown_left = maxf(rolling_bone_cooldown,0.1)
	_boss_special_global_lock_left = maxf(boss_special_global_lock,0.1)
	_rolling_bone_sequence_serial += 1
	var serial:int = _rolling_bone_sequence_serial
	var pattern:int = _attack_rng.randi_range(0,2)
	_trigger_attack_eye_flash_burst_networked()
	_run_rolling_bone_sequence(serial,map_rect,pattern)


func _run_rolling_bone_sequence(serial:int,map_rect:Rect2,pattern:int) -> void:
	match clampi(pattern,0,2):
		0:
			await _run_rolling_small_stream(serial,map_rect)
		1:
			await _run_rolling_single_wall_row(serial,map_rect)
		_:
			await _run_rolling_opposite_walls(serial,map_rect)
	_finish_rolling_bone_sequence(serial)


func _rolling_sequence_valid(serial:int) -> bool:
	return (
		serial == _rolling_bone_sequence_serial
		and _rolling_bone_active
		and is_inside_tree()
		and health > 0
		and not _death_sequence_started
		and is_multiplayer_authority()
		and not is_damage_output_disabled()
	)


func _rolling_wall_span(map_rect:Rect2,side:int) -> float:
	return map_rect.size.x if side == WallSide.TOP or side == WallSide.BOTTOM else map_rect.size.y


func _rolling_wall_root(map_rect:Rect2,side:int,lateral:float) -> Vector2:
	match side:
		WallSide.TOP:
			return Vector2(map_rect.position.x + lateral,map_rect.position.y)
		WallSide.RIGHT:
			return Vector2(map_rect.end.x,map_rect.position.y + lateral)
		WallSide.BOTTOM:
			return Vector2(map_rect.position.x + lateral,map_rect.end.y)
		_:
			return Vector2(map_rect.position.x,map_rect.position.y + lateral)


func _rolling_wall_tangent(side:int) -> Vector2:
	if side == WallSide.TOP or side == WallSide.BOTTOM:
		return Vector2.RIGHT
	return Vector2.DOWN


func _rolling_random_speed() -> float:
	return _attack_rng.randf_range(
		minf(rolling_bone_speed_min,rolling_bone_speed_max),
		maxf(rolling_bone_speed_min,rolling_bone_speed_max)
	)


func _rolling_random_size() -> float:
	return _attack_rng.randf_range(
		minf(rolling_bone_size_min,rolling_bone_size_max),
		maxf(rolling_bone_size_min,rolling_bone_size_max)
	)


func _rolling_start_lateral(span:float,margin:float,direction_sign:float,behind:float = 0.0) -> float:
	if direction_sign >= 0.0:
		return -margin - maxf(behind,0.0)
	return span + margin + maxf(behind,0.0)


func _run_rolling_small_stream(serial:int,map_rect:Rect2) -> void:
	var side:int = _attack_rng.randi_range(WallSide.TOP,WallSide.LEFT)
	var direction_sign:float = -1.0 if _attack_rng.randi_range(0,1) == 0 else 1.0
	var span:float = _rolling_wall_span(map_rect,side)
	var margin:float = maxf(rolling_bone_offscreen_margin,24.0)
	var speed:float = _rolling_random_speed()
	var count:int = maxi(rolling_bone_count,4)
	var min_len:float = minf(rolling_bone_small_length_min,rolling_bone_small_length_max)
	var max_len:float = maxf(rolling_bone_small_length_min,rolling_bone_small_length_max)
	_play_direction_gesture_for_side(side)

	# V62：同一面墙只使用一种小骨头效果：长度和视觉宽度都只抽一次。
	# 之前虽然长度固定，但每根骨头仍各自随机 size_scale，实机看起来依然像同墙混了多种骨头。
	var wall_length:float = _attack_rng.randf_range(min_len,max_len)
	var wall_size:float = _rolling_random_size()
	for i:int in range(count):
		if not _rolling_sequence_valid(serial):
			return
		var length:float = wall_length
		var start_lateral:float = _rolling_start_lateral(span,margin,direction_sign)
		var distance:float = span + margin * 2.0
		_spawn_wall_rolling_bone_networked(
			_rolling_wall_root(map_rect,side,start_lateral),
			_wall_inward_direction(side),
			_rolling_wall_tangent(side) * direction_sign,
			distance,speed,length,wall_size
		)
		if i < count - 1:
			await get_tree().create_timer(maxf(rolling_bone_spawn_interval,0.03)).timeout

	# 等最后一根骨头基本走完再释放技能锁，避免下一种 Boss 特殊技立刻叠进来。
	await get_tree().create_timer((span + margin * 2.0) / maxf(speed,20.0)).timeout


func _run_rolling_single_wall_row(serial:int,map_rect:Rect2) -> void:
	var side:int = _attack_rng.randi_range(WallSide.TOP,WallSide.LEFT)
	var direction_sign:float = -1.0 if _attack_rng.randi_range(0,1) == 0 else 1.0
	var span:float = _rolling_wall_span(map_rect,side)
	var margin:float = maxf(rolling_bone_offscreen_margin,24.0)
	var speed:float = _rolling_random_speed()
	var count:int = maxi(rolling_bone_count,5)
	var spacing:float = maxf(rolling_bone_train_spacing,12.0)
	var base_len:float = _attack_rng.randf_range(
		minf(rolling_bone_row_length_min,rolling_bone_row_length_max),
		maxf(rolling_bone_row_length_min,rolling_bone_row_length_max)
	)
	_play_direction_gesture_for_side(side)

	# V62：一面墙最多一种骨头效果；这一整排统一长度、统一视觉尺寸。
	var wall_size:float = _rolling_random_size()
	for i:int in range(count):
		if not _rolling_sequence_valid(serial):
			return
		var length:float = base_len
		var behind:float = spacing * float(i)
		var start_lateral:float = _rolling_start_lateral(span,margin,direction_sign,behind)
		var distance:float = span + margin * 2.0 + behind
		_spawn_wall_rolling_bone_networked(
			_rolling_wall_root(map_rect,side,start_lateral),
			_wall_inward_direction(side),
			_rolling_wall_tangent(side) * direction_sign,
			distance,speed,length,wall_size
		)

	await get_tree().create_timer((span + margin * 2.0 + spacing * float(count - 1)) / maxf(speed,20.0)).timeout


func _run_rolling_opposite_walls(serial:int,map_rect:Rect2) -> void:
	# 0 = 上/下；1 = 左/右。两面墙的骨头沿各自墙面朝相反方向滚动。
	var horizontal_pair:bool = _attack_rng.randi_range(0,1) == 0
	var side_a:int = WallSide.TOP if horizontal_pair else WallSide.LEFT
	var side_b:int = WallSide.BOTTOM if horizontal_pair else WallSide.RIGHT
	var sign_a:float = -1.0 if _attack_rng.randi_range(0,1) == 0 else 1.0
	var sign_b:float = -sign_a
	var span:float = _rolling_wall_span(map_rect,side_a)
	var margin:float = maxf(rolling_bone_offscreen_margin,24.0)
	var speed:float = _rolling_random_speed()
	# V60：相对双墙图案故意更疏。两侧各少量骨头，并保留大间距，
	# 让两条反向移动骨列之间有明确的大空档可穿行。
	var count:int = maxi(rolling_bone_opposite_count,2)
	var spacing:float = maxf(rolling_bone_opposite_spacing,40.0)
	# V62：相对双墙也只使用一种统一骨头效果。两面墙共用同一长度和同一视觉尺寸，
	# 只保留“移动方向相反”这一差异，避免看起来像两套骨头花样叠在同一技能里。
	var min_row_len:float = minf(rolling_bone_row_length_min,rolling_bone_row_length_max)
	var max_row_len:float = maxf(rolling_bone_row_length_min,rolling_bone_row_length_max)
	var shared_len:float = _attack_rng.randf_range(min_row_len,max_row_len)
	var shared_size:float = _rolling_random_size()
	_play_direction_gesture_for_side(side_a)

	for i:int in range(count):
		if not _rolling_sequence_valid(serial):
			return
		var behind:float = spacing * float(i)
		var lateral_a:float = _rolling_start_lateral(span,margin,sign_a,behind)
		var lateral_b:float = _rolling_start_lateral(span,margin,sign_b,behind)
		var distance:float = span + margin * 2.0 + behind
		var length_a:float = shared_len
		var length_b:float = shared_len
		_spawn_wall_rolling_bone_networked(
			_rolling_wall_root(map_rect,side_a,lateral_a),
			_wall_inward_direction(side_a),
			_rolling_wall_tangent(side_a) * sign_a,
			distance,speed,length_a,shared_size
		)
		_spawn_wall_rolling_bone_networked(
			_rolling_wall_root(map_rect,side_b,lateral_b),
			_wall_inward_direction(side_b),
			_rolling_wall_tangent(side_b) * sign_b,
			distance,speed,length_b,shared_size
		)

	await get_tree().create_timer((span + margin * 2.0 + spacing * float(count - 1)) / maxf(speed,20.0)).timeout


func _finish_rolling_bone_sequence(serial:int) -> void:
	if serial != _rolling_bone_sequence_serial:
		return
	_rolling_bone_active = false


func _cancel_rolling_bones() -> void:
	_rolling_bone_sequence_serial += 1
	_rolling_bone_active = false


func _spawn_wall_rolling_bone_networked(
	root_position:Vector2,
	inward:Vector2,
	travel_direction:Vector2,
	distance:float,
	speed:float,
	bone_length:float,
	size_scale:float
) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_rolling_bone.rpc(root_position,inward,travel_direction,distance,speed,bone_length,size_scale)
	else:
		_rpc_spawn_rolling_bone(root_position,inward,travel_direction,distance,speed,bone_length,size_scale)


@rpc("authority","call_local","reliable")
func _rpc_spawn_rolling_bone(
	root_position:Vector2,
	inward:Vector2,
	travel_direction:Vector2,
	distance:float,
	speed:float,
	bone_length:float,
	size_scale:float
) -> void:
	var parent:Node = get_tree().current_scene
	if parent == null:
		return
	var effect:Node2D = ROLLING_BONE_SCRIPT.new() as Node2D
	if effect == null:
		return
	effect.name = "Sans滚动骨头"
	effect.add_to_group("BattleTransient")
	parent.add_child(effect)
	effect.call(
		"configure",self,root_position,inward,travel_direction,distance,speed,bone_length,size_scale,5.0,1.0
	)


# ========================================================
# Boss 特殊技能 1：深蓝跳跃
#
# 保持 V35 的“Boss 数值不变”原则：不改 Can_Skill / Skill_Cooling，
# 使用独立冷却。AI 会自动施放；玩家直接控制 Boss Sans 时右键走 controlled_skill_action()。
# 效果持续到目标死亡或本 Sans 死亡：目标保持深蓝、持续吃当前方向的标准重力。
# 目标落地后等待随机时间，再以自己的 Speed 朝反重力方向起跳；左右仍按正常移速移动并碰墙反向。
# ========================================================
func controlled_skill_action() -> void:
	if _last_trial_active:
		return
	if not _boss_specialized or _boss_special_global_lock_left > 0.0:
		return
	# 玩家直接控制时按“整墙骨头 -> 滚动骨头 -> 大风车 -> 深蓝跳跃”的可用顺序施放，
	# 各自使用独立冷却，因此不会把原 Skill_Cooling 改掉。
	if _try_cast_boss_special_skill2():
		return
	if _try_cast_boss_rolling_bones():
		return
	_try_cast_boss_special_skill1()


func _update_boss_special_skill1(delta:float) -> void:
	if not _boss_specialized:
		return
	_boss_special_skill1_cooldown_left = maxf(_boss_special_skill1_cooldown_left - maxf(delta,0.0),0.0)
	_cleanup_invalid_gravity_target_refs()
	if is_player_controlled():
		return
	if _boss_special_skill1_cooldown_left > 0.0 or _boss_special_global_lock_left > 0.0 or _windmill_active or _rolling_bone_active:
		return
	if not is_combat_runtime_active() or is_damage_output_disabled():
		return
	if state_machine == null or state_machine.current_state == State.Die:
		return
	# 不在一次重力砸的飞行阶段中途切换目标物理模式，避免墙面落点判定被反弹打断。
	if _active_gravity_target != null and is_instance_valid(_active_gravity_target):
		return
	_try_cast_boss_special_skill1()


func _try_cast_boss_special_skill1() -> bool:
	if not _boss_specialized or not is_multiplayer_authority() or health <= 0:
		return false
	if _boss_special_skill1_cooldown_left > 0.0 or _boss_special_global_lock_left > 0.0 or _windmill_active or _rolling_bone_active or is_damage_output_disabled():
		return false
	var target:ball = _resolve_boss_special_skill1_target()
	if target == null:
		return false

	_boss_special_skill1_cooldown_left = maxf(boss_special_skill1_cooldown,0.1)
	_boss_special_global_lock_left = maxf(boss_special_global_lock,0.1)
	_trigger_attack_eye_flash_burst_networked()
	_apply_boss_blue_hop(target)
	return true


# Boss 特殊技能 2：安全重力 + 整墙低骨头。
# 先把目标的持久重力切到一个“目标当前没有贴近”的墙方向；短暂延迟后，
# 在目标会落向的那整面墙上铺一条低矮骨头带。
func _update_boss_special_skill2(delta:float) -> void:
	if not _boss_specialized:
		return
	_boss_special_skill2_cooldown_left = maxf(_boss_special_skill2_cooldown_left - maxf(delta,0.0),0.0)
	if is_player_controlled():
		return
	if _boss_special_skill2_cooldown_left > 0.0 or _boss_special_global_lock_left > 0.0 or _windmill_active or _rolling_bone_active:
		return
	if not is_combat_runtime_active() or is_damage_output_disabled():
		return
	if state_machine == null or state_machine.current_state == State.Die:
		return
	if _active_gravity_target != null and is_instance_valid(_active_gravity_target):
		return
	_try_cast_boss_special_skill2()


func _try_cast_boss_special_skill2() -> bool:
	if not _boss_specialized or not is_multiplayer_authority() or health <= 0:
		return false
	if _boss_special_skill2_cooldown_left > 0.0 or _boss_special_global_lock_left > 0.0 or _windmill_active or _rolling_bone_active or is_damage_output_disabled():
		return false
	var target:ball = _resolve_boss_special_skill1_target()
	if target == null:
		return false
	var map_rect:Rect2 = _current_map_world_rect()
	if map_rect.size.x <= 1.0 or map_rect.size.y <= 1.0:
		return false
	var side:int = _choose_safe_gravity_side_for_target(target,map_rect)
	var direction:Vector2 = _wall_inward_direction(side)
	if direction.length_squared() <= 0.000001:
		return false

	_boss_special_skill2_cooldown_left = maxf(boss_special_skill2_cooldown,0.1)
	_boss_special_global_lock_left = maxf(boss_special_global_lock,0.1)
	_boss_gravity_wall_sequence_serial += 1
	var serial:int = _boss_gravity_wall_sequence_serial
	_trigger_attack_eye_flash_burst_networked()
	_play_direction_gesture_for_side(side)
	_set_persistent_target_gravity(target,direction,true)
	_run_boss_gravity_wall_bones(serial,weakref(target),map_rect,direction)
	return true


func _run_boss_gravity_wall_bones(serial:int,target_ref:WeakRef,map_rect:Rect2,direction:Vector2) -> void:
	var tree:SceneTree = get_tree()
	if tree == null:
		return
	await tree.create_timer(maxf(boss_gravity_wall_bone_delay,0.05)).timeout
	if serial != _boss_gravity_wall_sequence_serial or not _boss_specialized or health <= 0 or _death_sequence_started:
		return
	var target:ball = null
	if target_ref != null:
		target = target_ref.get_ref() as ball
	if not _is_valid_enemy(target):
		return
	var wall_side:int = _wall_side_for_gravity_direction(direction)
	var attack_rect:Rect2 = _make_full_wall_bone_rect(map_rect,wall_side)
	if attack_rect.size.x <= 1.0 or attack_rect.size.y <= 1.0:
		return
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_bone_attack.rpc(attack_rect,wall_side)
	else:
		_rpc_spawn_bone_attack(attack_rect,wall_side)


func _make_full_wall_bone_rect(map_rect:Rect2,wall_side:int) -> Rect2:
	var margin:float = 2.0
	var max_horizontal_depth:float = maxf(map_rect.size.y * 0.24,12.0)
	var max_vertical_depth:float = maxf(map_rect.size.x * 0.24,12.0)
	var horizontal_depth:float = clampf(boss_gravity_wall_bone_depth,12.0,max_horizontal_depth)
	var vertical_depth:float = clampf(boss_gravity_wall_bone_depth,12.0,max_vertical_depth)
	match clampi(wall_side,WallSide.TOP,WallSide.LEFT):
		WallSide.TOP:
			return Rect2(Vector2(map_rect.position.x + margin,map_rect.position.y),Vector2(maxf(map_rect.size.x - margin * 2.0,1.0),horizontal_depth))
		WallSide.RIGHT:
			return Rect2(Vector2(map_rect.end.x - vertical_depth,map_rect.position.y + margin),Vector2(vertical_depth,maxf(map_rect.size.y - margin * 2.0,1.0)))
		WallSide.BOTTOM:
			return Rect2(Vector2(map_rect.position.x + margin,map_rect.end.y - horizontal_depth),Vector2(maxf(map_rect.size.x - margin * 2.0,1.0),horizontal_depth))
	return Rect2(Vector2(map_rect.position.x,map_rect.position.y + margin),Vector2(vertical_depth,maxf(map_rect.size.y - margin * 2.0,1.0)))


func _resolve_boss_special_skill1_target() -> ball:
	var nearest_unmarked:ball = null
	var nearest_unmarked_distance_sq:float = INF
	var nearest_any:ball = null
	var nearest_any_distance_sq:float = INF
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var candidate:ball = raw as ball
		if not _is_valid_enemy(candidate):
			continue
		var distance_sq:float = global_position.distance_squared_to(candidate.global_position)
		if distance_sq < nearest_any_distance_sq:
			nearest_any_distance_sq = distance_sq
			nearest_any = candidate
		if not _boss_blue_targets.has(candidate.get_instance_id()) and distance_sq < nearest_unmarked_distance_sq:
			nearest_unmarked_distance_sq = distance_sq
			nearest_unmarked = candidate
	return nearest_unmarked if nearest_unmarked != null else nearest_any


func _apply_boss_blue_hop(target:ball) -> void:
	if not _is_valid_enemy(target):
		return
	var target_id:int = target.get_instance_id()
	if not _boss_blue_targets.has(target_id):
		_boss_blue_targets[target_id] = weakref(target)
		# 与普通“砸”共用同一套深蓝 tint/refcount；之后普通砸临时再 +1，结束只 -1，
		# 因而 Boss 蓝魂底色不会被一次普通砸错误清掉。
		_set_gravity_tint_networked(str(target.name),true)

	var hop_seed:int = Game.battle_rng_seed_or(
		"scripts/characters/传说之下/Sans.gd:boss_blue_hop:%d:%d" % [get_instance_id(),target_id],
		maxi(abs(int(Time.get_ticks_usec()) ^ int(get_instance_id()) ^ target_id),1)
	)
	target.configure_external_directional_gravity_hop(
		true,
		minf(boss_blue_jump_min_interval,boss_blue_jump_max_interval),
		maxf(boss_blue_jump_min_interval,boss_blue_jump_max_interval),
		hop_seed,
		clampf(minf(boss_blue_bounce_min_ratio,boss_blue_bounce_max_ratio),0.0,100.0),
		clampf(maxf(boss_blue_bounce_min_ratio,boss_blue_bounce_max_ratio),0.0,100.0)
	)

	var map_rect:Rect2 = _current_map_world_rect()
	var direction:Vector2 = _persistent_gravity_direction_for_target(target)
	# 第一次进入蓝魂、或当前方向对应的墙已经贴得太近时，改选一个安全方向。
	if direction.length_squared() <= 0.000001 or _is_gravity_direction_too_close_to_wall(target,direction,map_rect):
		var safe_side:int = _choose_safe_gravity_side_for_target(target,map_rect)
		direction = _wall_inward_direction(safe_side)
	_set_persistent_target_gravity(target,direction,true)


func _is_target_boss_blue(target:ball) -> bool:
	return target != null and _boss_blue_targets.has(target.get_instance_id())


func _is_valid_enemy(target:ball) -> bool:
	if target == null or target == self or not is_instance_valid(target) or target.health <= 0:
		return false
	if target.has_method("is_combat_targetable") and not bool(target.call("is_combat_targetable")):
		return false
	if not Team.is_empty() and not target.Team.is_empty() and Team == target.Team:
		return false
	return true


func _visual_mode_for_wall_side(side:int) -> int:
	# 来源在下方 / 骨头从下向上 = 抬手；来源在上方 = 放手。
	# 来源在左边向右打 = Right Strike 正放；来源在右边向左打 = Right Strike 倒放。
	match clampi(side,WallSide.TOP,WallSide.LEFT):
		WallSide.TOP:
			return SansVisual.GRAVITY_DOWN
		WallSide.RIGHT:
			return SansVisual.GRAVITY_LEFT
		WallSide.BOTTOM:
			return SansVisual.GRAVITY_UP
	return SansVisual.GRAVITY_RIGHT


func _gesture_duration_for_mode(mode:int) -> float:
	var frames:Array = _visual_animation_frames(mode)
	return maxf(float(maxi(frames.size(),1)) * maxf(gravity_anim_frame_duration,0.02),0.08)


func _play_direction_gesture_for_side(side:int) -> void:
	var mode:int = _visual_mode_for_wall_side(side)
	_gesture_serial += 1
	var serial:int = _gesture_serial
	_set_visual_mode_networked(mode)
	var tree:SceneTree = get_tree()
	if tree == null:
		return
	var timer:=tree.create_timer(_gesture_duration_for_mode(mode))
	timer.timeout.connect(_on_direction_gesture_timeout.bind(serial))


func _on_direction_gesture_timeout(serial:int) -> void:
	if serial != _gesture_serial or _death_sequence_started or _death_visual_started_local:
		return
	if _visual_mode == SansVisual.DODGE:
		return
	_set_visual_mode_networked(SansVisual.IDLE)


# ========================================================
# V181：目标方向重力 / 整体朝向 / 砸击穿透
# ========================================================
func _persistent_gravity_key_for_target(target:ball) -> String:
	return "sans_persistent_gravity_%d" % target.get_instance_id()


func _gravity_collision_exception_meta_key() -> StringName:
	# 每个 Sans 独立记录自己是否给目标添加了碰撞例外，不再枚举 PhysicsBody2D
	# 的 collision exception 节点数组；这样目标/其它例外体已经释放时也不会触发空 body 转换。
	return StringName("_sans_gravity_ignore_%d" % get_instance_id())


func _gravity_restore_tween_meta_key() -> StringName:
	return StringName("_sans_gravity_restore_tween_%d" % get_instance_id())


func _cancel_target_gravity_restore_tween(target:ball) -> void:
	if target == null or not is_instance_valid(target):
		return
	var meta_key:StringName = _gravity_restore_tween_meta_key()
	# Object.get_meta(name, null) 在 key 不存在时仍会打印错误；必须先检查。
	if not target.has_meta(meta_key):
		return
	var raw:Variant = target.get_meta(meta_key)
	if raw is Tween:
		var tween:Tween = raw as Tween
		if tween != null and tween.is_valid():
			tween.kill()
	if target.has_meta(meta_key):
		target.remove_meta(meta_key)


func _persistent_gravity_state_for_target(target:ball) -> Dictionary:
	if target == null or not is_instance_valid(target):
		return {}
	var target_id:int = target.get_instance_id()
	var existing:Variant = _persistent_gravity_targets.get(target_id,{})
	if existing is Dictionary and not (existing as Dictionary).is_empty():
		var existing_ref:WeakRef = (existing as Dictionary).get("target_ref",null)
		if existing_ref != null and existing_ref.get_ref() == target:
			return existing as Dictionary

	# V191：只把“受重力目标 -> 施法 Sans”设成碰撞例外。
	# 不再调用 get_collision_exceptions()：该 API 会把 RID 列表转回 Node，列表里只要
	# 有一个已释放物理体就会产生截图中的 `Parameter "body" is null`。
	# 改用目标 metadata 记录“本 Sans 是否已经加过例外”，无需枚举任何 Node。
	var collision_meta_key:StringName = _gravity_collision_exception_meta_key()
	var target_exception_owned:bool = not bool(target.get_meta(collision_meta_key,false))
	if target_exception_owned:
		target.add_collision_exception_with(self)
		target.set_meta(collision_meta_key,true)

	var state:Dictionary = {
		"target_ref": weakref(target),
		"key": _persistent_gravity_key_for_target(target),
		"direction": Vector2.ZERO,
		"rotation": target.global_rotation,
		"original_rotation": target.global_rotation,
		"original_up_direction": target.up_direction,
		"original_terminal": target.external_directional_gravity_terminal_speed,
		"original_gravity_locomotion_enabled": target.is_external_directional_gravity_locomotion_enabled(),
		"original_gravity_axis_ratio_max": target.get_external_directional_gravity_axis_speed_ratio_max(),
		"target_sans_collision_exception_owned": target_exception_owned,
		"idle_restore_left": maxf(gravity_idle_restore_delay,0.5),
	}
	_persistent_gravity_targets[target_id] = state
	return state


func _ensure_gravity_target_ignores_sans(target:ball) -> void:
	if target == null or not is_instance_valid(target):
		return
	# 只查自己的 metadata，不再遍历 collision exception Node 数组。
	var collision_meta_key:StringName = _gravity_collision_exception_meta_key()
	if not bool(target.get_meta(collision_meta_key,false)):
		target.add_collision_exception_with(self)
		target.set_meta(collision_meta_key,true)


func _restore_gravity_target_sans_collision(target:ball,state:Dictionary) -> void:
	if target == null or not is_instance_valid(target):
		return
	var collision_meta_key:StringName = _gravity_collision_exception_meta_key()
	if bool(target.get_meta(collision_meta_key,false)):
		target.remove_collision_exception_with(self)
		target.remove_meta(collision_meta_key)


func _persistent_gravity_direction_for_target(target:ball) -> Vector2:
	if target == null or not is_instance_valid(target):
		return Vector2.ZERO
	var raw_state:Variant = _persistent_gravity_targets.get(target.get_instance_id(),{})
	if not raw_state is Dictionary:
		return Vector2.ZERO
	var direction:Variant = (raw_state as Dictionary).get("direction",Vector2.ZERO)
	return direction if direction is Vector2 else Vector2.ZERO


func _persistent_gravity_strength_for_target(target:ball) -> float:
	if _is_target_boss_blue(target):
		return maxf(boss_blue_gravity_acceleration,1.0)
	return maxf(gravity_persistent_acceleration,1.0)


func _set_persistent_target_gravity(target:ball,gravity_dir:Vector2,reset_velocity:bool = false) -> void:
	if target == null or not is_instance_valid(target) or gravity_dir.length_squared() <= 0.000001:
		return
	var world:Node = get_tree().current_scene if get_tree() != null else null
	if world == null or not world.has_method("register_directional_gravity"):
		return

	var direction:Vector2 = gravity_dir.normalized()
	var state:Dictionary = _persistent_gravity_state_for_target(target)
	if state.is_empty():
		return
	_cancel_target_gravity_restore_tween(target)
	if target.has_method("cancel_external_directional_gravity_release"):
		target.call("cancel_external_directional_gravity_release")
	state["idle_restore_left"] = maxf(gravity_idle_restore_delay,0.5)
	var original_rotation:float = float(state.get("original_rotation",target.global_rotation))
	# 默认人物是“脚朝 Vector2.DOWN”；把这个 down 轴旋到重力方向，就能让人物+血条一起转。
	var target_rotation:float = original_rotation + direction.angle() - Vector2.DOWN.angle()
	state["direction"] = direction
	state["rotation"] = target_rotation
	_persistent_gravity_targets[target.get_instance_id()] = state

	if reset_velocity:
		target.clear_external_directional_gravity_velocity()
	# Floating 模式下 up_direction 不参与地板分类，但仍同步为语义正确的“反重力方向”，
	# 兼容少数子类自己读取 up_direction 的逻辑。
	target.up_direction = -direction
	# V185：砸完后的持久重力使用标准重力积分；角色自己的移动只沿当前“地面”的左右轴。
	# 强砸飞行阶段仍临时关闭 locomotion，保留原来的高加速度砸墙过程。
	target.configure_external_directional_gravity_locomotion(true,gravity_motion_axis_ratio_max)
	world.call(
		"register_directional_gravity",
		self,
		str(state.get("key",_persistent_gravity_key_for_target(target))),
		direction,
		_persistent_gravity_strength_for_target(target),
		false,
		target
	)
	_set_target_gravity_rotation_networked(str(target.name),target_rotation)


func _set_target_gravity_rotation_networked(target_name:String,target_rotation:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_set_target_gravity_rotation.rpc(target_name,target_rotation)
	else:
		_rpc_set_target_gravity_rotation(target_name,target_rotation)


@rpc("authority","call_local","reliable")
func _rpc_set_target_gravity_rotation(target_name:String,target_rotation:float) -> void:
	var target:ball = _find_ball_by_name(target_name)
	if target == null:
		return
	_cancel_target_gravity_restore_tween(target)
	target.global_rotation = target_rotation


func _restore_target_gravity_rotation_networked(target_name:String,target_rotation:float,duration:float) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_restore_target_gravity_rotation.rpc(target_name,target_rotation,duration)
	else:
		_rpc_restore_target_gravity_rotation(target_name,target_rotation,duration)


@rpc("authority","call_local","reliable")
func _rpc_restore_target_gravity_rotation(target_name:String,target_rotation:float,duration:float) -> void:
	var target:ball = _find_ball_by_name(target_name)
	if target == null:
		return
	_cancel_target_gravity_restore_tween(target)
	var safe_duration:float = maxf(duration,0.0)
	if safe_duration <= 0.001:
		target.global_rotation = target_rotation
		return
	var start_rotation:float = target.global_rotation
	var meta_key:StringName = _gravity_restore_tween_meta_key()
	var tween:Tween = target.create_tween()
	target.set_meta(meta_key,tween)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var apply_rotation:Callable = func(weight:float) -> void:
		if target != null and is_instance_valid(target):
			target.global_rotation = lerp_angle(start_rotation,target_rotation,weight)
	tween.tween_method(apply_rotation,0.0,1.0,safe_duration)
	var clear_tween_meta:Callable = func() -> void:
		if target != null and is_instance_valid(target) and target.has_meta(meta_key):
			target.remove_meta(meta_key)
	tween.finished.connect(clear_tween_meta)


func _expire_persistent_gravity_target(target:ball,state:Dictionary) -> void:
	if target == null or not is_instance_valid(target):
		return
	var world:Node = get_tree().current_scene if get_tree() != null else null
	if world != null and is_instance_valid(world) and world.has_method("clear_directional_gravity"):
		world.call("clear_directional_gravity",self,str(state.get("key",_persistent_gravity_key_for_target(target))))
	var target_id:int = target.get_instance_id()
	if _boss_blue_targets.has(target_id):
		target.configure_external_directional_gravity_hop(false)
		_set_gravity_tint_networked(str(target.name),false)
		_boss_blue_targets.erase(target_id)
	target.external_directional_gravity_terminal_speed = float(
		state.get("original_terminal",target.external_directional_gravity_terminal_speed)
	)
	target.configure_external_directional_gravity_locomotion(
		bool(state.get("original_gravity_locomotion_enabled",false)),
		float(state.get("original_gravity_axis_ratio_max",0.80))
	)
	var original_up:Variant = state.get("original_up_direction",Vector2.UP)
	if original_up is Vector2 and (original_up as Vector2).length_squared() > 0.000001:
		target.up_direction = original_up as Vector2
	if target.has_method("begin_external_directional_gravity_release"):
		target.call("begin_external_directional_gravity_release",maxf(gravity_restore_velocity_deceleration,200.0))
	_restore_target_gravity_rotation_networked(
		str(target.name),
		float(state.get("original_rotation",target.global_rotation)),
		maxf(gravity_restore_rotation_duration,0.0)
	)
	_restore_gravity_target_sans_collision(target,state)


func _maintain_persistent_gravity_targets(delta:float) -> void:
	if _persistent_gravity_targets.is_empty():
		return
	var stale:Array[int] = []
	var expired:Array[int] = []
	var safe_delta:float = maxf(delta,0.0)
	for raw_id:Variant in _persistent_gravity_targets.keys():
		var target_id:int = int(raw_id)
		var state:Dictionary = _persistent_gravity_targets.get(target_id,{})
		var target_ref:WeakRef = state.get("target_ref",null)
		var target:ball = (target_ref.get_ref() as ball) if target_ref != null else null
		if target == null or not is_instance_valid(target) or not target.is_inside_tree() or target.health <= 0:
			if target != null and is_instance_valid(target):
				_restore_gravity_target_sans_collision(target,state)
			stale.append(target_id)
			continue

		# 正在强砸飞行时不允许超时恢复；强砸结束会再次刷新 idle_restore_left。
		if target == _active_gravity_target:
			state["idle_restore_left"] = maxf(gravity_idle_restore_delay,0.5)
			_persistent_gravity_targets[target_id] = state
		else:
			var restore_left:float = float(state.get("idle_restore_left",maxf(gravity_idle_restore_delay,0.5))) - safe_delta
			state["idle_restore_left"] = restore_left
			_persistent_gravity_targets[target_id] = state
			if restore_left <= 0.0:
				_expire_persistent_gravity_target(target,state)
				expired.append(target_id)
				continue

		var direction:Vector2 = state.get("direction",Vector2.ZERO)
		if direction.length_squared() > 0.000001:
			target.up_direction = -direction.normalized()
			target.global_rotation = float(state.get("rotation",target.global_rotation))
			_ensure_gravity_target_ignores_sans(target)
			target.configure_external_directional_gravity_locomotion(true,gravity_motion_axis_ratio_max)
	for target_id:int in stale:
		_persistent_gravity_targets.erase(target_id)
		_boss_blue_targets.erase(target_id)
	for target_id:int in expired:
		_persistent_gravity_targets.erase(target_id)


func _cleanup_invalid_gravity_target_refs() -> void:
	var stale_blue:Array[int] = []
	for raw_id:Variant in _boss_blue_targets.keys():
		var target_id:int = int(raw_id)
		var ref:WeakRef = _boss_blue_targets.get(target_id,null)
		var target:ball = (ref.get_ref() as ball) if ref != null else null
		if target == null or not is_instance_valid(target) or not target.is_inside_tree() or target.health <= 0:
			stale_blue.append(target_id)
	for target_id:int in stale_blue:
		_boss_blue_targets.erase(target_id)


# 砸飞阶段只改变 CharacterBody2D 的实体阻挡：临时拿掉项目“角色身体层 2”。
# Hitbox/Hurtbox 不动，所以这不是额外无敌；只是目标移动时能真正穿过其它角色。
# 其它碰撞层原样保留，因此墙、地形、特殊地图障碍仍按项目原配置阻挡；落墙后精确恢复旧值。
func _begin_slam_target_phasing(target:ball) -> void:
	if target == null or not is_instance_valid(target):
		return
	var count:int = int(target.get_meta(&"sans_slam_phase_refcount",0))
	if count <= 0:
		var saved:Dictionary = {
			"body_layer": target.collision_layer,
			"body_mask": target.collision_mask,
		}
		target.set_meta(&"sans_slam_phase_saved",saved)
	target.set_meta(&"sans_slam_phase_refcount",count + 1)
	# 关闭 layer/mask 2：自己不会被其它角色实体阻挡，其它角色也不会把飞行中的它当实体墙。
	target.set_collision_layer_value(2,false)
	target.set_collision_mask_value(2,false)


func _end_slam_target_phasing(target:ball) -> void:
	if target == null or not is_instance_valid(target):
		return
	var count:int = int(target.get_meta(&"sans_slam_phase_refcount",0))
	if count > 1:
		target.set_meta(&"sans_slam_phase_refcount",count - 1)
		return
	var raw_saved:Variant = target.get_meta(&"sans_slam_phase_saved",{})
	if raw_saved is Dictionary:
		var saved:Dictionary = raw_saved as Dictionary
		target.collision_layer = int(saved.get("body_layer",target.collision_layer))
		target.collision_mask = int(saved.get("body_mask",target.collision_mask))
	target.remove_meta(&"sans_slam_phase_refcount")
	target.remove_meta(&"sans_slam_phase_saved")


# V192：选择重力方向时避开目标已经特别靠近的墙。
# 例如目标贴底且靠左：向下、向左都会被排除，只会在向右/向上中随机。
func _gravity_side_destination_distance(target:ball,side:int,map_rect:Rect2) -> float:
	return _distance_to_map_wall(target,_wall_inward_direction(side),map_rect)


func _gravity_safe_distance_for_target(target:ball) -> float:
	var radius:float = 8.0
	if target != null and is_instance_valid(target):
		radius = maxf(target.get_crowd_separation_radius_world(),4.0)
	return maxf(gravity_direction_avoid_wall_distance,radius * 1.35)


func _is_gravity_direction_too_close_to_wall(target:ball,direction:Vector2,map_rect:Rect2) -> bool:
	if target == null or not is_instance_valid(target) or direction.length_squared() <= 0.000001:
		return false
	return _distance_to_map_wall(target,direction.normalized(),map_rect) <= _gravity_safe_distance_for_target(target)


func _choose_safe_gravity_side_for_target(target:ball,map_rect:Rect2) -> int:
	var safe_sides:Array[int] = []
	var threshold:float = _gravity_safe_distance_for_target(target)
	var farthest_side:int = WallSide.TOP
	var farthest_distance:float = -INF
	for side:int in [WallSide.TOP,WallSide.RIGHT,WallSide.BOTTOM,WallSide.LEFT]:
		var distance:float = _gravity_side_destination_distance(target,side,map_rect)
		if distance > farthest_distance:
			farthest_distance = distance
			farthest_side = side
		if distance > threshold:
			safe_sides.append(side)
	if safe_sides.is_empty():
		# 极小地图/超大角色导致四边都在阈值内时，至少选距离最远的墙，避免把目标继续压进最近墙。
		return farthest_side
	return safe_sides[_attack_rng.randi_range(0,safe_sides.size() - 1)]


func _wall_side_for_gravity_direction(direction:Vector2) -> int:
	var d:Vector2 = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.DOWN
	if absf(d.x) >= absf(d.y):
		return WallSide.RIGHT if d.x > 0.0 else WallSide.LEFT
	return WallSide.BOTTOM if d.y > 0.0 else WallSide.TOP


# ========================================================
# 1) 四向重力砸墙
# ========================================================
func _start_gravity_attack_background(target:ball) -> void:
	if not _is_valid_enemy(target):
		return
	var map_rect:Rect2 = _current_map_world_rect()
	if map_rect.size.x <= 1.0 or map_rect.size.y <= 1.0:
		return

	var side:int = _choose_safe_gravity_side_for_target(target,map_rect)
	var gravity_dir:Vector2 = _wall_inward_direction(side)
	_play_direction_gesture_for_side(side)
	# GDScript 协程在不读取返回值时可以直接异步启动；Attack() 本身立即结束并开始下一轮冷却。
	_run_gravity_slam_task(target,gravity_dir,map_rect)


func _run_gravity_slam_task(target:ball,gravity_dir:Vector2,map_rect:Rect2) -> void:
	if not _is_valid_enemy(target):
		return
	await _perform_gravity_slam(target,gravity_dir,map_rect)


func _perform_gravity_slam(target:ball,gravity_dir:Vector2,map_rect:Rect2) -> float:
	if not _is_valid_enemy(target):
		return 0.0
	var world:Node = get_tree().current_scene
	if world == null or not world.has_method("register_directional_gravity"):
		return 0.0

	var direction:Vector2 = gravity_dir.normalized()
	var target_name:String = str(target.name)
	# 先把“后续永久重力方向 + 整体朝向”切到本次砸击方向；同一 key 随后会被强砸加速度覆盖，
	# 撞墙结束时再降回持久重力强度。这样不会同时叠两条相同方向的重力源。
	_set_persistent_target_gravity(target,direction,true)
	var state:Dictionary = _persistent_gravity_state_for_target(target)
	if state.is_empty():
		return 0.0
	var gravity_key:String = str(state.get("key",_persistent_gravity_key_for_target(target)))

	_active_gravity_key = gravity_key
	_active_gravity_target = target
	_active_gravity_direction = direction
	_active_gravity_old_terminal = target.external_directional_gravity_terminal_speed
	target.external_directional_gravity_terminal_speed = maxf(gravity_terminal_speed,_active_gravity_old_terminal)
	# 强砸阶段保留原来的高加速度/高终速；撞墙后才切回 V185 的标准持久重力运动。
	target.configure_external_directional_gravity_locomotion(false,gravity_motion_axis_ratio_max)
	target.clear_external_directional_gravity_velocity()
	_begin_slam_target_phasing(target)
	world.call("register_directional_gravity",self,gravity_key,direction,maxf(gravity_acceleration,1.0),false,target)
	_set_gravity_tint_networked(target_name,true)

	var elapsed:float = 0.0
	var last_projection:float = target.global_position.dot(direction)
	var stalled_frames:int = 0
	var impact_speed:float = 0.0
	var hit_environment:bool = false
	while elapsed < maxf(gravity_max_duration,0.1):
		await get_tree().physics_frame
		# Sans 若在砸击协程等待期间死亡，Die() 会撤销全部持久重力。这里必须立即退出，
		# 不能让已排队的协程下一帧又把重力/蓝 tint 重新注册回来。
		if not is_inside_tree() or health <= 0 or _death_sequence_started or _last_trial_active:
			if not _active_gravity_key.is_empty():
				_cleanup_active_gravity()
				_set_gravity_tint_networked(target_name,false)
			return elapsed
		if not _is_valid_enemy(target):
			break
		var delta:float = maxf(get_physics_process_delta_time(),1.0 / 240.0)
		elapsed += delta
		var gravity_velocity:Vector2 = target.get_external_directional_gravity_velocity()
		impact_speed = maxf(gravity_velocity.dot(direction),0.0)

		var projection:float = target.global_position.dot(direction)
		var moved_along:float = projection - last_projection
		last_projection = projection
		if impact_speed > 140.0 and moved_along < 0.18:
			stalled_frames += 1
		else:
			stalled_frames = 0

		var distance_to_wall:float = _distance_to_map_wall(target,direction,map_rect)
		if elapsed >= 0.08 and (distance_to_wall <= 2.5 or stalled_frames >= 2):
			hit_environment = true
			break

	if hit_environment:
		_trigger_gravity_slam_screen_shake_networked(direction)

	if target != null and is_instance_valid(target):
		_finish_active_gravity_as_persistent()
	else:
		_cleanup_active_gravity()
	_set_gravity_tint_networked(target_name,false)
	if not _is_valid_enemy(target):
		return elapsed

	# V185：Boss 深蓝不再“撞墙立即弹”。砸击结束后照常落地，随后由目标自己的
	# 落地随机计时器决定下一次跳跃，起跳速度严格等于目标 Speed。

	var slam_damage:int = clampi(int(round(impact_speed / maxf(gravity_damage_speed_step,1.0))),1,maxi(gravity_damage_max,1))
	var wall_point:Vector2 = target.global_position + direction * maxf(target.get_crowd_separation_radius_world(),6.0)
	_play_slam_sfx_networked(wall_point)
	var damaged:bool = target.receive_positional_damage(float(slam_damage),wall_point,true,self)
	if damaged:
		play_sans_damage_feedback(target,false)
	return elapsed


func _trigger_gravity_slam_screen_shake_networked(direction:Vector2) -> void:
	if gravity_slam_screen_shake <= 0.0:
		return
	var d:Vector2 = direction.normalized() if direction.length_squared() > 0.000001 else Vector2.DOWN
	if multiplayer.has_multiplayer_peer():
		_rpc_gravity_slam_screen_shake.rpc(d,gravity_slam_screen_shake,gravity_slam_screen_shake_direction_bias)
	else:
		_rpc_gravity_slam_screen_shake(d,gravity_slam_screen_shake,gravity_slam_screen_shake_direction_bias)


@rpc("authority","call_local","unreliable")
func _rpc_gravity_slam_screen_shake(direction:Vector2,amount:float,directional_bias:float) -> void:
	var world:Node = get_tree().current_scene
	if world != null and world.has_method("request_directional_camera_shake"):
		world.call("request_directional_camera_shake",direction,maxf(amount,0.0),clampf(directional_bias,0.0,1.0))


func _distance_to_map_wall(target:ball,gravity_dir:Vector2,map_rect:Rect2) -> float:
	var radius:float = maxf(target.get_crowd_separation_radius_world(),4.0)
	var p:Vector2 = target.global_position
	if gravity_dir.x > 0.5:
		return maxf(map_rect.end.x - radius - p.x,0.0)
	if gravity_dir.x < -0.5:
		return maxf(p.x - (map_rect.position.x + radius),0.0)
	if gravity_dir.y > 0.5:
		return maxf(map_rect.end.y - radius - p.y,0.0)
	return maxf(p.y - (map_rect.position.y + radius),0.0)


func _finish_active_gravity_as_persistent() -> void:
	var target:ball = _active_gravity_target
	var direction:Vector2 = _active_gravity_direction
	if target != null and is_instance_valid(target):
		target.external_directional_gravity_terminal_speed = _active_gravity_old_terminal
		target.clear_external_directional_gravity_velocity()
		_end_slam_target_phasing(target)
		_set_persistent_target_gravity(target,direction,true)
	_active_gravity_key = ""
	_active_gravity_target = null
	_active_gravity_direction = Vector2.DOWN


func _cleanup_active_gravity() -> void:
	if _active_gravity_target != null and is_instance_valid(_active_gravity_target):
		_active_gravity_target.external_directional_gravity_terminal_speed = _active_gravity_old_terminal
		_active_gravity_target.clear_external_directional_gravity_velocity()
		_end_slam_target_phasing(_active_gravity_target)
	var world:Node = null
	if get_tree() != null:
		world = get_tree().current_scene
	if world != null and is_instance_valid(world) and not _active_gravity_key.is_empty() and world.has_method("clear_directional_gravity"):
		world.call("clear_directional_gravity",self,_active_gravity_key)
	_active_gravity_key = ""
	_active_gravity_target = null
	_active_gravity_direction = Vector2.DOWN


func _set_gravity_tint_networked(target_name:String,enabled:bool) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_set_gravity_tint.rpc(target_name,enabled)
	else:
		_rpc_set_gravity_tint(target_name,enabled)


@rpc("authority","call_local","reliable")
func _rpc_set_gravity_tint(target_name:String,enabled:bool) -> void:
	var target:ball = _find_ball_by_name(target_name)
	if target == null or target.graphics == null:
		return
	var count_meta:StringName = &"sans_gravity_tint_refcount"
	var color_meta:StringName = &"sans_gravity_tint_original"
	var count:int = int(target.graphics.get_meta(count_meta,0))
	if enabled:
		if count <= 0:
			target.graphics.set_meta(color_meta,target.graphics.modulate)
		target.graphics.set_meta(count_meta,count + 1)
		# V186：深蓝必须是“叠加”，不是把 graphics.modulate 整体替换成纯蓝。
		# 以进入蓝魂前的 modulate 为底色，只混入一部分更浅的蓝色，因此原贴图、阵营色和明暗仍然可见。
		var original_modulate:Variant = target.graphics.get_meta(color_meta,Color.WHITE)
		var base_color:Color = original_modulate if original_modulate is Color else Color.WHITE
		var tint:Color = gravity_target_color
		tint.a = base_color.a
		target.graphics.modulate = base_color.lerp(tint,clampf(gravity_target_overlay_strength,0.0,0.95))
		return

	count = maxi(count - 1,0)
	if count > 0:
		target.graphics.set_meta(count_meta,count)
		return
	var original:Variant = target.graphics.get_meta(color_meta,Color.WHITE)
	if original is Color:
		target.graphics.modulate = original
	target.graphics.remove_meta(count_meta)
	target.graphics.remove_meta(color_meta)


# ========================================================
# 2) 骨头墙：固定面积，随机长宽，红框预警
# ========================================================
func _summon_bone_attack(target:ball) -> void:
	if not _is_valid_enemy(target):
		return
	var map_rect:Rect2 = _current_map_world_rect()
	if map_rect.size.x <= 1.0 or map_rect.size.y <= 1.0:
		return
	var side:int = _attack_rng.randi_range(WallSide.TOP,WallSide.LEFT)
	var attack_rect:Rect2 = _make_bone_attack_rect(target,map_rect,side)
	_play_direction_gesture_for_side(side)
	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_bone_attack.rpc(attack_rect,side)
	else:
		_rpc_spawn_bone_attack(attack_rect,side)


func _make_bone_attack_rect(target:ball,map_rect:Rect2,side:int) -> Rect2:
	# V181：骨头仍保持“总面积固定 + 长宽随机”，但作为锁定类攻击，最终完全伸出时
	# 至少要够到目标当前碰撞范围。旧逻辑把默认深度长期限制在约 20~101px，
	# 对停在地图中部、移动较慢的高血量角色（尤其军官）经常整排骨头都只停在墙边。
	# 现在 bone_min/max_depth 仍决定常规随机偏好；只有目标更深时才自动把深度下限推到目标附近。
	var margin:float = 4.0
	var horizontal_wall:bool = side == WallSide.TOP or side == WallSide.BOTTOM
	var max_depth:float = maxf((map_rect.size.y if horizontal_wall else map_rect.size.x) - margin * 2.0,12.0)
	var max_span:float = maxf((map_rect.size.x if horizontal_wall else map_rect.size.y) - margin * 2.0,12.0)

	var requested_area:float = maxf(bone_attack_area,12.0 * 12.0)
	var usable_area:float = minf(requested_area,max_depth * max_span)
	var depth_floor:float = maxf(usable_area / max_span,12.0)
	# 最窄允许收到一根完整 12px 骨头宽，因此固定面积攻击也能从很远的墙真正够到目标。
	var depth_ceiling:float = minf(max_depth,usable_area / 12.0)

	var target_pos:Vector2 = combat_target_position(target)
	var target_radius:float = 18.0
	if target != null and target.has_method("get_crowd_separation_radius_world"):
		target_radius = maxf(float(target.call("get_crowd_separation_radius_world")),6.0)

	var wall_distance:float = 0.0
	match side:
		WallSide.TOP:
			wall_distance = target_pos.y - map_rect.position.y
		WallSide.RIGHT:
			wall_distance = map_rect.end.x - target_pos.x
		WallSide.BOTTOM:
			wall_distance = map_rect.end.y - target_pos.y
		_:
			wall_distance = target_pos.x - map_rect.position.x

	# 只需要进入目标碰撞范围，不要求穿过目标中心；留 6px 保险避免离散物理帧刚好擦边。
	var target_reach_floor:float = clampf(
		wall_distance - target_radius * 0.72 + 6.0,
		depth_floor,
		depth_ceiling
	)
	var preferred_min:float = clampf(minf(bone_min_depth,bone_max_depth),depth_floor,depth_ceiling)
	var preferred_max:float = clampf(maxf(bone_min_depth,bone_max_depth),preferred_min,depth_ceiling)
	var random_min:float = maxf(preferred_min,target_reach_floor)
	# 目标很深时仍保留一部分长度随机，不让所有针对远目标的骨墙都变成同一个形状。
	var random_max:float = minf(depth_ceiling,maxf(preferred_max,random_min * 1.18))

	# 对数随机继续偏向覆盖“较浅较宽 / 较深较窄”两端。
	var depth:float = random_min
	if random_max > random_min + 0.01:
		depth = exp(_attack_rng.randf_range(log(random_min),log(random_max)))
	var span:float = usable_area / maxf(depth,0.001)
	span = clampf(span,12.0,max_span)
	depth = minf(usable_area / maxf(span,0.001),max_depth)

	if horizontal_wall:
		var x:float = clampf(target_pos.x - span * 0.5,map_rect.position.x + margin,map_rect.end.x - margin - span)
		var y:float = map_rect.position.y if side == WallSide.TOP else map_rect.end.y - depth
		return Rect2(Vector2(x,y),Vector2(span,depth))

	var y:float = clampf(target_pos.y - span * 0.5,map_rect.position.y + margin,map_rect.end.y - margin - span)
	var x:float = map_rect.position.x if side == WallSide.LEFT else map_rect.end.x - depth
	return Rect2(Vector2(x,y),Vector2(depth,span))


@rpc("authority","call_local","reliable")
func _rpc_spawn_bone_attack(attack_rect:Rect2,side:int) -> void:
	var parent:Node = get_tree().current_scene
	if parent == null:
		return
	var effect:Node2D = BONE_ATTACK_SCRIPT.new() as Node2D
	if effect == null:
		return
	effect.name = "Sans骨头攻击"
	effect.add_to_group("BattleTransient")
	parent.add_child(effect)
	effect.call(
		"configure",self,attack_rect,side,
		bone_warning_duration,bone_rise_duration,bone_active_duration,
		5.0,1.0
	)


# ========================================================
# 3) 龙骨炮：飞入、前4帧蓄力、第4帧开火、5/6循环、后坐力退出
# ========================================================
func _summon_gaster_attack(target:ball) -> void:
	if not _is_valid_enemy(target):
		return
	var map_rect:Rect2 = _current_map_world_rect()
	if map_rect.size.x <= 1.0 or map_rect.size.y <= 1.0:
		return
	var side:int = _attack_rng.randi_range(WallSide.TOP,WallSide.LEFT)
	_play_direction_gesture_for_side(side)
	var aim_point:Vector2 = combat_target_position(target)
	var park:Vector2 = _gaster_park_position(aim_point,map_rect,side)
	var outward:Vector2 = _wall_outward_direction(side)
	var min_scale:float = minf(gaster_size_min,gaster_size_max)
	var max_scale:float = maxf(gaster_size_min,gaster_size_max)
	var size_scale:float = _attack_rng.randf_range(min_scale,max_scale)
	var spawn_distance:float = _gaster_required_offscreen_distance(park,outward,size_scale)
	var spawn:Vector2 = park + outward * spawn_distance

	# V156：演出时长以用户给的原音频长度为“钟”。
	# 出现阶段只小幅随机；攻击阶段除了小幅随机，还让更宽的炮持续更久。
	var random_ratio:float = clampf(gaster_duration_randomness,0.0,0.12)
	var appear_random:float = _attack_rng.randf_range(1.0 - random_ratio,1.0 + random_ratio)
	var fire_random:float = _attack_rng.randf_range(1.0 - random_ratio,1.0 + random_ratio)
	var appear_audio_length:float = maxf(SFX_GASTER_APPEAR.get_length(),0.20)
	var fire_audio_length:float = maxf(SFX_GASTER_FIRE.get_length(),0.30)
	var appearance_duration:float = appear_audio_length * maxf(gaster_appear_duration_scale,0.10) * appear_random

	var size_t:float = 0.5
	if max_scale - min_scale > 0.001:
		size_t = clampf((size_scale - min_scale) / (max_scale - min_scale),0.0,1.0)
	var width_influence:float = clampf(gaster_width_duration_influence,0.0,0.40)
	var width_duration_multiplier:float = lerpf(1.0 - width_influence,1.0 + width_influence,size_t)
	var attack_duration:float = fire_audio_length * maxf(gaster_attack_duration_scale,0.10) * fire_random * width_duration_multiplier

	if multiplayer.has_multiplayer_peer():
		_rpc_spawn_gaster.rpc(spawn,park,aim_point,str(target.name),map_rect,size_scale,appearance_duration,attack_duration,gaster_beam_width_ratio,1.0)
	else:
		_rpc_spawn_gaster(spawn,park,aim_point,str(target.name),map_rect,size_scale,appearance_duration,attack_duration,gaster_beam_width_ratio,1.0)


func _gaster_park_position(target_pos:Vector2,map_rect:Rect2,side:int) -> Vector2:
	var outside:float = maxf(gaster_map_outside_offset,20.0)
	var edge_margin:float = 34.0
	match side:
		WallSide.TOP:
			return Vector2(clampf(target_pos.x,map_rect.position.x + edge_margin,map_rect.end.x - edge_margin),map_rect.position.y - outside)
		WallSide.RIGHT:
			return Vector2(map_rect.end.x + outside,clampf(target_pos.y,map_rect.position.y + edge_margin,map_rect.end.y - edge_margin))
		WallSide.BOTTOM:
			return Vector2(clampf(target_pos.x,map_rect.position.x + edge_margin,map_rect.end.x - edge_margin),map_rect.end.y + outside)
	return Vector2(map_rect.position.x - outside,clampf(target_pos.y,map_rect.position.y + edge_margin,map_rect.end.y - edge_margin))


func _wall_outward_direction(side:int) -> Vector2:
	match side:
		WallSide.TOP:
			return Vector2.UP
		WallSide.RIGHT:
			return Vector2.RIGHT
		WallSide.BOTTOM:
			return Vector2.DOWN
	return Vector2.LEFT


func _wall_inward_direction(side:int) -> Vector2:
	return -_wall_outward_direction(side)


func _gaster_required_offscreen_distance(park:Vector2,outward:Vector2,size_scale:float = 1.0) -> float:
	var required:float = maxf(gaster_spawn_extra_distance,20.0)
	var viewport:Viewport = get_viewport()
	if viewport == null:
		return required
	var camera:Camera2D = viewport.get_camera_2d()
	if camera == null:
		return required
	var zoom:Vector2 = camera.zoom.abs()
	var viewport_size:Vector2 = viewport.get_visible_rect().size
	var half_size:=Vector2(
		viewport_size.x / maxf(zoom.x,0.001),
		viewport_size.y / maxf(zoom.y,0.001)
	) * 0.5
	var screen_rect:=Rect2(camera.global_position - half_size,half_size * 2.0)
	var offscreen_margin:float = maxf(64.0,48.0 * maxf(size_scale,0.4))
	if outward.x > 0.5:
		required = maxf(required,screen_rect.end.x + offscreen_margin - park.x)
	elif outward.x < -0.5:
		required = maxf(required,park.x - (screen_rect.position.x - offscreen_margin))
	elif outward.y > 0.5:
		required = maxf(required,screen_rect.end.y + offscreen_margin - park.y)
	else:
		required = maxf(required,park.y - (screen_rect.position.y - offscreen_margin))
	return required


@rpc("authority","call_local","reliable")
func _rpc_spawn_gaster(
	spawn:Vector2,
	park:Vector2,
	aim_point:Vector2,
	target_name:String,
	map_rect:Rect2,
	size_scale:float,
	appearance_duration:float,
	attack_duration:float,
	beam_width_ratio_override:float,
	body_width_scale_override:float = 1.0,
	stop_beam_at_target:bool = false,
	prefire_delay_override:float = 0.0
) -> void:
	var parent:Node = get_tree().current_scene
	if parent == null:
		return
	var effect:Node2D = GASTER_ATTACK_SCRIPT.new() as Node2D
	if effect == null:
		return
	effect.name = "Sans龙骨炮"
	effect.add_to_group("BattleTransient")
	parent.add_child(effect)
	# target_name 属于 RPC/目标标识，不是龙骨炮 configure 参数。
	# V51：configure 末尾新增可选 body_width_scale；普通炮固定 1.0，大风车只压窄本体宽度。
	var resolved_beam_width_ratio:float = gaster_beam_width_ratio
	if beam_width_ratio_override > 0.0:
		resolved_beam_width_ratio = beam_width_ratio_override
	effect.call(
		"configure",self,spawn,park,aim_point,map_rect,
		appearance_duration,attack_duration,size_scale,resolved_beam_width_ratio,
		10.0,1.0,body_width_scale_override,stop_beam_at_target,prefire_delay_override
	)


# ========================================================
# 骨头/龙骨炮公共“1点帧伤 + KARMA”入口
# ========================================================
func apply_sans_frame_hit(target:ball,impact_position:Vector2,karma_amount:float) -> void:
	if not is_multiplayer_authority() or health <= 0 or is_damage_output_disabled():
		return
	if not _is_valid_enemy(target):
		return

	var before_health:float = float(target.health)
	if target.health_bar != null:
		target.health_bar.force_instant_update_once = true
		target.health_bar.suppress_floating_text = true

	# Sans 的攻击是“帧伤”：每个实际重叠的 physics frame 固定扣 1 HP，
	# 不为每帧创建通用 HitBurst/攻击 Tween/受击音；血条数字反馈单独节流。
	target.health = maxi(int(target.health) - 1,0)

	if target.health_bar != null:
		target.health_bar.suppress_floating_text = false

	var actual_damage:float = maxf(before_health - float(target.health),0.0)
	if actual_damage > 0.0:
		if is_instance_valid(target.health_bar):
			target.health_bar.pulse_health_number_on_silent_damage()
		target.record_combat_damage_source(self,before_health)
		if Game.has_method("report_combat_damage"):
			Game.report_combat_damage(self,target,actual_damage,before_health)

		# V181：Sans 的骨头/龙骨炮为了保持严格 1 点帧伤，会直接扣 health，
		# 因此不会经过目标覆写的 take_damage()。像军官这种“按实际掉血累计进度”的
		# 角色需要收到一次“已经结算完成的真实生命损失”通知。
		# 这里只通知，不再次扣血，避免伤害翻倍。
		if target.has_method("notify_external_actual_health_damage"):
			target.call("notify_external_actual_health_damage",actual_damage,self)

		play_sans_damage_feedback(target,false)
		queue_sans_damage_text(target,actual_damage)

	if karma_amount > 0.0 and target.health > 1:
		_add_karma_to_target(target,karma_amount)


func _add_karma_to_target(target:ball,amount:float) -> void:
	if target == null or amount <= 0.0:
		return
	var effect:Node = target.get_node_or_null("SansKarmaEffect")
	if effect == null:
		effect = KARMA_SCRIPT.new() as Node
		if effect == null:
			return
		effect.name = "SansKarmaEffect"
		target.add_child(effect)
	if effect.has_method("add_karma"):
		effect.call("add_karma",amount,self)


# ========================================================
# V158 帧伤跳字：真实伤害逐 physics frame 固定 1 点。
# 为避免每秒创建约 60 个 Label/Tween，显示层只做节流，不再把多帧伤害累加。
# 因此骨头/龙骨炮/KR 的每个可见跳字永远是 1。
# ========================================================
func queue_sans_damage_text(target:ball,_amount:float = 1.0) -> void:
	if target == null or not is_instance_valid(target):
		return
	var cooldown_key:StringName = &"sans_damage_text_next_usec"
	var now_usec:int = Time.get_ticks_usec()
	var next_usec:int = int(target.get_meta(cooldown_key,0))
	if now_usec < next_usec:
		return
	target.set_meta(cooldown_key,now_usec + int(maxf(damage_text_batch_interval,0.04) * 1000000.0))
	if target.health_bar == null or not is_instance_valid(target.health_bar):
		return
	if target.health_bar.has_method("_spawn_damage_text"):
		target.health_bar.call("_spawn_damage_text",1,target.health_bar.health_bar)


# ========================================================
# V155 Sans 音效 / KARMA 视觉反馈
# ========================================================
func play_sans_damage_feedback(target:ball,purple_flash:bool = false) -> void:
	if target == null or not is_instance_valid(target):
		return
	var target_name:String = str(target.name)
	if multiplayer.has_multiplayer_peer():
		_rpc_play_sans_damage_feedback.rpc(target_name,purple_flash)
	else:
		_rpc_play_sans_damage_feedback(target_name,purple_flash)


@rpc("authority","call_local","unreliable")
func _rpc_play_sans_damage_feedback(target_name:String,purple_flash:bool) -> void:
	var target:ball = _find_ball_by_name(target_name)
	if target == null:
		return
	var audio:=target.get_node_or_null("SansDamageAudio") as AudioStreamPlayer2D
	if audio == null:
		audio = AudioStreamPlayer2D.new()
		audio.name = "SansDamageAudio"
		audio.stream = SFX_DAMAGE
		audio.max_polyphony = 10
		audio.volume_db = 6.0
		audio.max_distance = 1200.0
		target.add_child(audio)
	audio.play()
	if purple_flash:
		_flash_target_karma_purple(target)


func _flash_target_karma_purple(target:ball) -> void:
	if target == null or target.image == null or not is_instance_valid(target.image):
		return
	var sprite:CanvasItem = target.image
	var token_key:StringName = &"sans_karma_flash_token"
	var original_key:StringName = &"sans_karma_original_hit_color"
	var token:int = int(sprite.get_meta(token_key,0)) + 1
	if not sprite.has_meta(original_key):
		var raw_original:Variant = sprite.get_instance_shader_parameter("hit_white_color")
		sprite.set_meta(original_key,raw_original if raw_original is Color else Color.WHITE)
	sprite.set_meta(token_key,token)
	sprite.set_instance_shader_parameter("hit_white_color",KARMA_FLASH_COLOR)

	# V183：不能再调用 hit_white_visual_only()，因为它会把 power 拉到 1.0，
	# 对当前项目 Shader 来说等价于把原像素完全替换成统一紫色。这里仅叠一层 42% 紫色，
	# 原贴图细节、亮暗和已有颜色仍可见，然后沿用受击闪白时长淡出。
	if target.hit_white_tween != null and target.hit_white_tween.is_valid():
		target.hit_white_tween.kill()
	var overlay_power:float = clampf(KARMA_FLASH_OVERLAY_POWER,0.0,0.95)
	target.hit_white_method(overlay_power)
	target.hit_white_tween = target.create_tween()
	target.hit_white_tween.tween_method(
		Callable(target,"hit_white_method"),
		overlay_power,
		0.0,
		maxf(target.hit_white_duration,0.05)
	)
	_restore_karma_flash_color_later(sprite,token,maxf(target.hit_white_duration,0.05) + 0.025)


func _restore_karma_flash_color_later(sprite:CanvasItem,token:int,delay:float) -> void:
	if get_tree() == null:
		return
	await get_tree().create_timer(maxf(delay,0.03)).timeout
	if sprite == null or not is_instance_valid(sprite):
		return
	if int(sprite.get_meta(&"sans_karma_flash_token",-1)) != token:
		return
	var original:Variant = sprite.get_meta(&"sans_karma_original_hit_color",Color.WHITE)
	sprite.set_instance_shader_parameter("hit_white_color",original if original is Color else Color.WHITE)
	sprite.remove_meta(&"sans_karma_flash_token")
	sprite.remove_meta(&"sans_karma_original_hit_color")


func _play_slam_sfx_networked(world_position:Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_slam_sfx.rpc(world_position)
	else:
		_rpc_play_slam_sfx(world_position)


@rpc("authority","call_local","unreliable")
func _rpc_play_slam_sfx(world_position:Vector2) -> void:
	if get_tree() == null or get_tree().current_scene == null:
		return
	var player:=AudioStreamPlayer2D.new()
	player.name = "SansGravitySlamAudio"
	player.stream = SFX_SLAM
	player.volume_db = -1.0
	player.max_distance = 1400.0
	get_tree().current_scene.add_child(player)
	player.global_position = world_position
	player.finished.connect(player.queue_free)
	player.play()


# ========================================================
# 闪避：普通 14 / Boss 特殊化 30；成功后完全无敌保护 0.1 秒
# ========================================================
func _update_dodge_recovery(delta:float) -> void:
	if _dodge_count >= max_dodge_count:
		_dodge_count = max_dodge_count
		_time_since_incoming_attack = 0.0
		_recovery_accumulator = 0.0
		return

	_time_since_incoming_attack += delta
	if _time_since_incoming_attack < maxf(dodge_recovery_delay,0.0):
		return

	_recovery_accumulator += delta
	var interval:float = maxf(dodge_recovery_interval,0.1)
	while _recovery_accumulator >= interval and _dodge_count < max_dodge_count:
		_recovery_accumulator -= interval
		_set_dodge_count_networked(_dodge_count + 1)
	if _dodge_count >= max_dodge_count:
		_recovery_accumulator = 0.0


func _mark_incoming_attack() -> void:
	_time_since_incoming_attack = 0.0
	_recovery_accumulator = 0.0


func _try_dodge_incoming() -> bool:
	if _last_trial_active:
		return true # 同帧立即免疫，阶段期间绝不再扣最后一次闪避。
	if not is_multiplayer_authority():
		return false
	if health <= 0 or state_machine == null or state_machine.current_state == State.Die:
		return false
	_mark_incoming_attack()
	# V172：一次成功闪避后的密集弹丸/同一攻击多 HitBox 仍然判定 MISS，
	# 但保护期内绝不重复扣闪避次数，也不重复瞬移/生成 MISS。
	if _dodge_grace_remaining > 0.0:
		return true
	if _dodge_count <= 0:
		return false
	_dodge_grace_remaining = maxf(dodge_post_success_grace,0.0)
	var origin_position:Vector2 = global_position
	var target_position:Vector2 = _pick_random_dodge_position()
	var remaining:int = maxi(_dodge_count - 1,0)
	if multiplayer.has_multiplayer_peer():
		_rpc_apply_dodge.rpc(origin_position,target_position,remaining)
	else:
		_rpc_apply_dodge(origin_position,target_position,remaining)
	if _boss_specialized and remaining == 1 and not _last_trial_used:
		_last_trial_active = true
		_last_trial_launch_queued = true
		_launch_last_trial.call_deferred()
	return true


func can_receive_hit_contact(_incoming_hit:hitbox,_contact_hurtbox:hurtbox) -> bool:
	return not _try_dodge_incoming()


func can_receive_hit_from(_incoming_hit:hitbox) -> bool:
	return not _try_dodge_incoming()


func on_incoming_hit_rejected(_incoming_hit:hitbox) -> void:
	pass


func should_destroy_projectile_on_rejected_hit(_incoming_hit:hitbox) -> bool:
	return false


# V179：给不经过公共 hitbox.gd、而是自己做 RayCast/连续扫掠的投射物使用。
# 返回 true = Sans 已经完成本次闪避，投射物必须把 Sans 当成“空气”继续原轨迹；
# 不播放命中/格挡反馈，不停止、不销毁、不反弹，也不改变自身状态。
func try_full_projectile_dodge(_projectile:Node = null) -> bool:
	return _try_dodge_incoming()


func receive_positional_damage(damage:float,impact_position:Vector2,ignore_block:bool = false,source:Node = null) -> bool:
	if damage > 0.0 and _try_dodge_incoming():
		return false
	return super.receive_positional_damage(damage,impact_position,ignore_block,source)


func receive_spatial_damage(damage:float,damage_space:Variant,ignore_block:bool = false,raw_health:bool = false) -> bool:
	if damage > 0.0 and _try_dodge_incoming():
		return false
	return super.receive_spatial_damage(damage,damage_space,ignore_block,raw_health)


func take_damage(damage:float,ignore_block:bool = false) -> void:
	if damage > 0.0 and _try_dodge_incoming():
		return
	super.take_damage(damage,ignore_block)


# “完全闪避”期间不接受同一波攻击随后追加的击退。
# 这只保护 Sans，自身闪避位移仍由 _rpc_apply_dodge() 直接设置 global_position。
func apply_knockback(
	knockback_direction:Vector2,
	knockback_distance:float,
	knockback_speed:float = 700.0,
	wall_bounce_strength:float = 0.0,
	stun_duration:float = 0.0,
	options:Dictionary = {}
) -> Node:
	if _dodge_grace_remaining > 0.0 and health > 0:
		return null
	return super.apply_knockback(
		knockback_direction,
		knockback_distance,
		knockback_speed,
		wall_bounce_strength,
		stun_duration,
		options
	)


@rpc("authority","call_local","reliable")
func _rpc_apply_dodge(origin_position:Vector2,target_position:Vector2,remaining:int) -> void:
	_apply_dodge_local(origin_position,target_position,remaining)


func _apply_dodge_local(origin_position:Vector2,target_position:Vector2,remaining:int) -> void:
	_dodge_grace_remaining = maxf(_dodge_grace_remaining,maxf(dodge_post_success_grace,0.0))
	var previous:int = _dodge_count
	_dodge_count = clampi(remaining,0,maxi(max_dodge_count,1))
	if _dodge_count != previous:
		_show_dodge_bar()
	# V168：用户要删除的是“人物身上的常驻闪避文字”，不是被攻击后跳出的 MISS。
	# MISS 留在闪避发生前的原位置，Sans 瞬移后仍会完成轻跳 + 渐隐。
	_spawn_miss_visual(origin_position)
	_set_visual_mode_local(SansVisual.DODGE)
	global_position = target_position
	_play_dodge_stretch_and_flash()
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO
	_motion_visual_last_position = global_position
	_motion_visual_initialized = true
	_refresh_dodge_status()


func _spawn_miss_visual(origin_position:Vector2) -> void:
	if get_tree() == null or get_tree().current_scene == null:
		return
	var label:=Label.new()
	label.name = "SansMISS"
	label.text = "MISS"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(50.0,22.0)
	label.size = Vector2(50.0,22.0)
	label.add_theme_font_size_override("font_size",14)
	label.add_theme_color_override("font_color",Color(0.02,0.02,0.025,1.0))
	label.add_theme_color_override("font_outline_color",Color(0.62,0.62,0.67,1.0))
	label.add_theme_constant_override("outline_size",4)
	label.z_as_relative = false
	label.z_index = 96
	get_tree().current_scene.add_child(label)
	var start_position:Vector2 = origin_position - label.size * 0.5 + Vector2(0.0,-26.0)
	label.global_position = start_position
	var tween:=label.create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(label,"global_position",start_position + Vector2(0.0,-7.0),0.10)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(label,"global_position",start_position,0.11)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(label,"modulate:a",0.0,0.34)
	tween.finished.connect(label.queue_free)


func _set_dodge_count_networked(value:int) -> void:
	var clamped:int = clampi(value,0,maxi(max_dodge_count,1))
	if multiplayer.has_multiplayer_peer():
		_rpc_sync_dodge_count.rpc(clamped)
	else:
		_rpc_sync_dodge_count(clamped)


@rpc("authority","call_local","reliable")
func _rpc_sync_dodge_count(value:int) -> void:
	var previous:int = _dodge_count
	_dodge_count = clampi(value,0,maxi(max_dodge_count,1))
	if _dodge_count != previous:
		_show_dodge_bar()
	_refresh_dodge_status()


func _refresh_dodge_status() -> void:
	if not is_inside_tree():
		return
	# V165：不再常驻显示“闪避: x/20”文字。剩余次数只通过脚下分段条反馈。
	# 新生成的 Sans 本身没有旧 permanent 项；这里保留移除调用，兼容热重载/旧存档实例。
	if has_method("side_status_remove_permanent"):
		call("side_status_remove_permanent","right","sans_dodge_count")
	_update_sweat_visual()


func _show_dodge_bar() -> void:
	_dodge_bar_alpha = 1.0
	_dodge_bar_hold_left = maxf(dodge_bar_hold_duration,0.0)
	_dodge_bar_fade_left = maxf(dodge_bar_fade_duration,0.05)
	queue_redraw()


func _update_dodge_bar_visual(delta:float) -> void:
	if _dodge_bar_alpha <= 0.0:
		return
	var safe_delta:float = maxf(delta,0.0)
	if _dodge_bar_hold_left > 0.0:
		_dodge_bar_hold_left = maxf(_dodge_bar_hold_left - safe_delta,0.0)
	else:
		_dodge_bar_fade_left = maxf(_dodge_bar_fade_left - safe_delta,0.0)
		_dodge_bar_alpha = clampf(
			_dodge_bar_fade_left / maxf(dodge_bar_fade_duration,0.05),
			0.0,1.0
		)
	queue_redraw()


func _dodge_bar_color(color:Color) -> Color:
	return Color(color.r,color.g,color.b,color.a * clampf(_dodge_bar_alpha,0.0,1.0))


func _draw() -> void:
	if _dodge_bar_alpha <= 0.001 or _death_visual_started_local:
		return
	var max_count:int = maxi(max_dodge_count,1)
	var remaining:int = clampi(_dodge_count,0,max_count)
	var pad_vec:=Vector2(DODGE_BAR_OUTER_PAD,DODGE_BAR_OUTER_PAD)

	draw_rect(
		Rect2(DODGE_BAR_RECT.position - pad_vec,DODGE_BAR_RECT.size + pad_vec * 2.0),
		_dodge_bar_color(DODGE_BAR_OUTER_COLOR),
		true
	)
	draw_rect(DODGE_BAR_RECT,_dodge_bar_color(DODGE_BAR_BACKGROUND_COLOR),true)

	# 每一个完整白格 = 一次仍可使用的闪避。
	# 先按剩余次数填白，再在每个格子边界画黑线，20 格在视觉上始终清晰可数。
	if remaining > 0:
		var filled_ratio:float = float(remaining) / float(max_count)
		draw_rect(
			Rect2(
				DODGE_BAR_RECT.position,
				Vector2(DODGE_BAR_RECT.size.x * filled_ratio,DODGE_BAR_RECT.size.y)
			),
			_dodge_bar_color(DODGE_BAR_FILL_COLOR),
			true
		)

	var segment_width:float = DODGE_BAR_RECT.size.x / float(max_count)
	for i:int in range(1,max_count):
		var x:float = DODGE_BAR_RECT.position.x + segment_width * float(i)
		draw_line(
			Vector2(x,DODGE_BAR_RECT.position.y),
			Vector2(x,DODGE_BAR_RECT.end.y),
			_dodge_bar_color(DODGE_BAR_SEPARATOR_COLOR),
			1.5
		)

	draw_rect(
		DODGE_BAR_RECT,
		_dodge_bar_color(DODGE_BAR_BORDER_COLOR),
		false,
		DODGE_BAR_BORDER_WIDTH
	)


func _pick_random_dodge_position() -> Vector2:
	var map_rect:Rect2 = _current_map_world_rect()
	if map_rect.size.x <= 0.001 or map_rect.size.y <= 0.001:
		return global_position + Vector2.from_angle(_dodge_rng.randf_range(0.0,TAU)) * 72.0

	var margin:float = maxf(dodge_map_margin,2.0)
	var safe_min:Vector2 = map_rect.position + Vector2.ONE * margin
	var safe_max:Vector2 = map_rect.end - Vector2.ONE * margin
	if safe_max.x <= safe_min.x or safe_max.y <= safe_min.y:
		safe_min = map_rect.position + Vector2.ONE * 2.0
		safe_max = map_rect.end - Vector2.ONE * 2.0
	if safe_max.x <= safe_min.x or safe_max.y <= safe_min.y:
		return map_rect.get_center()

	var fallback_any:Vector2 = map_rect.get_center()
	var fallback_clear:Vector2 = fallback_any
	var has_clear_fallback:bool = false
	var best_safe:Vector2 = Vector2.ZERO
	var best_safe_score:float = -INF
	var has_safe:bool = false
	for _i:int in range(maxi(dodge_position_attempts,1)):
		var candidate:=Vector2(
			_dodge_rng.randf_range(safe_min.x,safe_max.x),
			_dodge_rng.randf_range(safe_min.y,safe_max.y)
		)
		fallback_any = candidate
		if dodge_min_distance > 0.0 and candidate.distance_to(global_position) < dodge_min_distance:
			continue
		if not _dodge_position_is_clear(candidate):
			continue
		fallback_clear = candidate
		has_clear_fallback = true
		if not _dodge_position_is_hazard_safe(candidate):
			continue
		var score:float = _dodge_position_safety_score(candidate,map_rect)
		if not has_safe or score > best_safe_score:
			has_safe = true
			best_safe = candidate
			best_safe_score = score

	# 优先真正安全的位置；拥挤到一个都找不到时，再退化成普通随机闪避。
	if has_safe:
		return best_safe
	if has_clear_fallback:
		return fallback_clear
	return fallback_any


func _dodge_position_is_clear(candidate:Vector2) -> bool:
	if get_world_2d() == null:
		return true
	var shape:=CircleShape2D.new()
	shape.radius = maxf(dodge_clearance_radius,4.0)
	var query:=PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0,candidate)
	query.collision_mask = 3
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	var hits:Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(query,8)
	return hits.is_empty()


func _dodge_position_safety_score(candidate:Vector2,map_rect:Rect2) -> float:
	var nearest_enemy:float = maxf(map_rect.size.length(),1.0)
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if raw is ball:
			var other:ball = raw as ball
			if _is_valid_enemy(other):
				nearest_enemy = minf(nearest_enemy,candidate.distance_to(other.global_position))
	var wall_clearance:float = minf(
		minf(candidate.x - map_rect.position.x,map_rect.end.x - candidate.x),
		minf(candidate.y - map_rect.position.y,map_rect.end.y - candidate.y)
	)
	return nearest_enemy + maxf(wall_clearance,0.0) * 0.35


func _dodge_position_is_hazard_safe(candidate:Vector2) -> bool:
	var enemy_clearance:float = maxf(dodge_enemy_safe_distance,0.0)
	if enemy_clearance > 0.0:
		for raw:Node in get_tree().get_nodes_in_group("Ball"):
			if raw is ball:
				var other:ball = raw as ball
				if _is_valid_enemy(other) and candidate.distance_to(other.global_position) < enemy_clearance:
					return false

	var padding:float = maxf(dodge_hazard_padding,0.0) + maxf(dodge_clearance_radius,0.0)
	for hazard:Node in get_tree().get_nodes_in_group("AI_Hazard"):
		if hazard == null or not is_instance_valid(hazard) or not hazard.has_method("get_ai_hazard_info"):
			continue
		var raw_info:Variant = hazard.call("get_ai_hazard_info",self)
		if not raw_info is Dictionary or (raw_info as Dictionary).is_empty():
			continue
		var info:Dictionary = raw_info as Dictionary
		if not _dodge_hazard_should_avoid(info,hazard):
			continue
		if _dodge_point_inside_hazard(candidate,info,padding):
			return false
	return true


func _dodge_hazard_should_avoid(info:Dictionary,hazard:Node) -> bool:
	if bool(info.get("blocking",false)):
		return true
	var source_value:Variant = info.get("source",hazard)
	if source_value is ball:
		var hazard_source:ball = source_value as ball
		if hazard_source == self:
			return false
		if not Game.Game_Settings.Have_Team_Damage and not Team.is_empty() and not hazard_source.Team.is_empty() and Team == hazard_source.Team:
			return false
	return true


func _dodge_point_inside_hazard(point:Vector2,info:Dictionary,padding:float) -> bool:
	var shape_kind:String = str(info.get("shape",""))
	if shape_kind == "all" or shape_kind == "global_fate":
		return true
	if shape_kind == "circle":
		var center:Vector2 = info.get("center",info.get("position",Vector2.ZERO))
		var radius:float = maxf(float(info.get("radius",0.0)),0.0) + padding
		return point.distance_squared_to(center) <= radius * radius
	if shape_kind == "rect":
		var center:Vector2 = info.get("center",info.get("position",Vector2.ZERO))
		var half_extents:Vector2 = Vector2.ZERO
		if info.has("half_extents"):
			half_extents = info.get("half_extents",Vector2.ZERO)
		elif info.has("size"):
			var raw_size:Variant = info.get("size",Vector2.ZERO)
			if raw_size is Vector2:
				half_extents = (raw_size as Vector2) * 0.5
		half_extents += Vector2.ONE * padding
		var local:Vector2 = (point - center).rotated(-float(info.get("rotation",0.0)))
		return absf(local.x) <= half_extents.x and absf(local.y) <= half_extents.y
	if shape_kind == "segment" or shape_kind == "capsule":
		var start:Vector2 = info.get("start",info.get("from",Vector2.ZERO))
		var finish:Vector2 = info.get("end",info.get("to",start))
		var radius:float = maxf(float(info.get("radius",info.get("half_width",0.0))),0.0) + padding
		return _distance_point_to_segment(point,start,finish) <= radius
	if shape_kind == "point":
		var center:Vector2 = info.get("point",info.get("position",Vector2.ZERO))
		return point.distance_to(center) <= padding
	return false


func _distance_point_to_segment(point:Vector2,start:Vector2,finish:Vector2) -> float:
	var segment:Vector2 = finish - start
	var length_sq:float = segment.length_squared()
	if length_sq <= 0.000001:
		return point.distance_to(start)
	var t:float = clampf((point - start).dot(segment) / length_sq,0.0,1.0)
	return point.distance_to(start + segment * t)


func _current_map_world_rect() -> Rect2:
	if get_tree() == null or get_tree().current_scene == null:
		return Rect2()
	var world:Node = get_tree().current_scene
	if not world.has_method("return_map_world_rect"):
		return Rect2()
	var maps_value:Variant = world.get("map_group")
	if not maps_value is Dictionary:
		return Rect2()
	var maps:Dictionary = maps_value
	var map_name:String = str(world.get("now_choose_map"))
	if map_name.is_empty() or not maps.has(map_name):
		return Rect2()
	var map_node:Variant = maps[map_name]
	if not map_node is TileMapLayer:
		return Rect2()
	var rect_value:Variant = world.call("return_map_world_rect",map_node)
	if rect_value is Rect2:
		return rect_value
	return Rect2()


# Sans 死亡时撤销由本 Sans 维持的持久重力/蓝色弹跳，避免目标在施法者已经离场后继续横着飞。
func _cleanup_all_sans_gravity_states() -> void:
	var active_target_name:String = ""
	if _active_gravity_target != null and is_instance_valid(_active_gravity_target):
		active_target_name = str(_active_gravity_target.name)
	_cleanup_active_gravity()
	if not active_target_name.is_empty():
		# 只撤销“当前砸击”的临时蓝 tint；Boss 蓝魂若也在该目标上，下面还会再撤销它自己的那一层。
		_set_gravity_tint_networked(active_target_name,false)

	var world:Node = get_tree().current_scene if get_tree() != null else null
	if world != null and is_instance_valid(world) and world.has_method("clear_directional_gravity"):
		# key 为空 = 清掉这个 source(Sans) 注册的全部持久目标重力。
		world.call("clear_directional_gravity",self,"")

	# 先撤 Boss 蓝魂层：关闭落地随机跳跃，并把 tint refcount 减掉一次。
	for raw_id:Variant in _boss_blue_targets.keys():
		var target_id:int = int(raw_id)
		var ref:WeakRef = _boss_blue_targets.get(target_id,null)
		var target:ball = (ref.get_ref() as ball) if ref != null else null
		if target == null or not is_instance_valid(target):
			continue
		target.configure_external_directional_gravity_hop(false)
		_set_gravity_tint_networked(str(target.name),false)

	# 再恢复每个目标第一次被本 Sans 改重力前的朝向/up_direction/重力终速。
	for raw_id:Variant in _persistent_gravity_targets.keys():
		var target_id:int = int(raw_id)
		var state:Dictionary = _persistent_gravity_targets.get(target_id,{})
		var ref:WeakRef = state.get("target_ref",null)
		var target:ball = (ref.get_ref() as ball) if ref != null else null
		if target == null or not is_instance_valid(target):
			continue
		target.clear_external_directional_gravity_velocity()
		target.external_directional_gravity_terminal_speed = float(
			state.get("original_terminal",target.external_directional_gravity_terminal_speed)
		)
		target.configure_external_directional_gravity_locomotion(
			bool(state.get("original_gravity_locomotion_enabled",false)),
			float(state.get("original_gravity_axis_ratio_max",0.80))
		)
		var original_up:Variant = state.get("original_up_direction",Vector2.UP)
		if original_up is Vector2 and (original_up as Vector2).length_squared() > 0.000001:
			target.up_direction = original_up as Vector2
		_set_target_gravity_rotation_networked(
			str(target.name),
			float(state.get("original_rotation",target.global_rotation))
		)
		_restore_gravity_target_sans_collision(target,state)

	_boss_blue_targets.clear()
	_persistent_gravity_targets.clear()


func _find_ball_by_name(target_name:String) -> ball:
	if target_name.is_empty() or get_tree() == null:
		return null
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if raw is ball and str(raw.name) == target_name:
			return raw as ball
	return null


func _has_death_animation() -> bool:
	# 与项目里的骷髅/蠹虫/苦力怕保持一致：0 HP 后先留在场上完成 Minecraft 风格死亡姿势，
	# 再在死亡位置播放烟雾，最后由 authority 真正释放。
	return true


func Die() -> void:
	if _death_sequence_started:
		return
	_death_sequence_started = true
	_attack_face_active = false
	_attack_face_remaining = 0.0
	if _sans_eye_glow != null and is_instance_valid(_sans_eye_glow):
		_sans_eye_glow.visible = false
	if _sans_sweat != null and is_instance_valid(_sans_sweat):
		_sans_sweat.visible = false
	_cancel_windmill()
	_cancel_rolling_bones()
	_boss_gravity_wall_sequence_serial += 1
	_cleanup_all_sans_gravity_states()

	var death_position:Vector2 = global_position
	# 公共死亡入口继续负责项目统一死亡音效/统计；Sans 自己只补 Minecraft 风格视觉。
	super.Die()
	_broadcast_death_visual(death_position)

	if get_tree() == null:
		if is_multiplayer_authority() and is_instance_valid(self):
			Game.free_node(self)
		return
	await get_tree().create_timer(DEATH_POSE_DURATION).timeout
	if is_instance_valid(self) and is_multiplayer_authority():
		Game.free_node(self)


func _broadcast_death_visual(death_position:Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_start_death_visual.rpc(death_position)
	else:
		_rpc_start_death_visual(death_position)


@rpc("authority","call_local","reliable")
func _rpc_start_death_visual(death_position:Vector2) -> void:
	if _death_visual_started_local:
		return
	_death_visual_started_local = true
	_attack_face_active = false
	_reset_dodge_stretch()
	set_process(false)
	set_physics_process(false)

	# 死亡姿势固定回正常插兜 Sans，避免恰好死在重力动画中时停在奇怪的动作帧。
	_apply_body_region(BODY_IDLE,SansVisual.IDLE)
	_apply_face_frame(NORMAL_FACE_INDEX)
	if _sans_eye_glow != null and is_instance_valid(_sans_eye_glow):
		_sans_eye_glow.visible = false
	if _sans_sweat != null and is_instance_valid(_sans_sweat):
		_sans_sweat.visible = false
	if health_bar != null and is_instance_valid(health_bar):
		health_bar.hide()

	if graphics != null and is_instance_valid(graphics):
		# 完全复用 Minecraft 人物的表现：快速整体染红，再横向倒下约 90°。
		var rotate_sign:float = -1.0 if direction.x >= 0.0 else 1.0
		var tween:Tween = graphics.create_tween()
		tween.set_parallel(true)
		tween.tween_property(graphics,"modulate",Color(1.0,0.22,0.22,1.0),0.10)
		tween.tween_property(
			graphics,
			"rotation",
			graphics.rotation + rotate_sign * PI * 0.5,
			DEATH_POSE_DURATION
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	_create_delayed_death_smoke(death_position)


func _create_delayed_death_smoke(death_position:Vector2) -> void:
	var visual_parent:Node = _get_death_visual_parent()
	if visual_parent == null:
		return

	var smoke:=AnimatedSprite2D.new()
	smoke.name = "Sans死亡烟雾_%d" % smoke.get_instance_id()
	smoke.sprite_frames = DEATH_SMOKE_FRAMES
	smoke.animation = &"死亡烟雾"
	smoke.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	smoke.z_as_relative = false
	smoke.z_index = 8
	smoke.scale = Vector2.ONE * 0.56
	smoke.visible = false
	visual_parent.add_child(smoke,true)
	smoke.global_position = death_position
	smoke.animation_finished.connect(Callable(smoke,"queue_free"),CONNECT_ONE_SHOT)

	# 烟雾独立挂在 World 的运行时视觉容器上；Sans 本体倒下完成后释放，烟雾仍会完整播完。
	var delayed:Tween = smoke.create_tween()
	delayed.tween_interval(DEATH_POSE_DURATION)
	delayed.tween_callback(Callable(smoke,"show"))
	delayed.tween_callback(Callable(smoke,"play").bind(&"死亡烟雾"))


func _get_death_visual_parent() -> Node:
	if get_tree() == null:
		return null
	var world:Node = get_tree().current_scene
	if world == null:
		return null
	var container:Node = world.get_node_or_null("V311运行时对象")
	if container != null:
		return container
	container = Node2D.new()
	container.name = "V311运行时对象"
	world.add_child(container,true)
	return container


func _launch_last_trial() -> void:
	_last_trial_launch_queued = false
	if not is_inside_tree() or _last_trial_used or not _last_trial_active or health <= 0:
		return
	var world:Node = get_tree().current_scene
	if world == null or world.has_meta(&"sans_final_phase"):
		return # 多个 Boss Sans 依次进入，禁止争用全场临时地图。
	if multiplayer.has_multiplayer_peer():
		_rpc_begin_last_trial.rpc()
	else:
		_rpc_begin_last_trial()


@rpc("authority","call_local","reliable")
func _rpc_begin_last_trial() -> void:
	if _last_trial_used:
		return
	var script:Script = load("res://scripts/effects/传说之下/Sans终幕.gd")
	var phase:Node2D = script.new()
	phase.name = "SansFinal_" + str(name)
	phase.set_multiplayer_authority(get_multiplayer_authority())
	get_tree().current_scene.add_child(phase)
	_last_trial_active = true
	_last_trial_controller = phase
	if phase.call("begin",self):
		_last_trial_used = true
	else:
		_last_trial_controller = null
		_last_trial_active = false
		phase.queue_free()
