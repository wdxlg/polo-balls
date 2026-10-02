extends Node
## Render-only additive body shake. Never writes Node2D transforms, physics or RNG.
## Composed immediately before drawing so animation/stun/network poses remain intact.
const TUNING = preload("res://global/feedback_settings.gd")
const STRONG_DAMAGE_THRESHOLD:float = 50.0
const LIGHT_MAX_AMPLITUDE:float = 0.6
const MAX_AMPLITUDE:float = 18.0
const MAX_DURATION:float = 0.28
var actor:Node2D
var graphics:Node2D
# Opt-in detached artwork (e.g. top-level held weapons), never live projectiles.
var extra_graphics:Array[Node2D] = []
var extra_parts_provider:Callable
var _rendered_extra_graphics:Array[Node2D] = []
var amplitude:float = 0.0
var duration:float = 0.0
var age:float = 0.0
var phase:float = 0.0
var active:bool = false
var world_offset:Vector2 = Vector2.ZERO
var last_render_transform:Transform2D = Transform2D.IDENTITY
var _last_tick:int = 0
# Squash along the hit direction, then an underdamped spring back (slight stretch).
const SQUASH_MIN:float = 0.05
const SQUASH_MAX:float = 0.26
const SQUASH_FREQUENCY:float = 16.0
const SQUASH_DAMPING_RATIO:float = 0.45
const SQUASH_SIDE_RATIO:float = 0.5
var squash_axis:Vector2 = Vector2.RIGHT
var squash_amount:float = 0.0
var squash_velocity:float = 0.0
var squash_active:bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

static func strength_for_damage(actual_damage:float,settings:Dictionary = {}) -> float:
	return TUNING.amplitude(actual_damage,settings,"Body")

static func light_damage_limit(settings:Dictionary) -> float:
	return TUNING.number(settings,"Shake_High")

static func squash_for_damage(effective_damage:float,reference_health:float) -> float:
	if not is_finite(effective_damage) or effective_damage <= 0.0: return 0.0
	var ratio:float = clampf(effective_damage/maxf(reference_health*0.35,24.0),0.0,1.0)
	return lerpf(SQUASH_MIN,SQUASH_MAX,sqrt(ratio))

func _can_play() -> bool:
	return is_instance_valid(actor) and is_instance_valid(graphics) and actor.is_inside_tree() and graphics.is_inside_tree() and not actor.is_queued_for_deletion() and float(actor.get("health"))>0 and bool(actor.get("hurt_shake_enabled")) and not Game.now_stop_state and not get_tree().paused and Engine.time_scale>0.0 and TUNING.number(Game.Game_Settings,"Body_Gain")>0.0 and bool(actor.call("is_combat_runtime_active"))

func kick(actual_damage:float) -> void:
	var incoming:float = strength_for_damage(actual_damage,Game.Game_Settings)
	if incoming<=0.0 or not _can_play(): return
	var current:float = amplitude*pow(maxf(0.0,1.0-age/maxf(duration,0.001)),1.5) if active else 0.0
	# Small repeated ticks cannot keep an earlier heavy hit shaking indefinitely.
	if active and incoming < current: return
	var remaining:float = maxf(duration-age,0.0) if active else 0.0
	if not active:
		phase = 0.0
		_last_tick = Time.get_ticks_usec()
	amplitude = maxf(current,incoming)
	duration = maxf(remaining,TUNING.duration(actual_damage,Game.Game_Settings))
	age = 0.0
	active = true
	_start_rendering()
	_update_offset()

func squash(direction:Vector2,effective_damage:float,reference_health:float) -> void:
	if not direction.is_finite() or direction.length_squared() <= 0.000001: return
	var peak:float = squash_for_damage(effective_damage,reference_health)
	if peak <= 0.0 or not _can_play(): return
	# A weaker hit cannot cut short a stronger squash that is still recovering.
	if squash_active and peak < absf(squash_amount): return
	if not active and not squash_active: _last_tick = Time.get_ticks_usec()
	squash_axis = direction.normalized()
	squash_amount = peak
	squash_velocity = 0.0
	squash_active = true
	_start_rendering()

func _start_rendering() -> void:
	if not RenderingServer.frame_pre_draw.is_connected(_present):
		RenderingServer.frame_pre_draw.connect(_present)
	set_process(true)

func _process(_delta:float) -> void:
	var now:int = Time.get_ticks_usec()
	var real_delta:float = maxf(float(now-_last_tick)/1000000.0,0.0)
	_last_tick = now
	advance(real_delta)

func advance(real_delta:float) -> void:
	if not active and not squash_active: return
	if not _can_play():
		stop()
		return
	if squash_active: _advance_squash(maxf(real_delta,0.0))
	if active:
		age += maxf(real_delta,0.0)
		phase = fposmod(phase+maxf(real_delta,0.0)*TAU*TUNING.number(Game.Game_Settings,"Shake_Frequency"),TAU*100.0)
		if age>=duration:
			active = false
			amplitude = 0.0
			age = 0.0
			duration = 0.0
			world_offset = Vector2.ZERO
		else:
			_update_offset()
	if not active and not squash_active: stop()

