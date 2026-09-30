extends Node2D
const PROJECTILE_CONTACT = preload("res://scripts/projectile_contact.gd")

# Sans 骨头墙攻击（V171）：
# - V171：重新按 Atlas 实际像素边界计算头/杆中心：12px 头部 region 的几何中心为 x=5.5，
#   连接杆真实像素占 x=2..7、中心为 x=4.5，因此头部只应补偿 +1.0px。
#   旧 +1.5px 会让所有旋转方向都出现半像素横向错位。
# - V168：直杆身体改成 Polygon2D 直接贴到头部下面，不再使用 1px Sprite 拉伸，彻底消除头/杆之间的可见断层。
# - V168：直接接触伤害每两个 physics tick 结算一次，伤害频率降为原来的一半；单次仍固定 1 点。
# - V166：骨头视觉拆成“单个前端骨头头部 + 可任意延伸的直杆身体”，不再使用完整双头 101px 骨头图；
#   因此再长的骨头也不会把素材末端的第二个骨头头露出来。
# - V166：攻击结束后不再直接消失，而是按出墙动画原路收回墙内，完全收回后再释放节点。
# - V164：预警期描边在红色/黄色之间快速交替闪烁；
# - V153：四个墙面统一让圆头朝场内，根部永远埋在墙里；
# - 攻击面积由 Sans 固定，矩形长宽每次随机变化；骨头之间不重叠，攻击带两端都有骨头。
# - 激活期间按物理帧造成 1 点直接伤害，并叠加 KARMA。

const SANS_ATLAS:Texture2D = preload("res://Images/characters/传说之下/Sans/Sans_spritesheet.png")
# 原始骨头在 Atlas 中为 12×101：上端 10px 是圆头，6px 后进入恒定 6px 宽直杆；
# 下端 94px 以后是第二个骨头头。V166 永远不再采样下端骨头头。
const BONE_HEAD_REGION:Rect2 = Rect2(399,574,12,10)
const BONE_BODY_REGION:Rect2 = Rect2(401,580,6,1)
const BONE_HEAD_HEIGHT:float = 10.0
const BONE_BODY_ATTACH_Y:float = 6.0
const BONE_HEAD_LATERAL_OFFSET:float = 1.0
const BONE_SOURCE_WIDTH:float = 12.0
const BONE_MIN_GAP:float = 1.0
const SFX_WARNING:AudioStream = preload("res://audio/characters/传说之下/Sans/提示.ogg")
const SFX_SPIKE:AudioStream = preload("res://audio/characters/传说之下/Sans/骨头刺.ogg")

enum WallSide { TOP, RIGHT, BOTTOM, LEFT }

var source:ball = null
var source_team:String = ""
var final_rect:Rect2 = Rect2()
var wall_side:int = WallSide.BOTTOM
var warning_duration:float = 0.42
var rise_duration:float = 0.16
var active_duration:float = 0.92
var retract_duration:float = 0.16
var first_contact_karma:float = 5.0
var held_contact_karma:float = 1.0

var _elapsed:float = 0.0
var _phase:int = 0 # 0 warning, 1 rising, 2 active, 3 retracting, 4 done
var _inward:Vector2 = Vector2.UP
var _depth:float = 1.0
var _span:float = 1.0
var _bone_roots:Array[Node2D] = []
var _bone_heads:Array[Sprite2D] = []
var _bone_bodies:Array[Polygon2D] = []
var _damage_area:Area2D = null
var _damage_shape:CollisionShape2D = null
var _contact_started:Dictionary = {}
var _warning_audio:AudioStreamPlayer2D = null
var _spike_audio:AudioStreamPlayer2D = null
var _warning_flash_step:int = -1
var _damage_tick_toggle:bool = false
# V193/V50：骨头完全刺出后只抖视觉根节点一次；V50 明显加强幅度，伤害 Area/Shape 仍保持原地。
var _full_extension_shake_left:float = 0.0
var _full_extension_shake_started:bool = false
const FULL_EXTENSION_SHAKE_DURATION:float = 0.165
const FULL_EXTENSION_SHAKE_AMPLITUDE:float = 7.5
const FULL_EXTENSION_SHAKE_FREQUENCY:float = 72.0
const WARNING_FLASH_INTERVAL:float = 0.085
const WARNING_RED:Color = Color(1.0,0.06,0.08,1.0)
const WARNING_YELLOW:Color = Color(1.0,0.88,0.05,1.0)


