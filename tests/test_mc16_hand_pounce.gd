extends "res://tests/test_mc16_native_feedback.gd"
var camera:Camera2D
var caption:Label
var shot:int = 0
var focus_actor:Node2D
var focus_offset:Vector2 = Vector2(0,-4)
func capture(label:String,seconds:float = 0.08) -> void:
	if not "--capture" in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless": return
	caption.text = label
	if is_instance_valid(focus_actor):
		camera.global_position = focus_actor.global_position+focus_offset
		camera.force_update_scroll()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/mc16_hand_pounce_%03d.png" % shot)
	var f := FileAccess.open("res://tests/mc16_hand_pounce_frames.txt",FileAccess.READ_WRITE if shot>0 else FileAccess.WRITE)
	f.seek_end()
	f.store_line("%03d %.3f" % [shot,seconds])
	f.close()
	shot += 1
func run() -> void:
	game = root.get_node("Game")
	var drowned_scene:PackedScene = load("res://scenes/characters/我的世界/溺尸.tscn")
	var spider_scene:PackedScene = load("res://scenes/characters/我的世界/蜘蛛.tscn")
	check(drowned_scene!=null and spider_scene!=null,"native scenes load before background world workers")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(85.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	if not await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self):
		finish(1)
		return
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	geometry = load("res://scripts/effects/我的世界/mc16_geometry.gd")
	var owner:Node = spawn("res://scenes/characters/我的世界/溺尸.tscn",center+Vector2(-180,0))
	var spider:Node = spawn("res://scenes/characters/我的世界/蜘蛛.tscn",center+Vector2(250,120))
	var target:Node = dummy(center+Vector2(200,0))
	await process_frame
	await process_frame
	for actor:Node in [owner,spider]:
		actor.native_feedback.set_physics_process(false)
		actor.mc_native_animation.set_process(false)
	owner.hand_visual.set_process(false)
	camera = Camera2D.new()
	world.add_child(camera)
	camera.zoom = Vector2(40,40)
	camera.global_position = owner.global_position+Vector2(0,-4)
	focus_actor = owner
	camera.make_current()
	camera.force_update_scroll()
	world.get_node("CanvasLayer").hide()
	for actor:Node in [owner,spider,target]:
		for control:Node in actor.find_children("*","Control",true,false): control.hide()
	if "--capture" in OS.get_cmdline_user_args():
		RenderingServer.set_default_clear_color(Color(0.10,0.12,0.15))
		for child:Node in world.get_children():
			if child is CanvasItem and child!=camera:
				if child is Node2D and child in units: continue
				child.hide()
	var ui := CanvasLayer.new()
	ui.layer = 1000
	world.add_child(ui)
	caption = Label.new()
	caption.position = Vector2(35,40)
	caption.size.x = root.get_visible_rect().size.x-70.0
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_size_override("font_size",48)
	ui.add_child(caption)
	var a:Node = owner.mc_native_animation
	var hand:Node = owner.hand_visual
	var spear:Node = owner._trident
	hand.sync_pose()
	check(hand.visible and not hand.is_ghost and hand.opacity==1.0,"equipped native trident is visible in the hand")
	check(owner.image.texture==hand.record.body and hand.weapon.texture==hand.record.item,"body-only frame plus a separate native rightItem layer")
	check(spear.DRAW_SIZE==18.0,"flying and lodged item shrunk another 25 percent")
	check(hand.weapon.to_global(hand.record.grip).distance_to(owner.trident_hand_position())<0.1,"native hand grip anchors the separate item exactly")
	check(not hand.is_in_group("MCTrident") and not hand.is_in_group("MCUnenchantedTrident"),"presentation layer is not an extra real weapon")
	await capture("Native hand-held trident / smaller size",0.5)
	var image:Texture2D = hand.weapon.texture
	owner.global_position.x += 8.0
	a.advance(0.12)
	hand.sync_pose()
	check(a.current_clip==&"walk" and image!=hand.weapon.texture,"held weapon follows animated native arm bones")
	owner.set_character_visual_flip_h(not owner._visual_facing_flipped_h)
	hand.sync_pose()
	check(hand.weapon.to_global(hand.record.grip).distance_to(owner.trident_hand_position())<0.1,"mirrored facing retains exact hand attachment")
	owner.set_character_visual_flip_h(not owner._visual_facing_flipped_h)
	a.advance(0.3)
	check(owner.throw_trident(target),"initial throw has no refill presentation delay")
	check(not hand.visible and not owner.has_trident,"throw immediately removes the hand item")
	check(a.current_clip==&"throw_empty","native release animation has an empty body layer")
	spear.global_position = owner.global_position+Vector2(70,-15)
	await capture("Thrown: the hand is empty",0.5)
	spear.stick(owner.global_position+Vector2(90,-10))
	a.advance(0.31)
	hand.sync_pose()
	check(hand.is_ghost and hand.opacity==0.0 and owner._trident==null,"wall lodging begins a zero-opacity hand ghost")
	var real_count:int = get_nodes_in_group("MCTrident").size()
	for left:float in [2.4,1.8,1.2,0.6,0.001]:
		owner._refill_left = left
		hand.sync_pose()
		check(is_equal_approx(hand.opacity,1.0-left/2.4),"ghost opacity follows real refill progress: "+str(left))
	check(get_nodes_in_group("MCTrident").size()==real_count and owner._tridents.size()==1,"ghost creates no projectile or electric-network endpoint")
	var enchants:int = count(owner,"block.enchantment_table.use")
	owner.ENCHANTMENT.in_radius(owner,owner.trident_hand_position(),5.0)
	check(owner._trident==null and count(owner,"block.enchantment_table.use")==enchants,"lightning cannot enchant a not-yet-restored ghost")
	owner._refill_left = 1.2
	game.now_stop_state = true
	owner.tick_physics(owner.state_machine.current_state,3.0)
	hand.sync_pose()
	check(owner._refill_left==1.2 and is_equal_approx(hand.opacity,0.5),"pause freezes real recovery and ghost opacity together")
	game.now_stop_state = false
	# Deterministic GPU review of the complete fade-in, without inventing extra items.
	for i:int in range(31):
		owner._refill_left = 2.4*(1.0-float(i)/30.0)
		a.advance(0.08)
		hand.sync_pose()
		await capture("Lodged: restoring hand ghost %d%%" % int(round(hand.opacity*100)),0.08)
	fresh(owner)
	owner._new_trident()
	var restored:Node = owner._trident
	restored.set_physics_process(false)
	hand.sync_pose()
	check(hand.opacity==1.0 and not hand.is_ghost and owner.has_trident,"100 percent replaces the ghost with the real held item")
	check(is_equal_approx(restored.refill_scale(),1.45) and restored.refill_flash()==1.0,"refill completion instantly enlarges and flashes the trident white")
	check(hand.weapon.to_global(hand.record.grip).distance_to(owner.trident_hand_position())<0.1,"pop scales around the grip rather than shifting out of the hand")
	check(count(owner,"entity.experience_orb.pickup")==1 and count(owner,"entity.item.pickup")==0,"replacement plays native XP ding instead of the old pickup pop")
	owner._new_trident()
	check(count(owner,"entity.experience_orb.pickup")==1,"duplicate refill cannot replay ding or spawn another held weapon")
	check(not owner.throw_trident(target) and is_equal_approx(owner._refill_show_left,0.2),"new replacement is shown for 0.2 seconds before throwing")
	var stream:AudioStream = owner.native_feedback.BANK.EVENTS["entity.experience_orb.pickup"][0]
	check(stream is AudioStreamOggVorbis and stream.get_length()>0.0,"official XP orb OGG imports and decodes")
	game.now_stop_state = true
	restored.advance(0.5)
	check(restored._refill_pop_time==0.0,"pause also freezes white flash and elastic pop")
	game.now_stop_state = false
	var undershoot:bool = false
	for i:int in range(18):
		hand.sync_pose()
		undershoot = undershoot or restored.refill_scale()<1.0
		await capture("Restored: white flash + elastic size recovery",0.02)
		restored.advance(0.02)
	check(restored.refill_flash()==0.0 and restored.refill_scale()==1.0 and undershoot,"white quickly clears; size crosses below one then settles exactly")
	owner.tick_physics(owner.state_machine.current_state,0.199)
	check(owner.has_trident and not owner.throw_trident(target),"replacement cannot leave before the 0.2-second display boundary")
	owner.tick_physics(owner.state_machine.current_state,0.002)
	check(not owner.has_trident and restored.flight_state==1,"normal automatic throw resumes after the display window")
	restored._begin_return()
	restored.advance(1.0)
	hand.sync_pose()
	check(owner.has_trident and hand.visible and count(owner,"entity.experience_orb.pickup")==1,"return restores hand display without replaying replacement ding")
	# Replica receives ghost progress and pop age, but never originates item/audio.
	var replica:Node = spawn("res://scenes/characters/我的世界/溺尸.tscn",center+Vector2(-400,350))
	await process_frame
	await process_frame
	replica.native_feedback.set_physics_process(false)
	replica.set_multiplayer_authority(2)
	replica._sync_tridents([],1.2,0.0)
	replica.hand_visual.sync_pose()
	check(replica.hand_visual.is_ghost and is_equal_approx(replica.hand_visual.opacity,0.5),"replica receives recovery progress without a phantom held item")
	replica.hand_visual._process(0.12)
	check(replica._refill_left<1.2 and replica._trident==null,"replica smoothly interpolates presentation only")
	var data:Dictionary = restored.snapshot()
	data.refill_pop_time = 0.04
	replica._sync_tridents([data],-1.0,0.16)
	check(replica.has_trident and replica.hand_visual.visible and not replica.hand_visual.is_ghost,"replica snapshot replaces ghost with the actual equipped item")
	check(is_equal_approx(replica._trident._refill_pop_time,0.04) and count(replica,"entity.experience_orb.pickup")==0,"replicated pop age does not re-trigger local sound")
	replica.health = 0
	replica.hand_visual.sync_pose()
	check(not replica.hand_visual.visible,"death hides even a top-level hand presentation")
	# Actual spider lunge/impact drives bone actions; long flight does not freeze.
	var sa:Node = spider.mc_native_animation
	target.global_position = spider.global_position+Vector2(300,0)
	check(spider.hunt_web_target(target),"real web hunt begins a pounce")
	sa.advance(0.02)
	check(sa.current_clip==&"lunge","pounce begins with the native-model takeoff pose")
	check(spider._visual_facing_flipped_h,"takeoff faces the target even before the first movement tick")
	spider.tick_physics(spider.state_machine.current_state,0.15)
	sa.advance(0.02)
	check(sa.current_clip==&"lunge_air" and sa.frames.get_animation_loop(&"lunge_air"),"flight transitions to a looping articulated air pose")
	var unique:Dictionary = {}
	for i:int in range(25):
		sa.advance(0.04)
		unique[sa.sprite.texture.resource_path] = true
	check(unique.size()>8,"airborne head, abdomen and legs continue animating beyond the old 0.28-second freeze")
	var before:float = sa.clip_time
	game.now_stop_state = true
	sa.advance(0.3)
	check(sa.clip_time==before,"pause freezes the new spider bone animation")
	game.now_stop_state = false
	target.global_position = spider.global_position+Vector2(15,0)
	var hp:float = target.health
	spider._try_lunge_hit(target)
	check(spider._lunge_hit and hp-target.health==ceilf(spider.attack_damage()*spider.lunge_damage_ratio),"pounce still deals its original single hit")
	check(sa.current_clip==&"attack","successful pounce contact immediately selects striking/bite bones")
	spider.direction = Vector2.LEFT # Simulate contact bounce without turning the bite away.
	var hit_frame:Texture2D = spider.image.texture
	sa.advance(0.12)
	check(spider.image.texture!=hit_frame,"hit animation visibly changes articulated native pixels")
	check(spider._visual_facing_flipped_h and spider.direction==Vector2.LEFT,"bite keeps facing the struck target without changing physical bounce direction")
	spider._try_lunge_hit(target)
	check(hp-target.health==ceilf(spider.attack_damage()*spider.lunge_damage_ratio),"animated striking never adds a second damage event")
	sa.advance(0.3)
	check(sa.current_clip==&"idle","hit action finishes back at idle")
	sa._on_contact_attack(null)
	check(sa.current_clip==&"attack","ordinary contact attacks also have the native-model hit action")
	sa.advance(0.3)
	spider._end_lunge()
	check(sa.current_clip==&"land","miss or wall stop plays a short landing recovery")
	for clip:StringName in [&"lunge",&"lunge_air",&"attack",&"land"]:
		var paths:Dictionary = {}
		var unclipped:bool = true
		for i:int in range(sa.frames.get_frame_count(clip)):
			var texture:Texture2D = sa.frames.get_frame_texture(clip,i)
			paths[texture.resource_path] = true
			var rect:Rect2i = texture.get_image().get_used_rect()
			unclipped = unclipped and rect.position.x>0 and rect.position.y>0 and rect.end.x<160 and rect.end.y<224
		check(paths.size()>1 and unclipped,"articulated, unclipped action frames: "+str(clip))
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
		owner.hide()
		owner.hand_visual.hide()
		restored.hide()
		spear.hide()
		spider.global_position = center+Vector2(-120,100)
		target.global_position = center+Vector2(150,100)
		camera.global_position = center+Vector2(15,85)
		camera.zoom = Vector2(14,14)
		focus_actor = spider
		focus_offset = Vector2(15,-5)
		camera.force_update_scroll()
		spider._lunge_wait = 0.0
		sa._action_left = 0.0
		spider.hunt_web_target(target)
		for i:int in range(52):
			await physics_frame
			spider.tick_physics(spider.state_machine.current_state,1.0/60.0)
			if spider._lunge_left>0.0: spider.move(spider.Speed,1.0/60.0)
			sa.advance(1.0/60.0)
			camera.global_position = spider.global_position+Vector2(10,-5)
			camera.force_update_scroll()
			await capture("Native spider bones: takeoff / flight / hit (slow replay)",0.04)
		await capture("Native spider: attack completed",0.5)
	print("MC16_HAND_POUNCE_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
