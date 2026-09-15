extends ball

const WALL_SCENE:PackedScene = preload("res://scenes/creatures/建筑工人_墙.tscn")
const BRICK_SCENE:PackedScene = preload("res://scenes/shooter/建筑工人_砖块.tscn")
const VISUAL_NORMAL:Texture2D = preload("res://Images/characters/建筑工人/普通.png")
const VISUAL_BUILD:Texture2D = preload("res://Images/characters/建筑工人/造墙.png")
const VISUAL_BRICK_READY:Texture2D = preload("res://Images/characters/建筑工人/举砖准备.png")
const VISUAL_BRICK_THROW:Texture2D = preload("res://Images/characters/建筑工人/扔砖.png")
const AUDIO_BUILD:AudioStream = preload("res://audio/characters/建筑工人/建墙.wav")
const AUDIO_THROW_BRICK:AudioStream = preload("res://audio/characters/建筑工人/扔砖头.wav")

@export_category("建筑工人 - 造墙")
@export_range(10.0,180.0,1.0) var wall_spawn_distance:float = 32.0
@export_range(0.0,80.0,1.0) var wall_spawn_side_jitter:float = 2.0
@export_range(0.0,100.0,1.0) var wall_map_margin:float = 20.0
@export_range(0.25,2.0,0.05) var build_action_time:float = 1.05
@export_range(0.0,3.0,0.05) var post_build_attack_lock:float = 0.90

@export_category("建筑工人 - 抛砖")
@export_range(100.0,1000.0,10.0) var brick_speed:float = 430.0
@export_range(0.0,10.0,0.05) var brick_enemy_damage_multiplier:float = 1.3333333
@export_range(0.0,10.0,0.05) var brick_wall_damage_multiplier:float = 1.0
@export_range(0.0,120.0,1.0) var brick_knockback_distance:float = 24.0
@export_range(50.0,1000.0,10.0) var brick_knockback_speed:float = 360.0
@export_range(0.05,0.8,0.01) var brick_throw_pose_time:float = 0.16

var _owned_wall:ball = null
var _active_brick:Area2D = null
var _builder_action_audio:AudioStreamPlayer2D = null
var _building_wall:bool = false
var _post_build_attack_lock_left:float = 0.0


func _ready() -> void:
	super._ready()
	image_color = Color.WHITE
	image_color_mix = 0.0
	set_image_color()
	_set_builder_visual(VISUAL_NORMAL)


func get_preview_texture() -> Texture2D:
	# 放置预览不会执行 _ready()；显式告诉 world.gd 使用角色的正常立绘。
	return VISUAL_NORMAL


func _set_builder_visual(texture:Texture2D) -> void:
	if not image is Sprite2D or texture == null:
		return
	var sprite:Sprite2D = image as Sprite2D
	if sprite.texture == texture:
		return
	sprite.texture = texture
	sprite.offset = Vector2.ZERO
	sprite.visible = true
	var fitter:Node = get_node_or_null("CharacterAutoFit")
	if fitter != null and fitter.has_method("apply_visual_fit_only"):
		fitter.call_deferred("apply_visual_fit_only")


func get_next_state(state:State) -> int:
	# 没有可砸的活墙、或者上一块砖还在飞时，不启动普通攻击。
	if (
		is_multiplayer_authority()
		and Can_Attack
		and not is_damage_output_disabled()
		and state_machine.last_state_dis.Attack >= Attack_Cooling
		and (_nearest_owned_wall() == null or _has_active_brick() or _post_build_attack_lock_left > 0.0)
	):
		var saved_attack_time:float = float(state_machine.last_state_dis.Attack)
		Can_Attack = false
		var next_state:int = super.get_next_state(state)
		Can_Attack = true
		state_machine.last_state_dis.Attack = saved_attack_time
		return next_state

	# 角色设计固定为“同时只能有一堵自己的墙”。
	# 包括已经死亡、正在等待倒塌/下沉的墙；必须等旧墙真正离场后才能造下一堵。
	if (
		is_multiplayer_authority()
		and Can_Skill
		and not is_damage_output_disabled()
		and state_machine.last_state_dis.Skill >= Skill_Cooling
		and _has_any_owned_wall()
	):
		var saved_skill_time:float = float(state_machine.last_state_dis.Skill)
		Can_Skill = false
		var next_without_skill:int = super.get_next_state(state)
		Can_Skill = true
		state_machine.last_state_dis.Skill = saved_skill_time
		return next_without_skill

	return super.get_next_state(state)


