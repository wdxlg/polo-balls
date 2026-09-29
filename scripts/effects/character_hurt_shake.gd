extends Node
## Render-only additive body shake. Never writes Node2D transforms, physics or RNG.
## Composed immediately before drawing so animation/stun/network poses remain intact.
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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

static func strength_for_damage(actual_damage:float) -> float:
	if not is_finite(actual_damage) or actual_damage<=0.0: return 0.0
	return minf(MAX_AMPLITUDE,1.8+16.2*sqrt(actual_damage/(actual_damage+60.0)))

func _can_play() -> bool:
	return is_instance_valid(actor) and is_instance_valid(graphics) and actor.is_inside_tree() and graphics.is_inside_tree() and not actor.is_queued_for_deletion() and float(actor.get("health"))>0 and bool(actor.get("hurt_shake_enabled")) and not Game.now_stop_state and not get_tree().paused and Engine.time_scale>0.0 and bool(actor.call("is_combat_runtime_active"))

func kick(actual_damage:float) -> void:
	var incoming:float = strength_for_damage(actual_damage)
	if incoming<=0.0 or not _can_play(): return
	var weight:float = clampf((incoming-1.8)/16.2,0.0,1.0)
	var current:float = amplitude*pow(maxf(0.0,1.0-age/maxf(duration,0.001)),1.5) if active else 0.0
	var remaining:float = maxf(duration-age,0.0) if active else 0.0
	if not active:
		phase = 0.0
		_last_tick = Time.get_ticks_usec()
	amplitude = minf(MAX_AMPLITUDE,maxf(current,incoming))
	duration = minf(MAX_DURATION,maxf(remaining,lerpf(0.16,MAX_DURATION,weight)))
	age = 0.0
	active = true
	if not RenderingServer.frame_pre_draw.is_connected(_present):
		RenderingServer.frame_pre_draw.connect(_present)
	set_process(true)
	_update_offset()

func _process(_delta:float) -> void:
	var now:int = Time.get_ticks_usec()
	var real_delta:float = maxf(float(now-_last_tick)/1000000.0,0.0)
	_last_tick = now
	advance(real_delta)

func advance(real_delta:float) -> void:
	if not active: return
	if not _can_play():
		stop()
		return
	age += maxf(real_delta,0.0)
	phase = fposmod(phase+maxf(real_delta,0.0)*TAU*22.0,TAU*100.0)
	if age>=duration:
		stop()
		return
	_update_offset()

func _update_offset() -> void:
	var envelope:float = pow(maxf(1.0-age/maxf(duration,0.001),0.0),1.5)
	var wave := Vector2(cos(phase)*0.78+cos(phase*1.71+0.8)*0.22,sin(phase*1.31+0.4)*0.48)
	world_offset = wave.limit_length(1.0)*amplitude*envelope

func _present() -> void:
	if not active: return
	if not _can_play():
		stop()
		return
	last_render_transform = _render_part(graphics)
	var parts:Array[Node2D] = extra_parts_provider.call() if extra_parts_provider.is_valid() else extra_graphics
	# A held item may launch mid-shake: restore its own current pose immediately.
	for previous:Node2D in _rendered_extra_graphics:
		if is_instance_valid(previous) and previous.is_inside_tree() and not parts.has(previous):
			RenderingServer.canvas_item_set_transform(previous.get_canvas_item(),previous.transform)
	for part:Node2D in parts:
		if is_instance_valid(part) and part.is_inside_tree(): _render_part(part)
	_rendered_extra_graphics.assign(parts)

func _render_part(part:Node2D) -> Transform2D:
	var pose:Transform2D = part.transform
	var offset:Vector2 = world_offset
	if not part.is_set_as_top_level():
		var ancestor:Node = part.get_parent()
		while ancestor!=null and not ancestor is CanvasItem and not ancestor is CanvasLayer and not ancestor is Viewport:
			ancestor = ancestor.get_parent()
		var parent:CanvasItem = ancestor as CanvasItem
		if parent!=null:
			var basis:Transform2D = parent.get_global_transform()
			if absf(basis.determinant())<0.000001: return pose
			# basis_xform_inv assumes orthonormal axes; characters use scaled bases.
			offset = basis.affine_inverse().basis_xform(offset)
	pose.origin += offset
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
	set_process(false)
	if RenderingServer.frame_pre_draw.is_connected(_present):
		RenderingServer.frame_pre_draw.disconnect(_present)

func _exit_tree() -> void:
	stop()
