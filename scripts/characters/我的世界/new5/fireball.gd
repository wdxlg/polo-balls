extends "res://scripts/characters/我的世界/new5/base.gd"
const MC_ABILITIES=preload("res://scripts/effects/我的世界/mc_combat_abilities.gd")
const SMOKE_SCENE=preload("res://scenes/effects/我的世界/MC烟雾粒子.tscn")
const FX_CONTAINER=preload("res://scripts/effects/我的世界/mc_explosion.gd")
@export var smoke_interval:float=0.06
@export var smoke_spacing:float=8.0
@export var smoke_diameter:float=9.0
var boundary_passes_left:int=0
var _launch_origin:Vector2=Vector2.INF
var _launch_pending:bool=false
var _inside_boundary:bool=false
var _boundary_probe:=CircleShape2D.new()
var _smoke_wait:float=0.0
var _smoke_previous:Vector2
var _visual_rect:Rect2
@export var lifetime:float=5.0
@export var blast_radius:float=55.0
@export var damage_brake:float=5.0
@export var damage_impulse:float=5.0
var flight_velocity:Vector2=Vector2.RIGHT*185.0
var initial_team:String=""
var launch_owner_id:int=0
var neutral:bool=true
var reflected:bool=false
var exploded:bool=false
var _incoming_direction:Vector2=Vector2.LEFT
func _ready() -> void:
	set_meta("submission_allow_map_escape",true)
	neutral=true
	Team=""
	Master=null
	Master_name=""
	Type=Ball_Type.Creature
	super._ready()
	collision_layer=0
	collision_mask=0
	Can_Attack=false
	Can_Skill=false
	image.z_as_relative=false
	image.z_index=102
	health_bar.hide()
	_smoke_previous=global_position
	_boundary_probe.radius=0.025
	if not _launch_origin.is_finite(): _launch_origin=global_position
	boundary_passes_left=0 if map_contains(_launch_origin) else 1
	var used:Rect2i=image.texture.get_image().get_used_rect()
	_visual_rect=Rect2(image.get_rect().position+Vector2(used.position),Vector2(used.size))
func _is_character_ground_shadow_owner() -> bool: return false
func is_combat_targetable() -> bool: return health>0 and not exploded and not is_queued_for_deletion()
func can_receive_hit_from(incoming:hitbox) -> bool:
	var attacker:ball=_incoming_hit_attacker(incoming)
	if is_instance_valid(attacker): _incoming_direction=_attack_vector(attacker.global_position,attacker)
	return is_combat_targetable()
func _attack_vector(point:Vector2,source:Node) -> Vector2:
	if source is ball:
		if source.has_player_control_aim(): return source.player_control_aim_direction((global_position-point).normalized())
		if source.Type!=Ball_Type.Ball and source.velocity.length_squared()>0.001: return source.velocity.normalized()
	var offset:Vector2=global_position-point
	return offset.normalized() if offset.length_squared()>0.001 else -flight_velocity.normalized()
func receive_positional_damage(amount:float,point:Vector2,_ignore_block:bool=false,source:Node=null) -> bool:
	if amount<=0 or not is_combat_targetable(): return false
	_incoming_direction=_attack_vector(point,source)
	take_damage(amount,_ignore_block)
	return true
func take_damage(amount:float,_ignore_block:bool=false) -> void:
	if not is_multiplayer_authority() or amount<=0 or exploded: return
	var force:float=amount*damage_brake
	if not reflected:
		var old_speed:float=flight_velocity.length()
		if force<old_speed:
			flight_velocity=flight_velocity.normalized()*(old_speed-force)
		else:
			reflected=true
			Team=""
			Master=null
			Master_name=""
			flight_velocity=_incoming_direction*maxf(0,(force-old_speed)*damage_impulse/maxf(damage_brake,0.001))
	else:
		flight_velocity+=_incoming_direction*amount*damage_impulse
	flight_velocity=flight_velocity.limit_length(460.0)
	if reflected:
		# Every confirmed reflected launch gets ONE new boundary passage.
		boundary_passes_left=1
		_inside_boundary=false
		_launch_pending=false
func apply_knockback(_d:Vector2,_distance:float,_speed:float=700.0,_bounce:float=0.0,_stun:float=0.0,_options:Dictionary={}) -> Node:
	return null # Momentum is changed by confirmed damage, never by a duplicate hit knockback.
