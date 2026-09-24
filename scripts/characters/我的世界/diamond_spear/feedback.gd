extends Node2D
## Bounded, local-only drawing. No damage, camera shake or simulation/audio time changes.
var caster:Node2D
var kind:int = 0 # 0 = piercing line, 1 = confirmed impact.
var origin:Vector2
var endpoint:Vector2
var lifetime:float = 0.15
var hold:float = 0.032
var elapsed:float = 0.0
var previous_elapsed:float = 0.0
var _render_time:float = 0.0
var _length:float = 0.0

func _ready() -> void:
	top_level = true
	global_position = origin
	global_rotation = (endpoint-origin).angle()
	global_scale = Vector2.ONE
	_length = origin.distance_to(endpoint)
	z_as_relative = false
	z_index = 4
	add_to_group("DiamondSpearFeedback")
	add_to_group("BattleTransient")
	queue_redraw()

func _physics_process(delta:float) -> void:
	if not is_instance_valid(caster) or caster.is_queued_for_deletion():
		queue_free()
		return
	if not caster.is_combat_runtime_active(): return
	previous_elapsed = elapsed
	elapsed += delta
	_render_at(elapsed)
	if elapsed>=lifetime: queue_free()

func _process(_delta:float) -> void:
	if not is_instance_valid(caster) or not caster.is_combat_runtime_active(): return
	_render_at(lerpf(previous_elapsed,elapsed,Engine.get_physics_interpolation_fraction()))

func _render_at(time:float) -> void:
	_render_time = clampf(time,0.0,lifetime)
	queue_redraw()

func _draw() -> void:
	var progress:float = clampf(_render_time/maxf(lifetime,0.001),0.0,1.0)
	var alpha:float = pow(1.0-progress,1.6)
	if kind==0:
		# The original geometry-checked crossing, never a line to a moving target.
		var tip := Vector2(_length,0)
		draw_line(Vector2.ZERO,tip,Color(0.20,0.90,1.0,alpha*0.28),5.0,true)
		draw_line(Vector2.ZERO,tip,Color(0.76,1.0,1.0,alpha),1.3,true)
		var arrow := PackedVector2Array([tip,tip+Vector2(-8,-3),tip+Vector2(-5,0),tip+Vector2(-8,3)])
		draw_colored_polygon(arrow,Color(0.88,1.0,1.0,alpha))
	else:
		# Hold only this hit's drawing for ~32 ms, then open along the incoming direction.
		var release:float = clampf((_render_time-hold)/maxf(lifetime-hold,0.001),0.0,1.0)
		var radius:float = lerpf(3.0,14.0,sqrt(release))
		var core := PackedVector2Array([Vector2(-radius*0.7,0),Vector2(0,-radius*0.30),Vector2(radius,0),Vector2(0,radius*0.30)])
		draw_colored_polygon(core,Color(0.76,1.0,1.0,alpha))
		for angle:float in [-0.65,-0.28,0.28,0.65,PI-0.50,PI+0.50]:
			var axis := Vector2.RIGHT.rotated(angle)
			draw_line(axis*radius*0.70,axis*(radius+5.0),Color(0.28,0.94,1.0,alpha*0.75),1.0,true)
