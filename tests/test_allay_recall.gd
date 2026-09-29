extends "res://tests/test_allay_extended.gd"
var center:Vector2
var enemy:Node
func owner_with_notes(count:int) -> Node:
	var unit:Node=spawn("res://scenes/characters/我的世界/悦灵.tscn",center,"Team0")
	unit.process_mode=Node.PROCESS_MODE_DISABLED
	unit._generate_left=100.0
	unit.notes=count
	unit._note_cloud.resize(count,center)
	for i:int in count: unit._note_cloud.positions[i]=center+Vector2.from_angle(TAU*float(i)/maxi(count,1))*30.0
	return unit
func finish_cycle(unit:Node) -> void:
	for i:int in range(70):
		unit.clock+=0.02
		unit._recall.advance(0.02)
func cleanup(unit:Node) -> void:
	unit._recall.clear()
	for shot:Node in get_nodes_in_group("AllayFlyingNote"):
		if is_instance_valid(shot) and shot.Master==unit:
			shot._spent=true; shot.queue_free()
	for wave:Node in get_nodes_in_group("AllayRecallWave"):
		if wave.source_ref.get_ref()==unit: wave.queue_free()
	unit.queue_free()
func run() -> void:
	CAPTURE=load("res://scripts/characters/我的世界/allay/capture.gd")
	EXT=load("res://scripts/characters/我的世界/allay/extended_capture.gd")
	game=root.get_node("Game"); saved=game.Game_Settings.duplicate(true); saved_stop=game.now_stop_state
	game.Game_Settings.Map_Background="blue"; game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"; game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false; game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(60.0).timeout.connect(func(): finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"; world.refresh_map_presentation(); world.control.hide()
	await create_timer(0.3).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	enemy=spawn("res://scenes/ball.tscn",center+Vector2(32,0),"Team1")
	enemy.process_mode=Node.PROCESS_MODE_DISABLED; enemy.Max_health=10000; enemy.health=10000
	var unit:Node=owner_with_notes(4)
	check(not unit._recall.try_start(),"fewer than five available notes cannot start")
	cleanup(unit)
	unit=owner_with_notes(25)
	check(unit._recall.try_start(),"near enemy starts recall")
	check(unit._recall.live(true).size()==20 and unit.notes==5,"at most twenty participate; unused notes remain")
	var ring:Array=unit._recall.live(true)
	var expected:float=0.0
	for note:Node in ring:
		expected+=note._recall_damage
		note.process_mode=Node.PROCESS_MODE_DISABLED
	check(ring[0].attack_damage()==0.0 and ring[0]._recall_damage>0.0,"spin suppresses ordinary full-damage hitbox but retains damage budget")
	var before:float=enemy.health
	unit._recall.spin_contact(ring[0],enemy.global_position,enemy.global_position)
	check(enemy.health<before and before-enemy.health<ring[0]._recall_damage,"spinning contact deals only small damage")
	before=enemy.health
	unit._recall.spin_contact(ring[1],enemy.global_position,enemy.global_position)
	check(enemy.health==before,"all spinning notes share per-target contact cooldown")
	game.now_stop_state=true
	var elapsed:float=unit._recall.elapsed
	unit._recall.advance(2.0)
	check(unit._recall.elapsed==elapsed,"recall animation and timer pause with battle")
	game.now_stop_state=false
	finish_cycle(unit)
	check(unit._recall.last_consumed==20 and is_equal_approx(unit._recall.last_damage,expected*1.2),"final damage equals the twenty actual note damage budgets times 1.2")
	check(not unit._recall.try_start(),"cooldown prevents immediate repeated recall")
	check(unit._native_sfx_left.has("allay.recall.spin"),"spin phase emits original Minecraft riptide event")
	check(unit._native_sfx_left.has("allay.recall.release"),"real wave release emits original Minecraft wind-charge burst event")
	for event:String in ["allay.recall.spin","allay.recall.release"]:
		var record:Dictionary=unit.NATIVE_SOUNDS.EVENTS[event][0]
		check(record.stream.get_length()>0.0 and record.stream is AudioStreamOggVorbis,"original Minecraft OGG is imported: "+event)
		var expected_asset:String="riptide1.ogg" if event=="allay.recall.spin" else "wind_burst1.ogg"
		check(record.stream.resource_path.ends_with("/recall_vanilla/"+expected_asset),"phase uses official Minecraft asset, not generated WAV: "+event)
		check(record.pitch==(1.65 if event=="allay.recall.spin" else 1.25),"faster light spin, unchanged vanilla release pitch: "+event)
		var player:AudioStreamPlayer2D=unit._allay_sound(event,0,center,0.0)
		check(is_instance_valid(player) and player.playing and player.volume_db==0.0,"phase event reaches real player at original volume: "+event)
	var wave:Node=null
	for candidate:Node in get_nodes_in_group("AllayRecallWave"):
		if candidate.source_ref.get_ref()==unit: wave=candidate
	check(wave!=null and wave.max_radius==55.0 and wave.knockback==45.0,"small blue wave and medium knockback configured")
	wave.process_mode=Node.PROCESS_MODE_DISABLED
	var ally:Node=spawn("res://scenes/ball.tscn",center+Vector2(0,20),"Team0")
	ally.process_mode=Node.PROCESS_MODE_DISABLED
	var far:Node=spawn("res://scenes/ball.tscn",center+Vector2(110,0),"Team1")
	far.process_mode=Node.PROCESS_MODE_DISABLED
	var edge:Node=spawn("res://scenes/ball.tscn",center+Vector2(53,0),"Team1")
	edge.process_mode=Node.PROCESS_MODE_DISABLED
	var edge_hp:float=edge.health
	var ally_hp:float=ally.health
	var far_hp:float=far.health
	enemy.global_position=center+Vector2(32,0)
	before=enemy.health
	wave._physics_process(0.11)
	check(is_equal_approx(before-enemy.health,expected*1.2),"wave deals exact combined damage on expansion")
	before=enemy.health
	check(wave.radius>wave.initial_radius and wave.initial_radius==30.0 and wave.damage_window==0.1,"visual expands independently of short fixed damage radius")
	check(edge.health==edge_hp,"initial damage cannot hit target outside starting circle")
	edge.global_position=center+Vector2(0,20)
	wave._physics_process(0.22)
	check(edge.health==edge_hp,"entering initial circle after damage window cannot be hit")
	check(wave.sound_played,"successful explosion emits hit feedback")
	check(unit.hit_volume_db(51.0)<unit.hit_volume_db(100.0) and unit.hit_volume_db(100.0)<unit.hit_volume_db(200.0),"larger damage gives progressively louder feedback")
	check(unit.hit_volume_db(100000.0)<=6.0,"hit feedback gain is bounded")
	edge.queue_free()
	check(enemy.health==before,"wave cannot repeatedly damage same target")
	check(ally.health==ally_hp and far.health==far_hp,"wave spares allies and enemies outside compact radius")
	ally.queue_free(); far.queue_free(); cleanup(unit)
	# Existing airborne notes are recalled first and can still hit before arriving.
	unit=owner_with_notes(5)
	enemy.global_position=center+Vector2(32,0)
	var flying:Node=unit.fire_note(enemy)
	unit.notes-=1
	flying.global_position=center+Vector2(110,0); flying.Damage=30
	flying.process_mode=Node.PROCESS_MODE_DISABLED
	check(unit._recall.try_start() and flying._recall_state==1,"airborne note participates in recall")
	check(unit._recall.live(true).size()==4,"airborne note is not counted as arrived prematurely")
	before=enemy.health
	flying.move(94.0,0.3)
	check(flying._spent and flying.is_queued_for_deletion() and before-enemy.health==30,"returning note hits for normal damage and is consumed before arrival")
	finish_cycle(unit)
	check(not unit._native_sfx_left.has("allay.recall.release"),"insufficient notes never play fake release audio")
	check(unit._recall.last_consumed==4 and unit._recall.last_damage==0.0,"losing one of five means four actually consumed and no final wave")
	var no_wave:bool=true
	for candidate:Node in get_nodes_in_group("AllayRecallWave"):
		if candidate.source_ref.get_ref()==unit: no_wave=false
	check(no_wave,"no blue wave is spawned below five survivors")
	cleanup(unit)
	# Notes that arrive without hitting retain their own heterogeneous damage.
	unit=owner_with_notes(6)
	flying=unit.fire_note(enemy); unit.notes-=1
	flying.global_position=center+Vector2(-100,0); flying.Damage=37
	flying.process_mode=Node.PROCESS_MODE_DISABLED
	unit._recall.try_start()
	flying.move(94.0,0.3)
	check(flying._recall_state==2 and not flying._spent,"unobstructed returning note joins the spinning ring")
	var snapshot:Dictionary=CAPTURE.NATIVE_RETURN.snapshot(flying,CAPTURE.describe(flying))
	check(not snapshot.native_properties.has("_recall_state"),"captured spin note cannot transfer stale recall state to native return")
	expected=37.0
	for note:Node in unit._recall.live(true):
		if note!=flying: expected+=note._recall_damage
	finish_cycle(unit)
	check(unit._recall.last_consumed==6 and is_equal_approx(unit._recall.last_damage,expected*1.2),"arrived flying note contributes its own damage instead of current Allay damage")
	cleanup(unit)
	# Active spin notes still intercept incoming projectiles, reducing final count.
	await process_frame
	unit=owner_with_notes(5)
	unit._recall.try_start()
	var spinner:Node=unit._recall.live(true)[0]
	var bullet:Node=spawn("res://scenes/shooter/子弹.tscn",spinner.global_position,"Team1")
	bullet.Master=enemy
	check(CAPTURE.sweep(bullet,bullet.global_position,bullet.global_position) and spinner._spent,"spinning note retains interception and single-use consumption")
	finish_cycle(unit)
	check(not unit._native_sfx_left.has("allay.recall.release"),"insufficient notes never play fake release audio")
	check(unit._recall.last_consumed==4 and unit._recall.last_damage==0.0,"intercepted spin note is excluded from final blast")
	cleanup(unit)
	unit=owner_with_notes(5)
	unit._recall.try_start()
	spinner=unit._recall.live(true)[0]
	unit.queue_free()
	await process_frame
	if is_instance_valid(spinner):
		spinner.tick_physics(0,0.01)
		check(spinner.is_queued_for_deletion(),"owner removal cannot leave immortal spinning notes")
	else: check(true,"owner removal cleans up spinning notes")
	var script:Script=load("res://scripts/characters/我的世界/allay/note.gd")
	var shape:Node=script.new()
	shape._path_axis=Vector2.RIGHT; shape._curve_side=1.0
	shape._path_length=30.0
	var small:Vector2=shape.curve_offset(0.5)
	shape._path_length=100.0
	var large:Vector2=shape.curve_offset(0.5)
	check(small.length()<large.length()*0.2,"close-range note loop is substantially reduced")
	shape.free()
	enemy.queue_free()
	await create_timer(2.0).timeout
	print("ALLAY_RECALL_TEST checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
