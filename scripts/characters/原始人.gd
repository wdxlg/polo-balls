extends ball

const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")
const FIRE_SCENE:PackedScene = preload("res://scenes/terrain/原始人火堆.tscn")
const SFX_WAR_GODDESS_BURN_TICK:AudioStream = preload("res://audio/status/debuff/烫伤.wav")

@export_category("原始人 - 视觉")
@export var normal_texture:Texture2D
@export var dash_texture:Texture2D

@export_category("原始人 - 火堆")
@export_range(1,12,1) var fire_count:int = 3
@export_range(6.0,80.0,1.0) var fire_map_margin:float = 18.0
@export_range(20.0,180.0,2.0) var fire_min_spacing:float = 62.0
@export_range(1,240,1) var fire_spawn_wait_frames:int = 120
@export_range(0.0,100.0,1.0) var fire_heal_per_second:float = 8.0
@export_range(20.0,240.0,5.0) var fire_heal_radius:float = 78.0

@export_category("原始人 - 烈焰冲锋")
@export_range(0.05,2.0,0.05) var dash_windup:float = 0.45
@export_range(1.0,4.0,0.05) var dash_speed_multiplier:float = 2.20
@export_range(0.0,100.0,0.05) var dash_damage_multiplier:float = 83.3333333

@onready var dash_area:Area2D = $DashDamageArea
@onready var character_image:Sprite2D = $Graphics/Image

var _normal_speed:float = 0.0
var _dash_pending:bool = false
var _dashing:bool = false
var _dash_direction:Vector2 = Vector2.ZERO
var _manual_dash_available:bool = false
var _manual_dash_target:Vector2 = Vector2.ZERO
var _saved_collision_mask:int = 0
var _dash_hit_ids:Dictionary = {}
var _fires:Array[Node2D] = []
var _fire_heal_bank:float = 0.0
var _primitive_burn_audio_serial:int = 0

func _ready() -> void:
	Can_Attack = false
	Can_Skill = false
	Has_Collision_Damage = false
	super._ready()
	_normal_speed = Speed
	_set_character_texture(normal_texture)
	dash_area.top_level = true
	dash_area.global_rotation = 0.0
	dash_area.set_meta("threat_debug_damage",attack_damage(dash_damage_multiplier))
	if is_multiplayer_authority():
		call_deferred("_spawn_initial_fires")

func _set_character_texture(texture_value:Texture2D) -> void:
	if texture_value == null or character_image == null:
		return
	character_image.texture = texture_value
	var auto_fit:Node = get_node_or_null("CharacterAutoFit")
	if auto_fit != null and auto_fit.has_method("apply_visual_fit_only"):
		auto_fit.call("apply_visual_fit_only")

func is_primitive_character() -> bool:
	return true

# V82：原始人普通身体接触永远没有伤害。
# 唯一角色本体伤害来源是烈焰冲锋期间的 DashDamageArea。
func has_collision_damage() -> bool:
	return false

func _physics_process(delta:float) -> void:
	if health <= 0:
		_cleanup_owned_fires()
		return
	if not is_multiplayer_authority():
		return
	dash_area.global_position = global_position
	dash_area.global_rotation = 0.0
	_heal_near_lit_fire(delta)
	if not is_player_controlled() and _manual_dash_available and not _dash_pending and not _dashing:
		# 放开接管后，未使用的受火堆触发冲锋按原 AI 机制继续执行。
		_manual_dash_available = false
		_dash_pending = true
		call_deferred("_begin_fire_dash",_manual_dash_target)
	if _dashing:
		direction = _dash_direction
		_process_dash_hits()


func controlled_attack_action() -> void:
	# 左键：仅在火堆被敌人触发后才能释放已有的烈焰冲锋。
	if not is_player_controlled() or not is_multiplayer_authority() or health <= 0 or not is_combat_runtime_active():
		return
	if not _manual_dash_available or _dash_pending or _dashing:
		return
	_manual_dash_available = false
	_dash_pending = true
	call_deferred("_begin_fire_dash",_manual_dash_target)


func move(speed:float,delta:float):
	# 已发动的冲锋锁定到触发火堆的方向，期间暂时忽略 WASD，结束后恢复。
	if _dashing and is_player_controlled():
		var input_direction:Vector2 = player_control_direction
		player_control_direction = _dash_direction
		super.move(speed,delta)
		player_control_direction = input_direction
		return
	super.move(speed,delta)

