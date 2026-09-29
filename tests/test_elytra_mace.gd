extends SceneTree
var checks:int = 0
var failures:int = 0
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("ELYTRA_FAIL ",label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game:Node = root.get_node("Game")
	game.now_stop_state = false
	game.Game_Settings.Have_Team_Damage = false
	var arena:Node2D = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	var packed:PackedScene = load("res://scenes/characters/我的世界/鞘翅重锤.tscn")
	check(packed != null,"scene loads")
	var mace:Node2D = packed.instantiate()
	mace.Team = "Team0"
	arena.add_child(mace)
	check(mace.Max_health == 200 and mace.health == 200,"200 HP")
	check(mace.get_node_or_null("CharacterGroundShadow") == null,"no ground shadow")
	check(mace.collision_mask == 0 and mace.collision_layer == 0,"no body blockers")
	check(mace.self_hurtbox.collision_layer != 0,"still damageable")
	check(mace.get_node_or_null("Graphics/Elytra/Left") != null,"wings exist")
	mace._rocket_cooldown = 100.0
	mace._glide_velocity = Vector2(200,0)
	mace.glide_gravity = 0.0
	mace._step_glide(0.1)
	check(mace._glide_velocity.length() < 200.0,"drag reduces momentum")
	mace.glide_gravity = 135.0
	mace._glide_velocity = Vector2.ZERO
	mace._step_glide(0.1)
	check(mace.velocity.y > 0.0,"gravity falls down")
	mace._glide_velocity = Vector2.UP * 100.0
	mace._use_firework(Vector2.UP)
	var speed:float = mace._glide_velocity.length()
	mace._step_glide(0.1)
	check(mace.velocity.y < 0.0 and absf(mace.velocity.x) < 0.001,"firework points up")
	check(mace.velocity.length() > speed,"firework accelerates")
	check(absf(angle_difference(mace.image.global_rotation,mace.velocity.angle()+PI*0.5)) < 0.001,"motion facing")
	mace._sync_air_visual_followers()
	check(mace.get_node("Graphics/Firework").visible,"rocket visual")
	mace.global_position = Vector2(-2000,-2000)
	mace._step_glide(0.1)
	check(mace.global_position.y < -2000,"outside map movement")
	mace.global_position = Vector2.ZERO
	mace._begin_flight(1)
	var hurt_before:Vector2 = mace.self_hurtbox.global_position
	mace._update_flight(0.1)
	check(mace.global_position.y < 0.0,"root really rises")
	check(mace.self_hurtbox.global_position.y < hurt_before.y,"hurtbox follows real jump")
	check(mace.graphics.position == mace._visual_base_position,"no fake visual elevation")
	# Return plane without opponents must reset the combo.
	for i:int in range(180):
		if mace._airborne:
			mace._update_flight(1.0/60.0)
	check(not mace._airborne and not mace.Attacking,"miss ends combo")
	check(mace._chain_damage_multiplier == 0.0,"miss resets damage")
	var victim:Node2D = load("res://scenes/characters/我的世界/重锤.tscn").instantiate()
	victim.Team = "Team1"
	victim.Max_health = 100000
	arena.add_child(victim)
	mace.global_position = Vector2.ZERO
	victim.global_position = Vector2.ZERO
	mace._begin_flight(1)
	var before:int = victim.health
	mace._finish_landing()
	check(victim.health < before,"inherited smash damage")
	check(mace._airborne and mace.Attacking,"hit keeps combo")
	check(mace._chain_level == 2,"hit advances chain")
	check(mace.velocity.y < 0.0,"hit physically rebounds")
	check(is_equal_approx(mace._chain_damage_multiplier,mace.base_landing_damage_multiplier*2.0),"damage doubles")
	mace._chain_level = mace.max_chain_level
	before = victim.health
	mace._finish_landing()
	check(mace._airborne and victim.health < before,"chain survives level cap")
	check(is_equal_approx(mace._chain_damage_multiplier,mace.base_landing_damage_multiplier*4.0),"damage grows beyond cap")
	# Real falling path, not only direct landing calls.
	victim.global_position = Vector2(0,0)
	mace.global_position = Vector2(0,-120)
	mace._launch_y = 100.0
	mace._glide_velocity = Vector2(0,1000)
	before = victim.health
	mace._update_flight(0.15)
	check(victim.health < before,"swept falling strike hits")
	check(mace.velocity.y < 0.0 and mace._airborne,"falling hit continues combo")
	victim.health = 1
	victim.global_position = mace.global_position
	mace._finish_landing()
	check(victim.health == 0 and mace._airborne,"lethal hit still continues combo")
	var pos:Vector2 = mace.global_position
	game.now_stop_state = true
	mace._update_flight(0.5)
	check(mace.global_position == pos,"pause freezes flight")
	game.now_stop_state = false
	check(victim.Max_health == 100000,"original mace independently configured")
	print("ELYTRA_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
