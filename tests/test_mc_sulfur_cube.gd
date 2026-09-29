extends SceneTree
## Real World + two live balls: modes, damage, source textures and threat geometry.
var CUBE
var SCENE:PackedScene
var world:Node
var game:Node
var cube:Node2D
var enemy:Node2D
var ally:Node2D
var saved:Dictionary
var saved_stop:bool
var checks:int = 0
var failures:int = 0

func _initialize() -> void: call_deferred("run")
func check(condition:bool,label:String) -> void:
	checks += 1
	if condition: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func create_fighter(scene:PackedScene,team:String,point:Vector2) -> Node2D:
	var fighter:Node2D = scene.instantiate() as Node2D
	fighter.Team = team
	fighter.position = point
	world.add_child(fighter,true)
	fighter.state_machine.set_physics_process(false)
	fighter.set_physics_process(false)
	fighter.health = fighter.Max_health
	return fighter

func victim_radius(target:Node) -> float:
	# Avoid compiling ball/Game before the autoloads in a --script SceneTree run.
	return maxf(float(target.call("get_crowd_separation_radius_world")),3.0)

func attack_region(unit:Node2D) -> Dictionary:
	var regions:Array = unit.get_ai_attack_threats(enemy)
	return regions[0] as Dictionary if regions.size() == 1 else {}

func native_block_visible(mode:int,source_name:String) -> bool:
	var view:SubViewport = cube.get_node_or_null("SulfurCube3DViewport") as SubViewport
	if view == null or cube.image.texture != view.get_texture(): return false
	var model:Node3D = view.get_node_or_null("SulfurCubeModel") as Node3D
	if model == null or int(model.get("block_mode")) != mode: return false
	var shell:Node3D = model.get_node_or_null("NativeOuterShell") as Node3D
	var gel:Node3D = model.get_node_or_null("NativeInnerGel") as Node3D
	var block:Node3D = model.get_node_or_null("InterchangeableBlock") as Node3D
	if shell == null or gel == null or block == null or shell.get_child_count()!=6 or gel.get_child_count()!=6: return false
	if mode == 0: return gel.visible and not block.visible and block.get_child_count()==0
	# Java 26.2 draws the 16px inner jelly only when no block is absorbed.
	if gel.visible or not block.visible or block.get_child_count()!=6: return false
	var block_quad:QuadMesh = (block.get_child(0) as MeshInstance3D).mesh as QuadMesh
	var inner_quad:QuadMesh = (gel.get_child(0) as MeshInstance3D).mesh as QuadMesh
	if block_quad == null or inner_quad == null or block_quad.size.distance_to(inner_quad.size)>0.001: return false
	var mesh:MeshInstance3D = block.get_child(0) as MeshInstance3D
	var material:StandardMaterial3D = mesh.material_override as StandardMaterial3D
	if material==null or not material.albedo_texture.resource_path.ends_with("/source/"+source_name+".png"): return false
	if mode in [1,6]:
		var top:StandardMaterial3D = (block.get_child(4) as MeshInstance3D).material_override as StandardMaterial3D
		var bottom:StandardMaterial3D = (block.get_child(5) as MeshInstance3D).material_override as StandardMaterial3D
		if top==null or bottom==null: return false
		var top_name:String = "oak_log_top" if mode==1 else "tnt_top"
		var bottom_name:String = "oak_log_top" if mode==1 else "tnt_bottom"
		return top.albedo_texture.resource_path.ends_with("/source/"+top_name+".png") and bottom.albedo_texture.resource_path.ends_with("/source/"+bottom_name+".png")
	return true

func sound_events(event:String) -> Array[Node]:
	var found:Array[Node] = []
	for item:Node in get_nodes_in_group("MCNativeSFX"):
		if str(item.get_meta("mc_sound_event","")) == event: found.append(item)
	return found

func sulfur_events(event:String) -> Array[Node]:
	var found:Array[Node] = []
	for item:Node in get_nodes_in_group("MCNativeSFX"):
		if str(item.get_meta("mc_sulfur_event","")) == event: found.append(item)
	return found

func debug_region(analyzer:Node2D,kind:String) -> Dictionary:
	analyzer._refresh_debug_world()
	for entry:Dictionary in analyzer._debug_threats:
		if entry.get("source") == cube and str(entry.get("kind","")) == kind: return entry
	return {}