# V81：等待地图矩形真正可用后，再在整张地图里做分散随机。
# 旧 V80 的固定 72px 边距对 10x10 常用地图过大：160px 左右的地图会只剩中央十几像素可随机。
func _wait_for_valid_map_rect() -> Rect2:
	for _frame:int in range(maxi(fire_spawn_wait_frames,1)):
		if not is_inside_tree() or health <= 0:
			return Rect2()
		var rect:Rect2 = TOOLS.map_rect(self)
		if rect.size.x > 32.0 and rect.size.y > 32.0:
			return rect
		await get_tree().physics_frame
	return Rect2(global_position - Vector2(300.0,220.0),Vector2(600.0,440.0))

func _effective_fire_margin(rect:Rect2) -> float:
	var min_side:float = minf(rect.size.x,rect.size.y)
	if min_side <= 1.0:
		return 6.0
	return maxf(6.0,minf(fire_map_margin,min_side * 0.10))

func _effective_fire_spacing(rect:Rect2) -> float:
	var min_side:float = minf(rect.size.x,rect.size.y)
	if min_side <= 1.0:
		return fire_min_spacing
	return maxf(20.0,minf(fire_min_spacing,min_side * 0.40))

func _spawn_initial_fires() -> void:
	if FIRE_SCENE == null or not is_inside_tree():
		return
	var rect:Rect2 = await _wait_for_valid_map_rect()
	if rect.size.x <= 1.0 or rect.size.y <= 1.0 or not is_inside_tree() or health <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = Game.battle_rng_seed_or("scripts/characters/原始人.gd:rng.seed",int(get_instance_id()) ^ int(Time.get_ticks_usec()))
	var points:Array[Vector2] = _build_spread_fire_points(rect,rng,maxi(fire_count,1))
	for point:Vector2 in points:
		_spawn_fire(point)

# 把整个可用地图切成若干大格，再随机打乱格子。默认 3 个火堆会优先占用不同的大区域，
# 每个火堆仍在自己的大区域内随机，不会固定在格子中心。
func _build_spread_fire_points(rect:Rect2,rng:RandomNumberGenerator,count:int) -> Array[Vector2]:
	var margin:float = _effective_fire_margin(rect)
	var inner := Rect2(
		rect.position + Vector2.ONE * margin,
		rect.size - Vector2.ONE * margin * 2.0
	)
	if inner.size.x <= 1.0 or inner.size.y <= 1.0:
		inner = rect

	var aspect:float = inner.size.x / maxf(inner.size.y,1.0)
	var cols:int = maxi(int(ceil(sqrt(float(count) * maxf(aspect,0.25)))),1)
	var rows:int = maxi(int(ceil(float(count) / float(cols))),1)
	var cells:Array[int] = []
	for index:int in range(cols * rows):
		cells.append(index)
	for i:int in range(cells.size() - 1,0,-1):
		var j:int = rng.randi_range(0,i)
		var tmp:int = cells[i]
		cells[i] = cells[j]
		cells[j] = tmp

	var occupied:Array[Vector2] = []
	for raw:Node in get_tree().get_nodes_in_group("PrimitiveCampfire"):
		if raw is Node2D and is_instance_valid(raw):
			occupied.append((raw as Node2D).global_position)

	var chosen:Array[Vector2] = []
	var cell_size := Vector2(inner.size.x / float(cols),inner.size.y / float(rows))
	var required_spacing:float = _effective_fire_spacing(rect)
	for i:int in range(count):
		var cell_index:int = cells[i % cells.size()]
		var cx:int = cell_index % cols
		var cy:int = int(cell_index / cols)
		var cell_pos := inner.position + Vector2(float(cx),float(cy)) * cell_size
		var best_point := cell_pos + cell_size * 0.5
		var best_clearance:float = -1.0
		for _attempt:int in range(28):
			var point := Vector2(
				rng.randf_range(cell_pos.x + cell_size.x * 0.08,cell_pos.x + cell_size.x * 0.92),
				rng.randf_range(cell_pos.y + cell_size.y * 0.08,cell_pos.y + cell_size.y * 0.92)
			)
			var clearance:float = _minimum_fire_clearance(point,occupied,chosen)
			if clearance > best_clearance:
				best_clearance = clearance
				best_point = point
			if clearance >= required_spacing:
				break
		chosen.append(best_point)
	return chosen

func _minimum_fire_clearance(point:Vector2,occupied:Array[Vector2],chosen:Array[Vector2]) -> float:
	var nearest:float = INF
	for old:Vector2 in occupied:
		nearest = minf(nearest,old.distance_to(point))
	for old:Vector2 in chosen:
		nearest = minf(nearest,old.distance_to(point))
	return nearest

