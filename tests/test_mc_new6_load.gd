extends "res://tests/test_mc_bat.gd"
func _mk_enemy(point:Vector2) -> Node2D:
	var enemy:Node2D=spawn("res://scenes/ball.tscn",point,"Team1")
	enemy.state_machine.set_physics_process(false)
	enemy.Has_Collision_Damage=false
	enemy.self_hitbox.monitoring=false
	enemy.Max_health=10000
	enemy.default_properties.Max_health=10000
	enemy.health=10000
	return enemy
func _heard(event:String) -> bool:
	for sound:Node in get_nodes_in_group("MCNativeSFX"):
		if sound.get_meta("mc_sound_event","")==event: return true
	return false
func _mk_wall(point:Vector2) -> StaticBody2D:
	var wall:=StaticBody2D.new()
	wall.collision_layer=1
	wall.collision_mask=0
	var shape:=CollisionShape2D.new()
	var rect:=RectangleShape2D.new()
	rect.size=Vector2(30,300)
	shape.shape=rect
	wall.add_child(shape)
	world.add_child(wall)
	wall.global_position=point
	return wall
func _falls() -> Array[Node]:
	var out:Array[Node]=[]
	for child:Node in world.get_children():
		if child.has_method("configure") and str(child.get_script().resource_path).ends_with("heavenfall_arrow.gd"): out.append(child)
	return out
func _bolts() -> Array[Node]:
	var out:Array[Node]=[]
	for child:Node in world.get_children():
		if child.has_method("configure") and str(child.get_script().resource_path).ends_with("heavenfall_bolt.gd"): out.append(child)
	return out
func _tears() -> Array[Node]:
	var out:Array[Node]=[]
	for child:Node in world.get_children():
		if child.has_method("add_sample") and str(child.get_script().resource_path).ends_with("heavenfall_pierce_rift.gd"): out.append(child)
	return out
func _rifts() -> Array[Node]:
	var out:Array[Node]=[]
	for child:Node in world.get_children():
		if child.has_method("configure") and str(child.get_script().resource_path).ends_with("heavenfall_rift.gd"): out.append(child)
	return out