func capture(label:String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var picture:Image = root.get_texture().get_image()
	# The 1080x1920 logical canvas is scaled to a 540x960 physical window.
	# Viewport readback is in physical pixels, CanvasItem transforms are logical.
	var physical_scale:Vector2 = Vector2(picture.get_size())/root.get_visible_rect().size
	var on_screen:Vector2i = Vector2i(cube.get_global_transform_with_canvas().origin*physical_scale)
	var visible_area:Rect2i = Rect2i(on_screen-Vector2i(215,215),Vector2i(430,430)).intersection(Rect2i(Vector2i.ZERO,picture.get_size()))
	if visible_area.size.x <= 0 or visible_area.size.y <= 0:
		push_error("Sulfur Cube is offscreen in GPU preview: "+label)
		return
	print("SULFUR_GPU_"+label+"_BASE64=",Marshalls.raw_to_base64(picture.get_region(visible_area).save_png_to_buffer()))
	# Inspect the actual rendered 3D viewport, rather than trusting that six
	# geometry nodes exist while the character remains a hidden/flat image.
	var native_frame:Image = cube._model_viewport.get_texture().get_image()
	print("SULFUR_3D_"+label+"_BASE64=",Marshalls.raw_to_base64(native_frame.save_png_to_buffer()))
	if label in ["empty","wood"]:
		var visible_pixels:int = 0
		for y:int in range(native_frame.get_height()):
			for x:int in range(native_frame.get_width()):
				if native_frame.get_pixel(x,y).a > 0.10: visible_pixels += 1
		check(visible_pixels > 1500,"GPU renders a visible 3D shell from the very first empty state, not only a nominal SubViewport")
	if label == "empty":
		# Transparent inner jelly must NOT paint over the outer face. The eyes
		# are genuine dark pixels on Mojang's front texture, not drawn-on decals.
		var facial_pixels:int = 0
		for y:int in range(40,126):
			for x:int in range(35,136):
				var pixel:Color = native_frame.get_pixel(x,y)
				if pixel.a > 0.4 and maxf(pixel.r,maxf(pixel.g,pixel.b)) < 0.40: facial_pixels += 1
		check(facial_pixels >= 70,"empty GPU frame shows Mojang's original eyes and mouth instead of an opaque faceless jelly")
	if label == "tnt":
		# Check actual framebuffer pixels on the declared 72-world-unit circle,
		# not just that the script's _draw() and danger metadata exist.
		var radius_px:float = CUBE.TNT_RADIUS*3.0*physical_scale.x
		var visible_warning_points:int = 0
		for angle_index:int in range(48):
			var bearing:Vector2 = Vector2.RIGHT.rotated(TAU*float(angle_index)/48.0)
			var visible_at_angle:bool = false
			for radius_offset:int in range(-3,4):
				var point:Vector2i = on_screen+Vector2i(bearing*(radius_px+float(radius_offset)))
				if point.x < 0 or point.y < 0 or point.x >= picture.get_width() or point.y >= picture.get_height(): continue
				var pixel:Color = picture.get_pixelv(point)
				if pixel.r > 0.2 and pixel.r > 1.4*pixel.g and pixel.r > 1.3*pixel.b:
					visible_at_angle = true
					break
			if visible_at_angle: visible_warning_points += 1
		check(visible_warning_points >= 24,"GPU pixels show the TNT warning ring at the real blast radius")

func run() -> void:
	create_timer(55.0,true,false,true).timeout.connect(func(): print("SULFUR_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	CUBE = load("res://scripts/characters/我的世界/硫方怪.gd")
	SCENE = load("res://scenes/characters/我的世界/硫方怪.tscn")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.now_stop_state = false
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Training_Debug_Mode = false
	AudioServer.set_bus_mute(0,true)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.set_process(false)
	world.set_physics_process(false)
	world._ensure_character_path_index()
	if DisplayServer.get_name() != "headless":
		world.now_choose_map = "Map10x10"
		world.refresh_map_presentation()
		world.control.hide()
	var analyzer:Node2D = world.get_node("CombatThreatAnalyzer")
	check(world._character_paths_by_folder.get("我的世界",{}).has("硫方怪"),"scene is selectable in Minecraft category")
	var previous_locale:String = game.current_locale
	game.current_locale = "en"
	check(game.translate_game_text("硫方怪") == "Sulfur Cube" and game.translate_game_text("硫方怪蜂蜜黏滞") == "Sulfur Cube Stickiness","bilingual roster and honeycomb debuff resolve through game's real translation catalog")
	game.current_locale = previous_locale
	var center:Vector2 = world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	if DisplayServer.get_name() != "headless":
		var camera := Camera2D.new()
		world.add_child(camera)
		camera.global_position = center
		camera.zoom = Vector2(3.0,3.0)
		camera.make_current()
	cube = create_fighter(SCENE,"Team0",center)
	enemy = create_fighter(load("res://scenes/ball.tscn"),"Team1",center+Vector2(18,0))
	ally = create_fighter(load("res://scenes/ball.tscn"),"Team0",center+Vector2(-18,0))
	cube.Speed = 0.0 # Manual contact probes, no unrelated movement.
	cube.direction = Vector2.ZERO
	for other:Node2D in [enemy,ally]:
		other.Can_Attack = false
		other.Can_Skill = false
		other.Has_Collision_Damage = false
		other.self_hitbox.monitoring = false
		other.Max_health = 2000
		other.default_properties.Max_health = 2000
		other.health = 2000
	await physics_frame
	check(cube.is_combat_runtime_active() and cube.health > 0,"real World is active with live enemies")
	check(cube.block_mode == CUBE.Block.EMPTY and native_block_visible(CUBE.Block.EMPTY,""),"starts with actual 3D outer/inner vanilla shell and no internal cube")
	check(not cube.Has_Collision_Damage and not cube.self_hitbox.monitoring,"generic hitbox off, no duplicate MC contact hits")
	await capture("empty")
	cube.tick_physics(0,0.68)
	check(cube.block_mode == CUBE.Block.WOOD and native_block_visible(CUBE.Block.WOOD,"oak_log"),"inserts a separate six-sided native oak-log cube into the live 3D shell")
	var appearing_block:Node3D = cube._native_model.inner_block
	var initial_block_scale:float = appearing_block.scale.x
	cube._native_model.animate(0.12,0.12,true,0.0)
	check(appearing_block.scale.x > initial_block_scale and appearing_block.scale.x <= 1.0,"new inner block visibly grows into place rather than swapping the whole character sprite")
	check(cube.collision_shape_2d.shape.radius == CUBE.CONTACT_RADIUS and absf(float(attack_region(cube).get("radius",0.0))-cube.get_crowd_separation_radius_world())<0.01,"wood threat matches actual scaled CircleShape2D rather than its 43 local-unit radius")
	await capture("wood")
	# The native jump/squish clips are this mob's available movement sounds:
	# no step/ambient event exists in the official Java 26.2 sounds.json.
	cube.Can_Attack = false
	cube._hop_timer = -0.01
	cube._previous_motion_position = cube.global_position
	cube.tick_physics(0,0.05)
	check(sulfur_events("jump").is_empty() and sulfur_events("squish").is_empty(),"stationary cube makes no counterfeit footsteps or jump/landing sounds")
	cube._hop_timer = -0.01
	cube._previous_motion_position = cube.global_position-Vector2(1000,0)
	cube.tick_physics(0,0.05)
	check(sulfur_events("jump").is_empty(),"spawn/teleport displacement does not trigger a movement sound")
	cube._hop_timer = -0.01
	cube._previous_motion_position = cube.global_position
	cube.global_position += Vector2(0.7,0)
	cube.tick_physics(0,0.05)
	var native_steps:Array[Node] = sulfur_events("jump")
	check(native_steps.size()==1 and native_steps[0].stream != null,"real position change triggers one original sulfur cube jump sound")
	if native_steps.size()==1:
		var step:AudioStreamPlayer2D = native_steps[0] as AudioStreamPlayer2D
		var effective_rate:float = maxf(step.pitch_scale*AudioServer.playback_speed_scale,0.01)
		var clip_ms:int = ceili(step.stream.get_length()*1000.0/effective_rate)
		check(cube._motion_audio_until_ms-int(cube._sound_time.get(&"jump",0)) >= clip_ms,"movement sound spacing uses selected clip duration and pitch")
		check(not is_instance_valid(cube._emit_sound(&"squish")) and sulfur_events("squish").is_empty(),"landing cannot overlap a still-playing jump variation")
		# Simulate the selected jump clip finishing; test the landing channel
		# deterministically without waiting for the offline engine's audio clock.
		step.stop()
		cube._motion_audio_until_ms = Time.get_ticks_msec()-1
		cube._landing_wait = 0.02
		cube._previous_motion_position = cube.global_position
		cube.global_position += Vector2(0.7,0)
		cube.tick_physics(0,0.05)
		check(sulfur_events("squish").size()==1,"moving cube can play the original landing squish after the previous clip ends")
	cube.global_position = center
	cube._previous_motion_position = center
	cube.Can_Attack = true
	var friend_before:float = ally.health
	var enemy_before:float = enemy.health
	cube._pulse_contact()
	check(enemy.health < 2000 and ally.health == friend_before,"wood hit damages enemy but not ally")
	check(enemy.health == enemy_before,"wood contact cooldown prevents extra same-tick damage")
	check(enemy.Repel.is_finite(),"native bouncing impulse leaves finite motion")
	var ordinary_hits:Array[Node] = sound_events("entity.player.hurt")
	check(ordinary_hits.size() == 1 and float(ordinary_hits[0].volume_db) > 0.0 and ordinary_hits[0].get_meta("mc_damage_source",0) == cube.get_instance_id(),"one vanilla hurt sample from actual below-50 HP damage, amplified above default")
	var ordinary_gain:float = float(ordinary_hits[0].volume_db)
	check(CUBE.sulfur_impact_event(50.0) == &"entity.player.hurt" and CUBE.sulfur_impact_event(50.1) == &"entity.player.attack.crit","sulfur cube's original-MC hit-to-crit threshold is strictly above fifty")
	check(CUBE.sulfur_impact_gain(0.0)==0.0 and CUBE.sulfur_impact_gain(200.0)>CUBE.sulfur_impact_gain(28.0) and CUBE.sulfur_impact_gain(200.0)<=6.0,"Minecraft hit audio starts at source 0 dB, grows with actual HP lost and caps safely")
	cube.state_machine.last_state_dis["Skill"] = cube.Skill_Cooling+0.1
	cube.state_machine.set_physics_process(true)
	await physics_frame
	await physics_frame
	cube.state_machine.set_physics_process(false)
	check(cube.block_mode == CUBE.Block.ICE and native_block_visible(CUBE.Block.ICE,"blue_ice"),"actual AI skill replaces only the internal model with six-sided original blue ice")
	check(float(cube.state_machine.last_state_dis["Skill"]) < cube.Skill_Cooling,"state transition resets skill cooldown so cube does not skip blocks")
	await capture("ice")
	cube.Speed = 112.0
	cube.direction = Vector2.RIGHT
	cube.move(112.0,0.1)
	var ice_first:float = cube._slide_velocity.length()
	cube.move(112.0,0.1)
	check(ice_first > 0.0 and cube._slide_velocity.length() > ice_first,"blue ice accumulates physical slide momentum")
	cube.Speed = 0.0
	cube.direction = Vector2.ZERO
	cube.global_position = center
	var hot_distance:float = cube.get_crowd_separation_radius_world()+victim_radius(enemy)+6.0
	enemy.global_position = center+Vector2(hot_distance,0)
	cube.Skill()
	check(cube.block_mode == CUBE.Block.MAGMA and float(attack_region(cube).get("radius",0.0)) == CUBE.HOT_RADIUS,"magma reveals wider authentic hot contact region")
	check(native_block_visible(CUBE.Block.MAGMA,"magma"),"magma keeps all six faces and uses original animated source texture")
	check(hot_distance > cube.get_crowd_separation_radius_world()+victim_radius(enemy) and hot_distance < CUBE.HOT_RADIUS+victim_radius(enemy),"magma test victim is outside ordinary contact, inside hot area")
	enemy_before = enemy.health
	cube._pulse_contact()
	check(enemy.health < enemy_before,"magma damages within its true wider threat circle")
	await capture("magma")
	cube.Skill()
	check(cube.block_mode == CUBE.Block.HONEY and native_block_visible(CUBE.Block.HONEY,"honeycomb_block"),"honeycomb switches the physical inner cube and slows movement")
	enemy.global_position = center+Vector2(18,0)
	cube._clock += 1.0
	cube._pulse_contact()
	check(not enemy.Buff_Dic.is_empty(),"honeycomb applies a real timed speed debuff on contact")
	await capture("honey")
	cube.Skill()
	check(cube.block_mode == CUBE.Block.IRON and native_block_visible(CUBE.Block.IRON,"iron_block"),"iron changes the six-sided original block and remains defensive")
	cube.hurt_voice_chance = 1.0 # Force probabilistic original hurt sample for the regression.
	var before_iron:float = cube.health
	cube.take_damage(100.0)
	check(cube.health < before_iron and cube.health > before_iron-55.0,"iron reduces incoming damage without full immunity")
	check(sulfur_events("hurt").size()==1,"actual incoming HP damage can trigger one original sulfur cube hurt voice")
	cube.take_damage(0.0)
	check(sulfur_events("hurt").size()==1,"zero damage does not retrigger the creature's hurt voice")
	await capture("iron")
	cube.Skill()
	check(cube.block_mode == CUBE.Block.TNT and absf(cube.fuse_left-CUBE.TNT_FUSE_SECONDS)<0.001,"TNT insertion begins a visible fuse")
	check(native_block_visible(CUBE.Block.TNT,"tnt_side"),"TNT priming installs a real six-sided Minecraft TNT block")
	check(not sulfur_events("fuse").is_empty() and sulfur_events("fuse")[0].stream != null,"priming uses verified native TNT fuse sound")
	await capture("tnt")
	game.Game_Settings.Training_Debug_Mode = true
	analyzer._physics_process(0.1)
	var debug_tnt:Dictionary = debug_region(analyzer,"sulfur_cube_tnt")
	check(analyzer.visible and float(debug_tnt.get("radius",0.0)) == CUBE.TNT_RADIUS and float(debug_tnt.get("danger_in",0.0)) == cube.fuse_left,"actual World threat setting displays matching TNT blast radius and remaining fuse")
	var tnt:Dictionary = attack_region(cube)
	check(float(tnt.get("radius",0.0)) == CUBE.TNT_RADIUS and absf(float(tnt.get("danger_in",0.0))-cube.fuse_left)<0.001,"TNT threat radius and timing agree with actual detonation")
	cube.Skill()
	check(cube.block_mode == CUBE.Block.TNT,"primed TNT cannot be swapped out early")
	cube.Can_Attack = false
	cube.dizziness = true
	check(float(attack_region(cube).get("radius",0.0)) == CUBE.TNT_RADIUS,"TNT remains a real threat even if stunned after priming")
	cube.Can_Attack = true
	cube.dizziness = false
	game.now_stop_state = true
	var fuse_before:float = cube.fuse_left
	cube.tick_physics(0,0.65)
	check(cube.fuse_left == fuse_before,"pause freezes TNT fuse and attack clock")
	check(debug_region(analyzer,"sulfur_cube_tnt").is_empty(),"paused fuse does not advertise imminent damage")
	game.now_stop_state = false
	enemy.global_position = center+Vector2(CUBE.TNT_RADIUS+victim_radius(enemy)-7.0,0)
	enemy_before = enemy.health
	cube.tick_physics(0,CUBE.TNT_FUSE_SECONDS+0.05)
	check(cube.block_mode == CUBE.Block.WOOD and cube.fuse_left == 0.0,"single TNT detonation ejects block, cube lives and restarts cycle")
	check(enemy.health < enemy_before and ally.health == friend_before,"explosion damages enemy but never friendly cube")
	await capture("blast")
	var critical_hits:Array[Node] = sound_events("entity.player.attack.crit")
	check(critical_hits.size() == 1 and critical_hits[0].get_meta("mc_damage_source",0) == cube.get_instance_id() and float(critical_hits[0].volume_db) > ordinary_gain,"TNT's >50 actual HP hit produces one amplified vanilla critical sample")
	check(debug_region(analyzer,"sulfur_cube_tnt").is_empty() and absf(float(debug_region(analyzer,"sulfur_cube_contact").get("radius",0.0))-cube.get_crowd_separation_radius_world()) < 0.01,"debug overlay replaces TNT radius with post-blast wood contact, no stale ring")
	game.Game_Settings.Training_Debug_Mode = false
	analyzer._physics_process(0.1)
	check(not analyzer.visible and analyzer._debug_threats.is_empty(),"switching threat setting off immediately hides and clears overlay")
	var found_blast:bool = false
	for transient:Node in get_nodes_in_group("BattleTransient"):
		if transient.get_script() == load("res://scripts/effects/我的世界/sulfur_cube_blast.gd"):
			found_blast = true
	check(found_blast,"explosion uses original Minecraft particle frames")
	var remaining:float = enemy.health
	cube._detonate()
	check(enemy.health == remaining,"finished fuse cannot damage the same target again")
	cube.set_block(CUBE.Block.ICE)
	check(absf(float(attack_region(cube).get("radius",0.0))-cube.get_crowd_separation_radius_world()) < 0.01,"threat returns to contact when TNT is gone")
	cube.health = 0
	check(cube.get_debug_attack_regions().is_empty(),"death removes all declared threat regions")
	cube.Die()
	check(sulfur_events("death").size() == 1,"death hook plays original sulfur cube death sound")
	var bell:AudioStreamPlayer = root.get_node("Audios").get_node_or_null("Sfx/DeadBell") as AudioStreamPlayer
	check(bell != null and bell.playing,"death also plays the project's default death bell")
	cube.Die()
	check(sulfur_events("death").size() == 1,"repeated death callback does not duplicate the original creature voice")
	world.queue_free()
	await process_frame
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	print("MC_SULFUR_CUBE: %d checks / %d failures" % [checks,failures])
	quit(1 if failures > 0 else 0)
