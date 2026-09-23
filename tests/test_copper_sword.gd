extends "res://tests/test_mc16_spider_drowned.gd"
## Real World + real hurtboxes. No mock damage or cone-only collision checks.
const COPPER_PATH:String = "res://scenes/characters/我的世界/铜剑.tscn"
func copper(point:Vector2) -> Node2D:
	var unit:Node2D = spawn(COPPER_PATH,point)
	unit.Can_Attack = true
	unit.Can_Skill = true
	unit.default_properties.Can_Attack = true
	unit.default_properties.Can_Skill = true
	unit.direction = Vector2.RIGHT
	unit.velocity = Vector2.ZERO
	unit._face_right = true
	unit._movement_face_right = true
	unit.set_process(false)
	unit.visual_mob()
	return unit
func has_copper_status(unit:Node) -> bool:
	var panel:Variant = unit.side_status_ui
	return is_instance_valid(panel) and (panel._left_permanent_labels.has("mc_copper_sword") or panel._right_permanent_labels.has("mc_copper_sword"))
func swing(unit:Node,coarse:bool = false) -> bool:
	if not unit.begin_swing(): return false
	var guard:int = 0
	while unit._swing_active and guard<1000:
		unit.advance_swing(unit._swing_duration if coarse else 1.0/120.0)
		guard += 1
	return guard<1000
func clear_cues() -> void:
	for player:Node in get_nodes_in_group("MCNativeSFX"):
		player.stop()
		player.remove_from_group("MCNativeSFX")
		player.queue_free()
