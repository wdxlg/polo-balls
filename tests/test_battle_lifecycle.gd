extends SceneTree
var world:Node
var game:Node
var saved:Dictionary
var checks:int=0
var failures:int=0
var victory_audio_nodes:int=0
var center:Vector2
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok: failures+=1; push_error("LIFECYCLE_FAIL "+label)
	else: print("PASS: ",label)
func freeze() -> void:
	for unit:Node in get_nodes_in_group("Ball"):
		unit.process_mode=Node.PROCESS_MODE_DISABLED
func family(id:int) -> Array:
	var result:Array=[]
	for unit:Node in world.get_battle_units_fast():
		if is_instance_valid(unit) and not unit.is_queued_for_deletion() and int(unit.get_meta("battle_lifecycle_identity",{}).get("setup",-1))==id:
			result.append(unit)
	return result
func spawn(path:String,id:int,team:String,offset:float=-100) -> Node:
	var unit:Node=world._spawn_character_from_setup({"id":id,"char":path.get_file().get_basename(),"scene_path":path,"team":team,"x":center.x+offset,"y":center.y})
	freeze()
	return unit
func clean() -> void:
	world.reset()
	await process_frame
	await process_frame
	game.Game_Settings.Training_Mode_Type="manual"
	world.control.hide();world.control.team.hide()
func queue_case(mode:String,path:String) -> Node:
	await clean()
	game.Game_Settings.Training_Mode_Type="rotation"
	game.Game_Settings.Rotation_Match_Type=mode
	world._battle_setup_next_id=1
	for side:String in ["left","right"]:
		for i:int in range(2):
			world._enqueue_rotation_character("",path.get_file().get_basename() if side=="left" and i==0 else "Dummy",world._rotation_spawn_position(side),side,path if side=="left" and i==0 else "res://scenes/ball.tscn")
	world._update_special_training_modes(0.0)
	freeze()
	await process_frame
	return world._find_character_by_setup_id_any(1)
func finish_family(id:int) -> void:
	for unit:Node in family(id):
		unit.health=0
		unit.queue_free()
	await process_frame
	await create_timer(0.40).timeout
	var deadline:int=Time.get_ticks_msec()+7000
	while world._rotation_transitioning and Time.get_ticks_msec()<deadline: await process_frame
	freeze()
