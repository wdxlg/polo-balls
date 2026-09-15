class_name ball
extends CharacterBody2D

const VISUAL_PIXEL_SAMPLER_SCRIPT = preload("res://classes/visual_pixel_sampler.gd")

const WILD_DOG_OLD_AGE_AUDIO_PLAYED_META:StringName = &"wild_dog_milk_old_age_death_audio_played"
const DAMAGE_ELEMENT_FIRE:StringName = &"fire"

const KNOCKBACK_EFFECT_SCRIPT = preload("res://scripts/effects/knockback_effect.gd")
const HIT_BURST_EFFECT_SCRIPT = preload("res://scripts/effects/hit_burst_effect.gd")
const WALL_HIT_BURST_SCRIPT = preload("res://scripts/effects/wall_hit_burst.gd")
const STUN_VISUAL_SCENE = preload("res://scenes/effects/stun_visual.tscn")
const AFTER_IMAGE_MATERIAL = preload("res://shaders/after_image_material.tres")
const AFTER_IMAGE_STRETCH_MATERIAL = preload("res://shaders/after_image_stretch_material.tres")
const CHARACTER_SIDE_STATUS_UI_SCRIPT = preload("res://scripts/ui/character_side_status_ui.gd")
const SPECIAL_CHARACTER_THREAT_OVERLAY_SCRIPT = preload("res://scripts/training/special_character_threat_overlay.gd")
const BALL_MOTION_BLUR_SHADER = preload("res://shaders/ball_motion_blur.gdshader")

# V275：所有公共 poison Buff 共用的轻度深绿色视觉。
# 以 2 点 poison amount 约等于“一层”作为显示参考；首层只轻微变绿，叠加越高越明显。
const POISON_VISUAL_REFERENCE_AMOUNT_PER_STACK:float = 2.0
const POISON_VISUAL_STACK_DECAY:float = 0.86
const POISON_VISUAL_FULL_TINT:Color = Color(0.38,0.78,0.28,1.0)

# V254：只有真正人物使用脚底椭圆阴影。
# 阴影尺寸不再直接取整张图片/完整碰撞包围盒，而是采样人物贴图 Alpha 的“主体核心”：
# 伸出的手臂、武器、披风尖角等稀疏突出部分不会把脚底影子一起拉宽。
# 不把阴影做进 ball.tscn，避免投射物/召唤物等共享基场景对象被误加。
const CHARACTER_GROUND_SHADOW_SEGMENTS:int = 48
const CHARACTER_GROUND_SHADOW_SAMPLE_COLUMNS:int = 64
const CHARACTER_GROUND_SHADOW_SAMPLE_ROWS:int = 64
const CHARACTER_GROUND_SHADOW_ALPHA_THRESHOLD:float = 0.20
const CHARACTER_GROUND_SHADOW_CORE_MIN_DENSITY:float = 0.16
const CHARACTER_GROUND_SHADOW_CORE_RELATIVE_DENSITY:float = 0.42
const CHARACTER_GROUND_SHADOW_CORE_TOP_RATIO:float = 0.08
const CHARACTER_GROUND_SHADOW_CORE_BOTTOM_RATIO:float = 0.92
const CHARACTER_GROUND_SHADOW_WIDTH_RATIO:float = 0.90
const CHARACTER_GROUND_SHADOW_HEIGHT_FROM_WIDTH:float = 0.19
const CHARACTER_GROUND_SHADOW_MIN_WIDTH:float = 54.0
const CHARACTER_GROUND_SHADOW_MAX_WIDTH:float = 138.0
const CHARACTER_GROUND_SHADOW_MIN_HEIGHT:float = 10.0
const CHARACTER_GROUND_SHADOW_MAX_HEIGHT:float = 24.0
const CHARACTER_GROUND_SHADOW_FOOT_SCAN_COLUMNS:int = 96
const CHARACTER_GROUND_SHADOW_FOOT_MIN_OPAQUE_SAMPLES:int = 10
const CHARACTER_GROUND_SHADOW_FOOT_MIN_ROW_COVERAGE:float = 0.16
const CHARACTER_GROUND_SHADOW_FOOT_MIN_CONTIGUOUS_SAMPLES:int = 7
const CHARACTER_GROUND_SHADOW_OUTER_ALPHA:float = 0.14
const CHARACTER_GROUND_SHADOW_INNER_ALPHA:float = 0.18

# V59：这两个角色只保留威胁显示兼容识别。
# 不再为任何角色添加 PhysicsBody2D collision exception；角色本体碰撞始终有效。
const SPECIAL_CHARACTER_THREAT_OVERLAY_NAMES = ["伞夫","堇紫泪滴"]

#引用
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var health_bar: Health_bar = $Health_Bar
@onready var state_machine: Node = $state_machine
@onready var health_restore_timer: Timer = $Health_Restore_Timer
@onready var status_image: Sprite2D = $Status_Image
@onready var hurting_timer: Timer = $Hurting_Timer
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var graphics: Node2D = $Graphics

@export var image:Node2D

@export_category("角色侧边信息")
@export var side_status_ui_enabled:bool = true
@export_range(2.0,40.0,1.0) var side_status_horizontal_gap:float = 10.0
@export_range(40.0,160.0,2.0) var side_status_column_width:float = 76.0
@export_range(6,18,1) var side_status_font_size:int = 8
var side_status_ui:Control = null
var _special_character_threat_overlay:Node2D = null
var _character_ground_shadow:Node2D = null
var _character_ground_shadow_local_radius:Vector2 = Vector2.ZERO

# V275：记录外部/角色自身的 self_modulate 基线，避免中毒染色覆盖其它角色视觉。
var _poison_visual_base_self_modulate:Color = Color.WHITE
var _poison_visual_last_applied_self_modulate:Color = Color.WHITE
var _poison_visual_initialized:bool = false

func set_image_node_type() -> void:
	if not image:
		var sprite2d:Sprite2D = graphics.get_node("Image")
		var animatedspried2d:AnimatedSprite2D = graphics.get_node("AnimatedSprite2D")
		
		if sprite2d.texture != null:
			image = sprite2d
		else :
			image = animatedspried2d
		
	default_size = {
		scale = image.scale,
		skew = image.skew,
		offset = image.offset,
		rotation = image.rotation,
	}
	
	if image is Sprite2D:
		rect_size = image.get_rect().size
	elif image is AnimatedSprite2D:
		if image.sprite_frames and image.sprite_frames.has_animation(image.animation):
			rect_size = image.sprite_frames.get_frame_texture(image.animation,image.frame).get_size() * image.scale
		
	#碰撞
@onready var self_hitbox: hitbox = $hitbox
@onready var self_hurtbox: hurtbox = $hurtbox
	#设定
@export var When_Coliide_Tween:bool = true
@export var dir_left:bool = true
@export var Collide_Audio:String = "balls_collide1"
# 角色本体碰撞音效改为从 Audios.Sfx 下的音频组随机选择。
# Collide_Audio 保留给继承类/投射物的旧逻辑兼容。
@export var Collide_Audio_Node:String = "脚步"
@export var Hit_Audio:String = "balls_hit1"
@export var Dead_Audio:String = "DeadBell"
@export var Block_Audio:String = "BlockAtk1"
@export var BlockBreak_Audio:String = "DefenseBreak"

# ========================================================
# 角色独特音频
#
# 这些 AudioStream 槽位会出现在所有继承 ball 的人物 Inspector 中。
# 留空时继续使用原有的共享音效（Hit_Audio / Dead_Audio / 碰撞音频组等）。
# 填入后，常见角色事件会优先播放人物自己的 2D 定位音效。
# ========================================================
@export_group("角色独特音频")
@export var Unique_Attack_Audio:AudioStream
@export var Unique_Hit_Audio:AudioStream
@export var Unique_Hurt_Audio:AudioStream
@export var Unique_Skill_Audio:AudioStream
@export var Unique_Collide_Audio:AudioStream
@export var Unique_Death_Audio:AudioStream
@export var Unique_Block_Audio:AudioStream
@export var Unique_Block_Break_Audio:AudioStream
@export_range(-40.0,12.0,0.5) var Unique_Audio_Volume_DB:float = 0.0
@export_range(0.25,2.0,0.01) var Unique_Audio_Pitch_Scale:float = 1.0
@export_range(0.0,0.25,0.01) var Unique_Audio_Random_Pitch:float = 0.05
@export_range(50.0,3000.0,10.0) var Unique_Audio_Max_Distance:float = 900.0
@export_group("", "")

#常量
@export var Default_Rotation:float = self.rotation

# V286：所有 ball 派生投射物默认让根节点朝向“这一物理帧实际运动方向”。
# Default_Rotation 继续作为美术资源的基准偏角，因此旧场景里本来就有的 90°/180° 预旋转不会丢失。
@export_category("投射物视觉朝向")
@export var Projectile_Auto_Face_Motion:bool = true
@export_range(0.0,80.0,0.5) var Projectile_Facing_Min_Speed:float = 2.0
#变量
@onready var default_size:Dictionary
@onready var rect_size:Vector2
@onready var mouse_in_char:bool = false

enum State {
	Move,
	Stand,
	Die,
	Attack,
	Hurt,
	Skill
}
enum Ball_Type {
	Ball,
	Shooter,
	Shooter_with_Health,
	Creature
}

enum Character_Audio_Slot {
	Attack,
	Hit,
	Hurt,
	Skill,
	Collide,
	Death,
	Block,
	BlockBreak,
}

# V11：残影渲染模式与样式。
enum AfterImage_Render_Mode {
	Snapshots,
	Stretch_Only,
	Both
}
enum AfterImage_Texture_Mode {
	Source_Visual,
	Custom_Texture
}
# V12：单条 Stretch 可以选择旧版单 Sprite Warp，
# 或真正按历史运动路径弯曲的 Ribbon。
enum AfterImage_Stretch_Geometry_Mode {
	Sprite_Warp,
	Path_Ribbon
}
enum AfterImage_Style_Mode {
	Clean,
	Soft,
	Glow,
	Energy,
	Smoke,
	Silhouette
}
enum AfterImage_Fade_Mode {
	Linear,
	Smooth,
	Ease_Out,
	Ease_In
}
@export var Type:Ball_Type = Ball_Type.Ball

@export var Master:ball
@export var Master_name:String = ""
@onready var Creatures:Array[ball]

@export var Nearest_Enemy:Node
@export var Target_Enemy:Node

@export var image_color:Color = Color(1.0, 1.0, 1.0, 1.0)
@export var image_color_mix:float = 0

@export var Team:String = "Ball"

# ========================================================
# 角色标签
#
# ball 本体默认没有任何标签；具体角色在自己的 .tscn 中填写。
# Type_Tags：描述玩法/定位，例如“近战、射手、爆发、续航、控制、召唤”等。
# Negative_Tags：可被特殊机制读取的负面词条。键盘侠文字与目标负面标签完全匹配时会触发克制伤害。
#
# 使用 PackedStringArray：
# - Inspector 中仍然可以直接编辑；
# - 场景文件中序列化稳定；
# - 不需要把标签写死成 enum，之后可以继续自由增加新标签。
# ========================================================
@export_category("角色标签")
@export var Type_Tags:PackedStringArray = PackedStringArray()
@export var Negative_Tags:PackedStringArray = PackedStringArray()


func has_type_tag(tag:String) -> bool:
	var wanted:String = tag.strip_edges()
	if wanted.is_empty():
		return false
	for raw_tag in Type_Tags:
		if str(raw_tag).strip_edges() == wanted:
			return true
	return false


func has_negative_tag(tag:String) -> bool:
	var wanted:String = tag.strip_edges()
	if wanted.is_empty():
		return false
	for raw_tag in Negative_Tags:
		if str(raw_tag).strip_edges() == wanted:
			return true
	return false


# ========================================================
# 地图下方角色对话
#
# 角色脚本只需要调用：
#     say_dialogue("TRANSLATION_KEY", 3.0)
# 或直接传普通文字。World 会负责：
# - 检查“开启对话”设置；
# - 按角色所属阵营分配地图下方区域；
# - 计时模式为计时器保留独立区域；
# - 同一阵营的新台词覆盖旧台词。
# ========================================================
func say_dialogue(text:String, duration:float = -1.0) -> void:
	var source_text:String = text.strip_edges()
	if source_text.is_empty() or get_tree() == null:
		return
	_show_dialogue_local(source_text,duration)
	# V276：联网只同步“原始台词/翻译键”，绝不把房主已经翻译后的显示文字发给客户端。
	# 每个 peer 收到后都由自己的 Game.current_locale 再翻译，因此中文客户端不会被英文房主覆盖。
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_remote_say_dialogue.rpc(source_text,duration)


func _show_dialogue_local(source_text:String,duration:float) -> void:
	var world:Node = get_tree().current_scene
	if world == null or not is_instance_valid(world):
		return
	if world.has_method("show_character_dialogue"):
		world.call("show_character_dialogue", self, source_text, duration)


@rpc("authority","call_remote","reliable")
func _remote_say_dialogue(source_text:String,duration:float) -> void:
	_show_dialogue_local(source_text,duration)


# 逐字出现 + 停留 + 渐隐版本。
# reveal_duration 只负责“说话过程中”的逐字显示；显示完成后会强制补齐整句，
# 再等待 hold_duration，最后在 fade_duration 内淡出。
func say_dialogue_animated(
	text:String,
	reveal_duration:float,
	hold_duration:float = 1.2,
	fade_duration:float = 0.65
) -> void:
	var source_text:String = text.strip_edges()
	if source_text.is_empty() or get_tree() == null:
		return
	_show_dialogue_animated_local(source_text,reveal_duration,hold_duration,fade_duration)
	if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
		_remote_say_dialogue_animated.rpc(source_text,reveal_duration,hold_duration,fade_duration)


func _show_dialogue_animated_local(
	source_text:String,
	reveal_duration:float,
	hold_duration:float,
	fade_duration:float
) -> void:
	var world:Node = get_tree().current_scene
	if world == null or not is_instance_valid(world):
		return
	if world.has_method("show_character_dialogue_animated"):
		world.call(
			"show_character_dialogue_animated",
			self,
			source_text,
			maxf(reveal_duration, 0.0),
			maxf(hold_duration, 0.0),
			maxf(fade_duration, 0.0)
		)
	elif world.has_method("show_character_dialogue"):
		world.call(
			"show_character_dialogue",
			self,
			source_text,
			maxf(reveal_duration + hold_duration + fade_duration, 0.1)
		)


@rpc("authority","call_remote","reliable")
func _remote_say_dialogue_animated(
	source_text:String,
	reveal_duration:float,
	hold_duration:float,
	fade_duration:float
) -> void:
	_show_dialogue_animated_local(source_text,reveal_duration,hold_duration,fade_duration)


# ========================================================
# 队伍目标 / 友伤覆写（所有 ball 派生角色可复用）
# ========================================================
@export_category("队伍目标 / 友伤覆写")
# 允许角色脚本通过 return_reusable_combat_target() 把同队角色作为目标。
@export var Can_Target_Teammates:bool = false
# true：
#   有合法队友时优先锁最近队友。
# false：
#   如果 Can_Target_Teammates=true，则把最近队友和最近敌人一起比较，
#   谁离得更近就锁谁。
@export var Prefer_Teammates:bool = false
# 开启后，该角色以及 Master 指向它的投射物，无视全局 Have_Team_Damage 设置。
# 自己打自己、子弹打 Master 等保护规则仍然保留。
@export var Ignore_Team_Damage_Setting:bool = false

# ========================================================
# 本体碰撞伤害
# ========================================================
@export_category("本体碰撞伤害")
# 只控制“角色身体自然撞到角色”时，$hitbox 是否自动造成 Damage。
# false 不会移除 CharacterBody2D 的实体碰撞，所以角色仍会互相阻挡/反弹。
# 主动技能若显式调用 self_hitbox.try_hit_hurtbox()（例如决斗者刺击、猫抓挠），
# 仍然可以正常造成伤害，不受这个开关影响。
# 投射物/召唤物也不受这个开关影响；它只针对 Type == Ball_Type.Ball 的角色本体。
@export var Has_Collision_Damage:bool = false

func has_collision_damage() -> bool:
	return Type != Ball_Type.Ball or Has_Collision_Damage

@export var direction:Vector2 = Vector2.ZERO

@onready var Repel:Vector2 = Vector2.ZERO
#属性
@onready var Buff_Dic:Dictionary
#格式{
#顺序一般加法为1，乘法为2，特殊为0，最后为3
#Come_form(Node)={
	#Buff_Name={
		#算法=加法/乘法
		#剩余时间
		#类型(伤害，速度..)
		#数值
		#顺序
	#}
#}

@export var Attack_Cooling: float = 1
@export var Skill_Cooling: float = 1
@export var Health_Restore:int = 1
# 【攻击力统一规则】
# Damage 从 V107 起只表示“角色整体基础攻击力”，不再等同于本体碰撞伤害。
# Has_Collision_Damage 单独决定身体自然碰撞是否造成伤害。
# 只有一种攻击的角色：该攻击使用 Damage × 1.0。
# 有多种攻击的角色：Damage 保存最低的基础/独立攻击值，其余攻击只保存倍率，
# 最终伤害统一使用 attack_damage(倍率) = 当前 Damage × 倍率，再进入角色自身的最终伤害修正。
# 因此偷取/强化/削弱 Damage、Boss 倍率等都会同步影响角色的所有攻击方式。
@export var Damage:int = 10
@export var Speed:float = 100
# V129：所有普通角色的基础场景移动统一按 0.6 倍执行。
# 这里只缩放真实位移速度，不改写 Speed 属性本身，避免破坏牛系等“读取 Speed 计算技能/冲撞”的既有机制语义。
# Shooter / Creature 不属于“角色基础移速”，保持原速度。
const CHARACTER_BASE_MOVE_SPEED_MULTIPLIER:float = 0.60
@export var Damage_reduction:float = 0

# ========================================================
# 统一效果影响倍率
# ========================================================
@export_group("效果影响倍率")
# 通用正/负面效果倍率。0 = 完全免疫；1 = 标准；>1 = 效果更强。
# 现有 Minecraft 药水会正式接入这两个通用倍率；其它未来状态效果也应通过下方公共接口读取。
@export_range(0.0,10.0,0.05,"or_greater") var positive_effect_ratio:float = 1.0
@export_range(0.0,10.0,0.05,"or_greater") var negative_effect_ratio:float = 1.0
# 所有被明确标记为“纯火焰”的直接伤害、范围伤害与灼烧 DOT 都只在 receive_fire_* 入口乘一次。
# 0 = 完全免疫火焰伤害，并且不会附加/刷新灼烧。
@export_range(0.0,10.0,0.05,"or_greater") var fire_effect_ratio:float = 1.0

@export_subgroup("Minecraft 药水")
# 下面三个字段只服务于 res://scripts/effects/我的世界/女巫药水*.gd。
# 最终药水倍率 = 通用正/负面倍率 × 对应 Minecraft 药水倍率。
@export_range(0.0,10.0,0.05,"or_greater") var minecraft_potion_positive_effect_ratio:float = 1.0
@export_range(0.0,10.0,0.05,"or_greater") var minecraft_potion_negative_effect_ratio:float = 1.0
# true：瞬间治疗/持续恢复转为伤害；瞬间伤害/中毒转为治疗。
@export var minecraft_potion_invert_healing_damage:bool = false
@export_group("", "")

@export var Max_health:int = 100

@export_group("训练模式")
@export_group("", "")
var _training_mode_applied:bool = false

var _zero_health_resolution_pending:bool = false
# 最近一次真实生命伤害来源，用于把“实际死亡”归因给击杀者。
# 不长期保存 Node 引用：攻击者可能先于受害者死亡/queue_free，留下 <Freed Object>。
# 只保存 ObjectID，真正死亡时再验证并取回对象。
var _last_combat_damage_source_id:int = 0
var _last_combat_damage_health_before:float = 0.0
var _combat_death_reported:bool = false
# V64：伤害跳字使用“本次实际准备扣进生命的数值”，而不是被 0 HP 下限截断后的真实掉血。
# 例如 1 HP 受到 1000 伤害：生命仍只从 1 -> 0，但跳字应显示 -1000。
# 该值只在 health_changed 同步发射期间有效，不改变真实生命、击杀归因或战斗统计。
var _pending_health_damage_text_amount:int = 0
# V65：在完整 health setter 结算期间保留“请求扣血值”，让真正无限血角色也能识别
# 旧脚本直接 target.health -= huge_damage 的 INF 级破限伤害。
var _current_health_damage_request_amount:int = 0

func pending_health_damage_text_amount() -> int:
	return maxi(_pending_health_damage_text_amount,0)

func current_health_damage_request_amount() -> int:
	return maxi(_current_health_damage_request_amount,0)

@onready var health = Max_health:
	set(v):
		# 训练模式 V2 不再改生命规则：原上限、原伤害、原死亡流程全部保留。
		var old_health:int = int(health)
		var requested_health:int = int(v)
		var requested_health_damage:int = maxi(old_health - requested_health,0)
		var new_health:int = clampi(
			requested_health,
			0,
			Max_health
		)

		if new_health == health:
			return

		# 死亡状态禁止复活式回血。
		# 但允许把生命继续写到 0。
		if (
			state_machine
			and state_machine.current_state == State.Die
			and new_health > health
		):
			return

		_current_health_damage_request_amount = requested_health_damage

		# 关键修复：
		# 先修改真正的生命，再通知 HealthBar。
		#
		# 这样即使 UI 跳字/动画脚本出现问题，
		# 也不会阻止角色本身回血。
		health = new_health

		if health_bar:
			# health_changed 的 UI 回调是同步执行的；在这段窗口里提供未被 0 HP 下限截断的
			# 生命伤害显示值。发射完成立刻清空，避免后续回血/状态迁移误用旧值。
			_pending_health_damage_text_amount = requested_health_damage
			health_bar.health_changed.emit(
				old_health,
				health,
				Max_health,
				true
			)
			_pending_health_damage_text_amount = 0

		# 所有扣血路径最终都会经过 health setter。月计理智等角色机制只需覆写
		# on_actual_health_damage_received()，即可覆盖碰撞、技能、流血和直接扣血。
		var actual_health_loss:float = maxf(float(old_health - health), 0.0)
		if actual_health_loss > 0.0:
			# 先清空旧归因；真正带 source 的伤害会在伤害结算返回后重新 record。
			# 这样地图/自损等无来源扣血不会误算成上一位攻击者的击杀。
			_last_combat_damage_source_id = 0
			if has_meta("_kill_blood_context"):
				remove_meta("_kill_blood_context")
			_last_combat_damage_health_before = float(old_health)
			on_actual_health_damage_received(actual_health_loss, float(old_health))
			# 无敌/防御姿态可能在上面的角色钩子中恢复生命，必须在其后重新取实际损失。
			_notify_damage_camera_feedback(maxf(float(old_health) - float(health),0.0))
		_current_health_damage_request_amount = 0

		# 兜底：有些伤害来源会在状态机本帧更新之后才把生命写成 0。
		# 下一物理帧再确认一次，给猫/重女等 get_next_state() 的复活机制优先处理；
		# 若仍为 0，则确保普通人物真正进入死亡/释放流程。
		if health <= 0 and Type == Ball_Type.Ball:
			_schedule_zero_health_resolution()


# 统一从结算结果发出，不依赖 Hitbox、技能是否手工接入视觉反馈。
# 只由受击者权威端广播，避免属性同步与命中 RPC 在客户端重复计数。
# 无限生命目标可覆写视觉生命基准，不需要伪造真实扣血或战斗统计。
func get_impact_reference_health() -> float:
	return maxf(float(Max_health),1.0)


# 在已确认命中返回后查询；普通目标按减伤/护盾/免疫处理后的实际生命损失计算。
func get_received_hit_feedback_damage(_raw_damage:float,health_before:float) -> float:
	return maxf(health_before - float(health),0.0)


func _notify_damage_camera_feedback(actual_damage:float,blocked:bool = false) -> void:
	if actual_damage <= 0.0 or not is_finite(actual_damage):
		return
	if not is_node_ready() or not is_multiplayer_authority() or not is_combat_runtime_active():
		return
	_play_damage_camera_feedback_local(actual_damage,blocked)
	if multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_remote_damage_camera_feedback.rpc(actual_damage,blocked)


@rpc("authority","call_remote","unreliable")
func _remote_damage_camera_feedback(actual_damage:float,blocked:bool = false) -> void:
	_play_damage_camera_feedback_local(actual_damage,blocked)


func _play_damage_camera_feedback_local(actual_damage:float,blocked:bool = false) -> void:
	if not is_inside_tree():
		return
	var world:Node = get_tree().current_scene
	# 独立训练场/非战斗场景可以没有相机接口，不再直接写未知属性。
	if is_instance_valid(world) and world.has_method("add_damage_camera_shake"):
		world.call("add_damage_camera_shake",actual_damage)
	if not blocked and is_instance_valid(world) and world.has_method("request_damage_focus"):
		world.call("request_damage_focus",actual_damage,get_impact_reference_health(),global_position)
	if not is_instance_valid(world) or not world.has_method("add_confirmed_impact_visual"):
		return
	if Type != Ball_Type.Ball and Type != Ball_Type.Creature:
		return
	var accepted:bool = bool(world.call("add_confirmed_impact_visual",get_instance_id(),
		global_position,_hit_burst_character_radius(),actual_damage,get_impact_reference_health(),blocked))
	if accepted and not blocked:
		_play_confirmed_damage_flash(actual_damage)


func _play_confirmed_damage_flash(actual_damage:float) -> void:
	if image == null or not is_instance_valid(image) or Type == Ball_Type.Creature:
		return
	var strength:float = clampf(actual_damage / maxf(get_impact_reference_health() * 0.35,24.0),0.0,1.0)
	var peak:float = lerpf(0.65,1.0,sqrt(strength))
	if hit_white_tween:
		hit_white_tween.kill()
	hit_white_method(peak)
	hit_white_tween = create_tween()
	# 只改 shader，不更改 Hurt 状态/碰撞体；停顿期间不把闪白拖成长时间遮挡。
	hit_white_tween.set_ignore_time_scale(true)
	hit_white_tween.tween_interval(lerpf(0.012,0.025,strength))
	hit_white_tween.tween_method(hit_white_method,peak,0.0,lerpf(0.045,0.075,strength))


func _schedule_zero_health_resolution() -> void:
	if _zero_health_resolution_pending or not is_inside_tree():
		return
	_zero_health_resolution_pending = true
	call_deferred("_resolve_zero_health_after_physics")


func _resolve_zero_health_after_physics() -> void:
	if not is_inside_tree():
		_zero_health_resolution_pending = false
		return
	await get_tree().physics_frame
	_zero_health_resolution_pending = false
	if not is_inside_tree() or health > 0 or Type != Ball_Type.Ball:
		return
	if not is_multiplayer_authority():
		return

	# 状态机已经进入 Die，但旧逻辑没删掉节点时，直接做最后兜底。
	if state_machine != null and state_machine.current_state == State.Die:
		if not _has_death_animation() and not is_queued_for_deletion():
			queue_free()
		return

	# 主动询问一次下一状态。特殊复活角色会在这里恢复生命或返回 keep_state；
	# 普通角色会返回 State.Die。
	if state_machine != null:
		var next_state:int = get_next_state(state_machine.current_state)
		if health > 0:
			return
		if next_state == State.Die:
			state_machine.current_state = State.Die
		return

	# 极端情况下场景缺少状态机：仍保证普通人物不会以 0HP 永久留场。
	Die()
	if not _has_death_animation() and not is_queued_for_deletion():
		queue_free()


# 角色可覆写：只在真实生命下降时调用；护盾损失不会触发。
func on_actual_health_damage_received(_actual_health_damage:float, _health_before:float) -> void:
	pass


func record_combat_damage_source(source:Node, health_before:float) -> void:
	if not is_instance_valid(source):
		return
	_last_combat_damage_source_id = source.get_instance_id()
	_last_combat_damage_health_before = maxf(health_before, 0.0)


func _resolve_last_combat_damage_source() -> Node:
	if _last_combat_damage_source_id <= 0:
		return null
	if not is_instance_id_valid(_last_combat_damage_source_id):
		return null
	var candidate:Variant = instance_from_id(_last_combat_damage_source_id)
	if not is_instance_valid(candidate):
		return null
	if not (candidate is Node):
		return null
	return candidate as Node


func _report_combat_death_once() -> void:
	if _combat_death_reported:
		return
	_combat_death_reported = true
	if Game.has_method("report_combatant_death"):
		Game.report_combatant_death(
			self,
			_resolve_last_combat_damage_source(),
			_last_combat_damage_health_before
		)


#========================================================
# 训练模式生命规则
#========================================================
func apply_training_mode(enabled:bool) -> void:
	# V2：训练模式只负责训练工具/调试/复活策略，不再篡改人物 Max_health，
	# 也不锁 1HP、不周期回满。人物可以按原规则真正死亡。
	_training_mode_applied = enabled


#========================================================
# Boss 特殊化接口
#
# Boss 模式的数值倍率仍由 World 统一处理。角色如果拥有专属 Boss 形态，
# 只需要在自己的脚本里覆写下面三个方法即可。
# prepare_* 在 add_child()/ready 之前调用，适合改导出属性/资源选择；
# activate_* 在 ready 完成后调用，适合切图片、开阶段逻辑、生成专属节点。
#========================================================
func has_training_boss_specialization() -> bool:
	return false


func prepare_training_boss_specialization(_boss_multiplier:float) -> void:
	pass


func activate_training_boss_specialization(_boss_multiplier:float) -> void:
	pass



func training_prepare_property_reset() -> void:
	# 保留兼容入口；V2 不再改写 default_properties["Max_health"]。
	pass


func enforce_training_health_cap() -> void:
	# 保留兼容入口；V2 不再锁血量上限。
	pass


func _training_lock_health_cap(_fill_health:bool) -> void:
	pass


func _training_full_heal_if_needed() -> bool:
	return false


#========================================================
# 通用回血接口
#
# 所有 ball 派生角色以后都可以：
#
# heal(20)
#
# 返回实际恢复的生命。
#========================================================
#========================================================
# 通用击退 / 眩晕接口
#
# 所有 ball 派生角色都可以直接调用：
#
# target.apply_knockback(
#     direction,
#     distance,
#     speed,
#     wall_bounce_strength,
#     stun_duration,
#     {
#         "lock_control": true,
#         "stun_only_on_collision": false,
#         "collision_damage": 0.0,
#         "max_wall_bounces": 1,
#         "stop_on_character": true,
#         "character_bounce_strength": 0.0,
#         "use_speed_falloff": false,
#     }
# )
#
# 参数意义：
# distance                实际希望被击退/滑行的路径距离（px）
# speed                   击退过程速度（px/s）
# wall_bounce_strength    撞墙反弹倍率：0停止，0.5半速，1原速
# stun_duration           击退结束或碰撞后的眩晕时间
#
# 返回创建的 KnockbackEffect；参数非法时返回 null。
#========================================================
func apply_knockback(
	knockback_direction:Vector2,
	knockback_distance:float,
	knockback_speed:float = 700.0,
	wall_bounce_strength:float = 0.0,
	stun_duration:float = 0.0,
	options:Dictionary = {}
) -> Node:
	if health <= 0:
		return null
	if state_machine and state_machine.current_state == State.Die:
		return null
	if knockback_distance <= 0.0 and stun_duration <= 0.0:
		return null

	# V10.1：同一个角色同时只保留一个通用击退控制器。
	# 以前多人/多技能同帧命中会生成多个 KnockbackEffect，
	# 它们都在物理帧末尾写 Repel，最后执行的那个会覆盖前面的结果，
	# 于是会出现忽左忽右、突然停顿、撞墙后二次加速等不稳定观感。
	# 现在新击退默认平滑重定向现有控制器；确实需要并行效果时仍可显式 replace_existing=false。
	if bool(options.get("replace_existing",true)):
		for child in get_children():
			if child == null or not is_instance_valid(child):
				continue
			if child.get_script() != KNOCKBACK_EFFECT_SCRIPT:
				continue
			if child.has_method("is_active_effect") and not bool(child.call("is_active_effect")):
				continue
			if child.has_method("replace_with_hit"):
				child.call(
					"replace_with_hit",
					knockback_direction,
					maxf(knockback_distance,0.0),
					maxf(knockback_speed,0.0),
					maxf(wall_bounce_strength,0.0),
					maxf(stun_duration,0.0),
					options
				)
				return child

	var effect = KNOCKBACK_EFFECT_SCRIPT.new()
	effect.name = "KnockbackEffect_%d" % Time.get_ticks_usec()
	effect.target = self
	effect.source = options.get("source",null)
	effect.direction = knockback_direction
	effect.distance = maxf(knockback_distance,0.0)
	effect.speed = maxf(knockback_speed,0.0)
	effect.wall_bounce_strength = maxf(wall_bounce_strength,0.0)
	effect.max_wall_bounces = maxi(int(options.get("max_wall_bounces",1)),0)
	effect.stop_on_character = bool(options.get("stop_on_character",true))
	effect.character_bounce_strength = maxf(float(options.get("character_bounce_strength",0.0)),0.0)
	effect.lock_control_during_knockback = bool(options.get("lock_control",true))
	effect.stun_duration = maxf(stun_duration,0.0)
	effect.stun_only_on_collision = bool(options.get("stun_only_on_collision",false))
	effect.collision_damage = maxf(float(options.get("collision_damage",0.0)),0.0)
	effect.collision_damage_ignore_block = bool(options.get("collision_damage_ignore_block",false))
	effect.use_speed_falloff = bool(options.get("use_speed_falloff",false))
	effect.end_speed_ratio = clampf(float(options.get("end_speed_ratio",0.35)),0.0,1.0)

	# V10.1：默认开启物理式末段刹车、重定向平滑和控制恢复。
	effect.smooth_motion = bool(options.get("smooth_motion",true))
	effect.smooth_end_ratio = clampf(float(options.get("smooth_end_ratio",0.32)),0.05,0.8)
	effect.smooth_end_speed_ratio = clampf(float(options.get("smooth_end_speed_ratio",0.0)),0.0,0.5)
	effect.redirect_blend_time = clampf(float(options.get("redirect_blend_time",0.055)),0.0,0.2)
	effect.control_recovery_time = clampf(float(options.get("control_recovery_time",0.085)),0.0,0.25)
	effect.finish_distance_epsilon = clampf(float(options.get("finish_distance_epsilon",0.65)),0.1,4.0)
	effect.minimum_motion_time = clampf(float(options.get("minimum_motion_time",0.10)),0.0,0.3)
	# 兼容旧参数；新版不会再做“反弹后重新提速”。
	effect.bounce_recovery_time = 0.0
	effect.bounce_start_speed_ratio = 1.0
	effect.timeout_extra = maxf(float(options.get("timeout_extra",1.0)),0.25)

	add_child(effect)
	return effect

# 纯眩晕也复用同一个控制锁系统，避免多个技能互相提前解除 dizziness。
func apply_stun(duration:float) -> Node:
	if duration <= 0.0:
		return null

	return apply_knockback(
		Vector2.ZERO,
		0.0,
		0.0,
		0.0,
		duration,
		{
			"lock_control": true,
			"stun_only_on_collision": false,
		}
	)


func heal(amount:float) -> int:
	if amount <= 0.0:
		return 0

	if health <= 0:
		return 0

	if (
		state_machine
		and state_machine.current_state == State.Die
	):
		return 0

	var old_health:int = int(health)

	health = mini(
		health + int(round(amount)),
		Max_health
	)

	return maxi(
		int(health) - old_health,
		0
	)


@export var max_block:int = 0
@onready var block = 0:
	set(v):
		if v == block or not health_bar:return
		health_bar.block_changed.emit(block,v,max_block,true)
		
		block = clampi(v,0,max_block)
		
@export var max_energy:int = 0
@onready var energy = max_energy:
	set(v):
		if v == energy:
			return
		# 运行时复制角色可能会在 Health_Bar 完成 @onready 绑定前重写 energy。
		# 没有血条时仍然要正常写入能量，只跳过 UI 信号，避免 Nil.energy_changed 报错。
		if health_bar == null:
			energy = clampi(v,0,max_energy)
			return
		health_bar.energy_changed.emit(energy,v,max_energy,true)
		energy = clampi(v,0,max_energy)

@onready var default_properties:Dictionary = {
	Damage = Damage,
	Speed = Speed,
	max_block = max_block,
	max_energy = max_energy,
	Max_health = Max_health,
	Attack_Cooling = Attack_Cooling,
	Skill_Cooling = Skill_Cooling,
	Health_Restore = Health_Restore,
	Damage_reduction = Damage_reduction
}

# V379 性能：World 每个物理帧都会把这些运行时属性恢复到 default_properties。
# 旧实现由 World 对每个角色遍历 Dictionary，并通过 b[str(key)] 做 9 次动态属性写入。
# 这里改为 ball 内部的固定字段快速路径；仍然每帧读取 default_properties，所以角色脚本
# （例如猛攻哥护甲）运行时修改默认值后会立即生效，玩法语义保持不变。
func restore_default_runtime_properties_fast() -> void:
	var default_damage:int = int(default_properties.get("Damage",Damage))
	if Damage != default_damage:
		Damage = default_damage

	var default_speed:float = float(default_properties.get("Speed",Speed))
	if not is_equal_approx(Speed,default_speed):
		Speed = default_speed

	var default_max_block:int = int(default_properties.get("max_block",max_block))
	if max_block != default_max_block:
		max_block = default_max_block

	var default_max_energy:int = int(default_properties.get("max_energy",max_energy))
	if max_energy != default_max_energy:
		max_energy = default_max_energy

	var default_max_health:int = int(default_properties.get("Max_health",Max_health))
	if Max_health != default_max_health:
		Max_health = default_max_health

	var default_attack_cooling:float = float(default_properties.get("Attack_Cooling",Attack_Cooling))
	if not is_equal_approx(Attack_Cooling,default_attack_cooling):
		Attack_Cooling = default_attack_cooling

	var default_skill_cooling:float = float(default_properties.get("Skill_Cooling",Skill_Cooling))
	if not is_equal_approx(Skill_Cooling,default_skill_cooling):
		Skill_Cooling = default_skill_cooling

	var default_health_restore:int = int(default_properties.get("Health_Restore",Health_Restore))
	if Health_Restore != default_health_restore:
		Health_Restore = default_health_restore

	var default_damage_reduction:float = float(default_properties.get("Damage_reduction",Damage_reduction))
	if not is_equal_approx(Damage_reduction,default_damage_reduction):
		Damage_reduction = default_damage_reduction