func configure(
	actor:ball,
	attack_rect:Rect2,
	side:int,
	warn_time:float,
	rise_time:float,
	active_time:float,
	karma_first:float = 5.0,
	karma_held:float = 1.0
) -> void:
	source = actor
	source_team = actor.Team if actor != null else ""
	final_rect = attack_rect.abs()
	wall_side = clampi(side,WallSide.TOP,WallSide.LEFT)
	warning_duration = maxf(warn_time,0.05)
	rise_duration = maxf(rise_time,0.04)
	# 收回速度默认和刺出速度一致，这样视觉上是严格反向播放。
	retract_duration = rise_duration
	active_duration = maxf(active_time,0.08)
	first_contact_karma = maxf(karma_first,0.0)
	held_contact_karma = maxf(karma_held,0.0)
	global_position = final_rect.get_center()
	_resolve_axes()
	_build_damage_area()
	_build_bones()
	_build_audio()
	_warning_audio.play()
	queue_redraw()


func _build_audio() -> void:
	_warning_audio = AudioStreamPlayer2D.new()
	_warning_audio.name = "SansBoneWarningAudio"
	_warning_audio.stream = SFX_WARNING
	_warning_audio.volume_db = -1.0
	_warning_audio.max_distance = 1200.0
	add_child(_warning_audio)

	_spike_audio = AudioStreamPlayer2D.new()
	_spike_audio.name = "SansBoneSpikeAudio"
	_spike_audio.stream = SFX_SPIKE
	_spike_audio.volume_db = -1.0
	_spike_audio.max_distance = 1200.0
	add_child(_spike_audio)


func _resolve_axes() -> void:
	match wall_side:
		WallSide.TOP:
			_inward = Vector2.DOWN
			_depth = final_rect.size.y
			_span = final_rect.size.x
		WallSide.RIGHT:
			_inward = Vector2.LEFT
			_depth = final_rect.size.x
			_span = final_rect.size.y
		WallSide.BOTTOM:
			_inward = Vector2.UP
			_depth = final_rect.size.y
			_span = final_rect.size.x
		WallSide.LEFT:
			_inward = Vector2.RIGHT
			_depth = final_rect.size.x
			_span = final_rect.size.y


func _build_damage_area() -> void:
	_damage_area = Area2D.new()
	_damage_area.name = "SansBoneDamageArea"
	_damage_area.collision_layer = 0
	_damage_area.collision_mask = 2
	_damage_area.monitoring = false
	_damage_area.monitorable = false
	add_child(_damage_area)

	_damage_shape = CollisionShape2D.new()
	var shape:=RectangleShape2D.new()
	shape.size = Vector2(maxf(final_rect.size.x,1.0),maxf(final_rect.size.y,1.0))
	_damage_shape.shape = shape
	_damage_area.add_child(_damage_shape)
	_set_extension_progress(0.001)


func _build_bones() -> void:
	# 12px 宽的骨头头部不能互相重叠。第一根/最后一根外缘贴住攻击带两端，
	# 中间中心点等距分布，因此任意长宽矩形都不会在两端留下空白。
	var usable_between_centers:float = maxf(_span - BONE_SOURCE_WIDTH,0.0)
	var count:int = 1
	if _span >= BONE_SOURCE_WIDTH * 2.0:
		count = maxi(2,int(floor(usable_between_centers / (BONE_SOURCE_WIDTH + BONE_MIN_GAP))) + 1)
	count = clampi(count,1,48)

	for i:int in range(count):
		var root:=Node2D.new()
		root.name = "Bone_%02d" % i
		# root 的 local -Y 永远朝地图内部，因此头在 local -Y，身体向 local +Y 延伸回墙。
		root.rotation = _inward.angle() + PI * 0.5
		add_child(root)

		var body:=Polygon2D.new()
		body.name = "Body"
		body.color = Color.WHITE
		body.visible = false
		body.z_index = 1
		root.add_child(body)

		var head:=Sprite2D.new()
		head.name = "Head"
		head.texture = SANS_ATLAS
		head.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		head.centered = true
		head.region_enabled = true
		head.region_filter_clip_enabled = true
		head.region_rect = Rect2(BONE_HEAD_REGION.position,Vector2(BONE_HEAD_REGION.size.x,1.0))
		head.z_index = 2
		root.add_child(head)

		_bone_roots.append(root)
		_bone_heads.append(head)
		_bone_bodies.append(body)

	_set_extension_progress(0.001)


