extends SceneTree
## True lethal-hit interception in the real battle World, no fake status nodes.
var EFFECTS:GDScript
var FX:GDScript
var NATIVE_AUDIO:GDScript
var checks:int = 0
var failures:int = 0
var game:Node
var world:Node2D
var saved:Dictionary
var original_stop:bool

func _initialize() -> void: call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("EVOKER_TOTEM_FAIL " + label)

func spawn(path:String,point:Vector2,team:String) -> Node2D:
	var actor:Node2D = (load(path) as PackedScene).instantiate() as Node2D
	actor.Team = team
	actor.Can_Attack = false
	actor.Can_Skill = false
	actor.Speed = 0.0
	actor.Health_Restore = 0
	world.add_child(actor,true)
	actor.global_position = point
	actor.state_machine.set_physics_process(false)
	return actor

func active_fx() -> Array[Node]:
	var result:Array[Node] = []
	for fx:Node in get_nodes_in_group("MCEvokerTotemFX"):
		if is_instance_valid(fx) and not fx.is_queued_for_deletion(): result.append(fx)
	return result

func run() -> void:
	create_timer(60.0,true,false,true).timeout.connect(func(): push_error("EVOKER_TOTEM_TIMEOUT"); quit(2))
	game = root.get_node("Game")
	# Load after autoload registration, not while the SceneTree entry point
	# compiles: these gameplay scripts legitimately depend on Game.
	EFFECTS = load("res://scripts/effects/我的世界/mc_status_effects.gd") as GDScript
	FX = load("res://scripts/effects/我的世界/mc_totem_effect.gd") as GDScript
	NATIVE_AUDIO = load("res://scripts/effects/我的世界/mc_native_audio.gd") as GDScript
	saved = game.Game_Settings.duplicate(true)
	original_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Map_Background = "blue" # isolate other sessions' themed wall assets
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node2D
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.control.hide()
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	await create_timer(0.38).timeout
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var evoker:Node2D = spawn("res://scenes/characters/我的世界/唤魔者.tscn",center,"Team0")
	var enemy:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(150,0),"Team1")
	# The new map and actor need a real physics step before levitation's
	# ceiling query and native status physics can be asserted deterministically.
	await physics_frame
	var state_before:int = evoker.state_machine.current_state
	check(evoker.Max_health == 300 and evoker.health == 300,"evoker begins at 300/300 HP")
	check(evoker.is_multiplayer_authority(),"local combat authority handles the save")
	var health_events:Array[Vector2i] = []
	evoker.health_bar.health_changed.connect(func(before:int,after:int,_max:int,_tween:bool): health_events.append(Vector2i(before,after)))
	var other_source:Node = Node.new()
	world.add_child(other_source)
	for kind:String in ["poison","wither","slowness","weakness","levitation","bad_omen"]:
		check(EFFECTS.apply_effect(evoker,kind,1,20.0,enemy),"install negative "+kind)
	check(EFFECTS.apply_effect(evoker,"poison",2,22.0,other_source),"second independent poison source")
	check(EFFECTS.apply_effect(evoker,"speed",1,20.0,other_source),"existing positive status")
	var poison:Node = EFFECTS.current(evoker,"poison")
	check(poison != null and poison.applications.size() == 2,"two harmful sources coexist before cleansing")
	check(NATIVE_AUDIO.EVENTS.has("item.totem.use") and NATIVE_AUDIO.EVENTS["item.totem.use"][0].stream != null,"actual native totem-use audio resource is loaded")
	# A full-lethal raw hit exercises the same setter used by normal hits,
	# potions and direct health loss. The bar must never announce 0 HP.
	evoker.receive_spatial_raw_health_damage(1000.0,{"point":center,"shape":"all","source":enemy})
	check(evoker.health == 50 and evoker._totem_used,"lethal hit immediately saves once with exactly 50 HP")
	var ever_zero:bool = false
	for event:Vector2i in health_events:
		if event.y <= 0: ever_zero = true
	check(not ever_zero and evoker.state_machine.current_state != 2,"totem prevents actual death, zero-health signal and death state")
	check(not evoker._combat_death_reported and is_instance_valid(evoker) and not evoker.is_queued_for_deletion(),"saved evoker remains a live combatant")
	var fx_list:Array[Node] = active_fx()
	check(fx_list.size() == 1,"exactly one detached original totem animation appears")
	if fx_list.size() == 1:
		var fx:Node = fx_list[0]
		check(fx.totem_sprite.texture == FX.ITEM and fx.particles.size() == FX.PARTICLE_COUNT,"original totem icon and native glitter burst are reused")
		check(fx.get_parent() != evoker,"totem animation survives owner removal")
	evoker._show_totem_visual()
	check(active_fx().size() == 1,"replayed visual packet cannot duplicate the burst")
	var sound_uses:int = 0
	for sound:Node in get_nodes_in_group("MCNativeSFX"):
		if str(sound.get_meta("mc_sound_event","")) == "item.totem.use": sound_uses += 1
	check(sound_uses == 1,"original totem sound plays once, not evoker death sound")
	var negative_clear:bool = true
	for kind:String in EFFECTS.all_kinds():
		if not EFFECTS.positive(kind) and EFFECTS.active(evoker,kind): negative_clear = false
	check(negative_clear,"all negative Minecraft effects (including both poison casters) are cleared")
	check(EFFECTS.level_of(evoker,"speed") == 1,"existing positive potion stays")
	check(EFFECTS.level_of(evoker,"regeneration") == 2 and EFFECTS.level_of(evoker,"fire_resistance") == 1 and EFFECTS.level_of(evoker,"absorption") == 2,"Regeneration II, Fire Resistance I and Absorption II applied")
	for kind:String in ["regeneration","fire_resistance","absorption"]:
		var status:Node = EFFECTS.current(evoker,kind)
		check(status != null and is_equal_approx(float(status.remaining),10.0),kind+" begins with ten game seconds")
	var shield:Node = EFFECTS.current(evoker,"absorption")
	check(is_equal_approx(float(shield.absorption_remaining),40.0),"Absorption II supplies 40 real temporary HP")
	var before:int = evoker.health
	check(not evoker.receive_fire_positional_damage(25.0,evoker.global_position,false,enemy) and evoker.health == before,"real fire hits are blocked by Fire Resistance")
	evoker.receive_spatial_raw_health_damage(23.0,{"point":center,"shape":"all","source":enemy})
	check(evoker.health == before and is_equal_approx(float(shield.absorption_remaining),17.0),"non-fire damage drains absorption before the 50 real HP")
	# Game-clock duration, not a permanent script flag: regen actually heals,
	# and all three independent effects expire together after 10 game seconds.
	check(EFFECTS.current(evoker,"regeneration").can_process(),"real game physics can advance timed effects")
	await create_timer(10.4).timeout
	check(evoker.health > 50 and evoker.health <= 300,"Regeneration II actually heals over time")
	check(EFFECTS.level_of(evoker,"regeneration") == 0 and EFFECTS.level_of(evoker,"fire_resistance") == 0 and EFFECTS.level_of(evoker,"absorption") == 0,"all three buffs expire after ten game seconds")
	check(EFFECTS.level_of(evoker,"speed") == 1,"independent positive status remains after totem buffs expire")
	check(active_fx().is_empty(),"item animation and particles remove themselves")
	# Totem is consumed; the next lethal hit follows normal Minecraft death.
	evoker.health = 0
	check(evoker.health == 0 and evoker._totem_used and active_fx().is_empty(),"second lethal hit is NOT saved or replayed")
	await physics_frame
	await physics_frame
	check(not is_instance_valid(evoker) or evoker.state_machine.current_state != state_before,"second death runs the regular state machine")
	# If an existing effect protected exactly 50 HP, equal-value writes must
	# still fire the one-shot callback. Forced void removal must not consume it.
	var edge:Node2D = spawn("res://scenes/characters/我的世界/唤魔者.tscn",center+Vector2(220,0),"Team0")
	edge.health = 50
	edge.health = 0
	check(edge.health == 50 and edge._totem_used and EFFECTS.level_of(edge,"absorption") == 2,"totem works when revived HP equals previous HP")
	var edge_fx:Array[Node] = active_fx()
	edge.queue_free()
	await process_frame
	check(edge_fx.size() == 1 and is_instance_valid(edge_fx[0]),"FX continues after saved evoker leaves the tree")
	var forced:Node2D = spawn("res://scenes/characters/我的世界/唤魔者.tscn",center+Vector2(-220,0),"Team0")
	forced.set_meta(&"__out_of_bounds_forced_death",true)
	forced.health = 0
	check(forced.health == 0 and not forced._totem_used and active_fx().size() == 1,"forced map removal does not trigger a totem")
	var replica:Node2D = spawn("res://scenes/characters/我的世界/唤魔者.tscn",center+Vector2(-260,0),"Team0")
	replica.set_multiplayer_authority(2)
	replica.health = 0
	check(not replica._totem_used and EFFECTS.level_of(replica,"absorption") == 0 and active_fx().size() == 1,"non-authority cannot resolve or duplicate revival")
	await create_timer(1.8).timeout
	check(active_fx().is_empty(),"orphaned totem particles also clean up on their own")
	print("EVOKER_TOTEM_RESULT checks=",checks," failures=",failures)
	game.Game_Settings = saved
	game.now_stop_state = original_stop
	world.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
