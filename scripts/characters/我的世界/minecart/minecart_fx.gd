extends Node2D
## Texture-only FX: Mojang's smoke, redstone, critical-hit and electric-spark atlas frames.
## No SVG, generated artwork, drawn rings, arrows or line trails.
const NATIVE = preload("res://scripts/characters/我的世界/minecart/native_particles.gd")
var cart:Node2D
var particles:Array[Dictionary] = []
var trail:Array[Vector2] = []
var time:float = 0.0
var _trail_wait:float = 0.0
var _spark_wait:float = 0.0
var _rng := RandomNumberGenerator.new()
func _ready() -> void:
	top_level = true
	scale = Vector2.ONE
	z_as_relative = false
	z_index = 7
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.seed = int(get_instance_id())
func impact_kind() -> String:
	return "crit"
func emit(kind:String,point:Vector2,velocity_value:Vector2,life:float,size:float) -> void:
	if particles.size() >= 56: return
	particles.append({"point":point,"velocity":velocity_value,"age":0.0,"life":life,"kind":kind,"size":size})
func burst(kind:String,point:Vector2,heading:Vector2) -> void:
	var number:int = 18 if kind in ["wall","hit"] else 12
	for i:int in range(number):
		var particle_kind:String = impact_kind()
		if kind == "rail": particle_kind = "redstone"
		elif kind == "wall" and i%3 == 0: particle_kind = "electric"
		elif kind == "charge": particle_kind = "smoke"
		var axis:Vector2 = heading.rotated(_rng.randf_range(-1.8,1.8))
		emit(particle_kind,point,axis*_rng.randf_range(35,110),_rng.randf_range(0.25,0.5),_rng.randf_range(5,9))
	queue_redraw()
func _process(delta:float) -> void:
	if not is_instance_valid(cart): queue_free(); return
	global_position = cart.global_position
	if Game.now_stop_state or get_tree().paused or not cart.is_combat_runtime_active(): return
	time += delta
	for i:int in range(particles.size()-1,-1,-1):
		particles[i].age += delta
		particles[i].point += particles[i].velocity*delta
		particles[i].velocity *= maxf(0.0,1.0-delta*5.0)
		if particles[i].age >= particles[i].life: particles.remove_at(i)
	_trail_wait -= delta
	_spark_wait -= delta
	if cart.rush_phase in [2,3]:
		if _trail_wait <= 0.0:
			_trail_wait = 0.025
			trail.append(cart.global_position)
			if trail.size() > 14: trail.pop_front()
		if _spark_wait <= 0.0:
			_spark_wait = 0.08
			for side:int in [-1,1]:
				emit("redstone" if cart.rail_powered else "electric",cart.global_position-cart.rush_direction*12+cart.rush_direction.orthogonal()*side*8,-cart.rush_direction*65+Vector2(0,-10),0.3,6.0)
	else:
		if not trail.is_empty() and _trail_wait <= 0.0:
			_trail_wait = 0.025
			trail.pop_front()
		if cart.rush_phase == 1 and _spark_wait <= 0.0:
			_spark_wait = 0.07
			var progress:float = 1.0-cart.charge_left/maxf(cart.charge_duration,0.1)
			var p:Vector2 = cart.global_position+cart.rush_direction*(12.0+progress*16.0)+Vector2(_rng.randf_range(-3,3),-5)
			emit("redstone" if cart.rail_powered else "smoke",p,Vector2(0,-20),0.45,6.0+progress*4)
	queue_redraw()
func _draw() -> void:
	if not is_instance_valid(cart) or cart.health <= 0: return
	for i:int in range(trail.size()):
		var progress:float = 1.0-float(i+1)/float(trail.size())
		var kind:String = "redstone" if cart.rail_powered else "smoke"
		NATIVE.draw(self,kind,to_local(trail[i])+Vector2(0,-progress*8),8.0+progress*9,progress,(1.0-progress)*0.65)
	for particle:Dictionary in particles:
		var progress:float = particle.age/particle.life
		NATIVE.draw(self,particle.kind,to_local(particle.point),particle.size,progress,1.0-progress)