@onready var defualt_collision:Dictionary = {
	Hitbox = {
		position = self_hitbox.position,
		scale = self_hitbox.scale,
		rotation = self_hitbox.rotation,
		skew = self_hitbox.skew,
	},
	Hurtbox = {
		position = self_hurtbox.position,
		scale = self_hurtbox.scale,
		rotation = self_hurtbox.rotation,
		skew = self_hurtbox.skew,
	},
	Collidebox = {
		position = collision_shape_2d.position,
		scale = collision_shape_2d.scale,
		rotation = collision_shape_2d.rotation,
		skew = collision_shape_2d.skew,
	},
}
#特殊状态
@onready var char_state
@export var ignore_block:bool = false
@export var Can_Attack:bool = true
@export var Can_Skill:bool = true
@onready var Attacking:bool = false
@onready var Using_Skill:bool = false

# V128：玩家直接控制。真正 authority（服务器）只保存输入意图；
# 普通 AI 可以继续计算自己的 direction，但 move() 最终优先使用这里的 WASD 输入。
# 这样角色专属状态机/死亡/变身逻辑不被一个全局“玩家状态机”粗暴替换。
var player_control_peer_id:int = 0
var player_control_direction:Vector2 = Vector2.ZERO
# V130：直接控制的“移动方向”和“攻击瞄准”必须完全分离。
# WASD 只写 player_control_direction；鼠标世界坐标单独由 Game 同步到这里。
var player_control_aim_position:Vector2 = Vector2.ZERO
var player_control_aim_valid:bool = false

func is_player_controlled() -> bool:
	return player_control_peer_id > 0

func set_player_control_peer(peer_id:int) -> void:
	player_control_peer_id = maxi(peer_id,0)
	if player_control_peer_id == 0:
		player_control_direction = Vector2.ZERO
		player_control_aim_valid = false

func set_player_control_direction(input_direction:Vector2) -> void:
	if player_control_peer_id <= 0:
		player_control_direction = Vector2.ZERO
		return
	player_control_direction = input_direction.limit_length(1.0)

func set_player_control_aim_position(world_position:Vector2) -> void:
	if player_control_peer_id <= 0:
		player_control_aim_valid = false
		return
	if not is_finite(world_position.x) or not is_finite(world_position.y):
		return
	player_control_aim_position = world_position
	player_control_aim_valid = true
	# 这里只保存鼠标世界坐标，不持续覆盖 legacy direction。
	# direction 仍可由角色 AI/真实碰撞维护；玩家点击出招时 player_control_action() 才把
	# 起手方向对齐鼠标。这样 WASD、碰撞反弹与“攻击瞄准”不会互相污染。

func has_player_control_aim() -> bool:
	return is_player_controlled() and player_control_aim_valid

func player_control_aim_world_position(fallback:Vector2 = Vector2.ZERO) -> Vector2:
	if has_player_control_aim():
		return player_control_aim_position
	return fallback

func player_control_aim_direction(fallback:Vector2 = Vector2.RIGHT) -> Vector2:
	if has_player_control_aim():
		var aim:Vector2 = player_control_aim_position - global_position
		if aim.length_squared() > 0.000001:
			return aim.normalized()
	if fallback.length_squared() > 0.000001:
		return fallback.normalized()
	return Vector2.RIGHT

# V380：动作键长按默认允许按“持续点击”重试。
# 少数“再次点击=关闭/切换”的角色可覆写本函数，让某个动作只响应按下沿，避免长按高速来回切换。
func player_control_action_hold_repeat_allowed(_action_index:int) -> bool:
	return true

func player_control_action(action_index:int) -> void:
	# V129：直接控制时鼠标动作必须是“玩家触发”，不能再与 AI 自动出招混在一起。
	# 左键只尝试普通攻击；右键只尝试技能；中键先走角色专用钩子，
	# 没有钩子时才按“技能 -> 普攻”兜底。所有动作继续服从冷却/眩晕/禁攻/死亡/authority。
	if not is_multiplayer_authority() or player_control_peer_id <= 0:
		return
	if state_machine == null or state_machine.current_state == State.Die or dizziness or is_damage_output_disabled():
		return

	# 点击发生的一刻先把角色的“攻击朝向”锁到鼠标，而不是继续沿 AI 的 Nearest_Enemy/direction。
	# 真正移动仍由 player_control_direction 决定，因此瞄准不会让 WASD 失效。
	if has_player_control_aim():
		direction = player_control_aim_direction(direction)

	if action_index == 2 and has_method("controlled_middle_action"):
		call("controlled_middle_action")
		return

	# V130：部分角色（赌徒/锻刀师/战争女神等）并不走公共 State.Attack/State.Skill，
	# 它们会把 Can_Attack/Can_Skill 设为 false 并维护自己的冷却。直接控制时给这类角色
	# 一个统一的手动入口，避免“公共角色能点，特殊角色仍然自己打”。
	if action_index == 0 and has_method("controlled_attack_action"):
		call("controlled_attack_action")
		return
	if action_index == 1 and has_method("controlled_skill_action"):
		call("controlled_skill_action")
		return

	if action_index == 0:
		if Can_Attack and not Attacking and float(state_machine.last_state_dis.get("Attack",0.0)) >= Attack_Cooling:
			state_machine.current_state = State.Attack
		return

	if action_index == 1:
		if Can_Skill and not Using_Skill and float(state_machine.last_state_dis.get("Skill",0.0)) >= Skill_Cooling:
			state_machine.current_state = State.Skill
		return

	if action_index == 2:
		if Can_Skill and not Using_Skill and float(state_machine.last_state_dis.get("Skill",0.0)) >= Skill_Cooling:
			state_machine.current_state = State.Skill
			return
		if Can_Attack and not Attacking and float(state_machine.last_state_dis.get("Attack",0.0)) >= Attack_Cooling:
			state_machine.current_state = State.Attack
@onready var can_restore_health:bool = true

# ========================================================
# 通用“伤害被禁止”状态
#
# 裁判红牌等效果用它统一封住角色的新普攻/技能，并让 Hitbox / 投射物
# 在命中时自动把有效伤害降为 0。使用绝对毫秒时间，重复施加时只延长、不会提前解除。
# ========================================================
var _damage_output_disabled_until_msec:int = 0

func apply_damage_disable(duration:float) -> void:
	if duration <= 0.0:
		return
	var until_msec:int = Time.get_ticks_msec() + int(round(duration * 1000.0))
	_damage_output_disabled_until_msec = maxi(_damage_output_disabled_until_msec,until_msec)
	# 立刻停止正在准备中的普通攻击/技能，避免红牌刚命中后仍在本帧继续出手。
	if is_multiplayer_authority():
		Attacking = false
		Using_Skill = false

func is_damage_output_disabled() -> bool:
	return Time.get_ticks_msec() < _damage_output_disabled_until_msec

func effective_outgoing_damage(raw_damage:float) -> float:
	var source:ball = self
	if Master != null and is_instance_valid(Master):
		source = Master
	if source != null and (source.is_damage_output_disabled() or not source.is_combat_runtime_active()):
		return 0.0
	return maxf(raw_damage,0.0)


# V107：所有角色特殊攻击统一从这里读取“整体攻击力”。
# multiplier 只描述该攻击相对基础攻击力的倍率，禁止再在角色脚本里另存一套绝对攻击值。
# 召唤物可以显式打开 inherit_master_attack_power，并提供自己的 master_attack_damage_multiplier。
# 默认关闭，避免普通投射物已经写入“最终 Damage”后又被 Master 二次缩放。
var inherit_master_attack_power:bool = false
var master_attack_damage_multiplier:float = 1.0

func attack_damage(multiplier:float = 1.0) -> float:
	var resolved_multiplier:float = maxf(multiplier,0.0)
	if (
		inherit_master_attack_power
		and Master != null
		and is_instance_valid(Master)
		and Master != self
	):
		return Master.attack_damage(maxf(master_attack_damage_multiplier,0.0) * resolved_multiplier)
	return effective_outgoing_damage(float(Damage) * resolved_multiplier)


# 普通 $hitbox 的动态倍率覆写点。
# 默认身体/近战 Hitbox 为 1.0；肌肉男、气球、牛系、愤怒的普通人等
# 会根据自身机制覆写，但不会再改写 Damage 本身。
func current_hit_damage_multiplier() -> float:
	return 1.0


# ========================================================
# V35 通用战斗运行闸门
#
# World 负责判断“布阵/特殊模式是否已经真正开战”；ball 统一把这个结果提供给
# 状态机和不走状态机的异步角色技能。独立训练场不是 World 时仍按原逻辑运行，
# 只尊重 SceneTree.pause / Game.now_stop_state。
# ========================================================
func is_combat_runtime_active() -> bool:
	var tree:SceneTree = get_tree()
	if tree == null or tree.paused or Game.now_stop_state or Engine.time_scale <= 0.000001:
		return false
	if _cached_world != null and is_instance_valid(_cached_world):
		return _cached_world.is_combat_runtime_active()
	var scene:Node = tree.current_scene
	if scene is World:
		_cached_world = scene as World
		return _cached_world.is_combat_runtime_active()
	if scene != null and scene.has_method("is_combat_runtime_active"):
		return bool(scene.call("is_combat_runtime_active"))
	return true


# 等待“实际战斗时间”。暂停、布阵、Boss 开场等阶段不会消耗 remaining；
# Engine.time_scale 仍参与计时，因此 0.5x/2x/32x 的技能节奏保持原来的游戏时间语义。


# ========================================================
# V259 场景级定向重力
#
# CharacterBody2D 不会由 Godot 自动获得重力/外力速度，因此这里把 World 提供的
# “定向重力加速度”积分成一条独立的持续速度，再在公共 move()/stand() 前叠进 Repel。
# 所有继承 ball 且走公共 tick_physics() 的人物、Creature、Shooter 都会吃到同一套外力；
# 子类即使先更新了自己的弹道/AI方向，也不会覆盖这条独立外力速度。
#
# 重力场结束后并不瞬间把已获得的速度清零，而是快速衰减，既保留被“拽走”的惯性，
# 又避免场结束后单位永久漂移。最大附加速度用于防止多个重力源叠加时数值失控。
# ========================================================
@export_category("场景定向重力")
@export_range(50.0,1600.0,10.0) var external_directional_gravity_terminal_speed:float = 420.0
@export_range(50.0,2400.0,10.0) var external_directional_gravity_release_deceleration:float = 620.0

var _external_directional_gravity_velocity:Vector2 = Vector2.ZERO
# V58：Sans 持久重力解除时可临时提高残余重力速度的衰减率；速度归零后自动清除覆盖值。
var _external_directional_gravity_release_deceleration_override:float = 0.0
# V185：Sans 持久重力改回标准重力运动。
# 重力轴只做 v += a * delta 的连续积分；角色自己的正常移动只投影到重力切线方向。
# V190：重力积分继续保持不变；Boss 深蓝起跳保持线性随机，力度调整为：
# 起跳速度 = Speed * 随机比例，比例范围默认 2.0~4.0。
# 不再平方，因此随机比例与实际起跳力度成线性关系，避免小比例被平方压得过小、大比例被放得过大。
var _external_directional_gravity_locomotion_enabled:bool = false
# 兼容 V182/V184 的公开接口与旧场景属性；V185 不再用它限制重力轴速度。
var _external_directional_gravity_axis_speed_ratio_max:float = 0.80
var _external_directional_gravity_lateral_sign:float = 1.0
var _external_directional_gravity_grounded:bool = false
var _external_directional_gravity_last_direction:Vector2 = Vector2.ZERO

# Boss 深蓝特殊状态：落地后随机等待再起跳。
# V190：等待逻辑保持不变；起跳力度直接取 Speed 的 2.0~5.0 倍线性随机，
# 只在起跳的一帧写入初速度，后续仍走正常重力加速度。
var _external_directional_gravity_hop_enabled:bool = false
var _external_directional_gravity_hop_min_interval:float = 0.40
var _external_directional_gravity_hop_max_interval:float = 1.20
var _external_directional_gravity_hop_min_ratio:float = 2.0
var _external_directional_gravity_hop_max_ratio:float = 4.0
var _external_directional_gravity_hop_wait_left:float = -1.0
var _external_directional_gravity_hop_rng:=RandomNumberGenerator.new()
var _projectile_facing_last_position:Vector2 = Vector2.ZERO
var _projectile_facing_position_initialized:bool = false
# V105：缓存 World 与“是否投射物”分类，避免每个单位每个 physics tick 都做
# SceneTree.current_scene / has_method / Script.resource_path 字符串判断。
var _cached_world:World = null
var _projectile_motion_object_cache_valid:bool = false
var _projectile_motion_object_cache:bool = false


func get_external_directional_gravity() -> Vector2:
	# 大多数战斗绝大多数时间根本没有定向重力。V105 走 World 的无分配快速入口，
	# 空重力场时只做一次 Dictionary.is_empty()，不再每单位每帧动态 call()。
	if _cached_world != null and is_instance_valid(_cached_world):
		if not _cached_world.has_active_directional_gravity_fast():
			return Vector2.ZERO
		return _cached_world.get_directional_gravity_for_fast(self)
	var tree:SceneTree = get_tree()
	if tree == null:
		return Vector2.ZERO
	var scene:Node = tree.current_scene
	if scene is World:
		_cached_world = scene as World
		if not _cached_world.has_active_directional_gravity_fast():
			return Vector2.ZERO
		return _cached_world.get_directional_gravity_for_fast(self)
	if scene != null and scene.has_method("get_directional_gravity_for"):
		var resolved:Variant = scene.call("get_directional_gravity_for",self)
		if typeof(resolved) == TYPE_VECTOR2:
			return resolved
	return Vector2.ZERO


func get_external_directional_gravity_velocity() -> Vector2:
	return _external_directional_gravity_velocity


func clear_external_directional_gravity_velocity() -> void:
	_external_directional_gravity_velocity = Vector2.ZERO


func begin_external_directional_gravity_release(deceleration:float) -> void:
	_external_directional_gravity_release_deceleration_override = maxf(deceleration,0.0)


func cancel_external_directional_gravity_release() -> void:
	_external_directional_gravity_release_deceleration_override = 0.0


func configure_external_directional_gravity_locomotion(enabled:bool,axis_speed_ratio_max:float = 0.80) -> void:
	_external_directional_gravity_locomotion_enabled = enabled
	_external_directional_gravity_axis_speed_ratio_max = clampf(axis_speed_ratio_max,0.05,0.95)
	if not enabled:
		_external_directional_gravity_lateral_sign = 1.0
		_external_directional_gravity_grounded = false
		_external_directional_gravity_last_direction = Vector2.ZERO
		_external_directional_gravity_hop_wait_left = -1.0


func is_external_directional_gravity_locomotion_enabled() -> bool:
	return _external_directional_gravity_locomotion_enabled


func get_external_directional_gravity_axis_speed_ratio_max() -> float:
	return _external_directional_gravity_axis_speed_ratio_max


func _external_directional_gravity_normal_speed_budget() -> float:
	# 用户要求这里使用“当前移动速度数值”本身，而不是实际位移 / delta。
	# 因此直接返回当前 Speed；普通角色公共 0.6 倍实际移动倍率只在最终合速度完成后整体乘一次。
	return maxf(Speed,0.0)


# V190：配置“落地后随机等待再起跳”。
# 时间仍随机；起跳速度直接按 Speed 的 min/max_ratio 线性随机，默认 2.0~4.0 倍。
# 注意：这里只决定起跳瞬间初速度，不改变 apply_external_directional_gravity() 的标准重力积分。
func configure_external_directional_gravity_hop(
	enabled:bool,
	min_interval:float = 0.40,
	max_interval:float = 1.20,
	seed:int = 0,
	min_ratio:float = 2.0,
	max_ratio:float = 4.0
) -> void:
	_external_directional_gravity_hop_enabled = enabled
	_external_directional_gravity_hop_min_interval = maxf(minf(min_interval,max_interval),0.0)
	_external_directional_gravity_hop_max_interval = maxf(maxf(min_interval,max_interval),_external_directional_gravity_hop_min_interval)
	_external_directional_gravity_hop_min_ratio = clampf(minf(min_ratio,max_ratio),0.0,100.0)
	_external_directional_gravity_hop_max_ratio = clampf(
		maxf(min_ratio,max_ratio),
		_external_directional_gravity_hop_min_ratio,
		100.0
	)
	_external_directional_gravity_hop_wait_left = -1.0
	_external_directional_gravity_grounded = false
	if enabled:
		var resolved_seed:int = seed
		if resolved_seed == 0:
			resolved_seed = Game.battle_rng_seed_or(
				"classes/ball.gd:external_directional_gravity_hop:%d" % get_instance_id(),
				maxi(abs(int(Time.get_ticks_usec()) ^ int(get_instance_id())),1)
			)
		_external_directional_gravity_hop_rng.seed = resolved_seed


func is_external_directional_gravity_hop_enabled() -> bool:
	return _external_directional_gravity_hop_enabled


# 旧 V181-V184 名称保留成兼容壳。V190 继续把两个 ratio 作为起跳速度比例范围，
# 但不恢复旧版每帧勾股/平方重写速度的运动方式。
func configure_external_directional_gravity_bounce(
	enabled:bool,
	_min_ratio:float = 2.0,
	_max_ratio:float = 4.0,
	seed:int = 0
) -> void:
	configure_external_directional_gravity_hop(enabled,0.40,1.20,seed,_min_ratio,_max_ratio)


func is_external_directional_gravity_bounce_enabled() -> bool:
	return _external_directional_gravity_hop_enabled


func _schedule_external_directional_gravity_hop() -> void:
	_external_directional_gravity_hop_wait_left = _external_directional_gravity_hop_rng.randf_range(
		_external_directional_gravity_hop_min_interval,
		_external_directional_gravity_hop_max_interval
	)


# 处理任意方向重力下的“地面/天花板/左右墙”。ball 全局使用 FLOATING 模式，
# 因此不能依赖 is_on_floor()；这里直接用碰撞法线与当前重力方向的点积分类。
func _process_external_directional_gravity_locomotion_collisions() -> void:
	if not _external_directional_gravity_locomotion_enabled:
		return
	var gravity:Vector2 = get_external_directional_gravity()
	if gravity.length_squared() <= 0.000001:
		return
	var gravity_dir:Vector2 = gravity.normalized()
	var tangent:Vector2 = gravity_dir.orthogonal().normalized()
	var incoming:Vector2 = _last_requested_velocity
	var landed_this_frame:bool = false

	for index:int in range(get_slide_collision_count()):
		var collision:KinematicCollision2D = get_slide_collision(index)
		if collision == null:
			continue
		var collider:Variant = collision.get_collider()
		var normal:Vector2 = collision.get_normal().normalized()
		var floor_alignment:float = normal.dot(-gravity_dir)
		var ceiling_alignment:float = normal.dot(gravity_dir)
		var side_alignment:float = absf(normal.dot(tangent))

		# V187：起跳弹力只是一发反重力方向的初速度。只要这一发弹力真正“顶到”
		# 任意会阻挡它的碰撞体，就必须在本次碰撞帧立刻消失，不能让独立外力变量
		# 下一帧又把角色继续往障碍里推。这里不只认正天花板；斜面、障碍、其它人物
		# 只要碰撞法线对重力方向有正分量，就说明反重力弹力正撞进该表面。
		var bounce_axis_speed:float = _external_directional_gravity_velocity.dot(gravity_dir)
		if bounce_axis_speed < 0.0 and ceiling_alignment > 0.01:
			_external_directional_gravity_velocity -= gravity_dir * bounce_axis_speed

		# 人物互撞不能算“地面/侧墙”，不应该触发落地计时或左右掉头；
		# 但上面的起跳冲量清零仍然生效，因为人物如果真的挡住上冲，也算“顶到东西”。
		if collider is ball:
			continue

		if floor_alignment > 0.55:
			# 落地时只清掉“朝重力方向”的速度；横向速度由 locomotion 单独维护。
			var axis_speed:float = _external_directional_gravity_velocity.dot(gravity_dir)
			if axis_speed > 0.0:
				_external_directional_gravity_velocity -= gravity_dir * axis_speed
			landed_this_frame = true
		elif ceiling_alignment > 0.55:
			# V187：反重力弹力已经在上面的“任何顶撞表面”分支即时清零。
			# 这里保留分类分支，只负责阻止该碰撞被误当成左右侧墙反向。
			pass
		elif side_alignment > 0.55:
			# 沿“地面”左右移动碰到侧墙时反向。只在确实朝墙移动时掉头，避免角落抖动。
			var lateral_incoming:float = incoming.dot(tangent)
			if lateral_incoming * normal.dot(tangent) < -0.01:
				_external_directional_gravity_lateral_sign *= -1.0

	if landed_this_frame:
		if not _external_directional_gravity_grounded:
			_external_directional_gravity_grounded = true
			if _external_directional_gravity_hop_enabled:
				_schedule_external_directional_gravity_hop()


func _is_projectile_motion_object() -> bool:
	if _projectile_motion_object_cache_valid:
		return _projectile_motion_object_cache
	var result:bool = Type == Ball_Type.Shooter or Type == Ball_Type.Shooter_with_Health
	if not result:
		var script_value:Variant = get_script()
		if script_value is Script:
			var script_path:String = (script_value as Script).resource_path
			result = (
				script_path.begins_with("res://scripts/shooter/")
				or script_path == "res://scripts/training/speedster_training_projectile.gd"
			)
	_projectile_motion_object_cache = result
	_projectile_motion_object_cache_valid = true
	return result


func _compose_external_directional_gravity_locomotion(
	effective_direction:Vector2,
	normal_speed_value:float,
	actual_move_speed:float,
	repel:Vector2
) -> Vector2:
	if not _external_directional_gravity_locomotion_enabled:
		return effective_direction * actual_move_speed + repel + _crowd_separation_velocity
	var gravity:Vector2 = get_external_directional_gravity()
	if gravity.length_squared() <= 0.000001:
		return effective_direction * actual_move_speed + repel + _crowd_separation_velocity

	var gravity_dir:Vector2 = gravity.normalized()
	var tangent:Vector2 = gravity_dir.orthogonal().normalized()
	var projected_input:float = effective_direction.dot(tangent)
	if absf(projected_input) > 0.0001:
		_external_directional_gravity_lateral_sign = 1.0 if projected_input > 0.0 else -1.0

	# V185：横向就是角色自己的正常移动速度；重力轴完全来自连续积分后的外部重力速度。
	# 两条轴不再互相做勾股预算，也不再平方/除 10，因此不会每帧把跳跃曲线硬掰成新速度。
	var lateral_velocity:Vector2 = Vector2.ZERO
	if normal_speed_value > 0.0:
		lateral_velocity = tangent * _external_directional_gravity_lateral_sign * actual_move_speed
	var non_gravity_repel:Vector2 = repel - _external_directional_gravity_velocity
	return lateral_velocity + _external_directional_gravity_velocity + non_gravity_repel + _crowd_separation_velocity


func apply_external_directional_gravity(delta:float) -> void:
	if delta <= 0.0:
		return
	var gravity_accel:Vector2 = get_external_directional_gravity()
	var has_gravity:bool = gravity_accel.length_squared() > 0.000001
	var has_inertia:bool = _external_directional_gravity_velocity.length_squared() > 0.000001
	if not has_gravity and not has_inertia:
		return

	var terminal_multiplier:float = 1.0
	if has_gravity and _is_projectile_motion_object():
		gravity_accel *= 7.0
		terminal_multiplier = 4.0

	if has_gravity:
		_external_directional_gravity_release_deceleration_override = 0.0
		var gravity_dir:Vector2 = gravity_accel.normalized()
		# 重力方向被 Sans 改写时，旧方向的“落地”状态不能沿用。
		if _external_directional_gravity_locomotion_enabled:
			if (
				_external_directional_gravity_last_direction.length_squared() > 0.000001
				and _external_directional_gravity_last_direction.dot(gravity_dir) < 0.999
			):
				_external_directional_gravity_grounded = false
				_external_directional_gravity_hop_wait_left = -1.0
			_external_directional_gravity_last_direction = gravity_dir

		# Boss 深蓝跳跃：只有落地后等待计时。V190 起跳力度仍为线性随机：
		# jump_speed = Speed * ratio，ratio 默认在 2.0~4.0 之间。
		# 起跳后的每一帧仍然只做标准 gravity_accel * delta，因此重力曲线保持连续。
		var launched_hop:bool = false
		if _external_directional_gravity_locomotion_enabled and _external_directional_gravity_hop_enabled and _external_directional_gravity_grounded:
			if _external_directional_gravity_hop_wait_left < 0.0:
				_schedule_external_directional_gravity_hop()
			_external_directional_gravity_hop_wait_left -= delta
			# 等待期间保持重力轴静止；碰撞帧已经把落地速度清零。
			var axis_speed:float = _external_directional_gravity_velocity.dot(gravity_dir)
			_external_directional_gravity_velocity -= gravity_dir * axis_speed
			if _external_directional_gravity_hop_wait_left <= 0.0:
				var speed_budget:float = _external_directional_gravity_normal_speed_budget()
				var ratio:float = _external_directional_gravity_hop_rng.randf_range(
					_external_directional_gravity_hop_min_ratio,
					_external_directional_gravity_hop_max_ratio
				)
				var jump_speed:float = speed_budget * ratio
				_external_directional_gravity_velocity = -gravity_dir * jump_speed
				_external_directional_gravity_grounded = false
				_external_directional_gravity_hop_wait_left = -1.0
				launched_hop = true

		# 标准重力加速度：空中每个物理帧只做 v += a * delta。
		# 起跳的同一帧不再额外加一次重力，下一帧开始自然减速、到顶、再下落。
		if not launched_hop and not (
			_external_directional_gravity_locomotion_enabled
			and _external_directional_gravity_hop_enabled
			and _external_directional_gravity_grounded
		):
			_external_directional_gravity_velocity += gravity_accel * delta

		var terminal_speed:float = maxf(external_directional_gravity_terminal_speed,0.0) * terminal_multiplier
		if terminal_speed > 0.0:
			if _external_directional_gravity_locomotion_enabled:
				# 标准“下落终速”只限制顺重力方向的速度，不削掉反重力起跳冲量。
				# 因此 V191 的 2.0~4.0×Speed 起跳初速度能完整生效，随后仍由同一个 gravity_accel * delta 自然减速。
				var axis_speed:float = _external_directional_gravity_velocity.dot(gravity_dir)
				if axis_speed > terminal_speed:
					_external_directional_gravity_velocity -= gravity_dir * (axis_speed - terminal_speed)
			elif _external_directional_gravity_velocity.length() > terminal_speed:
				_external_directional_gravity_velocity = _external_directional_gravity_velocity.normalized() * terminal_speed
	else:
		_external_directional_gravity_grounded = false
		_external_directional_gravity_hop_wait_left = -1.0
		_external_directional_gravity_last_direction = Vector2.ZERO
		var release_deceleration:float = maxf(
			external_directional_gravity_release_deceleration,
			_external_directional_gravity_release_deceleration_override
		)
		_external_directional_gravity_velocity = _external_directional_gravity_velocity.move_toward(
			Vector2.ZERO,
			maxf(release_deceleration,0.0) * delta
		)
		if _external_directional_gravity_velocity.length_squared() <= 0.000001:
			_external_directional_gravity_velocity = Vector2.ZERO
			_external_directional_gravity_release_deceleration_override = 0.0

	if _external_directional_gravity_velocity.length_squared() > 0.000001:
		Repel += _external_directional_gravity_velocity


func _update_projectile_facing_from_position_delta(delta:float) -> void:
	if not Projectile_Auto_Face_Motion or not _is_projectile_motion_object():
		return
	if not _projectile_facing_position_initialized:
		_projectile_facing_last_position = global_position
		_projectile_facing_position_initialized = true
		return
	var frame_motion:Vector2 = global_position - _projectile_facing_last_position
	_projectile_facing_last_position = global_position
	_sync_projectile_facing_from_frame_motion(frame_motion,delta)


func _sync_projectile_facing_from_frame_motion(frame_motion:Vector2,delta:float) -> void:
	if not Projectile_Auto_Face_Motion:
		return
	if not _is_projectile_motion_object():
		return
	var motion_velocity:Vector2 = Vector2.ZERO
	if delta > 0.000001 and frame_motion.length_squared() > 0.000001:
		motion_velocity = frame_motion / delta
	var min_speed:float = maxf(Projectile_Facing_Min_Speed,0.0)
	if motion_velocity.length() < min_speed:
		var real_velocity:Vector2 = get_real_velocity()
		if real_velocity.length() >= min_speed:
			motion_velocity = real_velocity
	if motion_velocity.length() < min_speed and velocity.length() >= min_speed:
		motion_velocity = velocity
	if motion_velocity.length() < min_speed and direction.length_squared() > 0.000001 and Speed >= min_speed:
		motion_velocity = direction.normalized() * Speed
	if motion_velocity.length_squared() <= 0.000001:
		return
	# 只改视觉/碰撞根节点朝向，不反写 direction，避免视觉修复反过来改变导弹/弹道逻辑。
	global_rotation = Default_Rotation + motion_velocity.angle()


func wait_for_combat_time(duration:float) -> bool:
	var remaining:float = maxf(duration,0.0)
	var last_usec:int = Time.get_ticks_usec()
	while remaining > 0.0:
		var tree:SceneTree = get_tree()
		if tree == null:
			return false
		await tree.process_frame
		if not is_inside_tree() or health <= 0:
			return false
		var now_usec:int = Time.get_ticks_usec()
		var real_delta:float = clampf(float(now_usec - last_usec) / 1000000.0,0.0,0.25)
		last_usec = now_usec
		if not is_combat_runtime_active():
			continue
		remaining -= real_delta * maxf(Engine.time_scale,0.0)
	return is_combat_runtime_active()

@onready var dizziness:bool = false
var Status_image_tween:Tween

#========================================================
# 可复用眩晕视觉
#
# 不直接监听 dizziness，因为通用击退系统也会临时用 dizziness
# 锁住移动。只有真正进入“眩晕阶段”时才显示星星动画。
#
# 其他角色/技能统一调用 apply_stun(duration) 即可自动获得此特效。
#========================================================
@export_category("眩晕特效")
@export var stun_effect_offset:Vector2 = Vector2(0.0,-55.0)
@export_range(0.01,0.2,0.005) var stun_effect_scale:float = 0.055
@export var stun_effect_z_index:int = 1000

# 眩晕抖动只移动 Graphics 视觉节点，不修改 CharacterBody2D / Hurtbox / Hitbox 的真实位置。
@export var stun_shake_enabled:bool = true
@export_range(0.0,8.0,0.1) var stun_shake_world_strength:float = 2.6
@export_range(4.0,45.0,0.5) var stun_shake_frequency:float = 21.0

var _stun_visual_instance:Node2D = null
var _stun_visual_ref_count:int = 0

# 记录上一次只由眩晕系统添加的 Graphics 局部偏移，结束时可以无损恢复其它角色动画写入的位置。
var _stun_shake_elapsed:float = 0.0
var _stun_shake_last_local_offset:Vector2 = Vector2.ZERO
var _stun_shake_last_applied_position:Vector2 = Vector2.ZERO
var _stun_shake_position_valid:bool = false

func begin_stun_visual() -> void:
	_stun_visual_ref_count += 1
	if _stun_visual_ref_count == 1:
		_show_stun_visual()
		_begin_stun_shake()


func end_stun_visual() -> void:
	if _stun_visual_ref_count <= 0:
		return

	_stun_visual_ref_count -= 1
	if _stun_visual_ref_count == 0:
		_end_stun_shake()
		_remove_stun_visual()


func _show_stun_visual() -> void:
	if not is_inside_tree():
		return
	if _stun_visual_instance != null and is_instance_valid(_stun_visual_instance):
		return

	var visual = STUN_VISUAL_SCENE.instantiate()
	visual.name = "StunVisual"
	visual.setup(self,stun_effect_offset,stun_effect_scale,stun_effect_z_index)
	add_child(visual)
	_stun_visual_instance = visual


func _remove_stun_visual() -> void:
	var visual := _stun_visual_instance
	_stun_visual_instance = null

	if visual != null and is_instance_valid(visual):
		visual.queue_free()


# 功能：开始真正眩晕阶段的角色视觉抖动；记录当前 Graphics 位置，避免覆盖角色自身动画偏移。
func _begin_stun_shake() -> void:
	_stun_shake_elapsed = 0.0
	_stun_shake_last_local_offset = Vector2.ZERO
	_stun_shake_position_valid = false

	if not stun_shake_enabled or graphics == null or not is_instance_valid(graphics):
		return

	_stun_shake_last_applied_position = graphics.position
	_stun_shake_position_valid = true


# 功能：每物理帧更新眩晕抖动；使用两个不同频率的平滑振荡叠加，避免机械地只左右来回。
func _update_stun_shake_visual(delta:float) -> void:
	if _stun_visual_ref_count <= 0 or not stun_shake_enabled:
		if _stun_shake_position_valid:
			_end_stun_shake()
		return
	if graphics == null or not is_instance_valid(graphics):
		_stun_shake_position_valid = false
		_stun_shake_last_local_offset = Vector2.ZERO
		return

	# 多人时只让 authority 写同步中的 Graphics transform；远端直接接收该视觉位置，避免双重抖动。
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return

	if not _stun_shake_position_valid:
		_stun_shake_last_applied_position = graphics.position
		_stun_shake_last_local_offset = Vector2.ZERO
		_stun_shake_position_valid = true

	# 如果角色自己的动画/技能在两帧之间重写了 Graphics.position，就把新位置当作新的基准，
	# 不强行减去旧抖动，避免眩晕效果和人物专属动画争抢同一个属性。
	var externally_changed:bool = (
		graphics.position.distance_squared_to(_stun_shake_last_applied_position) > 0.0004
	)
	var base_position:Vector2
	if externally_changed:
		base_position = graphics.position
		_stun_shake_last_local_offset = Vector2.ZERO
	else:
		base_position = graphics.position - _stun_shake_last_local_offset

	_stun_shake_elapsed += maxf(delta,0.0)
	var frequency:float = maxf(stun_shake_frequency,0.1)
	var phase:float = _stun_shake_elapsed * TAU * frequency

	# 两组非整数倍频率叠加，形成快速不规则颤动；振幅始终被限制在 stun_shake_world_strength 内。
	var x_value:float = sin(phase) * 0.72 + sin(phase * 1.83 + 1.17) * 0.28
	var y_value:float = sin(phase * 1.37 + 2.11) * 0.68 + sin(phase * 2.19 + 0.43) * 0.32
	var world_offset := Vector2(x_value,y_value) * maxf(stun_shake_world_strength,0.0)

	# Graphics.position 是角色根节点的局部坐标；通过 to_local() 把“世界像素抖动量”转换回局部量，
	# 因此不同人物根 scale 下看到的屏幕抖动强度基本一致。
	var local_origin:Vector2 = to_local(global_position)
	var local_target:Vector2 = to_local(global_position + world_offset)
	var local_offset:Vector2 = local_target - local_origin

	graphics.position = base_position + local_offset
	_stun_shake_last_local_offset = local_offset
	_stun_shake_last_applied_position = graphics.position


# 功能：眩晕结束时只撤销本系统最后一次添加的偏移，不破坏角色动画在眩晕期间写入的新 Graphics 位置。
func _end_stun_shake() -> void:
	if graphics != null and is_instance_valid(graphics) and _stun_shake_position_valid:
		var still_our_position:bool = (
			graphics.position.distance_squared_to(_stun_shake_last_applied_position) <= 0.0004
		)
		if still_our_position:
			graphics.position -= _stun_shake_last_local_offset

	_stun_shake_elapsed = 0.0
	_stun_shake_last_local_offset = Vector2.ZERO
	_stun_shake_last_applied_position = Vector2.ZERO
	_stun_shake_position_valid = false


@onready var continue_attack_time:float = 0
@export var continue_attack_cooling:float = 0.5
@export var continue_attacking_delay:float = 3

#========================================================
# 自动残影 V11
#
# Render Mode：
#   Snapshots   = 传统多张快照残影
#   Stretch Only= 不复制快照，只保留一张持续拉长/扭曲的拖尾
#   Both        = 两种效果叠加
#
# Texture Mode：
#   Source Visual = 使用角色/投射物当前贴图
#   Custom Texture= 使用 AfterImage_Custom_Texture
#========================================================
@export_category("自动残影")
@export var AfterImage_Speed:float = -1.0
# 兼容旧场景：Interval 保留，但 V10.1+ 主要按移动距离补帧。
@export var AfterImage_Interval:float = 0.06
@export_range(2.0,30.0,0.5) var AfterImage_Spacing:float = 7.0
@export_range(1,8,1) var AfterImage_Max_Per_Frame:int = 4
@export_range(0.05,1.50,0.01) var AfterImage_Lifetime:float = 0.24

@export_group("残影模式")
@export var AfterImage_Mode:AfterImage_Render_Mode = AfterImage_Render_Mode.Snapshots
@export var AfterImage_Texture_Source:AfterImage_Texture_Mode = AfterImage_Texture_Mode.Source_Visual
@export var AfterImage_Style:AfterImage_Style_Mode = AfterImage_Style_Mode.Soft
@export var AfterImage_Fade:AfterImage_Fade_Mode = AfterImage_Fade_Mode.Smooth
@export var AfterImage_Custom_Texture:Texture2D
@export var AfterImage_Custom_Texture_Match_Source_Size:bool = true
@export var AfterImage_Custom_Texture_Scale:Vector2 = Vector2.ONE

@export_group("投射物残影保护")
# 某些远程角色会在运行时把通用小子弹换成高分辨率贴图。
# 如果残影沿用了旧子弹的缩放，半透明快照可能瞬间铺满屏幕。
# 这里只限制 Shooter / Shooter_with_Health 的残影视觉尺寸，不改变真实子弹、碰撞或人物残影。
@export_range(24.0,256.0,2.0) var AfterImage_Projectile_Max_Visual_Size:float = 88.0

