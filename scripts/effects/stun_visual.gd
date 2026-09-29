extends Node2D
class_name StunVisual
## MC swirl atlas + irregular pixel arcs. Orbital depth splits every arc at
## the character plane, not just entire lines, so both halves occlude correctly.
const ATLAS=preload("res://Images/Status/Stun/mc_status_particles.png")
const LAYER=preload("res://scripts/effects/stun_pixel_layer.gd")
var target:Node2D
var follow_offset:Vector2=Vector2(0,-20)
var visual_scale:float=0.02
var draw_z_index:int=1000 # Legacy setup parameter; depth is now relative to body art.
var back_layer:Node2D
var front_layer:Node2D
var age:float=0.0
var fading_out:bool=false
var fade_age:float=0.0
const FADE_DURATION:float=0.12
var strands:Array[Dictionary]=[]
var body:Sprite2D
var _ink:Rect2=Rect2(0,0,1,1)
var _body_items:Array[CanvasItem]=[]
func setup(p_target:Node2D,p_offset:Vector2=Vector2(0,-20),p_scale:float=0.02,p_z_index:int=1000) -> void:
	target=p_target
	follow_offset=p_offset
	visual_scale=maxf(p_scale,0.001)
	draw_z_index=p_z_index
	if is_node_ready():
		_capture_body()
		_follow_target()
func _ready() -> void:
	top_level=true
	z_as_relative=false
	z_index=0
	process_mode=Node.PROCESS_MODE_ALWAYS
	process_priority=100
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	add_to_group("MCPixelStunFX")
	back_layer=LAYER.new()
	front_layer=LAYER.new()
	back_layer.name="BackOrbit"
	front_layer.name="FrontOrbit"
	for layer:Node2D in [back_layer,front_layer]:
		layer.z_as_relative=false
		layer.atlas=ATLAS
		add_child(layer)
	var rng:=RandomNumberGenerator.new()
	rng.seed=int(target.get_instance_id()) if is_instance_valid(target) else int(get_instance_id())
	for pair:int in range(3):
		var angle:float=pair*2.1+rng.randf_range(-0.75,0.75)
		var speed:float=rng.randf_range(2.0,2.4)
		var radius:float=rng.randf_range(19.0,21.3)
		for tier:int in range(2):
			strands.append({"angle":angle+rng.randf_range(-0.275,0.275),"speed":speed,"radius":radius+rng.randf_range(0,1.3),"height":rng.randf_range(4.2,5.7),"offset":(-1.0 if tier==0 else 1.0)*rng.randf_range(1.5,2.7),"short":rng.randf_range(0.15,0.35),"long":rng.randf_range(0.65,1.4),"rate":rng.randf_range(0.75,1.6),"phase":rng.randf_range(0,TAU)})
	_capture_body()
	_follow_target()
	_rebuild_orbit()
func _capture_body() -> void:
	_body_items.clear()
	body=target.get_node_or_null("Graphics/Image") as Sprite2D if is_instance_valid(target) else null
	if not is_instance_valid(body): return
	_collect_body(target.get_node_or_null("Graphics"))
	_collect_body(target.get_node_or_null("PistonAssembly"))
	# One alpha-bounds read per stun, not GPU texture readbacks each frame.
	if body.texture!=null:
		var image:Image=body.texture.get_image()
		if image!=null and not image.is_empty():
			if body.region_enabled: image=image.get_region(body.region_rect)
			elif body.hframes>1 or body.vframes>1:
				var frame_size:Vector2i=image.get_size()/Vector2i(body.hframes,body.vframes)
				image=image.get_region(Rect2i(body.frame_coords*frame_size,frame_size))
			var used:Rect2i=image.get_used_rect()
			if used.has_area(): _ink=Rect2(Vector2(used.position)/Vector2(image.get_size()),Vector2(used.size)/Vector2(image.get_size()))
func _collect_body(node:Node) -> void:
	if node==null: return
	if node is Sprite2D or node is AnimatedSprite2D or node is Polygon2D: _body_items.append(node)
	for child:Node in node.get_children(): _collect_body(child)
static func effective_z(item:CanvasItem) -> int:
	var result:int=item.z_index
	while item.z_as_relative and item.get_parent() is CanvasItem:
		item=item.get_parent()
		result+=item.z_index
	return result
