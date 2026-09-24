extends Node2D
# 最后一层羊毛从放大后的原版身体纹理碎开；落地停留后独立淡出。
var TEX:Texture2D
const GRAVITY:float = 480.0 # 明显向下加速，避免草屑缓慢飘落。
const FADE_TIME:float = 0.35
var age:float = 0.0
var floor_y:float = 0.0
var leaf_samples:Array[Dictionary] = []
var parts:Array[Dictionary] = []
var rng:RandomNumberGenerator = RandomNumberGenerator.new()
func configure_from_wool(tuft:Sprite2D,ground:Vector2) -> void:
	TEX = tuft.texture
	var pixels:Image = TEX.get_image()
	var size:Vector2 = Vector2(pixels.get_size())
	for y:int in range(1,pixels.get_height()-2,2):
		for x:int in range(1,pixels.get_width()-2,2):
			if pixels.get_pixel(x,y).a < 0.9: continue
			var point:Vector2 = Vector2(x+0.5,y+0.5)-size*0.5
			if tuft.flip_h: point.x = -point.x
			leaf_samples.append({"origin":tuft.to_global(point)-ground,"source":Rect2(x-1,y-1,3,3)})

func _ready() -> void:
	add_to_group("BattleTransient")
	add_to_group("SheepWoolBreakFX")
	z_as_relative = false
	z_index = 110
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rng.randomize()
	for i:int in range(rng.randi_range(18,24)):
		var sample:Dictionary = leaf_samples[rng.randi_range(0,leaf_samples.size()-1)] if not leaf_samples.is_empty() else {"origin":Vector2(0,-6),"source":Rect2(5,8,3,3)}
		parts.append({"velocity":Vector2(rng.randf_range(-90.0,90.0),rng.randf_range(-115.0,-65.0)),"origin":sample.origin,"source":sample.source,"size":rng.randf_range(3.0,5.0),"ground_wait":rng.randf_range(0.9,1.6)})
	queue_redraw()
func landing_time(part:Dictionary) -> float:
	var velocity:Vector2 = part.velocity
	var origin:Vector2 = part.origin
	return (-velocity.y+sqrt(velocity.y*velocity.y+2.0*GRAVITY*maxf(floor_y-origin.y,0.0)))/GRAVITY
func particle_position(part:Dictionary,time:float) -> Vector2:
	var velocity:Vector2 = part.velocity
	var origin:Vector2 = part.origin
	var t:float = minf(maxf(time,0.0),landing_time(part))
	return Vector2(origin.x+velocity.x*t,minf(origin.y+velocity.y*t+0.5*GRAVITY*t*t,floor_y))
func particle_alpha(part:Dictionary,time:float) -> float:
	var fade_start:float = landing_time(part)+float(part.ground_wait)
	return 1.0-smoothstep(fade_start,fade_start+FADE_TIME,time)
func _process(delta:float) -> void:
	if Game.now_stop_state or get_tree().paused: return
	age += delta
	var alive:bool = false
	for part:Dictionary in parts:
		if particle_alpha(part,age) > 0.0: alive = true; break
	if not alive: queue_free(); return
	queue_redraw()
func _draw() -> void:
	for part:Dictionary in parts:
		var alpha:float = particle_alpha(part,age)
		if alpha <= 0.0: continue
		var point:Vector2 = particle_position(part,age)
		var size:float = part.size
		draw_texture_rect_region(TEX,Rect2(point-Vector2(size*0.5,size),Vector2(size,size)),part.source,Color(1,1,1,alpha))
