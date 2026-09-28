extends Node
## 蓝冰 momentum on one enemy (child node "WTIceBoost"). While the enemy stands on blue ice its
## own movement direction gains extra speed (acceleration up to max_ratio of its base speed).
## Off the ice the extra speed decays slowly; if it runs into a wall / obstacle before the
## boost has worn off it takes damage scaled by the remaining boost and the boost bounces off.
## Uses the shared additive ball.surface_motion_velocity channel (no Speed buff, no control lock).
const CATALOG = preload("res://scripts/characters/我的世界/wandering_trader/items/catalog.gd")
const NODE_NAME:StringName = &"WTIceBoost"
const ACCELERATION:float = 240.0
const MAX_RATIO:float = 1.3
const DECAY:float = 70.0
const WALL_MIN_SPEED:float = 20.0
const WALL_DAMAGE_MIN:float = 6.0
const WALL_DAMAGE_MAX:float = 30.0
var target_ref:WeakRef
var trader_ref:WeakRef
var momentum:Vector2 = Vector2.ZERO
var on_ice_time:float = 0.0 # >0 while touching ice this frame (refreshed by the patch)
var wall_hits:int = 0
var _previous:Vector2
var _wall_wait:float = 0.0

static func touch(target:ball,trader:Node) -> Node:
	if not is_instance_valid(target) or not target.is_multiplayer_authority() or target.health <= 0: return null
	var boost:Node = target.get_node_or_null(NodePath(NODE_NAME))
	if boost != null and boost.is_queued_for_deletion():
		target.remove_child(boost)
		boost = null
	if boost == null:
		boost = (load("res://scripts/characters/我的世界/wandering_trader/items/ice_boost.gd") as Script).new()
		boost.name = NODE_NAME
		boost.target_ref = weakref(target)
		boost._previous = target.global_position
		boost.process_physics_priority = -40
		target.add_child(boost)
	boost.trader_ref = weakref(trader)
	boost.on_ice_time = 0.1
	return boost

func max_speed(target:ball) -> float:
	var base:float = maxf(target.Speed,0.0)*(target.CHARACTER_BASE_MOVE_SPEED_MULTIPLIER if target.Type == ball.Ball_Type.Ball else 1.0)
	return maxf(base,30.0)*MAX_RATIO

func boost_ratio() -> float:
	var target:Variant = target_ref.get_ref() if target_ref != null else null
	if not is_instance_valid(target): return 0.0
	return clampf(momentum.length()/max_speed(target),0.0,1.0)

func _physics_process(delta:float) -> void:
	var target:Variant = target_ref.get_ref() if target_ref != null else null
	if not is_instance_valid(target) or target.health <= 0:
		_finish()
		return
	if CATALOG.paused(target) or not target.is_combat_runtime_active():
		_previous = target.global_position
		return
	_wall_wait = maxf(_wall_wait - delta,0.0)
	_check_wall(target)
	var traveled:Vector2 = target.global_position - _previous
	_previous = target.global_position
	var on_ice:bool = on_ice_time > 0.0
	on_ice_time -= delta
	if on_ice:
		var heading:Vector2 = traveled.normalized() if traveled.length() > 0.01 and traveled.length() < 30.0 else (momentum.normalized() if momentum.length_squared() > 0.01 else Vector2(target.direction))
		if heading.length_squared() > 0.000001:
			momentum = heading.normalized()*minf(momentum.length() + ACCELERATION*delta,max_speed(target))
	else:
		momentum = momentum.move_toward(Vector2.ZERO,DECAY*delta)
	# Another controller (e.g. sulfur ice) owns the channel: never fight it.
	if target.get_node_or_null(^"SurfaceAcceleration") == null: target.surface_motion_velocity = momentum
	if not on_ice and momentum.is_zero_approx(): _finish()

## Last move's slide collisions (this node runs before the unit's own movement this frame).
func _check_wall(target:ball) -> void:
	if momentum.length() < WALL_MIN_SPEED or _wall_wait > 0.0: return
	for i:int in range(target.get_slide_collision_count()):
		var collision:KinematicCollision2D = target.get_slide_collision(i)
		if collision == null or collision.get_collider() is ball: continue
		var normal:Vector2 = collision.get_normal()
		if momentum.dot(normal) >= -0.2*momentum.length(): continue
		var ratio:float = boost_ratio()
		var trader:Variant = trader_ref.get_ref() if trader_ref != null else null
		var amount:float = lerpf(WALL_DAMAGE_MIN,WALL_DAMAGE_MAX,ratio)
		wall_hits += 1
		_wall_wait = 0.45
		momentum = momentum.bounce(normal)*0.45
		# Neutral ice: credit the trader only against his enemies (his own side must not be blocked
		# by the team-damage rule, like the neutral dripstone / cactus); works without him too.
		CATALOG.hurt(trader,target,amount,collision.get_position(),CATALOG.enemy_of(trader,target))
		if is_instance_valid(trader): trader.set(&"ice_wall_hits",int(trader.get(&"ice_wall_hits")) + 1)
		return

func _finish() -> void:
	var target:Variant = target_ref.get_ref() if target_ref != null else null
	if is_instance_valid(target) and target.get_node_or_null(^"SurfaceAcceleration") == null: target.surface_motion_velocity = Vector2.ZERO
	momentum = Vector2.ZERO
	queue_free()

func _exit_tree() -> void:
	var target:Variant = target_ref.get_ref() if target_ref != null else null
	if is_instance_valid(target) and target.get_node_or_null(^"SurfaceAcceleration") == null: target.surface_motion_velocity = Vector2.ZERO