@export_group("快照 - 开头/结尾")
# 旧字段继续作为“开头”参数，保证旧场景数值无需迁移。
@export_range(0.0,1.0,0.01) var AfterImage_Alpha:float = 0.38
@export_range(0.0,1.0,0.01) var AfterImage_End_Alpha:float = 0.0
@export var AfterImage_Tint:Color = Color(0.92,0.97,1.0,1.0)
@export var AfterImage_End_Tint:Color = Color(0.68,0.82,1.0,1.0)
@export var AfterImage_Start_Scale:Vector2 = Vector2.ONE
@export var AfterImage_End_Scale:Vector2 = Vector2(0.88,0.88)
@export_range(0.0,12.0,0.1) var AfterImage_Blur_Pixels:float = 1.8
@export_range(0.0,16.0,0.1) var AfterImage_End_Blur_Pixels:float = 3.0
@export_range(0.0,40.0,0.5) var AfterImage_Smear_Pixels:float = 6.0
@export_range(0.0,40.0,0.5) var AfterImage_End_Smear_Pixels:float = 2.5
@export_range(0.0,24.0,0.25) var AfterImage_Distortion_Pixels:float = 0.0
@export_range(0.0,24.0,0.25) var AfterImage_End_Distortion_Pixels:float = 1.25
@export_range(1,16,1) var AfterImage_Sample_Count:int = 9

@export_group("拉长/扭曲 - 单条模式")
@export_range(20.0,1500.0,10.0) var AfterImage_Stretch_Full_Speed:float = 480.0
@export_range(0.0,260.0,1.0) var AfterImage_Stretch_Length:float = 54.0
@export_range(0.05,2.5,0.01) var AfterImage_Stretch_Head_Width:float = 1.0
@export_range(0.02,2.5,0.01) var AfterImage_Stretch_Tail_Width:float = 0.34
@export_range(0.0,1.0,0.01) var AfterImage_Stretch_Alpha:float = 0.34
@export var AfterImage_Stretch_Head_Color:Color = Color(0.95,0.98,1.0,1.0)
@export var AfterImage_Stretch_Tail_Color:Color = Color(0.42,0.72,1.0,0.55)
@export_range(0.0,24.0,0.25) var AfterImage_Stretch_Distortion_Pixels:float = 3.0
@export_range(1,8,1) var AfterImage_Stretch_Sample_Count:int = 4
@export_range(1.0,40.0,0.5) var AfterImage_Stretch_Response:float = 14.0

@export_group("拉长/扭曲 - 路径像素挤出")
@export var AfterImage_Stretch_Geometry:AfterImage_Stretch_Geometry_Mode = AfterImage_Stretch_Geometry_Mode.Sprite_Warp
@export var AfterImage_Path_Use_Texture:bool = false # false=挤出后沿真实像素；true=整张纹理沿路径拉伸
@export_range(0.1,4.0,0.05) var AfterImage_Path_Width_Multiplier:float = 1.0
@export_range(0.0,12.0,0.25) var AfterImage_Path_Edge_Inset_Pixels:float = 1.5 # 旧场景兼容
@export_range(2.0,64.0,1.0) var AfterImage_Path_Tail_Band_Pixels:float = 18.0
# Alpha 尾帽分析：只在刀尾附近搜索稳定的真实握把截面，不再使用整张 used_rect 包围盒。
@export_range(0.0,1.0,0.01) var AfterImage_Path_Alpha_Threshold:float = 0.08
# V17：沿“移动方向的最前沿”逐扫描线取样。每条扫描线都找自己最前面的非透明像素，
# 再把那个像素沿历史轨迹向后拉长。这样刀头覆盖到的行拉刀头像素，
# 只有握把的行就拉握把最前沿像素，不再退化成一根尾帽线。
@export_range(8,64,1) var AfterImage_Path_Scanline_Samples:int = 32
@export_range(0.0,4.0,0.25) var AfterImage_Path_Leading_Inset_Pixels:float = 0.0
@export_range(0.0,12.0,0.5) var AfterImage_Path_Attach_Overlap_Pixels:float = 2.0
@export var AfterImage_Path_Reverse_Source_Direction:bool = false # 仅反转“取哪一端像素”，不改变真实运动路径
@export_range(0.35,0.95,0.05) var AfterImage_Path_Solid_Width_Ratio:float = 0.70 # 忽略圆角/尖尾的极窄像素，优先取稳定握把宽度
@export_range(0.5,20.0,0.5) var AfterImage_Path_Point_Spacing:float = 3.0
@export_range(4,128,1) var AfterImage_Path_Max_Points:int = 64
@export_range(2,32,1) var AfterImage_Path_Round_Precision:int = 10
@export var AfterImage_Path_Antialiased:bool = true

var _after_image_elapsed:float = 0.0 # 兼容旧保存数据，不再作为主生成计时器
var _after_image_last_transform:Transform2D = Transform2D.IDENTITY
var _after_image_last_transform_valid:bool = false
var _after_image_distance_leftover:float = 0.0
var _after_image_stretch_sprite:Sprite2D = null
const STRETCH_UNIFORM_NAMES:Array[StringName] = [&"source_flip_h",&"head_color",&"tail_color",&"stretch_params",&"alpha_value",&"style_mode",&"sample_count",&"region_params"]
var _stretch_uniform_values:Array = []
var _stretch_uniform_target:int = 0
var _after_image_stretch_intensity:float = 0.0
var _after_image_path_mesh:MeshInstance2D = null
var _after_image_path_array_mesh:ArrayMesh = null
var _after_image_path_points:Array[Vector2] = []
# 可选的“历史路径颜色”。默认角色不使用；特殊角色可覆写 hook，
# 让每个路径采样点记住生成当时的颜色，而不是整条拖尾每帧一起换色。
var _after_image_path_history_colors:Array[Color] = []
# 纹理 Alpha / UV 分析结果跨所有实例共享；避免每把新飞刀重新 texture.get_image()。
static var _shared_after_image_path_visible_uv_cache:Dictionary = {}
# V15：尾部真实握把截面分析在所有 ball 实例之间共享。
# 旧版每把飞刀都逐像素扫描一次，是“每次投刀卡一下”的主要来源之一。
static var _shared_after_image_tail_band_cache:Dictionary = {}
# V17：逐扫描线最前沿像素缓存。相同纹理/Region/局部运动方向只分析一次。
static var _shared_after_image_leading_scanline_cache:Dictionary = {}
# Texture2D.get_image() 会从 GPU 取回一份 Image；所有实例共享一次，避免每把刀重复读取。
static var _shared_after_image_source_image_cache:Dictionary = {}


static func prewarm_after_image_texture(texture:Texture2D) -> void:
	if texture == null:
		return
	var key:String = str(texture.get_rid())
	if _shared_after_image_source_image_cache.has(key):
		return
	var img:Image = texture.get_image()
	if img == null or img.is_empty():
		return
	if img.is_compressed():
		img.decompress()
	_shared_after_image_source_image_cache[key] = img


func _get_cached_after_image_source_image(texture:Texture2D) -> Image:
	if texture == null:
		return null
	var key:String = str(texture.get_rid())
	if not _shared_after_image_source_image_cache.has(key):
		prewarm_after_image_texture(texture)
	return _shared_after_image_source_image_cache.get(key,null) as Image


func _inherit_master_combat_identity() -> void:
	if Master == null or not is_instance_valid(Master):
		return

	if Master_name.is_empty():
		Master_name = str(Master.name)

	# 旧角色大量召唤物/子弹忘记显式复制 Team，仍保留基类默认值 "Ball"。
	# 这会让两个不同阵营的旧投射物/召唤物互相被误判为同队。
	# 对有 Master 的战斗实体，空 Team / 遗留默认 Team 自动继承主人。
	if Team.is_empty() or Team == "Ball":
		Team = Master.Team

	if Target_Enemy == null and Master.Target_Enemy != null and is_instance_valid(Master.Target_Enemy):
		Target_Enemy = Master.Target_Enemy


func _resolve_master_identity_from_name() -> void:
	# Master Node 引用没有放进 MultiplayerSynchronizer；远端实例可能只有 Master_name。
	# 用已经同步的名字重新找到主人，并强制让召唤物的队伍跟随主人，避免 UI/友伤短暂或永久错队。
	if (Master == null or not is_instance_valid(Master)) and not Master_name.is_empty():
		var world := get_tree().current_scene
		if world != null:
			var resolved = world.get_node_or_null(NodePath(Master_name))
			if resolved is ball:
				Master = resolved as ball

	if Master != null and is_instance_valid(Master):
		if Master_name.is_empty():
			Master_name = str(Master.name)
		Team = Master.Team
		if Target_Enemy == null and Master.Target_Enemy != null and is_instance_valid(Master.Target_Enemy):
			Target_Enemy = Master.Target_Enemy


func _resolve_master_identity_with_retry() -> void:
	# MultiplayerSynchronizer 的 spawn 属性通常会在生成时一起到达，但网络帧顺序仍可能让
	# Master_name 比 _ready 稍晚。最多重试 5 帧，确保小寄生虫等召唤物最终拿到主人和队伍。
	for _attempt in range(5):
		if not is_inside_tree():
			return
		_resolve_master_identity_from_name()
		if Master != null and is_instance_valid(Master):
			return
		await get_tree().process_frame


func _normalize_collision_shape_node(collision:CollisionShape2D) -> void:
	if collision == null or collision.shape == null:
		return

	# Godot 官方建议 CollisionShape2D 的 Node2D scale 始终保持 (1,1)。
	# 项目旧场景大量用 scale（甚至负 scale）调整 RectangleShape2D，
	# 将其等价转换到 Shape.size，保留实际尺寸同时去掉不稳定变换。
	if collision.shape is RectangleShape2D:
		var old_shape := collision.shape as RectangleShape2D
		var abs_scale := Vector2(absf(collision.scale.x),absf(collision.scale.y))
		if (
			absf(collision.scale.x - 1.0) > 0.0001
			or absf(collision.scale.y - 1.0) > 0.0001
		):
			var new_shape := RectangleShape2D.new()
			new_shape.size = Vector2(
				maxf(old_shape.size.x * maxf(abs_scale.x,0.0001),0.001),
				maxf(old_shape.size.y * maxf(abs_scale.y,0.0001),0.001)
			)
			# V324：这个函数也可能在“死亡回归”于物理回调后重建角色时被 _ready() 调用。
			# CollisionShape2D.shape 会改动物理服务器中的 shape；Godot 官方要求这类
			# 物理属性变更延迟到当前物理查询结束后执行，否则会出现 flushing queries。
			collision.set_deferred(&"shape",new_shape)
			collision.set_deferred(&"scale",Vector2.ONE)


func _normalize_collision_shapes() -> void:
	_normalize_collision_shape_node(collision_shape_2d)
	if self_hitbox != null:
		_normalize_collision_shape_node(self_hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D)
	if self_hurtbox != null:
		_normalize_collision_shape_node(self_hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D)


#========================================================
# 通用角色侧边信息区
# 左侧 = 敌人相关；右侧 = 自己相关。
# 永久信息排上面，临时信息排下面。
#========================================================
func _ensure_side_status_ui() -> void:
	if not side_status_ui_enabled or Type != Ball_Type.Ball:
		return
	if side_status_ui != null and is_instance_valid(side_status_ui):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var ui := CHARACTER_SIDE_STATUS_UI_SCRIPT.new() as Control
	if ui == null:
		return
	ui.name = "CharacterSideStatus_%s" % str(get_instance_id())
	scene.add_child(ui)
	ui.call("setup",self,side_status_horizontal_gap,side_status_column_width,side_status_font_size)
	side_status_ui = ui


func side_status_set_permanent(side:String,key:String,text_value:String,color:Color = Color.WHITE) -> void:
	_ensure_side_status_ui()
	if side_status_ui != null and is_instance_valid(side_status_ui):
		side_status_ui.call("set_permanent",side,key,text_value,color)


func side_status_remove_permanent(side:String,key:String) -> void:
	if side_status_ui != null and is_instance_valid(side_status_ui):
		side_status_ui.call("remove_permanent",side,key)


func side_status_push_temporary(side:String,text_value:String,color:Color = Color.WHITE,duration:float = 1.25) -> void:
	_ensure_side_status_ui()
	if side_status_ui != null and is_instance_valid(side_status_ui):
		side_status_ui.call("push_temporary",side,text_value,color,duration)


func _is_character_ground_shadow_owner() -> bool:
	# 用户要求“必须是人物，投射物等各种东西不算”。
	# 先按战斗类型排除 Shooter / Shooter_with_Health 等所有非普通角色。
	if Type != Ball_Type.Ball:
		return false

	# 再严格按项目路径识别角色主体。scenes/creatures/ 是召唤物/生物，
	# scenes/shooter/ 是投射物，都不属于本轮“人物”。
	var scene_path:String = scene_file_path
	if scene_path.begins_with("res://scenes/characters/"):
		return true

	# 极少数动态实例 scene_file_path 为空时，用人物脚本目录做保守兜底。
	var own_script:Script = get_script() as Script
	if own_script != null:
		return own_script.resource_path.begins_with("res://scripts/characters/")

	return false


func _character_ground_shadow_bounds() -> Rect2:
	# V254 这里只作为 Alpha 主体采样失败时的兜底。
	# 优先使用人物实体碰撞范围；最终阴影宽度还会再按高度做上限，避免超长手臂/武器把兜底宽度拉爆。
	if (
		collision_shape_2d != null
		and is_instance_valid(collision_shape_2d)
		and collision_shape_2d.shape != null
	):
		var shape_rect:Rect2 = collision_shape_2d.shape.get_rect()
		if shape_rect.size.x > 0.001 and shape_rect.size.y > 0.001:
			var corners:Array[Vector2] = [
				shape_rect.position,
				Vector2(shape_rect.end.x,shape_rect.position.y),
				shape_rect.end,
				Vector2(shape_rect.position.x,shape_rect.end.y),
			]
			var min_point:=Vector2(INF,INF)
			var max_point:=Vector2(-INF,-INF)
			for corner:Vector2 in corners:
				var local_point:Vector2 = collision_shape_2d.transform * corner
				min_point.x = minf(min_point.x,local_point.x)
				min_point.y = minf(min_point.y,local_point.y)
				max_point.x = maxf(max_point.x,local_point.x)
				max_point.y = maxf(max_point.y,local_point.y)
			if max_point.x > min_point.x and max_point.y > min_point.y:
				return Rect2(min_point,max_point-min_point)

	# 没有有效碰撞体时才回退到当前人物视觉矩形。
	if image != null and is_instance_valid(image):
		var visual_rect:Rect2 = _hit_effect_visual_rect()
		if visual_rect.size.x > 0.001 and visual_rect.size.y > 0.001:
			var visual_corners:Array[Vector2] = [
				visual_rect.position,
				Vector2(visual_rect.end.x,visual_rect.position.y),
				visual_rect.end,
				Vector2(visual_rect.position.x,visual_rect.end.y),
			]
			var visual_min:=Vector2(INF,INF)
			var visual_max:=Vector2(-INF,-INF)
			for corner:Vector2 in visual_corners:
				var local_point:Vector2 = to_local(image.to_global(corner))
				visual_min.x = minf(visual_min.x,local_point.x)
				visual_min.y = minf(visual_min.y,local_point.y)
				visual_max.x = maxf(visual_max.x,local_point.x)
				visual_max.y = maxf(visual_max.y,local_point.y)
			if visual_max.x > visual_min.x and visual_max.y > visual_min.y:
				return Rect2(visual_min,visual_max-visual_min)

	return Rect2(Vector2(-70.0,-80.0),Vector2(140.0,160.0))


func _character_ground_shadow_body_metrics() -> Dictionary:
	# V254：从当前人物真实 Alpha 中找“主体核心”，而不是把所有可见像素都算进身体宽度。
	# 思路：在人物大部分高度内按列采样不透明占比。身体/躯干会形成连续的高密度列；
	# 横向伸出的手臂、长武器、飘带等通常只占很少几行，列密度明显更低，因此会自然被过滤。
	if image == null or not is_instance_valid(image):
		return {}

	var visual_rect:Rect2 = _hit_effect_visual_rect()
	var pixel_sampler:RefCounted = _make_visual_pixel_sampler()
	if visual_rect.size.x <= 0.001 or visual_rect.size.y <= 0.001:
		return {}

	var column_count:int = maxi(CHARACTER_GROUND_SHADOW_SAMPLE_COLUMNS,16)
	var row_count:int = maxi(CHARACTER_GROUND_SHADOW_SAMPLE_ROWS,16)
	var core_top:float = visual_rect.position.y + visual_rect.size.y * CHARACTER_GROUND_SHADOW_CORE_TOP_RATIO
	var core_bottom:float = visual_rect.position.y + visual_rect.size.y * CHARACTER_GROUND_SHADOW_CORE_BOTTOM_RATIO
	var core_height:float = maxf(core_bottom-core_top,1.0)
	var densities := PackedFloat32Array()
	densities.resize(column_count)
	var max_density:float = 0.0

	for column_index:int in range(column_count):
		var sample_x:float = visual_rect.position.x + visual_rect.size.x * (float(column_index)+0.5) / float(column_count)
		var opaque_count:int = 0
		for row_index:int in range(row_count):
			var sample_y:float = core_top + core_height * (float(row_index)+0.5) / float(row_count)
			if pixel_sampler.sample(Vector2(sample_x,sample_y)).a >= CHARACTER_GROUND_SHADOW_ALPHA_THRESHOLD:
				opaque_count += 1
		var density:float = float(opaque_count) / float(row_count)
		densities[column_index] = density
		max_density = maxf(max_density,density)

	if max_density <= 0.001:
		return {}

	# 阈值同时有固定下限和“相对最密列”的比例：胖/矮角色不会因统一绝对阈值被误删，
	# 细长的手臂/武器又很难达到主体列的占比。
	var density_threshold:float = maxf(
		CHARACTER_GROUND_SHADOW_CORE_MIN_DENSITY,
		max_density * CHARACTER_GROUND_SHADOW_CORE_RELATIVE_DENSITY
	)

	# 找最长连续高密度列。主体通常是最宽的连续块；孤立的刀、手、枪即使局部不透明也不会赢过主体。
	var best_start:int = -1
	var best_end:int = -1
	var best_length:int = 0
	var run_start:int = -1
	for column_index:int in range(column_count+1):
		var qualifies:bool = (
			column_index < column_count
			and densities[column_index] >= density_threshold
		)
		if qualifies:
			if run_start < 0:
				run_start = column_index
		elif run_start >= 0:
			var run_end:int = column_index-1
			var run_length:int = run_end-run_start+1
			if run_length > best_length:
				best_length = run_length
				best_start = run_start
				best_end = run_end
			run_start = -1

	if best_start < 0 or best_end < best_start or best_length < 3:
		return {}

	var column_step:float = visual_rect.size.x / float(column_count)
	var body_left_x:float = visual_rect.position.x + float(best_start) * column_step
	var body_right_x:float = visual_rect.position.x + float(best_end+1) * column_step
	var body_center_x:float = (body_left_x+body_right_x) * 0.5

	# V255：脚底 Y 不再取 92% 分位，而是从图片最底部逐行向上寻找“最低有效像素行”。
	# 用户要求阴影中心 Y == 图片真实脚底 Y，但一两个孤立像素不能算脚底。
	# 因此每一候选行必须同时满足：
	# 1) 主体核心宽度内的不透明采样点达到最少数量/覆盖率；
	# 2) 至少存在一段连续的不透明采样，排除单像素噪点、细线和孤立武器尖端。
	# 纵向按当前视觉矩形约 1 本地像素一步扫描，尽量贴近原图真正最底的有效像素行。
	var foot_scan_columns:int = maxi(CHARACTER_GROUND_SHADOW_FOOT_SCAN_COLUMNS,24)
	var foot_scan_rows:int = maxi(int(ceil(visual_rect.size.y)),16)
	var minimum_opaque:int = maxi(
		CHARACTER_GROUND_SHADOW_FOOT_MIN_OPAQUE_SAMPLES,
		int(ceil(float(foot_scan_columns)*CHARACTER_GROUND_SHADOW_FOOT_MIN_ROW_COVERAGE))
	)
	var minimum_contiguous:int = maxi(CHARACTER_GROUND_SHADOW_FOOT_MIN_CONTIGUOUS_SAMPLES,2)
	var foot_y:float = 0.0
	var found_foot:bool = false

	for bottom_row_index:int in range(foot_scan_rows):
		var sample_y:float = visual_rect.end.y - visual_rect.size.y * (float(bottom_row_index)+0.5) / float(foot_scan_rows)
		var opaque_count:int = 0
		var current_run:int = 0
		var longest_run:int = 0
		for foot_column_index:int in range(foot_scan_columns):
			var sample_x:float = lerpf(
				body_left_x,
				body_right_x,
				(float(foot_column_index)+0.5)/float(foot_scan_columns)
			)
			if pixel_sampler.sample(Vector2(sample_x,sample_y)).a >= CHARACTER_GROUND_SHADOW_ALPHA_THRESHOLD:
				opaque_count += 1
				current_run += 1
				longest_run = maxi(longest_run,current_run)
			else:
				current_run = 0

		if opaque_count >= minimum_opaque and longest_run >= minimum_contiguous:
			foot_y = sample_y
			found_foot = true
			break

	if not found_foot:
		return {}

	var left_root:Vector2 = to_local(image.to_global(Vector2(body_left_x,foot_y)))
	var right_root:Vector2 = to_local(image.to_global(Vector2(body_right_x,foot_y)))
	var foot_root:Vector2 = to_local(image.to_global(Vector2(body_center_x,foot_y)))
	var body_width:float = left_root.distance_to(right_root)
	if body_width <= 0.001:
		return {}

	return {
		"body_width": body_width,
		"foot_point": foot_root,
		"density_threshold": density_threshold,
		"core_columns": best_length,
	}


func _character_ground_shadow_fallback_metrics() -> Dictionary:
	var bounds:Rect2 = _character_ground_shadow_bounds()
	# 即使回退到碰撞框，也把宽度限制为“身高的一定比例”，避免横向伸手/长武器把影子拉成超宽椭圆。
	var body_width:float = minf(bounds.size.x,bounds.size.y*0.78)
	body_width = maxf(body_width,CHARACTER_GROUND_SHADOW_MIN_WIDTH)
	return {
		"body_width": body_width,
		"foot_point": Vector2(bounds.get_center().x,bounds.end.y),
	}


func _make_character_ground_shadow_polygon(
	radius_x:float,
	radius_y:float,
	color:Color
) -> Polygon2D:
	var polygon := Polygon2D.new()
	var points := PackedVector2Array()
	var segment_count:int = maxi(CHARACTER_GROUND_SHADOW_SEGMENTS,12)
	for index:int in range(segment_count):
		var angle:float = TAU * float(index) / float(segment_count)
		points.append(Vector2(cos(angle) * radius_x,sin(angle) * radius_y))
	polygon.polygon = points
	polygon.color = color
	polygon.antialiased = true
	return polygon


func _setup_character_ground_shadow() -> void:
	if not _is_character_ground_shadow_owner():
		return
	if _character_ground_shadow != null and is_instance_valid(_character_ground_shadow):
		return

	var metrics:Dictionary = _character_ground_shadow_body_metrics()
	if metrics.is_empty():
		metrics = _character_ground_shadow_fallback_metrics()

	var body_width:float = float(metrics.get("body_width",CHARACTER_GROUND_SHADOW_MIN_WIDTH))
	var foot_point:Vector2 = metrics.get("foot_point",Vector2.ZERO)
	var shadow_width:float = clampf(
		body_width * CHARACTER_GROUND_SHADOW_WIDTH_RATIO,
		CHARACTER_GROUND_SHADOW_MIN_WIDTH,
		CHARACTER_GROUND_SHADOW_MAX_WIDTH
	)
	var shadow_height:float = clampf(
		shadow_width * CHARACTER_GROUND_SHADOW_HEIGHT_FROM_WIDTH,
		CHARACTER_GROUND_SHADOW_MIN_HEIGHT,
		CHARACTER_GROUND_SHADOW_MAX_HEIGHT
	)
	# V255：阴影椭圆的 Y 轴中心必须与“最低有效脚底像素行”完全一致。
	# 不再做 V253 的向下偏移，也不再做 V254 的向上压入；只有 Alpha 扫描失败走碰撞回退时才使用回退脚底。
	var shadow_center:=Vector2(foot_point.x,foot_point.y)
	_character_ground_shadow_local_radius = Vector2(shadow_width * 0.5,shadow_height * 0.5)

	var holder := Node2D.new()
	holder.name = "CharacterGroundShadow"
	holder.position = shadow_center
	holder.rotation = 0.0
	holder.scale = Vector2.ONE
	holder.z_index = 0
	holder.z_as_relative = true
	holder.show_behind_parent = true

	# 两层半透明椭圆叠加出轻微软边；不使用图片资源，也不产生碰撞/监测。
	var outer := _make_character_ground_shadow_polygon(
		shadow_width * 0.5,
		shadow_height * 0.5,
		Color(0.0,0.0,0.0,CHARACTER_GROUND_SHADOW_OUTER_ALPHA)
	)
	outer.name = "Outer"
	holder.add_child(outer)

	var inner := _make_character_ground_shadow_polygon(
		shadow_width * 0.37,
		shadow_height * 0.31,
		Color(0.0,0.0,0.0,CHARACTER_GROUND_SHADOW_INNER_ALPHA)
	)
	inner.name = "Inner"
	holder.add_child(inner)

	add_child(holder)
	# 与 Graphics 保持同一最终 Z，只依靠同 Z 的树顺序画在 Graphics/Image 前面。
	# 这样阴影在人物脚下，但不会因为负 Z 掉到地图地板后面。
	move_child(holder,0)
	_character_ground_shadow = holder


func refresh_character_ground_shadow() -> void:
	# V277：AutoFit 或运行时换图后重新读取 Alpha 脚底，避免阴影停在旧图片位置。
	if not _is_character_ground_shadow_owner():
		return
	if _character_ground_shadow != null and is_instance_valid(_character_ground_shadow):
		_character_ground_shadow.queue_free()
	_character_ground_shadow = null
	_character_ground_shadow_local_radius = Vector2.ZERO
	call_deferred("_setup_character_ground_shadow")


func get_character_ground_shadow_ring_data(extra_margin_world:float = 3.0) -> Dictionary:
	# 多人控制圈直接围绕实际脚底影子，不再另算一个可能错位的碰撞圆。
	if _character_ground_shadow == null or not is_instance_valid(_character_ground_shadow):
		_setup_character_ground_shadow()
	if _character_ground_shadow == null or not is_instance_valid(_character_ground_shadow):
		return {}
	var world_scale:Vector2 = _character_ground_shadow.global_scale.abs()
	var margin:float = maxf(extra_margin_world,0.0)
	var radii_world := Vector2(
		_character_ground_shadow_local_radius.x * maxf(world_scale.x,0.0001) + margin,
		_character_ground_shadow_local_radius.y * maxf(world_scale.y,0.0001) + margin
	)
	return {
		"center": _character_ground_shadow.global_position,
		"radii": Vector2(maxf(radii_world.x,4.0),maxf(radii_world.y,4.0)),
	}


func _validate_combat_areas() -> void:
	# Area2D 只有 layer/mask 匹配且目标可 monitor 时才会报告重叠。
	# 正常人物统一保证 Hurtbox 在角色受击层 2；所有攻击 Hitbox 至少扫描层 2。
	if self_hurtbox != null:
		# V410 性能：Hurtbox 只需要“被 Hitbox 监测”，自身从不读取 overlapping_* / area_entered。
		# 因此保留 monitorable=true，但关闭 monitoring，避免 50+ 人时每只 Hurtbox 都主动参与重叠监听。
		# 延迟写入继续规避 PhysicsServer2D 正在 flush query 时修改 Area 状态。
		self_hurtbox.set_deferred(&"monitorable",true)
		self_hurtbox.set_deferred(&"monitoring",false)
		self_hurtbox.input_pickable = false
		if Type == Ball_Type.Ball:
			self_hurtbox.set_collision_layer_value(2,true)

	if self_hitbox != null:
		self_hitbox.set_collision_mask_value(2,true)
		if Type != Ball_Type.Ball or Has_Collision_Damage:
			self_hitbox.set_deferred(&"monitoring",true)


func _ready() -> void:
	# 大规模战斗切换前先记住场景原本的 collision_mask / max_slides，退出模式时原样恢复。
	_large_battle_original_collision_mask = collision_mask
	_large_battle_original_max_slides = max_slides
	_large_battle_collision_state_captured = true

	# 俯视角角色统一使用 Floating 模式，避免被 CharacterBody2D 的
	# floor / moving-platform 规则当成“站在其他角色上”并继承速度。
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	platform_floor_layers = 0
	platform_wall_layers = 0
	platform_on_leave = CharacterBody2D.PLATFORM_ON_LEAVE_DO_NOTHING

	_inherit_master_combat_identity()
	# 远端生成时 Master 可能尚未解析，入树后再补一次。
	call_deferred("_resolve_master_identity_with_retry")
	_normalize_collision_shapes()
	_validate_combat_areas()

	var tree = get_tree()
	if tree != null and tree.current_scene is World:
		_cached_world = tree.current_scene as World
	set_image_node_type()
	# 子类通常会在 super._ready() 之后替换正式人物贴图（例如盾狗），
	# 因此阴影延迟到本轮 ready 全部结束后再按最终角色尺寸建立。
	call_deferred("_setup_character_ground_shadow")
	# V410：MotionBlurLayer 改为真正懒创建；只有模糊强度实际可见时才分配 Sprite2D/ShaderMaterial。
	_migrate_native_flip_to_shader()
	_capture_collision_visual_base()
	
	if max_energy > 0 and health_bar != null:
		health_bar.show_energy_bar()
	
	#layer to delete balls which cant be hurt
	self_hurtbox.set_collision_layer_value(4,true)

	# 没有本体碰撞伤害的正常角色，不让自己的身体 Hitbox 自动监听 Hurtbox 重叠。
	# 这样只是取消“贴身/撞上就自动扣血”，CharacterBody2D 的实体碰撞仍然存在。
	# 主动技能仍可直接调用 try_hit_hurtbox()，因此不会影响决斗者刺击、猫抓挠等。
	if Type == Ball_Type.Ball and not Has_Collision_Damage and self_hitbox:
		self_hitbox.monitoring = false
	
	add_to_group("Ball")
	# V106：让 World 用事件注册维护战斗单位列表，避免每个 physics tick get_nodes_in_group()。
	if _cached_world != null and is_instance_valid(_cached_world):
		_cached_world.register_battle_unit(self)
	# 用 Node 自己的 tree_exiting signal，而不是依赖虚函数 _exit_tree()。
	# 很多角色脚本覆写了 _exit_tree 且不会调用 super；signal 能保证基类注销仍执行。
	if not tree_exiting.is_connected(_on_ball_tree_exiting):
		tree_exiting.connect(_on_ball_tree_exiting,CONNECT_ONE_SHOT)
	_setup_special_character_threat_overlay()
	set_image_color()
	# 性能：侧边状态 UI 改为真正懒加载。
	# 只有 side_status_set_permanent()/push_temporary() 第一次被调用时才创建，
	# 普通无状态角色不再白白生成一整套 VBox/Label 容器。
	if Type == Ball_Type.Ball:
		var initial_flip_h:bool = false
		if direction.length_squared() > MOTION_EPSILON_SQ:
			initial_flip_h = (direction.x > 0.0) if dir_left else (direction.x <= 0.0)
		set_character_visual_flip_h(initial_flip_h)
		_motion_visual_last_position = global_position
		_motion_visual_initialized = true
		_set_motion_shader_values(Vector2.RIGHT,0.0)
	
	health_restore_timer.timeout.connect(func():
		# 训练模式 V2 不改变角色自己的回血规则。
		if can_restore_health and not state_machine.current_state == State.Die:
			health += Health_Restore
	)

	# 训练场会在角色生成前打开 Game.Training_Mode；V2 只登记训练状态，
	# 不再修改 Max_health / health，人物仍按原规则受伤与死亡。
	if Game.is_training_mode():
		apply_training_mode(true)
	
	for s in State:
		state_machine.last_state_dis[s] = 0.0
		
	if Type == Ball_Type.Shooter:
		set_collision_layer_value(1,false)
		set_collision_layer_value(2,false)
		set_collision_layer_value(3,true)
		
		self_hurtbox.set_collision_layer_value(3,true)
	elif Type == Ball_Type.Ball:
		pass
		#set_collision_layer_value(1,true)
		#set_collision_layer_value(2,true)
		#set_collision_mask_value(2,true)
		#set_collision_mask_value(2,true)

	# 极少数角色若在入树前就已经进入眩晕，补建一次视觉节点。
	if _stun_visual_ref_count > 0:
		_show_stun_visual()
		_begin_stun_shake()

	# V79 单人性能修复：单机（无 multiplayer peer）时立即禁用 MultiplayerSynchronizer。
	# 原有逻辑只在进入大规模战斗模式时才禁用 Synchronizer，导致 64 单位以下的单人
	# 对局中每个角色的 Synchronizer 始终以 PROCESS_MODE_INHERIT 运行，
	# 每帧白白处理 41 个属性的脏检测，造成不必要的 CPU 开销。
	# 多人时保持 INHERIT，由大规模战斗模式按需调整。
	_apply_singleplayer_synchronizer_optimization()

func _on_ball_tree_exiting() -> void:
	# V106：通过 tree_exiting signal 主动从 World 注册表移除。
	if _cached_world != null and is_instance_valid(_cached_world):
		_cached_world.unregister_battle_unit(self)


# ========================================================
# 可复用目标辅助
# ========================================================
# 通用“能否作为战斗攻击目标”契约。
# 普通角色默认可被攻击；Creature 默认不可被攻击，只有建筑工人墙等明确覆写
# is_combat_targetable() 的实体才进入索敌/直接攻击逻辑。这样不会把宠物、纯视觉召唤物
# 一并当成敌人，同时让特殊建筑能被所有遵守公共契约的攻击正常选中。
func is_combat_targetable() -> bool:
	# V194：地图外演出来客等单位可以显式退出公共索敌契约。
	# 使用 metadata 而不是改 Type/Team，避免破坏它们自己 Attack()、投射物 Master 和阵营伤害逻辑。
	if has_meta(&"ignore_combat_targeting") and bool(get_meta(&"ignore_combat_targeting")):
		return false
	if health <= 0 or is_queued_for_deletion():
		return false
	if Type != Ball_Type.Ball:
		return false
	if state_machine != null and state_machine.current_state == State.Die:
		return false
	return true


# V88：把“能不能被攻击命中”和“能不能被 AI 锁定”拆成两个契约。
# is_combat_targetable() 继续表示实体可作为合法伤害对象；隐身等效果只通过
# ignore_combat_locking 退出 AI 锁定，因此已经飞来的投射物、范围伤害、Hitbox/Hurtbox
# 仍能正常命中，不会因为隐身被当成无效伤害目标。
func is_combat_lockable() -> bool:
	if not is_combat_targetable():
		return false
	if has_meta(&"ignore_combat_locking") and bool(get_meta(&"ignore_combat_locking")):
		return false
	return true


func return_nearest_teammate() -> ball:
	if not Can_Target_Teammates:
		return null

	# 空 Team 不视为一个真实队伍，避免未分队角色全部互相当队友。
	if Team == "":
		return null

	var nearest:ball = null
	var nearest_distance_sq:float = INF

	# V411：World 已维护权威战斗单位缓存。这里仍逐个比较“当前真实位置”，
	# 因而最近队友结果完全不变，只是不再为每次查询重新构造 SceneTree group Array。
	var candidates:Array = []
	if _cached_world != null and is_instance_valid(_cached_world):
		candidates = _cached_world.get_battle_units_fast()
	else:
		candidates = get_tree().get_nodes_in_group("Ball")

	for node:Node in candidates:
		if not node is ball:
			continue

		var candidate:ball = node

		if candidate == self:
			continue

		# 队友锁定只面向真正角色，不把子弹/召唤物误当队友目标。
		if candidate.Type != Ball_Type.Ball:
			continue

		if candidate.Team == "" or candidate.Team != Team:
			continue

		if candidate.health <= 0:
			continue

		if (
			candidate.state_machine
			and candidate.state_machine.current_state == State.Die
		):
			continue

		var distance_sq:float = global_position.distance_squared_to(
			candidate.global_position
		)

		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest = candidate

	return nearest


# 给所有锁定类攻击使用的“目标点”接口。
# 默认角色直接返回自己的真实位置；特殊角色可以覆写 get_combat_lock_position()
# 来提供一个滞后/诱饵位置。攻击者调用 combat_target_position() 后，
# 不需要知道目标是否有特殊锁定机制。
func get_combat_lock_position() -> Vector2:
	return global_position


func get_combat_lock_velocity() -> Vector2:
	if velocity.length_squared() > 0.000001:
		return velocity
	if direction.length_squared() > 0.000001:
		return direction.normalized() * maxf(Speed,0.0)
	return Vector2.ZERO


func combat_target_position(target:Node) -> Vector2:
	# V130：控制模式下，任何“用目标位置决定攻击朝向”的旧角色统一改读鼠标世界坐标。
	# 仍保留真实 target 对象给阵营/伤害/状态逻辑使用，但绝不能让它把方向重新吸回敌人。
	if has_player_control_aim():
		return player_control_aim_position
	if target == null or not is_instance_valid(target):
		return global_position
	if target.has_method("get_combat_lock_position"):
		var resolved:Variant = target.call("get_combat_lock_position")
		if resolved is Vector2:
			return resolved
	if target is Node2D:
		return (target as Node2D).global_position
	return global_position


func combat_target_velocity(target:Node) -> Vector2:
	# 手动瞄准点不是一个会移动的敌人；控制时禁止旧“预判目标速度”再次改变鼠标方向。
	if has_player_control_aim():
		return Vector2.ZERO
	if target == null or not is_instance_valid(target):
		return Vector2.ZERO
	if target.has_method("get_combat_lock_velocity"):
		var resolved:Variant = target.call("get_combat_lock_velocity")
		if resolved is Vector2:
			return resolved
	if target is ball:
		var target_ball:ball = target as ball
		if target_ball.velocity.length_squared() > 0.000001:
			return target_ball.velocity
		if target_ball.direction.length_squared() > 0.000001:
			return target_ball.direction.normalized() * maxf(target_ball.Speed,0.0)
	return Vector2.ZERO


