extends ball

const ANGRY_TEXTURE:Texture2D = preload("res://Images/characters/人物/愤怒的人/愤怒的人.png")
const VAN_FIST_TEXTURE:Texture2D = preload("res://Images/characters/人物/面包车/拳头.png")
const FIST_SWING_SFX:AudioStream = preload("res://audio/characters/面包车/拳头挥舞.mp3")
const FIST_HIT_SFX:AudioStream = preload("res://audio/characters/面包车/拳头命中.mp3")
const GANG_FLEE_SFX:AudioStream = preload("res://audio/characters/黑帮老大/跑路了兄弟.mp3")
const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")

@export_category("愤怒的人 - 战斗")
@export_range(28.0,120.0,0.1) var punch_range:float = 41.6
@export_range(0.0,50.0,0.5) var punch_knockback_distance:float = 14.0
@export_range(20.0,500.0,5.0) var punch_knockback_speed:float = 230.0
@export_range(70.0,300.0,1.0) var angry_visual_height:float = 185.0
@export_category("愤怒的人 - 房产证召唤逃跑")
@export_range(80.0,360.0,5.0) var property_flee_speed:float = 190.0
@export_range(20.0,160.0,1.0) var property_flee_exit_margin:float = 80.0

var deed_picker:ball = null
var _deed_picker_path:NodePath = NodePath()
var _deed_team:String = ""
var _summoning_leader_path:NodePath = NodePath()
var _property_fleeing:bool = false
var _property_flee_target:Vector2 = Vector2.ZERO
var _punching:bool = false
var _attack_target:ball = null
static var _fist_geometry_cache:Dictionary = {}


func _ready() -> void:
	Type = Ball_Type.Ball
	Has_Collision_Damage = false
	Can_Attack = true
	Can_Skill = false
	Health_Restore = 0
	Max_health = 200
	super._ready()
	health = mini(health,Max_health)
	_apply_angry_visual()


func _is_meaningful_team(team_value:String) -> bool:
	var normalized:String = team_value.strip_edges()
	return not normalized.is_empty() and normalized != "Ball"


func prime_property_deed_identity(config:Dictionary,picker_value:Variant = null) -> void:
	# V349：阵营快照只能在“房产证拾取配置”建立时写入。
	# 之后任何临时的 picker.Team / 网络默认 "Ball" 都不能反向污染 _deed_team。
	var configured_team:String = str(config.get("team","")).strip_edges()
	_deed_picker_path = config.get("picker_path",NodePath())
	_summoning_leader_path = config.get("summoner_leader_path",NodePath())

	var resolved_picker:ball = null
	if picker_value is ball and is_instance_valid(picker_value):
		resolved_picker = picker_value as ball
	elif not _deed_picker_path.is_empty() and is_inside_tree():
		var picker_node:Node = get_node_or_null(_deed_picker_path)
		if picker_node is ball and is_instance_valid(picker_node):
			resolved_picker = picker_node as ball

	# 配置快照优先；只有快照本身无效时才允许从当前 picker 补一次。
	if _is_meaningful_team(configured_team):
		_deed_team = configured_team
	elif resolved_picker != null and _is_meaningful_team(resolved_picker.Team):
		_deed_team = resolved_picker.Team.strip_edges()

	deed_picker = resolved_picker
	if deed_picker != null:
		Master = deed_picker
		Master_name = str(deed_picker.get_path())
	elif not _deed_picker_path.is_empty():
		Master_name = str(_deed_picker_path)

	if _is_meaningful_team(_deed_team):
		Team = _deed_team
		set_meta(&"forced_combat_team",_deed_team)


