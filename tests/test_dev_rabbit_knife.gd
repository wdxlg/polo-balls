extends SceneTree

const RABBIT_PATH:String = "res://scenes/characters/动物/兔子.tscn"
const BREED_EFFECT_PATH:String = "res://scenes/effects/兔子繁殖特效.tscn"
const KNIFE_PATH:String = "res://scenes/characters/meme/愤怒的普通人.tscn"
var checks:int = 0
var failures:int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if ok:
		print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func run() -> void:
	var game:Node = root.get_node("Game")
	var original:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Development_Mode = true
	game.Game_Settings.Development_Duration = 30.0
	game.Game_Settings.Development_Speed = 2.0
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Map_Background = "blue"
	AudioServer.set_bus_mute(0,true)
	var w:Node2D = load("res://scenes/world.tscn").instantiate()
	w.tree_entered.connect(func(): current_scene = w,CONNECT_ONE_SHOT)
	root.add_child(w)
	if is_instance_valid(w._mc_prewarmer): w._mc_prewarmer.free()
	await process_frame
	await process_frame
	w.control.team.show()
	var base_center:Vector2 = w._development.base_rect.get_center()
	var right:Rect2 = Rect2(w._development.base_rect.position+w._development._offset("right:0"),w._development.base_rect.size)
	var rabbit:Node2D = w._spawn_character_from_setup({"id":201,"char":"兔子","scene_path":RABBIT_PATH,"team":"Team1","x":base_center.x,"y":base_center.y,"development_base_position":true,"development_lane_key":"right:0"})
	await process_frame
	await process_frame
	var partner:Node2D = null
	for node:Node in get_nodes_in_group("Ball"):
		if node != rabbit and is_instance_valid(node) and node.scene_file_path == RABBIT_PATH and not node.is_baby:
			partner = node as Node2D
			break
	if partner == null:
		check(false,"original rabbit creates its adult partner")
		game.Game_Settings = original
		w.queue_free()
		quit(2)
		return
	check(right.has_point(partner.global_position) and str(partner.get_meta("development_lane_key","")) == "right:0","initial rabbit partner starts in the parent's arena, not at the upper-left origin")
	check(partner.process_mode == Node.PROCESS_MODE_DISABLED and rabbit.process_mode == Node.PROCESS_MODE_DISABLED,"both adult rabbits are frozen during setup")
	rabbit.global_position = Vector2(right.position.x+30.0,base_center.y-7.0)
	partner.global_position = Vector2(right.position.x+30.0,base_center.y+7.0)
	var spawn_point:Vector2 = rabbit._choose_safe_baby_position(partner)
	check(right.has_point(spawn_point),"rabbit breeding clamps to the parent's own arena, not the gap between copies")
	var breed_midpoint:Vector2 = (rabbit.global_position+partner.global_position)*0.5
	var first_effect_positions:Array[Vector2] = []
	var listen_effect:Callable = func(node:Node) -> void:
		if node is Node2D and node.scene_file_path == BREED_EFFECT_PATH:
			first_effect_positions.append((node as Node2D).global_position)
	node_added.connect(listen_effect)
	rabbit._spawn_baby_with(partner)
	await process_frame
	node_added.disconnect(listen_effect)
	check(not first_effect_positions.is_empty() and first_effect_positions[0].distance_to(breed_midpoint) < 1.0,"breeding hearts and sound start at the rabbits' midpoint before entering the tree")
	var baby:Node2D = null
	for node:Node in get_nodes_in_group("Ball"):
		if node != rabbit and node != partner and node.scene_file_path == RABBIT_PATH and node.is_baby:
			baby = node as Node2D
			break
	check(baby != null and right.has_point(baby.global_position) and str(baby.get_meta("development_lane_key","")) == "right:0","newborn rabbit has valid arena and position from its first tree event")
	if baby != null:
		check(baby.process_mode == Node.PROCESS_MODE_DISABLED,"newborn respects setup freeze")
	var left:Node2D = w._spawn_character_from_setup({"id":202,"char":"Test","scene_path":"res://scenes/ball.tscn","team":"Team0","x":base_center.x,"y":base_center.y,"development_base_position":true,"development_lane_key":"left:0"})
	left.Can_Attack = false
	left.Can_Skill = false
	w.control.team.hide()
	w._development.update(0.2)
	check(partner.process_mode != Node.PROCESS_MODE_DISABLED and (baby == null or baby.process_mode != Node.PROCESS_MODE_DISABLED),"new adults and babies participate once development begins")
	if baby != null:
		baby._play_damage_camera_feedback_local(1600.0,false)
		var impact:Node2D = w._combat_impact_layer
		var fx_at_baby:bool = impact != null and not impact._particles.is_empty()
		if fx_at_baby:
			for p:Dictionary in impact._particles:
				fx_at_baby = fx_at_baby and (p["origin"] as Vector2).distance_to(baby.global_position) < 72.0
		check(fx_at_baby and w._damage_focus_pending_position.distance_to(baby.global_position) < 1.0,"rabbit impact and camera focus start at its real position, not the upper-left origin")
	w._development.update(30.0)
	await create_timer(1.7,true,false,true).timeout
	check(w._development.phase == w._development.BATTLE and is_instance_valid(partner) and w.return_map_world_rect(w._current_map_node()).has_point(partner.global_position),"rabbit family retains valid positions after merge")
	rabbit.global_position = base_center+Vector2(-12.0,-7.0)
	partner.global_position = base_center+Vector2(-12.0,7.0)
	rabbit._spawn_baby_with(partner)
	var battle_baby:Node2D = null
	for node:Node in get_nodes_in_group("Ball"):
		if node != baby and node != rabbit and node != partner and node.scene_file_path == RABBIT_PATH and node.is_baby:
			battle_baby = node as Node2D
			break
	check(battle_baby != null and w.return_map_world_rect(w._current_map_node()).has_point(battle_baby.global_position),"breeding after the merge also creates a baby inside the real battlefield")
	var knife:Node2D = load(KNIFE_PATH).instantiate()
	knife.Team = "Team0"
	knife.position = w.to_local(base_center)
	w.add_child(knife,true)
	var sprite:Sprite2D = knife.get_node("KnifeHitbox/KnifeVisual")
	var shape:CollisionShape2D = knife.get_node("KnifeHitbox/CollisionShape2D")
	check(sprite.global_position.distance_to(knife.global_position) < 32.0,"idle knife is held next to the character")
	check(sprite.global_position.distance_to(shape.global_position) < 1.0,"knife artwork stays aligned with hitbox")
	knife._place_knife(knife.knife_max_distance)
	check(sprite.global_position.distance_to(knife.global_position) < 80.0,"stab reaches forward without detaching from the character")
	var victim:Node2D = load("res://scenes/ball.tscn").instantiate()
	victim.Team = "Team1"
	victim.position = w.to_local(base_center+Vector2(55.0,0.0))
	w.add_child(victim,true)
	victim.Can_Attack = false
	victim.Can_Skill = false
	victim.Max_health = 500
	victim.health = 500
	# 固定攻击姿态两个物理帧，让缩短后的真实 Area2D 与敌方 Hurtbox 碰撞；
	# 测完后场景整体释放，不影响正常的自动攻击状态机。
	knife.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	knife.set_physics_process(false)
	knife._stab_direction = Vector2.RIGHT
	knife.Attacking = true
	knife._place_knife(knife.knife_max_distance)
	knife._set_knife_active(true)
	await physics_frame
	await physics_frame
	check(victim.health < 500,"shortened knife retains a working thrust hitbox and applies damage")
	game.Game_Settings = original
	w.queue_free()
	print("Rabbit/knife checks: ",checks,"; failures: ",failures)
	quit(1 if failures > 0 else 0)
