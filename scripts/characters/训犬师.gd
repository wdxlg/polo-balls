extends ball

const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const DOG_SCENE:PackedScene = preload("res://scenes/creatures/训犬师_狗.tscn")
const SHARED_WHISTLE = preload("res://scripts/audio/投稿吹哨音效.gd")
const TRAINER_AUDIO = preload("res://scripts/audio/训犬师音效.gd")

@export_category("训犬师 - 视觉")
@export var normal_texture:Texture2D
@export var whistle_texture:Texture2D
@export_range(0.05,2.0,0.05) var whistle_visual_duration:float = 0.45

@export_category("训犬师 - 标记红线")
@export_range(80.0,900.0,10.0) var line_length:float = 420.0
@export_range(4.0,180.0,1.0) var line_detector_half_height:float = 100.0
@export_range(20.0,240.0,5.0) var line_reveal_distance:float = 100.0
@export_range(0.0,16.0,0.5) var whistle_line_vertical_tolerance:float = 4.0
@export_range(0.0,1.0,0.01) var line_min_alpha:float = 0.10
@export_range(0.0,1.0,0.01) var line_max_alpha:float = 1.0
@export_range(0.0,40.0,1.0) var line_stop_before_character:float = 14.0
@export_range(40.0,1600.0,20.0) var line_extend_speed:float = 720.0

@export_category("训犬师 - 标记图标")
@export var marker_color:Color = Color(1.0,0.02,0.02,1.0)
@export_range(-80.0,0.0,1.0) var marker_offset_y:float = -24.0
@export_range(0.8,3.5,0.1) var marker_line_width:float = 1.7
@export_range(1.0,3.0,0.05) var marker_ring_spawn_scale:float = 1.65
@export_range(0.04,0.30,0.01) var marker_ring_shrink_duration:float = 0.10
@export_range(1.0,3.0,0.05) var marker_arms_spawn_scale:float = 1.55
@export_range(0.0,0.15,0.005) var marker_arms_delay:float = 0.055
@export_range(0.04,0.30,0.01) var marker_arms_shrink_duration:float = 0.09

@export_category("训犬师 - 猎犬")
@export_range(10.0,120.0,1.0) var dog_spawn_distance:float = 42.0
@export_range(1.0,60.0,0.5) var dog_spawn_interval:float = 14.0
@export_range(1,12,1) var dog_max_count:int = 3
@export_range(1.0,30.0,0.5) var whistle_action_cooldown:float = 6.0
@export_range(0.0,80.0,1.0) var dog_spawn_vertical_spread:float = 24.0

@onready var mark_line:Line2D = $MarkLine
@onready var mark_detector:Area2D = $MarkDetector
@onready var mark_shape:CollisionShape2D = $MarkDetector/CollisionShape2D
@onready var character_image:Sprite2D = $Graphics/Image

var dogs:Array[ball] = []
var dog_spawn_timer:Timer = null
var marked_target:ball = null
var _marker_visual:Node2D = null
var _active_mark_hunters:Dictionary = {}
var _mark_participants:Dictionary = {}
var _facing_sign:float = Vector2.RIGHT.x
var _dog_spawn_serial:int = 0
var _visual_serial:int = 0
var _last_whistle_action_msec:int = -1000000
var _line_material:ShaderMaterial = null
var _current_line_visual_length:float = 0.0

