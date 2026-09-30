extends SceneTree
var world:Node
var game:Node
var saved:Dictionary
var checks:int=0
var failures:int=0
var bell_players:int=0
func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if ok:print("PASS "+label)
	else:failures+=1;push_error("VICTORY_LIFECYCLE_FAIL "+label)
func tick() -> void:
	world._update_manual_victory_bell()
	world.duel_top_hud._update_clock(0)
	world.duel_top_hud._process(0.2)
func settle(frames:int=3) -> void:
	for i:int in range(frames):await process_frame;tick()
func place(team:String,offset:float=0) -> Node:
	var id:int=world._battle_setup_next_id
	var center:Vector2=world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	await world.create_char(team,"ball",center+Vector2(offset,0))
	var actor:Node=world._find_character_by_setup_id_any(id)
	if actor!=null:
		actor.Can_Attack=false;actor.Can_Skill=false;actor.Health_Restore=0
		actor.state_machine.set_physics_process(false)
	return actor
func eliminate(actor:Node) -> void:
	actor.health=0;actor.queue_free();await process_frame;tick();await settle()
func capture(label:String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://victory_lifecycle_"+label+".png")
func run() -> void:
	create_timer(90,true,false,true).timeout.connect(func():print("VICTORY_LIFECYCLE_TIMEOUT");quit(2))
	game=root.get_node("Game");saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false;game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Development_Mode=false;game.Game_Settings.Map_Background="blue"
	game.now_stop_state=false;AudioServer.set_bus_mute(0,true);root.size=Vector2i(540,960)
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT);root.add_child(world)
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.free()
	world._mc_prewarmer=null;await process_frame
	node_added.connect(func(node:Node):
		if node is AudioStreamPlayer and node.stream==world.VICTORY_BELL_AUDIO: bell_players+=1
	)
	world.now_choose_map="Map10x10";world.refresh_map_presentation();world.control.hide();world.control.team.hide()
	world.set_process(false);world.set_physics_process(false)
	# Use the same placement entry as the toolbar, not prefilled victory flags.
	world.Characters_Dic["ball"]=load("res://scenes/ball.tscn")
	var a:Node=await place("",-45);await settle()
	check(a!=null and not world._victory_bell_played and not world._victory_bell_armed,"first placed character alone is never a winner")
	var b:Node=await place("",45);await settle()
	check(world._victory_bell_armed and not world._victory_bell_played,"two real placements arm an actual battle")
	await eliminate(b)
	check(world._victory_bell_played and world.duel_top_hud.outro_active,"actual first elimination produces one victory")
	world.duel_top_hud.outro_elapsed=2;await capture("first_win")
	var identity:int=a.get_instance_id();a.health=321
	var c:Node=await place("",45);await settle()
	check(not world._victory_bell_played and not world.duel_top_hud.outro_active and world.duel_top_hud.victory_result.is_empty(),"placing a fresh opponent clears the old victory and toast")
	check(world._victory_bell_armed and world.duel_top_hud.sides.size()==2,"replacement battle is armed and normal versus HUD returns")
	check(a.get_instance_id()==identity and a.health==321,"new opponent does not respawn or heal previous winner")
	await capture("new_opponent")
	await eliminate(c)
	check(world._victory_bell_played and world.duel_top_hud.outro_active,"new opponent dying produces a new verdict, not stale frozen state")
	# User reset can occur while multiple previous bodies still await end-of-frame deletion.
	c=await place("",45);await settle()
	world.reset();tick() # no frame gap: deliberately poll queued old actors
	check(not world._victory_bell_played and not world._victory_bell_armed,"reset immediately disarms even before queued bodies leave the tree")
	await settle()
	var _only:Node=await place("",0);await settle()
	check(not world._victory_bell_played and not world._victory_bell_armed and not world.duel_top_hud.outro_active,"after reset placing one character never inherits a victory")
	await capture("reset_single")
	# Repeat the actual UI placement path: every new contest gets exactly its own result.
	for index:int in range(3):
		var epoch:int=world._victory_bell_sequence_generation
		var opponent:Node=await place("",45);await settle()
		check(not world._victory_bell_played and world._victory_bell_armed,"repeated contest %d starts without old achievement"%index)
		await eliminate(opponent)
		check(world._victory_bell_played and world.duel_top_hud.outro_active,"repeated contest %d can finish again"%index)
		if index>0:check(world._victory_bell_sequence_generation>epoch,"new contest advances presentation generation")
	# Team addition must not immediately re-win against historically dead setup entries.
	world.reset();await settle()
	a=await place("A",-45);var mate:Node=await place("A",-15);b=await place("B",45);await settle()
	await eliminate(mate);await eliminate(b)
	check(world.duel_top_hud.victory_result.get("member_count",0)==2,"original two-person team still wins as a team in its original contest")
	var old_setup_count:int=world._battle_setup.size()
	var ally:Node=await place("A",-15);await settle()
	check(not world._victory_bell_played and not world._victory_bell_armed and not world.duel_top_hud.outro_active,"adding only an ally clears result but cannot win against historical dead enemies")
	check(world._battle_setup.size()==old_setup_count+1,"new result scope preserves full rematch placement history")
	b=await place("B",45);await settle();await eliminate(ally);await eliminate(b)
	check(world.duel_top_hud.victory_result.get("member_count",0)==2,"new team result counts current-contest ally, not the old defeated teammate")
	b=await place("B",45);await settle();await eliminate(b)
	check(not world.duel_top_hud.victory_result.get("is_team",true) and world.duel_top_hud.victory_result.get("member_count",0)==1,"former team now entering alone is a single winner, without historical roster leakage")
	# Direct real spawning (e.g. training respawn) is reconciled by the shared World poll too.
	var new_id:int=world._battle_setup_next_id;world._battle_setup_next_id+=1
	var entry:Dictionary={"id":new_id,"char":"ball","scene_path":"res://scenes/ball.tscn","team":"B","x":a.global_position.x+50,"y":a.global_position.y}
	world._battle_setup.append(entry)
	var direct:Node=world._spawn_character_from_setup(entry);direct.Can_Attack=false;direct.Can_Skill=false;direct.state_machine.set_physics_process(false)
	await settle()
	check(not world._victory_bell_played and world._victory_bell_armed,"shared poll reopens a genuine direct-spawn opponent too")
	await eliminate(direct)
	var summon:Node=load("res://scenes/ball.tscn").instantiate();summon.Master=a;summon.Team="A";world.add_child(summon)
	summon.Can_Attack=false;summon.Can_Skill=false;summon.state_machine.set_physics_process(false);await settle()
	check(world._victory_bell_played and world.duel_top_hud.victory_result.get("member_count",0)==1,"winner's summon neither reopens a contest nor changes the solo result")
	# Same-frame reset + replacement, before the old queued nodes are physically gone.
	b=await place("B",45);await settle()
	world.reset();var _replacement:Node=await place("",0);tick()
	check(not world._victory_bell_played and not world._victory_bell_armed,"same-frame reset and single placement cannot inherit old sides")
	await settle();check(not world.duel_top_hud.outro_active,"same-frame reset stays clear after deferred exits")
	world.reset();tick();world.reset();tick();await settle()
	_replacement=await place("",0);await settle()
	check(not world._victory_bell_played and not world._victory_bell_armed,"repeated empty resets do not accumulate an armed verdict")
	b=await place("",45);await settle();await eliminate(b)
	var heard:int=bell_players
	world.reset();tick()
	await create_timer(0.5,true,false,true).timeout
	check(bell_players==heard,"reset cancels delayed second/third bells from the old generation")
	check(world.duel_top_hud.sides.is_empty() and world.duel_top_hud.victory_result.is_empty() and not world.duel_top_hud._focus_requested,"reset clears old pair, result snapshot and victory camera focus together")
	var rematch_count:int=world._last_battle_setup.size()
	await world.rematch_last_battle()
	for actor:Node in world._battle_units_cache:
		if is_instance_valid(actor):
			actor.Can_Attack=false;actor.Can_Skill=false;actor.state_machine.set_physics_process(false)
	await settle()
	check(rematch_count==2 and world._battle_setup.size()==rematch_count and world._collect_alive_victory_sides().size()==2 and world._victory_bell_armed and not world._victory_bell_played,"real rematch restores the complete saved roster as a fresh contest")
	world.reset();await settle();game.Game_Settings=saved;world.queue_free();await process_frame
	print("VICTORY_LIFECYCLE_RESULT checks=%d failures=%d renderer=%s"%[checks,failures,DisplayServer.get_name()])
	quit(0 if failures==0 else 1)
