extends StaticBody2D

# 野生狗奶把敌人衰老到 100% 后使用的专属“老死”残骸。
# 第一阶段保留整体骨堆并作为实体碰撞障碍；短暂停留后颤抖。
# 第二阶段关闭实体碰撞并散架：1 个头骨 + 多根骨头从残骸范围内抛出，旋转后落出地图。

const HEAD_TEXTURE:Texture2D = preload("res://Images/characters/meme/野生狗奶/头.png")
const BONE_TEXTURE:Texture2D = preload("res://Images/characters/meme/野生狗奶/骨头.png")
const DISASSEMBLE_AUDIO_PATH:String = "res://audio/characters/meme/野生狗奶/骨头散架.wav"

# V281 基础骨架 = V280 尺寸 × 0.85；实际实例再按死者本体碰撞箱世界横向宽度同比缩放。
const BASE_INTACT_SCALE:float = 0.0323
const BASE_COLLISION_SIZE:Vector2 = Vector2(38.08,29.92)
const BASE_COLLISION_POSITION:Vector2 = Vector2(0.0,1.70)
const BASE_HEAD_SCALE_MIN:float = 0.01156
const BASE_HEAD_SCALE_MAX:float = 0.01428
const BASE_BONE_SCALE_MIN:float = 0.00952
const BASE_BONE_SCALE_MAX:float = 0.01292
const MIN_SIZE_MULTIPLIER:float = 0.90

@export_category("老死残骸 - 整体")
@export_range(0.1,5.0,0.05) var intact_duration:float = 1.35
@export_range(0.1,3.0,0.05) var shake_duration:float = 0.90
@export_range(0.01,0.20,0.005) var shake_interval:float = 0.035
@export_range(0.0,20.0,0.5) var shake_amplitude:float = 5.0

@export_category("老死残骸 - 散架")
@export_range(2,12,1) var bone_piece_count:int = 7
@export_range(10.0,140.0,1.0) var scatter_radius:float = 58.0
@export_range(80.0,500.0,5.0) var horizontal_speed:float = 185.0
@export_range(120.0,800.0,5.0) var upward_speed_min:float = 285.0
@export_range(120.0,900.0,5.0) var upward_speed_max:float = 455.0
@export_range(100.0,1600.0,10.0) var gravity:float = 650.0
@export_range(0.5,10.0,0.1) var max_piece_lifetime:float = 7.5
@export_range(20.0,400.0,5.0) var map_exit_margin:float = 140.0

@onready var whole_sprite:Sprite2D = $整体
@onready var collision_shape:CollisionShape2D = $CollisionShape2D

var _seed_value:int = 0
var _size_multiplier:float = 1.0
var _rng := RandomNumberGenerator.new()
var _elapsed:float = 0.0
var _shake_elapsed:float = 0.0
var _disassembled:bool = false
var _disassemble_audio:AudioStream = null
var _pieces:Array[Dictionary] = []


func configure(seed_value:int,size_multiplier:float = 1.0) -> void:
	_seed_value = seed_value
	_size_multiplier = maxf(size_multiplier,MIN_SIZE_MULTIPLIER)


func _ready() -> void:
	if _seed_value == 0:
		_seed_value = Game.battle_rng_seed_or("scripts/effects/野生狗奶老死残骸.gd:_seed_value",int(Time.get_ticks_usec()) ^ int(get_instance_id()))
	_rng.seed = _seed_value
	_load_optional_disassemble_audio()
	_apply_character_size_multiplier()
	if whole_sprite != null:
		whole_sprite.position = Vector2.ZERO
	set_process(true)


func _apply_character_size_multiplier() -> void:
	# 完整骨架、实体碰撞框、后续头骨/散骨共用同一 size_multiplier。
	# 这里直接改 Shape.size；不缩放 CollisionShape2D 节点，避免物理缩放异常。
	_size_multiplier = maxf(_size_multiplier,MIN_SIZE_MULTIPLIER)
	if whole_sprite != null and is_instance_valid(whole_sprite):
		whole_sprite.scale = Vector2.ONE * BASE_INTACT_SCALE * _size_multiplier
	if collision_shape != null and is_instance_valid(collision_shape):
		collision_shape.scale = Vector2.ONE
		collision_shape.position = BASE_COLLISION_POSITION * _size_multiplier
		if collision_shape.shape != null:
			var local_shape:Shape2D = collision_shape.shape.duplicate() as Shape2D
			collision_shape.shape = local_shape
			if local_shape is RectangleShape2D:
				(local_shape as RectangleShape2D).size = BASE_COLLISION_SIZE * _size_multiplier


func _process(delta:float) -> void:
	var safe_delta:float = maxf(delta,0.0)
	if not _disassembled:
		_elapsed += safe_delta
		if _elapsed >= intact_duration:
			_update_shake(safe_delta)
		if _elapsed >= intact_duration + shake_duration:
			_disassemble()
		return
	_update_pieces(safe_delta)


func _update_shake(delta:float) -> void:
	if whole_sprite == null or not is_instance_valid(whole_sprite):
		return
	_shake_elapsed += delta
	if _shake_elapsed < maxf(shake_interval,0.01):
		return
	_shake_elapsed = 0.0
	var amplitude:float = maxf(shake_amplitude,0.0)
	whole_sprite.position = Vector2(
		_rng.randf_range(-amplitude,amplitude),
		_rng.randf_range(-amplitude * 0.60,amplitude * 0.60)
	)
	whole_sprite.rotation = _rng.randf_range(-0.035,0.035)