func Skill() -> void:
	if state_machine.current_state == State.Die or not is_multiplayer_authority():
		Using_Skill = false
		return
	if is_damage_output_disabled() or _has_any_owned_wall():
		Using_Skill = false
		return

	Using_Skill = true
	_building_wall = true
	velocity = Vector2.ZERO
	Repel = Vector2.ZERO
	_set_builder_visual(VISUAL_BUILD)
	_start_builder_action_audio(AUDIO_BUILD)

	# 建墙期间角色保持原地，完整等待建造时间后才生成墙。
	var action_time:float = maxf(build_action_time,0.25)
	await get_tree().create_timer(action_time).timeout
	if not is_instance_valid(self):
		return
	if state_machine.current_state == State.Die or is_damage_output_disabled() or _has_any_owned_wall():
		_finish_build_action(state_machine.current_state != State.Die)
		return

	_spawn_wall()
	_finish_build_action(true)


func tick_physics(state:State,delta:float) -> void:
	_post_build_attack_lock_left = maxf(_post_build_attack_lock_left - maxf(delta,0.0),0.0)
	if _building_wall:
		# ball 的 Skill 状态默认也会调用 move(Speed)，这里强制按 Stand 处理，
		# 同时清掉本帧击退，保证施工动作期间位置不发生变化。
		velocity = Vector2.ZERO
		Repel = Vector2.ZERO
		super.tick_physics(State.Stand,delta)
		velocity = Vector2.ZERO
		return
	super.tick_physics(state,delta)


func _finish_build_action(restore_visual:bool) -> void:
	_building_wall = false
	_stop_builder_action_audio()
	if restore_visual and state_machine.current_state != State.Die:
		_set_builder_visual(VISUAL_NORMAL)
	Using_Skill = false


func Attack() -> void:
	if state_machine.current_state == State.Die or not is_multiplayer_authority():
		Attacking = false
		return
	if is_damage_output_disabled() or _has_active_brick() or _post_build_attack_lock_left > 0.0:
		Attacking = false
		return

	var target_wall:ball = _nearest_owned_wall()
	if target_wall == null:
		Attacking = false
		return

	Attacking = true
	_set_builder_visual(VISUAL_BRICK_READY)
	var pose_time:float = maxf(brick_throw_pose_time,0.10)
	await get_tree().create_timer(pose_time * 0.48).timeout
	if not is_instance_valid(self) or state_machine.current_state == State.Die:
		return
	_throw_brick_at_wall(target_wall)
	_set_builder_visual(VISUAL_BRICK_THROW)
	await get_tree().create_timer(pose_time * 0.72).timeout
	if is_instance_valid(self):
		_set_builder_visual(VISUAL_NORMAL)
		Attacking = false


func _spawn_wall() -> void:
	var world := get_tree().current_scene
	if world == null or _has_any_owned_wall():
		return

	var wall:ball = WALL_SCENE.instantiate()
	wall.Master = self
	wall.Master_name = str(get_path())
	wall.Team = Team
	wall.Target_Enemy = Target_Enemy
	wall.direction = Vector2.ZERO
	wall.name = Game.return_random_name(wall)
	wall.set("builder_owner",self)
	world.add_child(wall,true)
	wall.global_position = _choose_wall_spawn_position()
	_owned_wall = wall
	# 建墙完成后额外锁住扔砖攻击，避免“之前已经蓄满攻击 CD”导致刚造完墙就立刻出手。
	_post_build_attack_lock_left = maxf(post_build_attack_lock,0.0)
	wall.tree_exited.connect(_on_owned_wall_exited.bind(wall),CONNECT_ONE_SHOT)


