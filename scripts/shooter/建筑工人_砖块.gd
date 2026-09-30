extends Area2D

const BRICK_SHEET:Texture2D = preload("res://Images/characters/建筑工人/砖墙.png")
const AUDIO_BRICK_LAND:AudioStream = preload("res://audio/characters/建筑工人/砖头摔倒.wav")

@export var move_speed:float = 430.0
@export var enemy_damage:float = 32.0
@export var wall_damage:float = 24.0
@export var knockback_distance:float = 24.0
@export var knockback_speed:float = 360.0
@export var lifetime:float = 2.6

var builder_owner:ball = null
var target_wall:ball = null
var team:String = ""
var _velocity:Vector2 = Vector2.ZERO
var _target_point:Vector2 = Vector2.ZERO
var _life_left:float = 0.0
var _hit_ids:Dictionary = {}
var _launched:bool = false
var _terminal_sound_played:bool = false


func _ready() -> void:
	add_to_group("AllayExtendedProjectile")
	add_to_group("BattleTransient")
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	_life_left = maxf(lifetime,0.1)
	_build_brick_visual()


func _build_brick_visual() -> void:
	var old_poly:CanvasItem = get_node_or_null("Brick") as CanvasItem
	if old_poly != null:
		old_poly.visible = false
	var old_line:CanvasItem = get_node_or_null("MortarLine") as CanvasItem
	if old_line != null:
		old_line.visible = false
	var sprite := Sprite2D.new()
	sprite.name = "BrickTexture"
	sprite.texture = BRICK_SHEET
	sprite.region_enabled = true
	# 直接取投稿砖墙图左上区域的一块完整红砖，不额外生成新素材。
	sprite.region_rect = Rect2(42.0,82.0,190.0,72.0)
	sprite.scale = Vector2(18.0 / 190.0,9.0 / 72.0)
	add_child(sprite)


func launch(target_position:Vector2) -> void:
	_target_point = target_position
	var travel:Vector2 = target_position - global_position
	if travel.length_squared() <= 0.000001:
		travel = Vector2.RIGHT
	_velocity = travel.normalized() * maxf(move_speed,1.0)
	rotation = _velocity.angle()
	_launched = true


func _physics_process(delta:float) -> void:
	if not _launched:
		return
	_life_left -= delta
	if _life_left <= 0.0:
		_play_terminal_sound()
		queue_free()
		return

	var rewrote_tracking_velocity:bool = false
	if target_wall != null and is_instance_valid(target_wall) and target_wall.health > 0:
		_target_point = target_wall.global_position
		var desired:Vector2 = _target_point - global_position
		if desired.length_squared() > 0.000001:
			_velocity = desired.normalized() * maxf(move_speed,1.0)
			rewrote_tracking_velocity = true

	# V286：World 会给大多数非 ball 弹丸直接改速度，但砖块在追墙时会把 _velocity
	# 每帧重算回“正对墙”的旧值。这里仅在发生这种重算后重新叠入投射物 3.5x 重力，
	# 确保砖块也能被明显掰弯；不追墙时继续使用 World 已经写入的 _velocity，避免双重施力。
	if rewrote_tracking_velocity:
		var world:Node = get_tree().current_scene
		if world != null and world.has_method("get_directional_gravity_for"):
			var gravity_value:Variant = world.call("get_directional_gravity_for",self)
			if typeof(gravity_value) == TYPE_VECTOR2:
				var gravity_accel:Vector2 = gravity_value
				_velocity += gravity_accel * 3.5 * maxf(delta,0.0)

	if _velocity.length_squared() > 0.000001:
		rotation = _velocity.angle()

	var step:Vector2 = _velocity * delta
	if get_tree().has_group("MinecraftAllay") and load("res://scripts/characters/我的世界/allay/capture.gd").sweep(self,global_position,global_position+step): return
	global_position += step

	# 目标墙因为物理帧顺序没有发出 body_entered 时，用距离兜底。
	if target_wall != null and is_instance_valid(target_wall) and target_wall.health > 0:
		if global_position.distance_squared_to(target_wall.global_position) <= 15.0 * 15.0:
			_hit_wall(target_wall)
	elif global_position.distance_squared_to(_target_point) <= 12.0 * 12.0:
		_play_terminal_sound()
		queue_free()


func _on_body_entered(body:Node) -> void:
	if body == null or not is_instance_valid(body):
		return
	if not body is ball:
		return
	var target:ball = body as ball
	if target == builder_owner or target == self:
		return
	if target.health <= 0:
		return

	if target.has_method("is_builder_wall") and bool(target.call("is_builder_wall")):
		_hit_wall(target)
		return

	if _is_friendly(target):
		return

	var target_id:int = target.get_instance_id()
	if _hit_ids.has(target_id):
		return
	if target.has_method("try_full_projectile_dodge") and bool(target.call("try_full_projectile_dodge",self)): return
	_hit_ids[target_id] = true

	if target.has_method("try_block_projectile_hit") and bool(target.call("try_block_projectile_hit",self,global_position,enemy_damage)):
		_play_terminal_sound()
		queue_free()
		return

	var accepted:bool = target.receive_positional_damage(enemy_damage,global_position,false,builder_owner)
	if accepted and knockback_distance > 0.0:
		var push_dir:Vector2 = _velocity.normalized()
		if push_dir.length_squared() <= 0.000001:
			push_dir = (target.global_position - global_position).normalized()
		target.apply_knockback(
			push_dir,
			knockback_distance,
			knockback_speed,
			0.0,
			0.0,
			{"source":builder_owner,"stop_on_character":true}
		)
	# 抛砖的核心是最终砸墙，所以穿过敌人后继续飞，不因命中人物消失。


func _hit_wall(wall:ball) -> void:
	if wall == null or not is_instance_valid(wall) or wall.health <= 0:
		queue_free()
		return
	wall.receive_positional_damage(wall_damage,global_position,true,builder_owner)
	_play_terminal_sound()
	queue_free()


func _play_terminal_sound() -> void:
	if _terminal_sound_played or AUDIO_BRICK_LAND == null or not is_inside_tree():
		return
	_terminal_sound_played = true
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = AUDIO_BRICK_LAND
	player.max_distance = 900.0
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	world.add_child(player)
	player.global_position = global_position
	player.play()
	get_tree().create_timer(0.90).timeout.connect(func():
		if is_instance_valid(player):
			player.stop()
			player.queue_free()
	)


func _is_friendly(target:ball) -> bool:
	if target == null:
		return true
	if team.is_empty() or target.Team.is_empty():
		return false
	if team != target.Team:
		return false
	# 自己的墙虽然同队，但砖块就是故意拿它当目标。
	if target.has_method("is_builder_wall"):
		return false
	return true
