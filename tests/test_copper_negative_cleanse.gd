extends "res://tests/test_copper_sword.gd"
var EFFECTS:Script
var COLD:Script
var BURN:Script
var CLEANSE:Script

class FutureStatus extends Node:
	var sign:int = -1
	var released:bool = false
	func get_status_effect_polarity() -> int: return sign
	func cleanse_status_effect() -> void: released = true

func freeze_statuses(unit:Node) -> void:
	for child:Node in unit.get_children():
		if CLEANSE.polarity(child)!=0:
			child.set_physics_process(false)
			child.set_process(false)

func natural(unit:Node2D) -> Node:
	unit.rust = 1.0
	unit.charged_left = 0.0
	unit._advance_rust(0.01)
	var bolt:Node = unit._cleanse_effect
	check(is_instance_valid(bolt),"natural rust cycle creates a real lightning effect")
	if is_instance_valid(bolt): bolt.set_process(false)
	return bolt

func run() -> void:
	CLEANSE = load("res://classes/status_cleansing.gd")
	BURN = load("res://scripts/effects/我的世界/mc_shared_burn.gd")
	COLD = load("res://scripts/characters/我的世界/snow_golem/cold.gd")
	EFFECTS = load("res://scripts/effects/我的世界/mc_status_effects.gd")
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(80.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"real World resources loaded")
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var unit:Node2D = copper(center)
	var caster:Node2D = dummy(center+Vector2(400,0))
	var other:Node2D = dummy(center+Vector2(-400,0))
	await physics_frame
	world.set_physics_process(false)
	for actor:Node2D in units: actor.set_physics_process(false)
	# Exercise every currently registered persistent potion, not a cherry-picked list.
	var positive:Dictionary = {}
	for kind:String in EFFECTS.all_kinds():
		if EFFECTS.is_instant(kind): continue
		EFFECTS.apply_effect(unit,kind,2,30.0,caster)
		var effect:Node = EFFECTS.current(unit,kind)
		check(is_instance_valid(effect),"actual catalog installs "+kind)
		if EFFECTS.positive(kind): positive[kind] = effect
	freeze_statuses(unit)
	var death_status:Node = EFFECTS.current(unit,"oozing")
	var infested_status:Node = EFFECTS.current(unit,"infested")
	var slow:Node = EFFECTS.current(unit,"slowness")
	EFFECTS.apply_effect(unit,"slowness",3,INF,other)
	check(slow.applications.size()==2,"one negative potion holds multiple finite/infinite sources")
	world.refresh_runtime_buffs(unit)
	var hp:float = unit.health
	var clock:float = world.process_time
	var bolt:Node = natural(unit)
	bolt._process(unit.lightning_warning*0.5)
	check(EFFECTS.current(unit,"poison")!=null and unit._negative_cleanse_revision==0,"warning cannot clear any negative effects")
	game.now_stop_state = true
	bolt._process(5.0)
	check(EFFECTS.current(unit,"poison")!=null and unit._negative_cleanse_revision==0,"pause freezes the real warning/cleanse")
	game.now_stop_state = false
	bolt._process(unit.lightning_warning)
	for kind:String in EFFECTS.all_kinds():
		if EFFECTS.is_instant(kind): continue
		check(EFFECTS.current(unit,kind)==positive.get(kind,null),"cleanse polarity is correct for "+kind)
	check(not unit.health_bar.health_changed.is_connected(infested_status._on_health_changed) and not unit.health_bar.health_changed.is_connected(death_status._on_health_changed),"negative on-hit/death triggers disconnected before deferred deletion")
	death_status._on_owner_death()
	check(not death_status._death_triggered and death_status.remaining==0.0 and death_status.applications.is_empty(),"stale death callback cannot resurrect removed potion source lifetimes")
	check(unit.health==hp and world.process_time==clock,"cleansing neither heals/replays DOT nor advances the shared poison clock")
	check(unit.cleanse_count==1 and unit.rust==0.0 and unit.charged_left==unit.charged_duration,"natural impact preserves rust reset and electrical charge")
	check(unit.Speed>float(unit.default_properties.Speed),"retained positive speed applies immediately")
	check(unit.Damage>int(unit.default_properties.Damage),"retained strength applies immediately")
	EFFECTS.apply_effect(unit,"poison",1,10.0,caster)
	freeze_statuses(unit)
	var reapplied:Node = EFFECTS.current(unit,"poison")
	check(reapplied!=null,"no immunity window: another hit reapplies poison in the same frame")
	bolt._process(1.0)
	unit._on_lightning_impact(unit.global_position,true)
	check(EFFECTS.current(unit,"poison")==reapplied and unit.cleanse_count==1,"duplicate natural impacts cannot cleanse a newly reapplied status")
	unit._show_copper_lightning(unit.global_position,74,false)
	var attack_bolt:Node = bolts(unit).back()
	attack_bolt.set_process(false)
	attack_bolt._process(unit.hit_lightning_warning+0.01)
	check(EFFECTS.current(unit,"poison")==reapplied and unit.cleanse_count==1,"actual charged-attack lightning does NOT cleanse")
	# A new actor without fire-resistance/invisibility for body/DOT/control cleanup.
	unit = copper(center+Vector2(0,150))
	unit.set_physics_process(false)
	var tint:Color = unit.image.modulate
	var self_tint:Color = unit.image.self_modulate
	check(BURN.apply_amount(caster,unit,15.0,3.0),"native shared fire is active")
	var blade:Node = load("res://scripts/status/锻刀师_燃烧.gd").new()
	unit.add_child(blade); blade.setup(unit,caster,15.0)
	var bleed:Node = load("res://scripts/status/剑客_流血.gd").new()
	unit.add_child(bleed); bleed.setup(unit,caster,2,5,15.0,2.0,0.5,1.0)
	var dagger:Node = load("res://scripts/status/面包车_匕首流血.gd").new()
	unit.add_child(dagger); dagger.setup(unit,caster,15.0)
	EFFECTS.apply_effect(unit,"wither",2,15.0,caster)
	var karma:Node = load("res://scripts/effects/传说之下/Sans业力.gd").new()
	unit.add_child(karma); karma.add_karma(12,caster)
	var cold:Node = COLD.ensure(unit)
	cold.add_cold(100,4.0,caster)
	unit.apply_stun(3.0,caster)
	freeze_statuses(unit)
	check(unit.dizziness and cold.frozen_left>0.0,"real cold freeze and stun own control leases")
	EFFECTS.apply_effect(unit,"strength",2,20.0,caster)
	EFFECTS.apply_effect(unit,"resistance",2,20.0,caster)
	freeze_statuses(unit)
	var positive_strength:Node = EFFECTS.current(unit,"strength")
	var future:Node = FutureStatus.new(); unit.add_child(future)
	var external:Node = FutureStatus.new(); world.add_child(external); unit.register_status_effect(external)
	var good:Node = FutureStatus.new(); good.sign = 1; unit.add_child(good)
	var neutral:Node = FutureStatus.new(); neutral.sign = 0; unit.add_child(neutral)
	var other_bad:Node = FutureStatus.new(); other.add_child(other_bad)
	unit.Buff_Dic[-987] = {
		"slow":Buff.new(0,20.0,Buff.Buff_types.Speed,0.1,Buff.Algorithms.mul),
		"haste":Buff.new(1,20.0,Buff.Buff_types.Attack_Cooling,0.8,Buff.Algorithms.mul),
		"poison":Buff.new(0,20.0,Buff.Buff_types.poison,5.0),
		"寄生":Buff.new(0,20.0,Buff.Buff_types.Infection,9.0),
	}
	world.refresh_runtime_buffs(unit)
	hp = unit.health
	bolt = natural(unit)
	bolt._process(unit.lightning_warning+0.01)
	check(not unit.has_node("MinecraftBlazeBurn") and not unit.has_node("MCSnowCold") and EFFECTS.current(unit,"wither")==null,"burn, cold/ice and wither fully detached on impact")
	check(bleed.get_parent()==null and dagger.get_parent()==null and blade.get_parent()==null and karma.get_parent()==null,"all legacy bleed/burn and Karma status holders removed")
	check(not unit.dizziness and int(unit.get_meta("generic_motion_lock_count",0))==0,"freeze and stun release their own control locks immediately")
	check(unit.image.modulate.is_equal_approx(tint) and unit.image.self_modulate.is_equal_approx(self_tint),"overlapping negative tints unwind without residual color")
	check(future.released and external.released and future.get_parent()==null and external.get_parent()==null,"unknown future negative status and registered external holder invoke their cleanup protocol")
	check(good.get_parent()==unit and neutral.get_parent()==unit and not good.released and not neutral.released,"future positive and neutral statuses remain untouched")
	check(other_bad.get_parent()==other and not other_bad.released,"cleansing self never removes another victim's status")
	check(unit.Buff_Dic[-987].size()==1 and unit.Buff_Dic[-987].has("haste"),"raw poison, parasite and slow removed, positive cooldown buff kept")
	check(unit.health==hp and is_equal_approx(unit.Speed,float(unit.default_properties.Speed)),"parasite removal cannot explode; speed is restored in this same frame")
	check(EFFECTS.current(unit,"strength")==positive_strength and unit.Damage>int(unit.default_properties.Damage),"positive potion keeps its exact source node/lifetime and effective property")
	# Explicit sign supports future ambiguous/resource buffs without changing consumers.
	var explicit:Buff = Buff.new(0,10.0,Buff.Buff_types.Speed,2.0,Buff.Algorithms.mul)
	explicit.effect_polarity = -1
	check(explicit.is_negative_for(unit),"explicit negative metadata overrides numerical benefit")
	for type:int in [Buff.Buff_types.Damage,Buff.Buff_types.Speed,Buff.Buff_types.Max_health,Buff.Buff_types.Damage_reduction]:
		check(Buff.new(0,5.0,type,-1).is_negative_for(unit) and not Buff.new(0,5.0,type,1).is_negative_for(unit),"legacy additive polarity "+str(type))
	check(Buff.new(0,5.0,Buff.Buff_types.Attack_Cooling,2.0,Buff.Algorithms.mul).is_negative_for(unit),"longer cooldown is negative, not positive")
	check(Buff.new(0,5.0,Buff.Buff_types.Speed,0.0,Buff.Algorithms.Set).is_negative_for(unit),"Set polarity compares against the default property")
	# A genuine wound controller must cancel an in-flight execution and its overlay.
	var wounds:Node = load("res://scripts/effects/我的世界/骷髅箭伤控制.gd").new()
	unit.add_child(wounds); wounds.setup(unit)
	var embed:Node2D = Node2D.new(); unit.image.add_child(embed); wounds.register_arrow(embed,caster)
	wounds._begin_execution()
	check(wounds._executing and wounds._red_bar!=null,"arrow execution owns a real health overlay and pending tween")
	unit.cleanse_negative_effects()
	wounds._finish_execution()
	var passed:Array[int] = [0]
	wounds._on_execution_arrow_passed_through(embed,Vector2.RIGHT,passed,1)
	check(passed[0]==0,"cancelled execution cannot launch queued arrows via stale tween callbacks")
	check(unit.health==hp and wounds._red_bar==null and embed.get_parent()==null and not wounds._executing,"cleanse cancels pending execution and refuses stale lethal callbacks")
	await process_frame
	await create_timer(0.55).timeout
	check(unit.health==hp,"cancelled DOT/arrow tweens cannot damage later")
	# Rejected natural impacts and nonauthority cannot clear negative statuses.
	EFFECTS.apply_effect(unit,"weakness",1,20.0,caster)
	freeze_statuses(unit)
	unit._cleanse_pending = true; unit.Can_Skill = false
	unit._on_lightning_impact(unit.global_position,true)
	check(EFFECTS.current(unit,"weakness")!=null,"disabled natural skill cancels instead of purging")
	unit.Can_Skill = true
	unit.set_multiplayer_authority(2)
	check(unit.cleanse_negative_effects()==0 and EFFECTS.current(unit,"weakness")!=null,"replica cannot independently request gameplay cleansing")
	unit.set_multiplayer_authority(1)
	unit.dizziness = true # Independent baseline, not owned by these negative effects.
	unit.cleanse_negative_effects()
	check(unit.dizziness,"no blanket dizziness reset that destroys independent control ownership")
	unit.dizziness = false
	var own_motion:Node = unit.apply_knockback(Vector2.RIGHT,60.0,180.0,0.0,0.0,{"source":unit})
	own_motion.set_physics_process(false)
	unit.cleanse_negative_effects()
	check(own_motion.get_parent()==unit and not own_motion.is_queued_for_deletion(),"self-powered recoil is neutral and survives cleansing")
	own_motion.cleanse_status_effect(); unit.remove_child(own_motion)
	var airborne:Node = (load("res://scripts/effects/physical_airborne_effect.gd") as GDScript).launch(unit,caster,70.0,300.0,2.0)
	airborne.set_physics_process(false)
	unit.cleanse_negative_effects()
	check(airborne.get_parent()==null and not unit.dizziness,"hostile physical airborne controller uses virtual cleanup and releases its lease")
	var layer:int = unit.collision_layer
	var mask:int = unit.collision_mask
	var sticky:Node = load("res://scripts/characters/我的世界/new5/sticky_hold.gd").new()
	sticky.target = unit; sticky.source = caster; unit.add_child(sticky); sticky.set_physics_process(false)
	check(sticky.acquired and unit.collision_layer==0 and unit.dizziness,"real sticky hold owns collision and control leases")
	unit.cleanse_negative_effects()
	check(sticky.get_parent()==null and unit.collision_layer==layer and unit.collision_mask==mask and not unit.dizziness and not unit.has_meta("mc_sticky_hold"),"sticky cleanup restores only its collision/control state")
	var embeds:Array[Node2D] = []
	for mode:int in range(3):
		var arrow:Node2D = load("res://scenes/shooter/我的世界/骷髅箭.tscn").instantiate()
		arrow._mode = mode; unit.image.add_child(arrow); arrow.set_physics_process(false); arrow.set_process(false); embeds.append(arrow)
	unit.cleanse_negative_effects()
	check(embeds[2].get_parent()==null and embeds[0].get_parent()==unit.image and embeds[1].get_parent()==unit.image,"stage-aware classification removes embedded wounds, not flying arrows or lodged terrain")
	for arrow:Node2D in embeds:
		if not arrow.is_queued_for_deletion(): arrow.queue_free()
	var honey:Node2D = spawn("res://scenes/characters/我的世界/硫方怪.tscn",unit.global_position+Vector2(5,0),"Team1")
	honey.set_process(false); honey.set_physics_process(false); honey.Can_Attack = true
	honey.set_block(honey.Block.HONEY); honey.acquire_block(honey.Block.IRON)
	honey._pull_touching_enemies(0.0)
	var path:String = str(honey.get_path_to(unit))
	check(honey.honey_target_paths.has(path) and honey.BODY_PAIRS.are_excluded(honey,unit),"real external honey holder captures the sword")
	unit.cleanse_negative_effects()
	check(not honey.honey_target_paths.has(path) and not honey.BODY_PAIRS.are_excluded(honey,unit) and not unit.wall_contact_impact.is_connected(honey._on_honey_wall_impact.bind(unit)),"shared cleanse notification releases external honey membership, collision and wall-damage callback")
	honey._pull_touching_enemies(0.01)
	check(not honey.honey_target_paths.has(path),"cleansed grab cannot instantly refresh without a new contact")
	honey.global_position += Vector2(150,0); honey._pull_touching_enemies(0.01)
	honey.global_position = unit.global_position+Vector2(5,0); honey._pull_touching_enemies(0.01)
	check(honey.honey_target_paths.has(path),"legitimate new contact reapplies control: no immunity was added")
	unit.cleanse_negative_effects()
	var pull:Script = honey.KNOCKBACK_EFFECT_SCRIPT
	pull.set_pull(unit,unit,Vector2(12,0)); pull.set_pull(unit,caster,Vector2(0,12))
	unit.cleanse_negative_effects()
	check(pull.pull_velocity(unit)==Vector2(12,0),"hostile pull contribution removed without deleting neutral self-motion")
	pull.release_pull(unit,unit)
	print("COPPER_NEGATIVE_CLEANSE_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
