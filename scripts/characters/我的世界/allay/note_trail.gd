extends Node2D
## World-space visual only: survives its projectile briefly, never deals damage.
const NOTE_TEXTURE = preload("res://Images/characters/我的世界/allay/note.png")
const INTERVAL:float = 0.045
const LIFETIME:float = 0.45
const MAX_PARTICLES:int = 16
var source_ref:WeakRef
var particles:Array[Dictionary] = []
var _previous:Vector2 = Vector2.ZERO
var _elapsed:float = 0.0

func setup(source:Node2D) -> void:
	source_ref = weakref(source)
	_previous = source.global_position
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_as_relative = false
	z_index = 101
	add_to_group("BattleTransient")

func _process(delta:float) -> void:
	if Game.now_stop_state: return
	var source:Node2D = source_ref.get_ref() if source_ref != null else null
	var emitting:bool = is_instance_valid(source) and not source.is_queued_for_deletion()
	if emitting and not source.is_combat_runtime_active(): return
	advance(source.global_position if emitting else _previous,delta,emitting)

func advance(point:Vector2,delta:float,emitting:bool) -> void:
	if delta<=0.0: return
	for i:int in range(particles.size()-1,-1,-1):
		var particle:Dictionary = particles[i]
		particle["life"] = float(particle["life"])-delta
		particle["pos"] = Vector2(particle["pos"])+Vector2(particle["velocity"])*delta
		if float(particle["life"])<=0.0: particles.remove_at(i)
	if emitting:
		# Cap catch-up after a stalled frame; do not spawn unbounded particles.
		var step:float = minf(delta,0.1)
		_elapsed += step
		while _elapsed>=INTERVAL:
			_elapsed -= INTERVAL
			var position_on_path:Vector2 = _previous.lerp(point,clampf(1.0-_elapsed/step,0.0,1.0))
			if particles.size()>=MAX_PARTICLES: particles.pop_front()
			particles.append({"pos":position_on_path+Vector2(randf_range(-2.0,2.0),randf_range(-2.0,2.0)),"velocity":Vector2(randf_range(-5.0,5.0),randf_range(-15.0,-7.0)),"life":LIFETIME,"size":randf_range(8.0,12.0)})
	_previous = point
	queue_redraw()
	if not emitting and particles.is_empty(): queue_free()

func _draw() -> void:
	for particle:Dictionary in particles:
		var remaining:float = clampf(float(particle["life"])/LIFETIME,0.0,1.0)
		var size:float = float(particle["size"])*lerpf(0.35,1.0,remaining)
		var point:Vector2 = to_local(Vector2(particle["pos"]))
		draw_texture_rect(NOTE_TEXTURE,Rect2(point-Vector2.ONE*size*0.7,Vector2.ONE*size*1.4),false,Color(0.3,0.62,1.0,0.16*remaining))
		draw_texture_rect(NOTE_TEXTURE,Rect2(point-Vector2.ONE*size*0.5,Vector2.ONE*size),false,Color(0.4,0.75,1.0,0.8*remaining))
