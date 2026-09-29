extends SceneTree
var world:Node
var game:Node
var checks:int = 0
var failures:int = 0
var saved:Dictionary
var initial_positions:Dictionary = {}
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func fighters() -> void:
	for unit:Node in get_nodes_in_group("Ball"): unit.process_mode = Node.PROCESS_MODE_DISABLED
func current(side:String) -> Node:
	return world._find_character_by_setup_id_any(int(world._rotation_active_setup[side]))
func settle(seconds:float = 0.45) -> void:
	await create_timer(seconds).timeout
	var deadline:int=Time.get_ticks_msec()+7000
	while world._rotation_transitioning and Time.get_ticks_msec()<deadline: await process_frame
	await process_frame
	fighters()
func setup(mode:String,blue:int = 3,red:int = 2) -> void:
	world.reset()
	await process_frame
	await process_frame
	game.Game_Settings.Training_Mode_Type = "rotation"
	game.Game_Settings.Rotation_Match_Type = mode
	game.Game_Settings.Training_Wheel_Battle = mode == "wheel"
	world.control.team.show()
	world._battle_setup_next_id = 1
	for side:String in ["left","right"]:
		for i:int in range(blue if side=="left" else red):
			world._enqueue_rotation_character("",("Blue" if side=="left" else "Red")+str(i),world._rotation_spawn_position(side),side,"res://scenes/ball.tscn")
	world.control.hide()
	world.control.team.hide()
	world._update_special_training_modes(0.0)
	fighters()
	await process_frame
	world._rotation_frame_hud.sync()
func eliminate(side:String) -> void:
	var unit:Node = current(side)
	if unit == null:
		check(false,"fighter exists for elimination: "+side)
		return
	unit.health = 0
	unit.queue_free()
	await settle()