func bolts(unit:Node) -> Array[Node]:
	var result:Array[Node] = []
	for child:Node in unit.get_children():
		if child.get_script()==unit.LIGHTNING and not child.is_queued_for_deletion(): result.append(child)
	return result

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(75.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3).timeout
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"resource preloads complete")
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var unit:Node2D = copper(center)
	var target:Node2D = dummy(center+Vector2(18,0))
	var friend:Node2D = dummy(center+Vector2(18,0),"Team0")
	var rear:Node2D = dummy(center+Vector2(-100,0))
	await physics_frame
	await process_frame
	check(unit.mc_live() and unit.can_act(),"copper sword is in active combat")
	check(is_equal_approx(unit.current_swing_duration(),0.44) and is_equal_approx(unit.Attack_Cooling,0.44),"faster initial swing and scene cooldown are synchronized at 0.44s")
	check(is_equal_approx(unit.initial_raise_duration,0.07),"first raise is shortened to 0.07s")
	for part:NodePath in [NodePath("CollisionShape2D"),NodePath("hitbox/CollisionShape2D"),NodePath("hurtbox/CollisionShape2D")]:
		var collider:CollisionShape2D = unit.get_node(part)
		var shape:CapsuleShape2D = collider.shape as CapsuleShape2D
		check(shape!=null and is_equal_approx(shape.radius,11.25) and is_equal_approx(shape.height,63.75),"body/hit/hurt use narrow sword-grip capsules: "+str(part))
	var reference_edge:float = unit.WEAPON_SIZE.visible_long_edge(unit.WEAPON_SIZE.REFERENCE_TEXTURE)*unit.WEAPON_SIZE.REFERENCE_SPRITE_SCALE
	var unchanged_scale:Vector2 = Vector2.ONE*(reference_edge/unit.WEAPON_SIZE.visible_long_edge(unit.SWORD))
	check(unit.image.scale.is_equal_approx(unchanged_scale),"grip collider does not shrink sword art or weapon-sweep scale")
	world._ensure_character_path_index()
	check(world._character_paths_by_folder.get("我的世界",{}).get("铜剑","")==COPPER_PATH,"registered in the Minecraft character partition")
	check(unit.get_preview_texture().resource_path.ends_with("copper_sword/copper_sword.png"),"menu uses actual vanilla copper sword")
	check(FileAccess.get_sha256("res://Images/characters/我的世界/copper_sword/copper_sword.png")=="a244ad9554b36ad31ad65b12ef0300de5e762ac7271447191e71e2955fe634dc","official copper-sword PNG is byte-identical")
	check(not unit.Has_Collision_Damage and not unit.self_hitbox.monitoring,"no passive body-contact damage")
	check(unit.Hit_Audio.is_empty() and unit.Dead_Audio.is_empty() and unit.Collide_Audio_Node.is_empty(),"generic non-Minecraft character cues disabled")
	check(unit.Unique_Death_Audio==unit.AUDIO.EVENTS["entity.item.break"][0].stream,"death uses native item break audio")
	check(unit._has_swing_target(),"AI sees an actually reachable hurtbox")
	var friend_hp:float = friend.health
	var rear_hp:float = rear.health
	var previous_duration:float = INF
	for i:int in range(6):
		var hp:float = target.health
		var moving:Vector2 = unit.direction
		var before_velocity:Vector2 = unit.velocity
		var down:bool = unit._next_swing_down
		check(swing(unit),"swing completes "+str(i+1))
		check(unit._swing_down==down and unit._next_swing_down!=down,"upper/lower windup alternates "+str(i+1))
		check(is_equal_approx(hp-target.health,ceilf(unit.attack_damage())),"one damage application per target per swing "+str(i+1))
		check(unit.combo_hits==i+1 and unit._swing_duration<previous_duration,"successive landed swings accelerate "+str(i+1))
		check(unit.direction==moving and unit.velocity==before_velocity,"attack does not steer movement "+str(i+1))
		previous_duration = unit._swing_duration
	check(friend.health==friend_hp and rear.health==rear_hp,"allies and distant rear enemies are not struck")
	unit.combo_hits = 999
	check(is_equal_approx(unit.attack_speed(),unit.maximum_attack_speed),"combo speed has a finite cap")
	var hp:float = target.health
	check(swing(unit,true) and is_equal_approx(hp-target.health,ceilf(unit.attack_damage())),"coarse timestep/high-speed swing still sweeps thin geometry exactly once")

	# A miss breaks the chain, even when friendly hurtboxes remain in reach.
	target.global_position = center+Vector2(350,200)
	await physics_frame
	await process_frame
	check(swing(unit) and unit.combo_hits==0 and is_equal_approx(unit.attack_speed(),1.0),"miss resets combo and speed")
	unit.combo_hits = 4
	unit._combo_left = 0.05
	unit.step_mob(0.1)
	check(unit.combo_hits==0,"idle gap also breaks the chain")
	unit._advance_return(unit.return_duration)
	unit.direction = Vector2.LEFT
	unit._update_movement_facing()
	unit.visual_mob()
	check(unit.is_character_visual_flipped_h(),"moving left mirrors the sword")
	unit.direction = Vector2.UP
	unit._update_movement_facing()
	check(not unit._face_right,"vertical movement retains last horizontal facing")
	unit.direction = Vector2.RIGHT
	unit._update_movement_facing()
	unit.visual_mob()
	check(not unit.is_character_visual_flipped_h(),"moving right restores normal facing")
	target.global_position = center+Vector2(18,0)
	await physics_frame
	await process_frame
	unit.player_control_peer_id = 1
	unit.player_control_direction = Vector2.LEFT
	unit.player_control_aim_valid = true
	unit.player_control_aim_position = unit.global_position+Vector2(-200,0)
	var saved_direction:Vector2 = unit.direction
	unit.player_control_action(0)
	check(unit._swing_active and unit._face_right and unit.direction==saved_direction,"manual attack faces the enemy without changing opposite movement input")
	unit.cancel_swing()
	unit.player_control_peer_id = 0
	unit._update_movement_facing()
	unit.rust = 0.4
	unit.charged_left = 2.0
	unit.combo_hits = 2
	unit._combo_left = 0.8
	game.now_stop_state = true
	unit.step_mob(20.0)
	check(unit.rust==0.4 and unit.charged_left==2.0 and unit.combo_hits==2 and unit._combo_left==0.8,"pause freezes oxidation, charge and combo clocks")
	check(not unit.begin_swing(),"pause rejects new attacks")
	game.now_stop_state = false
	unit.dizziness = true
	check(not unit.begin_swing(),"stun prevents attacks")
	unit.step_mob(0.1)
	check(unit.combo_hits==0 and unit.rust>0.4,"stun breaks combo but passive oxidation continues")
	unit.dizziness = false
	unit.Can_Attack = false
	check(not unit.begin_swing(),"Can_Attack restriction respected")
	unit.Can_Attack = true
	unit.Can_Skill = false
	var old_rust:float = unit.rust
	unit._advance_rust(20.0)
	check(unit.rust==old_rust,"Can_Skill restriction prevents oxidation/cleansing triggers")
	unit.Can_Skill = true
	unit.apply_damage_disable(5.0)
	check(not unit.begin_swing(),"shared damage-disable status rejects attacks")
	unit._advance_rust(20.0)
	check(unit.rust==old_rust,"shared damage-disable status prevents passive lightning bypass")
	unit._damage_output_disabled_until_msec = 0

	# A terrain wall blocks the actual melee path; broad body radii cannot hit through it.
	target.global_position = center+Vector2(22,0)
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var wall_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(3,90)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	world.add_child(wall)
	wall.global_position = center+Vector2(9,0)
	unit.charged_left = 0.0
	await physics_frame
	await process_frame
	hp = target.health
	check(swing(unit) and target.health==hp,"melee cannot damage through terrain")
	unit.cancel_swing()
	unit._advance_return(unit.return_duration)
	wall.queue_free()
	clear_cues()
	await physics_frame
	await process_frame

	# Fully green sword stays rusty throughout the warning, then cleanses at IMPACT.
	unit.rust = 0.99
	unit.charged_left = 0.0
	unit._advance_rust(unit.rust_duration*0.02)
	var cleanse:Node = unit._cleanse_effect
	check(is_instance_valid(cleanse) and cleanse.get_script()==unit.LIGHTNING,"cleansing instantiates exact drowned trident lightning script")
	cleanse.set_process(false)
	check(unit.rust==1.0 and unit.charged_left==0.0 and unit._cleanse_pending,"full oxidation waits for lightning impact before clearing")
	var count:int = unit.lightning_count
	unit._advance_rust(10.0)
	check(unit.lightning_count==count,"only one cleansing strike may be pending")
	unit.global_position = center+Vector2(30,0)
	target.global_position = unit.global_position+Vector2(18,0)
	friend.global_position = unit.global_position+Vector2(18,0)
	await physics_frame
	await process_frame
	hp = target.health
	friend_hp = friend.health
	var own_hp:float = unit.health
	cleanse._process(unit.lightning_warning*0.5)
	check(not cleanse._impact_started and unit.rust==1.0 and target.health==hp,"warning is not early damage or early rust reset")
	check(cleanse.global_position.is_equal_approx(unit.global_position),"self strike follows moving sword before impact")
	game.now_stop_state = true
	var elapsed:float = cleanse._elapsed
	cleanse._process(5.0)
	check(cleanse._elapsed==elapsed,"shared trident bolt freezes while paused")
	game.now_stop_state = false
	cleanse._process(unit.lightning_warning*0.5+0.01)
	check(unit.cleanse_count==1 and unit.rust==0.0 and unit.charged_left==unit.charged_duration,"actual strike clears rust and grants timed charge")
	check(is_equal_approx(hp-target.health,ceilf(unit.attack_damage()*unit.lightning_damage_ratio)) and target.dizziness,"cleansing lightning damages and stuns an enemy")
	check(unit.health==own_hp and friend.health==friend_hp,"self-cleanse and lightning do not harm caster/allies")
	check(unit.native_feedback.played.get("item.trident.thunder",0)>0,"actual native trident thunder feedback emitted")
	check(unit.native_feedback.played.get("block.enchantment_table.use",0)>0,"native enchantment audio emitted")
	hp = target.health
	cleanse._process(0.1)
	check(target.health==hp and unit.cleanse_count==1,"second visual flash cannot repeat damage or cleansing")
	unit._advance_rust(1.0)
	check(unit.rust>0.0 and unit.charged_left>0.0,"oxidation starts again even during temporary charge")
	unit.visual_mob()
	unit.charge_visual.advance(0.1)
	check(unit.charge_visual.visible and unit.charge_visual.get_script().get_base_script().resource_path.ends_with("trident_charge_visual.gd"),"charged effect inherits actual drowned-trident arcs")
	check(unit.charge_visual.glint_material.shader==unit.charge_visual.GLINT and unit.charge_visual.overlay.texture==unit.SWORD,"same native glint shader follows sword alpha")
	unit._face_right = false
	unit.visual_mob()
	unit.charge_visual.advance(0.0)
	check(unit.charge_visual.global_transform.determinant()<0.0,"charged mask mirrors with movement exactly once")
	unit._face_right = true
	unit.direction = Vector2.RIGHT
	for effect:Node in bolts(unit): effect.queue_free()
	await process_frame

	# Electrified MELEE creates a single extra bolt, and the bolt cannot proc itself.
	unit.reset_combo()
	# Let the first real stun release its counted control lock. Writing dizziness
	# directly would desynchronize the public stun pipeline and invalidate this test.
	await create_timer(unit.lightning_stun+0.25).timeout
	check(not target.dizziness,"first lightning stun expires before testing a fresh hit stun")
	hp = target.health
	count = unit.lightning_count
	check(swing(unit),"electrified melee swing completes")
	check(unit.lightning_count==count+1 and is_equal_approx(hp-target.health,ceilf(unit.attack_damage())),"charged melee schedules one extra bolt per actual target hit")
	var hit_bolts:Array[Node] = bolts(unit)
	check(hit_bolts.size()==1,"one hit bolt, no per-frame duplicate storms")
	if not hit_bolts.is_empty():
		var strike:Node = hit_bolts[0]
		strike.set_process(false)
		var contact:Vector2 = strike.global_position
		unit.global_position += Vector2(160,0)
		hp = target.health
		strike._process(unit.hit_lightning_warning+0.01)
		check(strike.fixed_impact and strike.global_position==contact,"hit lightning stays at contact rather than following caster")
		check(is_equal_approx(hp-target.health,ceilf(unit.attack_damage()*unit.hit_lightning_damage_ratio)),"charged hit bolt extra damage: actual=%s expected=%s" % [hp-target.health,ceilf(unit.attack_damage()*unit.hit_lightning_damage_ratio)])
		check(target.dizziness and target._stun_visual_ref_count>0,"charged hit bolt acquires a fresh real stun lock and visual")
		check(unit.lightning_count==count+1 and unit.combo_hits==1,"lightning cannot recursively create lightning or farm combo stacks")
	unit.step_mob(unit.charged_left+0.01)
	unit.visual_mob()
	unit.charge_visual.advance(0.0)
	check(unit.charged_left==0.0 and not unit.charge_visual.visible,"timed enchantment and all attached arcs expire")

	# Replica state is presentation-only, even if gameplay entry points are called.
	var replica:Node2D = copper(center+Vector2(350,-160))
	replica.set_multiplayer_authority(2)
	replica.accept_visual(unit.network_visual_state())
	old_rust = replica.rust
	hp = target.health
	replica.step_mob(60.0)
	replica._on_lightning_impact(target.global_position,true)
	check(not replica.begin_swing() and replica.rust==old_rust and target.health==hp,"non-authority replicas cannot attack, advance skill or deal lightning damage")
	check(not replica.get_armor_test_effect_summary().is_empty(),"character mechanic summary available")
	unit.health = 0
	count = unit.lightning_count
	unit._advance_rust(100.0)
	check(unit.lightning_count==count and not unit.begin_swing(),"dead sword cannot oxidize into new lightning or attack")
	unit.Die()
	check(bolts(unit).is_empty() and unit.charged_left==0.0,"death cleans pending lightning and enchantment")
	print("COPPER_SWORD_TEST checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
