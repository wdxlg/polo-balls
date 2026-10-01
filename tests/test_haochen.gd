extends "res://tests/test_sulfur_cube_balance.gd"
## Gameplay uses real original-scene copies, not a recolored generic dummy.
var hero:Node2D
var donor_a:Node2D
var donor_b:Node2D
var origin:Vector2
var TOOLS:Script
var CLASSIFY:Script

func unit(path:String,key:String,point:Vector2,team:String = "Team1") -> Node2D:
	var node:Node2D = load(path).instantiate()
	node.name = key
	node.Team = team
	node.position = point
	world.add_child(node)
	node.state_machine.set_physics_process(false)
	node.set_physics_process(false)
	node.Has_Collision_Damage = false
	return node

func freeze_copies() -> Array[Node]:
	var out:Array[Node] = []
	for raw:Variant in get_nodes_in_group("Ball"):
		if is_instance_valid(raw) and bool(raw.get_meta("haochen_copy",false)):
			raw.state_machine.set_physics_process(false)
			raw.set_physics_process(false)
			out.append(raw)
	return out

func full_request() -> Node:
	var request:Node = hero._copy_request.get_ref() if hero._copy_request!=null else null
	if is_instance_valid(request): request.set_physics_process(false)
	return request

func reset_cycle() -> void:
	var request:Node = full_request()
	if is_instance_valid(request): request.free()
	hero._copy_request = null
	hero.charge_phase = hero.Phase.RESTING
	hero.charge_energy = 0.0
	hero.contributions.clear()
	hero._contributor_serial = 0
	hero._retry_left = 0.0
	hero._scan_left = 0.0
	hero.movement_ratio = 1.0

