extends Node2D
## Native sonic-ring particles with swept hit geometry; the return echo must physically reach its owner.
const SONIC:Texture2D = preload("res://Images/characters/我的世界/frontier/sonic.png")
const U = preload("res://scripts/characters/我的世界/new5/utils.gd")
const SONIC_SCALE:float = 1.7
var actor:Node2D
var kind:String = "probe"
var heading:Vector2 = Vector2.RIGHT
var origin:Vector2
var distance:float = 0.0
var reach:float = 300.0
var speed:float = 320.0
var probe_initial_speed:float = 320.0
var probe_final_speed:float = 100.0
var flight_lifetime:float = 2.0
var _ground_shadow:Sprite2D
var damage:float = 0.0
var wave_id:int = 0
var epoch:int = 0
var token:String = ""
var age:float = 0.0
var hit_ids:Dictionary = {}
var trail:Array[Vector2] = []
func _ready() -> void:
	z_as_relative = false
	z_index = 8
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_to_group("BattleTransient")
	add_to_group("MCWardenWave")
func setup(owner_node:Node2D,mode:String,point:Vector2,axis:Vector2,serial:int,ritual:int,echo_token:String) -> void:
	actor = owner_node
	kind = mode
	global_position = point
	origin = point
	global_scale = Vector2.ONE
	heading = axis.normalized()
	wave_id = serial
	epoch = ritual
	token = echo_token
	reach = actor.sonic_range if kind=="sonic" else actor.probe_range
	speed = 900.0 if kind=="sonic" else 720.0 if kind=="return" else maxf(actor.probe_speed,1.0)
	probe_initial_speed=speed
	probe_final_speed=clampf(actor.probe_end_speed,1.0,speed)
	flight_lifetime=maxf(2.0,reach/maxf(speed,1.0)+0.5)
	if kind=="probe" and probe_initial_speed>probe_final_speed:
		flight_lifetime=maxf(2.0,reach*log(probe_initial_speed/probe_final_speed)/(probe_initial_speed-probe_final_speed)+0.5)
	damage = actor.attack_damage(3.0 if kind=="sonic" else 0.35)
	if kind=="probe":
		_ground_shadow=Sprite2D.new()
		var texture:=AtlasTexture.new()
		texture.atlas=SONIC
		var cell:int=mini(SONIC.get_width(),SONIC.get_height())
		texture.region=Rect2(0,cell*8 if SONIC.get_height()>=cell*16 else 0,cell,cell)
		_ground_shadow.texture=texture
		_ground_shadow.modulate=Color(0,0,0,0.22)
		_ground_shadow.z_as_relative=false
		_ground_shadow.z_index=-3
		add_child(_ground_shadow)
		_update_shadow()
func _physics_process(delta:float) -> void: advance(delta)
func advance(delta:float) -> void:
	if not is_instance_valid(actor) or actor.health<=0 or actor.is_queued_for_deletion(): queue_free(); return
	if not actor.is_combat_runtime_active() or Game.now_stop_state or get_tree().paused: return
	if actor.is_multiplayer_authority() and not (actor.sonic_can_continue() if kind=="sonic" else actor.can_act()): queue_free(); return
	age += delta
	if age>flight_lifetime: queue_free(); return
	var from:Vector2 = global_position
	if kind=="return":
		if actor.form!=actor.Form.DORMANT or actor.ritual_epoch!=epoch: queue_free(); return
		global_position = global_position.move_toward(actor.global_position,speed*delta)
		if actor.is_multiplayer_authority() and global_position.distance_to(actor.global_position)<=6.0:
			actor.receive_echo(epoch,token)
			queue_free()
	else:
		var step_distance:float=speed*delta
		if kind=="probe" and probe_initial_speed>probe_final_speed:
			# Exact integral of v = initial - slope * distance: smooth, frame-rate-independent slowing.
			var slope:float=(probe_initial_speed-probe_final_speed)/maxf(reach,1.0)
			step_distance=speed*(1.0-exp(-slope*delta))/slope
		var travel:float = minf(step_distance,maxf(0.0,reach-distance))
		global_position += heading*travel
		distance += travel
		if kind=="probe": speed=lerpf(probe_initial_speed,probe_final_speed,clampf(distance/maxf(reach,1.0),0.0,1.0))
		if actor.is_multiplayer_authority(): _sweep(from,global_position)
		if distance>=reach: queue_free()
	_update_shadow()
	trail.append(global_position)
	if trail.size()>10: trail.pop_front()
	queue_redraw()
