extends SceneTree
## 凋灵骷髅头部烟雾弹（2026-09-28）：600 血/20 近战；敌人在近战范围外才冷却（3 秒）；
## 弹体=凋灵头颅拖尾粒子的聚合团并留同款拖尾；小幅追踪；命中 5 伤 + 叠加凋零。
## 修订（同日）：弹体改为在弹体位置随机生成粒子（同向切向漂移=旋转感）；先向后上方弹出再被拉回的抛物线，巡航 120；发射音效；人物整体 0.9 倍。
var EFFECTS:Script
var BOLT:Script
var checks:int = 0
var failures:int = 0
var arena:Node2D
var actor:Node2D

func _initialize() -> void: call_deferred("run")
func check(value:bool,label:String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("WS_BOLT_FAIL: "+label)
	else:
		print("WS_BOLT_PASS: "+label)

func make_target(label:String,point:Vector2,body:bool = false,team:String = "B") -> Node2D:
	var target:Node2D = load("res://scenes/ball.tscn").instantiate()
	target.name = label
	target.Team = team
	target.Max_health = 10000
	target.Has_Collision_Damage = false
	target.position = point
	target.get_node("CharacterAutoFit").enabled = false
	var shape := CircleShape2D.new()
	shape.radius = 9.0
	target.get_node("hurtbox/CollisionShape2D").shape = shape
	var body_shape := CircleShape2D.new()
	body_shape.radius = 9.0
	target.get_node("CollisionShape2D").shape = body_shape
	target.get_node("CollisionShape2D").disabled = not body
	target.get_node("hitbox/CollisionShape2D").disabled = true
	arena.add_child(target,true)
	target.set_physics_process(false)
	target.state_machine.set_physics_process(false)
	target.set_process(false)
	target.health = 10000
	target.block = 0
	return target

func bolts() -> Array[Node]:
	var result:Array[Node] = []
	for node:Node in get_nodes_in_group("MCWitherSkeletonBolt"):
		if not node.is_queued_for_deletion(): result.append(node)
	return result

func clear_bolts() -> void:
	for node:Node in get_nodes_in_group("MCWitherSkeletonBolt"): node.free()

func run() -> void:
	EFFECTS = load("res://scripts/effects/我的世界/mc_status_effects.gd")
	BOLT = load("res://scripts/characters/我的世界/wither_skeleton/wither_bolt.gd")
	create_timer(60.0,true,false,true).timeout.connect(func(): quit(2))
	root.get_node("Game").now_stop_state = false
	root.size = Vector2i(800,600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	arena = Node2D.new()
	arena.name = "WitherSkeletonBoltTest"
	root.add_child(arena)
	current_scene = arena
	var background := ColorRect.new()
	background.size = Vector2(800,600)
	background.color = Color("7a8f5a")
	background.z_index = -10
	arena.add_child(background)
	actor = load("res://scenes/characters/我的世界/凋灵骷髅.tscn").instantiate()
	actor.name = "WitherSkeleton"
	actor.Team = "A"
	actor.position = Vector2(200,300)
	arena.add_child(actor)
	actor.set_physics_process(false)
	actor.state_machine.set_physics_process(false)
	actor.set_process(false)
	actor.voice.set_physics_process(false)
	await process_frame
	actor.health = actor.Max_health

	# --- 属性 ---
	check(actor.Max_health == 700 and actor.health == 700,"health is 700 (2026-09-29)")
	check(actor.Damage == 20 and is_equal_approx(actor.attack_damage(1.0),20.0),"melee damage is 20")
	check(is_equal_approx(actor.bolt_damage(),5.0),"bolt damage is 5 at base stats")
	check(is_equal_approx(actor.BOLT_COOLDOWN,3.0) and is_equal_approx(actor.bolt_cooldown_left,3.0),"medium 3 s cooldown, starts un-ready")

	# --- 冷却只在敌人处于近战范围外时进行 ---
	var foe:Node2D = make_target("Foe",actor.global_position+Vector2(40,0))
	await physics_frame
	check(not actor.enemy_outside_melee(foe),"enemy at 40 px is inside melee range")
	actor.step_mob(1.0)
	actor.cancel_combo()
	actor.cooldown_left = 0.0
	check(is_equal_approx(actor.bolt_cooldown_left,3.0),"cooldown frozen while enemy is in melee range")
	check(actor.bolts_fired == 0,"no bolt fired at melee range")
	foe.global_position = actor.global_position+Vector2(260,0)
	await physics_frame
	check(actor.enemy_outside_melee(foe),"enemy at 260 px is outside melee range")
	actor.step_mob(1.0)
	check(is_equal_approx(actor.bolt_cooldown_left,2.0) and actor.bolts_fired == 0,"cooldown counts down when enemy is outside melee range")
	foe.global_position = actor.global_position+Vector2(40,0)
	await physics_frame
	actor.step_mob(1.0)
	actor.cancel_combo()
	actor.cooldown_left = 0.0
	check(is_equal_approx(actor.bolt_cooldown_left,2.0),"cooldown pauses again when the enemy re-enters melee range")
	actor.dizziness = true
	foe.global_position = actor.global_position+Vector2(260,0)
	await physics_frame
	actor.step_mob(1.0)
	check(is_equal_approx(actor.bolt_cooldown_left,2.0),"stun also freezes the cooldown")
	actor.dizziness = false
	foe.free()

	# --- 发射 + 命中 ---
	var target:Node2D = make_target("Target",actor.global_position+Vector2(220,-40),true)
	await physics_frame
	await physics_frame
	actor.step_mob(1.0)
	check(actor.bolts_fired == 0 and is_equal_approx(actor.bolt_cooldown_left,1.0),"not yet ready")
	actor.step_mob(1.0)
	check(actor.bolts_fired == 1 and is_equal_approx(actor.bolt_cooldown_left,3.0),"fires when ready and restarts the cooldown")
	check(int(actor.voice.played.get("shoot",0)) == 1,"firing plays the shoot sound once")
	var shoot_ok:bool = true
	for record:Dictionary in actor.voice.events.get("shoot",[]):
		shoot_ok = shoot_ok and (record.stream as AudioStream).resource_path == "res://audio/characters/我的世界/wither/shoot.ogg"
	check(shoot_ok and actor.voice.events.get("shoot",[]).size() == 3,"shoot sound is the vanilla Wither shoot OGG (3 pitch variants)")
	var list:Array[Node] = bolts()
	check(list.size() == 1,"exactly one bolt in flight")
	var bolt:Node2D = list[0] if list.size() > 0 else null
	var muzzle:Vector2 = actor.bolt_muzzle_position()
	check(bolt != null and bolt.global_position.distance_to(muzzle) < 0.01,"bolt starts at the head muzzle")
	var fire_aim:Vector2 = bolt.aim
	check(bolt.velocity.dot(fire_aim) < 0.0 and bolt.velocity.y < 0.0 and is_equal_approx(bolt.velocity.length(),100.0),"bolt pops out backward-and-up at 100 (" + str(bolt.velocity) + ")")
	var muzzle_pixel:Vector2 = actor.image.global_transform.affine_inverse()*muzzle-actor.image.offset+Vector2(80.0,112.0)
	check(muzzle_pixel.y > 56.0 and muzzle_pixel.y < 100.0 and absf(muzzle_pixel.x-80.0) < 1.0,"muzzle lies on the head of the original sprite (pixel " + str(muzzle_pixel) + ")")
	# 弹体 = 在弹体位置随机生成的同款拖尾粒子（无固定贴图）
	var fixed_sprites:int = 0
	for child:Node in bolt.get_children():
		if child is Sprite2D: fixed_sprites += 1
	check(fixed_sprites == 0,"bolt has no fixed body sprite")
	await physics_frame
	var body:Array[Node] = get_nodes_in_group(BOLT.BODY_GROUP)
	var near:bool = true
	var same:bool = true
	var swirl_ok:bool = true
	var spin_sign:float = 0.0
	var offsets:Dictionary = {}
	var widths:Dictionary = {}
	var body_rot:Dictionary = {}
	var body_width_ok:bool = true
	# 出膛补团的粒子（组内最先加入的 BODY_LAUNCH_BURST 个）以出膛点为中心，检查同向切向漂移。
	for k:int in range(mini(BOLT.BODY_LAUNCH_BURST,body.size())):
		var burst_off:Vector2 = (body[k]._start as Vector2)-muzzle
		if burst_off.length() > 1.0:
			var burst_motion:Vector2 = body[k]._motion
			var cross:float = burst_off.normalized().cross(burst_motion)
			if spin_sign == 0.0: spin_sign = signf(cross)
			swirl_ok = swirl_ok and signf(cross) == spin_sign and absf(burst_off.normalized().dot(burst_motion)) < burst_motion.length()*0.5
	for p:Node in body:
		var start:Vector2 = p._start
		var off:Vector2 = start-bolt.global_position
		near = near and off.length() <= BOLT.BODY_RADIUS+4.0
		same = same and p.texture == BOLT.SMOKE and p.self_modulate.r < 0.3
		offsets[Vector2i((off*4.0).round())] = true
		widths[snappedf(p._pixel_width,0.05)] = true
		body_rot[snappedf(p.rotation,0.05)] = true
		body_width_ok = body_width_ok and p._pixel_width >= BOLT.BODY_WIDTH.x-0.001 and p._pixel_width <= BOLT.BODY_WIDTH.y+0.001
	print("WS_BOLT_METRIC body_particles=",body.size()," distinct_offsets=",offsets.size()," distinct_widths=",widths.size())
	check(body.size() >= BOLT.BODY_LAUNCH_BURST,"bolt body appears immediately as a burst of particles")
	check(near,"body particles spawn within the bolt radius")
	check(offsets.size() >= body.size()-1 and widths.size() >= 4,"body particle positions and sizes are random")
	check(same,"body particles are the Wither-skull trail smoke particle")
	check(body_rot.size() >= int(body.size()*0.7),"body particle angles are random (" + str(body_rot.size()) + "/" + str(body.size()) + " distinct)")
	check(body_width_ok,"body particle size varies only in a small range (6.0-7.5)")
	check(swirl_ok,"every body particle swirls the same way around the centre (rotating cloud)")
	check(bolt.is_in_group("AI_Hazard") and bolt.get_ai_hazard_info().get("damage",0.0) == 5.0,"bolt is visible to AI dodge as 5-damage hazard")
	# 飞行途中截图
	var trail_seen:int = 0
	var shot_taken:bool = false
	var hit_frames:int = -1
	for f:int in range(360):
		await physics_frame
		if not is_instance_valid(bolt) or bolt.finished:
			hit_frames = f
			break
		trail_seen = maxi(trail_seen,get_nodes_in_group(BOLT.TRAIL_GROUP).size())
		if not shot_taken and bolt.traveled > 110.0:
			shot_taken = true
			await RenderingServer.frame_post_draw
			var image:Image = root.get_texture().get_image()
			DirAccess.make_dir_recursive_absolute("user://wither_skeleton_bolt")
			image.save_png("user://wither_skeleton_bolt/flight.png")
			var c:Vector2 = bolt.global_position
			image.get_region(Rect2i(int(c.x)-60,int(c.y)-30,120,60)).save_png("user://wither_skeleton_bolt/flight_crop.png")
			print("WS_BOLT_METRIC bolt_at=",c)
	check(trail_seen >= 10,"bolt leaves the same smoke trail (" + str(trail_seen) + " particles)")
	var trail_same:bool = true
	var trail_rot:Dictionary = {}
	var trail_widths:Dictionary = {}
	var trail_count:int = 0
	for p:Node in get_nodes_in_group(BOLT.TRAIL_GROUP):
		if p.is_in_group(BOLT.BODY_GROUP): continue # 弹体粒子另有随机宽度，单独检查
		trail_count += 1
		trail_rot[snappedf(p.rotation,0.05)] = true
		trail_widths[snappedf(p._pixel_width,0.02)] = true
		trail_same = trail_same and p.texture == BOLT.SMOKE and p.self_modulate.r < 0.3 \
			and p._pixel_width >= BOLT.TRAIL_WIDTH*BOLT.TRAIL_WIDTH_JITTER.x-0.001 and p._pixel_width <= BOLT.TRAIL_WIDTH*BOLT.TRAIL_WIDTH_JITTER.y+0.001
	check(trail_same,"trail particles use the skull-trail texture, size within 8 +-12%")
	check(trail_count >= 5 and trail_rot.size() >= int(trail_count*0.7) and trail_widths.size() >= mini(trail_count,5)-1,"trail particle angles and sizes are random (" + str(trail_rot.size()) + " angles / " + str(trail_widths.size()) + " sizes of " + str(trail_count) + ")")
	print("WS_BOLT_METRIC hit_frames=",hit_frames)
	check(hit_frames > 0,"bolt reaches the target")
	check(target.health == 9995,"bolt hit deals exactly 5 (" + str(target.health) + ")")
	check(EFFECTS.level_of(target,"wither") == 1,"bolt hit applies Wither I")
	check(actor.bolt_hits == 1,"hit counted")
	var status:Node = EFFECTS.current(target,"wither")
	if status != null: status.set_physics_process(false)

	# 第二发：叠加凋零 + 伤害随攻击力
	actor.bolt_cooldown_left = 0.0
	actor.Damage = 40
	check(is_equal_approx(actor.bolt_damage(),10.0),"bolt damage scales with live attack (40 -> 10)")
	actor.Damage = 20
	actor.step_mob(0.01)
	check(actor.bolts_fired == 2,"second bolt fired")
	for f:int in range(360):
		await physics_frame
		if bolts().is_empty(): break
	check(target.health == 9990 and EFFECTS.level_of(target,"wither") == 2,"second bolt: 5 more damage and Wither stacks to II")
	target.free()
	EFFECTS.clear(actor,"wither")

	# --- 抛物线：无目标弹体 = 恒定拉力，二阶差分恒定；先后退再向前；巡航 120 ---
	var free_bolt:Node2D = actor.fire_bolt(Vector2.RIGHT,null)
	var origin:Vector2 = free_bolt.global_position
	var track:Array[Vector2] = [origin]
	var cruise_frame:int = -1
	for f:int in range(90):
		await physics_frame
		if not is_instance_valid(free_bolt) or free_bolt.finished: break
		track.append(free_bolt.global_position)
		if cruise_frame < 0 and free_bolt.cruising: cruise_frame = f
	var dt:float = 1.0/float(Engine.physics_ticks_per_second)
	var min_along:float = INF
	for point:Vector2 in track: min_along = minf(min_along,(point-origin).x)
	var expected_back:float = pow(100.0*cos(deg_to_rad(40.0)),2.0)/(2.0*240.0)
	print("WS_BOLT_METRIC arc back=",-min_along," expected~",expected_back," cruise_frame=",cruise_frame," first_steps=",track.slice(0,4))
	check((track[1]-origin).x < 0.0 and (track[1]-origin).y < 0.0,"first motion is backward and up")
	check(absf(-min_along-expected_back) < 2.5,"backs off about " + str(snappedf(expected_back,0.1)) + " before swinging forward (" + str(snappedf(-min_along,0.1)) + ")")
	var parabola_ok:bool = true
	var arc_end:int = mini(cruise_frame,track.size()-2) if cruise_frame > 2 else 0
	for i:int in range(1,arc_end):
		var accel:Vector2 = (track[i+1]-2.0*track[i]+track[i-1])/(dt*dt)
		parabola_ok = parabola_ok and accel.distance_to(Vector2(240.0,0.0)) < 1.0
	check(arc_end > 20 and parabola_ok,"arc is a true parabola: constant pull along the aim until cruise")
	check(is_instance_valid(free_bolt) and free_bolt.cruising and is_equal_approx(free_bolt.velocity.length(),120.0) and free_bolt.velocity.x > 0.0,"then cruises forward at 120")
	check(track[track.size()-1].x > origin.x+40.0,"ends up well in front of the head")
	# 持续发射：巡航中弹体周围始终有新粒子
	var alive_body:int = 0
	for p:Node in get_nodes_in_group(BOLT.BODY_GROUP):
		if (p._start as Vector2).distance_to(free_bolt.global_position) < BOLT.BODY_RADIUS+30.0: alive_body += 1
	check(alive_body >= 8,"body keeps emitting particles around the bolt while flying (" + str(alive_body) + ")")
	clear_bolts()

	# --- 小幅追踪 ---
	var mover:Node2D = make_target("Mover",actor.global_position+Vector2(300,0),true)
	await physics_frame
	var homing:Node2D = actor.fire_bolt(Vector2.RIGHT.rotated(deg_to_rad(-25.0)),mover)
	var h0:Vector2 = Vector2.RIGHT.rotated(deg_to_rad(-25.0))
	var turned:float = absf(h0.angle_to(homing.turn_toward_target(h0,0.1)))
	check(turned > 0.0 and turned <= actor.BOLT_TURN_RATE*0.1+0.0001,"homing turns toward target at most 1.4 rad/s (" + str(turned) + " rad in 0.1 s)")
	var start_health:float = mover.health
	for f:int in range(360):
		await physics_frame
		if not is_instance_valid(homing) or homing.finished: break
	check(mover.health == start_health-5.0,"slight homing corrects a 25 degree miss onto a target 300 px away")
	clear_bolts()

	# --- 暂停：弹体不动 ---
	var paused_bolt:Node2D = actor.fire_bolt(Vector2.RIGHT,null)
	await physics_frame
	var paused_at:Vector2 = paused_bolt.global_position
	root.get_node("Game").now_stop_state = true
	var paused_count:int = get_nodes_in_group(BOLT.BODY_GROUP).size()
	for f:int in range(10): await physics_frame
	check(paused_bolt.global_position.is_equal_approx(paused_at),"bolt freezes while the battle is paused")
	check(get_nodes_in_group(BOLT.BODY_GROUP).size() == paused_count,"no new body particles (and none fade) while paused")
	root.get_node("Game").now_stop_state = false
	clear_bolts()

	# --- 发射者死亡：弹体散掉 ---
	var orphan:Node2D = actor.fire_bolt(Vector2.RIGHT,null)
	actor.health = 0
	await physics_frame
	await physics_frame
	check(not is_instance_valid(orphan) or orphan.finished,"bolt dissipates when its source dies")
	print("WS_BOLT_RESULT checks=",checks," failures=",failures)
	quit(1 if failures > 0 else 0)