func run() -> void:
	create_timer(130.0,true,false,true).timeout.connect(func():print("HAOCHEN_TIMEOUT");quit(2))
	game = root.get_node("Game")
	TOOLS = load("res://scripts/characters/投稿角色工具.gd")
	CLASSIFY = load("res://classes/combat_classification.gd")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var stopped:bool = game.now_stop_state
	game.now_stop_state = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	AudioServer.set_bus_mute(0,true)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.set_process(false)
	world.set_physics_process(false)
	origin = world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	hero = unit("res://scenes/characters/我的世界/皓宸.tscn","HaochenTest",origin,"Team0")
	hero.set_meta("battle_setup_id",8100)
	world.bind_battle_lifecycle(hero,null,true)
	hero.set_process(false)
	donor_a = unit("res://scenes/ball.tscn","EnergyA",origin+Vector2(-25,0))
	donor_b = unit("res://scenes/characters/我的世界/末影人.tscn","EnergyB",origin+Vector2(500,0))
	donor_a.Max_health = 600
	donor_a.health = 600
	donor_a.Damage = 80
	donor_a.Speed = 150.0
	donor_a.max_block = 40
	donor_a.max_energy = 80
	donor_a.Health_Restore = 6
	donor_a.Damage_reduction = 0.4
	donor_a.Attack_Cooling = 1.6
	donor_a.Skill_Cooling = 4.0
	for key:String in TOOLS.COPY_STAT_KEYS: donor_a.default_properties[key] = donor_a.get(key)
	await physics_frame
	check(world.character_scene_path("皓宸")=="res://scenes/characters/我的世界/皓宸.tscn","Haochen is discoverable in the real Minecraft scene roster")
	check(CLASSIFY.profile_of(hero).entity_kind=="character" and not hero.Has_Collision_Damage,"Haochen is a registered real character without invented contact damage")
	check(hero.player_control_action_ids().is_empty(),"automatic proximity/copy mechanics remain passive under direct control")
	check(hero.get_ai_attack_threats(null).is_empty() and hero.get_debug_detection_regions().size()==1,"energy radius is blue detection only, not fake damage")
	check(hero.BAR==load("res://scripts/characters/我的世界/frontier/creeper_style_bar.gd"),"Haochen uses the same shared Creeper bar painter")
	check(load("res://scripts/characters/我的世界/苦力怕.gd").SHARED_BAR==hero.BAR,"the actual Creeper now uses that exact same painter")
	var rect:Rect2 = hero.BAR.below_body(hero,hero.collision_shape_2d)
	check(rect.position.y>hero.collision_shape_2d.shape.get_rect().end.y and rect.size==Vector2(110,16),"reusable bar layout sits below the physical body")
	var home:Vector2 = hero.global_position
	hero._previous_audio_position = home
	hero._audio_sample_valid = true
	hero._step_creature_audio(0.4)
	check(hero._step_tickets.is_empty(),"standing still plays no footstep")
	hero.global_position.x += 4.0
	hero._step_creature_audio(0.05)
	check(hero._step_tickets.size()==1,"first real walking displacement plays a footstep")
	var stride:float = hero.FOOTSTEP.base_speed(hero)*maxf(hero.STEP_BASE_INTERVAL,hero._step_length)
	for i:int in range(9):
		hero.global_position.x += stride*0.05
		hero._step_creature_audio(0.01)
	check(hero._step_tickets.size()==1,"half a stride adds no footstep")
	for i:int in range(12):
		hero.global_position.x += stride*0.05
		hero._step_creature_audio(0.01)
	check(hero._step_tickets.size()==2 and hero.AUDIO.busy(hero._step_tickets[0]),"fast walking starts the next footstep while the previous still plays")
	for ticket:Dictionary in hero._step_tickets: hero.AUDIO.cancel(ticket)
	hero._step_tickets.clear()
	hero.global_position = home
	hero._previous_audio_position = home

	var hp:float = donor_a.health
	hero._step_energy(3.0)
	check(is_equal_approx(hero.charge_energy,60.0) and is_equal_approx(hero.contributions[donor_a.get_instance_id()].energy,60.0),"first donor supplies60 energy over three seconds")
	check(hero.movement_ratio==hero.minimum_move_ratio and donor_a.health==hp,"charging slows only Haochen down to a positive floor and does not damage donors")
	check(hero.image.texture==hero.FACE_LAUGH and hero.FACE_LAUGH.resource_path=="res://Images/characters/我的世界/皓宸/皓宸笑.png","charging shows the user's laughing head front")
	hero._aura_left = 0.0;hero._drain_left = 0.0
	hero._step_charge_stream(0.01)
	var aura:int = 0;var drain:int = 0
	var soul_script:Script = load("res://scripts/effects/我的世界/灵魂粒子.gd")
	for raw:Node in get_nodes_in_group("MCHaochenAuraParticle"):
		if int(raw.get_meta("haochen_stream_owner",0))==hero.get_instance_id() and raw.get_script()==soul_script: aura += 1
	for raw:Node in get_nodes_in_group("MCHaochenChargeParticle"):
		if int(raw.get_meta("haochen_stream_owner",0))==hero.get_instance_id() and raw.get_script()==soul_script: drain += 1
	check(aura>=1 and drain>=1,"charging emits native soul particles around Haochen and from the feeding enemy")
	donor_a.global_position = origin+Vector2(500,0)
	hero._scan_left = 0.0
	hero._step_energy(1.0)
	check(is_equal_approx(hero.charge_energy,60.0) and hero.contributions.size()==1 and hero.movement_ratio>hero.minimum_move_ratio,"leaving range retains energy/history while movement gradually recovers")
	check(hero.image.texture==hero.FACE_NORMAL and hero.FACE_NORMAL.resource_path=="res://Images/characters/我的世界/皓宸/皓宸.png","no nearby enemy returns to the normal head front")
	hero._step_energy(1.0)
	check(is_equal_approx(hero.movement_ratio,1.0),"two seconds without a nearby enemy restore ordinary voluntary speed")
	donor_b.global_position = origin+Vector2(25,0)
	hero._scan_left = 0.0
	hero._step_energy(2.0)
	var request:Node = full_request()
	check(is_instance_valid(request) and hero.charge_phase==hero.Phase.COPYING and is_equal_approx(hero.charge_energy,100.0),"full meter starts one confirmed copy cast")
	check(request.template_snapshot.scene==donor_a.scene_file_path and is_equal_approx(hero.contributions[donor_b.get_instance_id()].energy,40.0),"60/40 picks the first donor's character, not the last/nearest donor")
	check(world._battle_spawn_tickets.size()==1,"confirmed delayed copy registers a shared battle-lifecycle request")
	check(hero.image.texture==hero.FACE_LAUGH,"Haochen keeps laughing while the full meter is being cashed in")
	check(request.link_visible and request.link_from.distance_to(donor_a.global_position)<0.5 and request.link_to.distance_to(hero.global_position)<0.5,"copy link spans from the copied character to Haochen")
	donor_a.global_position += Vector2(0,30)
	request._refresh_link_points()
	check(request.link_from.distance_to(donor_a.global_position)<0.5,"authority keeps the link attached to the moving copied character")
	request._emit_link_particles(6,false)
	var link_particles:Array[Node] = []
	for raw:Node in get_nodes_in_group("MCHaochenLinkParticle"):
		if int(raw.get_meta("haochen_copy_request",0))==request.get_instance_id(): link_particles.append(raw)
	var on_segment:bool = link_particles.size()>=6
	for p:Node in link_particles:
		var start:Vector2 = p._start
		var nearest:Vector2 = Geometry2D.get_closest_point_to_segment(start,request.link_from,request.link_to)
		on_segment = on_segment and start.distance_to(nearest)<=6.0 and (start+p._motion).distance_to(request.link_to)<=4.5 and p.get_script()==load("res://scripts/effects/我的世界/灵魂粒子.gd")
	check(on_segment,"native soul particles spawn between them and flow into Haochen")
	var cast_serial:int = hero._sound_serial
	check(not (hero._sound_tickets.get(&"copy_start",{}) as Dictionary).is_empty() and hero.AUDIO.EVENTS[&"copy_start"][0].resource_path=="res://audio/characters/唤魔者/evoker.prepare_summon_1.ogg","confirmed copy cast plays the original Evoker prepare-summon clip")
	hero._step_energy(0.2)
	check(hero._sound_serial==cast_serial,"an in-progress copy cast does not replay its start sound every tick")
	request._physics_process(hero.copy_duration)
	var copies:Array[Node] = freeze_copies()
	check(copies.size()==1 and copies[0].scene_file_path==donor_a.scene_file_path,"copy is a fresh instance of the winning original scene")
	var copy:Node = copies[0]
	check(copy.Max_health==300 and copy.health==300 and copy.Damage==40 and copy.max_block==20 and copy.max_energy==40,"copied public combat attributes are halved and new health starts full at the new cap")
	check(copy.Speed==150.0 and copy.Attack_Cooling==1.6 and copy.Skill_Cooling==4.0,"movement speed and cooldown parameters are unchanged")
	check(copy.Health_Restore==3 and is_equal_approx(copy.Damage_reduction,0.2),"regeneration and defense follow the half-stat profile")
	copy.restore_default_runtime_properties_fast()
	check(copy.Damage==40 and copy.Max_health==300 and copy.Speed==150.0,"shared per-frame property reset cannot undo copied attributes")
	check(copy.direction.length()>0.1,"fresh copied character receives the existing World's normal initial movement direction")
	check(copy.Master==hero and copy.Team==hero.Team and copy.get_meta("battle_lifecycle_identity").root==hero.get_meta("battle_lifecycle_identity").root,"copy belongs to Haochen's actual owner/team/lifecycle family")
	check(bool(copy.character_copy_profile.monochrome) and copy.image.get_instance_shader_parameter("character_grayscale")==1.0,"copy opts into true shader grayscale instead of a gray color multiplier")
	check(hero.charge_energy==0.0 and hero.contributions.is_empty() and hero.completed_copies==1 and world._battle_spawn_tickets.is_empty(),"successful copy resets only this cycle and releases the spawn ticket")
	check(hero.image.texture==hero.FACE_NORMAL,"face returns to normal after the copy completes")
	check(get_nodes_in_group("MCHaochenCopyParticle").size()>0,"real copy process emits existing Minecraft particle instances")
	var souls:Script = load("res://scripts/effects/我的世界/灵魂粒子.gd")
	var soul_frames_ok:bool = souls.FRAMES.size()==11
	for i:int in range(souls.FRAMES.size()):soul_frames_ok = soul_frames_ok and souls.FRAMES[i].resource_path=="res://Images/effects/我的世界/灵魂粒子/soul_%d.png"%i
	check(soul_frames_ok,"soul particle plays the 11 native soul_0..soul_10 frames in order")
	for i:int in range(3):
		hero._scan_left = 0.0
		hero._step_energy(5.0)
		var next:Node = full_request()
		check(is_instance_valid(next),"another full meter begins another copy without a hidden cap")
		next._physics_process(hero.copy_duration)
		freeze_copies()
	check(freeze_copies().size()==4 and hero.completed_copies==4,"four living copies persist; new copies do not replace old ones")

	reset_cycle()
	donor_a.global_position = origin+Vector2(-25,0)
	donor_b.global_position = origin+Vector2(25,0)
	hero._record_contribution(donor_a,57.5)
	hero._record_contribution(donor_b,37.5)
	hero.charge_energy = 95.0
	hero._step_energy(1.0)
	request = full_request()
	check(is_equal_approx(hero.contributions[donor_a.get_instance_id()].energy,60.0) and is_equal_approx(hero.contributions[donor_b.get_instance_id()].energy,40.0),"the last five capacity points are shared fairly instead of assigned by loop order")
	request.free()
	check(world._battle_spawn_tickets.is_empty(),"cancelled copy frees its pending-lifecycle claim")
	reset_cycle()
	hero._record_contribution(donor_a,50.0)
	hero._record_contribution(donor_b,50.0)
	check(hero._winner().snapshot.scene==donor_a.scene_file_path,"equal contribution ties use first contribution order deterministically")

	reset_cycle()
	donor_a.Team = hero.Team
	donor_b.global_position = origin+Vector2(500,0)
	hero._step_energy(1.0)
	check(hero.charge_energy==0.0,"friendly units and owned copies do not supply energy")
	donor_a.Team = "Team1"
	hero._scan_left = 0.0
	game.now_stop_state = true
	hero._step_energy(5.0)
	check(hero.charge_energy==0.0 and hero.movement_ratio==1.0,"pause freezes energy and movement-ratio integration")
	game.now_stop_state = false
	hero.set_multiplayer_authority(2)
	hero._step_energy(5.0)
	check(hero.charge_energy==0.0,"non-authority cannot accumulate or create a copy")
	hero.set_multiplayer_authority(1)
	hero.energy_capacity = 1000.0
	hero._step_energy(1.0)
	check(is_equal_approx(hero.movement_ratio,0.65),"slowdown is gradual rather than an immediate speed clamp")
	hero._step_energy(1.0)
	check(is_equal_approx(hero.movement_ratio,0.3),"configured slowdown duration reaches its minimum and never zero")
	hero.player_control_peer_id = 1
	hero.player_control_direction = Vector2.RIGHT
	hero.collision_mask = 0
	hero.Repel = Vector2(50,0)
	hero.surface_motion_velocity = Vector2.ZERO
	await physics_frame
	hero.move(hero.Speed,1.0/60.0)
	check(is_equal_approx(hero._last_requested_velocity.x,hero.Speed*hero.CHARACTER_BASE_MOVE_SPEED_MULTIPLIER*0.3+50.0),"charging slow affects voluntary drive but never scales external knockback")

	# Common extraction retains Dice's distinct one-third/current-vitals policy.
	var snapshot:Dictionary = TOOLS.capture_character_template(donor_a)
	snapshot.health = 270
	var dice_profile:Dictionary = TOOLS.build_character_copy_profile(snapshot,1.0/3.0,{"full_vitals":false,"cooldown_factor":1.0/3.0})
	check(dice_profile.stats.Max_health==200 and dice_profile.stats.Damage==27 and dice_profile.health==90 and is_equal_approx(dice_profile.stats.Attack_Cooling,1.6/3.0),"parameterized factory preserves Dice's old third-stats/current-health/cooldown contract")
	check(not bool(dice_profile.monochrome),"existing Dice copies do not acquire Haochen's black-white style")
	snapshot.stats.Attack_Cooling = 0.0
	snapshot.stats.Skill_Cooling = 0.0
	var unchanged_cooldowns:Dictionary = TOOLS.build_character_copy_profile(snapshot,0.5)
	check(unchanged_cooldowns.stats.Attack_Cooling==0.0 and unchanged_cooldowns.stats.Skill_Cooling==0.0,"unchanged skill parameters also preserve zero-cooldown sentinel values")
	check(hero.get_armor_test_effect_summary().contains("贡献"),"real armor-stand introduction describes contribution-based copying")

	# No-team family membership must survive a confirmed cast source's deletion.
	var orphan_owner:Node2D = unit("res://scenes/characters/我的世界/皓宸.tscn","OrphanHaochen",origin+Vector2(0,-40),"")
	orphan_owner.set_meta("battle_setup_id",8101)
	world.bind_battle_lifecycle(orphan_owner,null,true)
	orphan_owner.set_process(false)
	orphan_owner._record_contribution(donor_a,100.0)
	orphan_owner.charge_energy = 100.0
	orphan_owner._begin_copy()
	var orphan_request:Node = orphan_owner._copy_request.get_ref()
	orphan_request.set_physics_process(false)
	var family_root:int = orphan_owner.get_meta("battle_lifecycle_identity").root
	orphan_owner.free()
	check(world._battle_family_alive(8101),"confirmed pending copy keeps its exact old family alive after the body is deleted")
	orphan_request._physics_process(orphan_request.cast_duration)
	var found:Node
	for candidate:Node in freeze_copies():
		if candidate.get_meta("battle_lifecycle_identity",{}).get("root",0)==family_root: found=candidate
	check(is_instance_valid(found) and found.Master_name=="OrphanHaochen" and world._battle_family_alive(8101),"orphan copy inherits the frozen original family without a fake new setup slot")
	check(world._battle_spawn_tickets.is_empty(),"successful orphan copy leaves no stale confirmed request")
	world.queue_free()
	await process_frame
	await create_timer(0.3,true,false,true).timeout
	game.Game_Settings = saved
	game.now_stop_state = stopped
	print("HAOCHEN checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
