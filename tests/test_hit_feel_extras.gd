extends SceneTree
## 命中手感附加层：挤压回弹、方向推镜、碎屑、分层命中音与同帧合并、重击压低其他声音、
## 游戏声总线审计、血条残影与抖动、局部顿帧。
const KEY:String = "High_Damage_Feedback"
var game:Node
var audios:Node
var world:Node
var attacker:Node2D
var target:Node2D
var checks:int = 0
var failures:int = 0
var center:Vector2
var LAYERS:Script
var MCF:Script
var SHAKE:Script

func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("HIT_FEEL_EXTRAS_FAIL " + label)
	else:
		print("HIT_FEEL_EXTRAS_PASS ",label)

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
	world._heavy_hit_next_allowed_usec = 0
	world._crit_flash_next_usec = 0
	world._damage_shake_pending_peak = 0.0
	world._damage_shake_pixels = 0.0
	world._damage_shake_time_left = 0.0
	world._clear_camera_kick()
	world.camera_shake_amount = 0.0
	target.Damage_reduction = 0.0
	target.block = 0
	target.health = 1000
	attacker.health = 1000

func hit(damage:float,source:Node = null) -> float:
	var before:float = target.health
	target.receive_positional_damage(damage,attacker.global_position,true,source if source != null else attacker)
	return before - float(target.health)

func world_basis_length(part:Node2D,pose:Transform2D,axis:Vector2) -> float:
	var parent:CanvasItem = part.get_parent() as CanvasItem
	var basis:Transform2D = parent.get_global_transform() if parent != null and not part.is_set_as_top_level() else Transform2D.IDENTITY
	var world_pose:Transform2D = basis * pose
	# 单位世界向量经过 pose 的逆映射再正向映射：测量沿 axis 的世界缩放。
	var local_axis:Vector2 = (basis * part.transform).affine_inverse().basis_xform(axis)
	return world_pose.basis_xform(local_axis).length()