func _enforce_property_deed_identity() -> void:
	# 只重新解析 picker 引用，不再用 picker.Team 覆盖已确定的房产证队伍快照。
	if deed_picker == null or not is_instance_valid(deed_picker):
		deed_picker = null
		if not _deed_picker_path.is_empty():
			var picker_node:Node = get_node_or_null(_deed_picker_path)
			if picker_node is ball and is_instance_valid(picker_node):
				deed_picker = picker_node as ball

	if deed_picker != null and is_instance_valid(deed_picker):
		Master = deed_picker
		Master_name = str(deed_picker.get_path())

	# 只有初始快照没拿到有效队伍时，才允许用一个“现在已经有效”的 picker.Team 补齐一次。
	if not _is_meaningful_team(_deed_team):
		if deed_picker != null and is_instance_valid(deed_picker) and _is_meaningful_team(deed_picker.Team):
			_deed_team = deed_picker.Team.strip_edges()

	if _is_meaningful_team(_deed_team):
		if Team != _deed_team:
			Team = _deed_team
		set_meta(&"forced_combat_team",_deed_team)


func configure_from_property_deed(config:Dictionary) -> void:
	global_position = config.get("origin",global_position)
	prime_property_deed_identity(config,deed_picker)
	_enforce_property_deed_identity()
	Speed = maxf(float(config.get("speed",Speed)),10.0)
	Attack_Cooling = maxf(float(config.get("attack_interval",Attack_Cooling)),0.1)
	Damage = maxf(float(config.get("damage",Damage)),0.0)
	punch_knockback_distance = maxf(float(config.get("knockback_distance",punch_knockback_distance)),0.0)
	punch_knockback_speed = maxf(float(config.get("knockback_speed",punch_knockback_speed)),10.0)
	Max_health = 200
	health = 200
	if default_properties != null:
		default_properties["Max_health"] = 200
		default_properties["Speed"] = Speed
		default_properties["Damage"] = Damage
		default_properties["Team"] = Team


func tick_physics(state:State,delta:float) -> void:
	_enforce_property_deed_identity()

	if is_multiplayer_authority() and health > 0 and state_machine.current_state != State.Die:
		if not _property_fleeing and _should_flee_from_summoning_leader():
			_begin_property_flee()
		if _property_fleeing:
			_update_property_flee()
			if is_queued_for_deletion():
				return

	# V353：正常战斗阶段不再自己把 direction 锁向最近敌人。
	# 完全交回 ball.gd 的普通 CharacterBody2D 移动链：
	# direction -> 公共 move() -> move_and_slide() -> 公共碰撞处理。
	super.tick_physics(state,delta)


func Attack() -> void:
	if _property_fleeing or state_machine.current_state == State.Die or not is_multiplayer_authority() or _punching:
		Attacking = false
		return

	var target:ball = TOOLS.nearest_enemy(self,punch_range)
	if target == null or not is_instance_valid(target) or not _is_legal_enemy(target):
		Attacking = false
		return
	if global_position.distance_to(target.global_position) > punch_range:
		Attacking = false
		return

	Attacking = true
	_punching = true
	_run_fist_attack(target)


func _run_fist_attack(target:ball) -> void:
	if target == null or not is_instance_valid(target):
		_punching = false
		Attacking = false
		return

	var attack_dir:Vector2 = target.global_position - global_position
	if attack_dir.length_squared() <= 0.0001:
		attack_dir = Vector2.RIGHT
	attack_dir = attack_dir.normalized()

	# 与面包车拳头小混混完全同一几何：
	# 拳头 PNG alpha -> polygon，真实拳长 30.4px，世界坐标 Area2D，不继承人物根 scale。
	var weapon:Area2D = _create_fist_weapon_area()
	if weapon == null:
		_punching = false
		Attacking = false
		return

	var world:Node = get_tree().current_scene
	if world == null:
		weapon.queue_free()
		_punching = false
		Attacking = false
		return

	world.add_child(weapon)
	weapon.global_rotation = attack_dir.angle()
	_play_fist_audio(false,global_position)

	var hit_ids:Dictionary = {}
	var steps:int = 12
	for i:int in range(steps):
		if not _fist_attack_still_valid():
			break
		var t:float = float(i) / float(maxi(steps - 1,1))
		# 与 VAN_FIST 完全一致：一拳伸出再收回。
		var extension:float = sin(t * PI) * 12.8
		weapon.global_position = global_position + attack_dir * (3.2 + extension)
		weapon.global_rotation = attack_dir.angle()
		await get_tree().physics_frame
		_damage_fist_overlaps(weapon,hit_ids)

	if weapon != null and is_instance_valid(weapon):
		weapon.queue_free()
	_punching = false
	Attacking = false


