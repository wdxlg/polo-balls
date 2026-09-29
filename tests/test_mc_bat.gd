extends SceneTree
var BAT:Script
var world:Node
var game:Node
var saved:Dictionary
var saved_stop:bool
var checks:int = 0
var failures:int = 0
var done:bool = false
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: "+label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func spawn(path:String,point:Vector2,team:String = "Team0") -> Node2D:
	var unit:Node2D = load(path).instantiate() as Node2D
	unit.Team = team
	unit.Can_Attack = false
	unit.Can_Skill = false
	unit.Health_Restore = 0
	unit.position = point
	world.add_child(unit,true)
	return unit
# Arrange the completed gather pose only for unrelated legacy mechanic tests.
# The dedicated transform test exercises actual convergence and terrain movement.
func settle_fusion(unit:Node2D) -> void:
	unit.fuse_swarm()
	if not bool(unit.cohort.get("gathering",false)): return
	for member:Node2D in unit.living_members(): member.global_position = unit.cohort.gather_point
	unit.cohort.gather_elapsed = unit.gather_min_duration
	unit.try_complete_gather()
func pause_members(unit:Node2D) -> void:
	for b:Node2D in unit.call("living_members"): b.state_machine.set_physics_process(false)
func totals(unit:Node2D) -> Vector2i:
	var value := Vector2i.ZERO
	for b:Node2D in unit.call("living_members"):
		value += Vector2i(int(b.health),b.Max_health)
	return value
func finish(code:int) -> void:
	if done: return
	done = true
	print("BAT RESULT: ",checks-failures,"/",checks," passed")
	if game != null:
		game.Game_Settings = saved
		game.now_stop_state = saved_stop
	# Stop the prewarm consumer before the test drains its outstanding load requests.
	if is_instance_valid(world):
		for node:Node in world.find_children("*","Node",true,false):
			if node.get_script() != null and node.get_script().resource_path.ends_with("mc_native_prewarm.gd"):
				node.set_process(false)
	# Drain pre-existing World background loads before engine shutdown.
	var warm:Script = load("res://scripts/effects/我的世界/mc_native_prewarm.gd")
	for role:String in warm.CHARACTERS:
		var path:String = "res://scenes/characters/我的世界/"+role+".tscn"
		var status:int = ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS or status == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(path)
	if is_instance_valid(world): world.queue_free()
	await process_frame
	quit(code)
