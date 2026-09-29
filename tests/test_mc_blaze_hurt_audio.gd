extends "res://tests/test_mc_frontier.gd"

const HURT_EVENT:String = "entity.player.hurt"

var FIREBALL_SCRIPT:Script = null
var FIRE_PATCH_SCRIPT:Script = null
var HURT_SFX:Script = null

func clear_hurt_audio(victims:Array[Node] = []) -> void:
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		if str(node.get_meta("mc_sound_event","")) != HURT_EVENT:
			continue
		node.call("stop")
		node.remove_from_group("MCNativeSFX")
		node.queue_free()
	for victim:Node in victims:
		if is_instance_valid(victim) and victim.has_meta("mc_event_sound_entity_player_hurt"):
			victim.remove_meta("mc_event_sound_entity_player_hurt")

func hurt_players(kind:String = "") -> Array[Node]:
	var players:Array[Node] = []
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		if str(node.get_meta("mc_sound_event","")) != HURT_EVENT:
			continue
		if not kind.is_empty() and str(node.get_meta("mc_damage_kind","")) != kind:
			continue
		players.append(node)
	return players

func fireball_at(source:Node2D,target:Node2D,damage:float,multiplier:float = 1.0) -> Node2D:
	clear_hurt_audio([target])
	source.Damage = damage
	var shot:Node2D = FIREBALL_SCRIPT.new() as Node2D
	shot.set_physics_process(false)
	world.add_child(shot)
	shot.global_position = target.global_position + Vector2(-110.0,0.0)
	shot.call("configure",source,source.Team,Vector2.RIGHT,700.0,multiplier,3.2,0.10,34.0,4.5,0.11,0.05)
	shot.call("_physics_process",0.25)
	return shot

func fire_patch_at(source:Node2D,position_value:Vector2,area_multiplier:float = 0.11) -> Node2D:
	var patch:Node2D = FIRE_PATCH_SCRIPT.new() as Node2D
	patch.set_physics_process(false)
	world.add_child(patch)
	patch.call("setup",source,source.Team,position_value,56.0,4.5,0.50,area_multiplier,2.2,0.05)
	return patch

func restore_victim(victim:Node2D) -> void:
	victim.health = 10000
	victim.block = 0
	victim.max_block = 0
	victim.Damage_reduction = 0.0