# 给需要“敌人/队友都可能成为目标”的角色调用。
#
# 规则：
# 1. 显式 Target_Enemy 仍然优先。
# 2. Prefer_Teammates=true：有队友时优先最近队友。
# 3. Can_Target_Teammates=true 且 Prefer_Teammates=false：
#    比较最近队友与最近敌人的实际距离，谁近就返回谁。
# 4. 没有队友时退回最近敌人；没有敌人时退回最近队友。
func return_reusable_combat_target() -> Node:
	if is_instance_valid(Target_Enemy):
		# V88：显式目标必须满足“可锁定”契约；隐身者仍可受伤，但不能继续作为 AI 锁定目标。
		if Target_Enemy.has_method("is_combat_lockable") and not bool(Target_Enemy.call("is_combat_lockable")):
			Target_Enemy = null
		elif Target_Enemy.has_method("is_combat_targetable") and not bool(Target_Enemy.call("is_combat_targetable")):
			Target_Enemy = null
		else:
			return Target_Enemy

	var teammate:ball = null
	if Can_Target_Teammates:
		teammate = return_nearest_teammate()

	var enemy:ball = null
	if (
		is_instance_valid(Nearest_Enemy)
		and Nearest_Enemy is ball
		and (Nearest_Enemy as ball).is_combat_lockable()
	):
		enemy = Nearest_Enemy as ball

	if (
		Prefer_Teammates
		and is_instance_valid(teammate)
	):
		return teammate

	if (
		Can_Target_Teammates
		and not Prefer_Teammates
		and is_instance_valid(teammate)
		and is_instance_valid(enemy)
	):
		var teammate_distance_sq:float = (
			global_position.distance_squared_to(
				teammate.global_position
			)
		)
		var enemy_distance_sq:float = (
			global_position.distance_squared_to(
				enemy.global_position
			)
		)

		if teammate_distance_sq <= enemy_distance_sq:
			return teammate
		return enemy

	if is_instance_valid(enemy):
		return enemy

	if is_instance_valid(teammate):
		return teammate

	return null


# ========================================================
# 通用人物独特音频接口
# ========================================================
func _unique_audio_stream(slot:int) -> AudioStream:
	match slot:
		Character_Audio_Slot.Attack:
			return Unique_Attack_Audio
		Character_Audio_Slot.Hit:
			return Unique_Hit_Audio
		Character_Audio_Slot.Hurt:
			return Unique_Hurt_Audio
		Character_Audio_Slot.Skill:
			return Unique_Skill_Audio
		Character_Audio_Slot.Collide:
			return Unique_Collide_Audio
		Character_Audio_Slot.Death:
			return Unique_Death_Audio
		Character_Audio_Slot.Block:
			return Unique_Block_Audio
		Character_Audio_Slot.BlockBreak:
			return Unique_Block_Break_Audio
	return null


func _play_unique_audio_local(slot:int,randomize_pitch:bool = true) -> void:
	var stream:AudioStream = _unique_audio_stream(slot)
	if stream == null:
		return

	var player := AudioStreamPlayer2D.new()
	player.name = "UniqueCharacterAudio"
	player.stream = stream
	player.volume_db = Unique_Audio_Volume_DB
	player.pitch_scale = maxf(Unique_Audio_Pitch_Scale,0.01)

	if randomize_pitch:
		var pitch_random:float = clampf(Unique_Audio_Random_Pitch,0.0,0.25)
		player.pitch_scale *= randf_range(1.0 - pitch_random,1.0 + pitch_random)

	player.max_distance = maxf(Unique_Audio_Max_Distance,50.0)
	player.attenuation = 1.0
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"

	add_child(player)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func play_unique_audio(slot:int,randomize_pitch:bool = true) -> void:
	_play_unique_audio_local(slot,randomize_pitch)
	if multiplayer.has_multiplayer_peer():
		_remote_play_unique_audio.rpc(slot,randomize_pitch)


@rpc("any_peer","call_remote","unreliable")
func _remote_play_unique_audio(slot:int,randomize_pitch:bool = true) -> void:
	_play_unique_audio_local(slot,randomize_pitch)


# V275：公共中毒视觉。只改 Image 自己的 self_modulate，不染血条/名字/状态 UI。
func _update_poison_visual() -> void:
	if image == null or not is_instance_valid(image) or not (image is CanvasItem):
		_poison_visual_initialized = false
		return

	var canvas:CanvasItem = image as CanvasItem
	var current_modulate:Color = canvas.self_modulate
	if not _poison_visual_initialized:
		_poison_visual_base_self_modulate = current_modulate
		_poison_visual_last_applied_self_modulate = current_modulate
		_poison_visual_initialized = true
	elif not _color_approx_equal(current_modulate,_poison_visual_last_applied_self_modulate):
		# 外部角色逻辑刚刚改色：把它当作新的“未中毒”基线，再叠绿色。
		_poison_visual_base_self_modulate = current_modulate

	var poison_amount:float = _current_poison_visual_amount()
	var stack_equivalent:float = poison_amount / maxf(POISON_VISUAL_REFERENCE_AMOUNT_PER_STACK,0.001)
	var intensity:float = 0.0
	if stack_equivalent > 0.0:
		# 一层约14%：只微微暗绿；继续叠层时逐渐更深绿并自然饱和。
		intensity = clampf(1.0 - pow(POISON_VISUAL_STACK_DECAY,stack_equivalent),0.0,1.0)

	var poison_tint:Color = Color.WHITE.lerp(POISON_VISUAL_FULL_TINT,intensity)
	var applied:Color = _poison_visual_base_self_modulate * poison_tint
	applied.a = _poison_visual_base_self_modulate.a
	# 不把完全相同的颜色每个物理帧重复写回 RenderingServer。
	if not _color_approx_equal(canvas.self_modulate,applied):
		canvas.self_modulate = applied
	_poison_visual_last_applied_self_modulate = applied


func _current_poison_visual_amount() -> float:
	if Buff_Dic.is_empty():
		return 0.0
	var total:float = 0.0
	for raw_from:Variant in Buff_Dic.keys():
		var source_buffs:Dictionary = Buff_Dic[raw_from]
		for raw_name:Variant in source_buffs.keys():
			var poison_buff:Buff = source_buffs[raw_name]
			if poison_buff.buff_type != Buff.Buff_types.poison or poison_buff.duration <= 0.0:
				continue
			total += maxf(float(poison_buff.amount),0.0)
	return total


func _color_approx_equal(a:Color,b:Color,epsilon:float = 0.001) -> bool:
	return (
		absf(a.r - b.r) <= epsilon
		and absf(a.g - b.g) <= epsilon
		and absf(a.b - b.b) <= epsilon
		and absf(a.a - b.a) <= epsilon
	)


#颜色
func set_image_color() -> void:
	image.set_instance_shader_parameter("default_color",image_color)
	image.set_instance_shader_parameter("defualt_color_mix",image_color_mix)
#状态相关
func transition_state(from:State,to:State) -> void:
	if not is_multiplayer_authority():return
	if from == to:return
	if to != State.Hurt:hurting_timer.stop()
	state_machine.last_state_dis[State.keys()[to]] = 0
	
	match to:
		State.Attack:
			play_unique_audio(Character_Audio_Slot.Attack)
			Attack()
		State.Skill:
			play_unique_audio(Character_Audio_Slot.Skill)
			Skill()
		State.Die:
			_report_combat_death_once()
			if Type != Ball_Type.Creature:
				set_physics_process(false)
			
				set_collision_layer_value(1,false)
				set_collision_layer_value(2,false)
				set_collision_layer_value(3,false)
				set_collision_mask_value(1,false)
				set_collision_mask_value(2,false)
				set_collision_mask_value(3,false)

				# V9：普通人物死亡统一立即离场。
				#
				# 旧版尝试用 get_script_method_list() 判断子类有没有自定义 Die()，
				# 但继承脚本的方法列表会让普通子类也可能被误判成“特殊死亡”，
				# 结果就是 0HP 后永久停在 Die 状态。
				#
				# 现在先调用 Die()，让角色自己的同步清理（关门、清随从、停止音效等）
				# 正常执行；只要是正常人物且没有明确死亡动画，本帧末就直接释放。
				# 猫/重女这类 0HP 复活或二阶段角色会在 get_next_state() 里先把生命恢复，
				# 根本不会进入这里，因此不会被误删。
				var has_death_animation:bool = _has_death_animation()
				Die()
				if (
					Type == Ball_Type.Ball
					and not has_death_animation
					and is_inside_tree()
					and not is_queued_for_deletion()
				):
					queue_free()
	pass
func _has_custom_death_handler() -> bool:
	# get_script_method_list() 返回当前 Script 定义的方法。沿脚本继承链向上检查，
	# 直到公共 ball.gd；只要某一层自己实现了 Die()，就把死亡交给它处理。
	var current_script:Script = get_script() as Script
	while current_script != null:
		if current_script.resource_path == "res://classes/ball.gd":
			break
		for method_info:Dictionary in current_script.get_script_method_list():
			if StringName(method_info.get("name",&"")) == &"Die":
				return true
		current_script = current_script.get_base_script()
	return false


func _has_death_animation() -> bool:
	# 有明确死亡动画的角色继续保留在场景树中，由角色自己的动画/关键帧处理删除。
	if animation_player != null:
		for animation_name:StringName in animation_player.get_animation_list():
			var key:String = String(animation_name).to_lower()
			if key == "die" or key == "death" or key == "dead" or "死亡" in key:
				return true
	if image is AnimatedSprite2D:
		var animated_image:AnimatedSprite2D = image as AnimatedSprite2D
		if animated_image.sprite_frames != null:
			for animation_name:StringName in animated_image.sprite_frames.get_animation_names():
				var key:String = String(animation_name).to_lower()
				if key == "die" or key == "death" or key == "dead" or "死亡" in key:
					return true
	return false


func get_next_state(state:State) -> int:
	if not is_multiplayer_authority():return -1
	if health <= 0 and Type != Ball_Type.Creature:
		if state != State.Die:return State.Die
		else:return -1
	if dizziness:return -1
	#if name == "虔诚雕刻师":
		#print(str(state))

	var combat_runtime_active:bool = is_combat_runtime_active()
	var offense_disabled:bool = is_damage_output_disabled()
	if not combat_runtime_active:
		# 布阵/未开战/时间静止阶段不允许累计一个“开局立刻释放”的攻击或技能冷却。
		Attacking = false
		Using_Skill = false
		state_machine.last_state_dis.Attack = 0.0
		state_machine.last_state_dis.Skill = 0.0
	elif offense_disabled:
		# 红牌等禁伤期间允许继续正常移动，但不启动新的攻击/技能。
		Attacking = false
		Using_Skill = false
	else:
		# 已经由玩家/角色逻辑启动的动作必须继续完成；只禁止“冷却一到就自动起手”。
		if Using_Skill and not state == State.Skill:return State.Skill
		if Attacking and not state == State.Attack:return State.Attack

		if is_player_controlled():
			# V129：直接控制期间由鼠标决定何时出招。冷却继续累计，但 AI 不再自动进入 Attack/Skill。
			# 不能把 Can_Attack / Can_Skill 直接改成 false，否则角色专属脚本和玩家点击都会一起失效。
			pass
		else:
			if Can_Skill:
				if not Using_Skill and state_machine.last_state_dis.Skill >= Skill_Cooling:
					return State.Skill
			else: state_machine.last_state_dis.Skill = 0

			if Can_Attack:
				if state_machine.last_state_dis.Attack >= Attack_Cooling:
					return State.Attack
			else: state_machine.last_state_dis.Attack = 0
	
	match state:
		State.Move:
			if Speed <= 0:return State.Stand
		State.Stand:
			if Speed > 0:return State.Move
		State.Attack:
			if not Attacking:
				return State.Stand
			else: return -1
		State.Hurt:
			if hurting_timer.is_stopped():return State.Stand
		State.Skill:
			if not Using_Skill:
				return State.Stand
			else: return -1
	return -1

func tick_physics(state:State,delta:float) -> void:
	# 真正眩晕阶段的 Graphics 抖动只影响角色视觉，不改变根 CharacterBody2D 的真实物理坐标。
	_update_stun_shake_visual(delta)

	# V105：单位很多时把纯视觉 Shader/颜色维护错峰到约 20Hz（默认 divisor=3）。
	# 玩法状态机、移动、攻击、伤害与 Area2D 仍保持 60Hz，不牺牲命中判定。
	var visual_divisor:int = maxi(large_battle_visual_tick_divisor,1) if _large_battle_performance_mode else 1
	var run_heavy_visual_tick:bool = (
		visual_divisor <= 1
		or ((Engine.get_physics_frames() + get_instance_id()) % visual_divisor) == 0
	)
	if run_heavy_visual_tick:
		_update_poison_visual()
		_update_motion_inertia_visual(state,delta * float(visual_divisor))

	# V286：投射物朝向属于纯视觉，所有 peer 都按自己看到的实际位置差分更新。
	# 投射物不会进入大规模角色模式；普通人物通过缓存分类 O(1) 立即返回。
	_update_projectile_facing_from_position_delta(delta)
	if not is_multiplayer_authority():return
	if Type == Ball_Type.Ball and run_heavy_visual_tick:
		_ensure_upright_character_visual()
	apply_external_directional_gravity(delta)
	var projectile_frame_start:Vector2 = global_position
	if dizziness:
		stand(delta)
		_sync_projectile_facing_from_frame_motion(global_position - projectile_frame_start,delta)
		return
	elif Attacking and Can_Attack:
		continue_attack_time += delta
		if continue_attack_time >= continue_attack_cooling:
			continue_attack_time = 0
			continue_attack()
		
	match state:
		State.Move,State.Attack,State.Hurt,State.Skill:
			move(Speed,delta)
		State.Stand,State.Die:
			stand(delta)

	# V286：ball 派生投射物按“这一物理帧真实位移”更新朝向。
	# 重力、反弹、击退等造成的轨迹弯折都会反映到视觉方向，而不是一直保持出生角度。
	_sync_projectile_facing_from_frame_motion(global_position - projectile_frame_start,delta)
	_projectile_facing_last_position = global_position
	_projectile_facing_position_initialized = true
	
	#自动残影
	_process_auto_after_image(delta)

	#重置击退
	Repel = Vector2.ZERO


func _reset_after_image_sampling() -> void:
	_after_image_elapsed = 0.0
	_after_image_last_transform_valid = false
	_after_image_distance_leftover = 0.0


func _clear_after_image_path() -> void:
	_after_image_path_points.clear()
	_after_image_path_history_colors.clear()
	if _after_image_path_mesh != null and is_instance_valid(_after_image_path_mesh):
		_after_image_path_mesh.visible = false
	if _after_image_path_array_mesh != null:
		_after_image_path_array_mesh.clear_surfaces()


func _after_image_snapshot_enabled() -> bool:
	return AfterImage_Mode == AfterImage_Render_Mode.Snapshots or AfterImage_Mode == AfterImage_Render_Mode.Both


func _after_image_stretch_enabled() -> bool:
	return AfterImage_Mode == AfterImage_Render_Mode.Stretch_Only or AfterImage_Mode == AfterImage_Render_Mode.Both


func _get_source_after_image_texture() -> Texture2D:
	if image is Sprite2D:
		return (image as Sprite2D).texture
	if image is AnimatedSprite2D:
		var animated := image as AnimatedSprite2D
		if animated.sprite_frames != null and animated.sprite_frames.has_animation(animated.animation):
			return animated.sprite_frames.get_frame_texture(animated.animation,animated.frame)
	return null


func _get_current_after_image_texture() -> Texture2D:
	if AfterImage_Texture_Source == AfterImage_Texture_Mode.Custom_Texture and AfterImage_Custom_Texture != null:
		return AfterImage_Custom_Texture
	return _get_source_after_image_texture()


func _get_source_visual_rect_size() -> Vector2:
	if image != null and is_instance_valid(image) and image.has_method("get_rect"):
		var rect_variant = image.call("get_rect")
		if typeof(rect_variant) == TYPE_RECT2:
			var rect:Rect2 = rect_variant
			if rect.size.x > 0.001 and rect.size.y > 0.001:
				return rect.size.abs()
	var texture := _get_source_after_image_texture()
	if texture != null:
		return texture.get_size()
	return Vector2.ONE


func _get_after_image_region_params() -> Vector4:
	if AfterImage_Texture_Source == AfterImage_Texture_Mode.Custom_Texture and AfterImage_Custom_Texture != null:
		return Vector4(0.0,0.0,1.0,1.0)
	if image is Sprite2D:
		var source := image as Sprite2D
		if source.region_enabled and source.texture != null:
			var tex_size:Vector2 = source.texture.get_size()
			if tex_size.x > 0.001 and tex_size.y > 0.001:
				var rr:Rect2 = source.region_rect
				return Vector4(rr.position.x / tex_size.x,rr.position.y / tex_size.y,rr.size.x / tex_size.x,rr.size.y / tex_size.y)
		if source.hframes > 1 or source.vframes > 1:
			var col:int = source.frame % maxi(source.hframes,1)
			var row:int = int(source.frame / maxi(source.hframes,1))
			return Vector4(float(col) / float(source.hframes),float(row) / float(source.vframes),1.0 / float(source.hframes),1.0 / float(source.vframes))
	return Vector4(0.0,0.0,1.0,1.0)


func _configure_after_image_sprite_layout(sprite:Sprite2D) -> void:
	var using_custom:bool = AfterImage_Texture_Source == AfterImage_Texture_Mode.Custom_Texture and AfterImage_Custom_Texture != null
	if using_custom:
		sprite.centered = true
		sprite.offset = Vector2.ZERO
		sprite.region_enabled = false
		sprite.hframes = 1
		sprite.vframes = 1
		sprite.frame = 0
		return

	if image is Sprite2D:
		var source := image as Sprite2D
		sprite.centered = source.centered
		sprite.offset = source.offset
		sprite.region_enabled = source.region_enabled
		sprite.region_rect = source.region_rect
		sprite.region_filter_clip_enabled = source.region_filter_clip_enabled
		sprite.hframes = source.hframes
		sprite.vframes = source.vframes
		sprite.frame = source.frame
	elif image is AnimatedSprite2D:
		var animated := image as AnimatedSprite2D
		sprite.centered = animated.centered
		sprite.offset = animated.offset
		sprite.region_enabled = false
		sprite.hframes = 1
		sprite.vframes = 1
		sprite.frame = 0


func _after_image_transform_for_texture(base_transform:Transform2D,texture:Texture2D) -> Transform2D:
	var adjusted := base_transform

	if (
		AfterImage_Texture_Source == AfterImage_Texture_Mode.Custom_Texture
		and AfterImage_Custom_Texture != null
		and texture != null
	):
		var ratio:Vector2 = AfterImage_Custom_Texture_Scale
		if AfterImage_Custom_Texture_Match_Source_Size:
			var source_size:Vector2 = _get_source_visual_rect_size()
			var custom_size:Vector2 = texture.get_size()
			if custom_size.x > 0.001 and custom_size.y > 0.001:
				ratio *= Vector2(source_size.x / custom_size.x,source_size.y / custom_size.y)
		adjusted.x *= ratio.x
		adjusted.y *= ratio.y

	return _limit_projectile_after_image_transform(adjusted,texture)


func _limit_projectile_after_image_transform(transform_value:Transform2D,texture:Texture2D) -> Transform2D:
	if texture == null or AfterImage_Projectile_Max_Visual_Size <= 0.0:
		return transform_value
	if Type != Ball_Type.Shooter and Type != Ball_Type.Shooter_with_Health:
		return transform_value

	# 使用当前 Sprite 的有效帧/Region 尺寸，而不是直接拿整张图集尺寸。
	# transform_value 的两个基向量已经包含父节点与 Sprite 自身缩放。
	var visual_rect:Vector2 = _get_source_visual_rect_size()
	if visual_rect.x <= 0.001 or visual_rect.y <= 0.001:
		visual_rect = texture.get_size()
	if visual_rect.x <= 0.001 or visual_rect.y <= 0.001:
		return transform_value

	var rendered_width:float = visual_rect.x * transform_value.x.length()
	var rendered_height:float = visual_rect.y * transform_value.y.length()
	var rendered_max:float = maxf(rendered_width,rendered_height)
	var cap:float = maxf(AfterImage_Projectile_Max_Visual_Size,24.0)
	if rendered_max <= cap + 0.01:
		return transform_value

	var shrink:float = cap / maxf(rendered_max,0.001)
	var limited := transform_value
	limited.x *= shrink
	limited.y *= shrink
	return limited


func _process_auto_after_image(delta:float) -> void:
	if (
		AfterImage_Speed <= 0.0
		or image == null
		or not is_instance_valid(image)
		or not image.visible
		or state_machine.current_state == State.Die
	):
		_reset_after_image_sampling()
		# V410：默认没有残影的角色占绝大多数。若从未创建拖尾且强度已经为 0，
		# 直接返回；已有拖尾仍走原更新让它正常淡出，因此视觉效果不变。
		var has_live_stretch:bool = (
			(_after_image_stretch_sprite != null and is_instance_valid(_after_image_stretch_sprite))
			or (_after_image_path_mesh != null and is_instance_valid(_after_image_path_mesh))
			or _after_image_stretch_intensity > 0.002
		)
		if has_live_stretch:
			_update_after_image_stretch(delta,Transform2D.IDENTITY,0.0,Vector2.ZERO,false)
		return

	var current_transform:Transform2D = image.global_transform
	if not _after_image_last_transform_valid:
		_after_image_last_transform = current_transform
		_after_image_last_transform_valid = true
		_after_image_distance_leftover = 0.0
		_update_after_image_stretch(delta,current_transform,0.0,Vector2.ZERO,true)
		return

	var previous_transform:Transform2D = _after_image_last_transform
	var displacement:Vector2 = current_transform.origin - previous_transform.origin
	var distance:float = displacement.length()
	var visual_speed:float = distance / maxf(delta,0.0001)
	var trail_dir:Vector2 = displacement.normalized() if distance > 0.001 else _motion_visual_direction
	if trail_dir.length_squared() <= MOTION_EPSILON_SQ:
		trail_dir = direction if direction.length_squared() > MOTION_EPSILON_SQ else Vector2.RIGHT

	# 传送/同步大跳不应该在整张地图上铺满残影。
	if distance > 260.0:
		_after_image_last_transform = current_transform
		_after_image_distance_leftover = 0.0
		_clear_after_image_path()
		_update_after_image_stretch(delta,current_transform,0.0,trail_dir,true)
		return

	_update_after_image_stretch(delta,current_transform,visual_speed,trail_dir,true)

	# Stretch Only 不产生快照；它始终只复用一个拖尾 Sprite。
	if not _after_image_snapshot_enabled():
		_after_image_last_transform = current_transform
		_after_image_distance_leftover = 0.0
		return

	if visual_speed < AfterImage_Speed or distance <= 0.001:
		_after_image_last_transform = current_transform
		_after_image_distance_leftover = 0.0
		return

	var spacing:float = maxf(AfterImage_Spacing,2.0)
	var total_distance:float = _after_image_distance_leftover + distance
	var wanted_count:int = int(floor(total_distance / spacing))
	var spawn_count:int = mini(wanted_count,maxi(AfterImage_Max_Per_Frame,1))

	if spawn_count > 0:
		var distance_to_first:float = spacing - _after_image_distance_leftover
		if distance_to_first <= 0.001:
			distance_to_first = spacing
		for index in range(spawn_count):
			var along:float = distance_to_first + float(index) * spacing
			var weight:float = clampf(along / maxf(distance,0.001),0.0,1.0)
			var ghost_transform:Transform2D = previous_transform.interpolate_with(current_transform,weight)
			_spawn_after_image_at_transform(ghost_transform,trail_dir)

	# 如果一帧移动得极远并触发上限，直接丢掉多余 backlog。
	if wanted_count > spawn_count:
		_after_image_distance_leftover = fmod(total_distance,spacing)
	else:
		_after_image_distance_leftover = total_distance - float(spawn_count) * spacing

	_after_image_last_transform = current_transform


func _ensure_after_image_stretch_sprite() -> Sprite2D:
	if _after_image_stretch_sprite != null and is_instance_valid(_after_image_stretch_sprite):
		return _after_image_stretch_sprite
	var world := get_tree().current_scene
	if world == null:
		return null
	var sprite := Sprite2D.new()
	sprite.name = "AfterImageStretchTrail"
	sprite.centered = true
	sprite.flip_h = false
	sprite.flip_v = false
	sprite.visible = false
	sprite.z_as_relative = false
	sprite.z_index = image.z_index - 2 if image != null and is_instance_valid(image) else -2
	sprite.material = AFTER_IMAGE_STRETCH_MATERIAL
	world.add_child(sprite)
	# 拖尾是 world 下的视觉节点；主人离场时自动清理。
	tree_exiting.connect(Callable(sprite,"queue_free"),CONNECT_ONE_SHOT)
	_after_image_stretch_sprite = sprite
	return sprite



func _ensure_after_image_path_mesh() -> MeshInstance2D:
	if _after_image_path_mesh != null and is_instance_valid(_after_image_path_mesh):
		return _after_image_path_mesh
	var world := get_tree().current_scene
	if world == null:
		return null
	var mesh_instance := MeshInstance2D.new()
	mesh_instance.name = "AfterImagePixelExtrusionTrail"
	mesh_instance.z_as_relative = false
	mesh_instance.z_index = image.z_index - 2 if image != null and is_instance_valid(image) else -2
	mesh_instance.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mesh_instance.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	mesh_instance.visible = false
	_after_image_path_array_mesh = ArrayMesh.new()
	mesh_instance.mesh = _after_image_path_array_mesh
	world.add_child(mesh_instance)
	mesh_instance.global_transform = Transform2D.IDENTITY
	tree_exiting.connect(Callable(mesh_instance,"queue_free"),CONNECT_ONE_SHOT)
	_after_image_path_mesh = mesh_instance
	return mesh_instance


func _get_source_visual_rect() -> Rect2:
	if image != null and is_instance_valid(image) and image.has_method("get_rect"):
		var rect_variant = image.call("get_rect")
		if typeof(rect_variant) == TYPE_RECT2:
			var rect:Rect2 = rect_variant
			if rect.size.x > 0.001 and rect.size.y > 0.001:
				return rect
	var size:Vector2 = _get_source_visual_rect_size()
	return Rect2(-size * 0.5,size)



func _after_image_uv_from_local(
	local_pos:Vector2,
	display_rect:Rect2,
	region_params:Vector4
) -> Vector2:
	var nx:float = 0.5
	var ny:float = 0.5
	if absf(display_rect.size.x) > 0.0001:
		nx = (local_pos.x - display_rect.position.x) / display_rect.size.x
	if absf(display_rect.size.y) > 0.0001:
		ny = (local_pos.y - display_rect.position.y) / display_rect.size.y
	nx = clampf(nx,0.0,1.0)
	ny = clampf(ny,0.0,1.0)

	var source_x:float = 1.0 - nx if _visual_facing_flipped_h else nx
	return Vector2(
		region_params.x + source_x * region_params.z,
		region_params.y + ny * region_params.w
	)


func _after_image_leading_scanline_cache_key(
	texture:Texture2D,
	region_params:Vector4,
	display_rect:Rect2,
	local_forward:Vector2
) -> String:
	var angle_bucket:int = int(round(rad_to_deg(local_forward.angle())))
	return "%s|%.6f|%.6f|%.6f|%.6f|%.3f|%.3f|%.3f|%.3f|%d|%d|%.3f|%d|%.2f" % [
		str(texture.get_rid()),
		region_params.x,region_params.y,region_params.z,region_params.w,
		display_rect.position.x,display_rect.position.y,
		display_rect.size.x,display_rect.size.y,
		angle_bucket,
		1 if _visual_facing_flipped_h else 0,
		AfterImage_Path_Alpha_Threshold,
		AfterImage_Path_Scanline_Samples,
		AfterImage_Path_Leading_Inset_Pixels
	]


func _get_after_image_leading_scanline_profile(
	texture:Texture2D,
	visual_transform:Transform2D,
	world_forward:Vector2
) -> Dictionary:
	# V17 的定义非常直接：对“垂直于移动方向”的每一条扫描线，
	# 找这条扫描线上沿移动方向投影最大的非透明像素（最前面的像素）。
	# Mesh 后面所有历史截面都复用这颗像素的 UV，于是它会被真正向后拉长。
	if texture == null:
		return {}

	var region_params:Vector4 = _get_after_image_region_params()
	var display_rect:Rect2 = _get_source_visual_rect()
	if display_rect.size.x <= 0.001 or display_rect.size.y <= 0.001:
		return {}

	var local_forward:Vector2 = _after_image_path_local_forward(visual_transform,world_forward)
	if local_forward.length_squared() <= MOTION_EPSILON_SQ:
		local_forward = Vector2.RIGHT
	else:
		local_forward = local_forward.normalized()
	# 这里严格按“真实移动方向的最前沿”取样，不再用 V16 的尾端反转逻辑。
	var local_side:Vector2 = Vector2(-local_forward.y,local_forward.x)

	var key:String = _after_image_leading_scanline_cache_key(
		texture,region_params,display_rect,local_forward
	)
	var local_data:Dictionary = {}
	if _shared_after_image_leading_scanline_cache.has(key):
		local_data = _shared_after_image_leading_scanline_cache[key]
	else:
		var img:Image = _get_cached_after_image_source_image(texture)
		if img == null or img.is_empty():
			return {}

		var iw:int = img.get_width()
		var ih:int = img.get_height()
		if iw <= 0 or ih <= 0:
			return {}

		var px := Rect2i(
			int(round(region_params.x * float(iw))),
			int(round(region_params.y * float(ih))),
			maxi(int(round(region_params.z * float(iw))),1),
			maxi(int(round(region_params.w * float(ih))),1)
		).intersection(Rect2i(0,0,iw,ih))
		if px.size.x <= 0 or px.size.y <= 0:
			return {}

		var region_img:Image = img.get_region(px)
		var used:Rect2i = region_img.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			return {}

		var threshold:float = clampf(AfterImage_Path_Alpha_Threshold,0.0,1.0)
		var min_side:float = INF
		var max_side:float = -INF
		var local_per_px_x:float = absf(display_rect.size.x) / float(maxi(px.size.x,1))
		var local_per_px_y:float = absf(display_rect.size.y) / float(maxi(px.size.y,1))
		var local_per_px_forward:float = sqrt(
			pow(local_forward.x * local_per_px_x,2.0)
			+ pow(local_forward.y * local_per_px_y,2.0)
		)
		local_per_px_forward = maxf(local_per_px_forward,0.0001)

		# 第一遍只确定整个不透明轮廓在“侧向”上的跨度。
		for uy in range(used.position.y,used.end.y):
			var py:int = px.position.y + uy
			for ux in range(used.position.x,used.end.x):
				var px_abs:int = px.position.x + ux
				if img.get_pixel(px_abs,py).a < threshold:
					continue
				var nx:float = (float(ux) + 0.5) / float(maxi(px.size.x,1))
				var ny:float = (float(uy) + 0.5) / float(maxi(px.size.y,1))
				var display_nx:float = 1.0 - nx if _visual_facing_flipped_h else nx
				var local_pos := Vector2(
					display_rect.position.x + display_nx * display_rect.size.x,
					display_rect.position.y + ny * display_rect.size.y
				)
				var side_value:float = local_pos.dot(local_side)
				min_side = minf(min_side,side_value)
				max_side = maxf(max_side,side_value)

		if min_side == INF or max_side == -INF or max_side - min_side <= 0.0001:
			return {}

		var samples:int = clampi(AfterImage_Path_Scanline_Samples,8,64)
		var best_f:Array[float] = []
		var best_uv:Array[Vector2] = []
		var best_pos:Array[Vector2] = []
		var best_alpha:Array[float] = []
		var valid:Array[bool] = []
		for i in range(samples):
			best_f.append(-INF)
			best_uv.append(Vector2.ZERO)
			best_pos.append(Vector2.ZERO)
			best_alpha.append(0.0)
			valid.append(false)

		# 第二遍：每个侧向 bin 只留下“最前面的”那颗像素。
		for uy in range(used.position.y,used.end.y):
			var py:int = px.position.y + uy
			for ux in range(used.position.x,used.end.x):
				var px_abs:int = px.position.x + ux
				var pixel:Color = img.get_pixel(px_abs,py)
				if pixel.a < threshold:
					continue
				var nx:float = (float(ux) + 0.5) / float(maxi(px.size.x,1))
				var ny:float = (float(uy) + 0.5) / float(maxi(px.size.y,1))
				var display_nx:float = 1.0 - nx if _visual_facing_flipped_h else nx
				var local_pos := Vector2(
					display_rect.position.x + display_nx * display_rect.size.x,
					display_rect.position.y + ny * display_rect.size.y
				)
				var side_value:float = local_pos.dot(local_side)
				var normalized_side:float = clampf(
					(side_value - min_side) / maxf(max_side - min_side,0.0001),0.0,1.0
				)
				var index:int = clampi(int(round(normalized_side * float(samples - 1))),0,samples - 1)
				var f:float = local_pos.dot(local_forward)
				if f <= best_f[index]:
					continue
				best_f[index] = f
				best_pos[index] = local_pos
				best_uv[index] = Vector2(
					(float(px_abs) + 0.5) / float(iw),
					(float(py) + 0.5) / float(ih)
				)
				best_alpha[index] = pixel.a
				valid[index] = true

		# 透明安全边距/斜边可能造成个别 bin 没正好落到像素中心。
		# 位置/UV 用最近有效扫描线补齐，但把“原本无像素”的信息保留在 valid 里，
		# 顶点 Alpha 会把真正的空洞继续裁掉。
		for i in range(samples):
			if valid[i]:
				continue
			var nearest:int = -1
			var nearest_distance:int = 999999
			for j in range(samples):
				if not valid[j]:
					continue
				var d:int = absi(j - i)
				if d < nearest_distance:
					nearest = j
					nearest_distance = d
			if nearest >= 0:
				best_f[i] = best_f[nearest]
				best_pos[i] = best_pos[nearest]
				best_uv[i] = best_uv[nearest]
				best_alpha[i] = 0.0

		# 可选向内退一点，但默认 0：就是用户要求的“最前面的像素”。
		var inset_local:float = maxf(AfterImage_Path_Leading_Inset_Pixels,0.0) * local_per_px_forward
		if inset_local > 0.0:
			for i in range(samples):
				if best_f[i] == -INF:
					continue
				best_pos[i] -= local_forward * inset_local

		local_data = {
			"local_points": best_pos,
			"uvs": best_uv,
			"alphas": best_alpha,
			"samples": samples,
			"local_forward": local_forward,
			"local_side": local_side,
		}
		_shared_after_image_leading_scanline_cache[key] = local_data

	if local_data.is_empty():
		return {}

	# 把缓存的 local scanline profile 转成“当前视觉 transform 下的世界偏移”。
	# Mesh 历史段只需要旋转这些偏移到各自的路径切线方向即可。
	var current_forward:Vector2 = world_forward
	if current_forward.length_squared() <= MOTION_EPSILON_SQ:
		current_forward = visual_transform.x
	if current_forward.length_squared() <= MOTION_EPSILON_SQ:
		current_forward = Vector2.RIGHT
	current_forward = current_forward.normalized()
	var current_side:Vector2 = Vector2(-current_forward.y,current_forward.x)
	var center:Vector2 = visual_transform.origin

	var front_offsets:Array[float] = []
	var side_offsets:Array[float] = []
	var points:Array = local_data["local_points"]
	for point_variant in points:
		var local_point:Vector2 = point_variant
		var world_point:Vector2 = visual_transform * local_point
		var offset:Vector2 = world_point - center
		front_offsets.append(offset.dot(current_forward))
		side_offsets.append(offset.dot(current_side) * AfterImage_Path_Width_Multiplier)

	return {
		"front_offsets": front_offsets,
		"side_offsets": side_offsets,
		"uvs": local_data["uvs"],
		"alphas": local_data["alphas"],
		"samples": int(local_data["samples"]),
		"world_forward": current_forward,
		"world_side": current_side,
	}


func _after_image_uses_history_path_colors() -> bool:
	# 默认保持旧版“尾色 -> 头色”的实时渐变。
	# 需要真正沿历史路径保留颜色的角色（例如极速者）覆写为 true。
	return false


func _after_image_history_path_color_for_point(_point:Vector2) -> Color:
	return AfterImage_Stretch_Head_Color


func _after_image_path_tint(index:int,t:float) -> Color:
	if (
		_after_image_uses_history_path_colors()
		and _after_image_path_history_colors.size() == _after_image_path_points.size()
		and index >= 0
		and index < _after_image_path_history_colors.size()
	):
		return _after_image_path_history_colors[index]
	return AfterImage_Stretch_Tail_Color.lerp(AfterImage_Stretch_Head_Color,t)


func _append_after_image_path_point(point:Vector2) -> void:
	var history_colors:bool = _after_image_uses_history_path_colors()
	if not history_colors and not _after_image_path_history_colors.is_empty():
		_after_image_path_history_colors.clear()

	if _after_image_path_points.is_empty():
		_after_image_path_points.append(point)
		if history_colors:
			_after_image_path_history_colors.append(_after_image_history_path_color_for_point(point))
		return

	var last:Vector2 = _after_image_path_points[-1]
	var distance:float = last.distance_to(point)
	if distance <= 0.05:
		_after_image_path_points[-1] = point
		return

	var spacing:float = maxf(AfterImage_Path_Point_Spacing,0.5)
	var append_new:bool = true
	if _after_image_path_points.size() >= 2 and distance < spacing:
		var prev:Vector2 = _after_image_path_points[-2]
		var old_dir:Vector2 = last - prev
		var new_dir:Vector2 = point - last
		var turning:bool = old_dir.length_squared() > 0.0001 and new_dir.length_squared() > 0.0001 and old_dir.normalized().dot(new_dir.normalized()) < 0.996
		append_new = turning

	if append_new:
		_after_image_path_points.append(point)
		if history_colors:
			_after_image_path_history_colors.append(_after_image_history_path_color_for_point(point))
	else:
		# 小距离直线运动只推进最新几何点，不重染这个已经存在的路径段。
		_after_image_path_points[-1] = point

	while _after_image_path_points.size() > maxi(AfterImage_Path_Max_Points,4):
		_after_image_path_points.remove_at(0)
		if not _after_image_path_history_colors.is_empty():
			_after_image_path_history_colors.remove_at(0)