func _ready() -> void:
	Can_Attack = false
	Can_Skill = false
	Has_Collision_Damage = false
	super._ready()
	_set_trainer_texture(normal_texture)

	# ball.tscn 根节点本身 scale=0.2。标记线是“世界空间的水平扫描线”，
	# 因此 Line2D 和 Area2D 都必须脱离角色缩放，并明确恢复到 1:1 世界尺寸。
	mark_line.top_level = true
	mark_detector.top_level = true
	mark_line.global_scale = Vector2.ONE
	mark_detector.global_scale = Vector2.ONE
	mark_line.global_rotation = 0.0
	mark_detector.global_rotation = 0.0

	# 每个训犬师继续使用独立 ShaderMaterial，避免后续实例参数互相污染。
	# V206 起动态扫描长度不再传进 Shader；长度只负责 Line2D 几何裁剪，虚线相位独立。
	if mark_line.material is ShaderMaterial:
		_line_material = (mark_line.material as ShaderMaterial).duplicate() as ShaderMaterial
		mark_line.material = _line_material

	# 每个实例使用独立 Shape2D，避免多个训犬师共享 RectangleShape2D 尺寸。
	if mark_shape != null and mark_shape.shape != null:
		mark_shape.shape = mark_shape.shape.duplicate()
	mark_detector.set_meta("threat_debug_detection",true)
	_update_line_geometry(0.0)

	if is_multiplayer_authority():
		call_deferred("_start_dog_system")

func _set_trainer_texture(texture_value:Texture2D) -> void:
	if texture_value == null or character_image == null:
		return
	character_image.texture = texture_value
	var auto_fit:Node = get_node_or_null("CharacterAutoFit")
	if auto_fit != null and auto_fit.has_method("apply_visual_fit_only"):
		auto_fit.call("apply_visual_fit_only")


func _whistle_action_ready() -> bool:
	var cooldown_msec:int = int(round(maxf(whistle_action_cooldown,0.0) * 1000.0))
	return Time.get_ticks_msec() - _last_whistle_action_msec >= cooldown_msec

func _record_whistle_action() -> void:
	_last_whistle_action_msec = Time.get_ticks_msec()

func _show_whistle_visual() -> void:
	if whistle_texture == null or health <= 0:
		return
	_visual_serial += 1
	var my_serial:int = _visual_serial
	_set_trainer_texture(whistle_texture)
	await get_tree().create_timer(maxf(whistle_visual_duration,0.05)).timeout
	if not is_instance_valid(self) or health <= 0 or my_serial != _visual_serial:
		return
	_set_trainer_texture(normal_texture)

func _start_dog_system() -> void:
	if not is_inside_tree() or health <= 0:
		return
	# V205：开局第一条狗仍立即生成/吹哨，但它是出生初始化，不消耗统一吹哨动作冷却。
	# 因此比赛开始时扫描线和首次标记资格立即可用。
	_spawn_dog(true)
	if dog_spawn_timer != null and is_instance_valid(dog_spawn_timer):
		return
	dog_spawn_timer = Timer.new()
	dog_spawn_timer.name = "DogSpawnTimer"
	dog_spawn_timer.wait_time = maxf(dog_spawn_interval,0.1)
	dog_spawn_timer.one_shot = false
	dog_spawn_timer.autostart = false
	add_child(dog_spawn_timer)
	dog_spawn_timer.timeout.connect(_on_dog_spawn_timer_timeout)
	dog_spawn_timer.start()

func _on_dog_spawn_timer_timeout() -> void:
	if health <= 0 or not is_multiplayer_authority() or not is_combat_runtime_active():
		return
	_spawn_dog()

func _physics_process(delta:float) -> void:
	if health <= 0:
		if mark_line != null:
			mark_line.visible = false
		_clear_mark()
		return
	if absf(direction.x) > 0.05:
		_facing_sign = 1.0 if direction.x > 0.0 else -1.0

	_update_line_geometry(delta)
	_update_line_alpha()
	_update_marker_position()

	if not is_multiplayer_authority() or not is_combat_runtime_active():
		return

	_cleanup_dogs()

	if marked_target != null:
		if not is_instance_valid(marked_target) or marked_target.health <= 0 or not TOOLS.is_enemy(self,marked_target):
			_clear_mark()
		else:
			# 标记存在时，新召唤出的狗也会加入本次围猎。
			_assign_mark_to_available_dogs(marked_target)
			if _active_mark_hunters.is_empty():
				_clear_mark()
			return

	if dogs.is_empty():
		return

	var candidate:ball = _closest_detected_enemy()
	if candidate != null and _whistle_action_ready():
		_set_mark(candidate)
		_assign_mark_to_available_dogs(candidate)
		if _active_mark_hunters.is_empty():
			_clear_mark()