func run() -> void:
	create_timer(150.0,true,false,true).timeout.connect(func(): print("TIMEOUT"); quit(2))
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Boss_Intro = false
	game.Game_Settings.Map_Background = "blue"
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	node_added.connect(func(node:Node):
		if node is CharacterBody2D and node.has_meta("battle_setup_id"):
			initial_positions[int(node.get_meta("battle_setup_id"))] = node.global_position
	)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	await process_frame
	await process_frame
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	world.control._sync_training_mode_controls()
	check(world.control.rotation_match_option.item_count==3,"three rotation rule choices")
	check(game.ui_t("ROTATION_CHALLENGE")!="ROTATION_CHALLENGE","challenge label is translated")
	await setup("challenge")
	check(world._rotation_started,"challenge starts with both queues")
	check(current("left")!=null and current("right")!=null,"one blue and one red enter")
	check(world._rotation_frame_hud.visible,"frame HUD visible in rotation")
	world.refresh_versus_text()
	check(world.versus_label.visible and "VS" in world.versus_label.get_parsed_text(),"challenge shows ordinary XX VS XX title")
	check(world.versus_label.text==world.build_versus_text(),"rotation reuses ordinary title builder/style")
	check(world.versus_label.position.y==world.versus_screen_top_padding_px,"rotation title keeps ordinary screen top anchor")
	world._layout_rotation_versus_hud()
	check(not world.rotation_left_root.visible and not world.rotation_vs_label.visible,"legacy name HUD hidden in rotation")
	var map_node:Node = world.map_group[world.now_choose_map]
	var map_rect:Rect2 = world.return_map_visual_rect(map_node)
	var cell:float = world.map_visual_cell_size(map_node).x
	var top:Control = world._rotation_frame_hud.rows.left
	var bottom:Control = world._rotation_frame_hud.rows.right
	check(top.position.y+top.size.y<map_rect.position.y,"blue queue above map with separating gap")
	check(bottom.position.y>map_rect.end.y,"red queue below map")
	check(is_equal_approx(top.frame_rect(0).size.x,cell*0.9),"frame size is exactly 0.9 block")
	check(is_equal_approx(top.frame_rect(1).position.x-top.frame_rect(0).position.x,cell),"one slot per block")
	check(is_equal_approx(top.content_start(),(map_rect.size.x-3*cell)*0.5),"short queue is centered")
	check(top.clip_contents and bottom.clip_contents,"both rows clip overflow")
	var heads:RefCounted = world._rotation_frame_hud.portraits
	for character:String in heads.HEADS.keys():
		var tex:Texture2D = heads.resolve(world,{"char":character,"scene_path":"res://scenes/characters/我的世界/"+character+".tscn"})
		check(tex!=null and tex.get_image().get_used_rect().has_area(),"matching mob face: "+character)
	for character:String in ["仙人掌","唱片机","天堂陨落长弓","弓","木剑","木矛","木船","矿车","粘性活塞","苔藓","重锤","钓鱼竿","钻石剑","钻石长矛","铁砧","铜剑","鞘翅重锤","鞘翅长矛"]:
		var tex:Texture2D = heads.resolve(world,{"char":character,"scene_path":"res://scenes/characters/我的世界/"+character+".tscn"})
		check(tex!=null and tex.get_image().get_used_rect().has_area(),"actual item artwork: "+character)
	var full_health:int = current("left").health
	current("left").health = 17
	var first_red_instance:int = current("right").get_instance_id()
	await eliminate("right")
	check(int(world._rotation_active_setup.left)==1 and current("left").health==17,"blue winner retains damage between red opponents")
	check(int(world._rotation_active_setup.right)==5,"next red opponent enters in order")
	check(world._rotation_results.get(4)=="dead","red death recorded for cross overlay")
	await eliminate("right")
	check(world._rotation_results.get(1)=="won","beating entire red roster earns green check")
	check(int(world._rotation_active_setup.left)==2,"success advances to next blue")
	check(int(world._rotation_active_setup.right)==4,"red queue restarts at first fighter")
	check(current("left").health==full_health and current("right").health==full_health,"new attempt restores full health for both")
	check(current("right").get_instance_id()!=first_red_instance,"red is re-instantiated, not recycled with old state")
	check(not world._rotation_results.has(4) and not world._rotation_results.has(5),"red result markers cleared for new attempt")
	check((initial_positions[2] as Vector2).distance_to(world._rotation_spawn_position("left"))<1.0,"new blue starts at fixed initial position")
	check((initial_positions[4] as Vector2).distance_to(world._rotation_spawn_position("right"))<1.0,"new red starts at fixed initial position")
	await eliminate("left")
	check(world._rotation_results.get(2)=="dead","failed challenger earns cross, not check")
	check(int(world._rotation_active_setup.left)==3 and int(world._rotation_active_setup.right)==4,"failure advances blue and resets red")
	current("left").health = 0
	current("right").health = 0
	current("left").queue_free()
	current("right").queue_free()
	await settle()
	check(world._rotation_results.get(3)=="dead","simultaneous death is failed challenge")
	check(world._rotation_finished,"series finishes after every blue has challenged")
	check(get_nodes_in_group("Ball").is_empty(),"finished challenge has no stale fighters")
	world.rematch_last_battle()
	await settle()
	check(world._rotation_rosters.left.size()==3 and world._rotation_rosters.right.size()==2,"rematch restores complete queues")
	check(world._rotation_results.is_empty() and not world._rotation_finished,"rematch clears previous outcomes")
	check(int(world._rotation_active_setup.left)==1 and int(world._rotation_active_setup.right)==4,"rematch starts from both first entries")
	await setup("duel")
	world.refresh_versus_text()
	check(world.versus_label.visible and "VS" in world.versus_label.get_parsed_text(),"duel shows ordinary XX VS XX title")
	current("left").health = 19
	await eliminate("right")
	check(int(world._rotation_active_setup.left)==2 and int(world._rotation_active_setup.right)==5,"1v1 replaces BOTH fighters")
	check(world._rotation_results.get(1)=="won" and world._rotation_results.get(4)=="dead","1v1 survivor earns green check; loser keeps cross")
	world._rotation_frame_hud.sync()
	check(world._rotation_frame_hud.rows.left.results.get(1)=="won","winner status reaches portrait renderer")
	check(load("res://Images/UI/rotation_frames/check.png")!=null,"existing vanilla green check asset available")
	await setup("duel")
	await eliminate("left")
	check(world._rotation_results.get(1)=="dead" and world._rotation_results.get(4)=="won","red-side duel winner also earns check")
	await setup("duel")
	current("left").health=0
	current("right").health=0
	current("left").queue_free()
	current("right").queue_free()
	await settle()
	check(world._rotation_results.get(1)=="dead" and world._rotation_results.get(4)=="dead","double KO gives two crosses and no false winner")
	await setup("duel")
	current("right").health=0 # Death animation has not removed this actor yet.
	await eliminate("left")
	check(world._rotation_results.get(1)=="dead" and world._rotation_results.get(4)=="dead","zero-HP survivor awaiting removal never earns check")
	check(int(world._rotation_active_setup.left)==2 and int(world._rotation_active_setup.right)==5,"delayed death removal does not skip the next duel")
	await setup("wheel")
	world.refresh_versus_text()
	check(world.versus_label.visible and "VS" in world.versus_label.get_parsed_text(),"wheel shows ordinary XX VS XX title")
	current("left").health = 23
	await eliminate("right")
	check(int(world._rotation_active_setup.left)==1 and current("left").health==23,"wheel retains winner and current health")
	check(int(world._rotation_active_setup.right)==5,"wheel replaces loser only")
	check(world._rotation_results.get(1,"")!="won","wheel active winner is not marked as retired duel winner")
	world.refresh_versus_text()
	check(world.versus_label.text==world.build_versus_text(),"title updates to next current matchup")
	# Exercise the last-visible-slot rule with a standalone three-cell viewport.
	var row:Control = load("res://scripts/ui/rotation_frame_row.gd").new()
	row.world = world
	row.portraits = heads
	row.side = "left"
	root.add_child(row)
	row.size = Vector2(48,18)
	var records:Array = []
	for i:int in range(7): records.append({"id":100+i,"char":"苦力怕","scene_path":"res://scenes/characters/我的世界/苦力怕.tscn"})
	row.configure(records,{},100,16,2)
	check(row.first_visible==0 and row.content_start()==0,"overflow starts left-aligned")
	row.configure(records,{},102,16,2)
	check(row.first_visible==0,"no scroll while last visible fighter is current")
	row.configure(records,{102:"dead"},103,16,2)
	await create_timer(0.28).timeout
	check(row.first_visible==1 and is_equal_approx(row.scroll_pixels,16),"scrolls left one block after last visible fighter ends")
	check(is_equal_approx(row.frame_rect(3).position.x,32.8),"next fighter occupies predecessor rightmost slot")
	row.configure(records,{},106,16,2)
	await create_timer(0.28).timeout
	check(row.first_visible==4 and is_equal_approx(row.frame_rect(6).end.x,47.2),"last fighter stays inside map right boundary")
	row.queue_free()
	await setup("wheel")
	current("left").health = 0
	current("left").queue_free()
	await process_frame
	world.reset()
	await settle()
	check(world._rotation_rosters.left.is_empty() and get_nodes_in_group("Ball").is_empty(),"reset cancels delayed death callback without respawn")
	await setup("challenge")
	game.set_runtime_game_setting("Rotation_Match_Type","duel",false)
	await settle()
	check(world._rotation_results.is_empty() and int(world._rotation_active_setup.left)==1,"changing rules restarts safely with existing rosters")
	check(game.get_rotation_match_type()=="duel","new rule applied")
	# Boss uses its existing names and independent wheel flag.
	world.reset()
	await process_frame
	game.Game_Settings.Training_Mode_Type = "boss"
	game.Game_Settings.Training_Boss_Wheel_Battle = true
	world._layout_rotation_versus_hud()
	world._rotation_frame_hud.sync()
	check(not world._rotation_frame_hud.visible and world.rotation_left_root.visible,"Boss keeps its original queue HUD")
	world.refresh_versus_text()
	check(not world.versus_label.visible and world.rotation_vs_label.visible,"Boss wheel keeps only its legacy VS")
	if "--visual" in OS.get_cmdline_user_args(): await visual_preview()
	print("ROTATION_FRAMES_CHALLENGE: ",checks," checks / ",failures," failures")
	game.Game_Settings = saved
	world.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)

