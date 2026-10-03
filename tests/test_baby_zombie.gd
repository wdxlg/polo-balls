extends "res://tests/test_mc_bat_transform.gd"
const BABY_PATH:String = "res://scenes/characters/我的世界/小僵尸.tscn"
const ADULT_PATH:String = "res://scenes/characters/我的世界/僵尸.tscn"
func unit(path:String,point:Vector2,team:String) -> Node2D:
	var node:Node2D = spawn(path,point,team)
	node.state_machine.set_physics_process(false)
	node.Has_Collision_Damage = false
	return node
func dummy(point:Vector2,team:String) -> Node2D:
	var node:Node2D = unit("res://scenes/ball.tscn",point,team)
	node.Max_health = 10000
	node.default_properties.Max_health = 10000
	node.health = 10000
	node.block = 0
	node.max_block = 0
	node.Damage_reduction = 0
	node.default_properties.Damage_reduction = 0
	node.Speed = 0
	return node
func wall(point:Vector2,size:Vector2) -> StaticBody2D:
	var node := StaticBody2D.new()
	node.collision_layer = 1
	node.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	node.add_child(shape)
	world.add_child(node)
	node.global_position = point
	return node
func steps(node:Node2D,seconds:float,move:bool = false) -> void:
	for i:int in range(int(seconds/0.05)):
		node.step_zombie(0.05)
		if move: node.move(node.Speed,0.05)
