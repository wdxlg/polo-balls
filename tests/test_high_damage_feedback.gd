extends SceneTree
## Confirmed damage pipeline, local settings and optional fixed-step GPU comparison.
const KEY:String = "High_Damage_Feedback"
var game:Node
var world:Node
var attacker:Node2D
var target:Node2D
var checks:int = 0
var failures:int = 0
var curve:Script
var center:Vector2
var saved:Dictionary
var saved_stop:bool
var saved_locale:String

func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ",label)

func spawn_actor(scene:String,side:String,offset:Vector2) -> Node2D:
	var unit:Node2D = load(scene).instantiate()
	unit.Max_health = 1000
	unit.Team = side
	unit.position = center + offset
	world.add_child(unit,true)
	unit.Can_Attack = false
	unit.Can_Skill = false
	unit.Has_Collision_Damage = false
	unit.self_hitbox.monitoring = false
	unit.collision_layer = 0
	unit.collision_mask = 0
	unit.set_physics_process(false)
	unit.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	return unit

func reset_feedback() -> void:
	world._clear_high_damage_feedback()
	game.Game_Settings.Shaking_Camera = false
	world._update_damage_camera_shake(0.0)
	game.Game_Settings.Shaking_Camera = true
	target.Damage_reduction = 0.0
	target.block = 0
	target.health = 1000
	if is_instance_valid(target._hurt_shake_effect): target._hurt_shake_effect.stop()

func hit(damage:float,ignore_block:bool = true) -> float:
	var before:float = target.health
	target.receive_positional_damage(damage,attacker.global_position,ignore_block,attacker)
	return before - float(target.health)

