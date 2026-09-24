extends Node2D
# Java 1.21.4 firework.json -> spark_7 ... spark_0; world-space particles.
var source:WeakRef
var emit_left:float = 0.0
var particles:Array[Dictionary] = []
var frames:Array[Texture2D] = []
var last_position:Vector2
var emission_clock:float = 0.0
var sequence:int = 0
const LIFETIME:float = 0.75
const MAX_PARTICLES:int = 128
func _ready() -> void:
	top_level = true
	global_transform = Transform2D.IDENTITY
	z_as_relative = false
	z_index = 103
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_to_group("BattleTransient")
	for i:int in range(7,-1,-1):
		frames.append(load("res://Images/characters/我的世界/elytra_mace/spark_%d.png" % i) as Texture2D)
func begin(actor:Node2D,duration:float) -> void:
	source = weakref(actor)
	emit_left = maxf(emit_left,duration)
	last_position = actor.global_position
func _physics_process(delta:float) -> void:
	advance(delta)
func advance(delta:float) -> void:
	if get_tree().paused or Game.now_stop_state:
		return
	var actor:Node2D = source.get_ref() as Node2D if source != null else null
	if actor != null and actor.health > 0 and not actor.is_combat_runtime_active():
		return
	for i:int in range(particles.size()-1,-1,-1):
		var p:Dictionary = particles[i]
		p.age += delta
		p.velocity.y += 12.0*delta
		p.position += p.velocity*delta
		if p.age >= LIFETIME: particles.remove_at(i)
	if actor == null or actor.health <= 0:
		emit_left = 0.0
	if emit_left > 0.0 and actor != null:
		emit_left = maxf(emit_left-delta,0.0)
		emission_clock += delta
		var current:Vector2 = actor.global_position
		var distance:float = last_position.distance_to(current)
		if emission_clock >= 0.018 or distance >= 5.0:
			var count:int = clampi(int(ceil(distance/5.0)),1,16)
			# 传送不画一条贯穿地图的连接线。
			if distance > 250.0: last_position = current
			for i:int in range(count):
				sequence += 1
				var jitter:Vector2 = Vector2(sin(sequence*2.4),cos(sequence*1.7))
				var position_value:Vector2 = last_position.lerp(current,float(i+1)/count)+jitter*2.0
				if particles.size() >= MAX_PARTICLES: particles.pop_front()
				particles.append({"position":position_value,"velocity":jitter*9.0,"age":0.0})
			last_position = current
			emission_clock = 0.0
	queue_redraw()
	if emit_left <= 0.0 and particles.is_empty(): queue_free()
func _draw() -> void:
	if frames.size() != 8: return
	for p:Dictionary in particles:
		var t:float = clampf(float(p.age)/LIFETIME,0.0,1.0)
		var index:int = mini(int(t*8.0),7)
		var size:float = lerpf(4.0,2.0,t)
		var tint:Color = Color(1.0,0.96,0.8,1.0-t)
		draw_texture_rect(frames[index],Rect2(p.position-Vector2.ONE*size*0.5,Vector2.ONE*size),false,tint)