func visual_preview() -> void:
	# HUD-only visual fixture: foreground clouds would obscure the portrait rows.
	if is_instance_valid(world.minecraft_clouds): world.minecraft_clouds.hide()
	game.Game_Settings.Training_Mode_Type = "rotation"
	game.Game_Settings.Rotation_Match_Type = "duel"
	world._rotation_finished = true
	world._rotation_started = true
	world._rotation_rosters = {"left":[],"right":[]}
	world._rotation_results = {}
	world._rotation_active_setup = {"left":4,"right":103}
	var names:Array[String] = ["苦力怕","骷髅","末影人","钻石剑","唤魔者","女巫","铁傀儡","悦灵","监守者","羊","蜘蛛","重锤","溺尸","蝙蝠"]
	for side:String in ["left","right"]:
		for i:int in range(names.size()):
			var id:int = i+1 if side=="left" else i+101
			var character:String = names[i] if side=="left" else names[names.size()-1-i]
			world._rotation_rosters[side].append({"id":id,"char":character,"scene_path":"res://scenes/characters/我的世界/"+character+".tscn"})
	world._rotation_results = {1:"won",2:"dead",3:"won",101:"dead",102:"won"}
	var rect:Rect2 = world.return_map_world_rect(world.map_group[world.now_choose_map])
	for side:String in ["left","right"]:
		var id:int = int(world._rotation_active_setup[side])
		var character:String = "钻石剑" if side=="left" else "重锤"
		var point:Vector2 = rect.get_center()+Vector2(-30 if side=="left" else 30,0)
		var fighter:Node = world._spawn_character_from_setup({"id":id,"team":"Team0" if side=="left" else "Team1","char":character,"x":point.x,"y":point.y})
		if fighter != null: fighter.process_mode = Node.PROCESS_MODE_DISABLED
	world.control.hide()
	world.control.team.hide()
	world.refresh_versus_text()
	world._rotation_frame_hud.sync()
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/rotation_vs_winner_preview_20260927.png")
	world.control.show()
	world.control.game_setting.show()
	world.control._show_settings_category("training")
	world.control._sync_training_mode_controls()
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/rotation_vs_rules_preview_20260927.png")
