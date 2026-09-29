extends SceneTree
# 溺尸三叉戟：出手当帧瞄准敌人“当前坐标”直飞，飞行终点就是这一帧锁定的那个坐标；
# 中途撞到障碍物 → 插墙；飞到锁定终点仍未命中 → 插在那一点的地面上（落点夹在地图内），
# 附魔与周期引雷照旧。真实 World + Map50x50。
var game:Node
var world:Node
var saved:Dictionary
var saved_stop:bool
var checks:int = 0
var failures:int = 0
var finishing:bool = false
var center:Vector2
var arena:Rect2
var units:Array[Node2D] = []


func _initialize() -> void:
	# Historical ground-lodgement fixtures are retained for inspection only.
	# Their expected gameplay was explicitly withdrawn by the user.
	var legacy:Array[String] = [
		"res://tests/test_drowned_trident_aim_stick.gd",
		"res://tests/test_drowned_surface_probe.gd",
		"res://tests/test_drowned_surface_rules.gd",
		"res://tests/test_drowned_surface_pixels.gd",
		"res://tests/test_capture_drowned_trident_plant.gd"]
	if get_script().resource_path in legacy:
		print("SKIP: ground-plant gameplay was removed; run res://tests/test_drowned_wall_only.gd for the current contract")
		call_deferred("quit",0)
		return
	call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func spawn(path:String,point:Vector2,team:String = "Team0") -> Node2D:
	var unit:Node2D = load(path).instantiate()
	unit.Team = team
	unit.Can_Attack = false
	unit.Can_Skill = false
	unit.Health_Restore = 0
	world.add_child(unit,true)
	unit.global_position = point
	unit.state_machine.set_physics_process(false)
	units.append(unit)
	if unit.has_method("throw_trident"):
		unit._trident.set_physics_process(false)
		unit.native_feedback.set_physics_process(false)
		world.get_node("MCTridentNetwork").set_physics_process(false)
	return unit
func dummy(point:Vector2,team:String = "Team1") -> Node2D:
	var unit:Node2D = spawn("res://scenes/ball.tscn",point,team)
	unit.Max_health = 100000.0
	unit.default_properties["Max_health"] = 100000.0
	unit.health = 100000.0
	unit.Speed = 0.0
	return unit
func park_others(keep:Array) -> void:
	var i:int = 0
	for unit:Node2D in units:
		if unit not in keep:
			unit.global_position = center+Vector2(-800+i*90,800)
			i += 1
func bolts(spear:Node) -> Array[Node]:
	var found:Array[Node] = []
	for child:Node in spear.get_children():
		if child.has_signal("impact_started"): found.append(child)
	return found
func planted_of(drowned:Node) -> Node:
	# 取最近一根插在地面上的戟（插地后 unit._trident 会置空）。
	var planted:Node = null
	for spear:Node in get_nodes_in_group("MCTrident"):
		if spear.unit==drowned and spear.flight_state==3 and spear.planted: planted = spear
	return planted
func advance_until_stuck(spear:Node,limit:int = 1200) -> float:
	var elapsed:float = 0.0
	while elapsed<8.0 and spear.flight_state==1:
		spear.advance(1.0/120.0)
		elapsed += 1.0/120.0
	return elapsed
func ensure_trident(drowned:Node) -> Node:
	# 补发自带的 0.2 秒展示窗口只影响玩法节奏，测试里直接跳过。
	if not is_instance_valid(drowned._trident):
		drowned.tick_physics(drowned.state_machine.current_state,2.5)
	drowned._throw_left = -1.0
	drowned._throw_target = null
	drowned._refill_show_left = 0.0
	return drowned._trident