func _is_live_healthbar_character(candidate:ball) -> bool:
	if candidate == null or candidate == self or not is_instance_valid(candidate):
		return false
	# “人物”只取正常 Ball；训犬师自己的狗是 Creature，不应把扫描线截断在狗身上。
	if candidate.Type != Ball_Type.Ball or candidate.health <= 0 or candidate.Max_health <= 0:
		return false
	return candidate.get_node_or_null("Health_Bar") != null

func _character_vertical_half_extent(candidate:ball) -> float:
	if candidate == null or not is_instance_valid(candidate):
		return 0.0
	var body_shape:CollisionShape2D = candidate.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body_shape == null or body_shape.shape == null:
		return 0.0
	var scale_y:float = maxf(absf(body_shape.global_scale.y),0.0001)
	if body_shape.shape is RectangleShape2D:
		return (body_shape.shape as RectangleShape2D).size.y * 0.5 * scale_y
	if body_shape.shape is CircleShape2D:
		return (body_shape.shape as CircleShape2D).radius * scale_y
	if body_shape.shape is CapsuleShape2D:
		return (body_shape.shape as CapsuleShape2D).height * 0.5 * scale_y
	return 0.0

func _character_vertical_gap_to_scan_line(candidate:ball) -> float:
	if candidate == null or not is_instance_valid(candidate):
		return INF
	var center_gap:float = absf(candidate.global_position.y - global_position.y)
	return maxf(center_gap - _character_vertical_half_extent(candidate),0.0)

func _first_healthbar_character_forward_distance() -> float:
	var best_forward:float = INF
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var candidate:ball = raw as ball
		if not _is_live_healthbar_character(candidate):
			continue
		# V210：视觉红线只会被敌方有血条人物截断。己方单位可以站在线上，
		# 但绝不能缩短扫描线或挡住后方真正敌人的红线显示。
		if not TOOLS.is_enemy(self,candidate):
			continue
		var offset:Vector2 = candidate.global_position - global_position
		var forward:float = offset.x * _facing_sign
		if forward <= 0.0 or forward > line_length:
			continue
		# V212：宽扫描带只负责“渐显”，绝不能再负责视觉截断。
		# 只有敌方有血条人物的真实碰撞身体已经贴到水平红线（沿用吹哨约4px容差）时，
		# 才允许把线截在人物前面；因此上下仍有明显空隙的敌人不会造成“前面没东西却断线”。
		if _character_vertical_gap_to_scan_line(candidate) > maxf(whistle_line_vertical_tolerance,0.0):
			continue
		best_forward = minf(best_forward,forward)
	return best_forward

func _update_line_geometry(delta:float) -> void:
	if mark_line == null or mark_detector == null:
		return
	# detector 始终保持完整设计扫描范围，用于发现目标；视觉线只做几何裁剪。
	# V206：动态终点绝不能再参与 Shader 的虚线循环周期，否则目标距离变化会让整条 dash 相位重排。
	mark_line.global_scale = Vector2.ONE
	mark_detector.global_scale = Vector2.ONE
	mark_line.global_position = global_position
	mark_line.global_rotation = 0.0
	mark_detector.global_position = global_position + Vector2(_facing_sign * line_length * 0.5,0.0)
	mark_detector.global_rotation = 0.0
	if mark_shape != null and mark_shape.shape is RectangleShape2D:
		var rect:RectangleShape2D = mark_shape.shape as RectangleShape2D
		rect.size = Vector2(line_length,line_detector_half_height * 2.0)

	var desired_length:float = line_length
	var first_character_distance:float = _first_healthbar_character_forward_distance()
	if first_character_distance < INF:
		desired_length = maxf(first_character_distance - maxf(line_stop_before_character,0.0),1.0)
	desired_length = clampf(desired_length,1.0,line_length)

	if _current_line_visual_length <= 0.0 or delta <= 0.0:
		_current_line_visual_length = desired_length
	elif desired_length < _current_line_visual_length:
		# 人物靠近时立即缩短，保证红线绝不会穿过第一个有血条人物。
		_current_line_visual_length = desired_length
	else:
		# 人物远离/离开时平滑延长，只改变末端裁剪，不改变虚线相位。
		_current_line_visual_length = move_toward(
			_current_line_visual_length,
			desired_length,
			maxf(line_extend_speed,0.0) * maxf(delta,0.0)
		)
	_current_line_visual_length = clampf(_current_line_visual_length,1.0,line_length)
	mark_line.points = PackedVector2Array([Vector2.ZERO,Vector2(_facing_sign * _current_line_visual_length,0.0)])

