extends Node2D

signal landed(food:Node2D)

const FOOD_BONE:int = 0
const FOOD_BIG_MEAT:int = 1
const FOOD_SAUSAGE:int = 2
const FOOD_CHEW_STICK:int = 3

const TEX_BONE:Texture2D = preload("res://Images/characters/布鲁斯/骨头.png")
const TEX_BIG_MEAT:Texture2D = preload("res://Images/characters/布鲁斯/大肉.png")
const TEX_SAUSAGE:Texture2D = preload("res://Images/characters/布鲁斯/香肠.png")
const TEX_CHEW_STICK:Texture2D = preload("res://Images/characters/布鲁斯/磨牙棒.png")

var food_type:int = FOOD_BONE
var is_landed:bool = false
var claimed:bool = false
var _visual_root:Node2D = null


func setup(kind:int) -> void:
	food_type = clampi(kind,FOOD_BONE,FOOD_CHEW_STICK)
	_build_visual()


func launch_to(target_position:Vector2,duration:float = 0.36,arc_height:float = 26.0) -> void:
	var start:Vector2 = global_position
	var safe_duration:float = maxf(duration,0.05)
	var tween:Tween = create_tween()
	tween.tween_method(
		func(t:float) -> void:
			var p:Vector2 = start.lerp(target_position,t)
			p.y -= sin(t * PI) * maxf(arc_height,0.0)
			global_position = p,
		0.0,
		1.0,
		safe_duration
	).set_trans(Tween.TRANS_LINEAR)
	await tween.finished
	if not is_instance_valid(self):
		return
	global_position = target_position
	is_landed = true
	landed.emit(self)


func mark_claimed() -> bool:
	if claimed:
		return false
	claimed = true
	return true


func _build_visual() -> void:
	if _visual_root != null and is_instance_valid(_visual_root):
		_visual_root.queue_free()
	_visual_root = Node2D.new()
	_visual_root.name = "FoodVisual"
	add_child(_visual_root)
	z_index = 6

	var texture:Texture2D = TEX_BONE
	var target_size:float = 17.0
	match food_type:
		FOOD_BIG_MEAT:
			texture = TEX_BIG_MEAT
			target_size = 22.0
		FOOD_SAUSAGE:
			texture = TEX_SAUSAGE
			target_size = 18.0
		FOOD_CHEW_STICK:
			texture = TEX_CHEW_STICK
			target_size = 17.0
		_:
			texture = TEX_BONE
			target_size = 18.0

	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = true
	var texture_size:Vector2 = texture.get_size()
	var longest:float = maxf(texture_size.x,texture_size.y)
	var fit:float = target_size / maxf(longest,1.0)
	sprite.scale = Vector2(fit,fit)
	sprite.rotation = randf_range(-0.22,0.22)
	_visual_root.add_child(sprite)
