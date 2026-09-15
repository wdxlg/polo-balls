extends StaticBody2D

const STONE_LAND_SFX:AudioStream = preload("res://audio/characters/矿工/石子.mp3")

@export_category("矿工石头 - 外观（可留空）")
@export var stone_texture_1:Texture2D
@export var stone_texture_2:Texture2D
@export var stone_texture_3:Texture2D
@export_range(10.0,40.0,1.0) var visual_size:float = 20.0

@export_category("矿工石头 - 生命周期")
@export var Master_name:String = ""
@export_range(0.0,300.0,1.0) var lifetime:float = 24.0
@export_range(0.0,2.0,0.01) var spawn_collision_delay:float = 0.34

@onready var collision_shape:CollisionShape2D = $CollisionShape2D
@onready var sprite:Sprite2D = $Sprite2D

var _flight_start:Vector2 = Vector2.ZERO
var _flight_target:Vector2 = Vector2.ZERO
var _flight_arc_height:float = 0.0
var _flight_spin:float = 0.0
var _landed:bool = false
var _fallback_visual:Polygon2D = null


func _ready() -> void:
	add_to_group("MinerStone")
	add_to_group("AI_Hazard")
	add_to_group("BattleTransient")
	_auto_load_textures()
	_apply_stone_visual()
	if collision_shape != null:
		collision_shape.set_deferred("disabled",true)
	_enable_collision_after(maxf(spawn_collision_delay,0.0))
	if lifetime > 0.0 and is_multiplayer_authority():
		_expire_later()


func _auto_load_textures() -> void:
	if stone_texture_1 == null:
		stone_texture_1 = _try_load_texture("res://Images/terrain/矿工石头/石头1.png")
	if stone_texture_2 == null:
		stone_texture_2 = _try_load_texture("res://Images/terrain/矿工石头/石头2.png")
	if stone_texture_3 == null:
		stone_texture_3 = _try_load_texture("res://Images/terrain/矿工石头/石头3.png")


func _try_load_texture(path:String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var resource:Resource = ResourceLoader.load(path)
	return resource as Texture2D if resource is Texture2D else null


func _apply_stone_visual() -> void:
	if sprite == null:
		return

	var variants:Array[Texture2D] = []
	if stone_texture_1 != null:
		variants.append(stone_texture_1)
	if stone_texture_2 != null:
		variants.append(stone_texture_2)
	if stone_texture_3 != null:
		variants.append(stone_texture_3)

	if not variants.is_empty():
		var variant_index:int = int(abs(hash(name))) % variants.size()
		var tex:Texture2D = variants[variant_index]
		sprite.texture = tex
		sprite.visible = true
		var tex_size:Vector2 = tex.get_size()
		var max_dimension:float = maxf(tex_size.x,tex_size.y)
		if max_dimension > 0.0:
			sprite.scale = Vector2.ONE * (visual_size / max_dimension)
		return

	# 没填图片时仍给一个很小的程序石头，方便先测试逻辑。
	sprite.visible = false
	_create_fallback_stone()


func _create_fallback_stone() -> void:
	if _fallback_visual != null and is_instance_valid(_fallback_visual):
		return
	var rock := Polygon2D.new()
	rock.name = "FallbackStoneVisual"
	rock.polygon = PackedVector2Array([
		Vector2(-9.0,-2.0),
		Vector2(-5.0,-7.0),
		Vector2(3.0,-8.0),
		Vector2(9.0,-3.0),
		Vector2(8.0,5.0),
		Vector2(1.0,8.0),
		Vector2(-7.0,5.0),
	])
	rock.color = Color(0.48,0.43,0.36,1.0)
	rock.scale = Vector2.ONE * (visual_size / 20.0)
	add_child(rock)
	_fallback_visual = rock


func launch(start_position:Vector2,target_position:Vector2,duration:float,arc_height:float) -> void:
	_flight_start = start_position
	_flight_target = target_position
	_flight_arc_height = maxf(arc_height,0.0)
	_flight_spin = randf_range(-TAU * 1.35,TAU * 1.35)
	global_position = start_position
	_landed = false
	if collision_shape != null:
		collision_shape.set_deferred("disabled",true)

	if not is_inside_tree():
		call_deferred("launch",start_position,target_position,duration,arc_height)
		return

	var flight_time:float = maxf(duration,0.05)
	var tween:Tween = create_tween()
	var motion = tween.tween_method(_set_flight_progress,0.0,1.0,flight_time)
	motion.set_trans(Tween.TRANS_QUAD)
	motion.set_ease(Tween.EASE_OUT)
	tween.finished.connect(_finish_landing)


func _set_flight_progress(progress:float) -> void:
	var t:float = clampf(progress,0.0,1.0)
	var pos:Vector2 = _flight_start.lerp(_flight_target,t)
	pos.y -= sin(t * PI) * _flight_arc_height
	global_position = pos
	rotation = _flight_spin * t


func _finish_landing() -> void:
	global_position = _flight_target
	_landed = true
	if collision_shape != null:
		collision_shape.set_deferred("disabled",false)
	_play_landing_sfx()


func _play_landing_sfx() -> void:
	# 小石头很多，音量压低并随机一点音高。只由 authority 发起，再同步到所有端。
	if not is_multiplayer_authority():
		return
	var pitch:float = randf_range(0.82,1.08)
	if multiplayer.has_multiplayer_peer():
		_rpc_play_landing_sfx.rpc(global_position,pitch)
	else:
		_rpc_play_landing_sfx(global_position,pitch)


@rpc("authority","call_local","unreliable")
func _rpc_play_landing_sfx(position_value:Vector2,pitch:float) -> void:
	var world:Node = get_tree().current_scene
	if world == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.name = "MinerStoneLandSFX"
	player.stream = STONE_LAND_SFX
	# 同一锤会落下多颗石头：单颗适当压低音量，再用轻微随机音高避免叠在一起太生硬。
	player.volume_db = -6.0
	player.pitch_scale = pitch
	player.max_distance = 620.0
	player.attenuation = 1.0
	world.add_child(player)
	player.global_position = position_value
	player.finished.connect(player.queue_free)
	player.play()


func _enable_collision_after(delay:float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not is_instance_valid(self) or _landed:
		return
	_landed = true
	if collision_shape != null:
		collision_shape.set_deferred("disabled",false)


func get_ai_hazard_info(receiver:ball) -> Dictionary:
	if not _landed or receiver == null or not is_instance_valid(receiver):
		return {}
	return {
		"shape":"circle",
		"position":global_position,
		"velocity":Vector2.ZERO,
		"radius":_ai_blocking_radius(),
		"kind":"miner_stone",
		"blocking":true,
		"source":self,
	}


func _ai_blocking_radius() -> float:
	if collision_shape != null and collision_shape.shape != null:
		var sx:float = absf(collision_shape.global_scale.x)
		var sy:float = absf(collision_shape.global_scale.y)
		var shape:Shape2D = collision_shape.shape
		if shape is CircleShape2D:
			return maxf((shape as CircleShape2D).radius * maxf(sx,sy),4.0)
		if shape is RectangleShape2D:
			var size:Vector2 = (shape as RectangleShape2D).size
			return maxf(Vector2(size.x * sx,size.y * sy).length() * 0.5,4.0)
	return maxf(visual_size * maxf(absf(global_scale.x),absf(global_scale.y)) * 0.55,5.0)


func _expire_later() -> void:
	await get_tree().create_timer(lifetime).timeout
	if is_instance_valid(self):
		Game.free_node(self)
