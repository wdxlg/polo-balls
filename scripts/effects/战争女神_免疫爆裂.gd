extends Node2D

@export_range(0.2,1.5,0.01) var duration:float = 0.72
@export_range(4,40,1) var spark_count:int = 20
@export_range(20.0,320.0,1.0) var min_speed:float = 95.0
@export_range(20.0,420.0,1.0) var max_speed:float = 210.0
@export_range(-240.0,240.0,1.0) var upward_accel:float = -46.0
@export_range(0.5,8.0,0.1) var line_width:float = 2.2

var _elapsed:float = 0.0
var _sparks:Array[Dictionary] = []
var _configured:bool = false

func setup(seed_value:int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_sparks.clear()
	for i:int in range(maxi(spark_count,1)):
		# 火焰免疫的碎屑整体向外散，同时略偏向上方，避免看起来像静态贴点。
		var angle:float = rng.randf_range(-PI * 0.92, PI * 0.92)
		var radial := Vector2.RIGHT.rotated(angle)
		var speed:float = rng.randf_range(min_speed,max_speed)
		var velocity:Vector2 = radial * speed + Vector2(rng.randf_range(-20.0,20.0),rng.randf_range(-72.0,-18.0))
		_sparks.append({
			"position": Vector2(rng.randf_range(-3.0,3.0),rng.randf_range(-3.0,3.0)),
			"velocity": velocity,
			"length": rng.randf_range(7.0,18.0),
			"size": rng.randf_range(1.4,3.2),
			"heat": rng.randf(),
		})
	_configured = true
	queue_redraw()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_as_relative = false
	z_index = 40
	if not _configured:
		setup(Game.battle_rng_seed_or("scripts/effects/战争女神_免疫爆裂.gd:setup_seed",int(Time.get_ticks_usec()) ^ get_instance_id()))
	queue_redraw()

func _process(delta:float) -> void:
	_elapsed += maxf(delta,0.0)
	for i:int in range(_sparks.size()):
		var spark:Dictionary = _sparks[i]
		var pos:Vector2 = spark.get("position",Vector2.ZERO)
		var velocity:Vector2 = spark.get("velocity",Vector2.ZERO)
		pos += velocity * delta
		velocity += Vector2(0.0,upward_accel) * delta
		velocity *= maxf(1.0 - delta * 1.15,0.0)
		spark["position"] = pos
		spark["velocity"] = velocity
		_sparks[i] = spark
	queue_redraw()
	if _elapsed >= maxf(duration,0.05):
		queue_free()

func _draw() -> void:
	var t:float = clampf(_elapsed / maxf(duration,0.05),0.0,1.0)
	var fade:float = pow(1.0 - t,1.35)
	var flash:float = clampf(1.0 - t * 4.5,0.0,1.0)

	# 起始白热闪光 + 向外扩散的橙红环，确保免疫本身第一眼就看得出来。
	if flash > 0.0:
		draw_circle(Vector2.ZERO,lerpf(9.0,3.0,t),Color(1.0,0.96,0.62,0.72 * flash))
	var ring_radius:float = lerpf(6.0,42.0,t)
	draw_arc(Vector2.ZERO,ring_radius,0.0,TAU,42,Color(1.0,0.34,0.025,0.82 * fade),lerpf(3.5,1.0,t),true)

	for spark:Dictionary in _sparks:
		var pos:Vector2 = spark.get("position",Vector2.ZERO)
		var velocity:Vector2 = spark.get("velocity",Vector2.RIGHT)
		var dir:Vector2 = velocity.normalized() if velocity.length_squared() > 0.0001 else Vector2.RIGHT
		var trail_length:float = float(spark.get("length",10.0)) * (0.45 + fade * 0.75)
		var size:float = float(spark.get("size",2.0))
		var heat:float = float(spark.get("heat",0.5))
		var tail_color := Color(1.0,0.16 + heat * 0.18,0.01,0.34 * fade)
		var head_color := Color(1.0,0.72 + heat * 0.22,0.12,0.98 * fade)
		draw_line(pos - dir * trail_length,pos,tail_color,maxf(line_width * (0.75 + heat * 0.5),0.8),true)
		draw_circle(pos,size * (0.7 + fade * 0.5),head_color)
