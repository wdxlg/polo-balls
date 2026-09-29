extends SceneTree
# 撞墙脱困 + 墙体导航回归（确定性场景，无高速突进单位、无接舷干扰）。
# 阶段A1：boat1 从西侧 (-220,-400) 绕过中央墙缺口抵达东侧钉住的羊 (220,-400)。
# 阶段A2：boat2 从西南 (-480,500) 独立绕行同一目标（boat1 眩晕停远角）。
# 阶段B ：boat1 船头与墙零距离正对墙面 (-80,400)、目标 (300,650) 在墙正后方、
#         满油门——必须迅速脱离并绕行抵达，不允许持续顶墙空转。
# 统计口径：headless 下 process_frame 不一定推进物理，全部按物理帧门控。
var checks:int = 0
var failures:int = 0
var arena:Node2D

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("WALL_ESCAPE_FAIL ",label)

func _initialize() -> void:
	call_deferred("run")

func wall_at(point:Vector2,size:Vector2) -> StaticBody2D:
	var wall:StaticBody2D = StaticBody2D.new()
	var cs:CollisionShape2D = CollisionShape2D.new()
	var box:RectangleShape2D = RectangleShape2D.new()
	box.size = size
	cs.shape = box
	wall.add_child(cs)
	arena.add_child(wall)
	wall.global_position = point
	return wall

func spawn(path:String,point:Vector2,team:String,facing:Vector2):
	var packed:PackedScene = load(path)
	if packed == null:
		push_error("Scene unavailable: "+path)
		quit(2)
		return null
	var actor = packed.instantiate()
	actor.Team = team
	actor.position = point
	arena.add_child(actor,true)
	if actor.has_method("get") and actor.get("facing") != null:
		actor.facing = facing
	return actor

func park(actor,point:Vector2) -> void:
	actor.global_position = point
	actor.velocity = Vector2.ZERO
	actor._forward_speed = 0.0
	actor._charge_grace = 0.0
	actor.Repel = Vector2.ZERO
	actor.dizziness = 1e9