func _update_line_alpha() -> void:
	if mark_line == null:
		return

	# V203：扫描红线只在“可以建立新标记”的窗口显示。
	# 已经存在标记或统一吹哨动作仍在冷却时，红线完全隐藏。
	var scan_ready:bool = marked_target == null and _whistle_action_ready() and health > 0
	mark_line.visible = scan_ready
	if not scan_ready:
		return

	# V207：亮度只看“敌人身体边缘距离这条水平红线还有多远”。
	# 例如敌人再向红线移动 50px 就会碰到线，则 gap=50，已经进入渐显；
	# gap 越小越亮，身体边缘真正碰到红线时 gap=0，alpha 必须达到 100%。
	# 敌人到训犬师的水平距离只负责判断它是否位于扫描线前方，不再参与透明度。
	var best_vertical_gap:float = INF
	for node:Node in get_tree().get_nodes_in_group("Ball"):
		if not node is ball:
			continue
		var enemy:ball = node as ball
		if enemy.health <= 0 or enemy.Max_health <= 0:
			continue
		if not TOOLS.is_enemy(self,enemy):
			continue
		var offset:Vector2 = enemy.global_position - global_position
		var local_x:float = offset.x * _facing_sign
		if local_x < 0.0 or local_x > line_length:
			continue
		var vertical_gap:float = _character_vertical_gap_to_scan_line(enemy)
		if vertical_gap > line_detector_half_height:
			continue
		best_vertical_gap = minf(best_vertical_gap,vertical_gap)

	var reveal:float = 0.0
	if best_vertical_gap < INF:
		reveal = 1.0 - clampf(best_vertical_gap / maxf(line_reveal_distance,1.0),0.0,1.0)
	var min_alpha:float = clampf(maxf(line_min_alpha,0.10),0.10,1.0)
	var max_alpha:float = clampf(maxf(line_max_alpha,min_alpha),min_alpha,1.0)
	mark_line.self_modulate.a = lerpf(min_alpha,max_alpha,reveal)

func _closest_detected_enemy() -> ball:
	# V208：吹哨判定不再等同于“进入宽扫描带”。宽扫描带只负责红线渐显/视觉截断；
	# 真正建立标记必须位于训犬师当前朝向的左/右水平线上。用人物碰撞身体边缘到红线的
	# 垂直 gap 做硬过滤，默认仅允许 <=4px，因此 y 轴相差很大的敌人绝不会触发吹哨。
	var best:ball = null
	var best_forward:float = INF
	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if not raw is ball:
			continue
		var candidate:ball = raw as ball
		if not TOOLS.is_enemy(self,candidate) or candidate.health <= 0:
			continue
		var offset:Vector2 = candidate.global_position - global_position
		var forward:float = offset.x * _facing_sign
		if forward <= 0.0 or forward > line_length:
			continue
		if _character_vertical_gap_to_scan_line(candidate) > maxf(whistle_line_vertical_tolerance,0.0):
			continue
		if forward < best_forward:
			best_forward = forward
			best = candidate
	return best