func _fist_attack_still_valid() -> bool:
	return (
		is_instance_valid(self)
		and not is_queued_for_deletion()
		and health > 0
		and not _property_fleeing
	)


func _create_fist_weapon_area() -> Area2D:
	if VAN_FIST_TEXTURE == null:
		return null
	var geometry:Dictionary = _fist_weapon_geometry()
	if geometry.is_empty():
		return null

	var area := Area2D.new()
	area.name = "AngryFistAttack"
	area.collision_layer = 0
	area.collision_mask = 0xFFFFFFFF
	area.monitoring = true
	area.monitorable = false
	area.z_index = 25

	var sprite := Sprite2D.new()
	sprite.texture = VAN_FIST_TEXTURE
	sprite.centered = true
	sprite.position = geometry.get("sprite_position",Vector2.ZERO)
	sprite.rotation = float(geometry.get("sprite_rotation",0.0))
	var sprite_scale:float = float(geometry.get("sprite_scale",1.0))
	sprite.scale = Vector2.ONE * sprite_scale
	sprite.z_index = 1
	area.add_child(sprite)

	var polygons:Array = geometry.get("polygons",[])
	for raw_polygon:Variant in polygons:
		if not (raw_polygon is PackedVector2Array):
			continue
		var polygon:PackedVector2Array = PackedVector2Array(raw_polygon)
		if polygon.size() < 3:
			continue
		var collision := CollisionPolygon2D.new()
		collision.polygon = polygon
		area.add_child(collision)
	return area


func _fist_weapon_geometry() -> Dictionary:
	var key:String = "%s|%.4f|%.2f" % [VAN_FIST_TEXTURE.resource_path,deg_to_rad(-90.0),30.4]
	if _fist_geometry_cache.has(key):
		return _fist_geometry_cache[key]

	var image_data:Image = VAN_FIST_TEXTURE.get_image()
	if image_data == null or image_data.is_empty():
		return {}

	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(image_data,0.08)
	var source_polygons:Array[PackedVector2Array] = bitmap.opaque_to_polygons(
		Rect2i(Vector2i.ZERO,image_data.get_size()),
		3.0
	)
	if source_polygons.is_empty():
		return {}

	# 与 投稿随从.gd::VAN_FIST 相同：素材手柄方向 -90° 对齐到本地 +X。
	var source_tip_angle:float = deg_to_rad(-90.0)
	var correction:float = -source_tip_angle
	var image_center := Vector2(image_data.get_width() * 0.5,image_data.get_height() * 0.5)
	var min_x:float = INF
	var max_x:float = -INF
	var min_y:float = INF
	var max_y:float = -INF
	for polygon:PackedVector2Array in source_polygons:
		for p:Vector2 in polygon:
			var aligned:Vector2 = (p - image_center).rotated(correction)
			min_x = minf(min_x,aligned.x)
			max_x = maxf(max_x,aligned.x)
			min_y = minf(min_y,aligned.y)
			max_y = maxf(max_y,aligned.y)

	var raw_length:float = maxf(max_x - min_x,1.0)
	var uniform_scale:float = 30.4 / raw_length
	var shift := Vector2(-min_x * uniform_scale,-(min_y + max_y) * 0.5 * uniform_scale)

	var final_polygons:Array[PackedVector2Array] = []
	for polygon:PackedVector2Array in source_polygons:
		var transformed := PackedVector2Array()
		transformed.resize(polygon.size())
		for i:int in range(polygon.size()):
			transformed[i] = (polygon[i] - image_center).rotated(correction) * uniform_scale + shift
		final_polygons.append(transformed)

	var result:Dictionary = {
		"polygons":final_polygons,
		"sprite_position":shift,
		"sprite_rotation":correction,
		"sprite_scale":uniform_scale,
	}
	_fist_geometry_cache[key] = result
	return result