func _sweep(from:Vector2,to:Vector2) -> void:
	var width:float = 11.0*SONIC_SCALE if kind=="sonic" else probe_diameter()*0.5
	var shape:=RectangleShape2D.new()
	var depth:float=width if kind=="sonic" else width*0.52+2.0
	shape.size=Vector2(from.distance_to(to)+depth*2.0,width*2.0)
	var query:=PhysicsShapeQueryParameters2D.new()
	query.shape=shape
	query.transform=Transform2D(heading.angle(),(from+to)*0.5+(Vector2(0,-6) if kind=="probe" else Vector2.ZERO))
	query.collision_mask=2
	query.collide_with_bodies=false
	query.collide_with_areas=true
	for entry:Dictionary in get_world_2d().direct_space_state.intersect_shape(query,256):
		var area:Variant=entry.get("collider")
		if not area is hurtbox: continue
		var target:ball=area.get_parent() as ball
		if not U.enemy(actor,target): continue
		var id:int = target.get_instance_id()
		if hit_ids.has(id): continue
		hit_ids[id] = true
		var point:Vector2 = target.global_position
		var accepted:bool = actor.damage_with_sound(target,damage,Geometry2D.get_closest_point_to_segment(point,from,to),true)
		# A real enemy contact produces an echo even when armor absorbs all damage.
		if kind=="probe": actor.probe_contact(epoch,str(wave_id)+":"+str(id),point)
		if not accepted: continue
		if is_instance_valid(target) and target.health>0 and target.can_receive_negative_effects():
			target.apply_knockback(heading,110.0 if kind=="sonic" else 24.0,480.0 if kind=="sonic" else 260.0,0.0,0.0,{"lock_control":false,"source":actor,"stop_on_character":false,"collision_damage":0.0})
func probe_diameter() -> float:
	return lerpf(15.0,57.0,clampf(distance/maxf(reach,1.0),0.0,1.0))
func _update_shadow() -> void:
	if not is_instance_valid(_ground_shadow): return
	var size:float=probe_diameter()
	_ground_shadow.position=Vector2(0,4)
	_ground_shadow.scale=Vector2(size*0.8,size*0.22)/_ground_shadow.texture.get_size()
func _draw_probe() -> void:
	# A single travelling ring with a short rim, not a string of independent ring sprites.
	# Its ring plane is perpendicular to travel; perspective, rim shading and a ground shadow give depth.
	var cell:int=mini(SONIC.get_width(),SONIC.get_height())
	var frame:int=11 if SONIC.get_height()>=cell*16 else 0
	var region:=Rect2(0,frame*cell,cell,cell)
	var size:float=probe_diameter()
	# 残影：沿已经飞过的轨迹留下几个越来越淡、略小的同款圆环
	var ghosts:int=mini(4,trail.size()/2)
	for g:int in range(ghosts,0,-1):
		var index:int=trail.size()-1-g*2
		if index<0: continue
		var fade:float=(1.0-float(g)/float(ghosts+1))*0.55
		var ghost_size:float=size*(1.0-0.07*float(g))
		draw_set_transform(to_local(trail[index])+Vector2(0,-6),heading.angle(),Vector2(0.52,1.0))
		draw_texture_rect_region(SONIC,Rect2(-Vector2.ONE*ghost_size*0.5,Vector2.ONE*ghost_size),region,Color(0.8,1.0,1.0,fade))
	draw_set_transform(Vector2(0,-6),heading.angle(),Vector2(0.52,1.0))
	for layer:int in range(2,-1,-1):
		var shade:float=1.0-float(layer)*0.24
		var offset:Vector2=Vector2(-float(layer)*2.0,0)
		draw_texture_rect_region(SONIC,Rect2(offset-Vector2.ONE*size*0.5,Vector2.ONE*size),region,Color(shade,shade,shade,1.0))
	draw_set_transform(Vector2.ZERO)
func _draw() -> void:
	if kind=="probe":
		_draw_probe()
		return
	var cell:int = mini(SONIC.get_width(),SONIC.get_height())
	var columns:int = maxi(1,SONIC.get_width()/cell)
	var count:int = columns*maxi(1,SONIC.get_height()/cell)
	# Native strip: frames 0-7 are shrinking charge specks; 8-15 are the actual sonic rings.
	var first:int = 8 if count>=16 else 0
	var frame:int = first+mini(count-first-1,int(age*20.0))
	var region:=Rect2((frame%columns)*cell,(frame/columns)*cell,cell,cell)
	var length:float = minf(distance,110.0 if kind=="sonic" else 64.0)
	var number:int = maxi(1,int(length/14.0)) if kind!="return" else trail.size()
	for i:int in range(maxi(number,1)):
		var point:Vector2 = global_position-heading*float(i)*14.0
		if kind=="return" and not trail.is_empty(): point=trail[maxi(0,trail.size()-1-i)]
		var fade:float = 1.0-float(i)/float(maxi(number,1))*0.75
		var size:float = (28.0*SONIC_SCALE if kind=="sonic" else 18.0 if kind=="probe" else 12.0)*fade
		draw_texture_rect_region(SONIC,Rect2(to_local(point)-Vector2.ONE*size*0.5,Vector2.ONE*size),region,Color(0.55,1,1,fade) if kind=="return" else Color(1,1,1,fade))