func _trim_after_image_path_to_length(max_length:float) -> void:
	if _after_image_path_points.size() < 2:
		return
	var total:float = 0.0
	for i in range(_after_image_path_points.size() - 1,0,-1):
		total += _after_image_path_points[i].distance_to(_after_image_path_points[i - 1])
	if total <= max_length:
		return
	var excess:float = total - max_length
	while _after_image_path_points.size() >= 2 and excess > 0.0:
		var a:Vector2 = _after_image_path_points[0]
		var b:Vector2 = _after_image_path_points[1]
		var seg:float = a.distance_to(b)
		if seg <= 0.0001:
			_after_image_path_points.remove_at(0)
			if not _after_image_path_history_colors.is_empty():
				_after_image_path_history_colors.remove_at(0)
			continue
		if excess >= seg and _after_image_path_points.size() > 2:
			excess -= seg
			_after_image_path_points.remove_at(0)
			if not _after_image_path_history_colors.is_empty():
				_after_image_path_history_colors.remove_at(0)
		else:
			var ratio:float = clampf(excess / seg,0.0,1.0)
			_after_image_path_points[0] = a.lerp(b,ratio)
			if _after_image_path_history_colors.size() >= 2:
				_after_image_path_history_colors[0] = _after_image_path_history_colors[0].lerp(_after_image_path_history_colors[1],ratio)
			excess = 0.0


func _get_after_image_visible_uv_rect(texture:Texture2D,region_params:Vector4) -> Rect2:
	if texture == null:
		return Rect2(region_params.x,region_params.y,region_params.z,region_params.w)
	var key:String = "%s|%.6f|%.6f|%.6f|%.6f" % [str(texture.get_rid()),region_params.x,region_params.y,region_params.z,region_params.w]
	if _shared_after_image_path_visible_uv_cache.has(key):
		return _shared_after_image_path_visible_uv_cache[key]

	var fallback := Rect2(region_params.x,region_params.y,region_params.z,region_params.w)
	var img:Image = _get_cached_after_image_source_image(texture)
	if img == null or img.is_empty():
		_shared_after_image_path_visible_uv_cache[key] = fallback
		return fallback

	var iw:int = img.get_width()
	var ih:int = img.get_height()
	if iw <= 0 or ih <= 0:
		_shared_after_image_path_visible_uv_cache[key] = fallback
		return fallback

	var px := Rect2i(
		int(round(region_params.x * float(iw))),
		int(round(region_params.y * float(ih))),
		maxi(int(round(region_params.z * float(iw))),1),
		maxi(int(round(region_params.w * float(ih))),1)
	)
	px = px.intersection(Rect2i(0,0,iw,ih))
	if px.size.x <= 0 or px.size.y <= 0:
		_shared_after_image_path_visible_uv_cache[key] = fallback
		return fallback

	var region_img:Image = img.get_region(px)
	var used:Rect2i = region_img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		_shared_after_image_path_visible_uv_cache[key] = fallback
		return fallback

	var uv := Rect2(
		float(px.position.x + used.position.x) / float(iw),
		float(px.position.y + used.position.y) / float(ih),
		float(used.size.x) / float(iw),
		float(used.size.y) / float(ih)
	)
	_shared_after_image_path_visible_uv_cache[key] = uv
	return uv


func _after_image_path_local_forward(visual_transform:Transform2D,world_forward:Vector2) -> Vector2:
	var forward:Vector2 = world_forward
	if forward.length_squared() <= MOTION_EPSILON_SQ:
		forward = visual_transform.x
	var local:Vector2 = visual_transform.affine_inverse().basis_xform(forward)
	if local.length_squared() <= MOTION_EPSILON_SQ:
		return Vector2.RIGHT
	return local.normalized()



func _build_after_image_full_texture_path_mesh(
	texture:Texture2D,
	visual_transform:Transform2D,
	world_forward:Vector2
) -> ArrayMesh:
	# 保留 V11/V12 的“整张贴图沿路径铺开”模式，给能量/烟雾自定义贴图用。
	if texture == null or _after_image_path_points.size() < 2:
		return null
	var count:int = _after_image_path_points.size()
	var source_size:Vector2 = _get_source_visual_rect_size()
	var world_w:float = source_size.x * visual_transform.x.length()
	var world_h:float = source_size.y * visual_transform.y.length()
	var base_width:float = maxf(minf(world_w,world_h) * AfterImage_Path_Width_Multiplier,1.0)
	var visible_uv:Rect2 = _get_after_image_visible_uv_rect(texture,_get_after_image_region_params())
	var local_forward:Vector2 = _after_image_path_local_forward(visual_transform,world_forward)

	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.resize(count * 2)
	uvs.resize(count * 2)
	colors.resize(count * 2)
	var reference_side:Vector2 = Vector2(-world_forward.y,world_forward.x).normalized()

	for i in range(count):
		var point:Vector2 = _after_image_path_points[i]
		var tangent:Vector2
		if i == 0:
			tangent = _after_image_path_points[1] - point
		elif i == count - 1:
			tangent = point - _after_image_path_points[i - 1]
		else:
			tangent = _after_image_path_points[i + 1] - _after_image_path_points[i - 1]
		if tangent.length_squared() <= 0.0001:
			tangent = world_forward
		tangent = tangent.normalized()
		var side:Vector2 = Vector2(-tangent.y,tangent.x)
		if side.dot(reference_side) < 0.0:
			side = -side
		var t:float = float(i) / float(maxi(count - 1,1))
		var width_factor:float = lerpf(AfterImage_Stretch_Tail_Width,AfterImage_Stretch_Head_Width,t)
		var half_width:float = base_width * 0.5 * maxf(width_factor,0.01)
		vertices[i * 2] = point - side * half_width
		vertices[i * 2 + 1] = point + side * half_width

		var horizontal:bool = absf(local_forward.x) >= absf(local_forward.y)
		if horizontal:
			var u:float = lerpf(visible_uv.position.x,visible_uv.end.x,t)
			uvs[i * 2] = Vector2(u,visible_uv.position.y)
			uvs[i * 2 + 1] = Vector2(u,visible_uv.end.y)
		else:
			var v:float = lerpf(visible_uv.position.y,visible_uv.end.y,t)
			uvs[i * 2] = Vector2(visible_uv.position.x,v)
			uvs[i * 2 + 1] = Vector2(visible_uv.end.x,v)
		var tint:Color = _after_image_path_tint(i,t)
		tint.a *= AfterImage_Stretch_Alpha * _after_image_stretch_intensity * smoothstep(0.0,0.18,t)
		colors[i * 2] = tint
		colors[i * 2 + 1] = tint

	for i in range(count - 1):
		var a:int = i * 2
		var b:int = a + 1
		var c:int = a + 2
		var d:int = a + 3
		indices.append_array(PackedInt32Array([a,b,c,b,d,c]))

	var arrays:Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	if _after_image_path_array_mesh == null:
		_after_image_path_array_mesh = ArrayMesh.new()
	_after_image_path_array_mesh.clear_surfaces()
	_after_image_path_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return _after_image_path_array_mesh


func _build_after_image_pixel_extrusion_mesh(
	texture:Texture2D,
	visual_transform:Transform2D,
	world_forward:Vector2
) -> ArrayMesh:
	if texture == null or _after_image_path_points.size() < 2:
		return null
	if AfterImage_Path_Use_Texture:
		return _build_after_image_full_texture_path_mesh(texture,visual_transform,world_forward)

	var profile:Dictionary = _get_after_image_leading_scanline_profile(
		texture,visual_transform,world_forward
	)
	if profile.is_empty():
		return null

	var section_count:int = _after_image_path_points.size()
	var sample_count:int = int(profile["samples"])
	if section_count < 2 or sample_count < 2:
		return null

	var front_offsets:Array = profile["front_offsets"]
	var side_offsets:Array = profile["side_offsets"]
	var profile_uvs:Array = profile["uvs"]
	var profile_alphas:Array = profile["alphas"]
	var reference_side:Vector2 = Vector2(profile["world_side"])

	var vertex_count:int = section_count * sample_count
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.resize(vertex_count)
	uvs.resize(vertex_count)
	colors.resize(vertex_count)

	for section in range(section_count):
		var center:Vector2 = _after_image_path_points[section]
		var tangent:Vector2
		if section == 0:
			tangent = _after_image_path_points[1] - center
		elif section == section_count - 1:
			tangent = center - _after_image_path_points[section - 1]
		else:
			tangent = _after_image_path_points[section + 1] - _after_image_path_points[section - 1]
		if tangent.length_squared() <= 0.0001:
			tangent = world_forward if world_forward.length_squared() > 0.0001 else Vector2.RIGHT
		tangent = tangent.normalized()
		var side:Vector2 = Vector2(-tangent.y,tangent.x)
		if side.dot(reference_side) < 0.0:
			side = -side

		var t:float = float(section) / float(maxi(section_count - 1,1))
		var width_factor:float = lerpf(
			AfterImage_Stretch_Tail_Width,AfterImage_Stretch_Head_Width,t
		)
		var tint:Color = _after_image_path_tint(section,t)
		var path_alpha:float = AfterImage_Stretch_Alpha * _after_image_stretch_intensity * smoothstep(0.0,0.16,t)

		for scanline in range(sample_count):
			var index:int = section * sample_count + scanline
			# 关键：每条扫描线都有自己的“最前沿” front_offset。
			# 所以刀头存在的行从刀头最前像素开始拉；只有握把的行从握把最前像素开始拉。
			vertices[index] = (
				center
				+ tangent * float(front_offsets[scanline])
				+ side * float(side_offsets[scanline]) * maxf(width_factor,0.01)
			)
			# 同一条扫描线沿整个历史路径始终采样同一个“最前沿像素” UV，
			# 这才是像素被真正向后拉长，而不是另画一条带子。
			uvs[index] = Vector2(profile_uvs[scanline])
			var vertex_tint:Color = tint
			vertex_tint.a *= path_alpha * clampf(float(profile_alphas[scanline]),0.0,1.0)
			colors[index] = vertex_tint

	for section in range(section_count - 1):
		for scanline in range(sample_count - 1):
			var a:int = section * sample_count + scanline
			var b:int = a + 1
			var c:int = (section + 1) * sample_count + scanline
			var d:int = c + 1
			indices.append_array(PackedInt32Array([a,b,c,b,d,c]))

	var arrays:Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	if _after_image_path_array_mesh == null:
		_after_image_path_array_mesh = ArrayMesh.new()
	_after_image_path_array_mesh.clear_surfaces()
	_after_image_path_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return _after_image_path_array_mesh


func _update_after_image_path_ribbon(
	visual_transform:Transform2D,
	world_trail_dir:Vector2,
	valid_visual:bool
) -> void:
	var mesh_instance := _ensure_after_image_path_mesh()
	if mesh_instance == null:
		return
	if not valid_visual:
		# 停止移动/关闭残影时，不突然切掉旧 Mesh，而是先按 Stretch 响应衰减。
		mesh_instance.modulate.a = _after_image_stretch_intensity
		if _after_image_stretch_intensity <= 0.002:
			mesh_instance.visible = false
			if _after_image_path_array_mesh != null:
				_after_image_path_array_mesh.clear_surfaces()
			_after_image_path_points.clear()
			_after_image_path_history_colors.clear()
		return

	var forward:Vector2 = world_trail_dir.normalized() if world_trail_dir.length_squared() > MOTION_EPSILON_SQ else Vector2.RIGHT
	var texture := _get_current_after_image_texture()
	if texture == null:
		mesh_instance.visible = false
		return
	# V17：历史路径记录图片自己的真实中心。每条扫描线的最前沿偏移在 Mesh 里独立加上，
	# 因此不会再因为“尾帽锚点”造成整体偏移。
	_append_after_image_path_point(visual_transform.origin)
	var length_factor:float = lerpf(0.28,1.0,_after_image_stretch_intensity)
	_trim_after_image_path_to_length(maxf(AfterImage_Stretch_Length * length_factor,2.0))
	if _after_image_path_points.size() < 2:
		mesh_instance.visible = false
		return

	var mesh := _build_after_image_pixel_extrusion_mesh(texture,visual_transform,forward)
	if mesh == null:
		mesh_instance.visible = false
		return
	mesh_instance.texture = texture
	mesh_instance.mesh = mesh
	mesh_instance.modulate = image.modulate if image != null and is_instance_valid(image) else Color.WHITE
	mesh_instance.self_modulate = image.self_modulate if image != null and is_instance_valid(image) else Color.WHITE
	mesh_instance.visible = _after_image_stretch_intensity > 0.002


func _update_after_image_stretch(
	delta:float,
	visual_transform:Transform2D,
	visual_speed:float,
	world_trail_dir:Vector2,
	valid_visual:bool
) -> void:
	var wants_stretch:bool = valid_visual and _after_image_stretch_enabled() and AfterImage_Speed > 0.0
	var target:float = 0.0
	if wants_stretch and visual_speed >= AfterImage_Speed:
		var denom:float = maxf(AfterImage_Stretch_Full_Speed - AfterImage_Speed,1.0)
		target = clampf((visual_speed - AfterImage_Speed) / denom,0.0,1.0)
		# 阈值一旦跨过就给一点最低可见强度，避免低速时一闪一闪。
		target = maxf(target,0.12)

	var response:float = maxf(AfterImage_Stretch_Response,1.0)
	var blend:float = 1.0 - exp(-response * maxf(delta,0.0001))
	_after_image_stretch_intensity = lerpf(_after_image_stretch_intensity,target,blend)

	if AfterImage_Stretch_Geometry == AfterImage_Stretch_Geometry_Mode.Path_Ribbon:
		if _after_image_stretch_sprite != null and is_instance_valid(_after_image_stretch_sprite):
			_after_image_stretch_sprite.visible = false
		_update_after_image_path_ribbon(visual_transform,world_trail_dir,valid_visual)
		return
	elif _after_image_path_mesh != null and is_instance_valid(_after_image_path_mesh):
		_after_image_path_mesh.visible = false
		if _after_image_path_array_mesh != null:
			_after_image_path_array_mesh.clear_surfaces()
		_after_image_path_points.clear()
		_after_image_path_history_colors.clear()

	# 投射物死亡/隐藏后只允许残影原地淡出，不能把尚未衰减完的拖尾
	# 用 Transform2D.IDENTITY 重置到世界原点，否则会在地图左上角出现
	# 巨大的低透明度子弹/飞刀贴图。
	if not valid_visual:
		if _after_image_stretch_sprite != null and is_instance_valid(_after_image_stretch_sprite):
			_after_image_stretch_sprite.set_instance_shader_parameter(
				"intensity",_after_image_stretch_intensity
			)
			_after_image_stretch_sprite.visible = _after_image_stretch_intensity > 0.002
		return

	if _after_image_stretch_intensity <= 0.002 and target <= 0.0:
		if _after_image_stretch_sprite != null and is_instance_valid(_after_image_stretch_sprite):
			_after_image_stretch_sprite.visible = false
		return

	var texture := _get_current_after_image_texture()
	if texture == null:
		return
	var trail := _ensure_after_image_stretch_sprite()
	if trail == null:
		return
	trail.texture = texture
	_configure_after_image_sprite_layout(trail)
	trail.visible = true
	trail.modulate = image.modulate if image != null and is_instance_valid(image) else Color.WHITE
	trail.self_modulate = image.self_modulate if image != null and is_instance_valid(image) else Color.WHITE
	trail.global_transform = _after_image_transform_for_texture(visual_transform,texture)

	var local_dir:Vector2 = world_trail_dir
	if local_dir.length_squared() <= MOTION_EPSILON_SQ:
		local_dir = Vector2.RIGHT
	local_dir = local_dir.normalized().rotated(-trail.global_rotation)

	trail.set_instance_shader_parameter("trail_direction",local_dir.normalized())
	trail.set_instance_shader_parameter("intensity",_after_image_stretch_intensity)
	var uniforms:Array = [
		1.0 if _visual_facing_flipped_h else 0.0,
		AfterImage_Stretch_Head_Color,AfterImage_Stretch_Tail_Color,
		Vector4(AfterImage_Stretch_Length,AfterImage_Stretch_Head_Width,AfterImage_Stretch_Tail_Width,AfterImage_Stretch_Distortion_Pixels),
		AfterImage_Stretch_Alpha,int(AfterImage_Style),
		clampi(AfterImage_Stretch_Sample_Count,1,8),_get_after_image_region_params()
	]
	# Most knife settings remain constant for their whole lifetime. Keep direction
	# and fading live every tick; upload the other uniforms only when they change.
	if _stretch_uniform_target != trail.get_instance_id() or uniforms != _stretch_uniform_values:
		_stretch_uniform_target = trail.get_instance_id()
		_stretch_uniform_values = uniforms
		for index:int in range(STRETCH_UNIFORM_NAMES.size()):
			trail.set_instance_shader_parameter(STRETCH_UNIFORM_NAMES[index],uniforms[index])


#移动
@export_category("碰撞反馈")
# 旧版按毫秒冷却会吞掉高速角色紧接着发生的第二次真实反弹。
# 现在只做“同一 physics frame 去重”：同一撞击被多个系统重复报告时只播一次，
# 但下一物理帧只要真的又反弹，就一定再次播放声音和动画。
@export_range(0.0,0.5,0.005) var collide_audio_cooldown:float = 0.0 # 兼容旧场景，不再参与判定
@export_range(0.0,0.5,0.005) var collide_visual_cooldown:float = 0.0 # 兼容旧场景，不再参与判定
# 即使相对速度较小，只要 move_and_slide 确认真正发生碰撞，也至少给一个可见反馈。
@export_range(0.0,500.0,5.0) var collide_visual_min_power:float = 110.0
# 高速撞击只增强到这个参考速度；再快也不继续放大形变。
@export_range(50.0,2000.0,10.0) var collide_visual_full_power:float = 300.0
@export_range(0.0,0.70,0.01) var collide_visual_squash:float = 0.34
@export_range(0.0,0.55,0.01) var collide_visual_stretch:float = 0.20
@export_range(0.0,0.45,0.01) var collide_visual_rebound_overshoot:float = 0.17
@export_range(0.0,0.25,0.005) var collide_visual_wobble:float = 0.040
@export_range(0.0,1.0,0.01) var collide_visual_min_strength:float = 0.60
@export_range(0.0,20.0,0.5) var collide_visual_tilt_degrees:float = 0.0
@export_range(0.0,240.0,1.0) var collide_visual_recoil:float = 0.0
@export_range(0.01,0.20,0.005) var collide_visual_in_time:float = 0.035
@export_range(0.01,0.25,0.005) var collide_visual_rebound_time:float = 0.060
@export_range(0.02,0.50,0.01) var collide_visual_return_time:float = 0.14
# 人物/投射物撞到地图墙或静态实体时，在实际碰撞点喷出白色受击线条。
@export var wall_hit_burst_enabled:bool = true
@export_range(0.25,2.0,0.05) var wall_hit_burst_strength_scale:float = 1.0
@export var debug_collision_feedback:bool = false

@export_category("远程受击反馈")
@export var ranged_hit_feedback_enabled:bool = true
# 达到该有效伤害时使用完整远程受击形变；更高伤害封顶。
@export_range(1.0,500.0,1.0) var ranged_hit_full_damage:float = 90.0
@export_range(0.0,1.0,0.01) var ranged_hit_min_strength:float = 0.22
@export_range(0.0,1.25,0.01) var ranged_hit_max_strength:float = 0.78
# 远程命中采用更短、更硬的局部冲击，不带碰撞脚步声。
@export_range(0.0,0.70,0.01) var ranged_hit_squash:float = 0.24
@export_range(0.0,0.55,0.01) var ranged_hit_bulge:float = 0.13
@export_range(0.0,0.45,0.01) var ranged_hit_rebound:float = 0.10
@export_range(0.0,0.25,0.005) var ranged_hit_wobble:float = 0.018
@export_range(0.0,240.0,1.0) var ranged_hit_recoil:float = 0.0
@export_range(0.0,20.0,0.5) var ranged_hit_tilt_degrees:float = 0.0
@export_range(0.05,0.40,0.01) var ranged_hit_duration:float = 0.13

@export_category("移动软体惯性")
@export var motion_stretch_enabled:bool = true
# 到达该速度时使用完整移动拉伸；更快只封顶，不会无限变形。
@export_range(50.0,1200.0,10.0) var motion_stretch_full_speed:float = 300.0
# 沿移动方向拉长，例如向右时 X 增大。
@export_range(0.0,0.30,0.005) var motion_stretch_amount:float = 0.105
# 垂直移动方向压缩，例如向右时 Y 减小。
@export_range(0.0,0.25,0.005) var motion_squash_amount:float = 0.065
# 头肩相对躯干的轻微惯性滞后。
@export_range(0.0,0.12,0.002) var motion_inertia_lean:float = 0.028
# 越高越快追上目标形变；保留一点缓动避免速度变化时跳变。
@export_range(1.0,40.0,0.5) var motion_stretch_response:float = 11.0
@export_range(1.0,40.0,0.5) var motion_direction_response:float = 15.0
# 远端同步/传送超过这个单帧距离时不按位移计算速度，避免瞬间拉成长条。
@export_range(50.0,3000.0,10.0) var motion_visual_teleport_threshold:float = 500.0

@export_category("运动模糊")
# V114：速度驱动“方向性运动模糊”，不是历史位置残影。
# 所有关键参数都直接导出到 Inspector；带 or_greater 的项目可以手动输入超过滑条上限的值。
@export var motion_blur_enabled:bool = true
# 总体效果倍率。1.0=标准；>1 会更早达到强模糊，0=关闭速度强度（仍可用下方强制预览）。
@export_range(0.0,4.0,0.05,"or_greater") var motion_blur_effect_strength:float = 1.80
# 普通移动开始出现模糊的真实世界速度。
@export_range(0.0,1200.0,5.0,"or_greater") var motion_blur_start_speed:float = 10.0
# 达到完整方向模糊的真实世界速度。
@export_range(10.0,2000.0,10.0,"or_greater") var motion_blur_full_speed:float = 220.0
# 速度曲线：<1 会让中低速更快变糊；>1 会把强模糊推迟到高速。
@export_range(0.10,4.0,0.05,"or_greater") var motion_blur_strength_curve:float = 0.55
# 满强度时方向模糊的基础长度（纹理像素）。可手动输入超过 256 的值做夸张效果。
@export_range(1.0,256.0,1.0,"or_greater") var motion_blur_max_pixels:float = 56.0
# 模糊层覆盖清晰本体的最大透明度。1.0 最明显。
@export_range(0.0,1.0,0.01) var motion_blur_max_alpha:float = 1.0
# 几何前缘沿运动方向展开倍率；越高，运动方向的拉伸越明显。
@export_range(0.0,4.0,0.05,"or_greater") var motion_blur_forward_stretch:float = 1.35
# 纹理采样扩散倍率；越高，同样像素长度下的连续 smear 越宽。
@export_range(0.10,4.0,0.05,"or_greater") var motion_blur_sample_spread:float = 1.55
# 保留清晰核心的比例：0=最糊，1=几乎保持原图。默认很低以增强模糊。
@export_range(0.0,1.0,0.01) var motion_blur_core_sharpness:float = 0.05
# 越高越快跟上速度变化，避免加速/停下时模糊残留太久。
@export_range(1.0,80.0,0.5,"or_greater") var motion_blur_response:float = 20.0
# 调试/调参预览：-1=自动按速度；0~1=强制固定模糊强度。运行时 Remote Inspector 可直接拖动。
@export_range(-1.0,1.0,0.01) var motion_blur_force_strength:float = -1.0

var _last_collision_feedback_physics_frame:int = -1000000
var _last_wall_hit_burst_physics_frame:int = -1000000
# 连续贴着同一面墙时，move_and_slide() 会每个物理帧继续返回同一接触。
# 这里把“持续接触”和“离墙后再次撞上”分开，避免每帧叠一组白线，
# 同时保证真正再次撞同一面墙时会创建一套独立动画，不会重置上一套。
var _active_wall_contact_key:int = 0
var _active_wall_contact_last_frame:int = -1000000
var _last_requested_velocity:Vector2 = Vector2.ZERO
var _collision_visual_base:Dictionary = {}
var _visual_facing_flipped_h:bool = false
# V411：朝向没变化时不要每个 physics tick 重写 Sprite/Shader。
var _visual_facing_initialized:bool = false
# V412：同朝向快速路径还要确认视觉节点 / Shader 没被角色脚本替换；否则换图后必须重新同步。
var _visual_facing_last_image_id:int = 0
var _visual_facing_last_shader_id:int = -1

var _motion_visual_initialized:bool = false
var _motion_visual_last_position:Vector2 = Vector2.ZERO
var _motion_visual_direction:Vector2 = Vector2.RIGHT
var _motion_visual_strength:float = 0.0

var _motion_blur_ghost:Sprite2D = null
var _motion_blur_material:ShaderMaterial = null
var _motion_blur_strength:float = 0.0

# 性能：Shader 能力只在实际 Shader 资源变化时重新扫描源码，避免每单位每物理帧 code.find()。
var _visual_shader_cache_id:int = -1
var _visual_supports_motion_shader_cache:bool = false
var _visual_supports_flip_shader_cache:bool = false
# 性能：移动软体参数变化不足一个可见阈值时不重复向 RenderingServer 写同样/近似参数。
var _motion_shader_last_valid:bool = false
var _motion_shader_last_direction:Vector2 = Vector2.RIGHT
var _motion_shader_last_strength:float = -1.0
var _motion_shader_last_shape:Vector3 = Vector3(-1.0,-1.0,-1.0)

const MOTION_EPSILON_SQ:float = 0.000001

# 记录上一物理帧已经处理过的实体角色接触。
# 只在“新接触”的第一帧补一次 Hitbox 命中，避免贴着角色时每帧持续扣血。
var _physical_contact_ids:Dictionary = {}

# 大规模战斗性能模式由 World 自动启停；普通规模战斗完全保持原来的 CharacterBody2D 身体碰撞。
var _large_battle_performance_mode:bool = false
# V105：大规模战斗只降低纯视觉更新频率；状态机、伤害、移动、Area2D 命中仍保持完整 physics tick。
@export_range(1,6,1) var large_battle_visual_tick_divisor:int = 3
var _large_battle_original_collision_mask:int = 0
var _large_battle_original_max_slides:int = 4
var _large_battle_collision_state_captured:bool = false
# 角色之间不再交给 Physics 2D 做密集实体互撞后，由 World 空间网格提供轻量分离速度。
var _crowd_separation_velocity:Vector2 = Vector2.ZERO

# 功能：刷新当前人物视觉 Shader 的能力缓存；Shader 未变化时 O(1) 返回。
func _refresh_visual_shader_capability_cache() -> void:
	var shader:Shader = null
	if image != null and is_instance_valid(image):
		var canvas_item := image as CanvasItem
		if canvas_item != null:
			var shader_material := canvas_item.material as ShaderMaterial
			if shader_material != null:
				shader = shader_material.shader

	var shader_id:int = shader.get_instance_id() if shader != null else 0
	if shader_id == _visual_shader_cache_id:
		return

	_visual_shader_cache_id = shader_id
	_motion_shader_last_valid = false
	if shader == null:
		_visual_supports_motion_shader_cache = false
		_visual_supports_flip_shader_cache = false
		return

	var code:String = shader.code
	_visual_supports_motion_shader_cache = code.find("motion_params") >= 0
	_visual_supports_flip_shader_cache = code.find("sprite_flip_h") >= 0


func _setup_motion_blur_ghost() -> void:
	if _motion_blur_ghost != null and is_instance_valid(_motion_blur_ghost):
		return
	if Type != Ball_Type.Ball or image == null or not is_instance_valid(image):
		return
	_motion_blur_material = ShaderMaterial.new()
	_motion_blur_material.shader = BALL_MOTION_BLUR_SHADER
	_motion_blur_ghost = Sprite2D.new()
	_motion_blur_ghost.name = "MotionBlurLayer"
	_motion_blur_ghost.material = _motion_blur_material
	_motion_blur_ghost.visible = false
	_motion_blur_ghost.z_as_relative = true
	_motion_blur_ghost.z_index = 1
	graphics.add_child(_motion_blur_ghost)
	_sync_motion_blur_source()


func _sync_motion_blur_source() -> void:
	if _motion_blur_ghost == null or not is_instance_valid(_motion_blur_ghost) or image == null or not is_instance_valid(image):
		return
	# 方向模糊层始终只复制当前人物“当前帧”，不保存历史位置；它不是残影系统。
	# MotionBlurLayer 与 image 同为 Graphics 的直接子节点，复制局部 transform 最稳定，
	# 避免 global_transform 在父节点缩放/镜像变化时产生一帧重算偏差。
	if image is Node2D:
		_motion_blur_ghost.transform = (image as Node2D).transform
	_motion_blur_ghost.modulate = image.modulate
	_motion_blur_ghost.self_modulate = image.self_modulate
	_motion_blur_ghost.z_index = image.z_index + 1
	_motion_blur_ghost.texture_filter = image.texture_filter
	_motion_blur_ghost.texture_repeat = image.texture_repeat

	# Shader 必须只在当前帧自己的 UV 范围内采样。
	# 对 hframes/vframes 图集尤其重要，否则横向模糊会采到隔壁帧，
	# 看起来就像叠了一张反方向/另一动作的人物。
	var frame_uv_min:Vector2 = Vector2.ZERO
	var frame_uv_max:Vector2 = Vector2.ONE

	if image is Sprite2D:
		var source := image as Sprite2D
		_motion_blur_ghost.texture = source.texture
		# 方向模糊层使用 Sprite2D 自己的原生 flip_h 复制最终朝向。
		# 原人物仍可继续使用自己的 Shader sprite_flip_h；两者不会双重镜像。
		_motion_blur_ghost.flip_h = _visual_facing_flipped_h
		_motion_blur_ghost.flip_v = false
		_motion_blur_ghost.centered = source.centered
		_motion_blur_ghost.offset = source.offset
		_motion_blur_ghost.region_enabled = source.region_enabled
		_motion_blur_ghost.region_rect = source.region_rect
		_motion_blur_ghost.region_filter_clip_enabled = source.region_filter_clip_enabled
		_motion_blur_ghost.hframes = source.hframes
		_motion_blur_ghost.vframes = source.vframes
		_motion_blur_ghost.frame = source.frame

		if source.texture != null:
			var texture_size:Vector2 = Vector2(source.texture.get_size())
			if source.region_enabled and texture_size.x > 0.0 and texture_size.y > 0.0:
				var region_pos:Vector2 = source.region_rect.position
				var region_end:Vector2 = source.region_rect.position + source.region_rect.size
				frame_uv_min = Vector2(
					minf(region_pos.x,region_end.x) / texture_size.x,
					minf(region_pos.y,region_end.y) / texture_size.y
				)
				frame_uv_max = Vector2(
					maxf(region_pos.x,region_end.x) / texture_size.x,
					maxf(region_pos.y,region_end.y) / texture_size.y
				)
			else:
				var safe_hframes:int = maxi(source.hframes,1)
				var safe_vframes:int = maxi(source.vframes,1)
				var safe_frame:int = clampi(source.frame,0,safe_hframes * safe_vframes - 1)
				var frame_x:int = safe_frame % safe_hframes
				var frame_y:int = floori(float(safe_frame) / float(safe_hframes))
				frame_uv_min = Vector2(
					float(frame_x) / float(safe_hframes),
					float(frame_y) / float(safe_vframes)
				)
				frame_uv_max = Vector2(
					float(frame_x + 1) / float(safe_hframes),
					float(frame_y + 1) / float(safe_vframes)
				)
	elif image is AnimatedSprite2D:
		var source := image as AnimatedSprite2D
		_motion_blur_ghost.flip_h = _visual_facing_flipped_h
		_motion_blur_ghost.flip_v = false
		_motion_blur_ghost.centered = source.centered
		_motion_blur_ghost.offset = source.offset
		if source.sprite_frames != null and source.sprite_frames.has_animation(source.animation):
			_motion_blur_ghost.texture = source.sprite_frames.get_frame_texture(source.animation,source.frame)
		else:
			_motion_blur_ghost.texture = null
	else:
		_motion_blur_ghost.texture = null

	_motion_blur_ghost.set_instance_shader_parameter("frame_uv_min",frame_uv_min)
	_motion_blur_ghost.set_instance_shader_parameter("frame_uv_max",frame_uv_max)
	_motion_blur_ghost.set_instance_shader_parameter("tint_color",image_color)
	_motion_blur_ghost.set_instance_shader_parameter("tint_mix",clampf(image_color_mix,0.0,1.0))


func _set_motion_blur_values(direction_value:Vector2,speed_value:float,delta:float) -> void:
	if (
		not motion_blur_enabled
		or _large_battle_performance_mode
		or Type != Ball_Type.Ball
		or image == null
		or not is_instance_valid(image)
	):
		_motion_blur_strength = 0.0
		if _motion_blur_ghost != null and is_instance_valid(_motion_blur_ghost):
			_motion_blur_ghost.visible = false
		return

	var start_speed:float = maxf(motion_blur_start_speed,0.0)
	var full_speed:float = maxf(motion_blur_full_speed,start_speed + 1.0)
	var speed_ratio:float = clampf((speed_value - start_speed) / (full_speed - start_speed),0.0,1.0)
	var curved_strength:float = pow(speed_ratio,maxf(motion_blur_strength_curve,0.01))
	var target_strength:float = clampf(curved_strength * maxf(motion_blur_effect_strength,0.0),0.0,1.0)
	# 调参时允许强制固定 0~1 强度，-1 才恢复按真实速度自动计算。
	if motion_blur_force_strength >= 0.0:
		target_strength = clampf(motion_blur_force_strength,0.0,1.0)
	var blend:float = 1.0 - exp(-maxf(motion_blur_response,0.01) * maxf(delta,0.0))
	_motion_blur_strength = lerpf(_motion_blur_strength,target_strength,blend)
	if target_strength <= 0.0 and _motion_blur_strength < 0.015:
		_motion_blur_strength = 0.0

	# V410：静止/低速角色不再提前创建 MotionBlurLayer。第一次真正需要显示时再创建，
	# 创建发生在同一渲染更新内，因此可见效果、阈值和响应曲线完全不变。
	if _motion_blur_strength <= 0.01:
		if _motion_blur_ghost != null and is_instance_valid(_motion_blur_ghost):
			_motion_blur_ghost.visible = false
		return
	if _motion_blur_ghost == null or not is_instance_valid(_motion_blur_ghost):
		_setup_motion_blur_ghost()
	if _motion_blur_ghost == null or not is_instance_valid(_motion_blur_ghost):
		return

	_sync_motion_blur_source()
	var has_texture:bool = _motion_blur_ghost.texture != null
	_motion_blur_ghost.visible = has_texture and image.visible and _motion_blur_strength > 0.01
	if not _motion_blur_ghost.visible:
		return

	var local_motion_dir:Vector2 = direction_value
	if local_motion_dir.length_squared() <= MOTION_EPSILON_SQ:
		local_motion_dir = _motion_visual_direction if _motion_visual_direction.length_squared() > MOTION_EPSILON_SQ else Vector2.RIGHT
	else:
		local_motion_dir = local_motion_dir.normalized()

	# vertex 拉宽使用真实图片局部运动方向；角色自身旋转时先把世界方向转回图片局部空间。
	if image is Node2D:
		local_motion_dir = local_motion_dir.rotated(-(image as Node2D).global_rotation)
	if local_motion_dir.length_squared() <= MOTION_EPSILON_SQ:
		local_motion_dir = Vector2.RIGHT
	else:
		local_motion_dir = local_motion_dir.normalized()

	# 原生 flip_h 只反转纹理 U 轴，不应该反转几何“往哪边移动”。
	# 所以 V113 把 vertex 几何方向和 fragment UV 采样方向彻底拆开：
	# 几何仍按真实运动方向向前拉；只有 UV 方向在水平镜像时反转 X。
	var texture_sample_dir:Vector2 = local_motion_dir
	if _motion_blur_ghost.flip_h:
		texture_sample_dir.x = -texture_sample_dir.x
	if texture_sample_dir.length_squared() <= MOTION_EPSILON_SQ:
		texture_sample_dir = Vector2.RIGHT
	else:
		texture_sample_dir = texture_sample_dir.normalized()

	_motion_blur_ghost.set_instance_shader_parameter("blur_direction",local_motion_dir)
	_motion_blur_ghost.set_instance_shader_parameter("blur_uv_direction",texture_sample_dir)
	_motion_blur_ghost.set_instance_shader_parameter("blur_strength",_motion_blur_strength)
	_motion_blur_ghost.set_instance_shader_parameter("blur_pixels",lerpf(4.0,maxf(motion_blur_max_pixels,4.0),_motion_blur_strength))
	_motion_blur_ghost.set_instance_shader_parameter("blur_alpha",clampf(motion_blur_max_alpha,0.0,1.0))
	_motion_blur_ghost.set_instance_shader_parameter("forward_stretch",maxf(motion_blur_forward_stretch,0.0))
	_motion_blur_ghost.set_instance_shader_parameter("sample_spread",maxf(motion_blur_sample_spread,0.01))
	_motion_blur_ghost.set_instance_shader_parameter("core_sharpness",clampf(motion_blur_core_sharpness,0.0,1.0))


func _image_supports_motion_shader() -> bool:
	_refresh_visual_shader_capability_cache()
	return _visual_supports_motion_shader_cache


