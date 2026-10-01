extends SceneTree
## 分级顿挫（轻/重/暴击、白闪、声音不随顿挫变慢）与连击计数（命中音不升调）。
const KEY:String = "High_Damage_Feedback"
var COMBO:Script
var game:Node
var world:Node
var attacker:Node2D
var target:Node2D
var checks:int = 0
var failures:int = 0
var center:Vector2

func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("HIT_FEEL_FAIL " + label)
	else:
		print("HIT_FEEL_PASS ",label)

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
	target.Damage_reduction = 0.0
	target.block = 0
	target.health = 1000

func hit(damage:float) -> float:
	var before:float = target.health
	target.receive_positional_damage(damage,attacker.global_position,true,attacker)
	return before - float(target.health)

func run() -> void:
	create_timer(90.0,true,false,true).timeout.connect(func(): print("HIT_FEEL_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var saved_stop:bool = game.now_stop_state
	var tuning:Script = load("res://global/feedback_settings.gd")
	COMBO = load("res://scripts/effects/hit_combo.gd")

	# 旧默认值迁移：四项都没动过才迁移；玩家改过任意一项则全部保留。
	var legacy:Dictionary = {"Feedback_Hitstop_Damage":20.0,"Feedback_Hitstop_HealthPercent":18.0,"Feedback_Hitstop_MinDuration":0.035,"Feedback_Hitstop_MaxDuration":0.06}
	var a:Dictionary = legacy.duplicate()
	tuning.normalize(a)
	check(a.Feedback_Hitstop_Damage == 12.0 and a.Feedback_Hitstop_HealthPercent == 6.0 and is_equal_approx(a.Feedback_Hitstop_MinDuration,0.025) and is_equal_approx(a.Feedback_Hitstop_MaxDuration,0.09),"untouched legacy hitstop defaults migrate to the tiered defaults")
	var b:Dictionary = legacy.duplicate()
	b.Feedback_Hitstop_MaxDuration = 0.07
	tuning.normalize(b)
	check(b.Feedback_Hitstop_Damage == 20.0 and is_equal_approx(b.Feedback_Hitstop_MaxDuration,0.07),"customised hitstop settings are kept")

	game.reset_feedback_settings("Shaking_Camera",false)
	game.reset_feedback_settings(KEY,false)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Development_Mode = false
	game.Game_Settings.Camera_Move = false
	game.Game_Settings.Shaking_Camera = true
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

	# 档位：1000 生命的门槛是 60。
	check(world.hitstop_tier(59.0,1000.0) == 0,"below threshold: no hitstop")
	check(world.hitstop_tier(60.0,1000.0) == 1 and world.hitstop_tier(119.0,1000.0) == 1,"threshold..2x: light tier")
	check(world.hitstop_tier(120.0,1000.0) == 2 and world.hitstop_tier(239.0,1000.0) == 2,"2x..4x: heavy tier")
	check(world.hitstop_tier(240.0,1000.0) == 3,"4x: crit tier")
	check(world.hitstop_tier(5.0,1000.0,true) == 3,"a lethal finishing blow is crit regardless of damage")
	var d1:float = world.hitstop_duration(60.0,1000.0,1)
	var d2:float = world.hitstop_duration(180.0,1000.0,2)
	var d3:float = world.hitstop_duration(300.0,1000.0,3)
	check(is_equal_approx(d1,0.025) and d2 > d1 and d2 < 0.09 and is_equal_approx(d3,0.09 * 1.8),"duration grows with damage: %.3f < %.3f < %.3f" % [d1,d2,d3])

	# 轻顿：真实停顿、轻震屏、声音不变慢。
	reset_feedback()
	check(hit(70.0) == 70.0 and world._heavy_hit_pending_tier == 1,"light hit queues a light stop")
	world._update_heavy_hitstop()
	check(world._heavy_hit_active_tier == 1 and is_equal_approx(game.get_time_scale_override_factor(),world.heavy_hitstop_time_factor),"light stop actually slows the world")
	await process_frame
	check(Engine.time_scale < 0.5 and is_equal_approx(AudioServer.playback_speed_scale,1.0),"hitstop freezes the picture but not the hit sound (engine %.2f, audio %.2f)" % [Engine.time_scale,AudioServer.playback_speed_scale])
	# 轻顿进行中接上暴击：延长并升档。
	var end_light:int = world._heavy_hit_end_usec
	target.health = 1000
	world._damage_shake_pending_peak = 0.0
	hit(300.0)
	world._update_heavy_hitstop()
	check(world._heavy_hit_active_tier == 3 and world._heavy_hit_end_usec > end_light,"a crit during a light stop extends it")
	check(is_equal_approx(world._damage_shake_pending_peak,game.FEEDBACK_SETTINGS.amplitude(300.0,game.Game_Settings,"Camera")),"camera shake still follows the configurable damage curve")
	var flash:ColorRect = world._crit_flash_rect
	check(is_instance_valid(flash) and flash.modulate.a > 0.3,"crit flashes the screen white")
	check(target.hit_white_tween != null and target.hit_white_tween.is_running(),"crit target holds the white flash")
	world._release_heavy_hitstop()
	await process_frame
	check(is_equal_approx(Engine.time_scale,1.0) and is_equal_approx(AudioServer.playback_speed_scale,1.0),"time and audio restore after the stop")
	# 其它慢动作仍会拖慢声音（只有顿挫豁免）。
	game.request_time_scale_override("hit_feel_test_slow",0.5,Color.TRANSPARENT)
	await process_frame
	check(is_equal_approx(AudioServer.playback_speed_scale,0.5),"ordinary slow motion still slows audio")
	game.release_time_scale_override("hit_feel_test_slow")
	await process_frame
	await create_timer(0.3,true,false,true).timeout
	check(is_instance_valid(flash) and flash.modulate.a < 0.05,"white flash fades out")
	# 击杀：仍是暴击档顿帧，但不整屏闪白。
	reset_feedback()
	check(world.request_heavy_hitstop(5.0,1000.0,target.global_position,true) == 3 and world._heavy_hit_pending_tier == 3,"a killing blow still queues the crit stop")
	check(flash.modulate.a < 0.05,"a killing blow does not flash the screen white")
	world._heavy_hit_pending_tier = 0
	world._heavy_hit_pending_strength = -1.0

	# 连击计数；命中音不随连击升调。
	COMBO.reset(attacker)
	var counts:Array[int] = []
	for i:int in 3:
		counts.append(COMBO.register(attacker))
		await physics_frame
	check(counts == [1,2,3],"consecutive hits count up: %s" % [counts])
	check(COMBO.register(attacker) == 4 and COMBO.register(attacker) == 4,"several hits in one physics frame count once")
	check(is_equal_approx(COMBO.pitch_for(1),1.0) and is_equal_approx(COMBO.pitch_for(3),1.0) and is_equal_approx(COMBO.pitch_for(40),1.0),"combo hits keep the original pitch instead of climbing")
	COMBO.reset(attacker)
	var pitches:Array[float] = []
	for i:int in 6:
		pitches.append(COMBO.next_pitch(attacker))
		await physics_frame
	check(pitches.all(func(p:float) -> bool: return is_equal_approx(p,1.0)),"six consecutive real combo hits all play at pitch 1.0: %s" % [pitches])
	attacker.set_meta(COMBO.META,[5,Time.get_ticks_usec() - COMBO.WINDOW_USEC - 1000,-1])
	await physics_frame
	check(COMBO.register(attacker) == 1,"a gap longer than the window resets the combo")
	var minion:Node2D = spawn_actor("res://scenes/ball.tscn","Team0",Vector2(-60,30))
	minion.Master = attacker
	check(COMBO.owner_of(minion) == attacker,"summons and projectiles count toward their owner")
	minion.queue_free()
	# 被打中的一方连击中断；Minecraft 统一命中音路径计入攻击者连击。
	reset_feedback()
	COMBO.reset(attacker)
	target.set_meta(COMBO.META,[6,Time.get_ticks_usec(),-1])
	await physics_frame
	hit(10.0)
	check(COMBO.count_of(target) == 0,"getting hit breaks the victim's combo")
	check(COMBO.count_of(attacker) == 1,"Minecraft unified hit audio registers the attacker's combo")
	await physics_frame
	hit(10.0)
	check(COMBO.count_of(attacker) == 2,"second Minecraft hit still counts toward the combo")
	var hit_player:AudioStreamPlayer = game.get_node("/root/Audios").Sfx.get_node_or_null("balls_hit1") as AudioStreamPlayer
	if hit_player != null:
		Audios_play(hit_player)
	else:
		check(false,"balls_hit1 template exists")

	world._clear_high_damage_feedback()
	world.queue_free()
	await process_frame
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	print("HIT_FEEL_RESULT checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)

func Audios_play(player:AudioStreamPlayer) -> void:
	var audios:Node = root.get_node("Audios")
	audios.play_sfx("balls_hit1",{},false)
	var base:float = player.pitch_scale
	audios.play_sfx("balls_hit1",{"pitch_mul":1.5},false)
	check(is_equal_approx(player.pitch_scale,base * 1.5),"play_sfx pitch_mul raises the hit sound (%.3f -> %.3f)" % [base,player.pitch_scale])
	player.stop()