func _cleanup_dogs() -> void:
	var alive:Array[ball] = []
	var live_ids:Dictionary = {}
	for current_dog:ball in dogs:
		if current_dog == null or not is_instance_valid(current_dog) or current_dog.health <= 0:
			continue
		alive.append(current_dog)
		live_ids[current_dog.get_instance_id()] = true
	dogs = alive

	var stale_hunters:Array = []
	for hunter_id:Variant in _active_mark_hunters.keys():
		if not live_ids.has(hunter_id):
			stale_hunters.append(hunter_id)
	for hunter_id:Variant in stale_hunters:
		_active_mark_hunters.erase(hunter_id)


func _spawn_dog(startup_spawn:bool = false) -> void:
	if DOG_SCENE == null or not is_inside_tree() or health <= 0:
		return
	# V202：训犬师最多同时维持 3 条存活猎犬。先清理死亡/失效引用，再判断上限；
	# 达到上限时本轮计时器只跳过生成，不吹哨、不刷新吹哨动作冷却。
	_cleanup_dogs()
	if dogs.size() >= maxi(dog_max_count,1):
		return
	var world:Node = get_tree().current_scene
	if world == null:
		return
	# 开局初始化生成不进入吹哨冷却；之后周期召狗仍正常刷新统一动作冷却。
	if not startup_spawn:
		_record_whistle_action()
	_show_whistle_visual()
	_play_summon_whistle_everywhere(global_position)
	var new_dog:ball = DOG_SCENE.instantiate() as ball
	if new_dog == null:
		return
	new_dog.Master = self
	new_dog.Master_name = str(get_path())
	new_dog.Team = Team
	new_dog.inherit_master_attack_power = true
	new_dog.master_attack_damage_multiplier = 1.5
	new_dog.set("owner_trainer",self)
	new_dog.name = Game.return_random_name(new_dog)
	world.add_child(new_dog,true)

	_dog_spawn_serial += 1
	var alternating_sign:float = -1.0 if (_dog_spawn_serial % 2) == 0 else 1.0
	var vertical_offset:float = alternating_sign * dog_spawn_vertical_spread * (0.5 + float((_dog_spawn_serial - 1) % 3) * 0.25)
	var spawn_offset := Vector2(-_facing_sign * dog_spawn_distance,vertical_offset)
	new_dog.global_position = TOOLS.safe_spawn_position(self,global_position + spawn_offset,18.0)
	dogs.append(new_dog)
	_play_dog_command_bark_everywhere(new_dog.global_position)

	# 标记期间新来的狗也立即执行同一个目标，不需要等下一次扫描。
	if marked_target != null and is_instance_valid(marked_target) and TOOLS.is_enemy(self,marked_target):
		new_dog.call("assign_hunt_target",marked_target)
		if bool(new_dog.call("is_hunting")):
			var new_dog_id:int = new_dog.get_instance_id()
			_active_mark_hunters[new_dog_id] = true
			_mark_participants[new_dog_id] = true

func _assign_mark_to_available_dogs(target:ball) -> void:
	if target == null or not is_instance_valid(target):
		return
	for current_dog:ball in dogs:
		if current_dog == null or not is_instance_valid(current_dog) or current_dog.health <= 0:
			continue
		var dog_id:int = current_dog.get_instance_id()
		if _mark_participants.has(dog_id):
			continue
		current_dog.call("assign_hunt_target",target)
		if bool(current_dog.call("is_hunting")):
			_active_mark_hunters[dog_id] = true
			_mark_participants[dog_id] = true

func _add_marker_stroke(parent:Node2D,points_value:PackedVector2Array,width_value:float = -1.0) -> void:
	var stroke := Line2D.new()
	stroke.width = marker_line_width if width_value <= 0.0 else width_value
	stroke.default_color = marker_color
	stroke.antialiased = true
	stroke.points = points_value
	parent.add_child(stroke)