func _set_motion_shader_values(direction_value:Vector2,strength_value:float) -> void:
	if not _image_supports_motion_shader():
		return
	var safe_dir:Vector2 = direction_value
	if safe_dir.length_squared() <= MOTION_EPSILON_SQ:
		safe_dir = _motion_visual_direction if _motion_visual_direction.length_squared() > MOTION_EPSILON_SQ else Vector2.RIGHT
	else:
		safe_dir = safe_dir.normalized()

	# Shader 坐标是图片自己的局部坐标。角色图片若正在旋转（例如部分技能瞄准），
	# 先把世界移动方向转回图片局部空间，保证“屏幕向右移动”仍沿屏幕向右拉伸。
	var shader_dir:Vector2 = safe_dir
	if image is Node2D:
		shader_dir = safe_dir.rotated(-(image as Node2D).global_rotation)
	if shader_dir.length_squared() <= MOTION_EPSILON_SQ:
		shader_dir = Vector2.RIGHT
	else:
		shader_dir = shader_dir.normalized()

	var safe_strength:float = clampf(strength_value,0.0,1.0)
	var current_shape := Vector3(motion_stretch_amount,motion_squash_amount,motion_inertia_lean)
	var direction_changed:bool = not _motion_shader_last_valid or _motion_shader_last_direction.dot(shader_dir) < 0.9995
	var strength_changed:bool = not _motion_shader_last_valid or absf(_motion_shader_last_strength - safe_strength) >= 0.012
	# 强度回到 0 时必须发送最后一次归零，避免停在极小残余形变。
	if safe_strength <= 0.001 and _motion_shader_last_strength > 0.001:
		strength_changed = true
	var shape_changed:bool = not _motion_shader_last_valid or current_shape != _motion_shader_last_shape
	if not direction_changed and not strength_changed and not shape_changed:
		return

	image.set_instance_shader_parameter("motion_direction",shader_dir)
	image.set_instance_shader_parameter(
		"motion_params",
		Vector4(
			safe_strength,
			motion_stretch_amount,
			motion_squash_amount,
			motion_inertia_lean
		)
	)
	_motion_shader_last_valid = true
	_motion_shader_last_direction = shader_dir
	_motion_shader_last_strength = safe_strength
	_motion_shader_last_shape = current_shape


func _update_motion_inertia_visual(state:State,delta:float) -> void:
	if Type != Ball_Type.Ball or image == null:
		_set_motion_blur_values(_motion_visual_direction,0.0,delta)
		return

	if not _motion_visual_initialized:
		_motion_visual_initialized = true
		_motion_visual_last_position = global_position
		_set_motion_shader_values(_motion_visual_direction,0.0)
		_set_motion_blur_values(_motion_visual_direction,0.0,delta)
		return

	# V113：运动模糊必须按“画面实际移动”计算，而不是只按 Speed/方向意图猜。
	# 这样冲刺、击退、自定义 move_and_collide、特殊角色移动都能得到正确的方向模糊。
	var visual_velocity:Vector2 = Vector2.ZERO
	var travelled:Vector2 = global_position - _motion_visual_last_position
	if travelled.length() <= motion_visual_teleport_threshold and delta > 0.000001:
		visual_velocity = travelled / delta

	# authority 在刚出生/位置差分还没形成的第一帧允许用运动意图兜底；
	# 正常运行后始终以真实位置差分为准。
	if (
		is_multiplayer_authority()
		and visual_velocity.length_squared() <= 0.25
		and not dizziness
		and state in [State.Move,State.Attack,State.Hurt,State.Skill]
	):
		visual_velocity = direction * maxf(Speed,0.0) + Repel

	_motion_visual_last_position = global_position

	var speed_value:float = visual_velocity.length()
	if speed_value > 0.5:
		var target_dir:Vector2 = visual_velocity.normalized()
		var dir_blend:float = 1.0 - exp(-maxf(motion_direction_response,0.01) * maxf(delta,0.0))
		var mixed:Vector2 = _motion_visual_direction.lerp(target_dir,dir_blend)
		if mixed.length_squared() > MOTION_EPSILON_SQ:
			_motion_visual_direction = mixed.normalized()

		# sprite_flip_h 已经不再放在 MultiplayerSynchronizer 中同步。
		# 远端客户端直接用同步位置差分得到的真实屏幕运动方向更新朝向。
		if not is_multiplayer_authority() and absf(visual_velocity.x) > 0.5:
			var desired_flip_h:bool = (visual_velocity.x > 0.0) if dir_left else (visual_velocity.x <= 0.0)
			set_character_visual_flip_h(desired_flip_h)

	# V109 运动模糊独立于“移动软体拉伸”开关；关闭软体时仍可保留速度模糊。
	_set_motion_blur_values(_motion_visual_direction,speed_value,delta)

	var target_strength:float = 0.0
	if motion_stretch_enabled and speed_value > 0.5:
		target_strength = clampf(speed_value / maxf(motion_stretch_full_speed,1.0),0.0,1.0)
	var strength_blend:float = 1.0 - exp(-maxf(motion_stretch_response,0.01) * maxf(delta,0.0))
	_motion_visual_strength = lerpf(_motion_visual_strength,target_strength,strength_blend)
	if target_strength <= 0.0 and _motion_visual_strength < 0.001:
		_motion_visual_strength = 0.0
	_set_motion_shader_values(_motion_visual_direction,_motion_visual_strength)


func _image_supports_shader_horizontal_flip() -> bool:
	_refresh_visual_shader_capability_cache()
	return _visual_supports_flip_shader_cache


func _migrate_native_flip_to_shader() -> void:
	# V10：不仅人物，所有使用主 Shader 的 Sprite/AnimatedSprite 都禁用原生 flip_h。
	# 三角洲共用的“子弹.tscn”历史上 flip_h=true；在 V6+ UV 重映射 Shader 下会产生
	# 负绘制矩形与 REGION_RECT 裁切冲突，最终整颗子弹变透明。
	if not _image_supports_shader_horizontal_flip():
		return

	var inherited_flip:bool = false
	if image is Sprite2D:
		inherited_flip = (image as Sprite2D).flip_h
	elif image is AnimatedSprite2D:
		inherited_flip = (image as AnimatedSprite2D).flip_h

	set_character_visual_flip_h(inherited_flip)


func set_character_visual_flip_h(flipped:bool) -> void:
	# V411/V412：move() 在角色移动期间每个 physics tick 都会请求一次朝向。
	# 绝大多数帧朝向、Image 与 Shader 都没有变化；同值直接返回，避免重复 RenderingServer 写入。
	# 角色运行时换图/换 Shader 时即使朝向没变，也必须重新同步，所以快速路径同时校验资源身份。
	_refresh_visual_shader_capability_cache()
	var image_id:int = image.get_instance_id() if image != null and is_instance_valid(image) else 0
	if (
		_visual_facing_initialized
		and _visual_facing_flipped_h == flipped
		and _visual_facing_last_image_id == image_id
		and _visual_facing_last_shader_id == _visual_shader_cache_id
	):
		return
	_visual_facing_flipped_h = flipped
	_visual_facing_initialized = true
	_visual_facing_last_image_id = image_id
	_visual_facing_last_shader_id = _visual_shader_cache_id

	# V6：有软体 Shader 的人物绝不再用 Sprite2D.flip_h。
	# Godot 的原生 flip_h 会通过负宽度目标矩形完成镜像；与 fragment UV 重映射
	# 同时使用时容易让区域/裁切坐标变成反向。现在几何始终保持正向，
	# 仅在 Shader 最终 texture() 采样前镜像 X。
	var shader_flip_supported:bool = _image_supports_shader_horizontal_flip()

	if image is Sprite2D:
		var sprite := image as Sprite2D
		sprite.flip_v = false
		sprite.flip_h = false if shader_flip_supported else flipped
	elif image is AnimatedSprite2D:
		var animated_sprite := image as AnimatedSprite2D
		animated_sprite.flip_v = false
		animated_sprite.flip_h = false if shader_flip_supported else flipped

	if shader_flip_supported:
		image.set_instance_shader_parameter("sprite_flip_h",1.0 if flipped else 0.0)


func is_character_visual_flipped_h() -> bool:
	return _visual_facing_flipped_h


func _ensure_upright_character_visual() -> void:
	# 正常人物永远不允许纵向镜像。
	# 对 V6 Shader 人物，也持续确保原生 flip_h 为 false，防止角色脚本或同步残留值
	# 再次把绘制矩形变成负宽度。
	if image is Sprite2D:
		var sprite := image as Sprite2D
		if sprite.flip_v:
			sprite.flip_v = false
		if _image_supports_shader_horizontal_flip() and sprite.flip_h:
			sprite.flip_h = false
	elif image is AnimatedSprite2D:
		var animated := image as AnimatedSprite2D
		if animated.flip_v:
			animated.flip_v = false
		if _image_supports_shader_horizontal_flip() and animated.flip_h:
			animated.flip_h = false


# 功能：切换大规模战斗物理模式；只关闭“角色身体扫描角色身体”，墙体和 Hitbox/Hurtbox 仍照常工作。
func set_large_battle_performance_mode(enabled:bool) -> void:
	if Type != Ball_Type.Ball and Type != Ball_Type.Creature:
		_large_battle_performance_mode = false
		_crowd_separation_velocity = Vector2.ZERO
		return

	if not _large_battle_collision_state_captured:
		_large_battle_original_collision_mask = collision_mask
		_large_battle_original_max_slides = max_slides
		_large_battle_collision_state_captured = true

	_large_battle_performance_mode = enabled
	if enabled:
		# 通用运动模糊是每个角色额外一张 Sprite2D + Shader。大规模战斗隐藏这层，
		# 角色专属 AfterImage/技能特效不受影响；退出大规模模式后自动恢复按速度计算。
		_motion_blur_strength = 0.0
		if _motion_blur_ghost != null and is_instance_valid(_motion_blur_ghost):
			_motion_blur_ghost.visible = false
		# Layer 2 是项目当前角色身体/受击层。这里只从 CharacterBody2D 的移动扫描中去掉 Layer 2；
		# self_hitbox/self_hurtbox 自己的 collision layer/mask 不变，所以真实攻击与受伤检测不丢失。
		set_collision_mask_value(2,false)
		# 顶视角大规模模式下只需要墙体停止/一次滑动；减少一次 move_and_slide() 内的重复碰撞求解上限。
		max_slides = 1
		_physical_contact_ids.clear()

		# 单机没有任何远程 Peer 时，不让每个单位的 MultiplayerSynchronizer 继续进入内部处理。
		var synchronizer := get_node_or_null("MultiplayerSynchronizer") as MultiplayerSynchronizer
		if synchronizer != null and not multiplayer.has_multiplayer_peer():
			synchronizer.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		collision_mask = _large_battle_original_collision_mask
		max_slides = maxi(_large_battle_original_max_slides,1)
		_crowd_separation_velocity = Vector2.ZERO

		var synchronizer := get_node_or_null("MultiplayerSynchronizer") as MultiplayerSynchronizer
		if synchronizer != null:
			synchronizer.process_mode = Node.PROCESS_MODE_INHERIT


# 功能：返回当前角色是否正在使用大规模战斗轻量物理模式。
func is_large_battle_performance_mode() -> bool:
	return _large_battle_performance_mode


# 功能：接收 World 空间网格计算出的角色分离速度，避免关闭身体互撞后所有单位完全叠成一点。
func set_crowd_separation_velocity(value:Vector2) -> void:
	_crowd_separation_velocity = value if _large_battle_performance_mode else Vector2.ZERO


# V79 单人性能修复辅助：在没有多人 Peer 时禁用 MultiplayerSynchronizer，
# 避免单机对局中每个角色每帧都运行 41 个属性的脏检测。
# 多人时不调用此函数，Synchronizer 维持正常工作。
# set_large_battle_performance_mode() 仍负责大规模战斗时的动态切换。
func _apply_singleplayer_synchronizer_optimization() -> void:
	if multiplayer.has_multiplayer_peer():
		# 多人模式：由 set_large_battle_performance_mode 按需管理 Synchronizer。
		return
	var synchronizer := get_node_or_null("MultiplayerSynchronizer") as MultiplayerSynchronizer
	if synchronizer != null:
		synchronizer.process_mode = Node.PROCESS_MODE_DISABLED


# 功能：从角色真实根碰撞框估算世界空间分离半径，只用于 crowd separation，不参与攻击/受伤判定。
func get_crowd_separation_radius_world() -> float:
	if collision_shape_2d == null or not is_instance_valid(collision_shape_2d) or collision_shape_2d.shape == null:
		return 18.0

	var shape:Shape2D = collision_shape_2d.shape
	var world_scale:Vector2 = collision_shape_2d.global_scale.abs()

	if shape is RectangleShape2D:
		var rectangle := shape as RectangleShape2D
		var size_world:Vector2 = rectangle.size * world_scale
		return maxf(maxf(size_world.x,size_world.y) * 0.5,6.0)

	if shape is CircleShape2D:
		var circle := shape as CircleShape2D
		return maxf(circle.radius * maxf(world_scale.x,world_scale.y),6.0)

	if shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		var width_world:float = capsule.radius * 2.0 * world_scale.x
		var height_world:float = capsule.height * world_scale.y
		return maxf(maxf(width_world,height_world) * 0.5,6.0)

	return 18.0


# ============================================================
# V59：伞夫 / 堇紫泪滴只保留威胁框兼容挂载；不再改角色本体碰撞
# ============================================================
func _special_character_script_basename() -> String:
	var script_value:Variant = get_script()
	if script_value is Script:
		var path:String = (script_value as Script).resource_path
		if not path.is_empty():
			return path.get_file().get_basename()
	return str(name)


func uses_special_character_threat_overlay() -> bool:
	var base_name:String = _special_character_script_basename()
	if base_name in SPECIAL_CHARACTER_THREAT_OVERLAY_NAMES:
		return true
	var node_name:String = str(name)
	for target_name:String in SPECIAL_CHARACTER_THREAT_OVERLAY_NAMES:
		if target_name in node_name:
			return true
	return false


func _setup_special_character_threat_overlay() -> void:
	if not uses_special_character_threat_overlay():
		return
	if _special_character_threat_overlay != null and is_instance_valid(_special_character_threat_overlay):
		return
	var overlay:Node2D = SPECIAL_CHARACTER_THREAT_OVERLAY_SCRIPT.new() as Node2D
	if overlay == null:
		push_warning("威胁显示兼容层：无法为 %s 创建调试绘制节点" % str(name))
		return
	overlay.name = "SpecialCharacterThreatOverlayV57"
	add_child(overlay)
	overlay.call("setup",self)
	_special_character_threat_overlay = overlay


# V64：普通 CharacterBody2D 移动保持统一逻辑。
# 不再为伞夫/堇紫泪滴在共享 ball.move() 中增加“预判停下/切线绕行”等角色特判。
# 特殊角色与其他角色一样依靠 direction、move_and_slide() 和 when_collide() 的公共移动/碰撞链路。
func move(speed:float,delta:float):

	var effective_direction:Vector2 = player_control_direction if is_player_controlled() else direction
	if effective_direction != Vector2.ZERO and Type == Ball_Type.Ball:
		# 保留原项目 dir_left 的含义，但把真正的左右镜像交给 Shader。
		var desired_flip_h:bool = (effective_direction.x > 0.0) if dir_left else (effective_direction.x <= 0.0)
		set_character_visual_flip_h(desired_flip_h)

	# Speed <= 0 时不允许方向速度反向；仍保留技能主动写入 Repel 的击退。
	# normal_speed_value 保留原始 Speed 数值给 V185 落地起跳；move_speed 才是最后实际横向移动使用的数值。
	var normal_speed_value:float = maxf(speed,0.0)
	var move_speed:float = normal_speed_value
	# V129：普通角色基础移动统一为原来的 0.6 倍。
	# 放在公共 move() 最终位移层，所有继承 ball、并继续走公共移动链的角色都会一致生效；
	# 不改 Shooter / Creature，也不篡改 Speed 数值本身，避免影响以 Speed 作为机制参数的旧角色。
	if Type == Ball_Type.Ball:
		move_speed *= CHARACTER_BASE_MOVE_SPEED_MULTIPLIER
	velocity = _compose_external_directional_gravity_locomotion(
		effective_direction,
		normal_speed_value,
		move_speed,
		Repel
	)
	_last_requested_velocity = velocity

	# move_and_slide() 即使 velocity == 0，也会执行 safe_margin 的碰撞恢复。
	# 没有实际运动时完全不调用，Speed == 0 的角色因此不会被附近角色“吸走”。
	if velocity.length_squared() <= MOTION_EPSILON_SQ:
		velocity = Vector2.ZERO
		return

	# 先移动，再读取本次 move_and_slide() 产生的碰撞。
	move_and_slide()
	_process_external_directional_gravity_locomotion_collisions()

	# 高速角色可能先被 CharacterBody2D 实体碰撞截停，
	# 导致同尺寸的 Hitbox/Hurtbox 没有机会真正进入重叠状态。
	#
	# 因此在这里把“实体角色接触”作为 Hitbox 的兜底触发源。
	# 必须放在 when_collide() 之前：
	# 牛等角色会在 when_collide() 内结束冲刺，如果晚一步计算，
	# 本次冲撞伤害会错误地读取到冲刺结束后的低 Speed。
	_process_physical_contact_hits()
	_process_wall_hit_bursts_from_slide_collisions(move_speed)

	# move_and_slide() 一帧可以产生多个 slide collision。不要只拿“最后一次”，
	# 否则角落/多角色挤压时，最后那个轻微接触会盖掉真正的主撞击。
	var collision := _select_primary_slide_collision(_last_requested_velocity)
	if collision != null:
		when_collide(move_speed,collision)
	else:
		_trigger_motion_change_fallback(_last_requested_velocity,move_speed)

func _process_physical_contact_hits() -> void:
	var current_contacts:Dictionary = {}

	for index in range(get_slide_collision_count()):
		var collision:KinematicCollision2D = get_slide_collision(index)
		if collision == null:
			continue

		var collider = collision.get_collider()
		if not collider is ball:
			continue

		var other:ball = collider
		var other_id:int = other.get_instance_id()
		current_contacts[other_id] = true

		# 已经在上一物理帧接触，不重复触发。
		if _physical_contact_ids.has(other_id):
			continue

		# 自己 -> 对方。
		# 这里只是 CharacterBody2D 实体接触的“被碰撞体截停前命中兜底”，
		# 因此必须遵守 Has_Collision_Damage。主动技能直接调用 try_hit_hurtbox() 不走这里。
		if (
			has_collision_damage()
			and self_hitbox != null
			and other.self_hurtbox != null
			and self_hitbox.has_method("try_hit_hurtbox")
		):
			self_hitbox.try_hit_hurtbox(other.self_hurtbox)

		# 对方 -> 自己。
		# 原本两个 Area2D 真正重叠时双方 Hitbox 都有机会触发，
		# 实体碰撞兜底也保持同样的双向接触语义。
		if (
			other.has_collision_damage()
			and other.self_hitbox != null
			and self_hurtbox != null
			and other.self_hitbox.has_method("try_hit_hurtbox")
		):
			other.self_hitbox.try_hit_hurtbox(self_hurtbox)

	_physical_contact_ids = current_contacts

func stand(delta:float):
	# Stand 状态只有显式 Repel 才允许发生位移。
	# hitbox/hurtbox 是 Area2D，不调用 move_and_slide() 也仍可正常攻击/受伤。
	velocity = Repel + _crowd_separation_velocity
	_last_requested_velocity = velocity
	if velocity.length_squared() <= MOTION_EPSILON_SQ:
		velocity = Vector2.ZERO
		# 自己不再执行实体移动时，清掉上一帧接触缓存。
		# 以后重新运动并再次撞上同一个角色时可以正常再次命中。
		_physical_contact_ids.clear()
		return

	var knockback_speed:float = velocity.length()
	var knockback_dir:Vector2 = velocity.normalized() if knockback_speed > 0.0001 else Vector2.ZERO
	move_and_slide()
	_process_external_directional_gravity_locomotion_collisions()
	_process_physical_contact_hits()
	_process_wall_hit_bursts_from_slide_collisions(knockback_speed)

	# Stand/Hurt 中由 Repel 推动的角色以前不会经过 when_collide()，
	# 所以同样的反弹有时没有声音、也没有视觉反馈。这里补齐反馈，
	# 但不改角色本身 direction，避免击退碰墙后破坏原本 AI 朝向。
	var collision := _select_primary_slide_collision(_last_requested_velocity)
	if collision != null:
		if not _is_external_gravity_quiet_support_collision(collision):
			var impact_power:float = _calculate_collision_impact_power(collision,knockback_speed)
			_trigger_collision_feedback(knockback_dir,impact_power,collision)
	else:
		_trigger_motion_change_fallback(_last_requested_velocity,knockback_speed)

func AfterImage() -> void:
	# 兼容手动调用：无论当前 Render Mode 是否是 Stretch Only，手动调用都生成一张快照。
	if image == null or not is_instance_valid(image):
		return
	var trail_dir:Vector2 = _motion_visual_direction if Type == Ball_Type.Ball else Vector2.RIGHT.rotated(global_rotation - Default_Rotation)
	if trail_dir.length_squared() <= MOTION_EPSILON_SQ:
		trail_dir = direction if direction.length_squared() > MOTION_EPSILON_SQ else Vector2.RIGHT
	_spawn_after_image_at_transform(image.global_transform,trail_dir.normalized())


# Fast path for a plain Sprite2D visual leaf (physics attachments are excluded). The caller overwrites the material and every
# after-image instance uniform, so copying the source shader state is wasted work.
# Preserve all native stored properties; fall back for scripts, children, metadata,
# groups, packed-scene roots or persistent signal connections (duplicate semantics).
static var _snapshot_sprite_properties:Array[StringName] = []
static var _snapshot_sprite_signals:Array[StringName] = []

# 视觉快照不能把插箭/受击区等物理子树复制成新战斗实体。
# 保留已有装饰子节点的兼容路径；纯贴图+插箭仍可走轻量 Sprite 快照。
func _has_snapshot_visual_children(source:Node) -> bool:
	for child:Node in source.get_children(true):
		if not child is CollisionObject2D: return true
	return false
func _strip_snapshot_physics_children(snapshot:Node) -> void:
	for child:Node in snapshot.get_children(true):
		if child is CollisionObject2D:
			# 必须在 add_child 到场景之前清理，不能先触发复制箭的 _ready/分组/监控。
			child.free()
		else:
			_strip_snapshot_physics_children(child)

func _make_plain_sprite_snapshot(source:Sprite2D) -> Sprite2D:
	if (
		source.get_script() != null
		or _has_snapshot_visual_children(source)
		or not source.scene_file_path.is_empty()
		or not source.get_meta_list().is_empty()
		or not source.get_groups().is_empty()
	):
		return null
	if _snapshot_sprite_signals.is_empty():
		for info:Dictionary in source.get_signal_list():
			_snapshot_sprite_signals.append(StringName(info["name"]))
	for signal_name:StringName in _snapshot_sprite_signals:
		if not Signal(source,signal_name).has_connections():
			continue
		for connection:Dictionary in source.get_signal_connection_list(signal_name):
			if (int(connection["flags"]) & CONNECT_PERSIST) != 0:
				return null
	if _snapshot_sprite_properties.is_empty():
		for info:Dictionary in source.get_property_list():
			var property_name:String = str(info["name"])
			if (int(info["usage"]) & PROPERTY_USAGE_STORAGE) == 0:
				continue
			if property_name == "script" or property_name == "material" or property_name.begins_with("instance_shader_parameters/"):
				continue
			_snapshot_sprite_properties.append(StringName(property_name))
	var sprite:Sprite2D = Sprite2D.new()
	for property_name:StringName in _snapshot_sprite_properties:
		sprite.set(property_name,source.get(property_name))
	sprite.set_multiplayer_authority(source.get_multiplayer_authority(),false)
	return sprite


func _make_after_image_snapshot_visual(texture:Texture2D) -> Node2D:
	if texture == null:
		return null

	if AfterImage_Texture_Source == AfterImage_Texture_Mode.Custom_Texture and AfterImage_Custom_Texture != null:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		_configure_after_image_sprite_layout(sprite)
		return sprite

	if image is Sprite2D:
		var plain_snapshot:Sprite2D = _make_plain_sprite_snapshot(image as Sprite2D)
		if plain_snapshot != null:
			return plain_snapshot
	var duplicated := image.duplicate() as Node2D
	if duplicated != null: _strip_snapshot_physics_children(duplicated)
	return duplicated


# 子类可以按“每一张快照”的世界变换决定残影颜色。
# 默认仍使用 Inspector 中的开头/结尾颜色，因此不会改变其他角色。
func _get_after_image_snapshot_colors(_ghost_transform:Transform2D) -> Dictionary:
	return {
		"start": AfterImage_Tint,
		"end": AfterImage_End_Tint,
	}


