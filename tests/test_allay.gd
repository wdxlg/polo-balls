extends SceneTree
var game:Node
var world:Node
var saved:Dictionary
var saved_stop:bool
var failures:int = 0
var checks:int = 0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func spawn(path:String,point:Vector2,team:String) -> Node2D:
	var unit:Node2D = load(path).instantiate()
	unit.Team = team
	unit.position = point
	world.add_child(unit,true)
	return unit
func intercept(allay:Node,shot:Node) -> bool:
	allay.notes = 1
	allay._note_cloud.clear()
	allay._note_cloud.resize(1,shot.global_position)
	return load("res://scripts/characters/我的世界/allay/capture.gd").sweep(shot,shot.global_position,shot.global_position)
func freeze(unit:Node) -> void:
	unit.Speed = 0
	unit.default_properties["Speed"] = 0
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Map_Background = "blue"
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(35.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3).timeout
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var allay:Node = spawn("res://scenes/characters/我的世界/悦灵.tscn",center,"Team0")
	var enemy:Node = spawn("res://scenes/ball.tscn",center+Vector2(300,0),"Team1")
	freeze(allay)
	freeze(enemy)
	enemy.Can_Attack = false
	enemy.Can_Skill = false
	var capture:Script = load("res://scripts/characters/我的世界/allay/capture.gd")
	check(allay.active(),"Allay battle runtime active")
	check(allay.Max_health==400 and allay.health==400,"allay starts with 400 health")
	var first_frame:Texture2D = allay.image.texture
	await create_timer(0.25).timeout
	check(allay.image.texture!=first_frame,"allay body plays official animation frames")
	allay.step_mob(1.5)
	check(allay.notes>=1,"passive generates orbiting notes")
	allay.step_mob(0.01)
	check(not allay.visual_state().has("collecting"),"periodic collection state removed")
	var bullet:Node = spawn("res://scenes/shooter/子弹.tscn",center+Vector2(45,0),"Team1")
	bullet.Master = enemy
	var before:float = allay.health
	check(intercept(allay,bullet),"enemy bullet collected")
	check(allay.notes==0 and allay._note_cloud.positions.is_empty() and allay.cargo.size()==1 and bullet.is_queued_for_deletion(),"one orbit note consumed and attack becomes one blue cube")
	check(allay.health==before,"collection causes no damage")
	check(capture.sweep(bullet,center,center) and allay.cargo.size()==1 and allay.notes==0,"duplicate capture cannot consume another note or mint cargo")
	check(allay._absorbs.size()==1,"captured projectile animates into a blue dot")
	var ally:Node = spawn("res://scenes/shooter/子弹.tscn",center+Vector2(40,0),"Team0")
	check(not intercept(allay,ally),"allied attack is not collected")
	ally.queue_free()
	check(not intercept(allay,enemy),"melee bodies cannot be collected")
	for i:int in range(10):
		var extra:Node = spawn("res://scenes/shooter/子弹.tscn",center+Vector2(45,0),"Team1")
		extra.Master = enemy
		check(intercept(allay,extra),"saturation still absorbs %d"%i)
	check(allay.cargo.size()==8,"cargo is bounded at eight")
	allay.cargo.clear()
	var returned:Node = spawn("res://scenes/shooter/子弹.tscn",center+Vector2(45,0),"Team1")
	returned.set_meta("allay_returned",true)
	check(intercept(allay,returned) and allay.cargo.is_empty(),"returned attack consumed without recursive ammunition")
	allay.notes = 0
	allay._note_cloud.clear()
	var incoming:Node = spawn("res://scenes/shooter/子弹.tscn",center,"Team1")
	incoming.Master = enemy
	var body_health:float = allay.health
	check(not capture.sweep(incoming,center+Vector2(45,0),center),"no notes means no body absorption field")
	check(incoming.self_hitbox.try_hit_hurtbox(allay.self_hurtbox),"unblocked projectile hits allay body normally")
	check(allay.health<body_health and allay.cargo.is_empty(),"body takes damage without creating cargo")
	var other:Node = spawn("res://scenes/shooter/子弹.tscn",center+Vector2(180,0),"Team1")
	other.Master = enemy
	allay.notes=1
	allay._note_cloud.clear()
	allay._note_cloud.resize(1,center+Vector2(30,0))
	check(capture.sweep(other,center+Vector2(180,0),center+Vector2(-180,0)),"fast attack is intercepted by an actual orbit note")
	check(allay.notes==0,"high speed interception consumes orbit note")
	var arrow:Node = load("res://scenes/shooter/我的世界/骷髅箭.tscn").instantiate()
	world.add_child(arrow)
	arrow.global_position = center+Vector2(60,0)
	arrow.configure(enemy,"Team1",Vector2.LEFT,520.0,25.0,3.0,3.0,90.0,5.5)
	check(intercept(allay,arrow),"Minecraft arrow adapter")
	var arrow_data:Dictionary = allay.cargo.back()
	var shot:Node = capture.launch(allay,arrow_data,enemy,center+Vector2(25,0))
	check(shot!=null and shot.get_script().resource_path.ends_with("骷髅箭.gd") and shot._source_ball().Master==allay,"returned arrow preserves type and changes ownership")
	shot.queue_free()
	var blaze:Node = load("res://scenes/shooter/我的世界/烈焰弹.tscn").instantiate()
	world.add_child(blaze)
	blaze.global_position = center+Vector2(60,0)
	blaze.configure(enemy,"Team1",Vector2.LEFT,330.0,1.0,3.2,0.1,34.0,4.5,0.11,0.05)
	check(intercept(allay,blaze),"blaze projectile collected without spawning ground fire")
	shot = capture.launch(allay,allay.cargo.back(),enemy,center+Vector2(25,0))
	check(shot!=null and shot._source_ball().Master==allay,"blaze returned with new owner")
	shot.queue_free()
	var shulker:Node = spawn("res://scenes/shooter/潜影弹.tscn",center+Vector2(45,0),"Team1")
	shulker.Master = enemy
	check(intercept(allay,shulker),"shulker projectile captured without levitation")
	shot = capture.launch(allay,allay.cargo.back(),enemy,center+Vector2(25,0))
	check(shot!=null and shot.target_ref.get_ref()==enemy and shot.Master.Master==allay,"returned shulker targets new enemy")
	shot.queue_free()
	check(allay.receive_positional_damage(5,center,false,enemy),"uncollectible positional damage remains effective")
	var data:Dictionary = {"kind":"simple","scene":"res://scenes/shooter/子弹.tscn","damage":99999.0,"speed":400.0,"scale":Vector2.ONE}
	shot = capture.launch(allay,data,enemy,center+Vector2(25,0))
	check(shot.Damage==99999 and shot.Master==allay,"returned damage is not capped and attribution correct")
	shot.queue_free()
	# Fired notes are single-use interceptors, including attacks outside body range.
	allay.notes=0
	allay._note_cloud.clear()
	allay.cargo.clear()
	var intercept_note:Node = allay.fire_note(enemy)
	intercept_note.global_position=center+Vector2(220,100)
	var remote_bullet:Node = spawn("res://scenes/shooter/子弹.tscn",center+Vector2(260,100),"Team1")
	remote_bullet.Master=enemy
	check(capture.sweep_note(intercept_note,center+Vector2(220,100),center+Vector2(280,100)),"moving fired note catches a stationary enemy attack far from owner")
	check(intercept_note._spent and intercept_note.is_queued_for_deletion() and remote_bullet.is_queued_for_deletion() and allay.cargo.size()==1,"fired note and attack consumed for exactly one cube")
	check(not capture.sweep_note(intercept_note,center+Vector2(220,100),center+Vector2(280,100)) and allay.cargo.size()==1,"spent flying note cannot absorb twice")
	intercept_note=allay.fire_note(enemy)
	intercept_note.global_position=center+Vector2(220,100)
	remote_bullet=spawn("res://scenes/shooter/子弹.tscn",center+Vector2(280,100),"Team1")
	remote_bullet.Master=enemy
	check(capture.sweep(remote_bullet,center+Vector2(280,100),center+Vector2(180,100)),"incoming fast attack collides with flying note")
	check(intercept_note._spent and allay.cargo.size()==2,"incoming collision consumes flying note once")
	intercept_note=allay.fire_note(enemy)
	intercept_note.global_position=center+Vector2(220,100)
	remote_bullet=spawn("res://scenes/shooter/子弹.tscn",center+Vector2(240,100),"Team0")
	check(not capture.sweep_note(intercept_note,center+Vector2(220,100),center+Vector2(260,100)) and not intercept_note._spent,"friendly attack does not consume flying note")
	remote_bullet.queue_free()
	intercept_note.queue_free()
	allay.notes=1
	allay._note_cloud.resize(1,center+Vector2(200,150))
	remote_bullet=spawn("res://scenes/shooter/子弹.tscn",center+Vector2(200,150),"Team1")
	remote_bullet.Master=enemy
	capture.scan_orbit(allay)
	check(allay.notes==0 and remote_bullet.is_queued_for_deletion(),"orbit note can absorb a stationary overlapping attack")
	# Real automatic return consumes exactly one cube outside collection.
	allay.cargo.clear()
	allay.cargo.append(data)
	allay._return_left = 0
	allay._cube_cloud.clear()
	allay._cube_cloud.has_spawn = false
	allay._cube_cloud.resize(1,center+Vector2(30,0))
	allay.joy_chance = 1.0
	allay._native_sfx_left.clear()
	enemy.global_position = center+Vector2(140,0)
	allay.step_mob(0.01)
	check(not allay._windup.is_empty(),"return starts with a backward windup")
	check(int(allay._windup.get("idx",-1))==0,"the cube nearest the enemy attacks")
	for i:int in range(60): allay.step_mob(1.0/60.0)
	check(allay.cargo.is_empty(),"nearby enemy triggers automatic cargo return")
	check(allay._lines.size()>=8,"launch emits a random glowing line burst")
	check(allay._native_sfx_left.has("entity.allay.item_thrown"),"cube throws can play the delighted sound")
	allay.cargo.append(data)
	allay._cube_cloud.resize(1,center+Vector2(30,0))
	allay._return_left = 0
	allay.step_mob(0.01)
	check(not allay._windup.is_empty(),"cargo return has no collection phase pause")
	allay._windup.clear()
	allay.cargo.clear()
	allay.notes = 0
	allay.Can_Attack = false
	var note:Node = allay.fire_note(enemy)
	note._ensure_path()
	check(note.collision_mask==0,"note body ignores solid obstacles")
	check(note.curve_offset(0.0).is_zero_approx() and note.curve_offset(1.0).is_zero_approx(),"arc begins and ends on aim spine")
	check(note.curve_offset(0.5).length()>10.0,"note follows a pronounced parabolic arc")
	check(note.curve_offset(0.25).dot(note._path_axis)>0.0 and note.curve_offset(0.75).dot(note._path_axis)<0.0,"arc has a forward and backward looping component")
	note._create_trail()
	var trail:Node = note._trail
	trail.set_process(false)
	check(trail.get_parent()==world,"note trail lives independently in world space")
	trail.advance(note.global_position,0.05,true)
	check(trail.particles.size()>0,"flying note emits small notes")
	var first_trail_point:Vector2 = trail.particles[0]["pos"]
	trail.advance(note.global_position+Vector2(20,0),0.1,true)
	check(trail.particles.size()>=3,"small notes continue spawning along the flight")
	check(Vector2(trail.particles[0]["pos"]).distance_to(first_trail_point)<3.0,"old small notes stay behind rather than following projectile")
	var trail_count:int = trail.particles.size()
	var trail_life:float = trail.particles[0]["life"]
	trail.advance(note.global_position,0.0,true)
	check(trail.particles.size()==trail_count and trail.particles[0]["life"]==trail_life,"paused trail does not emit or age")
	for i:int in range(120): trail.advance(note.global_position,1.0/60.0,true)
	check(trail.particles.size()<=trail.MAX_PARTICLES,"continuous trail particle count stays bounded")
	note.life = 0.15
	var initial:float = note.direction.angle()
	enemy.global_position = center+Vector2(0,300)
	note.tick_physics(note.State.Move,0.05)
	check(absf(angle_difference(initial,note.direction.angle()))<=note.turn_rate*0.05+0.001,"note homing turn rate is limited")
	await create_timer(0.3).timeout
	check(not is_instance_valid(note),"fired note expires")
	check(is_instance_valid(trail),"small notes survive projectile expiry to fade out")
	trail.advance(Vector2.ZERO,0.5,false)
	check(trail.particles.is_empty() and trail.is_queued_for_deletion(),"remaining trail expires and cleans itself up")
	allay.step_mob(0.02)
	check(not allay.has_method("collecting_now"),"body collection state API removed")
	# Dealt-damage vanilla feedback: hurt below 50, crit above, pitch scales with damage.
	var small_hit:AudioStreamPlayer2D = allay.notify_allay_hit(8.0,center)
	check(small_hit != null and small_hit.pitch_scale<1.0,"normal damage plays the vanilla hurt sound")
	var crit_hit:AudioStreamPlayer2D = allay.notify_allay_hit(60.0,center)
	check(crit_hit != null and crit_hit.pitch_scale>1.2,"over 50 damage switches to the critical sound")
	check(crit_hit.pitch_scale>small_hit.pitch_scale,"higher damage raises the pitch")
	allay.Can_Attack = false
	enemy.global_position = center+Vector2(70,0)
	var health_before:float = enemy.health
	var hurt_meta_at_fire:int = int(allay.get_meta("mc_event_sound_entity_player_hurt",-9999))
	var hit_note:Node = allay.fire_note(enemy)
	hit_note.Speed = 150.0
	check(allay._flash>0.0,"note firing pulses the body highlight")
	allay._native_sfx_left.clear()
	allay.step_mob(0.02)
	check(not allay._native_sfx_left.has("entity.allay.item_taken"),"no periodic collection windup sound")
	allay._native_sfx_left.clear()
	allay.giggle_chance = 1.0
	allay.fire_note(enemy)
	check(allay._native_sfx_left.has("entity.allay.item_given"),"note shots can play the giggle sound")
	allay.giggle_chance = 0.35
	allay._native_sfx_left.clear()
	allay._ambient_left = 0.001
	allay.tick_ambient(0.01)
	var audible:AudioStreamPlayer2D = allay.play_sound("entity.allay.item_taken",-4.0)
	check(audible != null and audible.volume_db>-16.0,"voice sounds stay above the audibility floor")
	var breath:AudioStreamPlayer2D = allay._ambient_player
	check(breath != null and is_instance_valid(breath),"breathing uses the vanilla search ambient")
	check(allay._ambient_left >= breath.stream.get_length()-0.05,"next breath waits at least for the previous clip length")
	await create_timer(0.65).timeout
	check(enemy.health<health_before,"slow note deals real damage on contact")
	check(not is_instance_valid(hit_note),"note disappears after hitting")
	check(int(allay.get_meta("mc_event_sound_entity_player_hurt",-9999))>hurt_meta_at_fire,"note hits trigger the master hurt sound hook")
	# Verify movement slowdown uses actual locomotion, without mutating Speed.
	allay.global_position = center
	allay.direction = Vector2.RIGHT
	allay.Repel = Vector2.ZERO
	allay.move(120.0,0.016)
	var normal_distance:float = allay.global_position.distance_to(center)
	allay.global_position = center
	allay.move(120.0,0.016)
	var slow_distance:float = allay.global_position.distance_to(center)
	check(normal_distance>0 and absf(slow_distance/normal_distance-1.0)<0.02,"movement no longer has collection slowdown")
	allay.global_position = center
	var blocker:=StaticBody2D.new()
	var shape_node:=CollisionShape2D.new()
	var rect:=RectangleShape2D.new()
	rect.size=Vector2(10,120)
	shape_node.shape=rect
	blocker.add_child(shape_node)
	world.add_child(blocker)
	blocker.global_position=center+Vector2(100,0)
	await physics_frame
	check(allay._constrain_point(center+Vector2(100,0)).x<center.x+94.9,"blue dots are squeezed out of obstacles")
	var map_rect:Rect2 = world.return_map_world_rect(world.map_group["Map50x50"])
	check(map_rect.has_point(allay._constrain_point(map_rect.position-Vector2(80,80))),"blue dots are clamped inside the map")
	allay.notes=1
	allay._note_cloud.clear()
	allay._note_cloud.resize(1,center)
	var occluded:Node = spawn("res://scenes/shooter/子弹.tscn",center+Vector2(180,0),"Team1")
	check(not capture.sweep(occluded,center+Vector2(180,0),center),"collection does not pull through solid walls")
	occluded.queue_free()
	# Wall spans the entire curved path, so a hit proves real penetration.
	blocker.global_position = center+Vector2(45,0)
	rect.size = Vector2(10,400)
	enemy.global_position = center+Vector2(90,0)
	allay.cargo.clear()
	allay._note_cloud.clear()
	allay.notes = 1
	allay._generate_left = 10.0
	allay._note_left = 0.0
	allay.Can_Attack = true
	await physics_frame
	var wall_health:float = enemy.health
	allay.step_mob(0.01)
	check(allay.notes==0,"note fires at enemy behind wall")
	allay.Can_Attack = false
	await create_timer(1.35).timeout
	check(enemy.health<wall_health,"curved note passes through wall and damages enemy")
	blocker.queue_free()
	allay.Can_Attack = true
	enemy.global_position=center+Vector2(500,0)
	allay.notes=0
	allay._generate_left=0.0
	for i:int in range(12): allay.step_mob(0.81)
	check(allay.notes==allay.current_note_capacity(),"idle notes respect capacity")
	allay.cargo.append(data)
	allay._return_left=0.0
	allay.step_mob(0.01)
	check(allay.cargo.size()==1,"no nearby enemy preserves stored ammunition")
	allay.Can_Attack=false
	# End-to-end: actual curved flight crosses a stationary projectile.
	allay.cargo.clear()
	allay.notes=0
	allay._note_cloud.clear()
	enemy.global_position=center+Vector2(320,150)
	var live_note:Node = allay.fire_note(enemy)
	live_note.global_position=center+Vector2(200,150)
	live_note.direction=Vector2.RIGHT
	live_note._ensure_path()
	var intercept_point:Vector2 = live_note.global_position+Vector2.RIGHT*30.0+live_note.curve_offset(0.25)
	var live_attack:Node = spawn("res://scenes/shooter/子弹.tscn",intercept_point,"Team1")
	live_attack.Master=enemy
	freeze(live_attack)
	await create_timer(0.7).timeout
	check(not is_instance_valid(live_note) and not is_instance_valid(live_attack) and allay.cargo.size()==1,"actual curved flight consumes note and enemy attack into one cube")
	# Await outstanding world character-prewarm work before engine shutdown.
	await create_timer(3.0).timeout
	finish(0 if failures==0 else 1)
func finish(code:int) -> void:
	if game!=null:
		game.Game_Settings=saved
		game.now_stop_state=saved_stop
	print("ALLAY_TEST checks=",checks," failures=",failures)
	quit(code)