func run() -> void:
	create_timer(150,true,false,true).timeout.connect(func():push_error("LIFECYCLE_TIMEOUT");quit(2))
	game=root.get_node("Game");saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false;game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Development_Mode=false;game.Game_Settings.Training_Boss_Intro=false
	game.now_stop_state=false
	node_added.connect(func(node:Node):
		if node is AudioStreamPlayer and node.stream==load("res://audio/system/胜利铃声.mp3"): victory_audio_nodes+=1
	)
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.free()
	world._mc_prewarmer=null
	world.now_choose_map="Map50x50";world.refresh_map_presentation()
	center=world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	world.set_process(false);world.set_physics_process(false)
	await process_frame
	# Fresh summons must inherit ownership before ANY victory poll.
	for team:String in ["Team0",""]:
		await clean()
		var root_unit:Node=spawn("res://scenes/characters/我的世界/唤魔者.tscn",11,team)
		spawn("res://scenes/ball.tscn",12,"Team1" if not team.is_empty() else "",200)
		var audio_before:int= victory_audio_nodes
		root_unit.summon_vex();freeze()
		check(family(11).size()>=2,"real evoker summons bind immediately: "+team)
		var key:String=world._victory_side_key_for_character(root_unit)
		root_unit.health=0;root_unit.Die();root_unit.queue_free()
		await process_frame
		world._victory_bell_armed=true;world._update_manual_victory_bell()
		check(world._collect_alive_victory_sides().has(key) and not world._victory_bell_played,"owner freed before first poll cannot erase vex side: "+team)
		check(world.is_combat_runtime_active(),"orphan combat gate remains active")
		check(victory_audio_nodes==audio_before,"no victory audio player created on body death")
		await finish_family(11)
		world._update_manual_victory_bell()
		check(world._victory_bell_played,"last real vex extinction allows bell exactly once")
		world._update_manual_victory_bell();check(not world._victory_bell_armed,"repeat poll cannot rearm bell")
		await create_timer(0.5).timeout
		check(victory_audio_nodes-audio_before==3,"real victory audio triplet is created once after family extinction")
	# All three queue rules wait for a real on-death brood.
	for mode:String in ["duel","wheel","challenge"]:
		var parasite:Node=await queue_case(mode,"res://scenes/characters/杀戮尖塔/异蛙寄生虫.tscn")
		parasite.health=0
		world._update_manual_victory_bell()
		check(int(world._rotation_active_setup.left)==1 and not world._victory_bell_played,"lethal setter waits for death handler: "+mode)
		parasite.Die();freeze();parasite.queue_free()
		await process_frame
		await create_timer(0.35).timeout
		freeze();world._update_manual_victory_bell()
		check(family(1).size()==4,"real death handler creates four children: "+mode)
		check(int(world._rotation_active_setup.left)==1 and not world._rotation_results.has(1),"original slot remains active through brood: "+mode)
		check(not world._rotation_transitioning and not world._victory_bell_played,"brood can fight without premature bell/transition: "+mode)
		await finish_family(1)
		check(int(world._rotation_active_setup.left)==2 and world._rotation_results.get(1)=="dead","last child advances original slot once: "+mode)
		check(int(world._rotation_active_setup.right)==(4 if mode=="duel" else 3),"other side follows original queue rule: "+mode)
	# Two generations of actual slime splitting, including a surviving orphan WIN.
	var slime:Node=await queue_case("duel","res://scenes/characters/我的世界/史莱姆.tscn")
	slime.health=0;slime.Die();freeze();slime.queue_free()
	await process_frame
	check(family(1).size()==2 and int(world._rotation_active_setup.left)==1,"large slime exit preserves two-medium slot")
	for medium:Node in family(1):medium.health=0;medium.Die();medium.queue_free()
	freeze();await process_frame
	check(family(1).size()==4 and world._battle_family_alive(1),"four grandchildren retain original slot")
	await finish_family(3)
	check(world._rotation_results.get(1)=="won" and int(world._rotation_active_setup.left)==2,"orphan slime family wins the original portrait check")
	check(family(1).is_empty(),"duel retirement clears all old winners, not only missing body")
	# A detached village companion remains a valid fighter.
	var golem:Node=await queue_case("wheel","res://scenes/characters/我的世界/铁傀儡.tscn")
	golem.ensure_companion();freeze()
	check(family(1).size()==2,"real golem companion registered under original slot")
	golem.health=0;golem.Die();golem.queue_free();await process_frame
	world._update_manual_victory_bell()
	check(world._battle_family_alive(1) and int(world._rotation_active_setup.left)==1,"cleared Master does not detach orphan villager from slot")
	await finish_family(1)
	check(int(world._rotation_active_setup.left)==2,"orphan villager last death advances slot")
	# Real independent-body families without Master links.
	for path:String in ["res://scenes/characters/动物/兔子.tscn","res://scenes/characters/人物/保安.tscn","res://scenes/characters/人物/NC佬.tscn","res://scenes/characters/我的世界/蝙蝠.tscn"]:
		var leader:Node=await queue_case("wheel",path)
		await process_frame;await process_frame;freeze()
		var count:int=family(1).size()
		check(count>1,"initial multipart family bound: "+path.get_file())
		if path.ends_with("兔子.tscn") and count>1:
			var partner:Node=null
			for member:Node in family(1):
				if member!=leader:partner=member;break
			leader._spawn_baby_with(partner);freeze()
			check(family(1).size()==count+1,"new baby inherits breeder's slot without changing Master")
		leader.health=0;leader.queue_free();await process_frame
		world._update_manual_victory_bell()
		check(int(world._rotation_active_setup.left)==1 and world._battle_family_alive(1),"leader loss keeps independent descendants active: "+path.get_file())
		await finish_family(1)
		check(int(world._rotation_active_setup.left)==2,"last independent descendant advances once: "+path.get_file())
	# Actual confirmed guard reinforcement survives caller death across its delay.
	var guard_source:Node=await queue_case("wheel","res://scenes/characters/人物/保安.tscn")
	await process_frame;freeze()
	var request:Node=load("res://scripts/characters/保安_增援请求.gd").new()
	request.Team=guard_source.Team;request.guard_scene=load("res://scenes/characters/人物/保安.tscn")
	request.arrival_delay=0.20;request.car_drive_time=0.20;request.spawn_position=center
	request.bind_battle_source(guard_source);world.add_child(request)
	for member:Node in family(1):member.health=0;member.queue_free()
	await process_frame;world._update_manual_victory_bell()
	check(family(1).is_empty() and world._battle_family_alive(1) and int(world._rotation_active_setup.left)==1,"confirmed guard in transit holds the empty original slot")
	await create_timer(0.48).timeout;freeze()
	check(family(1).size()==1 and int(world._rotation_active_setup.left)==1,"real guard request delivers the original identity after caller deletion")
	check(world._battle_spawn_tickets.is_empty(),"arrival consumes its ticket")
	await finish_family(1)
	check(int(world._rotation_active_setup.left)==2,"last reinforcement death finally advances")
	# Real brick tween handoff after the insect has already left the tree.
	var insect:Node=await queue_case("wheel","res://scenes/characters/我的世界/蠹虫.tscn")
	var field:Node=insect._stone_field
	var coords:Array=field._stone_cells.keys()
	check(not coords.is_empty(),"real silverfish stone field has hatchable cells")
	field._begin_break(coords[coords.size()/2],insect.Team,true,0,9182,str(insect.name))
	insect.health=0;insect.queue_free();await process_frame
	world._update_manual_victory_bell()
	check(world._battle_family_alive(1) and int(world._rotation_active_setup.left)==1,"brick ticket holds slot without original insect")
	await create_timer(0.25).timeout;freeze()
	check(family(1).size()==1 and int(world._rotation_active_setup.left)==1,"real 0.18-second hatch receives original roster id")
	check(world._battle_spawn_tickets.is_empty(),"brick spawn releases completed ticket")
	await finish_family(1)
	check(int(world._rotation_active_setup.left)==2,"legacy silverfish extinction callback cannot skip descendants")
	# Actual creeper next-frame head spawn and delayed body retirement.
	var creeper:Node=await queue_case("wheel","res://scenes/characters/我的世界/苦力怕.tscn")
	creeper._explode()
	await process_frame;await process_frame;freeze()
	check(family(1).size()>=2,"next-frame creeper head joins same family before body removal")
	if is_instance_valid(creeper):creeper.queue_free()
	await process_frame;world._update_manual_victory_bell()
	check(world._battle_family_alive(1) and int(world._rotation_active_setup.left)==1,"head carries original creeper slot after body exit")
	await finish_family(1)
	check(int(world._rotation_active_setup.left)==2,"last creeper head advances once")
	# Potion fallback source: caster gone, existing rule assigns victim's Team.
	await clean()
	var potion_owner:Node=spawn("res://scenes/ball.tscn",71,"Team0")
	spawn("res://scenes/ball.tscn",72,"Team1",200)
	var status:Node=load("res://scripts/effects/我的世界/女巫药水状态.gd").new()
	status.target=potion_owner;status.effect_type="oozing"
	status._spawn_mobs("res://scenes/creatures/我的世界/史莱姆_小.tscn",2)
	status.free();freeze()
	check(family(71).size()==3,"potion death-spawn fallback preserves victim family as well as Team")
	potion_owner.health=0;potion_owner.queue_free();await process_frame
	world._victory_bell_armed=true;world._update_manual_victory_bell()
	check(not world._victory_bell_played,"potion-spawned survivors prevent premature bell")
	await finish_family(71);world._update_manual_victory_bell()
	check(world._victory_bell_played,"potion descendants eventually settle normally")
	# A wooden sword's two physical fragments also have no Master link.
	var sword:Node=await queue_case("wheel","res://scenes/characters/我的世界/木剑.tscn")
	# The fixture froze process_mode, removing the physics body from its space.
	# Reattach it before the real split uses move_and_collide; production mechanics are unchanged.
	sword.process_mode=Node.PROCESS_MODE_INHERIT
	sword.state_machine.set_physics_process(false)
	sword._split_requested=true;sword.split_sword();freeze()
	check(family(1).size()==2,"real wooden sword split binds both fragments to original slot")
	sword.health=0;sword.Die();sword.queue_free();await process_frame
	world._update_manual_victory_bell()
	check(world._battle_family_alive(1) and int(world._rotation_active_setup.left)==1,"surviving blade prevents premature replacement")
	await finish_family(1)
	check(int(world._rotation_active_setup.left)==2,"workbenches and visual debris do not hold extinct sword family")
	# Pending delayed hatch is part of the family even with ZERO living nodes.
	await clean()
	var parent:Node=spawn("res://scenes/ball.tscn",31,"",-100)
	spawn("res://scenes/ball.tscn",32,"",200)
	var keeper:Node=Node.new();world.add_child(keeper)
	var ticket:int=world.begin_battle_spawn(parent,keeper)
	var source_key:String=world._victory_side_key_for_character(parent)
	parent.health=0;parent.queue_free();await process_frame
	world._victory_bell_armed=true;world._update_manual_victory_bell()
	check(ticket>0 and world._battle_family_alive(31) and not world._victory_bell_played,"pending spawn prevents the empty-frame victory hole")
	var child:Node=load("res://scenes/ball.tscn").instantiate()
	child.Team=""
	check(world.apply_battle_spawn_identity(child,ticket),"ticket transfers identity after source has been freed")
	world.add_child(child,true);freeze();world.finish_battle_spawn(ticket)
	check(world._collect_alive_victory_sides().has(source_key) and world._battle_family_alive(31),"orphan hatch keeps neutral solo identity and roster id")
	await finish_family(31);world._update_manual_victory_bell()
	check(world._victory_bell_played,"resolved ticket cannot hold an extinct side forever")
	# Cancellation/reset and keeper disappearance must release pending work.
	await clean()
	parent=spawn("res://scenes/ball.tscn",41,"Team0")
	keeper=Node.new();world.add_child(keeper)
	ticket=world.begin_battle_spawn(parent,keeper)
	keeper.queue_free();await process_frame
	world._prune_battle_spawn_tickets()
	check(not world._battle_spawn_tickets.has(ticket),"deleted custodian cancels pending spawn")
	keeper=Node.new();world.add_child(keeper);ticket=world.begin_battle_spawn(parent,keeper)
	world.reset();await process_frame
	child=load("res://scenes/ball.tscn").instantiate()
	check(not world.apply_battle_spawn_identity(child,ticket),"reset rejects old asynchronous spawn ticket")
	child.free();keeper.queue_free()
	# Classification excludes projectiles and ground effects from victory.
	await clean()
	parent=spawn("res://scenes/ball.tscn",51,"Team0")
	spawn("res://scenes/ball.tscn",52,"Team1",200)
	child=load("res://scenes/ball.tscn").instantiate();child.Master=parent;child.Master_name=parent.name;child.Team=parent.Team
	child.set_meta("combat_classification",{"entity_kind":"hazard"})
	world.add_child(child,true);freeze()
	check(not world._battle_unit_keeps_family_alive(child),"hazard with legacy Ball Type is not a surviving character")
	parent.health=0;parent.queue_free();await process_frame
	world._victory_bell_armed=true;world._update_manual_victory_bell()
	check(world._victory_bell_played,"lingering hazard never blocks final bell")
	# Creature's generic state machine has no Ball death resolver: 0 HP is final
	# unless that creature explicitly declares a continuation bridge.
	await clean()
	var pet_owner:Node=spawn("res://scenes/ball.tscn",81,"Team0")
	var pet:Node=load("res://scenes/ball.tscn").instantiate()
	pet.Type=3;pet.Master=pet_owner;pet.Master_name=pet_owner.name;pet.Team=pet_owner.Team
	world.add_child(pet,true);freeze()
	check(world._battle_unit_keeps_family_alive(pet),"healthy Creature keeps its owner's family alive")
	pet.health=0
	check(not world._battle_unit_keeps_family_alive(pet),"dead generic Creature cannot wait forever for a nonexistent death resolver")
	# Same Team is not the identity of a queue slot.
	await clean()
	var first:Node=spawn("res://scenes/ball.tscn",61,"Team0")
	var second:Node=spawn("res://scenes/ball.tscn",62,"Team0",100)
	first.health=0;first.queue_free();await process_frame
	check(not world._battle_family_alive(61) and world._battle_family_alive(62),"different same-team setup ids never keep each other alive")
	world._reset_victory_bell_state()
	world.request_silverfish_extinction_victory_recheck("team:old_match")
	await process_frame;await process_frame
	check(not world._victory_bell_played,"old extinction callback cannot invent victory in an unarmed single-side placement")
	# Timed/challenge restrictions cannot be bypassed by old silverfish callback.
	game.Game_Settings.Training_Mode_Type="timed";world._reset_victory_bell_state();world._victory_bell_armed=true
	world.request_silverfish_extinction_victory_recheck("team:gone")
	await process_frame;await process_frame
	check(not world._victory_bell_played,"legacy extinction callback cannot ring timed mode")
	await clean()
	print("BATTLE_LIFECYCLE_RESULT checks=",checks," failures=",failures)
	game.Game_Settings=saved;world.queue_free();await process_frame
	quit(0 if failures==0 else 1)
