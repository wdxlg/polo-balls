extends "res://tests/test_mc16_native_feedback.gd"
var camera:Camera2D
func bolts(spear:Node) -> Array[Node]:
	var result:Array[Node] = []
	for child:Node in spear.get_children():
		if child.has_signal("impact_started"): result.append(child)
	return result
func capture(tag:String,point:Vector2) -> void:
	if not "--capture" in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless": return
	camera.global_position = point
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/mc16_charged_"+tag+".png")
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(65.0).timeout.connect(func(): finish(2))
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
	camera = Camera2D.new()
	world.add_child(camera)
	camera.zoom = Vector2(5.0,5.0)
	camera.make_current()
	var owner:Node = spawn("res://scenes/characters/我的世界/溺尸.tscn",center)
	var target:Node = dummy(center+Vector2(210,0))
	var friend:Node = dummy(target.global_position+Vector2(0,30),"Team0")
	var far:Node = dummy(target.global_position+Vector2(0,220))
	owner.native_feedback.set_physics_process(false)
	await process_frame
	await process_frame
	owner.mc_native_animation.set_process(false)
	var spear:Node = owner._trident
	var fx:Node = spear.charge_visual
	check(owner.trident_damage_ratio==0.5,"direct thrown damage reduced by exactly fifty percent")
	check(owner.impact_lightning_damage_ratio==0.7 and owner.impact_lightning_stun==0.3,"contact bolt damage reduced thirty percent; stun unchanged")
	check(owner.lightning_damage_ratio==1.4 and owner.lightning_stun==0.65,"periodic lightning damage reduced thirty percent; stun unchanged")
	check(not fx.visible,"uncharged trident has no enchantment or electric arcs")
	var hp:float = target.health
	owner.throw_trident(target)
	owner._advance_trident_throw(owner.trident_throw_windup+0.01)
	spear.advance(2.0)
	check(hp-target.health==ceilf(owner.attack_damage()*0.5),"real uncharged sweep deals half-strength direct damage")
	check(bolts(spear).is_empty(),"uncharged hit cannot summon a contact bolt")
	spear.advance(2.0)
	check(owner.has_trident and hp-target.health==ceilf(owner.trident_hit_damage()),"uncharged return still cannot deal a second hit")
	spear.charge()
	check(fx.visible and fx._tex_key!="free","held charge uses exact native bone-frame mask")
	check(owner.hand_visual.LAYERS.TRACKS.size()==8,"independent native item layers cover all eight animated poses")
	check(FileAccess.get_sha256("res://Images/characters/我的世界/native_frames/trident_masks/enchanted_item_glint.png")=="99cf0defcbe422c8b91a42886f469d89cfbaba157371d8142d01ba7e8055a631","enchantment uses byte-exact Mojang glint texture")
	check(fx.overlay.material is ShaderMaterial and fx._arcs.size()==2,"enchantment animation and branched shaft arcs are both active")
	await capture("held_a",owner.global_position)
	var initial_arcs:Array = fx._arcs.duplicate(true)
	spear.advance(0.35)
	check(fx._arcs!=initial_arcs,"shaft electricity reroutes rather than orbiting in fixed rings")
	await capture("held_b",owner.global_position)
	owner.mc_native_animation.advance(0.18)
	fx._process(0.0)
	check(fx._tex_key==str(owner.mc_native_animation.current_clip)+":"+str(owner.mc_native_animation.frame_index) and fx.overlay.texture==owner.hand_visual.weapon.texture,"held enchantment resyncs in the same rendered native animation frame")
	var old_transform:Transform2D = fx.global_transform
	owner._visual_facing_flipped_h = not owner._visual_facing_flipped_h
	owner.hand_visual.sync_pose()
	spear.advance(0.01)
	# Grip tracking may rotate the mirrored item; handedness is the determinant.
	check(fx.global_transform.determinant()*old_transform.determinant()<0.0 and fx.global_transform.is_equal_approx(owner.hand_visual.weapon.global_transform),"held mask and electricity mirror with native character facing")
	owner._visual_facing_flipped_h = not owner._visual_facing_flipped_h
	var glint_time:float = spear._clock
	var routes:int = fx.reroutes
	game.now_stop_state = true
	spear.advance(5.0)
	check(spear._clock==glint_time and fx.reroutes==routes,"pause freezes native glint and arc rerouting")
	game.now_stop_state = false
	hp = target.health
	var ally_hp:float = friend.health
	var far_hp:float = far.health
	var own_hp:float = owner.health
	fresh(owner)
	owner.throw_trident(target)
	owner._advance_trident_throw(owner.trident_throw_windup+0.01)
	spear.advance(0.3)
	check(fx.visible and fx._tex_key=="free" and fx.overlay.texture==spear.TEXTURE,"flying trident uses the same glint on its own item silhouette")
	await capture("flying",spear.global_position)
	spear.advance(1.7)
	var lightning:Array[Node] = bolts(spear)
	check(lightning.size()==1 and not lightning[0]._impact_started and lightning[0].fixed_impact,"first charged enemy hit starts one fixed-point warning")
	var bolt:Node = lightning[0]
	bolt.set_process(false)
	var hit_point:Vector2 = bolt.global_position
	check(owner.impact_lightning_warning==0.15 and bolt.warning_delay==0.15,"contact lightning uses the selected 0.15 second warning")
	check(hp-target.health==ceilf(owner.trident_hit_damage()),"direct hit stays immediate without premature lightning damage")
	check(count(owner,"entity.lightning_bolt.thunder")==1 and count(owner,"entity.generic.explode")==0 and count(owner,"item.trident.thunder")==0,"Creeper warning thunder plays before either impact sound")
	spear.advance(0.1)
	bolt._process(0.14)
	check(not bolt._impact_started and hp-target.health==ceilf(owner.trident_hit_damage()) and bolt.global_position==hit_point,"warning holds the collision point while returning trident moves away")
	game.now_stop_state = true
	bolt._process(1.0)
	check(not bolt._impact_started,"pause cannot consume the contact warning or deal its deferred damage")
	game.now_stop_state = false
	bolt._process(0.02)
	check(bolt.impact_ring_radius()==owner.lightning_radius,"first actual impact frame ring exactly equals the attack radius even after time-step overshoot")
	check(hp-target.health==ceilf(owner.trident_hit_damage())+ceilf(owner.attack_damage()*0.7),"charged hit applies unchanged direct damage plus reduced contact lightning")
	check(target.dizziness,"charged contact bolt actually stuns the victim")
	check(friend.health==ally_hp and owner.health==own_hp and far.health==far_hp,"contact bolt preserves team immunity and radius limit")
	check(count(owner,"item.trident.thunder")==1 and count(owner,"entity.generic.explode")==1,"actual impact layers native Creeper impact sound and retained trident thunder once")
	await capture("impact",hit_point)
	hp = target.health
	spear._charged_contact()
	bolt._start_impact()
	spear.advance(2.0)
	bolt._process(0.01)
	check(target.health==hp and count(owner,"item.trident.thunder")==1,"return, repeated contact and repeated impact cannot add another bolt or damage")
	check(bolt.global_position.is_equal_approx(hit_point),"contact bolt never follows returning trident back to owner")
	await create_timer(0.38).timeout
	check(not target.dizziness,"short contact stun expires instead of using periodic 0.65 second stun")
	for effect:Node in bolts(spear): effect.queue_free()
	await process_frame
	# A genuine static obstacle wins the sweep before the distant target.
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12,160)
	shape.shape = rect
	wall.add_child(shape)
	world.add_child(wall)
	wall.global_position = owner.global_position+Vector2(105,0)
	target.global_position = owner.global_position+Vector2(260,0)
	var splash:Node = dummy(wall.global_position+Vector2(-22,32))
	await physics_frame
	hp = target.health
	var splash_hp:float = splash.health
	# Avoid placing the splash victim directly on the incoming sweep.
	splash.global_position.y += 20.0
	owner.throw_trident(target)
	owner._advance_trident_throw(owner.trident_throw_windup+0.01)
	spear.advance(2.0)
	lightning = bolts(spear)
	check(spear.flight_state==3 and is_instance_valid(spear.wall_ref.get_ref()),"charged projectile actually lodges in the obstacle")
	check(lightning.size()==1 and not lightning[0]._impact_started,"charged obstacle collision starts one short lightning warning")
	check(target.health==hp and splash.health==splash_hp,"obstacle blocks direct damage and its lightning does not hurt before warning")
	lightning[0].set_process(false)
	lightning[0]._process(owner.impact_lightning_warning+0.01)
	check(splash_hp-splash.health==ceilf(owner.attack_damage()*0.7) and splash.dizziness,"obstacle contact bolt deals reduced area damage and unchanged short stun")
	check(fx.visible and fx._tex_key=="free","lodged charged trident retains enchanted moving texture")
	spear.advance(owner.lightning_first_delay+0.01)
	var periodic:Node
	for effect:Node in bolts(spear):
		if not effect.fixed_impact: periodic = effect
	check(is_instance_valid(periodic) and not periodic._impact_started,"contact bolt does not replace later periodic warning")
	periodic.set_process(false)
	splash_hp = splash.health
	periodic._process(owner.lightning_warning+0.01)
	check(splash_hp-splash.health==ceilf(owner.attack_damage()*1.4),"periodic bolt uses the reduced stronger lightning multiplier")
	# Empty range completion is not a collision; a new launch resets the guard.
	var empty:Node = owner._create_trident(900)
	empty.set_physics_process(false)
	empty.charge()
	var saved_range:float = owner.trident_range
	owner.trident_range = 80.0 # Stay inside the real map: 600 units may reach its boundary.
	empty.launch(Vector2.UP)
	empty.advance(owner.trident_range/owner.trident_speed+0.1)
	owner.trident_range = saved_range
	check(empty.traveled>=80.0-0.001 and empty.flight_state==3 and empty.planted,"charged range miss plants itself in the ground after its full range")
	check(empty.wall_ref==null and owner._trident==null,"a planted miss has no support and does not re-arm the hand slot")
	check(bolts(empty).is_empty(),"an empty range completion still invents no impact bolt")
	empty.launch(Vector2.DOWN)
	check(not empty._impact_emitted,"each fresh throw resets its first-impact guard")
	owner.set_multiplayer_authority(2)
	var before:int = bolts(empty).size()
	empty._charged_contact()
	check(bolts(empty).size()==before,"non-authority replica cannot originate a damaging contact bolt")
	owner.set_multiplayer_authority(1)
	owner.health = 0
	spear.advance(0.01)
	check(spear.is_queued_for_deletion(),"permanent charged item still cleans up when owner dies")
	print("MC16_CHARGED_IMPACT_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