func contract_cases() -> void:
	check(bool(game.get_script().get_property_default_value("Game_Settings").get(KEY,false)),"special feedback defaults on")
	game.set_runtime_game_setting(KEY,true,false)
	check(not game._is_network_shared_setting(KEY) and not game._shared_settings_snapshot().has(KEY),"special feedback is a local preference, not a room rule")
	var toggles:Array[Node] = []
	for node:Node in world.control._collect_descendants(world.control.settings_category_boxes.parameters):
		if node is TextureButton and node.get_meta("game_setting_key","")==KEY: toggles.append(node)
	check(toggles.size()==1,"parameters page builds exactly one special-feedback switch")
	for locale:String in ["zh","en"]:
		game.set_language(locale,false)
		var key:String = "SETTING_HIGH_DAMAGE_FEEDBACK"
		check(game.t(key)==("高伤害特殊反馈" if locale=="zh" else "Heavy Hit Effects"),locale+" runtime translation is present")
		check(load("res://global/translation_catalog.gd").TABLE[locale][key]==game.t(key),locale+" export catalog matches")
	game.set_language("zh",false)
	for invalid:float in [0.0,-1.0,INF,NAN]: check(curve.strength_for_damage(invalid)==0.0,"invalid body-shake input stays silent")
	for value:float in [1.0,25.0,49.0,50.0]:
		check(curve.strength_for_damage(value)>0.0 and curve.strength_for_damage(value)<=0.6,"body damage <=50 is slight: "+str(value))
	for value:float in [50.01,51.0,250.0,1000000.0]:
		check(curve.strength_for_damage(value)>5.0 and curve.strength_for_damage(value)<=18.0,"body damage >50 is strong and bounded: "+str(value))
	game.set_runtime_game_setting(KEY,false,false)
	for value:float in [25.0,50.0,51.0,250.0]:
		reset_feedback()
		check(hit(value)==value,"real health loss matches controlled hit: "+str(value))
		var amplitude:float = target._hurt_shake_effect.amplitude
		var camera:float = world._damage_shake_pending_peak
		check(amplitude<=0.6 and camera<=0.75 if value<=50 else amplitude>5.0 and camera>5.0,"body and camera use the same actual-damage boundary: "+str(value))
		check(world._damage_focus_pending_strength<0 and world._heavy_hit_pending_strength<0,"switch off suppresses both zoom and hitstop, not shake")
	reset_feedback()
	world.damage_shake_strength = 0.5
	world.add_damage_camera_shake(1000000.0)
	check(is_equal_approx(world._damage_shake_pending_peak,5.0),"heavy damage preserves the existing strength multiplier")
	reset_feedback()
	world.add_damage_camera_shake(50.0)
	check(is_equal_approx(world._damage_shake_pending_peak,0.375),"light damage also respects the strength multiplier")
	world.damage_shake_strength = 1.0
	reset_feedback()
	target.Damage_reduction = 0.9
	var reduced:float = hit(250.0)
	check(reduced<=50 and target._hurt_shake_effect.amplitude<=0.6 and world._damage_shake_pending_peak<=0.75,"defense is applied before selecting the shake tier")
	reset_feedback()
	target.Damage_reduction = 1.0
	check(hit(250.0)==0.0 and not target._hurt_shake_effect.active and world._damage_shake_pending_peak==0.0,"immunity never creates damage shake")
	reset_feedback()
	target.max_block = 1000
	target.block = 1000
	check(hit(500.0,false)==0.0 and not target._hurt_shake_effect.active and world._damage_shake_pending_peak<=0.75,"large shield absorption cannot masquerade as strong health-damage shake")
	reset_feedback()
	for i:int in 500:
		world.add_damage_camera_shake(50.0)
		target._play_body_hurt_shake(50.0)
	world._update_damage_camera_shake(0.0)
	check(world._damage_shake_pixels<=1.0 and target._hurt_shake_effect.amplitude<=0.6,"hundreds of small hits cannot stack into strong feedback")
	target._hurt_shake_effect.kick(250.0)
	target._hurt_shake_effect.advance(0.04)
	var age:float = target._hurt_shake_effect.age
	var duration:float = target._hurt_shake_effect.duration
	target._hurt_shake_effect.kick(1.0)
	check(target._hurt_shake_effect.age==age and target._hurt_shake_effect.duration==duration,"weak tick does not extend an active heavy body shake")
	reset_feedback()
	game.set_runtime_game_setting(KEY,true,false)
	check(hit(250.0)==250.0 and world._damage_focus_pending_strength>=0.0 and world._heavy_hit_pending_strength>=0.0,"switch on queues zoom and hitstop through confirmed positional damage")
	world._update_damage_focus()
	world._damage_focus_started_usec = Time.get_ticks_usec()-100000
	world._update_damage_focus()
	world._update_heavy_hitstop()
	check(world._damage_focus_weight>0 and not world._heavy_hit_time_key.is_empty() and game.get_time_scale_override_factor()<1.0,"queued effects actually play")
	game.request_time_scale_override("feedback_test_foreign",0.3,Color.TRANSPARENT)
	world._cinematic_focus_weight = 0.4
	game.set_runtime_game_setting(KEY,false,false)
	check(world._damage_focus_weight==0 and world._damage_focus_pending_strength<0 and world._heavy_hit_time_key.is_empty() and world._heavy_hit_pending_strength<0,"disabling clears active and queued special effects immediately")
	check(is_equal_approx(game.get_time_scale_override_factor(),0.3) and world._cinematic_focus_weight==0.4,"disabling preserves another skill's time lease and cinematic channel")
	world._cinematic_focus_weight = 0.0
	game.release_time_scale_override("feedback_test_foreign")
	reset_feedback()
	game.set_runtime_game_setting(KEY,true,false)
	game.Game_Settings.Shaking_Camera = false
	check(hit(250.0)==250.0 and world._damage_shake_pending_peak==0 and world._damage_focus_pending_strength>=0 and world._heavy_hit_pending_strength>=0,"camera-shake switch remains independent of special feedback")
	reset_feedback()
	var role:String = game.network_role
	game.network_role = "client"
	check(not world._can_play_heavy_hitstop(),"local setting never enables unsynchronized multiplayer hitstop")
	game.network_role = role
	var doomed:Node2D = spawn_actor("res://scenes/ball.tscn","Team1",Vector2(24,18))
	doomed.health = 20
	reset_feedback()
	doomed.receive_positional_damage(250.0,attacker.global_position,true,attacker)
	check(world._damage_shake_pending_peak<=0.75,"overkill is capped to remaining health for camera-shake threshold")
	check(world._damage_focus_pending_strength>=0.0,"existing overkill focus policy is preserved independently")
	if is_instance_valid(doomed): doomed.queue_free()
	reset_feedback()