func _advance_squash(real_delta:float) -> void:
	var omega:float = SQUASH_FREQUENCY
	var remaining:float = minf(real_delta,0.25)
	while remaining > 0.0:
		var step:float = minf(remaining,1.0/240.0)
		squash_velocity += (-omega*omega*squash_amount-2.0*SQUASH_DAMPING_RATIO*omega*squash_velocity)*step
		squash_amount += squash_velocity*step
		remaining -= step
	if absf(squash_amount) < 0.002 and absf(squash_velocity) < 0.05:
		squash_active = false
		squash_amount = 0.0
		squash_velocity = 0.0

## World-space squash matrix: compressed along the hit axis, widened across it.
func squash_basis() -> Transform2D:
	if not squash_active: return Transform2D.IDENTITY
	var along:float = 1.0-squash_amount
	var across:float = 1.0+squash_amount*SQUASH_SIDE_RATIO
	var a:Vector2 = squash_axis
	var p:Vector2 = Vector2(-a.y,a.x)
	return Transform2D(a*(along*a.x)+p*(across*p.x),a*(along*a.y)+p*(across*p.y),Vector2.ZERO)

func _update_offset() -> void:
	var envelope:float = pow(maxf(1.0-age/maxf(duration,0.001),0.0),1.5)
	var wave := Vector2(cos(phase)*0.78+cos(phase*1.71+0.8)*0.22,sin(phase*1.31+0.4)*0.48)
	world_offset = wave.limit_length(1.0)*amplitude*envelope

func _present() -> void:
	if not active and not squash_active: return
	if not _can_play():
		stop()
		return
	last_render_transform = _render_part(graphics,true)
	var parts:Array[Node2D] = extra_parts_provider.call() if extra_parts_provider.is_valid() else extra_graphics
	# A held item may launch mid-shake: restore its own current pose immediately.
	for previous:Node2D in _rendered_extra_graphics:
		if is_instance_valid(previous) and previous.is_inside_tree() and not parts.has(previous):
			RenderingServer.canvas_item_set_transform(previous.get_canvas_item(),previous.transform)
	for part:Node2D in parts:
		if is_instance_valid(part) and part.is_inside_tree(): _render_part(part)
	_rendered_extra_graphics.assign(parts)

func _render_part(part:Node2D,with_squash:bool = false) -> Transform2D:
	var pose:Transform2D = part.transform
	var offset:Vector2 = world_offset
	var basis:Transform2D = Transform2D.IDENTITY
	if not part.is_set_as_top_level():
		var ancestor:Node = part.get_parent()
		while ancestor!=null and not ancestor is CanvasItem and not ancestor is CanvasLayer and not ancestor is Viewport:
			ancestor = ancestor.get_parent()
		var parent:CanvasItem = ancestor as CanvasItem
		if parent!=null:
			basis = parent.get_global_transform()
			if absf(basis.determinant())<0.000001: return pose
			# basis_xform_inv assumes orthonormal axes; characters use scaled bases.
			offset = basis.affine_inverse().basis_xform(offset)
	pose.origin += offset
	if with_squash and squash_active and is_instance_valid(actor):
		# Squash in world space around the body centre, so flipped/scaled parents stay correct.
		var world_pose:Transform2D = basis*pose
		var center:Vector2 = actor.global_position+world_offset
		var squash_matrix:Transform2D = squash_basis()
		world_pose = Transform2D(squash_matrix.basis_xform(world_pose.x),squash_matrix.basis_xform(world_pose.y),center+squash_matrix.basis_xform(world_pose.origin-center))
		pose = basis.affine_inverse()*world_pose
	RenderingServer.canvas_item_set_transform(part.get_canvas_item(),pose)
	return pose

func stop() -> void:
	if is_instance_valid(graphics) and graphics.is_inside_tree():
		last_render_transform = graphics.transform
		RenderingServer.canvas_item_set_transform(graphics.get_canvas_item(),graphics.transform)
	for part:Node2D in _rendered_extra_graphics:
		if is_instance_valid(part) and part.is_inside_tree():
			RenderingServer.canvas_item_set_transform(part.get_canvas_item(),part.transform)
	_rendered_extra_graphics.clear()
	active = false
	amplitude = 0.0
	age = 0.0
	duration = 0.0
	world_offset = Vector2.ZERO
	squash_active = false
	squash_amount = 0.0
	squash_velocity = 0.0
	set_process(false)
	if RenderingServer.frame_pre_draw.is_connected(_present):
		RenderingServer.frame_pre_draw.disconnect(_present)

func _exit_tree() -> void:
	stop()
