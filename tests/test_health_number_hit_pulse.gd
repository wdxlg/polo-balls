extends SceneTree
## The health number pops on an actual character HP loss, not on healing,
## block/energy updates, restoration or a non-character ball's durability.
var game:Node
var world:Node
var saved:Dictionary
var checks:int = 0
var failures:int = 0
var finishing:bool = false

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("HEALTH_NUMBER_HIT_FAIL " + label)

func near(a:Vector2,b:Vector2) -> bool:
	return a.distance_to(b) < 0.012

func spawn(path:String,position:Vector2,team:String = "Team0") -> Node2D:
	var unit:Node2D = (load(path) as PackedScene).instantiate() as Node2D
	unit.Team = team
	unit.position = position
	world.add_child(unit,true)
	unit.state_machine.set_physics_process(false)
	unit.Has_Collision_Damage = false
	return unit

func finish(code:int) -> void:
	if finishing: return
	finishing = true
	if is_instance_valid(world) and is_instance_valid(world.get("_mc_prewarmer")):
		for path:Variant in world._mc_prewarmer._paths.values():
			var status:int = ResourceLoader.load_threaded_get_status(str(path))
			if status in [ResourceLoader.THREAD_LOAD_IN_PROGRESS,ResourceLoader.THREAD_LOAD_LOADED]:
				ResourceLoader.load_threaded_get(str(path))
	if game != null:
		game.Game_Settings = saved
		game.now_stop_state = true
	if is_instance_valid(world): world.queue_free()
	await process_frame
	await process_frame
	quit(code)

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Boss_Intro = false
	game.Game_Settings.Camera_Move = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(45.0,true,false,true).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3,true,false,true).timeout
	for unit:Node in get_nodes_in_group("Ball"):
		if unit.get_parent() == world: unit.queue_free()
	await process_frame
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var fighter:Node2D = spawn("res://scenes/characters/默认/盔甲架.tscn",center)
	var hud:Node = fighter.health_bar
	var number:Label = hud.label
	var base:Vector2 = number.scale
	var bar_scale:Vector2 = hud.health_bar.scale
	check(hud._is_character_health_bar_owner() and number.pivot_offset_ratio == Vector2(0.5,0.5),"the character number scales around its own centre")
	var initial_hp:int = fighter.health
	check(initial_hp > 100 and near(base,Vector2.ONE),"fresh character begins with normal-sized health digits")
	fighter.take_damage(12.0,true)
	var first:Tween = hud._health_number_hit_tween
	check(fighter.health == initial_hp-12 and first != null and first.is_valid(),"real HP damage starts one number pulse")
	# Sample animation frames instead of wall-clock timers: on first use the
	# headless renderer may spend a frame loading shaders/assets.
	var peak:float = base.x
	var shrank:bool = false
	var elastic_overshoot:bool = false
	var started_at:int = Time.get_ticks_msec()
	while first.is_running() and Time.get_ticks_msec()-started_at < 1800:
		await process_frame
		var current:float = number.scale.x
		peak = maxf(peak,current)
		shrank = shrank or peak > base.x*1.10 and current < peak-0.025
		elastic_overshoot = elastic_overshoot or current < base.x*0.985
	check(peak > base.x*1.15,"digits rapidly grow after damage")
	check(shrank and elastic_overshoot,"elastic shrink briefly bounces past original size")
	check(not first.is_running() and near(number.scale,base) and near(hud.health_bar.scale,bar_scale),"digits settle at authored scale without scaling the health bar")
	# Shield, energy, heal and same-value status refresh are not damage feedback.
	var previous:Tween = hud._health_number_hit_tween
	hud.block_changed.emit(15,9,20,true)
	hud.energy_changed.emit(9,7,20,true)
	check(hud._health_number_hit_tween == previous and near(number.scale,base),"block and energy updates do not pulse health digits")
	var shielded_hp:int = fighter.health
	fighter.max_block = 20
	fighter.block = 15
	fighter.take_damage(5.0)
	check(fighter.health == shielded_hp and fighter.block == 10 and hud._health_number_hit_tween == previous,"a shield-only hit does not pulse the HP number")
	fighter.block = 0
	fighter.max_block = 0
	fighter.health += 5
	check(hud._health_number_hit_tween == previous,"healing does not start a hit pulse")
	hud.health_changed.emit(fighter.health,fighter.health,fighter.Max_health,false)
	check(hud._health_number_hit_tween == previous,"unchanged HP refresh does not start a hit pulse")
	hud.suppress_floating_text = true
	fighter.health -= 4
	hud.suppress_floating_text = false
	check(hud._health_number_hit_tween == previous and near(number.scale,base),"silent HP migration does not pretend to be a hit")
	var sans:Node2D = spawn("res://scenes/characters/传说之下/Sans.tscn",center+Vector2(180,180),"Team1")
	var before_sans:int = fighter.health
	sans.apply_sans_frame_hit(fighter,fighter.global_position,0.0)
	var frame_hit_tween:Tween = hud._health_number_hit_tween
	check(fighter.health == before_sans-1 and frame_hit_tween != previous and frame_hit_tween.is_valid(),"Sans true frame damage pulses even with silent floating text")
	sans.apply_sans_frame_hit(fighter,fighter.global_position,0.0)
	check(fighter.health == before_sans-2 and hud._health_number_hit_tween == frame_hit_tween,"rapid frame hits share one pulse instead of creating 60 tweens/s")
	hud.force_instant_update_once = true
	fighter.health -= 3
	check(hud._health_number_hit_tween != frame_hit_tween and hud._health_number_hit_tween.is_valid(),"actual HP loss pulses even when the bar updates instantly")
	# A new hit during the old tween restarts from the original scale; it must
	# not stack on the first animation or leave digits permanently enlarged.
	fighter.take_damage(4.0,true)
	var interrupted:Tween = hud._health_number_hit_tween
	await create_timer(0.045,true,false,true).timeout
	fighter.take_damage(4.0,true)
	check(hud._health_number_hit_tween != interrupted and not interrupted.is_valid() and near(number.scale,base),"successive hits replace rather than compound the old tween")
	hud.set_invincible_display(true,false)
	check(hud.label.text == "INF" and near(number.scale,base) and hud._health_number_hit_tween == null,"switching to INF cancels an active number pulse")
	var during_inf:Tween = hud._health_number_hit_tween
	fighter.health -= 2
	check(hud._health_number_hit_tween == during_inf and near(number.scale,base),"INF display ignores later HP signals")
	hud.set_invincible_display(false,false)
	# A non-character ball has the same HUD scene but must not inherit the
	# character-only visual; no editor-authored bar dimensions are rewritten.
	var prop:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(280,0))
	var prop_hud:Node = prop.health_bar
	check(not prop_hud._is_character_health_bar_owner(),"base projectile-like Ball is outside character HUD scope")
	prop.health -= 5
	check(prop_hud._health_number_hit_tween == null,"non-character HUD number never pulses")
	print("HEALTH_NUMBER_HIT_RESULT checks=",checks," failures=",failures)
	await finish(1 if failures > 0 else 0)