func move(_speed:float,_delta:float) -> void: pass
func step_mob(delta:float) -> void:
	if exploded: return
	if fully_outside_window():
		discard_outside()
		return
	if clock>=lifetime:
		explode()
		return
	# Sweep the mouth offset too: a 30-unit muzzle offset must not teleport
	# an inside shot through a wall or grant an outside shot a second entry.
	var departing:bool=_launch_pending and not reflected and flight_velocity.dot(global_position-_launch_origin)>0.0
	var start:Vector2=_launch_origin if _launch_pending else global_position
	_launch_pending=false
	var end:Vector2=global_position+flight_velocity*delta
	if get_tree().has_group("MinecraftAllay") and load("res://scripts/characters/我的世界/allay/capture.gd").sweep(self,start,end): return
	if get_tree().has_group("MinecraftWoolSheep") and load("res://scripts/characters/我的世界/new6/wool_projectile.gd").sweep(self,start,end): return
	var obstacle:Dictionary=trace_flight(start,end)
	var best:float=start.distance_to(obstacle.position) if not obstacle.is_empty() else INF
	var contact:Vector2=obstacle.get("position",end)
	var hit_any:bool=not obstacle.is_empty()
	for target:Node in get_tree().get_nodes_in_group("Ball"):
		if target.get_instance_id()==launch_owner_id and departing: continue # Only the outward muzzle sweep; never an explosion exemption.
		if not U.enemy(self,target,true): continue
		if target.has_method("is_builder_wall") and target.is_builder_wall():
			if reflected: continue
		var closest:Vector2=Geometry2D.get_closest_point_to_segment(ball.body_point_seg(target,start,end),start,end)
		if closest.distance_to(ball.body_point(target,closest))>U.radius(target)+5.0: continue
		var d:float=start.distance_to(closest)
		if d<best:
			if target.has_method("try_full_projectile_dodge") and bool(target.call("try_full_projectile_dodge",self)): continue
			best=d
			contact=closest
			hit_any=true
	global_position=contact if hit_any else end
	velocity=flight_velocity
	if hit_any: explode()
	elif fully_outside_window(): discard_outside()
func explode() -> void:
	if exploded or not is_multiplayer_authority(): return
	exploded=true
	for target:Node in get_tree().get_nodes_in_group("Ball"):
		if not U.enemy(self,target,true): continue
		var offset:Vector2=ball.body_point(target,global_position)-global_position
		if offset.length()>blast_radius+U.radius(target): continue
		if not U.trace(self,global_position,target.global_position,true,reflected).is_empty(): continue
		# Neutral from launch: the caster and teammates can always take blast damage.
		if U.damage(self,target,Damage,global_position,true):
			target.apply_knockback(offset.normalized(),40.0,300.0,0,0,{"source":self})
	var updates:Array=MC_ABILITIES.obstacle_blast(self,global_position,blast_radius)
	if not updates.is_empty():
		if multiplayer.has_multiplayer_peer(): _obstacle_damage.rpc(updates)
		_obstacle_damage(updates)
	if multiplayer.has_multiplayer_peer(): _blast_visual.rpc(global_position)
	else: _blast_visual(global_position)
	queue_free()
@rpc("authority","call_local","reliable")
func _blast_visual(point:Vector2) -> void:
	var effect:Node2D=preload("res://scripts/characters/我的世界/new5/blast.gd").new()
	effect.position=point
	effect.radius=blast_radius
	get_tree().current_scene.add_child(effect)
func visual_mob() -> void:
	image.rotation+=0.015
	image.modulate=Color(1.0,0.82,0.6) if neutral else Color.WHITE
func visual_state() -> Dictionary: return {"time":clock,"neutral":true,"reflected":reflected,"flight":flight_velocity,"boundary_passes":boundary_passes_left}
func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	neutral=true
	Team=""
	Master=null
	Master_name=""
	reflected=bool(data.get("reflected",false))
	flight_velocity=data.get("flight",Vector2.ZERO)
	boundary_passes_left=int(data.get("boundary_passes",1))

func boundary_at(point:Vector2) -> bool:
	var query:=PhysicsShapeQueryParameters2D.new()
	query.shape=_boundary_probe
	query.transform=Transform2D(0.0,point)
	query.collision_mask=1
	query.collide_with_areas=false
	query.exclude=[get_rid()]
	for hit:Dictionary in get_world_2d().direct_space_state.intersect_shape(query,32):
		hit["position"]=point
		if U.boundary_hit(self,hit): return true
	return false