func run() -> void:
	create_timer(120.0,true,false,true).timeout.connect(func(): print("HIT_FEEL_EXTRAS_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	audios = root.get_node("Audios")
	LAYERS = load("res://scripts/effects/hit_feel_audio.gd")
	MCF = load("res://scripts/effects/我的世界/mc_hit_feedback.gd")
	SHAKE = load("res://scripts/effects/character_hurt_shake.gd")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var saved_stop:bool = game.now_stop_state
	# 本测试改动的设置一律写到临时文件，不污染玩家自己的设置。
	var saved_settings_path:String = game._settings_storage_path
	game._settings_storage_path = "user://test_hit_feel_extras_settings.cfg"
	game.reset_feedback_settings("Shaking_Camera",false)
	game.reset_feedback_settings(KEY,false)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.Camera_Move = false
	game.Game_Settings.Shaking_Camera = true
	game.Game_Settings.Local_Hitstop = false
	game.now_stop_state = false
	game.set_runtime_game_setting(KEY,true,false)
	AudioServer.set_bus_mute(0,true)
	root.size = Vector2i(540,960)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	world.control.hide()
	center = world.return_map_world_rect(world._current_map_node()).get_center()
	attacker = spawn_actor("res://scenes/characters/我的世界/烈焰人.tscn","Team0",Vector2(-38,0))
	target = spawn_actor("res://scenes/characters/我的世界/骷髅.tscn","Team1",Vector2(38,0))
	await process_frame
	await process_frame
	world.set_physics_process(false)
	world.camera_2d.global_position = center
	world.camera_2d.force_update_scroll()

	# ---------- 1. 沿击退方向挤压 + 弹性回弹，随伤害变化 ----------
	check(SHAKE.squash_for_damage(10.0,1000.0) < SHAKE.squash_for_damage(100.0,1000.0) and SHAKE.squash_for_damage(100.0,1000.0) < SHAKE.squash_for_damage(400.0,1000.0),"squash strength grows with damage")
	check(is_equal_approx(SHAKE.squash_for_damage(100000.0,1000.0),SHAKE.SQUASH_MAX) and SHAKE.squash_for_damage(0.0,1000.0) == 0.0,"squash is capped and zero damage does nothing")
	reset_feedback()
	hit(30.0)
	var shake:Node = target._hurt_shake_effect
	check(is_instance_valid(shake) and shake.squash_active,"a confirmed attack hit squashes the victim")
	check(is_instance_valid(shake) and shake.squash_axis.dot(Vector2.RIGHT) > 0.99,"squash axis follows the knockback direction (attacker on the left)")
	var light_squash:float = shake.squash_amount
	check(is_equal_approx(light_squash,SHAKE.squash_for_damage(30.0,target.get_impact_reference_health())),"squash peak matches the damage curve (%.3f)" % light_squash)
	shake._present()
	var graphics:Node2D = target.graphics
	var along:float = world_basis_length(graphics,shake.last_render_transform,Vector2.RIGHT)
	var across:float = world_basis_length(graphics,shake.last_render_transform,Vector2.UP)
	check(absf(along - (1.0 - light_squash)) < 0.02 and absf(across - (1.0 + light_squash * 0.5)) < 0.02,"rendered pose is compressed along the hit and widened across it (%.3f / %.3f)" % [along,across])
	var samples:Array[float] = []
	for i:int in 60:
		shake.advance(1.0 / 60.0)
		samples.append(shake.squash_amount)
	check(samples.min() < -0.01,"recovery overshoots into a slight stretch (min %.3f)" % samples.min())
	check(not shake.squash_active or absf(shake.squash_amount) < 0.01,"squash settles within a second")
	target.health = 1000
	hit(300.0)
	check(is_instance_valid(shake) and shake.squash_amount > light_squash,"heavier hits squash harder (%.3f > %.3f)" % [shake.squash_amount,light_squash])
	var heavy_amount:float = shake.squash_amount
	target.health = 1000
	hit(5.0)
	check(is_equal_approx(shake.squash_amount,heavy_amount),"a weak hit does not cut a strong squash short")
	shake.stop()
	check(not shake.squash_active and shake.squash_amount == 0.0,"stop clears the squash")

	# ---------- 2. 方向性推镜 ----------
	reset_feedback()
	world.add_directional_camera_kick(Vector2.RIGHT,300.0,target.global_position)
	check(world._camera_kick_pending.x > 0.0,"an on-screen hit queues a directional camera kick")
	var min_x:float = 0.0
	var max_abs_y:float = 0.0
	var peak_frame:int = -1
	for i:int in 30:
		world._update_damage_camera_shake(1.0 / 60.0)
		var pixels:Vector2 = world.camera_2d.offset * world.camera_2d.zoom
		if pixels.x < min_x:
			min_x = pixels.x
			peak_frame = i
		max_abs_y = maxf(max_abs_y,absf(pixels.y))
	check(min_x < -1.0 and min_x >= -world.damage_shake_max_pixels - 0.01,"camera moves against the hit so the picture lurches along it (%.2f px)" % min_x)
	check(peak_frame >= 2 and peak_frame <= 8,"kick peaks after a few frames, visible rather than a one-frame flicker (frame %d)" % peak_frame)
	check(max_abs_y < 0.01,"a horizontal hit only kicks horizontally")
	for i:int in 60: world._update_damage_camera_shake(1.0 / 60.0)
	check(world.camera_2d.offset == Vector2.ZERO,"camera springs back to center")
	world.add_directional_camera_kick(Vector2.RIGHT,300.0,center + Vector2(100000,0))
	check(world._camera_kick_pending == Vector2.ZERO,"off-screen hits do not kick the camera")
	game.Game_Settings.Shaking_Camera = false
	world.add_directional_camera_kick(Vector2.RIGHT,300.0,target.global_position)
	check(world._camera_kick_pending == Vector2.ZERO,"camera shake setting off disables the kick")
	game.Game_Settings.Shaking_Camera = true
	world.add_directional_camera_kick(Vector2.RIGHT,10.0,target.global_position)
	var weak:float = world._camera_kick_pending.length()
	world.add_directional_camera_kick(Vector2.UP,400.0,target.global_position)
	world.add_directional_camera_kick(Vector2.LEFT,20.0,target.global_position)
	check(world._camera_kick_pending.length() > weak and world._camera_kick_pending.normalized().dot(Vector2.UP) > 0.99,"same-frame hits keep only the strongest kick direction")
	world._clear_camera_kick()
	world.camera_2d.offset = Vector2.ZERO

	# ---------- 4. 碎屑 ----------
	var counts:Array[int] = []
	var palette:Dictionary = {}
	var pal_sampler:RefCounted = target._make_visual_pixel_sampler()
	var pal_rect:Rect2 = pal_sampler.rect
	for gx:int in range(int(pal_rect.size.x * 4.0)):
		for gy:int in range(int(pal_rect.size.y * 4.0)):
			var c:Color = pal_sampler.sample(pal_rect.position + Vector2(gx + 0.5,gy + 0.5) * 0.25)
			if c.a > 0.10: palette[c.to_html()] = true
	check(palette.size() >= 2,"target texture has a real palette to compare (%d colours)" % palette.size())
	var cell_counts:Dictionary = {}
	var speeds:Array = []
	var lives:Array = []
	for damage:float in [8.0,400.0]:
		# force_white=true：受击闪白时打击线是白的，碎屑仍取人物真实像素。
		target._play_hit_burst_feedback_local(attacker.global_position,damage,20.0,12345,true,Vector2.RIGHT)
		var effect:Node = null
		for child:Node in world.get_children():
			if child is HitBurstEffect: effect = child
		check(effect != null,"hit burst effect spawned for %.0f damage" % damage)
		if effect == null: continue
		var chips:Array = effect._chips
		counts.append(chips.size())
		var all_from_texture:bool = not chips.is_empty()
		var non_white:int = 0
		for c:Dictionary in chips:
			cell_counts[(c.cells as Array).size()] = true
			speeds.append((c.velocity as Vector2).length())
			lives.append(float(c.life))
			for cell:Array in c.cells:
				if not palette.has((cell[1] as Color).to_html()): all_from_texture = false
				if not (cell[1] as Color).is_equal_approx(Color.WHITE): non_white += 1
		check(all_from_texture,"every chip cell colour is a real pixel of the character texture (%d chips)" % chips.size())
		check(non_white > 0,"chips are not the white hit-flash colour")
		var forward:int = 0
		for c:Dictionary in chips:
			if (c.velocity as Vector2).x > 0.0: forward += 1
		check(forward * 2 >= chips.size(),"chips fly out along the hit direction")
		effect.free()
	check(counts.size() == 2 and counts[1] > counts[0],"heavier hits throw more chips (%s)" % [counts])
	speeds.sort(); lives.sort()
	check(cell_counts.size() >= 3,"chips come in several shapes (cell counts %s)" % [cell_counts.keys()])
	check(speeds.size() >= 4 and speeds[-1] > speeds[0] * 2.0 and lives[-1] - lives[0] > 0.15,"chip speeds and lifetimes vary widely")

	# ---------- 9. 游戏声总线审计 ----------
	var accent:int = AudioServer.get_bus_index(&"ImpactAccent")
	var gameplay:int = AudioServer.get_bus_index(&"GameplayRecord")
	check(accent > gameplay and gameplay >= 0 and AudioServer.get_bus_send(accent) == &"GameplayRecord","ImpactAccent exists and feeds GameplayRecord (so recordings include it)")
	check(AudioServer.get_bus_effect_count(gameplay) >= 1 and AudioServer.get_bus_effect(gameplay,0) is AudioEffectAmplify,"duck amplifier sits first on GameplayRecord, before any recording tap")
	var loose2d := AudioStreamPlayer2D.new()
	world.add_child(loose2d)
	var loose := AudioStreamPlayer.new()
	target.add_child(loose)
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var ui_player := AudioStreamPlayer.new()
	layer.add_child(ui_player)
	await process_frame
	check(loose2d.bus == &"GameplayRecord" and loose.bus == &"GameplayRecord","players left on Master are routed to GameplayRecord")
	check(ui_player.bus == &"UI","players under a CanvasLayer stay on UI and out of recordings")
	layer.queue_free()
	loose.queue_free()
	loose2d.queue_free()
	var stray:Array[String] = []
	for node:Node in world.find_children("*","AudioStreamPlayer2D",true,false) + world.find_children("*","AudioStreamPlayer",true,false):
		var bus:StringName = node.get("bus")
		var in_ui:bool = false
		var p:Node = node.get_parent()
		while p != null:
			if p is CanvasLayer: in_ui = true
			p = p.get_parent()
		if not in_ui and bus not in [&"GameplayRecord",&"ImpactAccent"] and not node.is_queued_for_deletion():
			stray.append("%s:%s" % [node.get_path(),bus])
	check(stray.is_empty(),"no in-world gameplay player bypasses GameplayRecord: %s" % [stray])

	# ---------- 6/7. 分层命中音 + 同帧合并 ----------
	var click:AudioStreamWAV = LAYERS.click_stream()
	var thump:AudioStreamWAV = LAYERS.thump_stream()
	check(click != null and absf(click.get_length() - LAYERS.CLICK_SECONDS) < 0.005 and thump != null and absf(thump.get_length() - LAYERS.THUMP_SECONDS) < 0.005,"procedural click and thump streams are generated")
	check(LAYERS.click_stream() == click and LAYERS.thump_stream() == thump,"layer streams are cached, not rebuilt per hit")
	var peak_click:int = 0
	for i:int in range(0,click.data.size(),2): peak_click = maxi(peak_click,absi(click.data.decode_s16(i)))
	var peak_thump:int = 0
	for i:int in range(0,thump.data.size(),2): peak_thump = maxi(peak_thump,absi(thump.data.decode_s16(i)))
	check(peak_click > 3000 and peak_thump > 15000 and peak_thump < 32767,"layers are audible but do not clip (%d / %d)" % [peak_click,peak_thump])
	LAYERS.last_layers = {}
	LAYERS.request(target,10.0,target.global_position,false)
	await process_frame
	check(int(LAYERS.last_layers.get("count",0)) == 1 and not LAYERS.last_layers.has("thump_db") and not LAYERS.last_layers.has("duck_db") and LAYERS.last_layers.get("bus") == &"GameplayRecord","light hit: transient click only, no thump, no ducking")
	await create_timer(0.1,true,false,true).timeout
	LAYERS.last_layers = {}
	LAYERS.request(target,20.0,target.global_position,false)
	LAYERS.request(attacker,80.0,attacker.global_position,false)
	LAYERS.request(target,40.0,target.global_position,false)
	await process_frame
	var merged:Dictionary = LAYERS.last_layers
	check(int(merged.get("count",0)) == 3 and is_equal_approx(float(merged.get("damage",0.0)),80.0),"three same-frame hits merge into one layered sound keyed by the strongest")
	check(is_equal_approx(float(merged.get("click_db",0.0)),LAYERS.click_volume_db(80.0,3)) and LAYERS.click_volume_db(80.0,3) - LAYERS.click_volume_db(80.0,1) == 3.0,"merged sound is a little louder per extra target (+1.5 dB each)")
	check(LAYERS.merge_bonus_db(20) == LAYERS.MERGE_MAX_DB,"merge loudness is capped")
	check(merged.has("thump_db") and merged.has("duck_db") and merged.get("bus") == &"ImpactAccent","heavy hit adds the low thump, ducks others and plays on the accent bus")
	check(not LAYERS.wants_thump(29.0,false) and LAYERS.wants_thump(30.0,false) and LAYERS.wants_thump(1.0,true),"thump from 30 damage or any kill")

	# ---------- 5. 重击压低其他声音 ----------
	var duck_fx:AudioEffectAmplify = AudioServer.get_bus_effect(gameplay,0) as AudioEffectAmplify
	var accent_fx:AudioEffectAmplify = AudioServer.get_bus_effect(accent,0) as AudioEffectAmplify
	check(audios.get_impact_duck_db() > 2.9 and is_equal_approx(duck_fx.volume_db,-audios.get_impact_duck_db()) and is_equal_approx(accent_fx.volume_db,audios.get_impact_duck_db()),"ducking lowers GameplayRecord and compensates ImpactAccent by the same amount")
	check(not LAYERS.wants_duck(50.0,false) and LAYERS.wants_duck(51.0,false) and LAYERS.wants_duck(5.0,true),"ducking only for >50 damage or kills")
	check(LAYERS.duck_depth_db(51.0,false) >= 3.0 and LAYERS.duck_depth_db(1000.0,false) <= 6.0 and LAYERS.duck_depth_db(5.0,true) >= 5.0,"duck depth stays within 3-6 dB")
	var deep:float = audios.get_impact_duck_db()
	audios.duck_for_impact(1.0)
	check(is_equal_approx(audios.get_impact_duck_db(),deep),"a shallower duck does not replace a deeper one")
	await create_timer(0.6,true,false,true).timeout
	check(audios.get_impact_duck_db() == 0.0 and is_zero_approx(duck_fx.volume_db) and is_zero_approx(accent_fx.volume_db),"ducking recovers fully after the release")

	# ---------- 7. MC 统一受击音同帧合并 ----------
	await physics_frame
	var t1:Dictionary = MCF.play(target,20.0,target.global_position,0,9001,1.0)
	var t2:Dictionary = MCF.play(attacker,25.0,attacker.global_position,0,9002,1.0)
	check(not t1.is_empty() and t1 == t2 and is_same(t1,t2),"same-frame MC hit sounds share one queued voice")
	check(is_equal_approx(float(t1.get("volume_db_override",0.0)),MCF.GAIN.damage_gain(25.0) + 1.5) and int(t1.get("merged_hits",0)) == 2,"merged MC hit is louder by 1.5 dB")
	var capped:Dictionary = MCF.play(target,500.0,target.global_position,0,9005,1.0)
	MCF.play(attacker,500.0,attacker.global_position,0,9006,1.0)
	MCF.play(target,500.0,target.global_position,0,9007,1.0)
	check(float(capped.get("volume_db_override",0.0)) <= MCF.GAIN.MAX_GAIN_DB + 0.0001,"merged loudness never exceeds the +6 dB hit-sound cap")
	var crit:Dictionary = MCF.play(target,80.0,target.global_position,0,9003,1.0)
	check(not crit.is_empty() and not is_same(crit,t1),"crit and normal hits in one frame stay separate events")
	await process_frame
	var normal_player:AudioStreamPlayer2D = (t1.player as WeakRef).get_ref() as AudioStreamPlayer2D if t1.get("player") is WeakRef else null
	var crit_player:AudioStreamPlayer2D = (crit.player as WeakRef).get_ref() as AudioStreamPlayer2D if crit.get("player") is WeakRef else null
	check(is_instance_valid(normal_player) and is_equal_approx(normal_player.volume_db,MCF.GAIN.damage_gain(25.0) + 1.5) and normal_player.bus == &"GameplayRecord","merged voice starts with the raised volume on GameplayRecord")
	check(is_instance_valid(crit_player) and crit_player.bus == &"ImpactAccent","heavy MC hit sound is not ducked by its own impact")
	await physics_frame
	var t3:Dictionary = MCF.play(target,20.0,target.global_position,0,9004,1.0)
	check(not is_same(t3,t1) and not t3.has("volume_db_override"),"the next physics frame starts a fresh voice")
	await process_frame

	# ---------- 12. 血条残影 + 抖动 ----------
	var bar:Node = target.health_bar
	reset_feedback()
	await create_timer(0.8,true,false,true).timeout
	var base_position:Vector2 = bar.texture_rect.position
	check(bar.bar_shake_pixels_for_drop(0.005) == 0.0 and bar.bar_shake_pixels_for_drop(0.05) < bar.bar_shake_pixels_for_drop(0.2),"bar shake scales with the fraction of health lost")
	target.health = 800
	check(is_equal_approx(bar.get_damage_ghost_value(),1.0),"lost health leaves a ghost at the previous level")
	await process_frame
	await process_frame
	check(bar.texture_rect.position != base_position,"health bar shakes on a big drop")
	check(bar.get_damage_ghost_value() > 0.85,"ghost holds briefly before draining (%.3f)" % bar.get_damage_ghost_value())
	await create_timer(0.2,true,false,true).timeout
	var mid:float = bar.get_damage_ghost_value()
	check(mid > 0.0 and mid < 0.97,"ghost is already draining after 0.2 s (%.3f)" % mid)
	target.health = 700
	check(absf(bar.get_damage_ghost_value() - mid) < 0.02,"consecutive hit continues from the current ghost instead of restarting")
	await create_timer(0.3,true,false,true).timeout
	check(bar.get_damage_ghost_value() < 0.0,"ghost drains and hides within about 0.3 s")
	await create_timer(0.3,true,false,true).timeout
	check(bar.texture_rect.position == base_position,"bar returns to its exact place after shaking")
	target.health = 695
	await process_frame
	check(bar.get_damage_ghost_value() > 0.0 and bar.texture_rect.position == base_position,"a tiny DOT tick shows the ghost without shaking")
	target.health = 1000
	check(bar.get_damage_ghost_value() < 0.0,"healing above the ghost hides it")

	# ---------- 13. 局部顿帧 ----------
	game.Game_Settings.Local_Hitstop = true
	reset_feedback()
	var original_target_mode:int = target.process_mode
	var original_attacker_mode:int = attacker.process_mode
	var body_mode:int = target.disable_mode
	hit(300.0)
	check(target.process_mode == Node.PROCESS_MODE_DISABLED and attacker.process_mode == Node.PROCESS_MODE_DISABLED,"local hitstop freezes only the victim and the attacker")
	check(world._heavy_hit_pending_tier == 0 and is_equal_approx(game.get_time_scale_override_factor(),1.0),"local hitstop does not slow the whole world")
	check(target.disable_mode == CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE,"frozen bodies keep their collision active")
	var third:Node2D = spawn_actor("res://scenes/characters/我的世界/骷髅.tscn","Team1",Vector2(0,60))
	check(third.process_mode != Node.PROCESS_MODE_DISABLED,"bystanders keep running")
	var frozen_end:int = int(world._local_hitstop_entries[target.get_instance_id()].end)
	check(frozen_end - Time.get_ticks_usec() <= int(world.hitstop_duration(300.0,1000.0,3) * 1000000.0) + 1000,"freeze lasts the normal hitstop duration")
	await create_timer(0.25,true,false,true).timeout
	world._update_local_hitstop()
	check(target.process_mode == original_target_mode and attacker.process_mode == original_attacker_mode and target.disable_mode == body_mode,"both resume with their original modes afterwards")
	# 冷却：紧接着的普通档不再冻结；投射物来源只冻受击者；致命一击不冻受击者。
	target.health = 1000
	hit(130.0)
	check(target.process_mode != Node.PROCESS_MODE_DISABLED,"cooldown prevents back-to-back freezes")
	world._local_hitstop_cooldowns.clear()
	target.health = 1000
	var bullet := Node2D.new()
	world.add_child(bullet)
	bullet.global_position = attacker.global_position
	hit(130.0,bullet)
	check(target.process_mode == Node.PROCESS_MODE_DISABLED and attacker.process_mode != Node.PROCESS_MODE_DISABLED,"a non-character source freezes only the victim")
	game.Game_Settings.Local_Hitstop = false
	world._update_local_hitstop()
	check(target.process_mode == original_target_mode,"turning the option off releases frozen units at once")
	bullet.queue_free()
	game.Game_Settings.Local_Hitstop = true
	world._local_hitstop_cooldowns.clear()
	reset_feedback()
	check(target._local_hitstop_participants(attacker,true) == [attacker],"a killing blow never freezes the victim")
	game.Game_Settings.Local_Hitstop = false
	third.queue_free()

	world._clear_high_damage_feedback()
	world.queue_free()
	await process_frame
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	game._settings_storage_path = saved_settings_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_hit_feel_extras_settings.cfg"))
	print("HIT_FEEL_EXTRAS_RESULT checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