func _draw() -> void:
	if _phase == 0:
		var local_rect:=Rect2(-final_rect.size * 0.5,final_rect.size)
		var flash_index:int = int(floor(_elapsed / WARNING_FLASH_INTERVAL))
		var warning_color:Color = WARNING_RED if (flash_index & 1) == 0 else WARNING_YELLOW
		draw_rect(local_rect,warning_color,false,2.6,true)


func _process(delta:float) -> void:
	if Game.now_stop_state:
		return
	_elapsed += maxf(delta,0.0)
	match _phase:
		0:
			var flash_step:int = int(floor(_elapsed / WARNING_FLASH_INTERVAL))
			if flash_step != _warning_flash_step:
				_warning_flash_step = flash_step
				queue_redraw()
			if _elapsed >= warning_duration:
				_elapsed = 0.0
				_phase = 1
				if _spike_audio != null:
					_spike_audio.play()
				if _damage_area != null:
					_damage_area.monitoring = true
				queue_redraw()
		1:
			var p:float = clampf(_elapsed / maxf(rise_duration,0.001),0.0,1.0)
			_set_extension_progress(p)
			if p >= 1.0:
				_elapsed = 0.0
				_phase = 2
				_full_extension_shake_started = true
				_full_extension_shake_left = FULL_EXTENSION_SHAKE_DURATION
		2:
			_set_extension_progress(1.0)
			_apply_full_extension_visual_shake(delta)
			if _elapsed >= active_duration:
				_elapsed = 0.0
				_phase = 3
				# 收回阶段不再造成新伤害；视觉和碰撞形状继续一起缩回墙内。
				if _damage_area != null:
					_damage_area.monitoring = false
		3:
			var retract_p:float = clampf(_elapsed / maxf(retract_duration,0.001),0.0,1.0)
			_set_extension_progress(1.0 - retract_p)
			if retract_p >= 1.0:
				_phase = 4
				queue_free()


func _apply_full_extension_visual_shake(delta:float) -> void:
	if not _full_extension_shake_started or _full_extension_shake_left <= 0.0:
		return
	_full_extension_shake_left = maxf(_full_extension_shake_left - maxf(delta,0.0),0.0)
	var life:float = clampf(_full_extension_shake_left / FULL_EXTENSION_SHAKE_DURATION,0.0,1.0)
	var phase:float = (FULL_EXTENSION_SHAKE_DURATION - _full_extension_shake_left) * FULL_EXTENSION_SHAKE_FREQUENCY
	# 主要沿出墙方向来回弹一下，再叠少量切线抖动；只改骨头 root，不改 Area2D。
	var tangent:=Vector2(-_inward.y,_inward.x)
	var offset:Vector2 = _inward * sin(phase) * FULL_EXTENSION_SHAKE_AMPLITUDE * life
	offset += tangent * sin(phase * 1.71 + 0.8) * FULL_EXTENSION_SHAKE_AMPLITUDE * 0.40 * life
	for root:Node2D in _bone_roots:
		if root != null and is_instance_valid(root):
			root.position += offset


func _physics_process(_delta:float) -> void:
	if Game.now_stop_state:
		return
	if _phase < 1 or _phase > 2:
		return
	if source == null or not is_instance_valid(source) or not source.is_multiplayer_authority():
		return
	if source.health <= 0 or source.is_damage_output_disabled():
		return
	if _damage_area == null or not _damage_area.monitoring:
		return

	# V168：原本每个 physics tick 都结算 1 点帧伤；现在严格每两个 physics tick 结算一次。
	_damage_tick_toggle = not _damage_tick_toggle
	if not _damage_tick_toggle:
		return

	for raw_body:Node2D in _damage_area.get_overlapping_bodies():
		if not raw_body is ball:
			continue
		var target:ball = raw_body as ball
		if not _is_enemy(target):
			continue
		var target_id:int = target.get_instance_id()
		var karma_amount:float = held_contact_karma
		if not _contact_started.has(target_id):
			_contact_started[target_id] = true
			karma_amount = first_contact_karma
		source.call("apply_sans_frame_hit",target,target.global_position,karma_amount)