func _spawn_fire(position_value:Vector2) -> void:
	if not is_inside_tree():
		return
	var fire:Node2D = FIRE_SCENE.instantiate() as Node2D
	if fire == null:
		return
	fire.set("owner_primitive",self)
	fire.name = Game.return_random_name(fire)
	# V85：火堆属于原始人的生命周期，但保持世界空间变换。
	# 这样原始人 queue_free 时 Godot 会递归释放火堆，同时不会继承 ball 根节点的缩放。
	fire.top_level = true
	add_child(fire,true)
	var current_rect:Rect2 = TOOLS.map_rect(self)
	fire.global_position = TOOLS.safe_spawn_position(self,position_value,_effective_fire_margin(current_rect))
	_fires.append(fire)

func _heal_near_lit_fire(delta:float) -> void:
	if health >= Max_health:
		return
	for fire:Node2D in _fires:
		if fire == null or not is_instance_valid(fire):
			continue
		if not bool(fire.get("lit")):
			continue
		if global_position.distance_to(fire.global_position) <= fire_heal_radius:
			_fire_heal_bank += fire_heal_per_second * delta
			var whole_heal:int = int(floor(_fire_heal_bank))
			if whole_heal > 0:
				_fire_heal_bank -= float(whole_heal)
				health += whole_heal
			return


# V97：原始人火堆所有伤害统一复用战争女神灼烧的伤害音效。
# 名字保持与战争女神一致，让既有 战争女神_灼烧.gd 在 source=原始人时也会自动调用这里。
func play_war_burn_tick_sfx(position_value:Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		_play_primitive_burn_tick_sfx_rpc.rpc(position_value)
	else:
		_play_primitive_burn_tick_sfx_rpc(position_value)


@rpc("authority","call_local","unreliable")
func _play_primitive_burn_tick_sfx_rpc(position_value:Vector2) -> void:
	if SFX_WAR_GODDESS_BURN_TICK == null or not is_inside_tree():
		return
	var player := AudioStreamPlayer2D.new()
	_primitive_burn_audio_serial += 1
	player.name = "PrimitiveBurnTick_%d" % _primitive_burn_audio_serial
	player.top_level = true
	player.stream = SFX_WAR_GODDESS_BURN_TICK
	# 与战争女神 burn_tick_sfx_volume_db / war_sfx_* 的默认值保持一致。
	player.volume_db = 1.0
	player.max_distance = 900.0
	player.attenuation = 0.75
	player.pitch_scale = randf_range(0.97,1.04)
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	add_child(player,true)
	player.global_position = position_value
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()

func request_fire_dash(fire:Node2D) -> void:
	if _dash_pending or _dashing or _manual_dash_available or fire == null or not is_instance_valid(fire) or health <= 0:
		return
	if is_player_controlled():
		_manual_dash_target = fire.global_position
		_manual_dash_available = true
		return
	_dash_pending = true
	call_deferred("_begin_fire_dash",fire.global_position)

func _begin_fire_dash(target_position:Vector2) -> void:
	await get_tree().create_timer(maxf(dash_windup,0.01)).timeout
	if not is_instance_valid(self) or health <= 0:
		return
	var to_fire:Vector2 = target_position - global_position
	if to_fire.length_squared() <= 0.000001:
		_dash_pending = false
		return
	_dash_pending = false
	_dashing = true
	_set_character_texture(dash_texture)
	_dash_hit_ids.clear()
	_dash_direction = to_fire.normalized()
	_normal_speed = maxf(_normal_speed,Speed)
	Speed = _normal_speed * maxf(dash_speed_multiplier,1.0)
	_saved_collision_mask = collision_mask
	# 冲锋身体只撞地图墙体（Layer1）；伤害由独立 DashDamageArea 对 Layer2 人物结算。
	collision_mask = 1
	direction = _dash_direction

func _process_dash_hits() -> void:
	for raw:Node2D in dash_area.get_overlapping_bodies():
		if not raw is ball:
			continue
		var target:ball = raw as ball
		if not TOOLS.is_enemy(self,target):
			continue
		var id:int = target.get_instance_id()
		if _dash_hit_ids.has(id):
			continue
		_dash_hit_ids[id] = true
		target.receive_spatial_damage(
			attack_damage(dash_damage_multiplier),
			{"shape":"rect","center":global_position,"size":Vector2(54.0,34.0),"source":self},
			false,
			false
		)

func when_collide(speed:float,collision:KinematicCollision2D) -> void:
	if _dashing:
		_end_dash()
		return
	super(speed,collision)

func _end_dash() -> void:
	if not _dashing:
		return
	_dashing = false
	_set_character_texture(normal_texture)
	Speed = _normal_speed
	collision_mask = _saved_collision_mask
	_dash_hit_ids.clear()

func _cleanup_owned_fires() -> void:
	for fire:Node2D in _fires:
		if fire != null and is_instance_valid(fire) and not fire.is_queued_for_deletion():
			fire.queue_free()
	_fires.clear()

func Die() -> void:
	_end_dash()
	_cleanup_owned_fires()
	super()