func trace_flight(start:Vector2,end:Vector2) -> Dictionary:
	if start.distance_squared_to(end)<0.000001: return {}
	var direction:Vector2=(end-start).normalized()
	var cursor:Vector2=start
	var exclusions:Array[RID]=[get_rid()]
	if _inside_boundary and not boundary_at(start): _inside_boundary=false
	for iteration:int in range(4096):
		if (end-cursor).dot(direction)<=0.0001:
			_inside_boundary=boundary_at(end)
			return {}
		var query:=PhysicsRayQueryParameters2D.create(cursor,end,1,exclusions)
		query.collide_with_areas=false
		query.hit_from_inside=true
		var hit:Dictionary=get_world_2d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			_inside_boundary=false
			return {}
		if U.boundary_hit(self,hit):
			# A gap before this contact means this is a NEW crossing, even on
			# the same TileMap RID. Do not exclude an entire map collision body.
			if cursor.distance_squared_to(hit.position)>0.26: _inside_boundary=false
			if not _inside_boundary:
				if boundary_passes_left<=0: return hit
				boundary_passes_left-=1
				_inside_boundary=true
			cursor=hit.position+direction*0.5
			if not boundary_at(cursor): _inside_boundary=false
			continue
		# Preserve the prior rule for INTERNAL walls after neutralization;
		# boundary contacts above always consume the finite passage budget.
		if reflected and U.wall_node(hit.collider):
			_inside_boundary=false
			cursor=hit.position+direction*0.5
			continue
		return hit
	return {"position":cursor}
func fully_outside_window() -> bool:
	if not is_instance_valid(image) or _visual_rect.size==Vector2.ZERO: return false
	var transform:Transform2D=image.get_global_transform_with_canvas()
	var bounds:=Rect2(transform*_visual_rect.position,Vector2.ZERO)
	for point:Vector2 in [_visual_rect.end,Vector2(_visual_rect.position.x,_visual_rect.end.y),Vector2(_visual_rect.end.x,_visual_rect.position.y)]:
		bounds=bounds.expand(transform*point)
	return not get_viewport_rect().intersects(bounds,true)
func discard_outside() -> void:
	if not is_multiplayer_authority() or exploded: return
	exploded=true
	queue_free() # No invisible blast and no damage when leaving the window.
func _process(delta:float) -> void:
	super._process(delta)
	if not exploded and is_combat_runtime_active() and not fully_outside_window(): update_smoke(delta)
func update_smoke(delta:float) -> void:
	_smoke_wait-=maxf(delta,0)
	var distance:float=_smoke_previous.distance_to(global_position)
	var count:int=int(distance/maxf(smoke_spacing,2.0))
	if _smoke_wait<=0: count=maxi(count,1)
	if count<=0: return
	count=mini(count,6)
	var container:Node2D=FX_CONTAINER.runtime_container(self)
	for i:int in range(count):
		var point:Vector2=_smoke_previous.lerp(global_position,float(i+1)/count)-flight_velocity.normalized()*3.0
		point+=Vector2(_voice_rng.randf_range(-3,3),_voice_rng.randf_range(-3,3))
		var smoke:Node2D=SMOKE_SCENE.instantiate()
		smoke.add_to_group("BattleTransient")
		smoke.add_to_group("MCGhastFireSmoke")
		container.add_child(smoke)
		smoke.configure(point,smoke_diameter*_voice_rng.randf_range(0.82,1.18),_voice_rng.randf_range(28,40),_voice_rng.randf_range(4,9),101)
	_smoke_previous=global_position
	_smoke_wait=maxf(smoke_interval,0.02)

func configure_launch(origin:Vector2) -> void:
	_launch_origin=origin
	_launch_pending=true
func map_contains(point:Vector2) -> bool:
	var world:Node=get_tree().current_scene
	if world==null or not world.has_method("map_island_rects"): return true
	var map:Node=world.call("_current_map_node")
	if map==null: return true
	for rect:Rect2 in world.map_island_rects(map):
		if rect.has_point(point): return true
	return false

@rpc("authority","call_remote","reliable")
func _obstacle_damage(updates:Array) -> void:
	MC_ABILITIES.apply_obstacle_updates(self,updates)
