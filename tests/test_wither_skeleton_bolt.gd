extends SceneTree
## 凋灵骷髅头部烟雾弹（2026-09-28）：600 血/20 近战；敌人在近战范围外才冷却（3 秒）；
## 弹体=凋灵头颅拖尾粒子的聚合团并留同款拖尾；小幅追踪；命中 5 伤 + 叠加凋零。
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
	check(actor.Max_health == 600 and actor.health == 600,"health is 600")
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
	var list:Array[Node] = bolts()
	check(list.size() == 1,"exactly one bolt in flight")
	var bolt:Node2D = list[0] if list.size() > 0 else null
	var muzzle:Vector2 = actor.bolt_muzzle_position()
	check(bolt != null and bolt.global_position.distance_to(muzzle) < 0.01,"bolt starts at the head muzzle")
	var muzzle_pixel:Vector2 = actor.image.global_transform.affine_inverse()*muzzle-actor.image.offset+Vector2(80.0,112.0)
	check(muzzle_pixel.y > 56.0 and muzzle_pixel.y < 100.0 and absf(muzzle_pixel.x-80.0) < 1.0,"muzzle lies on the head of the original sprite (pixel " + str(muzzle_pixel) + ")")
	# 弹体 = 同款拖尾粒子聚合团
	var sprites:int = 0
	var same_look:bool = true
	for child:Node in bolt.get_children():
		if child is Sprite2D:
			sprites += 1
			same_look = same_look and child.texture == BOLT.SMOKE and child.self_modulate.is_equal_approx(BOLT.TINT)
	check(sprites == BOLT.BODY_LAYOUT.size() and sprites >= 7 and same_look,"bolt body is a cluster of Wither-skull trail smoke particles")
	check(bolt.is_in_group("AI_Hazard") and bolt.get_ai_hazard_info().get("damage",0.0) == 5.0,"bolt is visible to AI dodge as 5-damage hazard")
	# 飞行途中截图
	var trail_seen:int = 0
	var shot_taken:bool = false
	var hit_frames:int = -1
	for f:int in range(150):
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
	for p:Node in get_nodes_in_group(BOLT.TRAIL_GROUP):
		trail_same = trail_same and p.texture == BOLT.SMOKE and p._pixel_width <= BOLT.TRAIL_WIDTH+0.01 and p.self_modulate.r < 0.3
	check(trail_same,"trail particles use the skull-trail texture/width")
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
	for f:int in range(150):
		await physics_frame
		if bolts().is_empty(): break
	check(target.health == 9990 and EFFECTS.level_of(target,"wither") == 2,"second bolt: 5 more damage and Wither stacks to II")
	target.free()
	EFFECTS.clear(actor,"wither")

	# --- 小幅追踪 ---
	var mover:Node2D = make_target("Mover",actor.global_position+Vector2(300,0),true)
	await physics_frame
	var homing:Node2D = actor.fire_bolt(Vector2.RIGHT.rotated(deg_to_rad(-25.0)),mover)
	var h0:Vector2 = homing.heading
	homing.steer(0.1)
	var turned:float = absf(h0.angle_to(homing.heading))
	check(turned > 0.0 and turned <= actor.BOLT_TURN_RATE*0.1+0.0001,"homing turns toward target at most 1.4 rad/s (" + str(turned) + " rad in 0.1 s)")
	homing.heading = h0
	var start_health:float = mover.health
	for f:int in range(150):
		await physics_frame
		if not is_instance_valid(homing) or homing.finished: break
	check(mover.health == start_health-5.0,"slight homing corrects a 25 degree miss onto a target 300 px away")
	# 追踪幅度小：近距离 90° 侧向目标追不上
	actor.bolt_cooldown_left = 0.0
	mover.global_position = actor.bolt_muzzle_position()+Vector2(0,60)
	await physics_frame
	EFFECTS.clear(mover,"wither") # 上一发的凋零持续伤害不能算作这一发命中
	var wide:Node2D = actor.fire_bolt(Vector2.RIGHT,mover)
	var before_wide:float = mover.health
	var min_gap:float = INF
	var wide_end:String = "life"
	for f:int in range(200):
		await physics_frame
		if not is_instance_valid(wide) or wide.finished:
			wide_end = "finished f=" + str(f)
			break
		min_gap = minf(min_gap,wide.global_position.distance_to(mover.global_position))
	print("WS_BOLT_METRIC wide start_gap=60 min_gap=",min_gap," end=",wide_end," health_delta=",before_wide-mover.health)
	check(mover.health == before_wide and min_gap > 55.0,"homing is only slight: a close target 90 degrees off is not caught")
	clear_bolts()

	# --- 暂停：弹体不动 ---
	var paused_bolt:Node2D = actor.fire_bolt(Vector2.RIGHT,null)
	await physics_frame
	var paused_at:Vector2 = paused_bolt.global_position
	root.get_node("Game").now_stop_state = true
	for f:int in range(10): await physics_frame
	check(paused_bolt.global_position.is_equal_approx(paused_at),"bolt freezes while the battle is paused")
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