func run() -> void:
	var center:Vector2 = await setup_world()
	FIREBALL_SCRIPT = load("res://scripts/effects/我的世界/烈焰弹.gd") as Script
	FIRE_PATCH_SCRIPT = load("res://scripts/effects/我的世界/烈焰火场.gd") as Script
	HURT_SFX = load("res://scripts/effects/我的世界/女巫药水伤害音效.gd") as Script
	check(FIREBALL_SCRIPT != null and FIRE_PATCH_SCRIPT != null and HURT_SFX != null,"Blaze scripts load after the live Game singleton exists")
	create_timer(75.0).timeout.connect(func(): finish(2))
	var source:Node2D = actor("烈焰人",center + Vector2(-520.0,0.0))
	var victim:Node2D = dummy(center + Vector2(80.0,0.0))
	var ally:Node2D = dummy(center + Vector2(80.0,300.0),"Team0")
	var immune:Node2D = dummy(center + Vector2(80.0,600.0))
	immune.fire_effect_ratio = 0.0
	await physics_frame
	await physics_frame
	await process_frame

	check(HURT_SFX.impact_volume(1.0) < HURT_SFX.impact_volume(10.0) and HURT_SFX.impact_volume(10.0) < HURT_SFX.impact_volume(100.0),"volume increases with actual damage")
	check(HURT_SFX.impact_volume(0.0) >= -24.0 and HURT_SFX.impact_volume(100000.0) <= 2.0,"volume curve stays safely bounded")

	restore_victim(victim)
	var low_before:float = float(victim.health)
	var low_shot:Node2D = fireball_at(source,victim,30.0)
	var low_actual:float = low_before - float(victim.health)
	var direct:Array[Node] = hurt_players("blaze_fireball")
	check(low_actual > 0.0,"fireball direct hit deals real health loss")
	check(direct.size() == 1,"direct hit emits exactly one MC hurt sound")
	if direct.size() == 1:
		var quiet_player:AudioStreamPlayer2D = direct[0] as AudioStreamPlayer2D
		check(quiet_player.stream in HURT_SFX.DAMAGE_SFX,"direct hit uses the official hit1-hit3 MC hurt variants")
		check(quiet_player.get_meta("mc_damage_source") == source.get_instance_id(),"direct hurt sound identifies the Blaze source")
		check(is_equal_approx(float(quiet_player.get_meta("mc_actual_damage")),low_actual),"direct hit records actual health damage")
		check(is_equal_approx(quiet_player.volume_db,HURT_SFX.impact_volume(low_actual)),"direct hit volume follows actual damage")
		low_shot.free()
	else:
		low_shot.free()

	restore_victim(victim)
	var high_before:float = float(victim.health)
	fireball_at(source,victim,120.0)
	var high_actual:float = high_before - float(victim.health)
	direct = hurt_players("blaze_fireball")
	check(high_actual > low_actual and direct.size() == 1,"stronger fireball deals and reports more damage")
	if direct.size() == 1:
		var loud_player:AudioStreamPlayer2D = direct[0] as AudioStreamPlayer2D
		check(loud_player.volume_db > HURT_SFX.impact_volume(low_actual),"larger direct damage is louder")

	restore_victim(victim)
	victim.Damage_reduction = 0.8
	var reduced_before:float = float(victim.health)
	fireball_at(source,victim,100.0)
	var reduced_actual:float = reduced_before - float(victim.health)
	direct = hurt_players("blaze_fireball")
	check(reduced_actual > 0.0 and reduced_actual < 100.0,"damage reduction changes post-mitigation health loss")
	if direct.size() == 1:
		var reduced_player:AudioStreamPlayer2D = direct[0] as AudioStreamPlayer2D
		check(is_equal_approx(reduced_player.volume_db,HURT_SFX.impact_volume(reduced_actual)),"volume uses reduced actual loss, not raw outgoing damage")
		check(not is_equal_approx(reduced_player.volume_db,HURT_SFX.impact_volume(100.0)),"raw outgoing damage is not used for volume")

	restore_victim(victim)
	victim.max_block = 1000
	victim.default_properties.max_block = 1000
	victim.block = 1000
	var shield_before:float = float(victim.health)
	fireball_at(source,victim,100.0)
	check(float(victim.health) == shield_before and hurt_players("blaze_fireball").is_empty(),"shield-only damage has no hurt sound")

	restore_victim(victim)
	var patch_before:float = float(victim.health)
	var patch:Node2D = fire_patch_at(source,victim.global_position,0.11)
	clear_hurt_audio([victim])
	patch.call("_damage_inside",source)
	var patch_actual:float = patch_before - float(victim.health)
	var ground:Array[Node] = hurt_players("blaze_ground_fire")
	check(patch_actual > 0.0 and ground.size() == 1,"ground fire tick deals real damage and emits one MC hurt sound")
	if ground.size() == 1:
		var ground_player:AudioStreamPlayer2D = ground[0] as AudioStreamPlayer2D
		check(ground_player.stream in HURT_SFX.DAMAGE_SFX,"ground fire uses the official hit1-hit3 MC hurt variants")
		check(is_equal_approx(ground_player.volume_db,HURT_SFX.impact_volume(patch_actual)),"ground fire volume follows actual health loss")
		check(ground_player.global_position.is_equal_approx(victim.global_position),"ground fire hurt sound is positioned on the burning victim")
	clear_hurt_audio([victim])
	patch.call("_damage_inside",source)
	check(hurt_players("blaze_ground_fire").size() == 1,"each effective ground-fire damage tick can emit its hurt feedback")
	patch.free()

	clear_hurt_audio([ally])
	var ally_patch:Node2D = fire_patch_at(source,ally.global_position,0.11)
	ally_patch.call("_damage_inside",source)
	check(hurt_players("blaze_ground_fire").is_empty(),"friendly fire filtering does not create hurt audio")
	ally_patch.free()

	clear_hurt_audio([immune])
	var immune_before:float = float(immune.health)
	var immune_patch:Node2D = fire_patch_at(source,immune.global_position,0.11)
	immune_patch.call("_damage_inside",source)
	check(float(immune.health) == immune_before and hurt_players("blaze_ground_fire").is_empty(),"fire immunity avoids false hurt audio")
	immune_patch.free()

	print("BLAZE_HURT_AUDIO_RESULT checks=",checks," failures=",failures)
	finish(0 if failures == 0 else 1)
