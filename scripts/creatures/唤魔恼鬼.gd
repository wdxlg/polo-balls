extends "res://scripts/creatures/mc_short_lived_mob.gd"
const NORMAL = preload("res://Images/characters/我的世界/唤魔者/恼鬼.png")
const CHARGING = preload("res://Images/characters/我的世界/唤魔者/恼鬼冲刺.png")
@export var attack_range:float = 75.0
@export var attack_interval:float = 1.8
@export var dash_speed:float = 230.0
@export var roam_radius:float = 85.0
var _attack_wait:float = 0.6
var _roam_wait:float = 0.0
var _roam_point:Vector2
var _dash_target:WeakRef
var _dash_direction:Vector2
var _dash_distance:float = 0.0
var _dash_hit:bool = false
var _windup:float = 0.0
var _charging:bool = false
var _last_motion:Vector2 = Vector2.ZERO
func _ready() -> void:
	enderman_clone = false
	super._ready()
	collision_layer = 0
	collision_mask = 0
	self_hitbox.set_deferred("monitoring",false)
	_finish_dash()
func has_collision_damage() -> bool: return false
func tick_physics(state:State,delta:float) -> void:
	if health <= 0 or _retired:
		retire()
		return
	if mc_live():
		_attack_wait -= delta
		if _windup > 0.0:
			_windup -= delta
			direction = Vector2.ZERO
			if _windup <= 0.0: _launch_dash()
		elif _charging:
			direction = _dash_direction
		else:
			_roam_wait -= delta
			if _roam_wait <= 0.0 or global_position.distance_to(_roam_point) < 9.0:
				_roam_wait = _mc_rng.randf_range(0.45,1.2)
				var anchor:Vector2 = Master.global_position if is_instance_valid(Master) else global_position
				_roam_point = anchor + Vector2.RIGHT.rotated(_mc_rng.randf_range(0,TAU))*_mc_rng.randf_range(20.0,roam_radius)
				var rect:Rect2 = mc_arena_rect().grow(-12.0)
				_roam_point = _roam_point.clamp(rect.position,rect.end)
			var aim:Vector2 = global_position.direction_to(_roam_point)
			direction = Vector2.RIGHT.rotated(rotate_toward(direction.angle(),aim.angle(),delta*3.2))
			var target:ball = mc_nearest(delta)
			if _attack_wait <= 0.0 and target != null and global_position.distance_to(target.global_position) <= attack_range:
				begin_dash(target)
	super.tick_physics(state,delta)
func begin_dash(target:ball) -> void:
	if not mc_enemy(target): return
	_dash_target = weakref(target)
	_windup = 0.16
	_attack_wait = attack_interval
	# 动画驱动读取 _windup / _charging，切换原版举剑与充能皮肤。
func _launch_dash() -> void:
	var target:Variant = _dash_target.get_ref() if _dash_target != null else null
	if not is_instance_valid(target) or not mc_enemy(target):
		_finish_dash()
		return
	_dash_direction = global_position.direction_to(target.global_position)
	_dash_distance = global_position.distance_to(target.global_position) + target.get_crowd_separation_radius_world() + 28.0
	_dash_hit = false
	_charging = true
	mc_play("charge",-5.0)
func move(speed:float,delta:float) -> void:
	var from:Vector2 = global_position
	var ratio:float = maxf(speed,0.0)/maxf(float(default_properties.get("Speed",speed)),1.0)
	super.move(dash_speed*ratio if _charging else speed,delta)
	# 能穿内部墙，但不离开战场的可见外边界。
	var arena:Rect2 = mc_arena_rect().grow(-10.0)
	var bounded:Vector2 = global_position.clamp(arena.position,arena.end)
	if not bounded.is_equal_approx(global_position):
		if not is_equal_approx(bounded.x,global_position.x): direction.x *= -1.0
		if not is_equal_approx(bounded.y,global_position.y): direction.y *= -1.0
		global_position = bounded
		_roam_wait = 0.0
		if _charging: _finish_dash()
	_last_motion = global_position-from
	if _charging:
		_check_dash_hit(from,global_position)
		_dash_distance -= _last_motion.length()
		if _dash_distance <= 0.0: _finish_dash()
func _check_dash_hit(from:Vector2,to:Vector2) -> void:
	if _dash_hit: return
	var target:Variant = _dash_target.get_ref() if _dash_target != null else null
	if not is_instance_valid(target) or not mc_enemy(target): return
	var shape := CapsuleShape2D.new()
	shape.radius = 3.5
	shape.height = from.distance_to(to)+7.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D((to-from).angle()+PI*0.5,from.lerp(to,0.5))
	query.collision_mask = 2
	query.collide_with_bodies = false
	query.collide_with_areas = true
	for hit:Dictionary in get_world_2d().direct_space_state.intersect_shape(query,32):
		var area:Variant = hit.get("collider")
		if area is hurtbox and area.get_parent() == target:
			_dash_hit = true
			target.receive_positional_damage(attack_damage(),global_position,false,self)
			return
func _finish_dash() -> void:
	_charging = false
	_windup = 0.0
	_dash_distance = 0.0
	_roam_wait = 0.0
	# 固定画布与比例，结束冲刺不再换回无动画静态图。