func run() -> void:
	game = root.get_node("Game")
	BAT = load("res://scripts/characters/我的世界/bat/bat.gd")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(65.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var b:Node2D = spawn(BAT.SCENE_PATH,center+Vector2(-100,0))
	b.state_machine.set_physics_process(false)
	var target:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(70,0),"Team1")
	target.state_machine.set_physics_process(false)
	target.Max_health = 10000
	target.default_properties["Max_health"] = 10000
	target.health = 10000
	target.Has_Collision_Damage = false
	await physics_frame
	await process_frame
	pause_members(b)
	check(b.call("living_members").size() == 5,"one roster selection creates exactly five bats")
	check(totals(b) == Vector2i(150,150),"initial swarm HP and maximum are 5 x 30")
	check(world.return_all_character_names().has("蝙蝠"),"bat appears in real Minecraft roster index")
	check(b.call("mc_live"),"real World combat is active")
	check(not b.call("mc_enemy",b.call("living_members")[1]),"cohort mates cannot bite each other")
	game.Game_Settings.Have_Team_Damage = true
	check(not b.call("mc_enemy",b.call("living_members")[1]),"cohort mates protected even with team damage enabled")
	game.Game_Settings.Have_Team_Damage = false
	var old_hp:int = b.health
	var old_max:int = b.Max_health
	var damage:int = b.call("drain_target",target)
	check(damage == 2 and b.health == old_hp+2 and b.Max_health == old_max+2,"bat heals and grows by actual health damage")
	b.restore_default_runtime_properties_fast()
	check(b.Max_health == old_max+2,"growth survives World property reset")
	target.max_block = 100
	target.default_properties["max_block"] = 100
	target.block = 100
	old_hp = b.health
	old_max = b.Max_health
	check(b.call("drain_target",target) == 0 and b.health == old_hp and b.Max_health == old_max,"blocked hits cannot generate lifesteal or capacity")
	target.block = 0
	game.now_stop_state = true
	var left:float = b.cohort.left
	b.tick_physics(0,1.0)
	check(b.cohort.left == left and b.call("drain_target",target) == 0,"pause freezes timers and damage")
	game.now_stop_state = false
	var sum_before:Vector2i = totals(b)
	settle_fusion(b)
	check(b.vampire and b.call("living_members").size() == 1,"five bats fuse into one vampire")
	check(totals(b) == sum_before,"fusion exactly conserves HP and capacity")
	check(b.Damage == 8 and b.Speed == 120.0,"vampire has stronger attack and movement stats")
	check(b.image.texture == BAT.VAMPIRE_TEXTURE,"vampire uses actual skin face crop")
	b.health -= 30
	old_hp = b.health
	old_max = b.Max_health
	var expected_damage:int = int(b.attack_damage())
	damage = b.call("drain_target",target)
	check(damage == expected_damage and b.health == old_hp+expected_damage*2 and b.Max_health == old_max+expected_damage,"vampire heals 2x actual damage and grows maximum by actual damage")
	b.health = 65
	sum_before = totals(b)
	b.call("split_swarm")
	pause_members(b)
	check(not b.vampire and b.call("living_members").size() == 2,"65/30 floors to two bats")
	check(totals(b) == sum_before,"split conserves both totals with integer remainders")
	var other:Node2D = b.call("living_members")[1]
	check(absi(int(b.health)-int(other.health)) <= 1 and absi(b.Max_health-other.Max_health) <= 1,"split allocation differs by at most one HP")
	check(BAT.split_count(1,30) == 1 and BAT.split_count(0,30) == 0,"low positive HP creates one; dead vampires create none")
	check(BAT.split_count(300,30) == 10,"growth may split into more than the initial five")
	# Leader death must not remove or disable the remaining independent member.
	b.health = 0
	await physics_frame
	await process_frame
	check(is_instance_valid(other) and other.health > 0 and other.call("living_members").size() == 1,"leader death preserves surviving bat and cohort leadership")
	settle_fusion(other)
	check(other.vampire,"survivor can continue transformation cycle")
	other.health = 1
	other.call("split_swarm")
	check(other.health == 1 and other.call("living_members").size() == 1,"one-HP vampire becomes one one-HP bat")
	# Repeated wounded morphs cannot mint HP/capacity.
	for i:int in range(4):
		var previous:Vector2i = totals(other)
		settle_fusion(other)
		other.call("split_swarm")
		check(totals(other) == previous,"repeated morph conservation "+str(i+1))
	# Bite uses target body geometry and follows without terrain phasing.
	other.Max_health = 80
	other.default_properties["Max_health"] = 80
	other.health = 80
	other.global_position = target.global_position+Vector2(-18,0)
	other.set("_cooldown",0.0)
	await physics_frame
	other.call("begin_bite",target)
	check(other.call("attached_target") == target,"near-body bite attaches to the actual enemy")
	var victim_before:int = target.health
	other.tick_physics(0,0.51)
	check(target.health < victim_before,"attachment periodically deals real health damage")
	var offset_before:Vector2 = other.global_position-target.global_position
	target.global_position += Vector2(6,0)
	other.move(other.Speed,0.016)
	check((other.global_position-target.global_position).distance_to(offset_before) < 2.0,"attached bat follows a moving host")
	other.tick_physics(0,2.1)
	check(other.call("attached_target") == null,"attachment expires after at most two seconds")
	other.set("_cooldown",0.0)
	other.call("begin_bite",target)
	target.queue_free()
	await process_frame
	other.tick_physics(0,0.1)
	check(other.call("attached_target") == null,"freed target detaches without stale instance access")
	var start:Vector2 = other.global_position
	other.direction = Vector2.RIGHT
	other.set("_cooldown",3.0)
	other.tick_physics(0,0.016)
	check(other.global_position.distance_to(start) > 0.0,"unattached bat retains standard movement")
	check(BAT.BAT_AUDIO.EVENTS.size() == 6,"six native sound events are registered")
	for event:String in BAT.BAT_AUDIO.EVENTS:
		check(BAT.BAT_AUDIO.EVENTS[event][0].stream.get_length() > 0.0,"nonempty original audio: "+event)
	# Wall occlusion is checked before damage, not only during subsequent movement.
	var victim:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(0,100),"Team1")
	victim.state_machine.set_physics_process(false)
	victim.Has_Collision_Damage = false
	other.global_position = victim.global_position+Vector2(-26,0)
	other.set("_cooldown",0.0)
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var wall_shape := CollisionShape2D.new()
	var wall_rect := RectangleShape2D.new()
	wall_rect.size = Vector2(3,80)
	wall_shape.shape = wall_rect
	wall.add_child(wall_shape)
	world.add_child(wall)
	wall.global_position = victim.global_position+Vector2(-21,0)
	await physics_frame
	var wall_hp:int = victim.health
	other.call("begin_bite",victim)
	check(other.call("attached_target") == null and victim.health == wall_hp,"thin wall blocks bite and damage")
	wall.queue_free()
	await physics_frame
	await process_frame
	other.call("begin_bite",victim)
	check(other.call("attached_target") == victim,"same near-body geometry bites after wall removal")
	victim.global_position += Vector2(130,0)
	other.tick_physics(0,0.1)
	check(other.call("attached_target") == null,"teleporting enemy breaks attachment instead of teleporting bat")
	settle_fusion(other)
	other.health = maxi(1,int(other.health)-20)
	var heal_before:int = other.health
	victim.health = 1
	var capped_damage:int = other.call("drain_target",victim)
	check(capped_damage == 1 and other.health == heal_before+2,"vampire overkill only heals twice actual remaining enemy HP")
	var second:Node2D = spawn(BAT.SCENE_PATH,center+Vector2(150,-100),"Team0")
	second.state_machine.set_physics_process(false)
	await physics_frame
	await process_frame
	pause_members(second)
	check(second.cohort.id != other.cohort.id and second.living_members().size() == 5,"separately placed swarms have independent cohorts")
	var isolated:Vector2i = totals(second)
	other.call("split_swarm")
	check(totals(second) == isolated,"one swarm transformation never consumes another swarm")
	finish(0 if failures == 0 else 1)