func _damage_fist_overlaps(weapon:Area2D,hit_ids:Dictionary) -> void:
	if weapon == null or not is_instance_valid(weapon):
		return
	for area:Area2D in weapon.get_overlapping_areas():
		_try_damage_fist_target(_collision_owner_ball(area),hit_ids)
	for body:Node2D in weapon.get_overlapping_bodies():
		_try_damage_fist_target(_collision_owner_ball(body),hit_ids)


func _collision_owner_ball(node:Node) -> ball:
	var current:Node = node
	for _i:int in range(8):
		if current == null:
			break
		if current is ball:
			return current as ball
		current = current.get_parent()
	return null


func _try_damage_fist_target(target:ball,hit_ids:Dictionary) -> void:
	if target == null or not is_instance_valid(target) or target.health <= 0:
		return
	if not _is_legal_enemy(target):
		return

	var target_id:int = target.get_instance_id()
	if hit_ids.has(target_id):
		return
	hit_ids[target_id] = true

	var impact_position:Vector2 = target.global_position
	var before_health:float = float(target.health)
	var dealt:bool = target.receive_positional_damage(
		attack_damage(),
		impact_position,
		false,
		self
	)
	if not dealt:
		return

	var health_loss:float = maxf(before_health - float(target.health),0.0)
	if health_loss > 0.0 and Game.has_method("report_training_damage"):
		Game.report_training_damage(self,target,health_loss)

	_play_fist_audio(true,impact_position)

	# 与面包车拳头小混混完全相同的小击退。
	var fist_push_dir:Vector2 = target.global_position - global_position
	if fist_push_dir.length_squared() <= 0.0001:
		fist_push_dir = Vector2.RIGHT
	target.apply_knockback(
		fist_push_dir.normalized(),
		punch_knockback_distance,
		punch_knockback_speed,
		0.0,
		0.0,
		{"source":self,"lock_control":true,"stop_on_character":true}
	)


func _is_legal_enemy(candidate:ball) -> bool:
	if preload("res://scripts/characters/我的世界/haochen/copy_friendly_guard.gd").skips_target(self,candidate): return false # 皓宸复制品及其产物不把己方选为目标
	if candidate == null or not is_instance_valid(candidate) or candidate == self:
		return false
	if not candidate.is_combat_targetable() or candidate.health <= 0:
		return false
	# V349：房产证召唤物属于小弟语义，永远不把同主人/同召唤链/同有效队伍当敌人；
	# 不再让全局友伤开关把自己的队友重新塞进 AI 敌人列表。
	if TOOLS.same_side(self,candidate):
		return false
	return true



func _should_flee_from_summoning_leader() -> bool:
	# 从“小弟分类”直接选出的独立愤怒的人没有 summoner 路径，不触发这条规则。
	if _summoning_leader_path.is_empty():
		return false
	var leader_node:Node = get_node_or_null(_summoning_leader_path)
	if leader_node == null or not is_instance_valid(leader_node):
		return true
	if leader_node.is_queued_for_deletion():
		return true
	if leader_node is ball:
		return (leader_node as ball).health <= 0
	return true


func _begin_property_flee() -> void:
	if _property_fleeing or health <= 0:
		return
	_property_fleeing = true
	_attack_target = null
	_punching = false
	Attacking = false
	Using_Skill = false
	Can_Attack = false
	Can_Skill = false
	Has_Collision_Damage = false
	Speed = property_flee_speed
	if default_properties != null:
		default_properties["Speed"] = Speed

	if self_hitbox != null and is_instance_valid(self_hitbox):
		self_hitbox.set_deferred(&"monitoring",false)

	# 与面包车小弟一致：跑路时退出实体阻挡，并允许 World 不把越界角色救回地图。
	collision_layer = 0
	collision_mask = 0
	set_meta(&"submission_allow_map_escape",true)
	_pick_property_flee_exit()
	_play_property_flee_audio()