func _spawn_after_image_at_transform(ghost_transform:Transform2D,world_trail_dir:Vector2) -> void:
	if image == null or not is_instance_valid(image) or not image.visible:
		return
	var world = get_tree().current_scene
	if world == null:
		return

	var texture := _get_current_after_image_texture()
	if texture == null:
		return
	var new_image := _make_after_image_snapshot_visual(texture)
	if new_image == null:
		return

	if new_image is CanvasItem:
		var ghost_item := new_image as CanvasItem
		var snapshot_colors:Dictionary = _get_after_image_snapshot_colors(ghost_transform)
		var snapshot_start:Color = snapshot_colors.get("start",AfterImage_Tint)
		var snapshot_end:Color = snapshot_colors.get("end",AfterImage_End_Tint)
		ghost_item.material = AFTER_IMAGE_MATERIAL
		ghost_item.set_instance_shader_parameter("progress",0.0)
		ghost_item.set_instance_shader_parameter("trail_direction",Vector2.RIGHT)
		ghost_item.set_instance_shader_parameter("source_flip_h",1.0 if _visual_facing_flipped_h else 0.0)
		ghost_item.set_instance_shader_parameter("start_color",snapshot_start)
		ghost_item.set_instance_shader_parameter("end_color",snapshot_end)
		ghost_item.set_instance_shader_parameter(
			"visual_params_a",
			Vector4(AfterImage_Alpha,AfterImage_End_Alpha,AfterImage_Blur_Pixels,AfterImage_End_Blur_Pixels)
		)
		ghost_item.set_instance_shader_parameter(
			"visual_params_b",
			Vector4(AfterImage_Smear_Pixels,AfterImage_End_Smear_Pixels,AfterImage_Distortion_Pixels,AfterImage_End_Distortion_Pixels)
		)
		ghost_item.set_instance_shader_parameter("style_mode",int(AfterImage_Style))
		ghost_item.set_instance_shader_parameter("sample_count",clampi(AfterImage_Sample_Count,1,16))
		ghost_item.set_instance_shader_parameter("fade_mode",int(AfterImage_Fade))

		var local_trail_dir:Vector2 = world_trail_dir
		if local_trail_dir.length_squared() <= MOTION_EPSILON_SQ:
			local_trail_dir = Vector2.RIGHT
		local_trail_dir = local_trail_dir.normalized().rotated(-ghost_transform.get_rotation())
		ghost_item.set_instance_shader_parameter("trail_direction",local_trail_dir.normalized())

		ghost_item.modulate = image.modulate
		ghost_item.self_modulate = image.self_modulate
		ghost_item.z_as_relative = false
		ghost_item.z_index = image.z_index - 1

	if new_image is Sprite2D:
		(new_image as Sprite2D).flip_h = false
		(new_image as Sprite2D).flip_v = false
	elif new_image is AnimatedSprite2D:
		(new_image as AnimatedSprite2D).flip_h = false
		(new_image as AnimatedSprite2D).flip_v = false
		(new_image as AnimatedSprite2D).pause()

	new_image.name = Game.return_random_name(new_image)
	world.add_child(new_image)
	new_image.global_transform = _after_image_transform_for_texture(ghost_transform,texture)

	var base_scale:Vector2 = new_image.scale
	var safe_start_scale := Vector2(maxf(absf(AfterImage_Start_Scale.x),0.01),maxf(absf(AfterImage_Start_Scale.y),0.01))
	var safe_end_scale := Vector2(maxf(absf(AfterImage_End_Scale.x),0.01),maxf(absf(AfterImage_End_Scale.y),0.01))
	new_image.scale = Vector2(base_scale.x * safe_start_scale.x,base_scale.y * safe_start_scale.y)
	var target_scale := Vector2(base_scale.x * safe_end_scale.x,base_scale.y * safe_end_scale.y)

	var lifetime:float = maxf(AfterImage_Lifetime,0.05)
	var tween:Tween = new_image.create_tween().set_parallel(true)
	# progress 保持线性，让 Shader 负责颜色/Alpha/模糊/扭曲曲线。
	tween.tween_method(
		_set_after_image_shader_progress.bind(new_image as CanvasItem),
		0.0,
		1.0,
		lifetime
	).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	# 尺寸同样可以独立定义开头与结尾。
	tween.tween_property(new_image,"scale",target_scale,lifetime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.finished.connect(Callable(new_image,"queue_free"))


func _set_after_image_shader_progress(value:float,ghost:CanvasItem) -> void:
	if ghost != null and is_instance_valid(ghost):
		ghost.set_instance_shader_parameter("progress",value)


#死亡
#Die_next用来辅助Die播放死亡动画后调用关键帧造成真正死亡 
func Die() -> void:
	# V274：老死的死亡音已在 Game.report_combatant_death() 播放；消费标记避免随后进入 Die 再响一次。
	if bool(get_meta(WILD_DOG_OLD_AGE_AUDIO_PLAYED_META,false)):
		remove_meta(WILD_DOG_OLD_AGE_AUDIO_PLAYED_META)
		return
	if Unique_Death_Audio != null:
		play_unique_audio(Character_Audio_Slot.Death)
	elif Dead_Audio != "":
		Audios.play_sfx(Dead_Audio,{},true)
func Die_next() -> void:
	
	pass
#碰撞
func _select_primary_slide_collision(requested_velocity:Vector2) -> KinematicCollision2D:
	var count:int = get_slide_collision_count()
	if count <= 0:
		return null

	var best:KinematicCollision2D = null
	var best_score:float = -INF
	for index in range(count):
		var candidate:KinematicCollision2D = get_slide_collision(index)
		if candidate == null:
			continue
		var normal:Vector2 = candidate.get_normal().normalized()
		var relative_velocity:Vector2 = requested_velocity - candidate.get_collider_velocity()
		var closing_speed:float = maxf(-relative_velocity.dot(normal),0.0)
		# depth 只用于同帧多个碰撞时打破平局，不直接作为动画强度。
		var score:float = closing_speed + maxf(candidate.get_depth(),0.0) * 8.0
		if best == null or score > best_score:
			best = candidate
			best_score = score

	return best


func _trigger_motion_change_fallback(requested_velocity:Vector2,fallback_speed:float) -> void:
	# 极少数挤压/恢复场景里，move_and_slide() 会明显修改 velocity，
	# 但 slide collision 列表可能没有留下适合做主碰撞的记录。
	# 用“请求速度 vs 实际保留速度”的变化作为最后兜底，只补反馈，不改 AI direction。
	if requested_velocity.length_squared() <= MOTION_EPSILON_SQ:
		return
	# V189：没有 slide collision 的 safe-margin 支撑恢复也可能把一小段重力轴速度消掉。
	# 角色已经处于定向重力落地状态时，这种低速变化不是新撞击，不应反复播脚步/形变。
	if _external_directional_gravity_locomotion_enabled and _external_directional_gravity_grounded:
		var gravity:Vector2 = get_external_directional_gravity()
		if gravity.length_squared() > 0.000001:
			var gravity_axis_speed:float = requested_velocity.dot(gravity.normalized())
			if gravity_axis_speed > 0.0 and gravity_axis_speed <= 32.0:
				return
	var velocity_change:Vector2 = requested_velocity - velocity
	var threshold:float = maxf(8.0,requested_velocity.length() * 0.08)
	if velocity_change.length() < threshold:
		return
	_trigger_collision_feedback(
		requested_velocity.normalized(),
		maxf(velocity_change.length(),maxf(fallback_speed,0.0) * 0.35),
		null
	)


func _calculate_collision_impact_power(collision:KinematicCollision2D,fallback_speed:float) -> float:
	if collision == null:
		return maxf(fallback_speed,0.0)

	var normal:Vector2 = collision.get_normal().normalized()
	var requested_velocity:Vector2 = _last_requested_velocity
	if requested_velocity.length_squared() <= MOTION_EPSILON_SQ:
		requested_velocity = direction.normalized() * maxf(fallback_speed,0.0) if direction.length_squared() > MOTION_EPSILON_SQ else Vector2.ZERO

	# 使用 Godot 实际报告的 collider velocity，而不是用“角色 Speed * direction”猜测。
	# 只取沿碰撞法线互相接近的速度，擦边碰撞自然更轻。
	var relative_velocity:Vector2 = requested_velocity - collision.get_collider_velocity()
	var closing_speed:float = maxf(-relative_velocity.dot(normal),0.0)

	# 某些 safe-margin / 挤压恢复碰撞的法线速度接近 0，但它仍是一次真实接触。
	# 给一个小的 fallback，避免出现“明明弹开了却完全没动画”。
	if closing_speed < 1.0:
		closing_speed = maxf(requested_velocity.length() * 0.35,maxf(fallback_speed,0.0) * 0.35)

	return closing_speed


func _is_wall_like_collision(collision:KinematicCollision2D) -> bool:
	if collision == null:
		return false
	var collider:Variant = collision.get_collider()
	if collider == null or collider == self or collider is ball:
		return false
	# 当前地图碰撞来自 TileMapLayer；同时兼容普通静态墙和可动画移动墙。
	if collider is TileMapLayer or collider is StaticBody2D or collider is AnimatableBody2D:
		return true
	# 给以后特殊墙体留一个显式 opt-in，不把其它角色/投射物误判成墙。
	if collider is Object and (collider as Object).has_meta("wall_hit_surface"):
		return bool((collider as Object).get_meta("wall_hit_surface"))
	return false


func _is_external_gravity_quiet_support_collision(collision:KinematicCollision2D) -> bool:
	# V189：Sans 定向重力把某个墙面当作“地面”后，角色会持续与该面保持支撑接触。
	# move_and_slide() 仍可能逐帧报告这个接触，但它不是一次新的撞击，不能重复播放脚步声/碰撞形变/白线。
	# 只抑制“沿重力地面法线、且法向接近速度很低”的支撑接触；真正高速落地仍正常反馈。
	if collision == null or not _external_directional_gravity_locomotion_enabled:
		return false
	var gravity:Vector2 = get_external_directional_gravity()
	if gravity.length_squared() <= 0.000001:
		return false
	var normal:Vector2 = collision.get_normal()
	if normal.length_squared() <= MOTION_EPSILON_SQ:
		return false
	normal = normal.normalized()
	var gravity_dir:Vector2 = gravity.normalized()
	if normal.dot(-gravity_dir) <= 0.55:
		return false
	var relative_velocity:Vector2 = _last_requested_velocity - collision.get_collider_velocity()
	var closing_speed:float = maxf(-relative_velocity.dot(normal),0.0)
	# 32px/s 足以覆盖标准重力在一两个 physics tick 内重新产生的贴墙压力，
	# 同时不会吞掉真正的砸墙/高速落地撞击。
	return closing_speed <= 32.0


func _wall_contact_key(collision:KinematicCollision2D) -> int:
	if collision == null:
		return 0
	var collider:Variant = collision.get_collider()
	var collider_id:int = 0
	if collider is Object and is_instance_valid(collider):
		collider_id = int((collider as Object).get_instance_id())

	# 同一个 TileMapLayer 可能同时拥有四个方向的墙面，因此把量化后的法线也放进 key。
	# 这样墙角从横墙切到竖墙时仍能正确产生新的撞击反馈。
	var normal:Vector2 = collision.get_normal()
	if normal.length_squared() <= MOTION_EPSILON_SQ:
		normal = Vector2.RIGHT
	normal = normal.normalized()
	var nx:int = int(round(normal.x * 16.0)) + 17
	var ny:int = int(round(normal.y * 16.0)) + 17
	return collider_id ^ (nx * 73856093) ^ (ny * 19349663)


func _process_wall_hit_bursts_from_slide_collisions(fallback_speed:float) -> void:
	# 主碰撞有时会被角色实体接触占据；墙面反馈单独从本帧全部 slide collision
	# 中选最强的一次，保证“同时撞人 + 撞墙”仍然看得到墙被打中的线条。
	var best_collision:KinematicCollision2D = null
	var best_power:float = -1.0
	for index:int in range(get_slide_collision_count()):
		var candidate:KinematicCollision2D = get_slide_collision(index)
		if candidate == null or not _is_wall_like_collision(candidate):
			continue
		# 定向重力下持续压在“地面墙”上的支撑接触不是新撞击，不喷白线。
		if _is_external_gravity_quiet_support_collision(candidate):
			continue
		var candidate_power:float = _calculate_collision_impact_power(candidate,fallback_speed)
		if best_collision == null or candidate_power > best_power:
			best_collision = candidate
			best_power = candidate_power

	var physics_frame:int = Engine.get_physics_frames()
	if best_collision == null:
		# 至少完整离开一个物理帧后才解除“仍贴着这面墙”的锁。
		# 不在当前帧立刻清掉，避免同一帧的另一段移动流程误判成重新撞墙。
		if physics_frame > _active_wall_contact_last_frame + 1:
			_active_wall_contact_key = 0
		return

	var contact_key:int = _wall_contact_key(best_collision)
	var is_continuous_contact:bool = (
		contact_key != 0
		and contact_key == _active_wall_contact_key
		and physics_frame <= _active_wall_contact_last_frame + 1
	)
	_active_wall_contact_key = contact_key
	_active_wall_contact_last_frame = physics_frame

	# 按住方向一直顶墙不是一连串新的撞击。旧实现每物理帧生成一组白线，
	# 会让动画互相覆盖，看起来既不丝滑又像“上一组被新一组清掉”。
	if is_continuous_contact:
		return

	_try_wall_hit_burst_from_collision(best_collision,best_power)


func _finite_wall_surface_projection(collision:KinematicCollision2D,surface_normal:Vector2) -> Dictionary:
	# StaticBody2D / AnimatableBody2D 在项目里不只有地图墙，也包含棋子、阵石、矿工石头、
	# 投资者柱、影子实体等“有真实有限尺寸”的角色造物。碰撞白线必须受这些物体自己的
	# CollisionShape2D 尺寸约束，而不能一律按无限墙面处理。
	if collision == null:
		return {}
	var collider:Variant = collision.get_collider()
	if not (collider is StaticBody2D or collider is AnimatableBody2D):
		return {}
	if not (collider is CollisionObject2D) or not is_instance_valid(collider):
		return {}

	var shape_object:Variant = collision.get_collider_shape()
	if not (shape_object is Shape2D):
		return {}
	var shape:Shape2D = shape_object as Shape2D

	var normal:Vector2 = surface_normal
	if normal.length_squared() <= MOTION_EPSILON_SQ:
		normal = Vector2.RIGHT
	normal = normal.normalized()
	var tangent:Vector2 = Vector2(-normal.y,normal.x)

	var collision_object:CollisionObject2D = collider as CollisionObject2D
	var shape_transform:Transform2D = collision_object.global_transform
	var shape_index:int = collision.get_collider_shape_index()
	var owner_id:int = collision_object.shape_find_owner(shape_index)
	if owner_id >= 0:
		shape_transform = shape_transform * collision_object.shape_owner_get_transform(owner_id)

	var min_projection:float = INF
	var max_projection:float = -INF

	if shape is CircleShape2D:
		# 非等比缩放后的圆会成为椭圆。直接投影两条 basis，可得到该方向上的真实半径。
		var circle := shape as CircleShape2D
		var projected_radius:float = circle.radius * sqrt(
			pow(shape_transform.x.dot(tangent),2.0)
			+ pow(shape_transform.y.dot(tangent),2.0)
		)
		var circle_center_projection:float = shape_transform.origin.dot(tangent)
		min_projection = circle_center_projection - projected_radius
		max_projection = circle_center_projection + projected_radius
	elif shape is RectangleShape2D:
		var rectangle := shape as RectangleShape2D
		var rect_half_projection:float = (
			absf(shape_transform.x.dot(tangent)) * rectangle.size.x * 0.5
			+ absf(shape_transform.y.dot(tangent)) * rectangle.size.y * 0.5
		)
		var rect_center_projection:float = shape_transform.origin.dot(tangent)
		min_projection = rect_center_projection - rect_half_projection
		max_projection = rect_center_projection + rect_half_projection
	elif shape is CapsuleShape2D:
		# 胶囊的包围尺寸就是 2r × height；用投影后的包围尺寸作为稳定上限。
		var capsule := shape as CapsuleShape2D
		var capsule_size := Vector2(capsule.radius * 2.0,capsule.height)
		var capsule_half_projection:float = (
			absf(shape_transform.x.dot(tangent)) * capsule_size.x * 0.5
			+ absf(shape_transform.y.dot(tangent)) * capsule_size.y * 0.5
		)
		var capsule_center_projection:float = shape_transform.origin.dot(tangent)
		min_projection = capsule_center_projection - capsule_half_projection
		max_projection = capsule_center_projection + capsule_half_projection
	elif shape is ConvexPolygonShape2D:
		var polygon := shape as ConvexPolygonShape2D
		for point:Vector2 in polygon.points:
			var projection:float = (shape_transform * point).dot(tangent)
			min_projection = minf(min_projection,projection)
			max_projection = maxf(max_projection,projection)
	elif shape is SegmentShape2D:
		var segment := shape as SegmentShape2D
		var projection_a:float = (shape_transform * segment.a).dot(tangent)
		var projection_b:float = (shape_transform * segment.b).dot(tangent)
		min_projection = minf(projection_a,projection_b) - 0.5
		max_projection = maxf(projection_a,projection_b) + 0.5
	else:
		# 其它 Shape2D（例如 ConcavePolygonShape2D）用 Shape2D.get_rect() 的四角投影兜底。
		# get_rect() 是 Godot 提供的形状边界，不依赖角色脚本自己写额外 metadata。
		var shape_rect:Rect2 = shape.get_rect()
		var corners:Array[Vector2] = [
			shape_rect.position,
			shape_rect.position + Vector2(shape_rect.size.x,0.0),
			shape_rect.end,
			shape_rect.position + Vector2(0.0,shape_rect.size.y),
		]
		for corner:Vector2 in corners:
			var projection:float = (shape_transform * corner).dot(tangent)
			min_projection = minf(min_projection,projection)
			max_projection = maxf(max_projection,projection)

	if min_projection == INF or max_projection == -INF:
		return {}
	var width:float = max_projection - min_projection
	if is_nan(width) or is_inf(width) or width <= 0.01:
		return {}
	return {
		"tangent":tangent,
		"min_projection":min_projection,
		"max_projection":max_projection,
		"width":maxf(width,1.0),
	}


func _resolve_wall_hit_visual_position(collision:KinematicCollision2D,visual_width:float = -1.0) -> Vector2:
	var raw_point:Vector2 = collision.get_position()

	# 对所有有有限 CollisionShape2D 的 StaticBody2D / AnimatableBody2D 自动使用真实碰撞面。
	# 不再只给棋子写特例：阵石、矿工石头、投资者柱、影子实体以及以后新增的同类角色造物
	# 都会自动把白线限制在自己的实际碰撞宽度内。
	var finite_surface:Dictionary = _finite_wall_surface_projection(collision,collision.get_normal())
	if not finite_surface.is_empty():
		var tangent:Vector2 = finite_surface["tangent"]
		var min_projection:float = float(finite_surface["min_projection"])
		var max_projection:float = float(finite_surface["max_projection"])
		var surface_width:float = float(finite_surface["width"])
		var resolved_width:float = visual_width
		if resolved_width <= 0.0:
			resolved_width = minf(_estimate_wall_impact_cross_section(collision.get_normal()),surface_width)
		resolved_width = clampf(resolved_width,1.0,surface_width)

		# 白线是围绕中心向两边铺开的，所以把中心也限制到“留出半条白线后”的表面范围内。
		# 这样即使撞在小物体边缘/角上，白线也不会从实际棋子或障碍物轮廓之外冒出来。
		var half_width:float = resolved_width * 0.5
		var low:float = min_projection + half_width
		var high:float = max_projection - half_width
		var raw_projection:float = raw_point.dot(tangent)
		var target_projection:float = (min_projection + max_projection) * 0.5
		if low <= high:
			target_projection = clampf(raw_projection,low,high)
		return raw_point + tangent * (target_projection - raw_projection)

	# TileMapLayer 等真正连续墙面仍沿用原来的视觉居中逻辑。
	# get_position() 是真实的全局接触点，但大角色/墙角发生碰撞时，物理解算给出的单个
	# manifold 点可能落在接触区域的一侧，因此只沿墙面切线方向做有限修正。
	var normal:Vector2 = collision.get_normal()
	if normal.length_squared() <= MOTION_EPSILON_SQ:
		return raw_point
	normal = normal.normalized()

	if collision_shape_2d == null or not is_instance_valid(collision_shape_2d):
		return raw_point
	if collision_shape_2d.disabled or collision_shape_2d.shape == null:
		return raw_point

	var shape_center:Vector2 = collision_shape_2d.global_transform.origin
	var tangent:Vector2 = Vector2(-normal.y,normal.x)
	var tangent_delta:float = (shape_center - raw_point).dot(tangent)
	var mover_width:float = _estimate_wall_impact_cross_section(normal)
	var max_tangent_correction:float = clampf(mover_width * 0.5,2.0,24.0)
	tangent_delta = clampf(tangent_delta,-max_tangent_correction,max_tangent_correction)
	return raw_point + tangent * tangent_delta


func _try_wall_hit_burst_from_collision(collision:KinematicCollision2D,impact_power:float) -> void:
	if not _is_wall_like_collision(collision):
		return
	var incoming_direction:Vector2 = _last_requested_velocity
	if incoming_direction.length_squared() <= MOTION_EPSILON_SQ:
		incoming_direction = direction
	if incoming_direction.length_squared() <= MOTION_EPSILON_SQ:
		incoming_direction = -collision.get_normal()

	var normal:Vector2 = collision.get_normal()
	var visual_width:float = -1.0
	var finite_surface:Dictionary = _finite_wall_surface_projection(collision,normal)
	if not finite_surface.is_empty():
		# 白线最大只能覆盖“撞击者自身接触宽度”和“被撞有限物体宽度”两者中的较小值。
		# 因此大人物撞小棋子/小石头时不会再出现一整面墙宽的白线。
		visual_width = maxf(minf(
			_estimate_wall_impact_cross_section(normal),
			float(finite_surface["width"])
		),1.0)

	var collider:Variant = collision.get_collider()
	if collider is Object and is_instance_valid(collider):
		var collider_object:Object = collider as Object
		if collider_object.has_meta("wall_hit_visual_width"):
			var explicit_width:float = maxf(float(collider_object.get_meta("wall_hit_visual_width")),1.0)
			visual_width = explicit_width if visual_width <= 0.0 else minf(visual_width,explicit_width)

	var visual_impact_position:Vector2 = _resolve_wall_hit_visual_position(collision,visual_width)
	notify_wall_impact_feedback(
		visual_impact_position,
		normal,
		impact_power,
		visual_width,
		incoming_direction.normalized()
	)


func _estimate_wall_impact_cross_section(surface_normal:Vector2) -> float:
	# 取撞击物自身 CollisionShape2D 在“墙面切线方向”的投影宽度。
	# 这样子弹只影响很小一块墙面，大人物/大型投射物则覆盖更宽。
	if collision_shape_2d == null or not is_instance_valid(collision_shape_2d):
		return 10.0
	if collision_shape_2d.disabled or collision_shape_2d.shape == null:
		return 10.0

	var normal:Vector2 = surface_normal
	if normal.length_squared() <= MOTION_EPSILON_SQ:
		normal = Vector2.RIGHT
	normal = normal.normalized()
	var tangent:Vector2 = Vector2(-normal.y,normal.x)
	var shape:Shape2D = collision_shape_2d.shape
	var transform_value:Transform2D = collision_shape_2d.global_transform
	var axis_x:Vector2 = transform_value.x
	var axis_y:Vector2 = transform_value.y
	var width:float = 0.0

	if shape is RectangleShape2D:
		var rect := shape as RectangleShape2D
		var half_x:Vector2 = axis_x * (rect.size.x * 0.5)
		var half_y:Vector2 = axis_y * (rect.size.y * 0.5)
		width = 2.0 * (absf(half_x.dot(tangent)) + absf(half_y.dot(tangent)))
	elif shape is CircleShape2D:
		var circle := shape as CircleShape2D
		var projected_radius:float = circle.radius * sqrt(
			pow(axis_x.dot(tangent),2.0) + pow(axis_y.dot(tangent),2.0)
		)
		width = projected_radius * 2.0
	elif shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		var capsule_size := Vector2(capsule.radius * 2.0,capsule.height)
		var half_x:Vector2 = axis_x * (capsule_size.x * 0.5)
		var half_y:Vector2 = axis_y * (capsule_size.y * 0.5)
		width = 2.0 * (absf(half_x.dot(tangent)) + absf(half_y.dot(tangent)))
	elif shape is ConvexPolygonShape2D:
		var polygon := shape as ConvexPolygonShape2D
		if not polygon.points.is_empty():
			var min_projection:float = INF
			var max_projection:float = -INF
			for point:Vector2 in polygon.points:
				var world_point:Vector2 = transform_value * point
				var projection:float = world_point.dot(tangent)
				min_projection = minf(min_projection,projection)
				max_projection = maxf(max_projection,projection)
			width = maxf(max_projection - min_projection,0.0)
	elif shape is SegmentShape2D:
		var segment := shape as SegmentShape2D
		var a:Vector2 = transform_value * segment.a
		var b:Vector2 = transform_value * segment.b
		width = absf((b - a).dot(tangent)) + 1.0
	else:
		# 其它 Shape2D 使用包围矩形的四角投影作为稳定兜底。
		var shape_rect:Rect2 = shape.get_rect()
		var corners:Array[Vector2] = [
			shape_rect.position,
			shape_rect.position + Vector2(shape_rect.size.x,0.0),
			shape_rect.end,
			shape_rect.position + Vector2(0.0,shape_rect.size.y),
		]
		var min_projection:float = INF
		var max_projection:float = -INF
		for corner:Vector2 in corners:
			var world_corner:Vector2 = transform_value * corner
			var projection:float = world_corner.dot(tangent)
			min_projection = minf(min_projection,projection)
			max_projection = maxf(max_projection,projection)
		width = maxf(max_projection - min_projection,0.0)

	return clampf(width if width > 0.0 else 10.0,2.0,96.0)


func notify_wall_impact_feedback(
	impact_position:Vector2,
	surface_normal:Vector2,
	impact_power:float,
	impact_width:float = -1.0,
	incoming_direction:Vector2 = Vector2.ZERO
) -> void:
	if not wall_hit_burst_enabled or not is_multiplayer_authority():
		return

	# 同一 physics frame 角落可能同时返回两条墙碰撞，只播一组线，避免视觉翻倍。
	var physics_frame:int = Engine.get_physics_frames()
	if physics_frame == _last_wall_hit_burst_physics_frame:
		return
	_last_wall_hit_burst_physics_frame = physics_frame

	var normal:Vector2 = surface_normal
	if normal.length_squared() <= MOTION_EPSILON_SQ:
		normal = -_last_requested_velocity.normalized() if _last_requested_velocity.length_squared() > MOTION_EPSILON_SQ else Vector2.RIGHT
	normal = normal.normalized()

	var incoming:Vector2 = incoming_direction
	if incoming.length_squared() <= MOTION_EPSILON_SQ:
		incoming = _last_requested_velocity
	if incoming.length_squared() <= MOTION_EPSILON_SQ:
		incoming = direction
	if incoming.length_squared() <= MOTION_EPSILON_SQ:
		incoming = -normal
	incoming = incoming.normalized()

	var scaled_power:float = maxf(impact_power,1.0) * maxf(wall_hit_burst_strength_scale,0.0)
	var resolved_width:float = impact_width
	if resolved_width <= 0.0:
		resolved_width = _estimate_wall_impact_cross_section(normal)
	resolved_width = clampf(resolved_width,2.0,96.0)
	var seed:int = Game.battle_rng_seed_or("classes/ball.gd:wall_hit_seed",int(get_instance_id()) ^ int(physics_frame * 1103515245))
	_play_wall_impact_feedback_local(impact_position,normal,scaled_power,resolved_width,seed,incoming)
	if multiplayer.has_multiplayer_peer():
		_remote_wall_impact_feedback.rpc(impact_position,normal,scaled_power,resolved_width,seed,incoming)


@rpc("authority","call_remote","reliable")
func _remote_wall_impact_feedback(
	impact_position:Vector2,
	surface_normal:Vector2,
	impact_power:float,
	impact_width:float,
	seed:int,
	incoming_direction:Vector2
) -> void:
	_play_wall_impact_feedback_local(impact_position,surface_normal,impact_power,impact_width,seed,incoming_direction)


func _play_wall_impact_feedback_local(
	impact_position:Vector2,
	surface_normal:Vector2,
	impact_power:float,
	impact_width:float,
	seed:int,
	incoming_direction:Vector2
) -> void:
	var parent:Node = get_tree().current_scene
	if parent == null:
		return
	WALL_HIT_BURST_SCRIPT.spawn(
		parent,
		impact_position,
		surface_normal,
		impact_power,
		impact_width,
		seed,
		incoming_direction
	)


#碰撞
func when_collide(speed:float,collision:KinematicCollision2D):
	if not is_multiplayer_authority():
		return
	# V189：重力把角色压在当前“地面墙”上时，这是持续支撑，不是每帧一次新碰撞。
	# 直接跳过可同时阻止脚步碰撞声、碰撞形变和方向反弹。真正落地的高速撞击不会被此条件吞掉。
	if _is_external_gravity_quiet_support_collision(collision):
		return

	var normal:Vector2 = collision.get_normal().normalized()
	var incoming_velocity:Vector2 = _last_requested_velocity
	var incoming_dir:Vector2 = incoming_velocity.normalized() if incoming_velocity.length_squared() > MOTION_EPSILON_SQ else (direction.normalized() if direction.length_squared() > MOTION_EPSILON_SQ else -normal)

	# 只有仍然朝碰撞面运动时才反弹，避免贴墙时方向来回翻转。
	if direction.dot(normal) < 0.0:
		direction = direction.bounce(normal).normalized()

	var collider = collision.get_collider()
	var suppress_bounce_audio:bool = false
	if collider is ball:
		var other_for_audio:ball = collider as ball
		# 任意一方的身体碰撞会真正结算伤害时，命中声由 _on_hitbox_on_hit()
		# 统一播放 Hit_Audio（默认 balls_hit1）。这里不再叠加随机“脚步”碰撞声。
		suppress_bounce_audio = has_collision_damage() or other_for_audio.has_collision_damage()

	var impact_power:float = _calculate_collision_impact_power(collision,speed)
	_trigger_collision_feedback(incoming_dir,impact_power,collision,suppress_bounce_audio)

	# CharacterBody2D 对两个都在移动的角色并不保证双方这一帧都会得到各自的
	# slide collision。主动方已经检测到实体角色碰撞时，也给被撞方补一次反馈。
	# 对方自己的碰撞若随后也触发，会被“同 physics frame 去重”合并，不会无限重复。
	if collider is ball:
		var other:ball = collider as ball
		if other != self and other.is_multiplayer_authority():
			other.notify_bounce_feedback(-incoming_dir,impact_power,null,suppress_bounce_audio)


func notify_bounce_feedback(
	impact_dir:Vector2,
	power:float,
	collision:KinematicCollision2D = null,
	suppress_audio:bool = false
) -> void:
	# 所有“会把角色方向弹开”的代码路径统一走这里。
	# authority 负责一次真实事件，再通过 RPC 让远端只播放表现。
	if not is_multiplayer_authority():
		return
	_trigger_collision_feedback(impact_dir,power,collision,suppress_audio)


func _trigger_collision_feedback(
	impact_dir:Vector2,
	power:float,
	collision:KinematicCollision2D = null,
	suppress_audio:bool = false
) -> void:
	# 只合并同一 physics frame 中由多个系统报告的同一次撞击。
	# 不再使用 25/45ms 冷却，否则高速角色连续两次真实反弹会被吞掉。
	var physics_frame:int = Engine.get_physics_frames()
	if physics_frame == _last_collision_feedback_physics_frame:
		return
	_last_collision_feedback_physics_frame = physics_frame

	var visual_power:float = maxf(power,collide_visual_min_power)
	_play_collision_feedback_local(impact_dir,visual_power,"",suppress_audio)

	# 反弹是离散事件，不能使用 unreliable。声音 + 动画合成一个 reliable RPC，
	# 远端要么一起收到，要么由可靠通道重传，避免“只有声/只有动画/整次丢失”。
	if multiplayer.has_multiplayer_peer():
		_remote_bounce_feedback.rpc(impact_dir,visual_power,Collide_Audio_Node,suppress_audio)

	if debug_collision_feedback:
		print("[CollisionFeedback] ",name," frame=",physics_frame," power=",power," slides=",get_slide_collision_count()," collider=",collision.get_collider() if collision != null else null)


func _play_collision_feedback_local(
	impact_dir:Vector2,
	visual_power:float,
	audio_node:String = "",
	suppress_audio:bool = false
) -> void:
	if not suppress_audio:
		if Unique_Collide_Audio != null:
			_play_unique_audio_local(Character_Audio_Slot.Collide,true)
		else:
			var node_name:String = audio_node if not audio_node.is_empty() else Collide_Audio_Node
			if not node_name.is_empty():
				Audios.play_sfx_from_node(node_name,{},true,true)
	Figure_collide_transform(impact_dir,visual_power)


@rpc("authority","call_remote","reliable")
func _remote_bounce_feedback(
	impact_dir:Vector2,
	visual_power:float,
	audio_node:String,
	suppress_audio:bool = false
) -> void:
	_play_collision_feedback_local(impact_dir,visual_power,audio_node,suppress_audio)


func _capture_collision_visual_base() -> void:
	# 保留旧字段兼容存档/脚本，但碰撞表现不再修改任何同步 Transform。
	_collision_visual_base = {}


# 特效等
var collide_tween:Tween
# V7.1：缓存打包后的 Shader 参数。Tween 只改 phase，不需要从 RenderingServer 反读参数。
var _bounce_shader_params_a:Vector4 = Vector4(1.0,0.0,0.34,0.20)
var _bounce_shader_params_b:Vector4 = Vector4(0.17,0.040,0.0,0.0)

func _collision_shader_supported() -> bool:
	if image == null or not is_instance_valid(image):
		return false
	var canvas_item := image as CanvasItem
	if canvas_item == null:
		return false
	var material := canvas_item.material as ShaderMaterial
	if material == null or material.shader == null:
		return false
	return material.shader.code.find("bounce_params_a") >= 0


func _set_collision_shader_phase(value:float) -> void:
	if image != null and is_instance_valid(image):
		_bounce_shader_params_a.x = clampf(value,0.0,1.0)
		image.set_instance_shader_parameter("bounce_params_a",_bounce_shader_params_a)


func _configure_impact_shader(
	dir:Vector2,
	strength:float,
	squash:float,
	bulge:float,
	rebound:float,
	wobble:float,
	recoil:float,
	tilt_degrees:float
) -> void:
	if image == null or not is_instance_valid(image):
		return

	# Shader 使用图片局部坐标；先把世界方向转换到图片局部。
	var shader_dir:Vector2 = dir
	if image is Node2D:
		shader_dir = dir.rotated(-(image as Node2D).global_rotation)
	if shader_dir.length_squared() <= MOTION_EPSILON_SQ:
		shader_dir = Vector2.RIGHT
	shader_dir = shader_dir.normalized()

	_bounce_shader_params_a = Vector4(
		0.0,
		clampf(strength,0.0,1.25),
		maxf(squash,0.0),
		maxf(bulge,0.0)
	)
	_bounce_shader_params_b = Vector4(
		maxf(rebound,0.0),
		maxf(wobble,0.0),
		maxf(recoil,0.0),
		deg_to_rad(maxf(tilt_degrees,0.0))
	)
	image.set_instance_shader_parameter("bounce_direction",shader_dir)
	image.set_instance_shader_parameter("bounce_params_a",_bounce_shader_params_a)
	image.set_instance_shader_parameter("bounce_params_b",_bounce_shader_params_b)


func _configure_collision_shader(dir:Vector2,strength:float) -> void:
	_configure_impact_shader(
		dir,
		strength,
		collide_visual_squash,
		collide_visual_stretch,
		collide_visual_rebound_overshoot,
		collide_visual_wobble,
		collide_visual_recoil,
		collide_visual_tilt_degrees
	)


func _reset_collision_shader() -> void:
	if image == null or not is_instance_valid(image):
		return
	_bounce_shader_params_a = Vector4(1.0,0.0,collide_visual_squash,collide_visual_stretch)
	_bounce_shader_params_b = Vector4(
		collide_visual_rebound_overshoot,
		collide_visual_wobble,
		collide_visual_recoil,
		deg_to_rad(collide_visual_tilt_degrees)
	)
	image.set_instance_shader_parameter("bounce_params_a",_bounce_shader_params_a)
	image.set_instance_shader_parameter("bounce_params_b",_bounce_shader_params_b)
	image.set_instance_shader_parameter("bounce_direction",Vector2.RIGHT)


func Figure_collide_transform(Dir:Vector2,Power:float) -> void:
	# V5：Tween 只推进一个 0→1 的 phase。
	# 真正的压扁、鼓起、回弹、余震全部由 Shader 用连续函数计算，
	# 不再把三个线性缩放阶段硬拼起来，因此高速连续撞击也更丝滑。
	if not When_Coliide_Tween or image == null:
		return
	if not _collision_shader_supported():
		return

	if collide_tween != null and collide_tween.is_valid():
		collide_tween.kill()

	var dir:Vector2 = Dir.normalized() if Dir.length_squared() > MOTION_EPSILON_SQ else Vector2.RIGHT
	var raw_strength:float = clampf(Power / maxf(collide_visual_full_power,1.0),0.0,1.0)
	# 低速碰撞也必须肉眼明显；高速则平滑接近 1，不无限增大。
	var strength:float = lerpf(clampf(collide_visual_min_strength,0.0,1.0),1.0,smoothstep(0.0,1.0,raw_strength))

	_configure_collision_shader(dir,strength)
	_set_collision_shader_phase(0.0)

	# 三个 Inspector 时间仍保留，方便继续调手感；Shader 内部按归一化 phase
	# 自动分配撞击/弹出/余震，不再逐段 Tween 多个参数。
	var total_time:float = maxf(
		collide_visual_in_time + collide_visual_rebound_time + collide_visual_return_time,
		0.08
	)
	collide_tween = create_tween().bind_node(self)
	collide_tween.tween_method(_set_collision_shader_phase,0.0,1.0,total_time).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	collide_tween.tween_callback(_reset_collision_shader)


func _is_ranged_hit_source(source:ball) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	return source.Type == Ball_Type.Shooter or source.Type == Ball_Type.Shooter_with_Health


func _play_ranged_hit_feedback_local(impact_dir:Vector2,strength:float) -> void:
	if not ranged_hit_feedback_enabled or image == null or not _collision_shader_supported():
		return

	if collide_tween != null and collide_tween.is_valid():
		collide_tween.kill()

	_configure_impact_shader(
		impact_dir,
		strength,
		ranged_hit_squash,
		ranged_hit_bulge,
		ranged_hit_rebound,
		ranged_hit_wobble,
		ranged_hit_recoil,
		ranged_hit_tilt_degrees
	)
	_set_collision_shader_phase(0.0)

	collide_tween = create_tween().bind_node(self)
	collide_tween.tween_method(
		_set_collision_shader_phase,
		0.0,
		1.0,
		maxf(ranged_hit_duration,0.05)
	).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_OUT)
	collide_tween.tween_callback(_reset_collision_shader)


@rpc("authority","call_remote","reliable")
func _remote_ranged_hit_feedback(impact_dir:Vector2,strength:float) -> void:
	_play_ranged_hit_feedback_local(impact_dir,strength)


func notify_ranged_hit_feedback(
	source:ball,
	raw_damage:float,
	health_loss:float,
	block_loss:float
) -> void:
	if not ranged_hit_feedback_enabled or source == null or not _is_ranged_hit_source(source):
		return
	if state_machine != null and state_machine.current_state == State.Die:
		return

	# 护盾吸收也算冲击，但权重略低；至少保留一小部分原始伤害，
	# 让“命中但被减伤/格挡”的远程攻击仍然有视觉反馈。
	var effective_impact:float = maxf(
		maxf(health_loss,0.0) + maxf(block_loss,0.0) * 0.65,
		maxf(raw_damage,0.0) * 0.20
	)
	if effective_impact <= 0.0:
		return

	var ratio:float = clampf(effective_impact / maxf(ranged_hit_full_damage,1.0),0.0,1.0)
	# sqrt 让中低伤害也能看见，高伤害再逐渐接近上限。
	var shaped:float = sqrt(ratio)
	var strength:float = lerpf(
		clampf(ranged_hit_min_strength,0.0,1.25),
		clampf(ranged_hit_max_strength,0.0,1.25),
		shaped
	)

	var impact_dir:Vector2 = source.direction
	if impact_dir.length_squared() <= MOTION_EPSILON_SQ:
		impact_dir = global_position - source.global_position
	if impact_dir.length_squared() <= MOTION_EPSILON_SQ:
		impact_dir = Vector2.RIGHT
	impact_dir = impact_dir.normalized()

	_play_ranged_hit_feedback_local(impact_dir,strength)
	if multiplayer.has_multiplayer_peer():
		_remote_ranged_hit_feedback.rpc(impact_dir,strength)



# ========================================================
# 通用受击爆射线特效
#
# 标准 Hitbox 命中和脚本位置伤害统一触发：
# - 射出方向：攻击来源 -> 受击者，即远离攻击来源。
# - 伤害越高：射程越远、线更长、扩散略收紧。
# - Hitbox 横向覆盖越宽：扩散越大、射程越短。
# - 人物正在白闪：所有线纯白。
# - 否则：每条线从人物贴图上的随机不透明像素产生，并读取该像素当前颜色。
# ========================================================
func _estimate_hit_effect_cross_section(source_hitbox:hitbox,travel_direction:Vector2) -> float:
	if source_hitbox == null or not is_instance_valid(source_hitbox):
		return 28.0

	if source_hitbox.has_meta("hit_effect_coverage_width"):
		var override_width:float = float(source_hitbox.get_meta("hit_effect_coverage_width"))
		if override_width > 0.0:
			return override_width

	var travel:Vector2 = travel_direction
	if travel.length_squared() <= 0.000001:
		travel = Vector2.RIGHT
	var tangent:Vector2 = Vector2(-travel.y,travel.x).normalized()
	var widest:float = 0.0

	for child:Node in source_hitbox.get_children():
		if not child is CollisionShape2D:
			continue
		var collision := child as CollisionShape2D
		if collision.shape == null or collision.disabled:
			continue

		var shape:Shape2D = collision.shape
		var width:float = 0.0
		var axis_x:Vector2 = collision.global_transform.x
		var axis_y:Vector2 = collision.global_transform.y

		if shape is RectangleShape2D:
			var rect := shape as RectangleShape2D
			var half_x:Vector2 = axis_x * (rect.size.x * 0.5)
			var half_y:Vector2 = axis_y * (rect.size.y * 0.5)
			width = 2.0 * (absf(half_x.dot(tangent)) + absf(half_y.dot(tangent)))
		elif shape is CircleShape2D:
			var circle := shape as CircleShape2D
			var projected_radius:float = circle.radius * sqrt(
				pow(axis_x.dot(tangent),2.0) + pow(axis_y.dot(tangent),2.0)
			)
			width = projected_radius * 2.0
		elif shape is CapsuleShape2D:
			var capsule := shape as CapsuleShape2D
			var capsule_size := Vector2(capsule.radius * 2.0,capsule.height)
			var half_x:Vector2 = axis_x * (capsule_size.x * 0.5)
			var half_y:Vector2 = axis_y * (capsule_size.y * 0.5)
			width = 2.0 * (absf(half_x.dot(tangent)) + absf(half_y.dot(tangent)))
		elif shape is ConvexPolygonShape2D:
			var polygon := shape as ConvexPolygonShape2D
			if not polygon.points.is_empty():
				var min_projection:float = INF
				var max_projection:float = -INF
				for point:Vector2 in polygon.points:
					var world_point:Vector2 = collision.global_transform * point
					var projection:float = world_point.dot(tangent)
					min_projection = minf(min_projection,projection)
					max_projection = maxf(max_projection,projection)
				width = maxf(max_projection - min_projection,0.0)
		elif shape is SegmentShape2D:
			var segment := shape as SegmentShape2D
			var a:Vector2 = collision.global_transform * segment.a
			var b:Vector2 = collision.global_transform * segment.b
			width = absf((b - a).dot(tangent)) + 2.0

		widest = maxf(widest,width)

	return maxf(widest,8.0) if widest > 0.0 else 28.0


func notify_hit_burst_feedback(
	source_position:Vector2,
	raw_damage:float,
	health_loss:float,
	block_loss:float,
	coverage_width:float,
	seed:int,
	incoming_direction:Vector2 = Vector2.ZERO
) -> void:
	# 顿挫只来自已确认的攻击命中，不从 health setter 触发，避免复制生命/技能自损误触发。
	var impact_world:Node = get_tree().current_scene
	if is_instance_valid(impact_world) and impact_world.has_method("request_heavy_hitstop"):
		impact_world.call("request_heavy_hitstop",health_loss,get_impact_reference_health(),global_position)
	if state_machine != null and state_machine.current_state == State.Die:
		return

	var effective_damage:float = maxf(
		maxf(health_loss,0.0) + maxf(block_loss,0.0) * 0.70,
		maxf(raw_damage,0.0) * 0.22
	)
	if effective_damage <= 0.0:
		return

	var force_white:bool = _hit_white_visual_power >= 0.5
	_play_hit_burst_feedback_local(
		source_position,
		effective_damage,
		maxf(coverage_width,1.0),
		seed,
		force_white,
		incoming_direction
	)

	if multiplayer.has_multiplayer_peer():
		_remote_hit_burst_feedback.rpc(
			source_position,
			effective_damage,
			maxf(coverage_width,1.0),
			seed,
			force_white,
			incoming_direction
		)


@rpc("authority","call_remote","reliable")
func _remote_hit_burst_feedback(
	source_position:Vector2,
	effective_damage:float,
	coverage_width:float,
	seed:int,
	force_white:bool,
	incoming_direction:Vector2
) -> void:
	_play_hit_burst_feedback_local(
		source_position,
		effective_damage,
		coverage_width,
		seed,
		force_white,
		incoming_direction
	)


func _play_hit_burst_feedback_local(
	source_position:Vector2,
	effective_damage:float,
	coverage_width:float,
	seed:int,
	force_white:bool,
	incoming_direction:Vector2
) -> void:
	if image == null or not is_instance_valid(image):
		return
	var parent:Node = get_tree().current_scene
	if parent == null:
		return

	# 人物受击恢复为“背后爆射”：白线从攻击穿过人物后的背侧出现，
	# 主方向跟随真实入射角度，而不是固定水平/垂直，也不是朝攻击者反喷。
	# 例如攻击方向为右上，则人物背侧白线也以右上为主轴，并在该角度附近扩散。
	var outward:Vector2 = incoming_direction
	if outward.length_squared() <= 0.000001:
		outward = global_position - source_position
	if outward.length_squared() <= 0.000001:
		if velocity.length_squared() > 0.000001:
			outward = velocity.normalized()
		elif direction.length_squared() > 0.000001:
			outward = direction.normalized()
		else:
			outward = Vector2.RIGHT
	outward = outward.normalized()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	# 受击表现同时看“实际伤害”和“命中横截面”。横截面会按当前角色尺寸归一化：
	# 子弹/刺击属于小覆盖，角色相撞/宽攻击属于大覆盖。
	var character_radius:float = _hit_burst_character_radius()
	var character_diameter:float = maxf(character_radius * 2.0,1.0)
	var coverage_start:float = character_diameter * 0.18
	var coverage_full:float = character_diameter * 1.10
	var coverage_ratio:float = clampf(
		(coverage_width - coverage_start) / maxf(coverage_full - coverage_start,1.0),
		0.0,
		1.0
	)

	# 伤害按角色生命尺度归一化，避免不同血量角色使用同一个固定伤害阈值。
	# 约 35% 最大生命的单次有效伤害会接近视觉强度上限。
	var damage_reference:float = maxf(get_impact_reference_health() * 0.35,24.0)
	var damage_ratio:float = clampf(effective_damage / damage_reference,0.0,1.0)
	var damage_shape:float = sqrt(damage_ratio)

	# 冲击密度：覆盖越小越容易集中；伤害越高，集中冲击的密度进一步提高。
	# 这个值主要影响线条数量和小范围命中的“扎实感”。
	var concentration_ratio:float = 1.0 - coverage_ratio
	var density_ratio:float = clampf(
		concentration_ratio * 0.58
		+ damage_shape * lerpf(0.34,0.20,coverage_ratio)
		+ damage_shape * concentration_ratio * 0.28,
		0.0,
		1.0
	)

	# 扩散规则：
	# - 小范围命中：伤害越高越收束，像子弹/刺击把冲击集中到一个方向。
	# - 大范围命中：伤害越高越铺开，但最大仍限制在 68 度。
	var base_spread_degrees:float = lerpf(9.0,54.0,coverage_ratio)
	var high_damage_spread_factor:float = lerpf(0.52,1.28,coverage_ratio)
	var spread_degrees:float = base_spread_degrees * lerpf(
		1.0,
		high_damage_spread_factor,
		damage_shape
	)
	spread_degrees = clampf(spread_degrees,4.0,68.0)

	# 射程仍严格以角色体型为基准。小范围高伤可以相对更“冲”，
	# 大范围攻击则更侧重铺开而不是飞远。
	var base_distance:float = character_radius * lerpf(0.72,2.05,damage_shape)
	base_distance *= lerpf(1.0,0.68,coverage_ratio)
	var min_distance:float = character_radius * 0.62
	var max_distance:float = minf(character_radius * 2.35,68.0)
	base_distance = clampf(base_distance,min_distance,max_distance)

	var base_length:float = character_radius * lerpf(0.26,0.72,damage_shape)
	base_length *= lerpf(0.92,1.08,coverage_ratio)
	base_length = clampf(base_length,3.5,minf(character_radius * 0.90,20.0))

	# 数量不是固定值：伤害、覆盖范围、冲击密度都会抬高期望数量，
	# 每次命中再加入与强度相关的随机波动。
	var expected_count:float = (
		4.0
		+ damage_shape * 3.8
		+ coverage_ratio * 2.8
		+ density_ratio * 3.2
	)
	var count_variance:int = 2 + int(round(damage_shape + coverage_ratio * 1.5))
	var count:int = clampi(
		int(round(expected_count)) + rng.randi_range(-count_variance,count_variance),
		3,
		18
	)

	var streaks:Array = []
	for _index:int in range(count):
		var sample:Dictionary = _random_hit_effect_visual_sample(
			rng,
			force_white,
			outward,
			character_radius,
			coverage_ratio
		)
		var angle_offset:float = deg_to_rad(rng.randf_range(-spread_degrees,spread_degrees))
		var streak_direction:Vector2 = outward.rotated(angle_offset).normalized()

		var distance:float = clampf(
			base_distance * rng.randf_range(0.82,1.12),
			min_distance,
			max_distance
		)
		var length:float = base_length * rng.randf_range(0.72,1.16)
		# 保持细线；密集冲击只增加数量/收束程度，不靠加粗表现。
		var width:float = rng.randf_range(0.40,0.78) * lerpf(0.94,1.04,damage_shape)
		var duration:float = rng.randf_range(0.20,0.31) * lerpf(1.0,0.90,damage_shape)
		var delay:float = rng.randf_range(0.0,lerpf(0.045,0.070,coverage_ratio))

		streaks.append({
			"spawn_offset": sample.get("spawn_offset",Vector2.ZERO),
			"direction": streak_direction,
			"distance": distance,
			"length": length,
			"width": width,
			"duration": duration,
			"delay": delay,
			"color": sample.get("color",Color.WHITE),
		})

	var effect = HIT_BURST_EFFECT_SCRIPT.new()
	effect.setup(global_position,streaks)
	parent.add_child(effect)


