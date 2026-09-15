extends Node2D

const DICE_TEXTURES = [
	preload("res://Images/characters/投稿/掷骰子的人/骰子_01_上面点数1.png"),
	preload("res://Images/characters/投稿/掷骰子的人/骰子_02_上面点数2.png"),
	preload("res://Images/characters/投稿/掷骰子的人/骰子_03_上面点数3.png"),
	preload("res://Images/characters/投稿/掷骰子的人/骰子_04_上面点数4.png"),
	preload("res://Images/characters/投稿/掷骰子的人/骰子_05_上面点数5.png"),
	preload("res://Images/characters/投稿/掷骰子的人/骰子_06_上面点数6.png"),
	preload("res://Images/characters/投稿/掷骰子的人/骰子_07_上面点数7_原始版.png"),
]

@export_range(24.0,96.0,1.0) var die_display_size:float = 48.0
@export_range(0.04,0.30,0.01) var throw_pose_time:float = 0.16
@export_range(0.02,0.20,0.005) var roll_step:float = 0.065

var face:int = 1
var _rolling:bool = false
var _roll_left:float = 0.0
var _roll_elapsed:float = 0.0
var _step_elapsed:float = 0.0
var _final_face:int = 1
var _wait_pose_started:bool = false
var _rng := RandomNumberGenerator.new()
var _sprite:Sprite2D = null

func _ready() -> void:
	_rng.seed = Game.battle_rng_seed_or("scripts/effects/投稿/掷骰子视觉.gd:_rng",int(Time.get_ticks_usec()) ^ int(get_instance_id()))
	z_as_relative = false
	z_index = 130
	_sprite = get_node_or_null("DiceSprite") as Sprite2D
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "DiceSprite"
		add_child(_sprite)
	_sprite.centered = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_set_face_texture(1)
	visible = false

func play_roll(final_face:int,duration:float = 0.62) -> void:
	_final_face = clampi(final_face,1,7)
	_rolling = true
	_roll_left = maxf(duration,0.08)
	_roll_elapsed = 0.0
	_step_elapsed = 0.0
	_wait_pose_started = false
	face = _rng.randi_range(1,6)
	_set_face_texture(face)
	rotation = 0.0

	# 投出的那一下直接使用人物素材里自带的骰子，所以独立骰子先隐藏。
	visible = false
	_notify_character_pose("throw")

func settle(final_face:int) -> void:
	_final_face = clampi(final_face,1,7)
	_rolling = false
	_roll_left = 0.0
	face = _final_face
	rotation = 0.0
	_set_face_texture(face)
	visible = true
	# 骰子不再随机时，人物回到普通状态；最终点数仍短暂留在右下角。
	_notify_character_pose("normal")

func hide_after(delay:float) -> void:
	var wait_time:float = maxf(delay,0.0)
	if wait_time > 0.0:
		await get_tree().create_timer(wait_time,false).timeout
	if is_instance_valid(self) and not _rolling:
		visible = false

func is_rolling_visual() -> bool:
	return _rolling

func _process(delta:float) -> void:
	if not _rolling:
		return

	_roll_left -= delta
	_roll_elapsed += delta
	_step_elapsed += delta

	if not _wait_pose_started and _roll_elapsed >= minf(throw_pose_time,maxf(_roll_left + _roll_elapsed,0.08) * 0.45):
		_wait_pose_started = true
		visible = true
		_notify_character_pose("wait")

	if _roll_left <= 0.0:
		settle(_final_face)
		return

	if _step_elapsed >= maxf(roll_step,0.02):
		_step_elapsed = 0.0
		face = _rng.randi_range(1,6)
		_set_face_texture(face)
		rotation += _rng.randf_range(-0.22,0.22)

func _set_face_texture(value:int) -> void:
	if _sprite == null:
		return
	var index:int = clampi(value,1,7) - 1
	var texture:Texture2D = DICE_TEXTURES[index]
	_sprite.texture = texture
	if texture == null:
		return
	var size:Vector2 = texture.get_size()
	var longest:float = maxf(size.x,size.y)
	if longest > 0.0:
		var scale_value:float = die_display_size / longest
		_sprite.scale = Vector2(scale_value,scale_value)

func _notify_character_pose(pose:String) -> void:
	var owner_node:Node = get_parent()
	if owner_node != null and owner_node.has_method("_on_dice_visual_pose"):
		owner_node.call("_on_dice_visual_pose",pose)