func _is_enemy(target:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(source,target): return false # 皓宸复制品及其产物不把己方选为目标
	if PROJECTILE_CONTACT.ignores(target): return false
	if target == null or target == source or target.health <= 0:
		return false
	if target.has_method("is_combat_targetable") and not target.is_combat_targetable():
		return false
	if (
		not Game.Game_Settings.Have_Team_Damage
		and not source_team.is_empty()
		and not target.Team.is_empty()
		and source_team == target.Team
	):
		return false
	return true


func _wall_boundary_local() -> Vector2:
	match wall_side:
		WallSide.TOP:
			return Vector2(0.0,-_depth * 0.5)
		WallSide.RIGHT:
			return Vector2(_depth * 0.5,0.0)
		WallSide.BOTTOM:
			return Vector2(0.0,_depth * 0.5)
	return Vector2(-_depth * 0.5,0.0)


func _set_bone_length(index:int,visible_length:float) -> void:
	if index < 0 or index >= _bone_heads.size() or index >= _bone_bodies.size():
		return
	var head:Sprite2D = _bone_heads[index]
	var body:Polygon2D = _bone_bodies[index]
	var safe_length:float = maxf(visible_length,0.0)

	# 头部从墙里逐像素露出：不足 10px 时只裁头部本身，不缩放。
	if safe_length < BONE_HEAD_HEIGHT:
		var head_visible:float = maxf(safe_length,0.001)
		head.region_rect = Rect2(BONE_HEAD_REGION.position,Vector2(BONE_HEAD_REGION.size.x,head_visible))
		head.position = Vector2(BONE_HEAD_LATERAL_OFFSET,-safe_length * 0.5)
		head.visible = safe_length > 0.01
		body.visible = false
		body.polygon = PackedVector2Array()
		return

	# V168：头部保持原图；杆体直接画成 6px 宽白色矩形。
	# 杆体推进到头部内部 4px（BONE_BODY_ATTACH_Y=6，而头高 10），两部分始终重叠。
	head.visible = true
	head.region_rect = BONE_HEAD_REGION
	head.position = Vector2(BONE_HEAD_LATERAL_OFFSET,-safe_length + BONE_HEAD_HEIGHT * 0.5)

	var body_tip_y:float = minf(-safe_length + BONE_BODY_ATTACH_Y,-0.001)
	var half_width:float = BONE_BODY_REGION.size.x * 0.5
	body.visible = true
	body.polygon = PackedVector2Array([
		Vector2(-half_width,0.0),
		Vector2( half_width,0.0),
		Vector2( half_width,body_tip_y),
		Vector2(-half_width,body_tip_y),
	])


func _set_extension_progress(raw_progress:float) -> void:
	var p:float = clampf(raw_progress,0.0,1.0)
	var current_depth:float = maxf(_depth * p,0.0)
	var boundary:Vector2 = _wall_boundary_local()
	var collision_depth:float = maxf(current_depth,0.5)
	var collision_center:Vector2 = boundary + _inward * (collision_depth * 0.5)

	if _damage_shape != null and _damage_shape.shape is RectangleShape2D:
		var rectangle:=_damage_shape.shape as RectangleShape2D
		if wall_side == WallSide.TOP or wall_side == WallSide.BOTTOM:
			rectangle.size = Vector2(final_rect.size.x,collision_depth)
		else:
			rectangle.size = Vector2(collision_depth,final_rect.size.y)
		_damage_shape.position = collision_center

	var count:int = _bone_roots.size()
	if count <= 0:
		return

	var first_center:float = -_span * 0.5 + BONE_SOURCE_WIDTH * 0.5
	var center_step:float = 0.0
	if count > 1:
		center_step = maxf((_span - BONE_SOURCE_WIDTH) / float(count - 1),BONE_SOURCE_WIDTH)

	for i:int in range(count):
		var across:float = 0.0 if count == 1 else first_center + center_step * float(i)
		var across_vec:Vector2 = (
			Vector2(across,0.0)
			if wall_side == WallSide.TOP or wall_side == WallSide.BOTTOM
			else Vector2(0.0,across)
		)
		var root:Node2D = _bone_roots[i]
		# root 固定在墙线；局部 -Y 朝场内。这样身体任意延长时，根部永远停在墙里。
		root.position = across_vec + boundary
		_set_bone_length(i,current_depth)