func capture_case(folder:String,label:String,damage:float,enabled:bool) -> void:
	var path:String = folder.path_join(label)
	DirAccess.make_dir_recursive_absolute(path)
	reset_feedback()
	game.set_runtime_game_setting(KEY,enabled,false)
	world.camera_2d.global_position = center
	world.camera_2d.force_update_scroll()
	for warm:int in 60: await RenderingServer.frame_post_draw
	var initial_zoom:float = world.camera_2d.zoom.x
	var rows:Array = []
	var peak_zoom:float = initial_zoom
	var min_scale:float = 1.0
	var loss:float = 0.0
	for frame:int in 132:
		await process_frame
		if frame==36: loss = hit(damage)
		await RenderingServer.frame_post_draw
		var image:Image = root.get_texture().get_image()
		var saved_image:Error = image.save_png(path.path_join("%04d.png"%frame))
		if saved_image != OK: check(false,"save comparison frame: "+label)
		peak_zoom = maxf(peak_zoom,world.camera_2d.zoom.x)
		min_scale = minf(min_scale,game.get_time_scale_override_factor())
		rows.append({"frame":frame,"scale":game.get_time_scale_override_factor(),"zoom":world.camera_2d.zoom.x/initial_zoom,"shake":world._damage_shake_pixels,"target_x":(root.get_stretch_transform()*root.get_canvas_transform()*target.global_position).x,"target_y":(root.get_stretch_transform()*root.get_canvas_transform()*target.global_position).y})
	check(loss==damage,"GPU clip uses confirmed health damage: "+label)
	check(peak_zoom>initial_zoom*1.05 and min_scale<0.5 if enabled else is_equal_approx(peak_zoom,initial_zoom) and is_equal_approx(min_scale,1.0),"GPU zoom/time results obey switch: "+label)
	var file:FileAccess = FileAccess.open(path.path_join("timing.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(rows))
	file.close()
	print("FEEDBACK_CLIP ",label," damage=",loss," zoom=",peak_zoom/initial_zoom," min_scale=",min_scale)

func run() -> void:
	create_timer(120.0,true,false,true).timeout.connect(func(): print("HIGH_DAMAGE_FEEDBACK_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	saved_locale = game.current_locale
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.Map_Background = "blue"
	game.Game_Settings.Minecraft_Clouds = false
	game.Game_Settings.Camera_Move = false
	game.Game_Settings.Only_In_Game_Translation = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	root.size = Vector2i(540,960)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	world.control.hide()
	world.control.team.hide()
	world.fps.hide()
	game.stop_background.hide()
	game.stop_text.hide()
	center = world.return_map_world_rect(world._current_map_node()).get_center()
	curve = load("res://scripts/effects/character_hurt_shake.gd")
	attacker = spawn_actor("res://scenes/characters/我的世界/烈焰人.tscn","Team0",Vector2(-38,0))
	target = spawn_actor("res://scenes/characters/我的世界/骷髅.tscn","Team1",Vector2(38,0))
	await process_frame
	await process_frame
	world.set_physics_process(false)
	world.camera_2d.global_position = center
	world.camera_2d.force_update_scroll()
	contract_cases()
	var args:PackedStringArray = OS.get_cmdline_user_args()
	if DisplayServer.get_name()!="headless" and args.size()>0:
		DirAccess.make_dir_recursive_absolute(args[0])
		Engine.call("set_recording_fixed_fps",60)
		Engine.max_fps = 0
		for warm:int in 120: await RenderingServer.frame_post_draw
		world.control.show()
		world.control.game_setting.show()
		world.control._show_settings_category("parameters")
		await process_frame
		for node:Node in world.control._collect_descendants(world.control.settings_category_boxes.parameters):
			if node is TextureButton and node.get_meta("game_setting_key","")==KEY: world.control.settings_scroll.ensure_control_visible(node.get_parent().get_parent())
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[0].path_join("settings.png"))
		world.control.game_setting.hide()
		world.control.hide()
		for frame:int in 12: await RenderingServer.frame_post_draw
		await capture_case(args[0],"special_on",250.0,true)
		await capture_case(args[0],"special_off",250.0,false)
		await capture_case(args[0],"damage_25",25.0,false)
		await capture_case(args[0],"damage_50",50.0,false)
		await capture_case(args[0],"damage_51",51.0,false)
		Engine.call("set_recording_fixed_fps",-1)
	world._clear_high_damage_feedback()
	world.queue_free()
	await process_frame
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	game.set_language(saved_locale,false)
	print("HIGH_DAMAGE_FEEDBACK_RESULT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