func catch_back(drowned:Node,spear:Node) -> bool:
	var elapsed:float = 0.0
	while elapsed<8.0 and not drowned.has_trident:
		spear.advance(1.0/120.0)
		elapsed += 1.0/120.0
	return drowned.has_trident
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
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
	await create_timer(0.35).timeout
	if not await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self):
		finish(1)
		return
	arena = world.return_map_world_rect(world.map_group["Map50x50"])
	center = arena.get_center()
	var TRIDENT:Script = load("res://scripts/effects/我的世界/三叉戟.gd")
	var drowned:Node2D = spawn("res://scenes/characters/我的世界/溺尸.tscn",center+Vector2(-260,0))
	var target:Node2D = dummy(center+Vector2(60,0))
	await process_frame
	await process_frame
	drowned.mc_native_animation.set_process(false)
	check(drowned.mc_live(),"fixture drowned is in live combat")

	# --- 1. 出手当帧瞄准敌人的当前坐标 -------------------------------------------------
	var windup_start:Vector2 = target.global_position
	check(drowned.throw_trident(target),"held trident starts its throw windup")
	drowned._advance_trident_throw(drowned.trident_throw_windup*0.5)
	check(drowned.has_trident and drowned._trident.flight_state==0,"weapon stays in hand during preparation")
	target.global_position = center+Vector2(60,-110) # 目标在蓄力途中移动
	var release_point:Vector2 = target.global_position
	drowned._advance_trident_throw(drowned.trident_throw_windup)
	var spear:Node = drowned._trident
	spear.set_physics_process(false)
	check(spear.flight_state==1 and not drowned.has_trident,"release leaves the hand on the release frame")
	check(is_equal_approx(drowned.trident_last_aim_point().x,release_point.x) and is_equal_approx(drowned.trident_last_aim_point().y,release_point.y),"aim point is the enemy position read on the release frame")
	check(drowned.trident_last_aim_point().distance_to(windup_start)>20.0,"the target actually moved between windup start and release")
	check(spear.global_position.direction_to(release_point).dot(spear.axis)>0.9999,"flight axis points from the real release point to the enemy's current position")
	check(spear.axis.angle_to(spear.global_position.direction_to(windup_start))>0.05,"the throw is not aimed at the stale windup-start position")
	var hp:float = target.health
	var hit_steps:int = 0
	while hit_steps<600 and spear.flight_state==1 and target.health>=hp:
		spear.advance(1.0/120.0)
		hit_steps += 1
	check(target.health<hp and is_equal_approx(hp-float(target.health),ceilf(drowned.trident_hit_damage())),"straight throw at the current position lands a direct hit")
	check(spear.flight_state==2,"a direct hit still returns to the hand instead of sticking")
	check(catch_back(drowned,spear) and drowned.has_trident,"loyalty return puts the same trident back in hand")

	# --- 2. 没打到就插在落点地面上 -----------------------------------------------------
	drowned.global_position = center+Vector2(-260,120)
	target.global_position = center+Vector2(60,-120)
	check(drowned.throw_trident(target),"second throw starts")
	drowned._advance_trident_throw(drowned.trident_throw_windup+0.01)
	var missed:Node = drowned._trident
	missed.set_physics_process(false)
	var throw_origin:Vector2 = missed.global_position
	var locked_aim:Vector2 = drowned.trident_last_aim_point()
	var saved_range:float = drowned.trident_range
	var spin_before:float = missed._return_elapsed
	target.global_position = center+Vector2(60,420) # 出手后目标离开弹道
	check(float(missed.material.get_shader_parameter("plant_clip"))<0.5,"an airborne trident is not clipped")
	var stuck_time:float = advance_until_stuck(missed)
	check(missed.flight_state==3 and missed.planted,"a miss sticks in the ground instead of flying home")
	check(missed._return_elapsed==spin_before and missed.wall_ref==null,"a grounded trident neither spins home nor follows a wall")
	# 飞行终点 = 出手当帧锁定的敌人坐标，而不是继续飞到射程尽头。
	check(missed.aim_point.is_equal_approx(locked_aim),"the locked endpoint is the enemy position read on the release frame")
	check(is_equal_approx(missed.flight_length,minf(saved_range,throw_origin.distance_to(locked_aim))),"flight length equals the locked distance, capped by the range")
	check(missed.traveled<=missed.flight_length+0.5,"the trident stops at the locked endpoint instead of flying the whole range")
	check(throw_origin.distance_to(locked_aim)<saved_range-20.0,"fixture keeps the locked endpoint well short of the range end")
	check(is_equal_approx(missed.rotation,TRIDENT.PLANT_ANGLE+TRIDENT.PLANT_LEAN),"grounded trident uses the head-down planted pose")
	# 头朝地：戟叉沿戟轴竖直向下，节点中心被拉回地面上方，只有戟头埋在土里。
	var head_dir:Vector2 = missed.plant_head_direction()
	check(head_dir.y>0.9 and absf(head_dir.x)<0.45,"the planted trident points head-down into the ground")
	check(missed.plant_buried_units()>=4.0,"the whole spear head is sunk below the surface")
	var contact:Vector2 = missed.plant_contact_point()
	check(missed.plant_tip_point().y>contact.y+1.0,"the buried spear tip finishes under the ground it landed on")
	check(missed.global_position.distance_to(contact)>1.5 and missed.global_position.y<contact.y,"the node is pulled back up the shaft so the head, not the shaft, is buried")
	check(arena.grow(-6.0).has_point(contact),"the ground contact point stays inside the map")
	check(drowned.mc_position_clear(contact,6.0),"the ground contact point is not buried inside a wall")
	check(contact.distance_to(throw_origin)>100.0,"the miss planted far along the flight path, not at the thrower")
	check(contact.distance_to(locked_aim)<3.0,"the ground contact sits exactly on the locked endpoint")
	check(is_instance_valid(missed.stuck_mound) and missed.stuck_mound.visible,"the planted sprite draws its ground mound")
	check(is_equal_approx(missed.stuck_mound.rotation,-missed.rotation),"the mound stays level while the shaft is tilted")
	check(missed.stuck_mound.global_position.distance_to(contact)<0.5,"the mound is anchored at the ground contact point")
	# 插地时戟头整体裁掉，断面压在地表以下、由土堆盖住，所以土堆外不会再看到戟叉。
	check(float(missed.material.get_shader_parameter("plant_clip"))>0.5,"the planted sprite clips away the part under the surface")
	check(missed.plant_clip_y()>=contact.y-4.0 and missed.plant_clip_y()<=contact.y,"the clip line sits just above the landing point, at the top of the fork")
	# 地表落在戟叉根部之上：戟头（含白刃）全部在土表以下，所以材质裁切后土面上只剩戟杆。
	check(missed.plant_tip_point().y>missed.plant_clip_y()+4.0,"the buried spear tip ends well below the clip line")
	check(missed.plant_contact_point().distance_to(missed.global_position)<missed.global_position.distance_to(missed.plant_tip_point()),"the surface crossing sits between the node and the buried tip")
	# Body, overlay and stroke geometry now derive world positions in vertex().
	check(is_equal_approx(float(missed.material.get_shader_parameter("plant_clip_y")),missed.plant_clip_y()),"the geometry-based clip plane follows the planted contact")
	var mound_local:Vector2 = missed.stuck_mound.position
	check(mound_local.x>1.2 and mound_local.y<-1.2,"the mound sits on the buried side of the node, under the head")
	check(missed.plant_clip_y()>missed.plant_contact_point().y-4.0,"the cut line stays within the mound so the cut ends stay hidden")
	check(not drowned.has_trident and drowned._trident==null and drowned._refill_left>0.0,"a grounded trident starts the empty-hand refill state")
	check(int(drowned.native_feedback.played.get("item.trident.hit_ground",0))>0,"planting plays the original ground-hit sound")
	# 插地复用重锤的方块碎屑：独立战场寿命，回收戟不会截断刚开始的爆发。
	check(not get_nodes_in_group("MCTridentGroundDebris").is_empty(),"planting into the ground bursts the mace-style block debris")
	var debris:Node2D = get_nodes_in_group("MCTridentGroundDebris")[0]
	check(debris.get_parent()!=missed and int(debris.get_meta("mc_trident_source_id",0))==missed.get_instance_id() and debris.global_position.distance_to(contact)<1.0,"the independent debris burst remains anchored at the trident landing point")
	print("TRIDENT_PLANT: contact=",contact," rotation=",missed.rotation," stuck_after=",stuck_time)

	# --- 3. 插地的戟不造成伤害、继续附魔与引雷 -----------------------------------------
	var neighbor:Node2D = dummy(contact+Vector2(6,0))
	await process_frame
	var neighbor_hp:float = neighbor.health
	missed.advance(0.5)
	check(neighbor.health==neighbor_hp,"a lodged trident deals no contact damage to enemies standing on it")
	check(missed in get_nodes_in_group("MCTrident") and not missed.is_queued_for_deletion(),"the planted trident stays in the world while its owner keeps fighting")
	missed.advance(drowned.stuck_enchant_delay+0.01)
	check(missed.charged and missed.charge_visual.visible,"a grounded trident still enchants after its stuck delay")
	check(missed.charge_visual.global_transform.origin.distance_to(missed.global_position)<1.0,"the enchantment overlay follows the planted pose")
	# 附魔后埋进土里的戟叉不能又透出来：流光遮罩用同一条土表线裁切，电弧只画地面以上。
	check(float(missed.charge_visual.glint_material.get_shader_parameter("plant_clip"))>0.5,"the enchant overlay is clipped at the same ground line")
	check(is_equal_approx(float(missed.charge_visual.glint_material.get_shader_parameter("plant_clip_y")),missed.plant_clip_y()),"the overlay uses the planted ground line")
	print("TRIDENT_ARCS: size=",missed.charge_visual._path.size()," clip_y=",missed.plant_clip_y()," node=",missed.global_position)
	check(missed.charge_visual._path.size()>3 and missed.charge_visual._path.size()<14,"the enchant arcs only keep the part above the ground")
	var arcs_ok:bool = true
	for point:Vector2 in missed.charge_visual._path: arcs_ok = arcs_ok and missed.to_global(point).y<=missed.plant_clip_y()+0.6
	check(arcs_ok,"no enchant arc is drawn under the ground line")
	missed.advance(drowned.lightning_first_delay+0.01)
	check(bolts(missed).size()>=1,"the enchanted planted trident still starts its periodic lightning")
	var anchor_ok:bool = false
	for effect:Node in bolts(missed): anchor_ok = anchor_ok or effect.global_position.distance_to(missed.global_position)<=maxf(drowned.lightning_radius,1.0)
	check(anchor_ok,"the lightning anchors to the planted trident itself")
	# 暂停冻结插地戟的引雷计时。
	game.now_stop_state = true
	var frozen:float = missed.lightning_left
	missed.advance(1.0)
	check(is_equal_approx(missed.lightning_left,frozen),"pause freezes the planted trident clock")
	game.now_stop_state = false
	missed.advance(600.0)
	check(not missed.is_queued_for_deletion() and missed.planted,"the planted trident is kept permanently, not cleaned up by age")

	# --- 4. 补发的新戟与插地戟并存 ------------------------------------------------------
	check(ensure_trident(drowned)!=missed and drowned.has_trident,"the drowned refills a fresh trident while the missed one stays planted")
	check(is_instance_valid(planted_of(drowned)),"the planted trident is still reachable for enchantment/network use")

	# --- 5. 副本按快照重放插地姿态 ------------------------------------------------------
	var replica:Node = drowned._create_trident(701)
	replica.set_physics_process(false)
	replica.receive(missed.snapshot())
	check(replica.flight_state==3 and replica.planted and is_equal_approx(replica.rotation,missed.rotation),"a client replica replays the planted state from the snapshot")
	check(replica.stuck_mound.visible and replica.stuck_mound.position.is_equal_approx(missed.stuck_mound.position),"the replica draws the same mound at the same spot")
	replica.retire()

	# --- 6. 撞墙仍然是插墙（外观不变） --------------------------------------------------
	var fresh:Node = ensure_trident(drowned)
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(14,220)
	shape.shape = rect
	wall.add_child(shape)
	world.add_child(wall)
	drowned.global_position = center+Vector2(-200,-260)
	target.global_position = center+Vector2(200,-260)
	wall.global_position = center+Vector2(-40,-260)
	park_others([drowned,target])
	drowned._throw_left = -1.0
	drowned._throw_target = null
	await physics_frame
	check(fresh==drowned._trident and fresh.flight_state==0,"the wall fixture still holds its own trident before the throw")
	var debris_before:int = get_nodes_in_group("MCTridentGroundDebris").size()
	check(drowned.throw_trident(target),"wall throw starts after the refill display window")
	drowned._advance_trident_throw(drowned.trident_throw_windup+0.01)
	fresh = drowned._trident
	fresh.set_physics_process(false)
	advance_until_stuck(fresh)
	print("TRIDENT_WALL: wall=",wall.global_position," origin=",fresh.global_position," traveled=",fresh.traveled," wall_ref=",fresh.wall_ref)
	check(get_nodes_in_group("MCTridentGroundDebris").size()==debris_before,"a wall lodgement does not play the ground debris")
	check(fresh.flight_state==3 and not fresh.planted,"hitting a wall is still a wall lodgement, not a ground plant")
	check(fresh.wall_ref!=null and is_instance_valid(fresh.wall_ref.get_ref()) and not fresh.stuck_mound.visible,"wall lodgement keeps the old look and no mound")
	check(float(fresh.material.get_shader_parameter("plant_clip"))<0.5,"a wall lodgement is never clipped at the ground line")
	check(absf(fresh.global_position.x-(wall.global_position.x-7.0))<4.0,"the wall lodgement still sits on the real wall surface")
	wall.queue_free()
	await physics_frame

	# --- 7. 落点越界时夹回地图内 --------------------------------------------------------
	var clamp_spear:Node = ensure_trident(drowned)
	clamp_spear.set_physics_process(false)
	clamp_spear.launch(Vector2.RIGHT)
	clamp_spear.stick_ground(Vector2(arena.end.x+240.0,arena.end.y+180.0))
	var clamped_contact:Vector2 = clamp_spear.plant_contact_point()
	check(clamp_spear.flight_state==3 and clamp_spear.planted,"an out-of-map ground plant still plants itself")
	check(arena.grow(-5.0).grow(0.6).has_point(clamped_contact),"a landing outside the map is clamped back inside the arena")
	check(drowned.mc_position_clear(clamped_contact,6.0),"the clamped landing is not buried in the map border wall")
	check(clamped_contact.distance_to(Vector2(arena.end.x+240.0,arena.end.y+180.0))>200.0,"the out-of-map request is pulled back to the real playable ground")

	# --- 8. 朝地图边缘投掷不会把戟丢到地图外 --------------------------------------------
	drowned.global_position = Vector2(arena.end.x-170.0,center.y)
	park_others([drowned,target,neighbor])
	target.Repel = Vector2.ZERO
	target.direction = Vector2.ZERO
	target.Speed = 0.0
	target.global_position = drowned.global_position+Vector2(150,0)
	target.Repel = Vector2.ZERO
	drowned._throw_left = -1.0
	drowned._throw_target = null
	await physics_frame
	var border_spear:Node = ensure_trident(drowned)
	drowned.trident_range = 1200.0
	var aim_before:Vector2 = target.global_position
	check(border_spear==drowned._trident and border_spear.flight_state==0,"the edge fixture throws with its own held trident")
	check(drowned.throw_trident(target),"edge throw starts")
	drowned._advance_trident_throw(drowned.trident_throw_windup+0.01)
	border_spear.set_physics_process(false)
	target.global_position = Vector2(center.x,arena.end.y-60.0) # 出手后目标离开弹道
	drowned.trident_range = saved_range
	advance_until_stuck(border_spear)
	var border_contact:Vector2 = border_spear.global_position
	if border_spear.planted: border_contact = border_spear.plant_contact_point()
	check(border_spear.flight_state==3,"a throw aimed at the map edge stops there instead of leaving the world")
	# 锁定落点贴在边界墙上时不再回退插地，而是继续飞一小段，插到那堵墙上。
	# 锁定落点贴着边界墙时：先尝试继续飞插墙；真找不到墙才回退成贴地插，两种都不许出地图。
	if border_spear.ground_seek:
		check(not border_spear.planted or border_spear.plant_contact_point().distance_to(aim_before)>1.0,"a squeezed edge landing never keeps the raw landing when it seeks the wall")
	elif border_spear.planted:
		check(border_spear.plant_contact_point().distance_to(aim_before)<20.0,"a clear edge landing plants near the locked endpoint")
	check(border_spear.traveled<=aim_before.distance_to(drowned.global_position)+320.0,"the edge throw still stops near the locked endpoint, not at the range end")
	check(arena.grow(24.0).has_point(border_contact),"the stopped trident stays inside the map, whatever stops it")
	var border_wall:Variant = border_spear.wall_ref.get_ref() if border_spear.wall_ref!=null else null
	print("TRIDENT_EDGE: arena=",arena," clamped=",clamped_contact," border=",border_contact," border_planted=",border_spear.planted," traveled=",border_spear.traveled," wall=",border_wall.name if is_instance_valid(border_wall) else "none"," class=",border_wall.get_class() if is_instance_valid(border_wall) else "-")
	# --- 9. 落点贴着障碍物：继续沿弹道飞，插到墙上而不是回退插地 ------------------------
	var seek_wall := StaticBody2D.new()
	seek_wall.collision_layer = 1
	seek_wall.collision_mask = 0
	var seek_shape := CollisionShape2D.new()
	var seek_rect := RectangleShape2D.new()
	seek_rect.size = Vector2(14,240)
	seek_shape.shape = seek_rect
	seek_wall.add_child(seek_shape)
	world.add_child(seek_wall)
	var seek_spear:Node = ensure_trident(drowned)
	seek_spear.set_physics_process(false)
	var seek_origin:Vector2 = seek_spear.global_position
	# 墙架在弹道自己所在的高度上，落点故意压在墙面附近：直接插地被挤住，必须继续飞。
	seek_wall.global_position = seek_origin+Vector2(96.0,0.0)
	await physics_frame
	seek_spear.launch(Vector2.RIGHT,seek_origin,Vector2(seek_wall.global_position.x-10.0,seek_origin.y))
	check(not seek_spear._plant_ground_ok(seek_spear.aim_point),"a landing squeezed by the obstacle ahead cannot plant directly")
	var seek_debris_before:int = get_nodes_in_group("MCTridentGroundDebris").size()
	advance_until_stuck(seek_spear)
	print("TRIDENT_SEEK: origin=",seek_origin," wall=",seek_wall.global_position," traveled=",seek_spear.traveled," seek=",seek_spear.ground_seek," planted=",seek_spear.planted," wall_ref=",seek_spear.wall_ref)
	check(seek_spear.flight_state==3 and not seek_spear.planted,"a squeezed landing keeps flying instead of backing up into the ground")
	check(seek_spear.ground_seek,"the flight switched into the wall-seeking extension")
	check(seek_spear.wall_ref!=null and is_instance_valid(seek_spear.wall_ref.get_ref()) and seek_spear.wall_ref.get_ref()==seek_wall,"the extended flight lodges into the obstacle it was flying at")
	check(seek_spear.traveled>seek_origin.distance_to(seek_spear.aim_point)+2.0,"it flew past the blocked landing to reach the wall")
	check(get_nodes_in_group("MCTridentGroundDebris").size()==seek_debris_before,"a wall seek never bursts ground debris")
	seek_wall.queue_free()
	await physics_frame
	# 落点空着时仍然照旧插地（不能因为新规则把正常插地也变成插墙）。
	var open_spear:Node = ensure_trident(drowned)
	open_spear.set_physics_process(false)
	var open_origin:Vector2 = open_spear.global_position
	var open_aim:Vector2 = open_origin+Vector2(120,0)
	open_spear.launch(Vector2.RIGHT,open_origin,open_aim)
	check(open_spear._plant_ground_ok(open_aim),"open ground still accepts a direct ground plant")
	advance_until_stuck(open_spear)
	check(open_spear.planted and open_spear.flight_state==3 and not open_spear.ground_seek,"an unobstructed landing still plants straight into the ground")
	check(open_spear.plant_contact_point().distance_to(open_aim)<2.0,"the ground plant still happens on the locked landing")
	neighbor.queue_free()
	print("TRIDENT_AIM_STICK_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)

func finish(code:int) -> void:
	if finishing: return
	finishing = true
	if not await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self): code = 1
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	if is_instance_valid(world): world.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	_stop_audio(root)
	await create_timer(0.12,true,false,true).timeout
	print("TRIDENT_AIM_STICK_EXIT=",code)
	quit(code)
func _stop_audio(node:Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		node.stop()
		if node.is_in_group("MCNativeSFX"): node.queue_free()
	for child:Node in node.get_children(): _stop_audio(child)
