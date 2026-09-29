extends "res://tests/test_mc16_native_feedback.gd"
const ENCHANT_EVENT:String = "block.enchantment_table.use"
var item_serial:int = 1000
func extra(owner:Node,point:Vector2,phase:int = 3) -> Node:
	item_serial += 1
	var spear:Node = owner._create_trident(item_serial)
	spear.set_physics_process(false)
	if phase==3: spear.stick(point)
	else:
		spear.flight_state = phase
		spear.global_position = point
		spear._reset_enchantment_timer()
	return spear
func pending(spear:Node) -> Node:
	for child:Node in spear.get_children():
		if child.has_signal("impact_started") and not child.is_queued_for_deletion(): return child
	return null
func run() -> void:
	game = root.get_node("Game")
	# Game-dependent scripts load after autoload init but before World starts its workers.
	var drowned_scene:PackedScene = load("res://scenes/characters/我的世界/溺尸.tscn")
	check(drowned_scene!=null,"drowned fixture loads before world resource workers")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(70.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	if not await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self):
		finish(1)
		return
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	geometry = load("res://scripts/effects/我的世界/mc16_geometry.gd")
	var owner:Node = spawn("res://scenes/characters/我的世界/溺尸.tscn",center+Vector2(-350,150))
	var ally:Node = spawn("res://scenes/characters/我的世界/溺尸.tscn",center+Vector2(150,150))
	var hostile:Node = spawn("res://scenes/characters/我的世界/溺尸.tscn",center+Vector2(450,350),"Team1")
	for actor:Node in [owner,ally,hostile]: actor.native_feedback.set_physics_process(false)
	await process_frame
	await process_frame
	var hand:Node = owner._trident
	check(owner.held_enchant_delay==5.0 and owner.stuck_enchant_delay==12.0,"selected held five / grounded twelve second defaults")
	hand.advance(4.99)
	check(not hand.charged and count(owner,ENCHANT_EVENT)==0,"held trident does not enchant before five seconds")
	var held_time:float = hand._enchant_elapsed
	game.now_stop_state = true
	hand.advance(40.0)
	check(not hand.charged and hand._enchant_elapsed==held_time and not hand.charge(),"custom battle pause freezes timers and rejects enchant triggers")
	game.now_stop_state = false
	paused = true
	hand.advance(40.0)
	check(not hand.charged and hand._enchant_elapsed==held_time,"SceneTree pause also freezes enchant timer")
	paused = false
	owner.set_multiplayer_authority(2)
	hand.advance(40.0)
	check(not hand.charged and not hand.charge() and hand._enchant_elapsed==held_time,"non-authority cannot run timers or originate enchanting")
	owner.set_multiplayer_authority(1)
	hand.advance(0.02)
	check(hand.charged and count(owner,ENCHANT_EVENT)==1,"five continuous held seconds enchant and play native cue once")
	check(hand.charge_visual.visible,"timed enchant immediately activates existing glint and shaft electricity")
	hand.charge(); hand.advance(10.0)
	check(count(owner,ENCHANT_EVENT)==1 and count(owner,"item.trident.riptide_1")==0,"already enchanted item cannot replay cue or substitute riptide")
	var sound_native:bool = false
	for player:Node in get_nodes_in_group("MCNativeSFX"):
		if player.get_meta("mc_sound_event","")==ENCHANT_EVENT: sound_native = player.stream in owner.native_feedback.BANK.EVENTS[ENCHANT_EVENT] and player.pitch_scale==1.0
	check(sound_native and owner.native_feedback.BANK.EVENTS[ENCHANT_EVENT].size()==3,"enchant uses three official enchanting-table clips at original pitch")
	# A throw/catch restarts continuous holding time; advance the existing throw pose.
	var cycling:Node = ally._trident
	cycling.advance(4.0)
	var enemy:Node = dummy(ally.global_position+Vector2(300,0))
	check(ally.throw_trident(enemy) and not cycling.charged,"normal unenchanted throw starts before enchant timer finishes")
	ally._advance_trident_throw(ally.trident_throw_windup+0.01)
	cycling.advance(0.15)
	check(cycling._enchant_elapsed==0.0 and not cycling.charged,"outbound flight neither carries held progress nor charges itself")
	cycling._begin_return()
	cycling.advance(1.0)
	check(cycling.flight_state==0 and cycling._enchant_elapsed==0.0,"catch starts a fresh held timer")
	cycling.advance(4.99)
	check(not cycling.charged,"short held visits do not accumulate across throws")
	cycling.advance(0.02)
	check(cycling.charged,"fresh full held interval can enchant after a return")
	# Grounded timer has no old nearby-drowned shortcut and no retroactive periodic cast.
	fresh(owner)
	var pole:Node = extra(owner,center+Vector2(450,-350))
	owner.global_position = pole.global_position
	pole.advance(11.99)
	check(not pole.charged and pending(pole)==null,"standing on a pole cannot bypass its twelve second wait")
	var before:int = count(owner,ENCHANT_EVENT)
	pole.advance(0.02)
	check(pole.charged and count(owner,ENCHANT_EVENT)==before+1,"grounded trident enchants at twelve seconds")
	check(pending(pole)==null and is_equal_approx(pole.lightning_left,owner.lightning_first_delay),"timer-crossing frame cannot consume first periodic warning delay")
	pole.advance(owner.lightning_first_delay-0.01)
	check(pending(pole)==null,"newly enchanted pole still waits before periodic lightning")
	pole.advance(0.02)
	var bolt:Node = pending(pole)
	check(is_instance_valid(bolt) and not bolt._impact_started,"enchanted grounded pole retains periodic warning mechanism")
	bolt.set_process(false)
	bolt.queue_free()
	# Leaving the hand for a wall starts twelve seconds from zero, not held remainder.
	var transitional:Node = extra(owner,owner.trident_hand_position(),0)
	transitional.advance(4.0)
	transitional.launch(Vector2.RIGHT)
	transitional.stick(center+Vector2(700,450))
	transitional.advance(8.1)
	check(not transitional.charged,"four held seconds cannot shorten grounded charge to eight seconds")
	transitional.advance(4.0)
	check(transitional.charged,"grounded item finishes its own independent twelve second interval")
	# Real impact spreads to allied ITEMS, not owners standing nearby or absent inventory.
	fresh(owner)
	var recipient:Node = spawn("res://scenes/characters/我的世界/溺尸.tscn",center+Vector2(50,0))
	recipient.native_feedback.set_physics_process(false)
	await process_frame
	await process_frame
	var point:Vector2 = recipient.trident_hand_position()
	var grounded:Node = extra(owner,point+Vector2(12,0))
	var flying:Node = extra(recipient,point+Vector2(20,0),1)
	var returning:Node = extra(recipient,point+Vector2(-20,0),2)
	var far:Node = extra(recipient,point+Vector2(160,0),1)
	var hostile_item:Node = extra(hostile,point)
	pole.global_position = point
	var source_cues:int = count(owner,ENCHANT_EVENT)
	var target_cues:int = count(recipient,ENCHANT_EVENT)
	var ally_hp:float = recipient.health
	owner.summon_trident_lightning(pole,true)
	bolt = pending(pole)
	bolt.set_process(false)
	bolt._process(0.14)
	check(not recipient._trident.charged and not grounded.charged and not flying.charged,"warning phase cannot enchant items before the actual strike")
	bolt._process(0.02)
	check(recipient._trident.charged and grounded.charged and flying.charged and returning.charged,"actual lightning enchants allied held, grounded, outbound and returning items")
	check(not hostile_item.charged and not hostile._trident.charged,"enemy weapons never receive allied lightning enchantment")
	check(not far.charged,"nearby owner cannot remotely enchant an out-of-range flying item")
	check(recipient.health==ally_hp,"allied enchant spread does not require friendly damage")
	check(count(owner,ENCHANT_EVENT)==source_cues+1 and count(recipient,ENCHANT_EVENT)==target_cues+3,"each newly enchanted item plays exactly one cue even in a multi-item strike")
	bolt._start_impact(); owner._charge_drowned_in_bolt(point)
	check(count(recipient,ENCHANT_EVENT)==target_cues+3,"duplicate impact/spread callbacks do not replay enchant audio")
	bolt.queue_free()
	var remote_source_target:Node = extra(recipient,point+Vector2(25,0))
	owner.set_multiplayer_authority(2)
	owner._charge_drowned_in_bolt(point)
	check(remote_source_target.charged,"replicated source effect can charge a locally owned allied item")
	owner.set_multiplayer_authority(1)
	var foreign_target:Node = extra(recipient,point+Vector2(30,0))
	recipient.set_multiplayer_authority(2)
	owner._charge_drowned_in_bolt(point)
	check(not foreign_target.charged,"source peer cannot mutate a foreign-authority target item")
	var replica_cues:int = count(recipient,ENCHANT_EVENT)
	foreign_target.receive({"id":foreign_target.serial,"phase":3,"point":foreign_target.global_position,"rotation":0.0,"charged":true,"enchant_elapsed":0.0})
	check(foreign_target.charged and foreign_target.charge_visual.visible and count(recipient,ENCHANT_EVENT)==replica_cues,"snapshot activates replica visuals without originating a second enchant sound")
	recipient.set_multiplayer_authority(1)
	# No enchant credit for a nonexistent replacement item.
	var old_hand:Node = recipient._trident
	old_hand.stick(point+Vector2(250,0))
	recipient.on_mc_lightning_struck()
	recipient._new_trident()
	recipient._trident.set_physics_process(false)
	check(not recipient._trident.charged,"empty-hand strike does not pre-enchant a future replacement")
	# Isolated real network: only two initial endpoints; an uncharged item on the wire joins later.
	for spear:Node in get_nodes_in_group("MCTrident"):
		spear.charged = false
		if spear.flight_state!=0: spear.global_position = center+Vector2(750,550)
	for actor:Node in [owner,ally,recipient,hostile]: actor.global_position = center+Vector2(650,600)
	var receiver:Node = spawn("res://scenes/characters/我的世界/溺尸.tscn",center+Vector2(0,-180))
	receiver.native_feedback.set_physics_process(false)
	await process_frame
	await process_frame
	var middle:Vector2 = receiver.trident_hand_position()
	var a:Node = extra(owner,middle+Vector2(-100,0))
	var b:Node = extra(owner,middle+Vector2(100,0))
	var middle_pole:Node = extra(recipient,middle+Vector2(20,0))
	var enemy_pole:Node = extra(hostile,middle)
	var crossing:Node = extra(recipient,middle+Vector2(0,-35),1)
	var swept:Node = extra(recipient,middle+Vector2(0,40))
	a.charge(); b.charge()
	fresh(owner)
	var network:Node = world.get_node("MCTridentNetwork")
	network.pulse()
	check(network.last_pair_count==1,"newly enchanted items do not recursively explode the current pulse graph")
	check(middle_pole.charged and receiver._trident.charged and not enemy_pole.charged,"real wire creation enchants allied ground and hand items, not enemies")
	check(network.endpoints().size()==4,"wire-enchanted items become eligible endpoints for subsequent pulses")
	var arc:Node = get_nodes_in_group("MCTridentArc")[-1]
	arc.set_physics_process(false)
	check(not crossing.charged and not swept.charged,"off-wire items do not enchant merely because they are allied")
	crossing.global_position = middle+Vector2(0,35)
	arc.advance(0.01)
	check(crossing.charged,"fast moving trident crossing an active wire is swept rather than missed")
	a.global_position += Vector2(0,80); b.global_position += Vector2(0,80)
	arc.advance(0.01)
	check(swept.charged,"moving network segment sweeps over and enchants a stationary allied item")
	var waiting:Node = extra(recipient,middle+Vector2(0,80))
	game.now_stop_state = true
	var left:float = arc.left
	arc.advance(10.0)
	check(not waiting.charged and arc.left==left,"pause freezes network spread and its lifetime")
	game.now_stop_state = false
	arc.advance(0.01)
	check(waiting.charged,"resumed active wire can enchant the waiting item")
	var n:int = count(recipient,ENCHANT_EVENT)
	arc.advance(0.01)
	check(count(recipient,ENCHANT_EVENT)==n,"remaining in a live wire cannot replay enchanting")
	# Dead owners / destroyed supports cannot finish pending charge.
	var wall := Node2D.new()
	world.add_child(wall)
	var doomed:Node = extra(recipient,middle+Vector2(250,0))
	doomed.wall_ref = weakref(wall)
	doomed._enchant_elapsed = 11.99
	wall.queue_free()
	await process_frame
	await process_frame
	doomed.advance(0.02)
	check(doomed.is_queued_for_deletion() and not doomed.charged,"destroyed support retires before a pending enchant can fire")
	var dead:Node = extra(hostile,middle+Vector2(300,0))
	hostile.health = 0
	dead.advance(20.0)
	check(dead.is_queued_for_deletion() and not dead.charged,"owner death cannot complete enchant or leave a permanent orphan")
	check(owner.trident_damage_ratio==0.5 and owner.lightning_damage_ratio==1.4 and owner.impact_lightning_damage_ratio==0.7,"enchantment preserves direct damage and reduced lightning ratios")
	print("MC16_ENCHANTMENT_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