func _disassemble() -> void:
	if _disassembled:
		return
	_disassembled = true
	if whole_sprite != null and is_instance_valid(whole_sprite):
		whole_sprite.position = Vector2.ZERO
		whole_sprite.rotation = 0.0
		whole_sprite.visible = false
	if collision_shape != null and is_instance_valid(collision_shape):
		collision_shape.set_deferred("disabled",true)
	collision_layer = 0
	collision_mask = 0
	_play_disassemble_audio()

	_spawn_piece(HEAD_TEXTURE,true)
	for _index:int in range(maxi(bone_piece_count,2)):
		_spawn_piece(BONE_TEXTURE,false)


func _load_optional_disassemble_audio() -> void:
	# V282：散架音属于可选运行时资源，不再使用编译期 preload。
	# 这样即使用户只覆盖了脚本、音频还没复制进项目，也不会让整个脚本解析失败。
	_disassemble_audio = null
	if not ResourceLoader.exists(DISASSEMBLE_AUDIO_PATH):
		return
	var loaded:Resource = ResourceLoader.load(DISASSEMBLE_AUDIO_PATH)
	if loaded is AudioStream:
		_disassemble_audio = loaded as AudioStream


func _play_disassemble_audio() -> void:
	if _disassemble_audio == null:
		_load_optional_disassemble_audio()
	if _disassemble_audio == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.name = "BoneDisassembleAudio"
	player.stream = _disassemble_audio
	player.volume_db = 0.0
	player.max_distance = 1000.0
	player.attenuation = 1.0
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		player.bus = &"GameplayRecord"
	add_child(player)
	player.finished.connect(player.queue_free,CONNECT_ONE_SHOT)
	player.play()


func _spawn_piece(texture:Texture2D,is_head:bool) -> void:
	if texture == null:
		return
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.z_index = 4
	# V281：散架部件先以 V280 ×0.85 作为基础尺寸，再与完整骨架使用同一人物宽度倍率。
	var scale_value:float = (
		_rng.randf_range(BASE_HEAD_SCALE_MIN,BASE_HEAD_SCALE_MAX)
		if is_head
		else _rng.randf_range(BASE_BONE_SCALE_MIN,BASE_BONE_SCALE_MAX)
	)
	sprite.scale = Vector2.ONE * scale_value * _size_multiplier
	var angle:float = _rng.randf_range(0.0,TAU)
	var radius:float = sqrt(_rng.randf()) * maxf(scatter_radius,1.0)
	sprite.position = Vector2.from_angle(angle) * radius
	sprite.rotation = _rng.randf_range(-PI,PI)
	add_child(sprite)

	var vx:float = _rng.randf_range(-maxf(horizontal_speed,0.0),maxf(horizontal_speed,0.0))
	if absf(vx) < horizontal_speed * 0.22:
		vx = signf(vx if absf(vx) > 0.001 else _rng.randf_range(-1.0,1.0)) * horizontal_speed * 0.22
	var vy:float = -_rng.randf_range(
		minf(upward_speed_min,upward_speed_max),
		maxf(upward_speed_min,upward_speed_max)
	)
	var spin:float = _rng.randf_range(-5.4,5.4)
	if absf(spin) < 1.0:
		spin = signf(spin if absf(spin) > 0.001 else _rng.randf_range(-1.0,1.0))
	_pieces.append({
		"node":sprite,
		"velocity":Vector2(vx,vy),
		"spin":spin,
		"age":0.0
	})


func _update_pieces(delta:float) -> void:
	var map_rect:Rect2 = _resolve_map_world_rect()
	var has_map_rect:bool = map_rect.size.x > 0.0 and map_rect.size.y > 0.0
	for index:int in range(_pieces.size() - 1,-1,-1):
		var piece:Dictionary = _pieces[index]
		var node_variant:Variant = piece.get("node",null)
		if not is_instance_valid(node_variant) or not (node_variant is Sprite2D):
			_pieces.remove_at(index)
			continue
		var sprite:Sprite2D = node_variant as Sprite2D
		var velocity:Vector2 = piece.get("velocity",Vector2.ZERO)
		velocity.y += maxf(gravity,0.0) * delta
		sprite.position += velocity * delta
		sprite.rotation += float(piece.get("spin",0.0)) * delta
		var age:float = float(piece.get("age",0.0)) + delta
		piece["velocity"] = velocity
		piece["age"] = age
		_pieces[index] = piece

		var should_remove:bool = age >= maxf(max_piece_lifetime,0.5)
		if has_map_rect:
			var world_pos:Vector2 = sprite.global_position
			# 只在已经开始向下掉之后判定“掉出地图”，确保每块都先完成向上阶段。
			if velocity.y > 0.0 and world_pos.y > map_rect.end.y + maxf(map_exit_margin,20.0):
				should_remove = true
		if should_remove:
			sprite.queue_free()
			_pieces.remove_at(index)

	if _pieces.is_empty():
		queue_free()


func _resolve_map_world_rect() -> Rect2:
	if get_tree() == null:
		return Rect2()
	var world:Node = get_tree().current_scene
	if world == null or not world.has_method("return_map_world_rect"):
		return Rect2()
	var map_group_value:Variant = world.get("map_group")
	var chosen_value:Variant = world.get("now_choose_map")
	if not (map_group_value is Dictionary):
		return Rect2()
	var map_group:Dictionary = map_group_value as Dictionary
	if not map_group.has(chosen_value):
		return Rect2()
	var map_node:Variant = map_group[chosen_value]
	if not (map_node is TileMapLayer):
		return Rect2()
	var result:Variant = world.call("return_map_world_rect",map_node as TileMapLayer)
	if result is Rect2:
		return result
	return Rect2()
