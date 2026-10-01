extends Node2D
## 时钟残影：原版表盘贴图淡出；带伤残影在权威端附带实体碰撞（时钟自身例外）。
const ARMED_TINT := Color(1.0,0.86,0.45,0.62)
const PLAIN_TINT := Color(0.66,0.82,1.0,0.46)
var life:float = 0.4
var age:float = 0.0
var armed:bool = false
var _sprite:Sprite2D
var _body:StaticBody2D
var _clock_ref:WeakRef


func setup(clock:Node2D,texture:Texture2D,sprite_scale:Vector2,point:Vector2,duration:float,is_armed:bool,solid_radius:float) -> void:
	name = "ClockAfterimage"
	add_to_group(&"BattleTransient")
	global_position = point
	life = maxf(duration,0.05)
	armed = is_armed
	z_index = clock.z_index
	z_as_relative = false
	_clock_ref = weakref(clock)
	_sprite = Sprite2D.new()
	_sprite.texture = texture
	_sprite.scale = sprite_scale
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_apply_fade()
	if solid_radius > 0.0 and clock is CollisionObject2D:
		_body = StaticBody2D.new()
		_body.collision_layer = (clock as CollisionObject2D).collision_layer
		_body.collision_mask = 0
		_body.set_meta("clock_afterimage",true)
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = solid_radius
		shape.shape = circle
		_body.add_child(shape)
		add_child(_body)
		if clock is PhysicsBody2D: (clock as PhysicsBody2D).add_collision_exception_with(_body)


func _physics_process(delta:float) -> void:
	if Game.now_stop_state: return
	age += delta
	_apply_fade()
	if age >= life: _expire()


func _apply_fade() -> void:
	if _sprite == null: return
	var tint:Color = ARMED_TINT if armed else PLAIN_TINT
	var f:float = clampf(1.0 - age / life,0.0,1.0)
	tint.a *= f * f
	_sprite.modulate = tint


func _expire() -> void:
	var clock:Variant = _clock_ref.get_ref() if _clock_ref != null else null
	if _body != null and is_instance_valid(clock) and clock is PhysicsBody2D:
		(clock as PhysicsBody2D).remove_collision_exception_with(_body)
	queue_free()