func _follow_target() -> void:
	if not is_instance_valid(target): return
	var low:int=effective_z(target)
	var high:int=low
	if is_instance_valid(body):
		low=effective_z(body)
		high=low
	for item:CanvasItem in _body_items:
		if is_instance_valid(item) and item.is_visible_in_tree():
			low=mini(low,effective_z(item))
			high=maxi(high,effective_z(item))
	back_layer.z_index=clampi(low-1,-4096,4096)
	front_layer.z_index=clampi(high+1,-4096,4096)
	global_rotation=0.0
	var factor:float=clampf(visual_scale/0.02,0.85,1.5)
	if is_instance_valid(body):
		var rect:Rect2=body.get_rect()
		var ink:Rect2=Rect2(rect.position+rect.size*_ink.position,rect.size*_ink.size)
		if body.flip_h: ink.position.x=rect.position.x+rect.size.x-(ink.end.x-rect.position.x)
		if body.flip_v: ink.position.y=rect.position.y+rect.size.y-(ink.end.y-rect.position.y)
		var bounds:Rect2=Rect2(body.to_global(ink.position),Vector2.ZERO)
		for point:Vector2 in [ink.end,Vector2(ink.end.x,ink.position.y),Vector2(ink.position.x,ink.end.y)]: bounds=bounds.expand(body.to_global(point))
		factor*=clampf(bounds.size.x/45.0,0.85,1.6)
		# Anchor at the visible head, not the old icon offset. ball.tscn uses -20 / 0.02.
		# Keep a shallow overlap for the front/rear occlusion instead of sinking into the body.
		global_position=Vector2(body.global_position.x,bounds.position.y+minf(bounds.size.y*0.08,4.0))+Vector2(follow_offset.x,clampf(follow_offset.y+20.0,-8.0,0.0))
	else: global_position=target.global_position+follow_offset
	global_scale=Vector2.ONE*factor*0.75
func _process(delta:float) -> void:
	if not is_instance_valid(target) or target.is_queued_for_deletion() or (target.get("health")!=null and float(target.get("health"))<=0):
		hide()
		queue_free()
		return
	visible=target.is_visible_in_tree()
	_follow_target()
	if fading_out:
		fade_age+=maxf(delta,0.0)
		modulate.a=1.0-smoothstep(0.0,FADE_DURATION,fade_age)
		age+=maxf(delta,0.0)
		_rebuild_orbit()
		if fade_age>=FADE_DURATION: queue_free()
		return
	if Game.now_stop_state or get_tree().paused: return
	if target.has_method("is_combat_runtime_active") and not target.is_combat_runtime_active(): return
	age+=maxf(delta,0.0)
	_rebuild_orbit()
func _rebuild_orbit() -> void:
	back_layer.pixels.clear()
	front_layer.pixels.clear()
	back_layer.glyphs.clear()
	front_layer.glyphs.clear()
	for strand:Dictionary in strands:
		var length:float=lerpf(strand.short,strand.long,0.5+0.5*sin(age*strand.rate+strand.phase))
		var center:float=age*strand.speed+strand.angle+0.1*sin(age*0.7+strand.phase)
		var radius:float=strand.radius+0.45*sin(age*0.8+strand.phase)
		for j:int in range(81):
			var u:float=float(j)/80.0
			var angle:float=center+(u-0.5)*length
			var depth:float=sin(angle)
			var point:Vector2=Vector2(cos(angle)*radius,strand.offset+depth*strand.height).round()
			var alpha:float=(0.50+0.42*sin(PI*u))*(0.94+0.06*depth)
			var layer:Node2D=front_layer if depth>=0 else back_layer
			layer.pixels[point]=maxf(float(layer.pixels.get(point,0.0)),alpha)
	for i:int in range(4):
		var life:float=fposmod(age/1.5+float(i)/4.0,1.0)
		var angle:float=age*2.3+i*PI/2.0
		var layer:Node2D=front_layer if sin(angle)>=0 else back_layer
		layer.glyphs.append({"point":(Vector2(cos(angle)*24,sin(angle)*5-life*8)-Vector2(5,5)).round(),"frame":1+mini(6,int(life*7)),"alpha":minf(life/0.08,1.0)*clampf((1.0-life)/0.35,0.0,1.0)*0.98})
	back_layer.queue_redraw()
	front_layer.queue_redraw()

func begin_fade_out() -> void:
	if fading_out: return
	fading_out=true
	fade_age=0.0