func _pick_property_flee_exit() -> void:
	var rect:Rect2 = TOOLS.map_rect(self)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		_property_flee_target = global_position + Vector2.RIGHT * 500.0
		direction = Vector2.RIGHT
		return

	var p:Vector2 = global_position
	var distances := PackedFloat32Array([
		absf(p.x - rect.position.x),
		absf(rect.end.x - p.x),
		absf(p.y - rect.position.y),
		absf(rect.end.y - p.y),
	])
	var best_index:int = 0
	var best_value:float = distances[0]
	for i:int in range(1,distances.size()):
		if distances[i] < best_value:
			best_index = i
			best_value = distances[i]

	match best_index:
		0:
			_property_flee_target = Vector2(rect.position.x - property_flee_exit_margin,p.y)
		1:
			_property_flee_target = Vector2(rect.end.x + property_flee_exit_margin,p.y)
		2:
			_property_flee_target = Vector2(p.x,rect.position.y - property_flee_exit_margin)
		_:
			_property_flee_target = Vector2(p.x,rect.end.y + property_flee_exit_margin)

	var to_exit:Vector2 = _property_flee_target - global_position
	direction = to_exit.normalized() if to_exit.length_squared() > 0.000001 else Vector2.RIGHT


func _update_property_flee() -> void:
	var to_exit:Vector2 = _property_flee_target - global_position
	if to_exit.length_squared() > 0.001:
		direction = to_exit.normalized()

	var rect:Rect2 = TOOLS.map_rect(self)
	if rect.size.x > 0.0 and rect.size.y > 0.0:
		if not rect.grow(18.0).has_point(global_position):
			queue_free()
	elif global_position.distance_to(_property_flee_target) <= 12.0:
		queue_free()


func _play_property_flee_audio() -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_property_flee_audio.rpc(global_position)
	else:
		_rpc_play_property_flee_audio(global_position)


@rpc("authority","call_local","unreliable")
func _rpc_play_property_flee_audio(position_value:Vector2) -> void:
	var world:Node = get_tree().current_scene
	if world == null or GANG_FLEE_SFX == null:
		return

	# 和面包车/黑帮小弟共用同一个全局防叠计时键，避免多个小弟同时跑路叠成人声墙。
	var now_msec:int = Time.get_ticks_msec()
	var last_msec:int = int(world.get_meta("_gang_flee_sfx_last_msec",-100000))
	if now_msec - last_msec < 650:
		return
	world.set_meta("_gang_flee_sfx_last_msec",now_msec)

	var player := AudioStreamPlayer2D.new()
	player.stream = GANG_FLEE_SFX
	player.volume_db = -4.0
	player.max_distance = 1500.0
	player.attenuation = 0.45
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	world.add_child(player)
	player.global_position = position_value
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _apply_angry_visual() -> void:
	if not (image is Sprite2D):
		return
	var sprite:Sprite2D = image as Sprite2D
	sprite.texture = ANGRY_TEXTURE
	sprite.visible = true
	var source_height:float = maxf(float(ANGRY_TEXTURE.get_height()),1.0)
	sprite.scale = Vector2.ONE * (angry_visual_height / source_height)


func _play_fist_audio(hit:bool,position_value:Vector2) -> void:
	if multiplayer.has_multiplayer_peer():
		_rpc_play_fist_audio.rpc(hit,position_value)
	else:
		_rpc_play_fist_audio(hit,position_value)


@rpc("authority","call_local","unreliable")
func _rpc_play_fist_audio(hit:bool,position_value:Vector2) -> void:
	var stream:AudioStream = FIST_HIT_SFX if hit else FIST_SWING_SFX
	if stream == null:
		return
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = 0.0 if hit else -2.0
	player.max_distance = 1350.0
	player.attenuation = 0.48
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	world.add_child(player)
	player.global_position = position_value
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()