func _add_marker_center_dot(parent:Node2D) -> void:
	# 中央红点是独立静态层：外圈和四条线的缩放都不能带动它。
	var dot := Polygon2D.new()
	dot.name = "CenterDot"
	dot.color = marker_color
	var points := PackedVector2Array()
	var radius:float = 1.65
	for i:int in range(16):
		var angle:float = TAU * float(i) / 16.0
		points.append(Vector2(cos(angle),sin(angle)) * radius)
	dot.polygon = points
	parent.add_child(dot)

func _marker_arc_points(start_deg:float,end_deg:float,radius:float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps:int = 5
	for i:int in range(steps):
		var t:float = float(i) / float(steps - 1)
		var angle:float = deg_to_rad(lerpf(start_deg,end_deg,t))
		points.append(Vector2(cos(angle),sin(angle)) * radius)
	return points

func _build_marker_visual() -> Node2D:
	# V105：整体缩小，并把动画拆为三层：中央红点静止、断开圆环先收缩、四条线紧接着收缩。
	# 标记纯视觉；MarkDetector 与实际伤害碰撞几何仍完全独立。
	var marker := Node2D.new()
	marker.name = "DogTrainerMark"
	marker.top_level = true

	var center := Node2D.new()
	center.name = "MarkerCenter"
	marker.add_child(center)
	_add_marker_center_dot(center)

	var ring := Node2D.new()
	ring.name = "MarkerRing"
	marker.add_child(ring)
	# 比 V104 小约三分之一。四段弧在上下左右留口，保持用户草图的断开圆轮廓。
	var ring_radius:float = 11.5
	_add_marker_stroke(ring,_marker_arc_points(-72.0,-18.0,ring_radius))
	_add_marker_stroke(ring,_marker_arc_points(18.0,72.0,ring_radius))
	_add_marker_stroke(ring,_marker_arc_points(108.0,162.0,ring_radius))
	_add_marker_stroke(ring,_marker_arc_points(198.0,252.0,ring_radius))

	var arms := Node2D.new()
	arms.name = "MarkerArms"
	marker.add_child(arms)
	# 四条外伸线单独成层，稍晚于圆环开始缩小；总延迟只有几十毫秒。
	var arm_inner:float = 15.0
	var arm_outer:float = 22.0
	_add_marker_stroke(arms,PackedVector2Array([Vector2(0.0,-arm_inner),Vector2(0.0,-arm_outer)]))
	_add_marker_stroke(arms,PackedVector2Array([Vector2(arm_inner,0.0),Vector2(arm_outer,0.0)]))
	_add_marker_stroke(arms,PackedVector2Array([Vector2(0.0,arm_inner),Vector2(0.0,arm_outer)]))
	_add_marker_stroke(arms,PackedVector2Array([Vector2(-arm_inner,0.0),Vector2(-arm_outer,0.0)]))
	return marker

func _play_marker_spawn_animation(marker:Node2D) -> void:
	if marker == null or not is_instance_valid(marker):
		return
	var ring:Node2D = marker.get_node_or_null("MarkerRing") as Node2D
	var arms:Node2D = marker.get_node_or_null("MarkerArms") as Node2D
	var center:Node2D = marker.get_node_or_null("MarkerCenter") as Node2D

	# 中央红点从生成到结束始终 1x，不参加任何 Tween。
	if center != null:
		center.scale = Vector2.ONE
	if ring != null:
		ring.scale = Vector2.ONE * maxf(marker_ring_spawn_scale,1.0)
	if arms != null:
		arms.scale = Vector2.ONE * maxf(marker_arms_spawn_scale,1.0)

	# 圆环先开始收缩，四线仅晚约 0.055 秒开始；两个动画轻微重叠，避免看起来像两段割裂动作。
	var tween:Tween = marker.create_tween().set_parallel(true)
	if ring != null:
		tween.tween_property(ring,"scale",Vector2.ONE,maxf(marker_ring_shrink_duration,0.04)).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	if arms != null:
		tween.tween_property(arms,"scale",Vector2.ONE,maxf(marker_arms_shrink_duration,0.04)).set_delay(maxf(marker_arms_delay,0.0)).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

func _set_mark(target:ball) -> void:
	if target == null or not is_instance_valid(target) or not _whistle_action_ready():
		return
	_clear_mark()
	marked_target = target
	_record_whistle_action()
	_show_whistle_visual()
	_play_mark_whistle_everywhere()
	_play_all_dogs_mark_bark_everywhere()
	var marker:Node2D = _build_marker_visual()
	target.add_child(marker,true)
	_marker_visual = marker
	_update_marker_position()
	_play_marker_spawn_animation(marker)

func _update_marker_position() -> void:
	if _marker_visual == null or not is_instance_valid(_marker_visual):
		return
	if marked_target == null or not is_instance_valid(marked_target):
		_clear_mark()
		return
	_marker_visual.global_position = marked_target.global_position + Vector2(0.0,marker_offset_y)

func notify_hunt_finished(hunter:ball,target:ball,_hit:bool) -> void:
	if hunter != null and is_instance_valid(hunter):
		_active_mark_hunters.erase(hunter.get_instance_id())
	if target != marked_target:
		return
	if _active_mark_hunters.is_empty():
		_clear_mark()

func _clear_mark() -> void:
	marked_target = null
	_active_mark_hunters.clear()
	_mark_participants.clear()
	if _marker_visual != null and is_instance_valid(_marker_visual):
		_marker_visual.queue_free()
	_marker_visual = null


func _play_mark_whistle_everywhere() -> void:
	var pick:int = SHARED_WHISTLE.random_index()
	if multiplayer.has_multiplayer_peer():
		_rpc_play_mark_whistle.rpc(pick,global_position)
	else:
		_rpc_play_mark_whistle(pick,global_position)

@rpc("authority","call_local","unreliable")
func _rpc_play_mark_whistle(index:int,position_value:Vector2) -> void:
	SHARED_WHISTLE.play_at(self,index,position_value,-1.0,randf_range(0.98,1.02))

func _play_summon_whistle_everywhere(position_value:Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_summon_whistle.rpc(position_value)
	else:
		_rpc_play_summon_whistle(position_value)

@rpc("authority","call_local","unreliable")
func _rpc_play_summon_whistle(position_value:Vector2) -> void:
	TRAINER_AUDIO.play_summon_whistle_at(self,position_value,-1.0,randf_range(0.99,1.01))

func _play_dog_command_bark_everywhere(position_value:Vector2) -> void:
	var pick:int = TRAINER_AUDIO.random_dog_index()
	if multiplayer.has_multiplayer_peer():
		_rpc_play_dog_command_bark.rpc(pick,position_value)
	else:
		_rpc_play_dog_command_bark(pick,position_value)

@rpc("authority","call_local","unreliable")
func _rpc_play_dog_command_bark(index:int,position_value:Vector2) -> void:
	TRAINER_AUDIO.play_dog_at(self,index,position_value,-1.0,randf_range(0.97,1.03))

func _play_all_dogs_mark_bark_everywhere() -> void:
	for current_dog:ball in dogs:
		if current_dog == null or not is_instance_valid(current_dog) or current_dog.health <= 0:
			continue
		_play_dog_command_bark_everywhere(current_dog.global_position)

func Die() -> void:
	_visual_serial += 1
	if mark_line != null:
		mark_line.visible = false
	_clear_mark()
	if dog_spawn_timer != null and is_instance_valid(dog_spawn_timer):
		dog_spawn_timer.stop()
	for current_dog:ball in dogs:
		if current_dog != null and is_instance_valid(current_dog) and current_dog.has_method("force_owner_lost"):
			current_dog.call("force_owner_lost")
	dogs.clear()
	super()
