extends "res://tests/test_anvil.gd"
## Real World placement, terrain physics and anvil/stone integration. No actor facade.
const STONE_PATH:String = "res://scenes/characters/默认/石头.tscn"

func stones() -> Array[Node]:
	var result:Array[Node] = []
	for node:Node in get_nodes_in_group("PlaceableObstacle"):
		if is_instance_valid(node) and not node.is_queued_for_deletion() and world.is_ancestor_of(node): result.append(node)
	return result

func add_stone(point:Vector2) -> StaticBody2D:
	var stone:StaticBody2D = load(STONE_PATH).instantiate()
	world.add_child(stone,true)
	stone.global_position = point
	return stone

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Character_Placement_Mode = "custom"
	game.Game_Settings.Training_Boss_Intro = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(90.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3).timeout
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"stone integration preloads complete")
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var actors_before:int = get_nodes_in_group("Ball").size()
	var registered_before:int = world._battle_units_cache.size()
	var stone:Node2D = add_stone(center)
	await physics_frame
	await process_frame
	check(stone is StaticBody2D and not is_instance_of(stone,load("res://classes/ball.gd")) and not stone is CharacterBody2D,"stone really is StaticBody2D, not a stationary/invulnerable character")
	check(not stone.is_in_group("Ball") and stone.is_in_group("PlaceableObstacle"),"stone belongs to editable terrain, never the Ball group")
	check(get_nodes_in_group("Ball").size()==actors_before and world._battle_units_cache.size()==registered_before,"stone registers no combat participant or targeting-cache entry")
	var properties:Dictionary = {}
	for info:Dictionary in stone.get_property_list(): properties[str(info.name)] = true
	check(not properties.has("Team") and not properties.has("health") and not properties.has("Max_health") and not properties.has("Speed") and not properties.has("Damage"),"terrain has no team, HP, speed or attack stats")
	check(stone.get_node_or_null("StateMachine")==null and stone.get_node_or_null("state_machine")==null and stone.get_node_or_null("hitbox")==null and stone.get_node_or_null("hurtbox")==null and stone.get_node_or_null("Health_Bar")==null,"stone has no character state machine, hit/hurt areas or health bar")
	check(not stone.has_method("take_damage") and not stone.has_method("Skill") and not stone.has_method("apply_knockback"),"stone does not expose fake actor damage/skill/knockback APIs")
	check(stone.collision_layer==1 and stone.collision_mask==2,"stone uses only the terrain layer and does not masquerade as an entity")
	check(stone.disable_mode==CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE,"pausing processing keeps the terrain collision active")
	var shape:CollisionShape2D = stone.get_node("CollisionShape2D")
	check((shape.shape.get_rect().size*shape.global_scale).is_equal_approx(Vector2(23,25.5)),"existing 23 by 25.5 world-unit body size is preserved")
	check(stone.image.global_scale.is_equal_approx(Vector2(0.025,0.025)) and stone.get_preview_texture()==stone.image.texture,"existing stone texture and world visual scale are preserved")
	var sync:MultiplayerSynchronizer = stone.get_node("MultiplayerSynchronizer")
	check(sync.replication_config.property_get_spawn(NodePath(".:position")) and sync.replication_config.property_get_spawn(NodePath(".:scale")),"native terrain spawn replication includes placement and size")
	var terrain_damage:Node = load("res://scripts/effects/我的世界/ghast_obstacle_damage.gd").new()
	check(not terrain_damage.protected(stone) and stone.get_node_or_null("MCObstacleProperties")!=null,"stone exposes common destructible-obstacle properties without fake character HP")
	terrain_damage.free()

	var ray:=PhysicsRayQueryParameters2D.create(center-Vector2(60,0),center+Vector2(60,0),1)
	var hit:Dictionary = stone.get_world_2d().direct_space_state.intersect_ray(ray)
	check(hit.get("collider")==stone,"real terrain raycasts hit the actual stone body")
	var mover:Node2D = dummy(center-Vector2(60,0))
	mover.set_large_battle_performance_mode(true)
	var original_transform:Transform2D = stone.global_transform
	var collision:KinematicCollision2D = mover.move_and_collide(Vector2(120,0))
	check(collision!=null and collision.get_collider()==stone and mover.global_position.x<center.x,"real character motion is stopped by stone even with entity collisions optimized away")
	check(stone.global_transform==original_transform,"a colliding character cannot push the static terrain")
	mover.queue_free()
	stone.process_mode = Node.PROCESS_MODE_DISABLED
	await physics_frame
	hit = stone.get_world_2d().direct_space_state.intersect_ray(ray)
	check(hit.get("collider")==stone,"stone still blocks real physics queries while its processing is disabled")
	stone.process_mode = Node.PROCESS_MODE_INHERIT

	check(game._find_ball_ancestor(stone)==null and game._find_ball_ancestor(shape)==null,"character/control ancestor lookup never identifies the stone as a ball")
	check(game._find_deletable_ancestor(stone)==stone and game._find_deletable_ancestor(shape)==stone,"placement deletion finds terrain from either its root or collision shape")
	check("石头" not in world.return_all_character_names() and "石头" in world.return_all_placement_names(),"stone remains manually placeable but is excluded from the combat-character catalog")
	var preview:Node2D = world.create_character_preview("石头","",false)
	check(preview!=null and not preview is CollisionObject2D and preview.find_children("*","CollisionObject2D",true,false).is_empty(),"terrain placement preview is visual-only, not a live collider/actor")
	if preview!=null:
		var preview_image:Sprite2D = preview.get_node("PreviewImage")
		check(preview_image.texture==stone.image.texture and preview_image.scale.is_equal_approx(stone.image.global_scale),"terrain preview preserves the actual image and placement size")
		preview.free()
	var search_before:String = world.control.char_search.text
	world.control.char_search.text = "石头"
	world.control.Create_char_buts()
	var found_button:bool = false
	for node:Node in world.control.char_box.get_children():
		if node is Button and not node.is_queued_for_deletion() and str(node.get_meta("choice_value",""))=="石头":
			found_button = node.visible and not node.tooltip_text.is_empty()
	check(found_button,"manual cross-category search still offers stone and labels it as an obstacle")
	world.control.char_search.text = search_before

	var dictionary_before:Dictionary = world.Characters_Dic.duplicate()
	world.Characters_Dic = {"石头":STONE_PATH,"StoneTestFighter":"res://scenes/ball.tscn"}
	var only_fighters:bool = true
	for i:int in range(20): only_fighters = only_fighters and world.return_random_char()=="StoneTestFighter"
	check(only_fighters,"ordinary random character selection cannot select terrain")
	world.Characters_Dic = {"石头":STONE_PATH}
	check(world.return_random_char().is_empty(),"a terrain-only category has no fake fallback fighter")
	world.Characters_Dic = dictionary_before
	game.Game_Settings.Random_Character_Categories = ["默认"]
	var pool:Array = world.random_character_draft.pool()
	var stone_in_pool:bool = false
	for entry:Dictionary in pool: stone_in_pool = stone_in_pool or entry.scene_path==STONE_PATH
	check(not pool.is_empty() and not stone_in_pool,"random draft pool contains fighters but never stone terrain")
	stone.queue_free()
	await physics_frame
	await process_frame

	# Real placement facade, persistent layout and right-click removal.
	game.create_ball_in_server("Team0","石头",center)
	await physics_frame
	await process_frame
	check(stones().size()==1,"existing placement RPC facade creates a real static obstacle")
	var placed:StaticBody2D = stones()[0] as StaticBody2D
	var entry:Dictionary = world._battle_setup.back()
	check(entry.kind=="obstacle" and entry.team=="" and placed.global_position.is_equal_approx(center),"layout records a neutral obstacle at the requested location")
	check(world._configured_manual_victory_side_count()==0 and world._count_primary_battle_characters()==0,"a stone contributes neither a combatant nor a victory side")
	var setup_id:int = int(placed.get_meta("battle_setup_id"))
	world._victory_bell_armed = true
	game._delete_char_at_authority(center)
	check(placed.is_queued_for_deletion() and world._find_battle_setup_entry(setup_id).is_empty(),"actual right-click authority path removes the terrain and its saved placement")
	check(world._victory_bell_armed,"deleting terrain does not reset combat/victory state")
	world._victory_bell_armed = false
	await physics_frame
	await process_frame

	# Obstacles must never be converted into rotation slots, scores, or Bosses.
	for mode:String in ["rotation","timed","boss"]:
		game.Game_Settings.Training_Mode = true
		game.Game_Settings.Training_Mode_Type = mode
		var queued:int = world._rotation_rosters.left.size()+world._rotation_rosters.right.size()
		var scored:int = world._timed_name_by_setup.size()
		world.create_char("Team1","石头",center+Vector2(45*stones().size(),50))
		var current:StaticBody2D = stones().back() as StaticBody2D
		check(world._rotation_rosters.left.size()+world._rotation_rosters.right.size()==queued and world._timed_name_by_setup.size()==scored and not current.has_meta("training_boss_side") and current.scale==Vector2.ONE,"terrain bypasses combat queues, scoring and Boss scaling in "+mode)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	world.reset()
	await physics_frame
	await process_frame
	check(stones().is_empty(),"reset clears placed terrain through the transient lifecycle")

	world.create_char("Team0","石头",center-Vector2(45,0))
	world.create_char("Team1","石头",center+Vector2(45,0))
	var layout:Array = world._battle_setup.duplicate(true)
	await world.rematch_last_battle(true)
	await physics_frame
	await process_frame
	var locations_match:bool = stones().size()==2
	for record:Dictionary in layout:
		var match_found:bool = false
		for node:Node2D in stones():
			match_found = match_found or (int(node.get_meta("battle_setup_id"))==int(record.id) and node.global_position.is_equal_approx(Vector2(record.x,record.y)))
		locations_match = locations_match and match_found
	check(locations_match and world._count_primary_battle_characters()==0,"rematch restores stone positions and IDs as terrain, not as characters")
	world.reset()
	await process_frame
	await world.rematch_last_battle(true)
	await physics_frame
	check(stones().size()==2,"rematch after clearing the arena also restores static terrain")
	world.reset()
	await physics_frame
	await process_frame
	var migrated:Node2D = world._spawn_battle_setup_entry({"id":99999,"char":"石头","team":"Team1","x":center.x,"y":center.y})
	check(migrated is StaticBody2D and not is_instance_of(migrated,load("res://classes/ball.gd")),"old saved stone entries without a kind field migrate to true terrain")
	migrated.queue_free()
	var before_map_spawn:int = stones().size()
	check(world.spawn_map_character(load(STONE_PATH),"Team0",center)==null and stones().size()==before_map_spawn,"character spawners cannot turn an obstacle into a fighter or leak null-count spawns")
	await physics_frame
	await process_frame

	# Actual anvil leap against the actual stone scene, not a synthetic wall.
	world.control.hide()
	game.now_stop_state = false
	var target:Node2D = dummy(center+Vector2(100,0))
	var unit:Node2D = anvil(center+Vector2(-100,70))
	await physics_frame
	await process_frame
	check(unit.begin_slam(target),"anvil begins its bounded jump toward a real enemy")
	stone = add_stone(unit.jump_position(0.22))
	var stone_position:Vector2 = stone.global_position
	await physics_frame
	await process_frame
	var hp:float = target.health
	check(not unit.mc_enemy(stone),"anvil does not consider stone an enemy or damage victim")
	advance_until(unit,func(): return unit.slam_phase!=unit.SlamPhase.RISING,1.0)
	var contact:Vector2 = unit.global_position
	check(unit.slam_phase==unit.SlamPhase.FALLING and unit.fall_speed==0.0 and contact.distance_to(unit._jump_to)>20.0,"the real stone interrupts the jump and immediately releases the slam at contact")
	unit.step_mob(0.06)
	check(unit.global_position.y>contact.y and unit.global_position.x>=contact.x-0.03 and unit.global_position.x-contact.x<=maxf(absf(unit._launch_horizontal_speed),unit.fall_track_speed)*0.06+0.03 and target.health==hp,"anvil drops from stone contact within impulse/acceleration budget, without penetrating or damaging terrain")
	check(stone.global_position==stone_position,"anvil contact cannot displace the static stone")

	# Falling onto stone is a terrain landing: it blocks damage to enemies below.
	unit._cancel_slam()
	unit.global_position = stone_position-Vector2(0,90)
	unit._active_slam = true
	unit.Using_Skill = true
	unit._drop_connected = false
	unit.fall_speed = 800.0
	unit._fall_hits.clear()
	target.global_position = stone_position+Vector2(0,60)
	var landings:int = unit.landing_count
	var clangs_before:int = unit.obstacle_impact_count
	await physics_frame
	await process_frame
	hp = target.health
	unit.step_mob(0.15)
	check(unit.slam_phase==unit.SlamPhase.GROUND and unit.landing_count==landings+1 and unit.global_position.y<stone_position.y,"a falling anvil lands on the real stone as solid terrain")
	check(target.health==hp and unit.obstacle_impact_count==clangs_before+1,"stone blocks damage below it and produces the terrain landing clang")
	print("STONE_OBSTACLE_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
