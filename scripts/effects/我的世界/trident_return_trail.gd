extends Node2D
# Dense, bounded projectile afterimages, emitted only after recall picks up speed.
const LIFETIME:float=0.24
const INTERVAL:float=0.008
const LIMIT:int=24
const MIN_SPEED:float=220.0
var samples:Array[Dictionary]=[]
var sample_left:float=0.0
var texture:Texture2D
var draw_size:float=16.0
var _previous_point:Vector2
var _previous_angle:float=0.0
var _initialized:bool=false
func _ready() -> void:
	set_as_top_level(true)
	global_transform=Transform2D.IDENTITY
	z_as_relative=false
	z_index=2
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	add_to_group("MCTridentReturnTrail")
func advance(delta:float,spear:Node2D) -> void:
	if not is_instance_valid(spear.unit) or spear.unit.health<=0:
		samples.clear();queue_redraw();return
	if Game.now_stop_state or get_tree().paused or not spear.unit.is_combat_runtime_active(): return
	var dt:float=maxf(delta,0.0)
	for i:int in range(samples.size()-1,-1,-1):
		samples[i].age+=dt
		if samples[i].age>=LIFETIME: samples.remove_at(i)
	if not _initialized:
		_previous_point=spear.global_position;_previous_angle=spear.rotation;_initialized=true
	if spear.flight_state==spear.Phase.RETURNING and spear.return_speed_at(spear._return_elapsed)>=MIN_SPEED:
		sample_left+=dt
		var count:int=int(floor(sample_left/INTERVAL))
		sample_left=fmod(sample_left,INTERVAL)
		texture=spear.TEXTURE;draw_size=spear.DRAW_SIZE
		# Interpolate samples within a frame: denser trails without extra nodes/timers.
		for index:int in range(maxi(0,count-LIMIT),count):
			var age:float=sample_left+float(count-1-index)*INTERVAL
			if age>=LIFETIME or spear.return_speed_at(maxf(spear._return_elapsed-age,0.0))<MIN_SPEED: continue
			var fraction:float=clampf(1.0-age/maxf(dt,0.00001),0.0,1.0)
			samples.append({"point":_previous_point.lerp(spear.global_position,fraction),"angle":lerpf(_previous_angle,spear.rotation,fraction),"scale":spear.global_scale,"age":age})
			if samples.size()>LIMIT: samples.pop_front()
	else: sample_left=0.0
	_previous_point=spear.global_position;_previous_angle=spear.rotation
	visible=not samples.is_empty();queue_redraw()
func _draw() -> void:
	if texture==null: return
	for sample:Dictionary in samples:
		var fade:float=pow(1.0-clampf(float(sample.age)/LIFETIME,0.0,1.0),1.5)
		draw_set_transform(sample.point,sample.angle,sample.scale)
		draw_texture_rect(texture,Rect2(Vector2.ONE*(-draw_size*0.5),Vector2.ONE*draw_size),false,Color(0.7,0.92,1.0,0.42*fade))
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