func run() -> void:
	var center:Vector2 = await setup_world()
	game._settings_storage_path = "user://baby_zombie_fixture_settings.cfg"
	create_timer(90.0).timeout.connect(func(): finish(2))
	var adult_scene:Node = load(ADULT_PATH).instantiate()
	var baby:Node2D = unit(BABY_PATH,center,"Team0")
	await physics_frame
	await process_frame
	check(baby.Max_health == adult_scene.Max_health and baby.health == 100 and baby.Damage == adult_scene.Damage,"same health and damage as the zombie")
	check(is_equal_approx(baby.Speed,adult_scene.Speed*1.5) and is_equal_approx(baby.Attack_Cooling,1.0),"1.5x speed and 20-tick melee cooldown")
	var adult_body:Vector2 = adult_scene.get_node("CollisionShape2D").shape.size
	var baby_body:Vector2 = baby.collision_shape_2d.shape.size
	check(absf(baby_body.y/adult_body.y-0.5) < 0.02,"half-height body: %s vs %s" % [baby_body,adult_body])
	adult_scene.free()
	check(baby.is_in_group("MinecraftZombie") and baby.voice.voice_pitch == Vector2(1.5,0.2),"baby voice pitch 1.5 +/- 0.2")
	check(baby.voice.events.has_all(["ambient","step","hurt","death"]),"reuses original zombie sounds")
	check(baby.player_control_action_ids() == [&"controlled_attack_action"],"one manual attack")
	check(not baby.get_armor_test_effect_summary().is_empty() and game.t("小僵尸") != "","names and introduction present")
	# Idle: wander with pauses.
	var strolled:bool = false
	var paused:bool = false
	var start:Vector2 = baby.global_position
	for i:int in range(600):
		baby.step_zombie(0.05)
		baby.move(baby.Speed,0.05)
		if baby.baby_moving: strolled = true
		elif strolled: paused = true
	check(strolled and paused,"no target: random stroll then pause")
	check(baby.global_position.distance_to(start) > 20.0,"stroll actually moves the body")
	check(baby.mc_arena_rect().has_point(baby.global_position),"stroll stays inside arena")
	# Sight-based acquisition and chase.
	baby.global_position = center
	baby.baby_strolling = false
	var enemy:Node2D = dummy(center+Vector2(220,0),"Team1")
	await create_timer(0.25).timeout # targeting snapshot refreshes on world ticks
	steps(baby,3.0)
	check(baby.baby_target != null and baby.baby_target.get_ref() == enemy,"acquires the visible enemy")
	check(baby.direction.x > 0.9 and baby.baby_moving,"chases toward the enemy")
	check(enemy.health == 10000,"no hit outside reach")
	# Melee: vanilla reach, instant hit, 1s cooldown, keeps pressing.
	var reach:float = baby.bite_reach()
	var half:float = enemy.global_position.x-baby.body_point(enemy,center).x
	check(absf(reach-(0.49*0.5+0.828)*64.0) < 0.5,"vanilla attack box reach %.1f" % reach)
	enemy.global_position = center+Vector2(reach-8.0+half,0)
	await physics_frame
	baby.bite_cooldown = 0.0
	baby.step_zombie(0.05)
	check(enemy.health == 10000-18,"arm swing deals 18 instantly: %s" % enemy.health)
	check(baby.baby_swing_clock >= 0.0,"swing animation starts")
	check(baby.baby_moving,"keeps closing in while attacking")
	check(baby.get_ai_attack_threats().size() == 1,"exposes melee reach to AI")
	baby._process(0.05)
	var frames:SpriteFrames = baby.body_frames()
	var in_attack:bool = false
	for name:StringName in [&"attack_idle",&"attack_walk"]:
		for f:int in range(frames.get_frame_count(name)):
			if frames.get_frame_texture(name,f) == baby.image.texture: in_attack = true
	check(in_attack,"shows an arm-swing frame")
	enemy.global_position = center+Vector2(reach-8.0+half,0)
	steps(baby,0.5)
	check(enemy.health == 10000-18,"no second hit before cooldown")
	enemy.global_position = center+Vector2(reach-8.0+half,0)
	steps(baby,0.6)
	check(enemy.health == 10000-36,"second hit after 1s: %s" % enemy.health)
	# Losing sight for 3s drops the target.
	enemy.global_position = center+Vector2(260,0)
	var block:StaticBody2D = wall(center+Vector2(130,0),Vector2(8,400))
	await physics_frame
	steps(baby,2.5)
	check(baby.baby_target != null and baby.baby_target.get_ref() == enemy,"keeps target briefly when unseen")
	steps(baby,1.0)
	check(baby.baby_target == null or baby.baby_target.get_ref() == null,"drops target after 3s unseen")
	steps(baby,3.0)
	check(baby.baby_target == null or baby.baby_target.get_ref() == null,"does not acquire through walls")
	# Hurt by target: lock onto attacker, alert idle same-team zombies only.
	var attacker:Node2D = dummy(center+Vector2(-200,0),"Team1")
	var ally:Node2D = unit(BABY_PATH,center+Vector2(0,150),"Team0")
	var busy:Node2D = unit(BABY_PATH,center+Vector2(0,-150),"Team0")
	var foe:Node2D = unit(BABY_PATH,center+Vector2(-60,150),"Team1")
	var adult:Node2D = unit(ADULT_PATH,center+Vector2(60,150),"Team0")
	await physics_frame
	busy.baby_lock(enemy)
	baby.receive_classified_positional_damage(5.0,baby.global_position,&"ordinary",false,attacker,{"carrier":"body_contact"})
	check(baby.baby_target.get_ref() == attacker,"hurt: locks onto attacker")
	check(ally.baby_target != null and ally.baby_target.get_ref() == attacker,"alerts idle same-team zombie")
	check(busy.baby_target.get_ref() == enemy,"zombie that already has a target keeps it")
	check(foe.baby_target == null,"other team not alerted")
	check(baby.health == 95,"hurt amount applied")
	ally.baby_target = null
	ally.baby_hurt_by(attacker)
	check(ally.baby_target.get_ref() == attacker,"direct hurt hook locks attacker")
	block.queue_free()
	adult.queue_free()
	enemy.queue_free()
	attacker.queue_free()
	var bar:CanvasItem = baby.get_node_or_null("Health_Bar")
	var frame:Texture2D = baby.image.texture
	var used:Rect2i = frame.get_image().get_used_rect()
	var top:float = baby.image.position.y+(used.position.y-frame.get_height()*0.5)*baby.image.scale.y
	check(bar != null and bar.visible and bar.position.y < top,"health bar cleared above the small body: bar %.0f vs head %.0f" % [bar.position.y,top])
	baby.receive_classified_positional_damage(40.0,baby.global_position,&"ordinary",false,attacker,{"carrier":"body_contact"})
	check(baby.health/baby.Max_health < 0.6,"damage reaches the health bar")
	finish(0)
