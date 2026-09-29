extends "res://tests/test_mc_bat_transform.gd"
## Deterministic gameplay contracts; live ticking and GPU presentation are separate tests.
func actor(role:String,point:Vector2,team:String = "Team0") -> Node2D:
	var unit:Node2D = spawn("res://scenes/characters/我的世界/"+role+".tscn",point,team)
	unit.Can_Attack = true
	unit.Can_Skill = true
	unit.default_properties["Can_Attack"] = true
	unit.default_properties["Can_Skill"] = true
	unit.state_machine.set_physics_process(false)
	unit.set_process(false)
	unit.set_player_control_peer(1)
	return unit
func dummy(point:Vector2,team:String = "Team1") -> Node2D:
	var unit:Node2D = spawn("res://scenes/ball.tscn",point,team)
	unit.state_machine.set_physics_process(false)
	unit.Has_Collision_Damage = false
	unit.self_hitbox.monitoring = false
	unit.Max_health = 10000
	unit.default_properties.Max_health = 10000
	unit.health = 10000
	return unit
func wall(point:Vector2,size:Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.set_meta("mc_wall",true)
	var shape := RectangleShape2D.new()
	shape.size = size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)
	body.global_position = point
	return body
func complete_moss_growth(unit:Node2D) -> void:
	if not unit._growth_winding: return
	unit.clock = unit._moss_pose_started+unit.placement_shrink_time+0.0001
	unit.finish_cultivation()
	unit.clock = unit._moss_pose_started+unit.placement_shrink_time+unit.placement_spring_time+0.0001
	unit.visual_mob()
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(75.0).timeout.connect(func(): finish(2))
	for role:String in ["苔藓","木剑","监守者","矿车"]:
		check(world.return_all_character_names().has(role),"actual Minecraft roster contains "+role)
	var w:Node2D = actor("监守者",center+Vector2(0,160))
	var target:Node2D = dummy(w.global_position+Vector2(150,0))
	var friendly:Node2D = dummy(w.global_position+Vector2(0,90),"Team0")
	await physics_frame
	await process_frame
	var bus:Node=world.get_node("MCBattleNoise")
	bus.set_physics_process(false)
	check(w.form==0 and w.alert_level==0 and w.signals_received==0 and w.Max_health==600,"new shrieker begins with empty alert and echo counters")
	check(w.get_preview_texture()==w.SHRIEKER and w.attack_damage()==0,"starting presentation and dormant damage gate")
	check(not w.begin_emergence() and not w.receive_echo(0,"fake"),"summoning requires real returned echoes")
	w.alert_level=w.alert_max
	check(w.begin_probe(),"full alert starts timed probing")
	w.listen_heading=Vector2.RIGHT
	for i:int in range(5):
		w.emit_probe()
		var wave:Node2D=w.waves.back()
		wave.set_physics_process(false)
		wave.advance(0.72)
		var echo:Node2D=w.waves.back()
		echo.set_physics_process(false)
		check(echo.kind=="return","a real probe hit produces a return signal")
		echo.advance(0.4)
	check(w.form==1 and w.signals_received==5,"five returning signals begin emergence")
	w.health=300
	var phase_before:float=w.form_left
	game.now_stop_state=true
	w.tick_physics(0,4)
	check(w.form_left==phase_before,"pause freezes emergence")
	game.now_stop_state=false
	w.tick_physics(0,w.emerge_duration+0.01)
	check(w.form==2 and w.health==600 and w.Max_health==1200,"awakening preserves health percentage")
	w.sounds.clear(); w.quiet_time=0
	w.step_mob(8.1)
	check(w.form==3,"silence starts burrowing")
	w.step_mob(1.81)
	check(w.form==0 and w.signals_received==0 and w.alert_level==0 and w.health==300,"burrow resets ritual and preserves health ratio")
	check(w.WARDEN.get_animation_names().size()==7 and w.WARDEN.get_frame_count(&"emerge")==24,"native Warden animation set is preserved")
	check(not w.WARDEN.get_frame_texture(&"idle",0) is AtlasTexture,"full-texture model frame contract is preserved")
	var hp:int=0
	var barrier:StaticBody2D
	var moss:Node2D = actor("苔藓",center+Vector2(-210,-160))
	check(not moss.image.z_as_relative and moss.image.z_index > moss.frontier_fx.z_index,"moss body remains above its own ground tiles")
	var grass_target:Node2D = dummy(moss.global_position+Vector2(55,0))
	moss.growth_left = 0.0
	check(moss.cultivate() and moss.patches.is_empty(),"growth begins with preview only")
	complete_moss_growth(moss)
	check(moss.patches.size() == 6,"growth creates six distinct moss cells on rebound")
	var tile:Vector2 = moss.patches[0].point
	check(moss.plant(tile) and moss.plant(tile) and not moss.plant(tile),"moss stacks to three layers and skips full cells")
	grass_target.global_position = tile
	hp = grass_target.health
	moss.check_trampling()
	check(grass_target.health == hp-30 and moss.patches.size() == 6,"fresh three-layer moss deals triple damage without consumption")
	hp = grass_target.health
	moss.check_trampling()
	check(grass_target.health == hp,"moss shares one damage cooldown per victim")
	grass_target.global_position = moss.global_position+Vector2(250,0)
	moss.global_position = tile
	moss.health = 300
	moss.tick_physics(0,1.01)
	check(moss.health == 306,"standing on moss heals six per combat second")
	for i:int in range(20):
		moss.growth_left = 0.0
		moss.cultivate()
		complete_moss_growth(moss)
	for patch:Dictionary in moss.patches: check(int(patch.layers) <= 3,"growth never exceeds three layers")
	var blocked_point:Vector2 = moss.global_position+Vector2(0,24)
	barrier = wall(blocked_point,Vector2(28,28))
	await physics_frame
	await process_frame
	moss.patches.clear()
	check(not moss.plant(blocked_point),"moss cannot be planted inside solid terrain")
	barrier.queue_free()
	await physics_frame
	moss.plant(moss.global_position)
	var growth_before:float = moss.growth_left
	var game_clock:float = moss.clock
	game.now_stop_state = true
	moss.tick_physics(0,9.0)
	check(moss.growth_left == growth_before and moss.clock == game_clock,"pause freezes moss growth and combat clock")
	game.now_stop_state = false
	moss.patches.clear()
	var sword:Node2D = actor("木剑",center+Vector2(210,-160))
	sword.direction = Vector2.RIGHT
	sword.velocity = Vector2.ZERO
	var sword_target:Node2D = dummy(sword.global_position+Vector2(12,0))
	await physics_frame
	await process_frame
	check(sword.durability == sword.MAX_DURABILITY,"wooden sword starts with full durability")
	check(not sword.has_method("begin_brace"),"old brace skill is deleted")
	sword.Skill()
	hp = sword.health
	sword.take_damage(40,true)
	check(sword.health==hp-40,"skill no longer grants damage reduction")
	sword.set_migrated_health(750,750)
	sword.durability=sword.MAX_DURABILITY
	sword.sword_charge=1.0
	hp=sword_target.health
	check(sword.begin_swing(),"charged swing starts")
	sword.advance_attack(0.34)
	check(sword_target.health==hp-84 and sword.durability==sword.MAX_DURABILITY-1,"full charge hits physical contact for 84 and spends one durability")
	hp=sword_target.health
	check(sword.resolve_swing()==0 and sword_target.health==hp,"completed swing cannot hit twice")
	sword.sword_charge=0.5
	sword.visual_mob()
	check(sword.image.rotation<0 and sword.image.position.y<0,"charge raises and rotates the sword")
	sword.sword_charge=0
	sword.spend_durability(999)
	await process_frame
	await process_frame
	check(sword.is_broken() and sword.durability == 0,"durability never underflows and zero splits the sword")
	sword.visual_mob()
	check(sword.image.texture == sword.HILT,"broken original becomes the actual sword hilt")
	var bench:Node2D = sword.workbench
	bench.set_physics_process(false)
	bench.age = bench.materialize_duration
	bench.update_opacity()
	var blade:Node2D
	for piece:Node2D in bench.living_pieces():
		piece.state_machine.set_physics_process(false)
		piece.dock_delay = 0.0
		piece.global_position = bench.global_position+Vector2(-10 if piece == sword else 10,0)
		if piece != sword: blade = piece
	check(is_instance_valid(blade) and blade.part_kind == 2,"break also creates an independent blade")
	sword.finish_repair()
	check(sword.is_broken(),"repair completion cannot skip the channel")
	bench.advance(0.8)
	check(sword.repairing and sword.repair_left > 0.0,"both pieces must spend real combat time touching")
	sword.receive_positional_damage(5,sword.global_position,false,sword_target)
	check(sword.repairing,"bench damage reduction does not cancel a valid contact channel")
	var repair_before:float = sword.repair_left
	game.now_stop_state = true
	bench.advance(6.0)
	check(sword.repair_left == repair_before and sword.is_broken(),"pause cannot finish a workbench channel")
	game.now_stop_state = false
	blade.global_position += Vector2(100,0)
	bench.advance(0.1)
	check(not sword.repairing and bench.progress == 0,"leaving bench resets repair")
	blade.global_position = bench.global_position+Vector2(10,0)
	bench.advance(2.41)
	check(sword.durability == sword.MAX_DURABILITY and sword.successful_repairs == 1 and sword.Max_health == 750,"completed contact repair recombines into a full-durability sword")
	var ghost:Node2D = actor("监守者",center+Vector2(0,-340))
	ghost.set_multiplayer_authority(2)
	ghost.accept_visual(w.visual_state())
	check(ghost.form == w.form and ghost.signals_received == w.signals_received and not ghost.begin_emergence(),"visual snapshots reproduce form without granting client-side summons")
	ghost.free()
	check(sword.frontier_fx.particles.size() <= 48 and w.frontier_fx.beams.size() <= 3,"combat effects remain explicitly bounded")
	var dead:Node2D = actor("监守者",center+Vector2(330,320))
	dead.health = 0
	dead.signals_received = 5
	check(not dead.begin_emergence() and not dead.finish_emergence(),"a killed shrieker cannot resurrect into a Warden")
	print("FRONTIER CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures == 0 else 1)