func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	saved_stop=game.now_stop_state
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(90.0).timeout.connect(func(): finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	var center:Vector2=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	# --- resource load smoke ---
	for path:String in ["res://scenes/characters/我的世界/弓.tscn","res://scenes/characters/我的世界/天堂陨落长弓.tscn","res://scenes/characters/我的世界/羊.tscn","res://scenes/characters/我的世界/木船.tscn","res://scenes/shooter/我的世界/天陨箭.tscn","res://scenes/shooter/我的世界/天陨箭矢.tscn","res://scenes/shooter/我的世界/天陨裂隙.tscn"]:
		check(load(path)!=null,"loads "+path.get_file())
	for path:String in ["res://Images/characters/我的世界/new6/sheep_frames.tres","res://Images/characters/我的世界/new6/sheep_frames.png","res://Images/characters/我的世界/new6/boat_frames.tres","res://Images/characters/我的世界/new6/boat_frames.png","res://Images/characters/我的世界/new6/sheep_preview.png","res://Images/characters/我的世界/new6/boat_preview.png","res://Images/characters/我的世界/new6/av_bow_idle.png","res://Images/characters/我的世界/new6/av_bow_pull0.png","res://Images/characters/我的世界/new6/av_bow_pull1.png","res://Images/characters/我的世界/new6/av_bow_pull2.png","res://Images/characters/我的世界/new6/av_bow_preview.png","res://Images/characters/我的世界/new6/heaven_swift.png","res://Images/characters/我的世界/new6/heaven_rain.png","res://Images/characters/默认/盔甲架/Bow.png","res://Images/characters/默认/盔甲架/Bow_Pulling_2.png","res://audio/characters/我的世界/new6/sheep_say1.ogg","res://audio/characters/我的世界/new6/wood_dig1.ogg"]:
		check(load(path)!=null,"loads "+path.get_file())
	# --- SpriteFrames structure: baked clips ---
	var sheep_frames:SpriteFrames=load("res://Images/characters/我的世界/new6/sheep_frames.tres")
	var sheep_names:Array[StringName]=[]
	for n:StringName in sheep_frames.get_animation_names(): sheep_names.append(n)
	# Compare textual names, not StringName intern/order-dependent identities.
	sheep_names.sort_custom(func(a:StringName,b:StringName) -> bool: return String(a)<String(b))
	check(sheep_names==[&"sheared_idle",&"sheared_walk",&"wool_idle",&"wool_walk"],"sheep atlas has four baked clips")
	var sheep_eight:bool=true
	for n:StringName in sheep_names:
		if sheep_frames.get_frame_count(n)!=8: sheep_eight=false
	check(sheep_eight,"every sheep clip has eight frames")
	var boat_frames:SpriteFrames=load("res://Images/characters/我的世界/new6/boat_frames.tres")
	check(boat_frames.has_animation(&"idle") and boat_frames.has_animation(&"row"),"boat atlas has idle and row clips")
	check(boat_frames.get_frame_count(&"idle")==8 and boat_frames.get_frame_count(&"row")==8,"both boat clips have eight frames")
	# --- bow: charge stages, full volley, close-range release ---
	var bow:Node2D=spawn("res://scenes/characters/我的世界/弓.tscn",center)
	bow.Can_Attack=true
	bow.state_machine.set_physics_process(false)
	var enemy:Node2D=_mk_enemy(center+Vector2(150,0))
	await physics_frame
	await process_frame
	bow.visual_mob()
	check(bow.image.texture==bow.TEX_IDLE,"bow starts undrawn")
	for i:int in range(20): bow.step_mob(0.016)
	bow.visual_mob()
	check(bow.drawing>0.05 and bow.image.texture==bow.TEX_PULL0,"bow shows early pull while aiming")
	for i:int in range(85): bow.step_mob(0.016)
	check(get_nodes_in_group("MinecraftSkeletonArrow").is_empty() and bow.drawing>=bow.draw_time,"full draw holds the string instead of firing at once")
	for i:int in range(25): bow.step_mob(0.016)
	check(get_nodes_in_group("MinecraftSkeletonArrow").size()>=1,"bow fires an arrow after the final hold")
	check(_heard("entity.arrow.shoot"),"bow plays shoot sound")
	var full_arrow:Node=get_nodes_in_group("MinecraftSkeletonArrow")[0]
	var full_dmg:float=full_arrow._direct_damage
	var full_speed:float=full_arrow._speed
	var hp:float=enemy.health
	for i:int in range(80):
		full_arrow._physics_process(0.016)
		if enemy.health<hp: break
	check(enemy.health<hp,"bow arrow damages the enemy")
	full_arrow.queue_free()
	bow.queue_free()
	await process_frame
	var bow2:Node2D=spawn("res://scenes/characters/我的世界/弓.tscn",center)
	bow2.Can_Attack=true
	bow2.state_machine.set_physics_process(false)
	enemy.global_position=center+Vector2(60,0)
	await physics_frame
	await process_frame
	for i:int in range(12): bow2.step_mob(0.016)
	check(get_nodes_in_group("MinecraftSkeletonArrow").size()>=1,"close enemy triggers an early release")
	var part_arrow:Node=get_nodes_in_group("MinecraftSkeletonArrow")[0]
	check(full_dmg>part_arrow._direct_damage,"charge increases speed-based arrow damage")
	check(full_speed>part_arrow._speed,"longer charge launches a faster arrow")
	check(part_arrow.get("_new6_max_dist")==240.0,"bow arrows carry a range cap")
	part_arrow.set("_new6_travelled",29.0)
	part_arrow.set("_new6_max_dist",30.0)
	part_arrow._physics_process(0.016)
	check(part_arrow.is_queued_for_deletion(),"arrow expires at max range")
	part_arrow.queue_free()
	bow2.queue_free()
	enemy.queue_free()
	await process_frame
	# --- longbow: bolt flight, homing, bounce, rain ---
	var longbow:Node2D=spawn("res://scenes/characters/我的世界/天堂陨落长弓.tscn",center)
	longbow.Can_Attack=true
	longbow.state_machine.set_physics_process(false)
	enemy=_mk_enemy(center+Vector2(200,0))
	await physics_frame
	await process_frame
	check(longbow._atlas_idle.size()==9 and longbow._atlas_pull.size()==3,"avaritia strips split into nine cosmic frames")
	longbow.visual_mob()
	check(longbow.image.texture is AtlasTexture,"longbow draws animated avaritia frames")
	for i:int in range(40): longbow.step_mob(0.016)
	check(_bolts().size()==1,"full draw launches one heaven bolt")
	var bolt:Node=_bolts()[0]
	check(absf(bolt.global_position.distance_to(longbow.global_position)-longbow.muzzle_offset)<0.5,"bolt spawns at the muzzle")
	check(longbow.muzzle_offset<=16.0,"muzzle sits at the bow head")
	check(bolt.get_node("Sprite2D").texture==load("res://Images/characters/我的世界/new6/天陨箭_纯白.png"),"bolt now uses the pure-white arrow sprite")
	check(bolt.get_node("Sprite2D").scale.is_equal_approx(Vector2(0.016,0.016)) and is_equal_approx(bolt.get_node("Sprite2D").rotation,PI*0.25),"ordinary arrow keeps the skeleton arrow's size and tilt")
	var dir0:Vector2=bolt._dir
	bolt.global_position=center+Vector2(2000,0)
	bolt._speed=120.0
	enemy.global_position=bolt.global_position+dir0.rotated(deg_to_rad(25.0))*200.0
	await physics_frame
	var ang0:float=absf(dir0.angle_to(enemy.global_position-bolt.global_position))
	for i:int in range(3): bolt._physics_process(0.016)
	var ang1:float=absf(bolt._dir.angle_to(enemy.global_position-bolt.global_position))
	check(ang1<ang0-0.035,"bolt homes slightly toward enemies")
	bolt._travelled=0.0
	bolt._max_dist=0.5
	bolt._physics_process(0.016)
	check(bolt.is_queued_for_deletion(),"spent bolt expires")
	check(_falls().size()==7,"expired bolt summons its rain")
	check(_rifts().size()==1,"expired bolt tears a rift")
	for fall:Node in _falls(): fall.queue_free()
	for rift:Node in _rifts(): rift.queue_free()
	await process_frame
	longbow.spawn_heaven_rain(PackedVector2Array([enemy.global_position]),longbow.attack_damage(0.35),22.0,0.1)
	await process_frame
	check(_falls().size()==1,"rain arrows land where aimed")
	hp=enemy.health
	for fall:Node in _falls(): fall._physics_process(0.15)
	check(enemy.health<hp,"heavenfall impacts damage the enemy")
	check(bool(enemy.Buff_Dic.get(longbow.get_instance_id(),{}).has("天陨减速")),"heavenfall applies slow")
	for fall:Node in _falls(): fall.queue_free()
	# 落地箭现在会在落点留下小裂缝（RainCrack），一并清理，避免污染后续穿透断言。
	for tear:Node in _tears(): tear.queue_free()
	enemy.queue_free()
	await process_frame
	var corridor:Node=load("res://scenes/shooter/我的世界/天陨箭矢.tscn").instantiate()
	world.add_child(corridor)
	corridor.global_position=center+Vector2(40,0)
	corridor.call("configure",longbow,longbow.Team,Vector2.RIGHT,620.0,10.0,30.0,0.0,0.0,5000.0,3,60.0,4.0,22.0,0.38)
	var wall_a:StaticBody2D=_mk_wall(center+Vector2(90,0))
	var wall_b:StaticBody2D=_mk_wall(center+Vector2(190,0))
	await physics_frame
	var heading:Vector2=corridor._dir
	for i:int in range(8): corridor._physics_process(0.016)
	check(corridor._dir.is_equal_approx(heading) and not corridor.is_queued_for_deletion(),"first obstacle is pierced instead of bounced")
	check(corridor.has_pierced() and corridor.global_position.x>center.x+90.0,"the arrow keeps going through the wall")
	check(_tears().size()==1 and _tears()[0].sample_count()>=2,"piercing leaves a rift that already grew along the way")
	for i:int in range(40):
		corridor._physics_process(0.016)
		if corridor.is_queued_for_deletion(): break
	check(corridor.is_queued_for_deletion() and _falls().size()==3,"a second obstacle still stops the arrow into rain")
	for fall:Node in _falls(): fall.queue_free()
	for rift:Node in _rifts(): rift.queue_free()
	for tear:Node in _tears(): tear.queue_free()
	wall_a.queue_free()
	wall_b.queue_free()
	enemy=_mk_enemy(center+Vector2(190,0))
	await physics_frame
	var direct:Node=load("res://scenes/shooter/我的世界/天陨箭矢.tscn").instantiate()
	world.add_child(direct)
	direct.global_position=center+Vector2(40,0)
	direct.call("configure",longbow,longbow.Team,Vector2.RIGHT,620.0,10.0,30.0,0.0,0.0,5000.0,3,60.0,4.0,22.0,0.38)
	hp=enemy.health
	for i:int in range(40):
		direct._physics_process(0.016)
		if direct.is_queued_for_deletion(): break
	check(enemy.health<hp,"bolt strike damages the enemy")
	check(direct.is_queued_for_deletion() and _falls().size()==3,"struck bolt expires into rain")
	for fall:Node in _falls(): fall.queue_free()
	for rift:Node in _rifts(): rift.queue_free()
	enemy.queue_free()
	await process_frame
	# --- rift: crack, dodge, blast, close ---
	enemy=_mk_enemy(center+Vector2(190,0))
	await physics_frame
	var rift_bolt:Node=load("res://scenes/shooter/我的世界/天陨箭矢.tscn").instantiate()
	world.add_child(rift_bolt)
	rift_bolt.global_position=center+Vector2(40,0)
	rift_bolt.call("configure",longbow,longbow.Team,Vector2.RIGHT,620.0,10.0,30.0,0.0,0.0,5000.0,3,60.0,4.0,22.0,0.38)
	for i:int in range(40):
		rift_bolt._physics_process(0.016)
		if rift_bolt.is_queued_for_deletion(): break
	check(rift_bolt.is_queued_for_deletion() and _rifts().size()==1,"struck bolt tears one rift")
	var rift:Node=_rifts()[0]
	var arena:Rect2=world.return_map_world_rect(world.map_group["Map50x50"])
	check(rift._points[0].is_equal_approx(rift_bolt.global_position),"rift center is the exact impact point, not a terrain-snapped point")
	check(rift.is_open(),"fresh rift is open")
	check(rift._has_center_join,"radial cracks include a finite central connecting aperture")
	check(arena.grow(-longbow.rift_safe_margin).has_point(rift.landing) and longbow._heaven_body_clear(rift.landing),"visual fractures do not bypass safe-landing checks")
	check(rift._branches.size()>=3 and rift._branches.size()<=8,"rift grows multiple irregular fractures and fine branches")
	var roots:int=1
	var backwards:bool=false
	var compact:bool=true
	for limb in rift._branches:
		if limb[0].is_equal_approx(rift._points[0]): roots+=1
		if (limb[limb.size()-1]-rift._points[0]).dot(Vector2.RIGHT)<-8.0: backwards=true
		for p:Vector2 in limb:
			if p.distance_to(rift._points[0])>longbow.rift_length*0.65: compact=false
	check(roots>=4 and roots<=6 and backwards,"four to six main cracks surround the impact instead of extending one way")
	check(compact,"the full fracture cluster remains compact around the impact")
	var land0:Vector2=rift.landing
	enemy.global_position=land0+Vector2(40,0)
	await physics_frame
	hp=enemy.health
	var lb_hp:float=longbow.health
	rift._age = rift.opening_time
	var dodged:bool=longbow.receive_positional_damage(50.0,longbow.global_position,false,enemy)
	check(not dodged and is_equal_approx(longbow.health,lb_hp),"rift dodge negates the incoming hit")
	check(longbow.is_rift_transiting() and enemy.health==hp,"dodge starts the launch before dealing arrival damage")
	check(rift.is_reserved() and not rift._closed,"chosen rift stays visibly open during transit but cannot be reused")
	longbow._advance_rift_transit(longbow.TRANSIT.TOTAL_TIME + 0.01)
	check(longbow.global_position.is_equal_approx(land0),"dodge reaches the safe rift landing after exiting the screen")
	check(enemy.health<hp,"rift blast damages the landing zone")
	check(not rift.is_open(),"used rift is consumed")
	for r2:Node in _rifts(): r2.queue_free()
	for fall:Node in _falls(): fall.queue_free()
	await process_frame
	longbow._rift_cool=0.0
	longbow._rift_grace=0.0
	longbow.global_position=center+Vector2(-160,120)
	longbow.spawn_heaven_rift(center+Vector2(-160,0),Vector2.LEFT)
	longbow.spawn_heaven_rift(center+Vector2(160,0),Vector2.RIGHT)
	await process_frame
	check(_rifts().size()==2,"multiple rifts coexist")
	for waiting:Node in _rifts(): waiting._age = waiting.opening_time
	var land_a:Vector2=_rifts()[0].landing
	var land_b:Vector2=_rifts()[1].landing
	var expect:Vector2=land_a if longbow.global_position.distance_to(land_a)<longbow.global_position.distance_to(land_b) else land_b
	lb_hp=longbow.health
	dodged=longbow.receive_positional_damage(50.0,longbow.global_position,false,enemy)
	check(not dodged and longbow._rift_transit.target.is_equal_approx(expect),"dodge picks the nearest rift")
	longbow._advance_rift_transit(longbow.TRANSIT.TOTAL_TIME + 0.01)
	var left:Node=null
	for r3:Node in _rifts():
		if r3.is_open(): left=r3
	left._age=left._life
	left._process(0.05)
	check(not left.is_open(),"closed rift stops working")
	var impact:Vector2=center+Vector2(115,0)
	longbow.rng.seed=718
	var expected_path:PackedVector2Array=longbow._build_rift_path(impact,Vector2.RIGHT)
	var expected_branches:Array=longbow._grow_rift_branches(expected_path)
	var wall_c:StaticBody2D=_mk_wall(center+Vector2(120,0))
	await physics_frame
	longbow.rng.seed=718
	longbow.spawn_heaven_rift(impact,Vector2.RIGHT)
	await process_frame
	var rp:Node=_rifts()[_rifts().size()-1]
	check(rp._points==expected_path and rp._branches==expected_branches,"terrain cannot truncate, reflect, relocate or reshape the fractures")
	check(rp._points[0].is_equal_approx(impact),"even an impact inside a wall keeps its exact connected center")
	wall_c.queue_free()
	for r2:Node in _rifts(): r2.queue_free()
	for fall:Node in _falls(): fall.queue_free()
	enemy.queue_free()
	await process_frame
	longbow.queue_free()
	await process_frame
	# Explicit focused mode avoids coupling a bow/rift change to unrelated
	# characters whose mechanics are evolving in this workspace.
	if OS.get_cmdline_user_args().has("--heavenfall-only"):
		print("HEAVENFALL SCOPED RESULT: %d/%d passed" % [checks-failures,checks])
		finish(0 if failures==0 else 1)
		return
	# --- sheep: baa, wool armor, clips, graze ---
	var sheep:Node2D=spawn("res://scenes/characters/我的世界/羊.tscn",center)
	sheep.Can_Attack=true
	sheep.state_machine.set_physics_process(false)
	enemy=_mk_enemy(center+Vector2(80,0))
	await physics_frame
	await process_frame
	check(sheep.wool==3,"sheep starts fully woolled")
	check(sheep.image.scale.is_equal_approx(Vector2(1.82,1.82)),"sheep retains enlarged scale after ready")
	hp=enemy.health
	sheep.step_mob(0.016)
	check(enemy.health<hp,"startled baa damages nearby enemies")
	check(bool(enemy.Buff_Dic.get(sheep.get_instance_id(),{}).has("惊吓")),"baa slows nearby enemies")
	check(_heard("entity.sheep.ambient"),"baa cries out")
	sheep.velocity=Vector2(60,0)
	sheep.step_mob(0.016)
	sheep.visual_mob()
	check(sheep.image.texture is AtlasTexture and is_equal_approx(sheep.image.texture.region.position.y,0.0),"moving sheep plays the wool walk clip")
	sheep.velocity=Vector2.ZERO
	sheep.step_mob(0.016)
	sheep.visual_mob()
	check(is_equal_approx(sheep.image.texture.region.position.y,128.0),"still sheep grazes idly")
	check(sheep.image.scale.is_equal_approx(Vector2(1.82,1.82)),"wool idle preserves enlarged sheep scale")
	sheep.health-=60.0
	sheep.step_mob(0.016)
	check(sheep.wool==2,"heavy hit sheds one wool layer")
	check(is_equal_approx(sheep.Damage_reduction,0.16),"wool sets damage reduction")
	sheep.wool=0
	sheep.velocity=Vector2(60,0)
	sheep.step_mob(0.016)
	sheep.visual_mob()
	check(is_equal_approx(sheep.image.texture.region.position.y,256.0),"naked sheep plays the sheared walk clip")
	check(sheep.image.scale.is_equal_approx(Vector2(1.82,1.82)),"shearing and walking preserve enlarged sheep scale")
	enemy.global_position=center+Vector2(400,0)
	sheep.health=400.0
	sheep.wool=2
	sheep.velocity=Vector2.ZERO
	sheep._since_hurt=5.0
	sheep._regrow=3.9
	for i:int in range(8): sheep.step_mob(0.05)
	check(sheep.health>400.0,"grazing heals out of combat")
	check(sheep.wool==3,"wool regrows while grazing")
	sheep.health=1.0
	sheep.Die()
	check(_heard("entity.sheep.death"),"sheep death sound plays")
	sheep.queue_free()
	enemy.queue_free()
	await process_frame
	# --- boat: clips, ram, crash, paddle ---
	var boat:Node2D=spawn("res://scenes/characters/我的世界/木船.tscn",center)
	boat.Can_Attack=true
	boat.state_machine.set_physics_process(false)
	enemy=_mk_enemy(center+Vector2(20,0))
	await physics_frame
	await process_frame
	boat.step_mob(0.016)
	boat.visual_mob()
	check(is_equal_approx(boat.image.texture.region.position.y,0.0),"still boat drifts on the idle clip")
	check(boat.image.scale.is_equal_approx(Vector2(1.8,1.8)),"idle boat retains enlarged scale")
	boat.velocity=Vector2(150,0)
	boat.step_mob(0.016)
	boat.visual_mob()
	check(is_equal_approx(boat.image.texture.region.position.y,128.0),"moving boat rows")
	check(boat.image.scale.is_equal_approx(Vector2(1.8,1.8)),"rowing preserves enlarged boat scale")
	enemy.queue_free()
	await process_frame
	enemy=_mk_enemy(boat.global_position+Vector2(20,0))
	await physics_frame
	hp=enemy.health
	boat.velocity=Vector2(150,0)
	boat.step_mob(0.016)
	check(enemy.health<hp,"boat ram damages on contact")
	check(boat._ram_cd.has(enemy.get_instance_id()),"ram starts per-target cooldown")
	hp=enemy.health
	boat.step_mob(0.016)
	check(is_equal_approx(enemy.health,hp),"ram cooldown prevents instant double hits")
	boat._paddle_cd=0.0
	boat.step_mob(0.016)
	check(_heard("entity.boat.paddle_water"),"moving boat paddles")
	check(_heard("entity.generic.hurt"),"ram hit plays the mc hurt sound")
	boat.FX.hit_sfx(boat,boat.global_position,60.0)
	check(_heard("entity.player.attack.crit"),"heavy hits play the crit sound")
	enemy.global_position=center+Vector2(300,0)
	var reef:StaticBody2D=_mk_wall(boat.global_position+Vector2(70,0))
	await physics_frame
	hp=boat.health
	boat.velocity=Vector2(150,0)
	boat.step_mob(0.016)
	check(boat.health<hp,"crashing into walls hurts the boat")
	check(_heard("block.wood.break"),"crash breaks wood")
	reef.queue_free()
	boat.Die()
	check(_heard("block.wood.break"),"boat wreck plays wood break")
	boat.queue_free()
	enemy.queue_free()
	await process_frame
	finish(0 if failures==0 else 1)


func _mature_rift_fixture(owner: Node2D, point: Vector2, id: int = 0) -> Node2D:
	if id <= 0: id = owner._rift_seq + 1
	owner._rift_seq = maxi(owner._rift_seq, id)
	owner._spawn_rift(id, PackedVector2Array([point,point+Vector2(32,0)]), [], point, owner.rift_lifetime)
	var result: Node2D = owner._rifts.back().get_ref()
	result.set_process(false)
	result._age = result.opening_time
	result._sync_visual()
	return result