func run() -> void:
	root.get_node("Game").now_stop_state = false
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	wall_at(Vector2(-620,0),Vector2(40,880))
	wall_at(Vector2(620,0),Vector2(40,880))
	wall_at(Vector2(0,-560),Vector2(40,560))
	wall_at(Vector2(0,560),Vector2(40,560))
	var boat = spawn("res://scenes/characters/我的世界/木船.tscn",Vector2(-220,-400),"A",Vector2.RIGHT)
	var boat2 = spawn("res://scenes/characters/我的世界/木船.tscn",Vector2(-480,500),"A",Vector2.RIGHT)
	# 目标用羊并每帧钉住：活塞会一帧突进数百像素制造三体顶牛混战，
	# 羊自身也会游走。导航断言需要完全确定的目标位置。
	var sheep = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2(220,-400),"B",Vector2.LEFT)
	if boat == null or boat2 == null or sheep == null:
		quit(2)
		return
	# 压制接舷：船 30px 内会把羊收进船，目标消失会让后续阶段失去导航目标。
	boat._board_left = 1e9
	boat2._board_left = 1e9
	var sheepA0:Vector2 = sheep.global_position
	var tick:float = 1.0/float(Engine.physics_ticks_per_second)
	var pf:int = Engine.get_physics_frames()
	# —— 阶段A1：boat1 绕墙（boat2 眩晕停在西北远角）——
	park(boat2,Vector2(-480,500))
	var stuck1:int = 0
	var slide1:int = 0
	var grind1:int = 0
	var path1:float = 0.0
	var prev1:Vector2 = boat.global_position
	var episodes1:int = 0
	var prev_contact:bool = false
	var reach1:int = -1
	var frames:int = 600
	var tA:int = 0
	while tA < frames:
		await process_frame
		if Engine.get_physics_frames() == pf: continue
		pf = Engine.get_physics_frames()
		tA += 1
		sheep.global_position = sheepA0
		sheep.velocity = Vector2.ZERO
		park(boat2,Vector2(-480,500))
		var s1:float = boat.velocity.length()
		var disp1:float = boat.global_position.distance_to(prev1)
		path1 += disp1
		prev1 = boat.global_position
		if s1 < 5.0: stuck1 += 1
		# 空转磨墙：电机高速运转但实际位移远低于应有值 = 顶着不动。
		if s1 > 60.0 and disp1 < s1*tick*0.35: grind1 += 1
		if absf(boat.global_position.x) < 80.0 and s1 > 20.0: slide1 += 1
		var contact_now:bool = float(boat.get("_wall_contact_left")) > 0.0
		if contact_now and not prev_contact: episodes1 += 1
		prev_contact = contact_now
		if reach1 < 0 and boat.global_position.distance_to(sheep.global_position) < 220.0: reach1 = tA
	check(float(stuck1) < float(frames)*0.25, "boat_not_pinned_against_wall")
	check(path1 > 400.0, "boat_keeps_moving")
	check(slide1 > 20, "boat_slides_along_wall")
	check(boat.global_position.distance_to(sheep.global_position) < 220.0, "boat_routes_around_wall_gap")
	check(episodes1 <= 8, "boat_few_wall_impacts")
	check(reach1 >= 0 and reach1 <= 520, "boat_reaches_target_promptly")
	check(float(grind1) < float(frames)*0.1, "boat_no_wall_grinding")
	# —— 阶段A2：boat2 独立绕墙（boat1 眩晕停在东南远角）——
	park(boat,Vector2(560,750))
	boat2.dizziness = 0.0
	var stuck2:int = 0
	var slide2:int = 0
	var grind2:int = 0
	var path2:float = 0.0
	var prev2:Vector2 = boat2.global_position
	var reach2:int = -1
	var trace2:Array = []
	tA = 0
	while tA < frames:
		await process_frame
		if Engine.get_physics_frames() == pf: continue
		pf = Engine.get_physics_frames()
		tA += 1
		sheep.global_position = sheepA0
		sheep.velocity = Vector2.ZERO
		park(boat,Vector2(560,750))
		var s2:float = boat2.velocity.length()
		var disp2:float = boat2.global_position.distance_to(prev2)
		path2 += disp2
		prev2 = boat2.global_position
		if s2 < 5.0: stuck2 += 1
		if s2 > 60.0 and disp2 < s2*tick*0.35: grind2 += 1
		if absf(boat2.global_position.x) < 80.0 and s2 > 20.0: slide2 += 1
		if reach2 < 0 and boat2.global_position.distance_to(sheep.global_position) < 220.0: reach2 = tA
		if tA % 20 == 0:
			var tg2 = boat2._nearest_outside_enemy()
			trace2.append([snappedf(boat2.global_position.x,1.0),snappedf(boat2.global_position.y,1.0),snappedf(boat2.global_position.distance_to(sheep.global_position),1.0),snappedf(boat2._forward_speed,1.0),snappedf(boat2._back_off_left,1.0),snappedf(boat2._charge_grace,1.0),snappedf(boat2._engage_time,1.0),snappedf(boat2._wall_contact_left,1.0),snappedf(boat2._wall_seek_left,1.0),1 if tg2 != null else 0])
	check(float(stuck2) < float(frames)*0.25, "boat2_not_pinned")
	check(path2 > 400.0, "boat2_keeps_moving")
	check(slide2 > 20, "boat2_slides_along_wall")
	check(reach2 >= 0 and reach2 <= 520, "boat2_routes_around_wall_gap")
	check(float(grind2) < float(frames)*0.1, "boat2_no_wall_grinding")
	# —— 阶段B：boat1 贴墙满油门（boat2 眩晕停在西北远角）——
	park(boat2,Vector2(-560,-780))
	boat.global_position = Vector2(-80,400)
	boat.facing = Vector2.RIGHT
	boat.direction = Vector2.RIGHT
	boat.velocity = Vector2.ZERO
	boat.dizziness = 0.0
	boat._forward_speed = 200.0
	boat._wall_contact_left = 0.0
	boat._follow_side = 0.0
	boat._reverse_left = 0.0
	boat._stuck_time = 0.0
	boat._flush_back = 0.0
	boat._slide_plan_left = 0.0
	sheep.global_position = Vector2(300,650)
	sheep.velocity = Vector2.ZERO
	var sheepB0:Vector2 = sheep.global_position
	var stuckB:int = 0
	var grindB:int = 0
	var episodesB:int = 0
	var reachB:int = -1
	var pathB:float = 0.0
	var flushB:int = 0
	var revB:int = 0
	var traceB:Array = []
	prev_contact = false
	prev1 = boat.global_position
	var framesB:int = 720
	var tB:int = 0
	while tB < framesB:
		await process_frame
		if Engine.get_physics_frames() == pf: continue
		pf = Engine.get_physics_frames()
		tB += 1
		sheep.global_position = sheepB0
		sheep.velocity = Vector2.ZERO
		park(boat2,Vector2(-560,-780))
		var sB:float = boat.velocity.length()
		var dispB:float = boat.global_position.distance_to(prev1)
		pathB += dispB
		prev1 = boat.global_position
		if sB < 5.0: stuckB += 1
		if sB > 60.0 and dispB < sB*tick*0.35: grindB += 1
		var contactB:bool = float(boat.get("_wall_contact_left")) > 0.0
		if contactB and not prev_contact: episodesB += 1
		prev_contact = contactB
		if float(boat.get("_flush_back")) > 0.0: flushB += 1
		if float(boat.get("_reverse_left")) > 0.0: revB += 1
		if reachB < 0 and boat.global_position.distance_to(sheep.global_position) < 250.0: reachB = tB
		if tB % 15 == 0:
			traceB.append([int(boat.global_position.x),int(boat.global_position.y),int(rad_to_deg(boat.facing.angle())),int(rad_to_deg(boat._dbg_desired.angle())),String(boat._dbg_branch),round(boat._dbg_controls.y*10)/10.0,int(boat._forward_speed),int(boat._follow_side)])
	check(float(stuckB) < float(framesB)*0.2, "flush_boat_not_pinned")
	check(float(grindB) < float(framesB)*0.1, "flush_boat_no_grinding")
	check(episodesB <= 6, "flush_boat_few_impacts")
	# 自行脱离贴墙点并绕墙航行，而不是原地磨墙。
	check(boat.global_position.distance_to(Vector2(-80,400)) > 180.0, "flush_boat_breaks_away")
	check(pathB > 450.0, "flush_boat_keeps_moving")
	check(reachB >= 0, "flush_boat_reaches_enemy_side")
	check(boat.health > 0.0 and boat2.health > 0.0 and sheep.health > 0.0, "actors_alive")
	# —— 阶段C：押送俘虏撞墙处决——高速撞墙必须让敌方乘客掉血，船不自伤 ——
	sheep.queue_free()
	boat.global_position = Vector2(-300,-400)
	boat.facing = Vector2.RIGHT
	boat.direction = Vector2.RIGHT
	boat.velocity = Vector2.ZERO
	boat._forward_speed = 0.0
	boat._angular_speed = 0.0
	boat._wall_contact_left = 0.0
	boat._follow_side = 0.0
	boat._reverse_left = 0.0
	boat._stuck_time = 0.0
	boat._flush_back = 0.0
	boat._slide_plan_left = 0.0
	boat._wall_heading = Vector2.ZERO
	boat._wall_seek_left = 0.0
	boat._roam_left = 0.0
	boat._crash_cd = 0.0
	var captive = spawn("res://scenes/characters/我的世界/羊.tscn",boat.global_position+Vector2(28,0),"B",Vector2.LEFT)
	if captive == null:
		quit(2)
		return
	check(boat.board_unit(captive),"captive_boarded_for_wall_ram")
	captive.Can_Attack = false
	var cap_hp:float = captive.health
	var ship_hp2:float = boat.health
	var boat_hpC_last:float = ship_hp2
	var selfDmgC:Array = []
	var damagedC:int = -1
	var pathC:float = 0.0
	prev1 = boat.global_position
	var framesC:int = 600
	var tC:int = 0
	while tC < framesC:
		await process_frame
		if Engine.get_physics_frames() == pf: continue
		pf = Engine.get_physics_frames()
		tC += 1
		park(boat2,Vector2(-560,-780))
		var dispC:float = boat.global_position.distance_to(prev1)
		pathC += dispC
		prev1 = boat.global_position
		if boat.health < boat_hpC_last:
			boat_hpC_last = boat.health
			selfDmgC.append([tC,int(boat.global_position.x),int(boat.global_position.y)])
		if damagedC < 0 and is_instance_valid(captive) and captive.health < cap_hp: damagedC = tC
	check(damagedC >= 0 and damagedC <= 300,"wall_ram_damages_captive_promptly")
	check(boat.health == ship_hp2,"wall_ram_no_self_damage")
	check(pathC > 300.0,"wall_ram_keeps_moving")
	# —— 阶段D：满员船低速顶上敌人——必须倒开拉距、全速冲撞造成 ram 伤害，
	# 而不是"退一点点—贴上—低速磨蹭"的无伤死循环 ——
	boat.global_position = Vector2(-210,-100)
	boat.facing = Vector2.RIGHT
	boat.direction = Vector2.RIGHT
	boat.velocity = Vector2.ZERO
	boat._forward_speed = 40.0
	boat._angular_speed = 0.0
	boat._wall_contact_left = 0.0
	boat._follow_side = 0.0
	boat._reverse_left = 0.0
	boat._stuck_time = 0.0
	boat._flush_back = 0.0
	boat._slide_plan_left = 0.0
	boat._wall_heading = Vector2.ZERO
	boat._wall_seek_left = 0.0
	boat._roam_left = 0.0
	boat._crash_cd = 0.0
	boat._back_off_left = 0.0
	boat._detour_left = 0.0
	var captive2 = spawn("res://scenes/characters/我的世界/羊.tscn",boat.global_position+Vector2(-28,0),"B",Vector2.RIGHT)
	check(captive2 != null and boat.board_unit(captive2),"second_captive_boarded_full_ship")
	var victimV0:Vector2 = Vector2(-60,-100)
	var victim = spawn("res://scenes/characters/我的世界/羊.tscn",victimV0,"B",Vector2.LEFT)
	if victim == null or captive2 == null:
		quit(2)
		return
	var vic_hp:float = victim.health
	var vic_hpD_last:float = vic_hp
	var hitDistD:Array = []
	var damagedD:int = -1
	var maxdistD:float = 0.0
	var pathD:float = 0.0
	var traceD:Array = []
	prev1 = boat.global_position
	var framesD:int = 600
	var tD:int = 0
	while tD < framesD:
		await process_frame
		if Engine.get_physics_frames() == pf: continue
		pf = Engine.get_physics_frames()
		tD += 1
		victim.global_position = victimV0
		victim.velocity = Vector2.ZERO
		park(boat2,Vector2(-560,-780))
		var dispD:float = boat.global_position.distance_to(prev1)
		pathD += dispD
		prev1 = boat.global_position
		maxdistD = maxf(maxdistD,boat.global_position.distance_to(victimV0))
		if victim.health < vic_hpD_last:
			vic_hpD_last = victim.health
			hitDistD.append(boat.global_position.distance_to(victimV0))
			if damagedD < 0: damagedD = tD
		if tD % 15 == 0:
			traceD.append([tD,int(boat.global_position.x),int(boat.global_position.y),int(rad_to_deg(boat.facing.angle())),String(boat._dbg_branch),round(boat._dbg_controls.y*10)/10.0,int(boat._forward_speed),int(boat.global_position.distance_to(victimV0)),int(boat._back_off_left*10),int(boat._engage_time*10),int(boat._charge_grace*10),int(boat.Repel.x),int(boat.Repel.y),int(boat.velocity.length()),String(boat._dbg_ram)])
	check(damagedD >= 0 and damagedD <= 480,"full_ship_ram_damages_victim")
	check(maxdistD >= 200.0,"full_ship_backs_off_for_run_up")
	check(pathD > 300.0,"full_ship_keeps_moving")
	# 钉住的受害羊会近身反击，船掉血属正常交战；只要求船活着。
	check(boat.health > 0.0,"full_ship_survives_melee")
	# —— 阶段E：追击横向逃逸的移动目标——必须追上并撞到，
	# 而不是"追 1.2s → 倒开 3.5s → 再追"的无效循环 ——
	boat.global_position = Vector2(-300,-300)
	boat.facing = Vector2.RIGHT
	boat.direction = Vector2.RIGHT
	boat.velocity = Vector2.ZERO
	boat._forward_speed = 0.0
	boat._angular_speed = 0.0
	boat._wall_contact_left = 0.0
	boat._follow_side = 0.0
	boat._reverse_left = 0.0
	boat._stuck_time = 0.0
	boat._flush_back = 0.0
	boat._slide_plan_left = 0.0
	boat._wall_heading = Vector2.ZERO
	boat._wall_seek_left = 0.0
	boat._roam_left = 0.0
	boat._crash_cd = 0.0
	boat._back_off_left = 0.0
	boat._detour_left = 0.0
	boat._charge_grace = 0.0
	boat._engage_time = 0.0
	var vic_hpE:float = victim.health
	var vic_hpE_last:float = vic_hpE
	var hitDistE:Array = []
	var damagedE:int = -1
	var pathE:float = 0.0
	var backE:int = 0
	prev1 = boat.global_position
	var thetaE:float = PI
	var framesE:int = 600
	var tE:int = 0
	while tE < framesE:
		await process_frame
		if Engine.get_physics_frames() == pf: continue
		pf = Engine.get_physics_frames()
		tE += 1
		# 受害者绕原点以 120px/s 切向逃逸（半径 250，不触碰任何墙）。
		park(boat2,Vector2(-560,-780))
		thetaE += 0.48*tick
		victim.global_position = Vector2(cos(thetaE),sin(thetaE))*250.0
		victim.velocity = Vector2.ZERO
		var dispE:float = boat.global_position.distance_to(prev1)
		pathE += dispE
		prev1 = boat.global_position
		if boat._back_off_left > 0.0: backE += 1
		if victim.health < vic_hpE_last:
			vic_hpE_last = victim.health
			hitDistE.append(boat.global_position.distance_to(victim.global_position))
			if damagedE < 0: damagedE = tE
	check(damagedE >= 0 and damagedE <= 540,"chase_moving_target_ram_connects")
	check(hitDistD.is_empty() or float(hitDistD.max()) <= 48.0,"ramD_visual_contact_range")
	check(hitDistE.is_empty() or float(hitDistE.max()) <= 48.0,"ramE_visual_contact_range")
	check(hitDistE.size() >= 2,"chase_ram_repeat_connects")
	check(backE < 240,"chase_no_backoff_spam")
	check(pathE > 450.0,"chase_keeps_moving")
	print("WALL_ESCAPE_STATS ",JSON.stringify({"stuck1":stuck1,"slide1":slide1,"grind1":grind1,"path1":path1,"episodes1":episodes1,"reach1":reach1,"stuck2":stuck2,"slide2":slide2,"grind2":grind2,"path2":path2,"reach2":reach2,"trace2":trace2,"frames":frames,"stuckB":stuckB,"grindB":grindB,"episodesB":episodesB,"reachB":reachB,"pathB":pathB,"flushB":flushB,"revB":revB,"facingB":boat.facing.angle(),"framesB":framesB,"selfDmgC":selfDmgC,"damagedC":damagedC,"pathC":pathC,"capHpC":captive.health if is_instance_valid(captive) else -1,"damagedD":damagedD,"maxdistD":maxdistD,"pathD":pathD,"vicHpD":vic_hpE,"damagedE":damagedE,"pathE":pathE,"backE":backE,"vicHpE":victim.health,"hitDistD":hitDistD,"hitDistE":hitDistE,"traceD":traceD,"traceB":traceB}))
	print("WALL_ESCAPE_RESULT checks=%d failures=%d"%[checks,failures])
	quit(1 if failures > 0 else 0)