func _throw_brick_at_wall(target_wall:ball) -> void:
	var world := get_tree().current_scene
	if world == null or target_wall == null or not is_instance_valid(target_wall) or _has_active_brick():
		return

	var brick:Area2D = BRICK_SCENE.instantiate()
	brick.name = Game.return_random_name(brick)
	brick.set("builder_owner",self)
	brick.set("target_wall",target_wall)
	brick.set("team",Team)
	brick.set("move_speed",brick_speed)
	brick.set("enemy_damage",attack_damage(brick_enemy_damage_multiplier))
	brick.set("wall_damage",attack_damage(brick_wall_damage_multiplier))
	brick.set("knockback_distance",brick_knockback_distance)
	brick.set("knockback_speed",brick_knockback_speed)
	world.add_child(brick,true)

	var throw_dir:Vector2 = target_wall.global_position - global_position
	if throw_dir.length_squared() <= 0.000001:
		throw_dir = Vector2.RIGHT
	throw_dir = throw_dir.normalized()
	brick.global_position = global_position + throw_dir * 18.0
	_play_builder_one_shot(AUDIO_THROW_BRICK,0.40)
	_active_brick = brick
	brick.tree_exited.connect(_on_active_brick_exited.bind(brick),CONNECT_ONE_SHOT)
	brick.call("launch",target_wall.global_position)


func _start_builder_action_audio(stream:AudioStream) -> void:
	_stop_builder_action_audio()
	if stream == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.name = "BuilderBehaviorAudio"
	player.stream = stream
	player.max_distance = 900.0
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	add_child(player)
	_builder_action_audio = player
	player.play()


func _stop_builder_action_audio() -> void:
	if _builder_action_audio == null:
		return
	if is_instance_valid(_builder_action_audio):
		_builder_action_audio.stop()
		_builder_action_audio.queue_free()
	_builder_action_audio = null


func _play_builder_one_shot(stream:AudioStream,max_lifetime:float = 2.0) -> void:
	if stream == null or not is_inside_tree():
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.max_distance = 900.0
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	add_child(player)
	player.play()
	var life:float = maxf(max_lifetime,0.05)
	get_tree().create_timer(life).timeout.connect(func():
		if is_instance_valid(player):
			player.stop()
			player.queue_free()
	)


func _has_any_owned_wall() -> bool:
	_cleanup_wall_ref()
	return _owned_wall != null


func _nearest_owned_wall() -> ball:
	_cleanup_wall_ref()
	if _owned_wall == null:
		return null
	if _owned_wall.health <= 0:
		return null
	if _owned_wall.has_method("is_collapse_started") and bool(_owned_wall.call("is_collapse_started")):
		return null
	return _owned_wall


func _has_active_brick() -> bool:
	if _active_brick == null:
		return false
	if not is_instance_valid(_active_brick) or _active_brick.is_queued_for_deletion():
		_active_brick = null
		return false
	return true


func _cleanup_wall_ref() -> void:
	if _owned_wall == null:
		return
	if not is_instance_valid(_owned_wall) or _owned_wall.is_queued_for_deletion():
		_owned_wall = null


func _on_owned_wall_exited(wall:ball) -> void:
	if _owned_wall == wall:
		_owned_wall = null


func _on_active_brick_exited(brick:Area2D) -> void:
	if _active_brick == brick:
		_active_brick = null


func _choose_wall_spawn_position() -> Vector2:
	# 墙从建筑工人周围生成，而不是固定朝敌人方向生成。
	var around_dir:Vector2 = Vector2.from_angle(randf_range(0.0,TAU))
	var radius:float = maxf(
		wall_spawn_distance + randf_range(-wall_spawn_side_jitter,wall_spawn_side_jitter),
		20.0
	)
	var candidate:Vector2 = global_position + around_dir * radius
	return _clamp_point_to_map(candidate,wall_map_margin)


func _clamp_point_to_map(point:Vector2,margin:float) -> Vector2:
	var world = get_tree().current_scene
	if world == null or not world.has_method("return_map_world_rect"):
		return point
	if not world.map_group.has(str(world.now_choose_map)):
		return point
	var map_node = world.map_group[str(world.now_choose_map)]
	if not map_node is TileMapLayer:
		return point
	var rect:Rect2 = world.return_map_world_rect(map_node)
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return point
	var safe_margin:float = maxf(margin,4.0)
	return Vector2(
		clampf(point.x,rect.position.x + safe_margin,rect.end.x - safe_margin),
		clampf(point.y,rect.position.y + safe_margin,rect.end.y - safe_margin)
	)


func Die() -> void:
	_building_wall = false
	Using_Skill = false
	_stop_builder_action_audio()
	super()
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(self):
		Game.free_node(self)
