extends Node2D
## Moss burrow / placement accents only. Destruction is shared block_fragments.gd.
## Ground turf stays below obstacles; these airborne fragments use a separate layer.
const MOSS:Texture2D = preload("res://Images/characters/我的世界/frontier/moss_tile.png")
const MAX_BLOCKS:int = 32
const GRAVITY:float = 460.0
var actor:Node2D
var blocks:Array[Dictionary] = []
var elapsed:float = 0.0
var duration:float = 0.0
var _rng := RandomNumberGenerator.new()
func setup(owner_actor:Node2D,point:Vector2,emerging:bool,cell_size:float,placed:bool = false) -> void:
	actor = owner_actor
	if placed: add_to_group("MCMossPlaceDebris")
	top_level = true
	global_position = point
	global_scale = Vector2.ONE
	z_as_relative = false
	z_index = 4
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.seed = int(point.x*92821.0+point.y*68917.0)+int(emerging)*317
	var pixels:Image = MOSS.get_image()
	var count:int = 6 if placed else 28 if emerging else 24
	blocks.clear()
	duration = 0.0
	for i:int in range(mini(count,MAX_BLOCKS)):
		var start:Vector2
		if placed:
			start = Vector2(_rng.randf_range(-0.4,0.4),_rng.randf_range(-0.4,0.4))*cell_size
		elif emerging:
			# Center of the exit cell, not its outline.
			start = Vector2(_rng.randf_range(-0.22,0.22),_rng.randf_range(-0.22,0.22))*cell_size
		else:
			# Evenly cover the four straight edges of the entry cell, never a circle.
			var along:float = _rng.randf_range(-0.5,0.5)*cell_size
			match i%4:
				0: start = Vector2(-cell_size*0.5,along)
				1: start = Vector2(cell_size*0.5,along)
				2: start = Vector2(along,-cell_size*0.5)
				3: start = Vector2(along,cell_size*0.5)
		var upward:float = _rng.randf_range(35.0,60.0) if placed else _rng.randf_range(175.0,235.0) if emerging else _rng.randf_range(65.0,100.0)
		var flight:float = 2.0*upward/GRAVITY
		var outward:Vector2 = start.normalized()
		if outward.is_zero_approx(): outward = Vector2.RIGHT.rotated(_rng.randf_range(0,TAU))
		var color:Color = pixels.get_pixel(_rng.randi_range(0,pixels.get_width()-1),_rng.randi_range(0,pixels.get_height()-1))
		if color.a < 0.1: color = Color(0.34,0.49,0.16)
		color = color.lerp(Color.WHITE if i%3==0 else Color.BLACK,_rng.randf_range(0.02,0.16))
		color.a = 1.0
		var delay:float = _rng.randf_range(0.0,0.045)
		blocks.append({"start":start,"velocity":outward*_rng.randf_range(12.0,38.0),"upward":upward,"flight":flight,"delay":delay,"size":_rng.randf_range(0.8,1.8) if placed else _rng.randf_range(1.5,3.5),"color":color})
		duration = maxf(duration,delay+flight+0.4)
	queue_redraw()
func _process(delta:float) -> void:
	if not is_instance_valid(actor) or actor.health <= 0:
		queue_free()
		return
	if not actor.is_combat_runtime_active(): return
	elapsed += maxf(delta,0.0)
	queue_redraw()
	if elapsed >= duration: queue_free()
func block_pose(block:Dictionary,at_time:float) -> Dictionary:
	var age:float = maxf(0.0,at_time-float(block.delay))
	var flight:float = float(block.flight)
	var air_time:float = minf(age,flight)
	var height:float = maxf(0.0,float(block.upward)*air_time-0.5*GRAVITY*air_time*air_time)
	var ground:Vector2 = block.start+block.velocity*(1.0-exp(-3.0*air_time))/3.0
	return {"point":ground+Vector2(0,-height),"alpha":clampf(1.0-(age-flight-0.18)/0.22,0.0,1.0)}
func _draw() -> void:
	for block:Dictionary in blocks:
		if elapsed < float(block.delay): continue
		var pose:Dictionary = block_pose(block,elapsed)
		var color:Color = block.color
		color.a *= float(pose.alpha)
		var size:float = float(block.size)
		draw_rect(Rect2(pose.point-Vector2.ONE*size*0.5,Vector2.ONE*size),color)
