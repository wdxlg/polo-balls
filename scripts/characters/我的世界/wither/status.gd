extends Node2D
## One status per target; refresh rather than stacking damage or tint.
var source_ref:WeakRef
var remaining:float = 0.0
var tick_left:float = 1.0
var saved_color:Color = Color.WHITE
var painted:bool = false
func refresh(source:ball) -> void:
	source_ref = weakref(source)
	remaining = 3.0
	if not painted and get_parent() is ball:
		var target:ball = get_parent() as ball
		if target.image is CanvasItem:
			saved_color = target.image.modulate
			target.image.modulate = Color(0.24,0.21,0.28,1.0)
			painted = true
func _physics_process(delta:float) -> void:
	var target:ball = get_parent() as ball
	var source:Variant = source_ref.get_ref() if source_ref != null else null
	if target == null or target.health <= 0 or not is_instance_valid(source) or source.health <= 0: queue_free(); return
	if not source.is_combat_runtime_active(): return
	remaining -= delta
	if source.is_multiplayer_authority():
		tick_left -= delta
		if tick_left <= 0 and remaining > 0:
			tick_left += 1.0
			source.impact(target,4.0,target.global_position)
	if remaining <= 0: queue_free()
func _process(_delta:float) -> void:
	queue_redraw()
func _draw() -> void:
	if remaining <= 0: return
	var time:float = Time.get_ticks_msec()*0.001
	for i:int in range(6):
		var phase:float = time*1.8+float(i)*1.047
		draw_circle(Vector2(sin(phase)*19.0,-12.0-fmod(phase*13.0,48.0)),2.8,Color(0.28,0.17,0.36,0.7))
func _exit_tree() -> void:
	var target:ball = get_parent() as ball
	if painted and is_instance_valid(target) and target.image is CanvasItem and target.image.modulate.is_equal_approx(Color(0.24,0.21,0.28,1.0)):
		target.image.modulate = saved_color
