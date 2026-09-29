extends "res://scripts/training/test_mc_new5.gd"

func family_units(family:String,stage:int=-1) -> Array[Node2D]:
	var found:Array[Node2D]=[]
	for unit:Node in get_nodes_in_group("Ball"):
		if is_instance_valid(unit) and not unit.is_queued_for_deletion() and unit.get_script()==load("res://scripts/characters/我的世界/new5/slime.gd") and unit.slime_family==family and (stage<0 or unit.slime_stage==stage):
			unit.state_machine.set_physics_process(false)
			found.append(unit)
	return found

func reset_case() -> void:
	game.Game_Settings.Training_Mode_Type="manual"
	world._rotation_started=false
	world._rotation_transitioning=false
	world._rotation_pending_dead_sides.clear()
	await clear_units()
	world._battle_setup.clear()
	world._reset_victory_bell_state()

func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(90,true,false,true).timeout.connect(func():finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	u=load("res://scripts/characters/我的世界/new5/utils.gd")
	# Drive real World collectors/bell/queue methods deterministically.
	game.set_process(false)
	world.set_process(false)
	world.set_physics_process(false)
	for team:String in ["Team0",""]:
		await reset_case()
		var parent:Node2D=spawn("史莱姆",Vector2(-100,0),team)
		parent.set_meta("battle_setup_id",701)
		var opponent:Node2D=spawn("",Vector2(250,0),"Team1" if not team.is_empty() else "")
		opponent.set_meta("battle_setup_id",702)
		var key:String=world._victory_side_key_for_character(parent)
		var view_key:String=world.return_ball_side_key(parent)
		var family:String=parent.slime_family
		world._update_manual_victory_bell()
		check(world._victory_bell_armed and not world._victory_bell_played,"two initial sides arm victory normally: "+team)
		parent.health=0
		world._update_manual_victory_bell()
		check(world._is_battle_death_bridge_unit(parent) and world._collect_alive_victory_sides().size()==2 and not world._victory_bell_played,"lethal health write cannot ring before the large slime splits: "+team)
		parent.Die()
		parent.Die()
		var mediums:Array[Node2D]=family_units(family,1)
		check(mediums.size()==2,"large slime splits exactly once into two mediums: "+team)
		for child:Node2D in mediums:
			check(child.Team==team and child.Master==parent and child.get_meta("battle_continuation_victory_side_key","")==key and child.get_meta("battle_continuation_setup_id",-1)==701,"child inherits real team, ownership, side and original roster identity")
			check(not child.has_meta("battle_setup_id"),"split child does not become a duplicate editable roster entry")
		check(not mediums[0].slime_enemy(mediums[1]) and not mediums[1].slime_enemy(mediums[0]),"siblings remain allies")
		check(mediums[0].slime_enemy(opponent),"split family still recognizes a real opposing side")
		var view:Dictionary=world.return_battle_sides()
		check(view.order.size()==2 and view.members.has(view_key) and view.members[view_key].size()==1,"top VS groups all children under the original slime rather than new sides")
		parent.free()
		world._update_manual_victory_bell()
		check(world._collect_alive_victory_sides().has(key) and not world._victory_bell_played and mediums[0].is_combat_runtime_active(),"deleting the original body neither loses its side nor stops the children")
		for medium:Node2D in mediums:
			medium.health=0
			world._update_manual_victory_bell()
			check(not world._victory_bell_played,"medium death also keeps the side alive before splitting")
			medium.Die()
			medium.free()
		var smalls:Array[Node2D]=family_units(family,2)
		check(smalls.size()==4,"both mediums create four final-generation slimes")
		for child:Node2D in smalls:
			check(child.Team==team and child.continuation_victory_key==key and child.continuation_presentation_key==view_key and child.continuation_setup_id==701,"grandchildren retain the original identity after both ancestor generations are freed")
		game.Game_Settings.Have_Team_Damage=true
		check(not smalls[0].slime_enemy(smalls[1]),"existing same-family no-friendly-fire rule survives global friendly fire")
		game.Game_Settings.Have_Team_Damage=false
		for index:int in range(3):
			smalls[index].health=0
			smalls[index].Die()
			smalls[index].free()
			world._update_manual_victory_bell()
			check(not world._victory_bell_played and world._collect_alive_victory_sides().size()==2,"no bell while any final-generation slime survives")
		smalls[3].health=0
		# Resolve the real death state before asking for terminal victory; a lethal
		# setter alone must still allow revival / on-death summons this frame.
		smalls[3].state_machine.current_state=smalls[3].State.Die
		world._update_manual_victory_bell()
		check(world._victory_bell_played and world._collect_alive_victory_sides().size()==1 and not world._is_battle_death_bridge_unit(smalls[3]),"only total family extinction permits the normal victory bell")
		smalls[3].Die()
		check(family_units(family,1).is_empty() and family_units(family,2).size()<=1,"smallest slime never creates another generation")
		world._update_manual_victory_bell()
		check(world._victory_bell_played and not world._victory_bell_armed,"repeat victory polls do not rearm the played bell")
	await reset_case()
	var a:Node2D=spawn("史莱姆",Vector2(-100,0),"")
	var b:Node2D=spawn("史莱姆",Vector2(100,0),"")
	a.set_meta("battle_setup_id",801)
	b.set_meta("battle_setup_id",802)
	var family_a:String=a.slime_family
	var family_b:String=b.slime_family
	a.health=0;a.Die();a.free()
	b.health=0;b.Die();b.free()
	var ac:Array[Node2D]=family_units(family_a,1)
	var bc:Array[Node2D]=family_units(family_b,1)
	check(ac[0].slime_enemy(bc[0]) and ac[0].continuation_victory_key!=bc[0].continuation_victory_key and world._collect_alive_victory_sides().size()==2,"separate unteamed slime families remain enemies rather than merging globally")
	var packed:PackedScene=load("res://scenes/creatures/我的世界/史莱姆_中.tscn")
	var mirror:Node2D=packed.instantiate()
	mirror.Team=ac[0].Team
	var config:SceneReplicationConfig=mirror.get_node("SlimeIdentitySync").replication_config
	for field:String in ["slime_family","continuation_victory_key","continuation_presentation_key","continuation_setup_id"]:
		var property:NodePath=NodePath(".:"+field)
		check(config.get_properties().has(property) and config.property_get_spawn(property),"spawn synchronization contains "+field)
		mirror.set(field,ac[0].get(field))
	world.add_child(mirror,true)
	# Local replica simulation: no connected peer 2 to request an initial RPC.
	mirror.set_multiplayer_authority(2)
	mirror.state_machine.set_physics_process(false)
	check(mirror.get_meta("battle_continuation_victory_side_key","")==ac[0].continuation_victory_key and mirror.slime_family==family_a,"replica binds inherited identity before ordinary scene registration")
	var before:int=family_units(family_a,2).size()
	mirror.health=0;mirror.Die()
	check(family_units(family_a,2).size()==before,"replicas do not duplicate authoritative splits")
	await reset_case()
	# Queue tests: a split family owns one active roster slot through all deaths.
	game.Game_Settings.Training_Mode_Type="rotation"
	game.Game_Settings.Rotation_Match_Type="duel"
	check(world._queue_battle_mode_active(),"queue fixture uses the actual rotation mode")
	world._rotation_started=true
	world._rotation_rosters={"left":[],"right":[]}
	world._rotation_next_index={"left":0,"right":0}
	world._rotation_active_setup={"left":901,"right":902}
	var root_slime:Node2D=spawn("史莱姆",Vector2(-100,0),"Team0")
	root_slime.set_meta("battle_setup_id",901)
	root_slime.set_meta("rotation_side","left")
	root_slime.tree_exiting.connect(Callable(world,"_on_rotation_character_tree_exiting").bind(root_slime,"left",901),CONNECT_ONE_SHOT)
	var foe:Node2D=spawn("",Vector2(250,0),"Team1")
	foe.set_meta("battle_setup_id",902)
	var f:String=root_slime.slime_family
	world._update_manual_victory_bell()
	root_slime.health=0
	check(world._rotation_side_has_contender("left"),"queue counts the lethal-frame bridge before any children exist")
	root_slime.Die();root_slime.free()
	world._update_manual_victory_bell()
	check(world._rotation_active_setup.left==901 and world._rotation_pending_dead_sides.is_empty() and not world._victory_bell_played,"parent exit neither advances the queue nor rings while children live")
	for medium:Node2D in family_units(f,1):
		medium.health=0;medium.Die();medium.free()
	var last:Array[Node2D]=family_units(f,2)
	for index:int in range(3):
		last[index].health=0;last[index].Die();last[index].free()
	check(world._rotation_side_has_contender("left") and world._rotation_active_setup.left==901,"queue waits through both generations until the last descendant")
	last[3].health=0
	last[3].state_machine.current_state=last[3].State.Die
	world._update_manual_victory_bell()
	check(world._victory_bell_played and not world._rotation_side_has_contender("left"),"queue victory is available only after the whole family dies")
	last[3].Die();last[3].free()
	check(world._rotation_active_setup.left==901 and world._rotation_pending_dead_sides.has("left"),"last descendant exit queues revalidation without prematurely erasing the original slot")
	game.Game_Settings.Training_Mode_Type="manual"
	world._rotation_pending_dead_sides.clear()
	print("SLIME_FAMILY_VICTORY checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