# 暴击粒子从当前人物图像全身采样，而不是复用受击射线的“背侧”或中心小椭圆。
# 每批只创建一次像素采样器；沿 3x3 区域轮换，减少少量粒子全挤在躯干的情况。
func sample_critical_particle_origins(count:int,rng:RandomNumberGenerator) -> PackedVector2Array:
	var points:PackedVector2Array = PackedVector2Array()
	if image == null or not is_instance_valid(image):
		return points
	var rect:Rect2 = _hit_effect_visual_rect()
	if rect.size.x <= 0.001 or rect.size.y <= 0.001:
		return points
	var sampler:RefCounted = _make_visual_pixel_sampler()
	var transform:Transform2D = image.global_transform
	var cell_start:int = rng.randi_range(0,8)
	for index:int in range(clampi(count,0,24)):
		var cell:int = (cell_start + index * 4) % 9
		var cell_position:Vector2 = Vector2(float(cell % 3),floorf(float(cell) / 3.0))
		var chosen:Vector2 = Vector2.INF
		for attempt:int in range(32):
			var uv:Vector2 = Vector2(rng.randf(),rng.randf())
			# 区域内没有人物像素时，后半段退回全身，避免在透明留白处喷粒子。
			if attempt < 16:
				uv = (cell_position + uv) / 3.0
			var local_point:Vector2 = rect.position + rect.size * uv
			if sampler.sample(local_point).a > 0.10:
				chosen = transform * local_point
				break
		# 极稀疏图案采样失败时复用已找到的实体点，不在透明包围盒外生成。
		if not chosen.is_finite():
			if points.is_empty():
				return points
			chosen = points[rng.randi_range(0,points.size() - 1)]
		points.append(chosen)
	return points


func _hit_burst_character_radius() -> float:
	# 优先使用实体碰撞体，保证视觉射程跟角色实际体型一致，而不是跟贴图留白一致。
	if collision_shape_2d != null and is_instance_valid(collision_shape_2d) and collision_shape_2d.shape != null:
		var shape:Shape2D = collision_shape_2d.shape
		var axis_x_scale:float = collision_shape_2d.global_transform.x.length()
		var axis_y_scale:float = collision_shape_2d.global_transform.y.length()
		var radius:float = 0.0

		if shape is CircleShape2D:
			radius = (shape as CircleShape2D).radius * maxf(axis_x_scale,axis_y_scale)
		elif shape is RectangleShape2D:
			var rect_size:Vector2 = (shape as RectangleShape2D).size
			radius = 0.5 * maxf(rect_size.x * axis_x_scale,rect_size.y * axis_y_scale)
		elif shape is CapsuleShape2D:
			var capsule := shape as CapsuleShape2D
			radius = 0.5 * maxf(capsule.radius * 2.0 * axis_x_scale,capsule.height * axis_y_scale)
		elif shape is ConvexPolygonShape2D:
			for point:Vector2 in (shape as ConvexPolygonShape2D).points:
				var scaled_point := Vector2(point.x * axis_x_scale,point.y * axis_y_scale)
				radius = maxf(radius,scaled_point.length())

		if radius > 0.001:
			return clampf(radius,8.0,48.0)

	# 没有有效碰撞体时才退回到当前视觉矩形。
	var visual_rect:Rect2 = _hit_effect_visual_rect()
	if visual_rect.size.x > 0.001 and visual_rect.size.y > 0.001 and image != null:
		var visual_x:float = image.global_transform.x.length()
		var visual_y:float = image.global_transform.y.length()
		var visual_radius:float = 0.5 * maxf(
			visual_rect.size.x * visual_x,
			visual_rect.size.y * visual_y
		)
		return clampf(visual_radius,8.0,48.0)

	return 16.0


func _random_hit_effect_visual_sample(
	rng:RandomNumberGenerator,
	force_white:bool,
	outward:Vector2,
	character_radius:float,
	coverage_ratio:float
) -> Dictionary:
	var visual_rect:Rect2 = _hit_effect_visual_rect()
	var pixel_sampler:RefCounted = _make_visual_pixel_sampler()
	var chosen_color:Color = Color.WHITE if force_white else _fallback_hit_effect_color()
	var chosen_world:Vector2 = global_position + outward * maxf(character_radius * 0.72,5.0)
	# This function never yields: source transform/origin are invariant for all
	# 44 trials. Use the same transform multiplication as Node2D.to_global().
	var sample_transform:Transform2D = image.global_transform if is_instance_valid(image) else Transform2D.IDENTITY
	var sample_origin:Vector2 = global_position

	# 起点始终在“攻击穿过人物后的背面”。
	# 同时让覆盖范围影响背面出生点的横向分布：
	# - 小范围命中集中在背面中心附近；
	# - 大范围命中可以铺到更宽的背侧轮廓。
	if visual_rect.size.x > 0.001 and visual_rect.size.y > 0.001:
		var tangent:Vector2 = Vector2(-outward.y,outward.x).normalized()
		var lateral_extent:float = character_radius * lerpf(0.18,0.92,coverage_ratio)
		var target_lateral:float = rng.randf_range(-lateral_extent,lateral_extent)
		var best_score:float = -INF
		var rear_threshold:float = maxf(character_radius * 0.12,1.5)
		var lateral_weight:float = lerpf(1.65,0.52,coverage_ratio)
		var rect_end:Vector2 = visual_rect.end
		var noise_max:float = maxf(character_radius * 0.18,1.5)

		for _attempt:int in range(44):
			var local_point := Vector2(
				rng.randf_range(visual_rect.position.x,rect_end.x),
				rng.randf_range(visual_rect.position.y,rect_end.y)
			)
			# Reject points on the wrong side before texture/color work. Neither
			# predicate consumes RNG; retain the noise draw only when BOTH pass.
			var world_point:Vector2 = sample_transform * local_point
			var relative_point:Vector2 = world_point - sample_origin
			var rear_projection:float = relative_point.dot(outward)
			if rear_projection < rear_threshold:
				continue
			var sampled:Color = pixel_sampler.sample(local_point)
			if sampled.a <= 0.10:
				continue

			var lateral_projection:float = relative_point.dot(tangent)
			var lateral_error:float = absf(lateral_projection - target_lateral)
			var score:float = (
				rear_projection
				- lateral_error * lateral_weight
				+ rng.randf_range(0.0,noise_max)
			)
			if score <= best_score:
				continue

			best_score = score
			chosen_world = world_point
			chosen_color = Color.WHITE if force_white else sampled

	return {
		"spawn_offset": chosen_world - global_position,
		"color": chosen_color,
	}


func _hit_effect_visual_rect() -> Rect2:
	if image is Sprite2D:
		return (image as Sprite2D).get_rect()

	if image is AnimatedSprite2D:
		var animated := image as AnimatedSprite2D
		var texture:Texture2D = _get_hit_effect_visual_texture()
		if texture == null:
			return Rect2()
		var size:Vector2 = Vector2(texture.get_size())
		var rect_position:Vector2 = animated.offset
		if animated.centered:
			rect_position -= size * 0.5
		return Rect2(rect_position,size)

	return Rect2()


func _get_hit_effect_visual_texture() -> Texture2D:
	if image is Sprite2D:
		return (image as Sprite2D).texture
	if image is AnimatedSprite2D:
		var animated := image as AnimatedSprite2D
		if animated.sprite_frames != null and animated.sprite_frames.has_animation(animated.animation):
			return animated.sprite_frames.get_frame_texture(animated.animation,animated.frame)
	return null


func _get_hit_effect_image(texture:Texture2D) -> Image:
	if texture == null:
		return null
	if _hit_effect_cached_texture == texture and _hit_effect_cached_image != null:
		return _hit_effect_cached_image

	# V412：人物脚底阴影 / 命中特效的 Alpha 采样与残影分析读取的是同一份原始纹理。
	# 旧版每个角色实例第一次采样都会 texture.get_image() 一次；50 个相同人物会重复 GPU->CPU 读取 50 次。
	# 复用 ball 已有的跨实例 Image 缓存，只消除重复读取，不改变任何像素或采样规则。
	var texture_image:Image = _get_cached_after_image_source_image(texture)
	if texture_image == null or texture_image.is_empty():
		return null

	_hit_effect_cached_texture = texture
	_hit_effect_cached_image = texture_image
	return _hit_effect_cached_image


# Capture once per synchronous batch: texture frame, crop, flips, tint and the exact
# CanvasItem modulation chain cannot change during these non-yielding sampling loops.
# No cross-frame cache: animation, damage tint and visibility changes remain immediate.
func _make_visual_pixel_sampler() -> RefCounted:
	var sampler:VISUAL_PIXEL_SAMPLER_SCRIPT = VISUAL_PIXEL_SAMPLER_SCRIPT.new()
	var texture:Texture2D = _get_hit_effect_visual_texture()
	var texture_image:Image = _get_hit_effect_image(texture)
	if texture == null or texture_image == null:
		return sampler
	sampler.source_image = texture_image
	sampler.width = texture_image.get_width()
	sampler.height = texture_image.get_height()
	sampler.source_size = Vector2(texture_image.get_size())
	if image is Sprite2D:
		var sprite:Sprite2D = image as Sprite2D
		sampler.rect = sprite.get_rect()
		sampler.flip_h = sprite.flip_h
		sampler.flip_v = sprite.flip_v
		if sprite.region_enabled:
			sampler.source_position = sprite.region_rect.position
			sampler.source_size = sprite.region_rect.size
		else:
			var columns:int = maxi(sprite.hframes,1)
			var rows:int = maxi(sprite.vframes,1)
			var frame_size:Vector2 = Vector2(texture.get_size()) / Vector2(float(columns),float(rows))
			sampler.source_size = frame_size
			sampler.source_position = Vector2(sprite.frame_coords) * frame_size
	elif image is AnimatedSprite2D:
		var animated:AnimatedSprite2D = image as AnimatedSprite2D
		sampler.rect = _hit_effect_visual_rect()
		sampler.flip_h = animated.flip_h
		sampler.flip_v = animated.flip_v
	else:
		return sampler
	var rect:Rect2 = sampler.rect
	if rect.size.x <= 0.001 or rect.size.y <= 0.001:
		return sampler
	sampler.tint = image_color
	sampler.mix_amount = clampf(image_color_mix,0.0,1.0)
	var modulation:Color = Color.WHITE
	var canvas:CanvasItem = image as CanvasItem
	while canvas != null:
		modulation *= canvas.modulate
		modulation *= canvas.self_modulate
		if canvas == self:
			break
		var parent_node:Node = canvas.get_parent()
		if parent_node is CanvasItem:
			canvas = parent_node as CanvasItem
		else:
			break
	sampler.modulation = modulation
	sampler.valid = true
	return sampler


func _sample_current_visual_pixel(local_point:Vector2) -> Color:
	var texture:Texture2D = _get_hit_effect_visual_texture()
	var texture_image:Image = _get_hit_effect_image(texture)
	if texture == null or texture_image == null:
		return Color.TRANSPARENT

	var uv:Vector2 = Vector2(-1.0,-1.0)
	var source_position:Vector2 = Vector2.ZERO
	var source_size:Vector2 = Vector2(texture_image.get_size())

	if image is Sprite2D:
		var sprite := image as Sprite2D
		var rect:Rect2 = sprite.get_rect()
		if rect.size.x <= 0.001 or rect.size.y <= 0.001 or not rect.has_point(local_point):
			return Color.TRANSPARENT
		uv = (local_point - rect.position) / rect.size
		if sprite.flip_h:
			uv.x = 1.0 - uv.x
		if sprite.flip_v:
			uv.y = 1.0 - uv.y

		if sprite.region_enabled:
			source_position = sprite.region_rect.position
			source_size = sprite.region_rect.size
		else:
			var columns:int = maxi(sprite.hframes,1)
			var rows:int = maxi(sprite.vframes,1)
			var frame_size:Vector2 = Vector2(texture.get_size()) / Vector2(float(columns),float(rows))
			source_size = frame_size
			source_position = Vector2(sprite.frame_coords) * frame_size
	elif image is AnimatedSprite2D:
		var animated := image as AnimatedSprite2D
		var rect:Rect2 = _hit_effect_visual_rect()
		if rect.size.x <= 0.001 or rect.size.y <= 0.001 or not rect.has_point(local_point):
			return Color.TRANSPARENT
		uv = (local_point - rect.position) / rect.size
		if animated.flip_h:
			uv.x = 1.0 - uv.x
		if animated.flip_v:
			uv.y = 1.0 - uv.y
	else:
		return Color.TRANSPARENT

	uv.x = clampf(uv.x,0.0,0.999999)
	uv.y = clampf(uv.y,0.0,0.999999)
	var pixel_position:Vector2 = source_position + uv * source_size
	var px:int = clampi(int(floor(pixel_position.x)),0,texture_image.get_width() - 1)
	var py:int = clampi(int(floor(pixel_position.y)),0,texture_image.get_height() - 1)
	var sampled:Color = texture_image.get_pixel(px,py)
	if sampled.a <= 0.0:
		return Color.TRANSPARENT

	# 与人物基础 Shader 一致：先把纹理颜色和 image_color 混合，
	# 然后再乘 CanvasItem 的 modulate/self_modulate 链。
	var mix_amount:float = clampf(image_color_mix,0.0,1.0)
	sampled = Color(
		lerpf(sampled.r,image_color.r,mix_amount),
		lerpf(sampled.g,image_color.g,mix_amount),
		lerpf(sampled.b,image_color.b,mix_amount),
		sampled.a
	)

	var modulation:Color = Color.WHITE
	var canvas:CanvasItem = image as CanvasItem
	while canvas != null:
		modulation *= canvas.modulate
		modulation *= canvas.self_modulate
		if canvas == self:
			break
		var parent_node:Node = canvas.get_parent()
		if parent_node is CanvasItem:
			canvas = parent_node as CanvasItem
		else:
			break

	sampled *= modulation
	return sampled


func _fallback_hit_effect_color() -> Color:
	var fallback:Color = image_color if image_color_mix > 0.5 else Color.WHITE
	if image != null and is_instance_valid(image):
		fallback *= image.modulate
		fallback *= image.self_modulate
	fallback.a = 1.0
	return fallback



# ========================================================
# 通用格挡 / 免疫反馈
#
# 目标在 can_receive_hit_from() 中直接拒绝命中时，hitbox.gd 会调用
# on_incoming_hit_rejected()。普通 block 吸收伤害时，则由 _on_hitbox_on_hit()
# 在伤害结算后调用 notify_block_burst_feedback()。
#
# 默认规则：
# - Shooter / Shooter_with_Health 被格挡或直接免疫时会被消除；
# - 特殊防御可以覆写 should_destroy_projectile_on_rejected_hit()，例如镜子反射；
# - 格挡视觉始终是命中点附近的小范围白色圆头线爆裂。
# ========================================================
func _incoming_hit_attacker(incoming_hit:hitbox) -> ball:
	if incoming_hit == null or not is_instance_valid(incoming_hit):
		return null
	var parent_node:Node = incoming_hit.get_parent()
	if parent_node is ball:
		return parent_node as ball
	if incoming_hit.owner is ball:
		return incoming_hit.owner as ball
	return null


func _estimate_block_impact_position(incoming_hit:hitbox) -> Vector2:
	var source_position:Vector2 = global_position
	if incoming_hit != null and is_instance_valid(incoming_hit):
		source_position = incoming_hit.global_position
		var attacker:ball = _incoming_hit_attacker(incoming_hit)
		if attacker != null and is_instance_valid(attacker):
			source_position = attacker.global_position

	var to_source:Vector2 = source_position - global_position
	if to_source.length_squared() <= 0.000001:
		return source_position

	# Area2D 进入信号没有直接提供接触点；把投射物中心沿来向夹到人物前侧轮廓，
	# 会比直接使用人物中心更接近视觉上的“子弹命中位置”。
	var radius:float = _hit_burst_character_radius()
	var boundary_distance:float = minf(to_source.length(),maxf(radius * 0.82,5.0))
	return global_position + to_source.normalized() * boundary_distance


# 特殊防御覆写点。返回 false 表示拒绝命中后不要销毁投射物，
# 典型用途就是镜子的反射窗口。
func should_destroy_projectile_on_rejected_hit(_incoming_hit:hitbox) -> bool:
	return true


func on_incoming_hit_rejected(incoming_hit:hitbox) -> void:
	if incoming_hit == null or not is_instance_valid(incoming_hit):
		return
	if state_machine != null and state_machine.current_state == State.Die:
		return

	var attacker:ball = _incoming_hit_attacker(incoming_hit)
	var impact_position:Vector2 = _estimate_block_impact_position(incoming_hit)
	var source_position:Vector2 = incoming_hit.global_position
	if attacker != null and is_instance_valid(attacker):
		source_position = attacker.global_position

	var travel_direction:Vector2 = global_position - source_position
	if travel_direction.length_squared() <= 0.000001:
		travel_direction = Vector2.RIGHT
	var coverage_width:float = _estimate_hit_effect_cross_section(incoming_hit,travel_direction)
	var raw_damage:float = float(attacker.Damage) if attacker != null and is_instance_valid(attacker) else 0.0
	var seed:int = Game.battle_rng_seed_or("classes/ball.gd:seed",int(Time.get_ticks_usec()) ^ int(get_instance_id()) ^ int(incoming_hit.get_instance_id()))

	notify_block_burst_feedback(impact_position,raw_damage,coverage_width,seed)

	# 角色本体攻击只被挡住，不会被删除；只有真正的投射物默认在格挡时消失。
	if (
		attacker != null
		and is_instance_valid(attacker)
		and _is_ranged_hit_source(attacker)
		and should_destroy_projectile_on_rejected_hit(incoming_hit)
	):
		attacker.on_projectile_blocked_by(self,impact_position)


func on_projectile_blocked_by(_target:ball,_impact_position:Vector2) -> void:
	if not _is_ranged_hit_source(self):
		return
	if not is_multiplayer_authority():
		return
	if state_machine != null and state_machine.current_state == State.Die:
		return

	# 先立刻停止，避免 Area2D 拒绝命中的这一帧继续穿过人物；
	# 状态切换放到 deferred，避免在 area_entered / area_shape_entered 回调中删除节点。
	Speed = 0.0
	direction = Vector2.ZERO
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO
	call_deferred("_finish_projectile_blocked")


func _finish_projectile_blocked() -> void:
	if not is_instance_valid(self):
		return
	if state_machine == null or state_machine.current_state == State.Die:
		return
	state_machine.current_state = State.Die


func notify_block_burst_feedback(
	impact_position:Vector2,
	raw_damage:float,
	coverage_width:float,
	seed:int
) -> void:
	if state_machine != null and state_machine.current_state == State.Die:
		return

	_play_block_burst_feedback_local(
		impact_position,
		maxf(raw_damage,0.0),
		maxf(coverage_width,1.0),
		seed
	)
	if multiplayer.has_multiplayer_peer():
		_remote_block_burst_feedback.rpc(
			impact_position,
			maxf(raw_damage,0.0),
			maxf(coverage_width,1.0),
			seed
		)


@rpc("authority","call_remote","reliable")
func _remote_block_burst_feedback(
	impact_position:Vector2,
	raw_damage:float,
	coverage_width:float,
	seed:int
) -> void:
	_play_block_burst_feedback_local(impact_position,raw_damage,coverage_width,seed)


func _play_block_burst_feedback_local(
	impact_position:Vector2,
	raw_damage:float,
	coverage_width:float,
	seed:int
) -> void:
	var parent:Node = get_tree().current_scene
	if parent == null:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var character_radius:float = _hit_burst_character_radius()
	var character_diameter:float = maxf(character_radius * 2.0,1.0)
	var coverage_ratio:float = clampf(coverage_width / maxf(character_diameter,1.0),0.0,1.4)
	var damage_reference:float = maxf(float(Max_health) * 0.25,20.0)
	var damage_ratio:float = clampf(raw_damage / damage_reference,0.0,1.0)

	# “一堆小线”但范围始终很小：伤害主要增加数量，覆盖面只轻微增加数量，
	# 不把格挡火花做成受击爆射那样的大范围冲击。
	var expected_count:float = 6.0 + damage_ratio * 3.0 + minf(coverage_ratio,1.0) * 1.5
	var count:int = clampi(int(round(expected_count)) + rng.randi_range(-2,2),5,12)
	var max_distance:float = clampf(
		character_radius * lerpf(0.42,0.72,damage_ratio),
		7.0,
		minf(character_radius * 0.90,22.0)
	)
	var max_length:float = clampf(character_radius * 0.28,2.8,7.0)

	var streaks:Array = []
	for index:int in range(count):
		# 黄金角 + 少量抖动，比完全随机更像从一个命中点“炸开”，同时每次仍不相同。
		var base_angle:float = float(index) * 2.39996323
		var angle:float = base_angle + rng.randf_range(-0.38,0.38)
		var streak_direction:Vector2 = Vector2.RIGHT.rotated(angle)
		var distance:float = max_distance * rng.randf_range(0.58,1.0)
		var length:float = max_length * rng.randf_range(0.55,1.0)
		var width:float = rng.randf_range(0.34,0.62)
		var duration:float = rng.randf_range(0.085,0.13)
		var delay:float = rng.randf_range(0.0,0.008)
		var tiny_offset:Vector2 = streak_direction * rng.randf_range(0.0,1.8)

		streaks.append({
			"spawn_offset": tiny_offset,
			"direction": streak_direction,
			"distance": distance,
			"length": length,
			"width": width,
			"duration": duration,
			"delay": delay,
			"grow_end": 0.24,
			"fade_in_end": 0.10,
			"fade_out_start": 0.40,
			"color": Color.WHITE,
		})

	var effect = HIT_BURST_EFFECT_SCRIPT.new()
	effect.setup(impact_position,streaks)
	parent.add_child(effect)


var hit_white_time := 0.1
var hit_white_duration := 0.1
var hit_white_tween:Tween
var _hit_white_visual_power:float = 0.0
var _hit_effect_cached_texture:Texture2D = null
var _hit_effect_cached_image:Image = null

func hit_white_method(power:float):
	_hit_white_visual_power = clampf(power,0.0,1.0)
	if image != null and is_instance_valid(image):
		image.set_instance_shader_parameter("power",power)


# 只播放受击闪白：不切 Hurt 状态，也不受 block 影响。
# 决斗者免疫非破绽伤害时需要这个反馈；保留为公共方法也兼容 v1-v4 补丁。
func hit_white_visual_only() -> void:
	if Type == Ball_Type.Creature or image == null or not is_instance_valid(image):
		return
	if hit_white_tween:
		hit_white_tween.kill()
	hit_white_method(1.0)
	hit_white_tween = create_tween()
	hit_white_tween.tween_method(hit_white_method,1.0,0.0,hit_white_duration)


func hit_white(ignore_block:bool = false):
	if (block > 0 and not ignore_block) or Type == Ball_Type.Creature:return
	if state_machine != null and state_machine.current_state != State.Die and state_machine.current_state != State.Attack and state_machine.current_state != State.Skill:
		state_machine.current_state = State.Hurt
	hit_white_visual_only()


# v1-v3 兼容入口。旧远程脚本仍可能调用 directional damage；
# 普通角色不做方向筛选，决斗者若是旧脚本则会覆写这些方法。
func can_receive_directional_damage(
	_source_position:Vector2,
	_incoming_direction:Vector2
) -> bool:
	return true


func on_directional_damage_rejected(
	_source_position:Vector2,
	_incoming_direction:Vector2,
	_damage:float,
	_ignore_block:bool
) -> void:
	pass


func receive_directional_damage(
	damage:float,
	source_position:Vector2,
	incoming_direction:Vector2 = Vector2.ZERO,
	ignore_block:bool = false
) -> bool:
	if damage <= 0.0:
		return false
	if not can_receive_directional_damage(source_position,incoming_direction):
		on_directional_damage_rejected(source_position,incoming_direction,damage,ignore_block)
		return false
	return receive_positional_damage(damage,source_position,ignore_block,null)


# 统一效果倍率公共协议。
# 调用方不要直接读取字段后自行重复乘法；优先使用这些方法，便于角色子类未来覆写。
func get_positive_effect_ratio() -> float:
	return maxf(positive_effect_ratio,0.0)


func get_negative_effect_ratio() -> float:
	return maxf(negative_effect_ratio,0.0)


func can_receive_positive_effects() -> bool:
	return get_positive_effect_ratio() > 0.000001


func can_receive_negative_effects() -> bool:
	return get_negative_effect_ratio() > 0.000001


func get_minecraft_potion_effect_ratio(is_positive:bool) -> float:
	var general_ratio:float = get_positive_effect_ratio() if is_positive else get_negative_effect_ratio()
	var potion_ratio:float = (
		maxf(minecraft_potion_positive_effect_ratio,0.0)
		if is_positive
		else maxf(minecraft_potion_negative_effect_ratio,0.0)
	)
	return general_ratio * potion_ratio


func is_minecraft_potion_healing_damage_inverted() -> bool:
	return minecraft_potion_invert_healing_damage


# 把乘法型效果按“距离中性值的幅度”缩放。
# 例：1.35 倍速度在 ratio=1.2 时得到 1 + 0.35*1.2 = 1.42；ratio=0 时回到中性 1.0。
func scale_effect_from_neutral(value:float,neutral_value:float,ratio:float) -> float:
	return neutral_value + (value - neutral_value) * maxf(ratio,0.0)


# 元素伤害公共协议。默认没有额外的硬编码元素免疫；
# 旧/特殊角色仍可以覆写 is_element_immune()，但标准火焰免疫应直接把 fire_effect_ratio 设为 0。
func is_element_immune(_element:StringName) -> bool:
	return false


func get_fire_effect_ratio() -> float:
	if is_element_immune(DAMAGE_ELEMENT_FIRE):
		return 0.0
	return maxf(fire_effect_ratio,0.0)


func is_fire_immune() -> bool:
	return get_fire_effect_ratio() <= 0.000001


func can_receive_fire_status() -> bool:
	return not is_fire_immune()


func receive_fire_positional_damage(
	damage:float,
	impact_position:Vector2,
	ignore_block:bool = false,
	source:Node = null
) -> bool:
	var scaled_damage:float = damage * get_fire_effect_ratio()
	if scaled_damage <= 0.0:
		return false
	var prior_element:Variant = get_meta("_blood_damage_element","")
	set_meta("_blood_damage_element","fire")
	var accepted:bool = receive_positional_damage(scaled_damage,impact_position,ignore_block,source)
	if prior_element == "": remove_meta("_blood_damage_element")
	else: set_meta("_blood_damage_element",prior_element)
	return accepted


func receive_fire_spatial_damage(
	damage:float,
	damage_space:Variant,
	ignore_block:bool = false,
	raw_health:bool = false
) -> bool:
	var scaled_damage:float = damage * get_fire_effect_ratio()
	if scaled_damage <= 0.0:
		return false
	var prior_element:Variant = get_meta("_blood_damage_element","")
	set_meta("_blood_damage_element","fire")
	var accepted:bool = receive_spatial_damage(scaled_damage,damage_space,ignore_block,raw_health)
	if prior_element == "": remove_meta("_blood_damage_element")
	else: set_meta("_blood_damage_element",prior_element)
	return accepted


# v4 兼容入口。对普通角色，空间上下文不改变原有伤害语义；
# 新版决斗者使用 receive_positional_damage() 做严格破绽位置判定。
func receive_spatial_damage(
	damage:float,
	damage_space:Variant,
	ignore_block:bool = false,
	raw_health:bool = false
) -> bool:
	if damage <= 0.0:
		return false
	var impact_position:Vector2 = global_position
	var source:Node = null
	if damage_space is Vector2:
		impact_position = damage_space as Vector2
	elif damage_space is Dictionary:
		var context:Dictionary = damage_space as Dictionary
		if context.has("point") and context["point"] is Vector2:
			impact_position = context["point"] as Vector2
		if context.get("source",null) is Node:
			source = context.get("source",null) as Node
	if raw_health:
		var before_health:float = float(health)
		var before_block:float = float(block)
		hit_white(true)
		health -= maxi(int(round(damage)),0)
		var actual_health_damage:float = maxf(before_health - float(health), 0.0)
		_emit_positional_damage_feedback(
			damage,
			impact_position,
			source,
			before_health,
			before_block,
			true
		)
		if actual_health_damage > 0.0 and source != null and Game.has_method("report_combat_damage"):
			Game.report_combat_damage(source, self, actual_health_damage, before_health)
		return actual_health_damage > 0.0
	return receive_positional_damage(damage,impact_position,ignore_block,source)


func receive_spatial_raw_health_damage(damage:float,damage_space:Variant) -> bool:
	return receive_spatial_damage(damage,damage_space,true,true)


	#伤害
func _hurtbox_target_ball(hurt:hurtbox) -> ball:
	if hurt == null or not is_instance_valid(hurt):
		return null
	# 正常结构中 hurtbox 是 ball 的直接子节点。优先 parent，
	# 再兼容旧场景依赖 Node.owner 的写法。
	var parent_node := hurt.get_parent()
	if parent_node is ball:
		return parent_node as ball
	if hurt.owner is ball:
		return hurt.owner as ball
	return null


func _on_hitbox_on_hit(hurt: hurtbox) -> void:
	if not is_multiplayer_authority():
		return
	if state_machine.current_state == State.Die or dizziness:
		return

	var target:ball = _hurtbox_target_ball(hurt)
	if target == null or target == self:
		return

	# 红牌等“禁伤”状态统一在真正命中这里生效。
	# 投射物会读取 Master 的状态，因此红牌期间已经飞出去的子弹仍会正常碰撞/销毁，
	# 但不会继续造成伤害。
	var outgoing_damage:float = attack_damage(current_hit_damage_multiplier())

	if outgoing_damage > 0.0 and (target.block < outgoing_damage or ignore_block):
		if Unique_Hit_Audio != null:
			play_unique_audio(Character_Audio_Slot.Hit,true)
		elif Hit_Audio != "":
			Audios.play_sfx.rpc(Hit_Audio,{volume = clampf(outgoing_damage - 12.0,-100.0,0.0)},true)

	var before_health:float = float(target.health)
	var before_block:float = float(target.block)
	var hit_source_position:Vector2 = self_hitbox.global_position if self_hitbox != null else global_position
	var hit_travel_direction:Vector2 = target.global_position - hit_source_position
	if hit_travel_direction.length_squared() <= 0.000001:
		hit_travel_direction = direction
	var hit_coverage_width:float = _estimate_hit_effect_cross_section(
		self_hitbox,
		hit_travel_direction
	)

	if outgoing_damage > 0.0:
		target.hit_white(ignore_block)
		target.take_damage(outgoing_damage,ignore_block)

	var health_loss:float = maxf(before_health - float(target.health),0.0)
	var block_loss:float = maxf(before_block - float(target.block),0.0)
	var hit_effect_seed:int = (
		int(Time.get_ticks_usec())
		^ int(get_instance_id())
		^ int(target.get_instance_id())
	)

	if block_loss > 0.0 and not ignore_block:
		var block_impact_position:Vector2 = target._estimate_block_impact_position(self_hitbox)
		target.notify_block_burst_feedback(
			block_impact_position,
			outgoing_damage,
			hit_coverage_width,
			hit_effect_seed ^ 0x51B10C
		)

		if _is_ranged_hit_source(self):
			on_projectile_blocked_by(target,block_impact_position)

	if health_loss > 0.0:
		target.notify_hit_burst_feedback(
			hit_source_position,
			outgoing_damage,
			health_loss,
			block_loss,
			hit_coverage_width,
			hit_effect_seed,
			hit_travel_direction.normalized() if hit_travel_direction.length_squared() > MOTION_EPSILON_SQ else Vector2.ZERO
		)

	if _is_ranged_hit_source(self):
		target.notify_ranged_hit_feedback(self,outgoing_damage,health_loss,block_loss)


func _on_hurtbox_on_hurt(_hit: hitbox) -> void:
	pass

# 统一的“有实际命中位置”的特殊伤害入口。
# 普通角色保持原行为；决斗者会覆写此函数，只接受落在真实破绽区域内的伤害。
#
# V88：此前公共“受击爆射线”只在 Hitbox.on_hit 链中生成。大量现代角色/投射物/
# 范围技能直接调用 receive_positional_damage()/receive_spatial_damage()，因此虽然真实扣血
# 和闪白正常，却完全没有受击爆射线。现在把这条反馈补到统一的位置伤害入口；
# 标准 Hitbox 链仍走 _on_hitbox_on_hit()，不会经过这里，所以不会重复生成。
func _positional_damage_feedback_origin(impact_position:Vector2,source:Node) -> Vector2:
	var origin:Vector2 = impact_position
	# 很多持续/范围伤害历史上把 target.global_position 当作 impact_position。
	# 这种情况下用真正来源节点的位置恢复入射方向，避免所有线都退化到角色自身移动方向。
	if origin.distance_squared_to(global_position) <= 4.0 and source is Node2D:
		origin = (source as Node2D).global_position
	return origin


func _positional_damage_feedback_coverage() -> float:
	# 直接脚本伤害通常没有独立 Hitbox Shape 可量横截面。用受击者体型给一个稳定的中等覆盖，
	# 既不会像针刺一样过度集中，也不会像整面墙命中一样铺满全身。
	return clampf(_hit_burst_character_radius() * 0.62,10.0,34.0)


func _source_handles_positional_hit_feedback(source:Node) -> bool:
	# 极少数老技能已经手工生成过专用爆射线（例如凑企鹅飞踢），允许它们显式声明接管，
	# 防止 V88 统一入口再叠一层。
	return (
		source != null
		and is_instance_valid(source)
		and source.has_method("handles_positional_hit_feedback")
		and bool(source.call("handles_positional_hit_feedback"))
	)


func _emit_positional_damage_feedback(
	raw_damage:float,
	impact_position:Vector2,
	source:Node,
	before_health:float,
	before_block:float,
	ignore_block:bool
) -> void:
	if _source_handles_positional_hit_feedback(source):
		return
	var health_loss:float = maxf(before_health - float(health),0.0)
	var block_loss:float = maxf(before_block - float(block),0.0)
	if health_loss <= 0.0 and block_loss <= 0.0:
		return

	var origin:Vector2 = _positional_damage_feedback_origin(impact_position,source)
	var incoming:Vector2 = global_position - origin
	if incoming.length_squared() <= MOTION_EPSILON_SQ and source is Node2D:
		incoming = global_position - (source as Node2D).global_position
	var coverage:float = _positional_damage_feedback_coverage()
	var seed:int = (
		int(Time.get_ticks_usec())
		^ int(get_instance_id())
		^ (int(source.get_instance_id()) if source != null and is_instance_valid(source) else 0)
	)

	if block_loss > 0.0 and not ignore_block:
		notify_block_burst_feedback(
			impact_position,
			raw_damage,
			coverage,
			seed ^ 0x51B10C
		)

	if health_loss > 0.0:
		notify_hit_burst_feedback(
			origin,
			raw_damage,
			health_loss,
			block_loss,
			coverage,
			seed,
			incoming.normalized() if incoming.length_squared() > MOTION_EPSILON_SQ else Vector2.ZERO
		)


func receive_positional_damage(
	damage:float,
	impact_position:Vector2,
	ignore_block:bool = false,
	source:Node = null
) -> bool:
	if damage <= 0.0:
		return false
	var before_health:float = float(health)
	var before_block:float = float(block)
	hit_white(ignore_block)
	take_damage(damage,ignore_block)
	var actual_health_damage:float = maxf(before_health - float(health), 0.0)
	_emit_positional_damage_feedback(
		damage,
		impact_position,
		source,
		before_health,
		before_block,
		ignore_block
	)
	if actual_health_damage > 0.0 and source != null and Game.has_method("report_combat_damage"):
		Game.report_combat_damage(source, self, actual_health_damage, before_health)
	return actual_health_damage > 0.0 or float(block) < before_block


func take_damage(damage:float,ignore_block:bool = false) -> void:
	var before_health:float = float(health)
	var before_block:float = float(block)
	damage *= 1 - Damage_reduction

	if not ignore_block and damage > 0:
		if block >= damage:
			block -= damage

			if Unique_Block_Audio != null:
				play_unique_audio(Character_Audio_Slot.Block,true)
			elif Block_Audio != "":
				Audios.play_sfx.rpc(Block_Audio,{volume = clampf(Damage - 12,-100,0)},true)
		elif block > 0:
			damage -= block
			block = 0
			health -= damage

			if Unique_Block_Break_Audio != null:
				play_unique_audio(Character_Audio_Slot.BlockBreak,true)
			elif BlockBreak_Audio != "":
				Audios.play_sfx.rpc(BlockBreak_Audio,{volume = clampf(Damage - 12,-100,0)},true)
		else:
			health -= damage
	elif damage > 0:
		health -= damage

	# 只有真正被攻击消耗的护盾提供较轻反馈；不把自然衰减/技能消费当作命中。
	_notify_damage_camera_feedback(maxf(before_block - float(block),0.0) * 0.35,true)
	if float(health) < before_health and Unique_Hurt_Audio != null:
		play_unique_audio(Character_Audio_Slot.Hurt,true)


func Skill() -> void:
	
	if state_machine.current_state == State.Die:return

var infection_texture = "infection"
func Attack() -> void:
	if state_machine.current_state == State.Die or not is_multiplayer_authority():return
	var world:World = get_tree().current_scene
	
	for come_from:int in Buff_Dic:
		for buff_name:String in Buff_Dic[come_from]:
			var buff:Buff = Buff_Dic[come_from][buff_name]
			if buff_name == "寄生" and buff.amount > 0:
				
				world.set_status_image.rpc(infection_texture,global_position)
				
				Audios.play_sfx.rpc("寄生",{},true)
				world.new_buff(self,come_from,"寄生",Buff.new(1,buff.duration + 1,Buff.Buff_types.Infection,-1,Buff.Algorithms.Set),"add")
				
				take_damage(3,true)
			elif buff_name == "寄生" and buff.amount <= 0:
				world.new_buff(self,come_from,"寄生",Buff.new(),"delete")
			
			
func continue_attack() -> void:
	
	if state_machine.current_state == State.Die:return
