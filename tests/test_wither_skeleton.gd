extends SceneTree
var EFFECTS:Script
var checks:int = 0
var failures:int = 0
var arena:Node2D
var actor:Node2D
var victim:Node2D
func _initialize() -> void: call_deferred("run")
func check(value:bool,label:String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("WITHER_SKELETON_FAIL: "+label)
func make_target(label:String,point:Vector2,team:String = "B") -> Node2D:
	var target:Node2D = load("res://scenes/ball.tscn").instantiate()
	target.name = label
	target.Team = team
	target.Max_health = 10000
	target.Has_Collision_Damage = false
	target.position = point
	target.get_node("CharacterAutoFit").enabled = false
	var shape:=CircleShape2D.new()
	shape.radius = 9.0
	target.get_node("hurtbox/CollisionShape2D").shape = shape
	target.get_node("CollisionShape2D").disabled = true
	target.get_node("hitbox/CollisionShape2D").disabled = true
	arena.add_child(target,true)
	target.set_physics_process(false)
	target.state_machine.set_physics_process(false)
	target.set_process(false)
	target.health = 10000
	target.block = 0
	return target
func reset_target(target:Node2D) -> void:
	EFFECTS.clear(target,"wither")
	target.health = 10000
	target.block = 0
func fresh() -> void:
	actor.cancel_combo()
	actor.cooldown_left = 0.0
	actor.Can_Attack = true
	actor.dizziness = false
	actor._damage_output_disabled_until_msec = 0
func run() -> void:
	EFFECTS = load("res://scripts/effects/我的世界/mc_status_effects.gd")
	create_timer(50.0,true,false,true).timeout.connect(func(): quit(2))
	root.get_node("Game").now_stop_state = false
	root.size = Vector2i(800,600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	arena = Node2D.new()
	arena.name = "WitherSkeletonTest"
	root.add_child(arena)
	current_scene = arena
	var background:=ColorRect.new()
	background.size = Vector2(800,600)
	background.color = Color("35434b")
	background.z_index = -10
	arena.add_child(background)
	actor = load("res://scenes/characters/我的世界/凋灵骷髅.tscn").instantiate()
	actor.name = "WitherSkeleton"
	actor.Team = "A"
	actor.position = Vector2(340,270)
	arena.add_child(actor)
	actor.set_physics_process(false)
	actor.state_machine.set_physics_process(false)
	actor.set_process(false)
	actor.voice.set_physics_process(false)
	await process_frame
	check(actor.Max_health == 700 and actor.Damage == 20 and actor.Speed == 88.0,"baseline attributes (2026-09-29: 700 HP, 20 melee)")
	check(is_equal_approx(actor.blade_length,18.0) and is_equal_approx(actor.blade_radius,2.25) and is_equal_approx(actor.ATTACK_HAND_REACH,4.5) and is_equal_approx(actor.acquisition_range,52.2),"whole character x0.9: 18 length / 2.25 radius / 4.5 reach / 52.2 melee range")
	check(actor.player_control_action_ids() == [&"controlled_attack_action",&"controlled_skill_action"],"left mouse slashes, right mouse head bolt")
	check(not actor.Has_Collision_Damage and not actor.Can_Skill,"no hidden collision or extra skill")
	check(actor.FRAMES.get_frame_count(&"attack") == 50,"full raised-arm downcut/upcut original-model clip")
	check(is_equal_approx(actor.image.scale.x,actor.BODY_SCALE) and is_equal_approx(actor.image.position.y,actor.BODY_OFFSET_Y),"body and image offset use the approved enlargement")
	var body_shape:RectangleShape2D = actor.get_node("CollisionShape2D").shape
	check(body_shape.size.is_equal_approx(Vector2(40,126)*actor.BODY_ENLARGEMENT*actor.SIZE_SCALE),"body collider matches the x0.9 visual")
	var hurt_shape:RectangleShape2D = actor.get_node("hurtbox/CollisionShape2D").shape
	check(hurt_shape.size.is_equal_approx(Vector2(38,122)*actor.BODY_ENLARGEMENT*actor.SIZE_SCALE),"hurt shape scaled by the same ratio")
	check(is_equal_approx(actor.SIZE_SCALE,0.9) and is_equal_approx(actor.image.global_scale.x,0.17*20.0/14.0*0.9),"body = previous 20/14 enlargement x0.9")
	check(actor.global_scale.is_equal_approx(Vector2.ONE*0.2),"root scale stays fixed: sword and locomotion are not scaled again")
	var foot_y:float = (actor.image.global_transform*Vector2(0,90)).y
	var collider_bottom:float = actor.collision_shape_2d.global_position.y+body_shape.size.y*actor.collision_shape_2d.global_scale.y*0.5
	check(absf(foot_y-collider_bottom)<0.01,"enlarged body's feet align with physical collider bottom")
	# Inspect the actual sprite tip and original texture hand anchor, not just angle metadata.
	var saved_direction:Vector2 = actor.direction
	for facing:Vector2 in [Vector2.RIGHT,Vector2.LEFT]:
		actor.direction = facing
		for walking:bool in [false,true]:
			actor._walking = walking
			for stamp:float in [0.0,0.25,0.5]:
				actor._view_clock = stamp
				actor.visual_mob()
				var tip:Vector2 = actor._sword.global_transform*Vector2(10.5,-10.5)
				var grip:Vector2 = actor._sword.global_position
				var diagonal:Vector2 = (tip-grip).normalized()
				check(is_equal_approx(absf(diagonal.x),sqrt(0.5)) and is_equal_approx(diagonal.y,-sqrt(0.5)) and is_equal_approx(grip.distance_to(tip),18.0),"idle/walking sword points diagonally 45deg up-forward, 18-unit length (x0.9), both facings")
				check(diagonal.x*(1.0 if actor._face_right else -1.0)>0.7 and absf(diagonal.x)>0.7,"diagonal held sword leans outward from each facing and is never vertical")
				var xy:Array = actor.POSES.HANDS[str(actor._body_clip)][actor._body_frame]
				var hand:Vector2 = Vector2(float(xy[0])-80.0,float(xy[1])-112.0)+actor.image.offset
				if actor._face_right: hand.x = -hand.x
				check((actor.image.global_transform*hand).distance_to(grip)<0.01,"diagonal held sword stays attached to enlarged original hand")
				check(tip.distance_to(actor.blade_segment(-1.0).end)<0.01,"diagonal render tip and geometry endpoint agree")
				check(actor.get_debug_attack_regions().is_empty() and not actor._arm.visible,"idle/walk diagonal pose adds no damage or duplicate arm")
	actor._walking = false
	actor._view_clock = 0.0
	actor.direction = saved_direction
	actor.visual_mob()
	check(actor.SOUNDS.EVENTS.size() == 4,"all four original creature audio categories")
	actor.begin_combo(Vector2.RIGHT)
	actor.visual_mob()
	var geometry:Dictionary = actor.blade_segment(0.23)
	var point:Vector2 = geometry.start.lerp(geometry.end,0.55)
	victim = make_target("Enemy",point)
	var friend:Node2D = make_target("Friend",point,"A")
	var behind:Node2D = make_target("Behind",actor.global_position+Vector2(-150,0))
	await physics_frame
	await physics_frame
	actor.advance_combo(0.31)
	check(victim.health == 9980,"first actual swept slash inflicts exactly 20")
	check(EFFECTS.level_of(victim,"wither") == 1,"first hit adds Wither I")
	check(friend.health == 10000 and behind.health == 10000,"no friend or rear phantom hit")
	check(not actor.get_debug_attack_regions().is_empty(),"actual sampled blade geometry exposed")
	var status:Node = EFFECTS.current(victim,"wither")
	if status != null: status.set_physics_process(false)
	actor.advance_combo(0.01)
	check(victim.health == 9980,"one target at most once within one slash")
	# Place at second slash's actual swept hand+blade, never mouse location.
	geometry = actor.blade_segment(0.49)
	victim.global_position = geometry.start.lerp(geometry.end,0.55)
	await physics_frame
	actor.advance_combo(0.25)
	check(victim.health == 9960,"second slash inflicts a separate 20")
	check(EFFECTS.level_of(victim,"wither") == 2,"two hits from zero produce Wither II")
	status = EFFECTS.current(victim,"wither")
	check(status != null and is_equal_approx(status.remaining,3.0),"second hit refreshes duration to 3 seconds")
	actor.advance_combo(0.25)
	check(actor.combo_time >= 0.0 and actor.swings_started == 2,"two swings landed, recover transition still playing")
	check(absf(wrapf(actor.blade_angle(actor.RECOVER_END-0.001)-actor.rest_angle(),-PI,PI)) < 0.06,"blade eases back toward the rest angle")
	actor.advance_combo(0.45)
	check(actor.combo_time < 0.0,"combo closes only after the recover transition")
	check(actor.get_debug_attack_regions().is_empty(),"no damage threat after completion")
	check(not actor.begin_combo(Vector2.RIGHT),"cooldown rejects spam")
	fresh()
	reset_target(victim)
	var other:Node2D = make_target("OtherSource",Vector2(650,400),"A")
	EFFECTS.apply_effect(victim,"wither",4,9.0,other)
	check(actor.apply_stacking_wither(victim),"existing external Wither can be upgraded")
	check(EFFECTS.level_of(victim,"wither") == 5,"current external level IV becomes V")
	status = EFFECTS.current(victim,"wither")
	status.set_physics_process(false)
	check(is_equal_approx(status.applications[other.get_instance_id()].time,9.0),"external source lifetime not erased")
	status._physics_process(3.0)
	check(EFFECTS.level_of(victim,"wither") == 4,"after 3 seconds original IV source remains")
	EFFECTS.clear(victim,"wither")
	EFFECTS.apply_effect(victim,"wither",255,3.0,actor)
	actor.apply_stacking_wither(victim)
	check(EFFECTS.level_of(victim,"wither") == 255,"shared 255-level ceiling")
	reset_target(victim)
	victim.minecraft_potion_negative_effect_ratio = 0.0
	check(actor.deal_sword_hit(victim,victim.global_position),"negative-status immunity does not block ordinary sword damage")
	check(EFFECTS.level_of(victim,"wither") == 0,"negative-status immunity prevents Wither")
	victim.minecraft_potion_negative_effect_ratio = 1.0
	reset_target(victim)
	actor.Damage = 48
	actor.deal_sword_hit(victim,victim.global_position)
	check(victim.health == 9952,"current attack attribute changes real damage")
	actor.Damage = 20
	reset_target(victim)
	victim.Damage_reduction = 1.0
	check(not actor.deal_sword_hit(victim,victim.global_position),"zero effective damage does not apply status")
	check(EFFECTS.level_of(victim,"wither") == 0,"no status on rejected damage")
	victim.Damage_reduction = 0.0
	fresh()
	actor.begin_combo(Vector2.RIGHT)
	root.get_node("Game").now_stop_state = true
	var frozen:float = actor.combo_time
	actor.advance_combo(5.0)
	check(actor.combo_time == frozen,"pause freezes combo and cannot deal catch-up hits")
	root.get_node("Game").now_stop_state = false
	actor.dizziness = true
	actor.advance_combo(0.1)
	check(actor.combo_time < 0.0,"stun cancels pending slashes")
	fresh()
	actor.begin_combo(Vector2.RIGHT)
	actor.apply_damage_disable(2.0)
	actor.advance_combo(0.2)
	check(actor.combo_time < 0.0,"damage disable cancels pending slashes")
	fresh()
	actor.set_player_control_peer(1)
	actor.set_player_control_aim_position(actor.global_position+Vector2.LEFT*120.0)
	actor.player_control_action(0)
	check(actor.combo_time >= 0.0 and actor.combo_heading.is_equal_approx(Vector2.LEFT),"manual left click uses mouse aim")
	var serial:int = actor._revision
	actor.player_control_action(1)
	actor.player_control_action(2)
	check(actor._revision == serial,"empty right and middle buttons do nothing")
	fresh()
	actor.step_mob(1.5)
	check(actor.combo_time < 0.0,"AI cannot start attacks while manually controlled")
	actor.set_player_control_peer(0)
	fresh()
	# Reliable duplicate status packets cannot amplify a stack on clients.
	actor._receive_wither(500,arena.get_path_to(victim),7,1.5)
	actor._receive_wither(500,arena.get_path_to(victim),8,3.0)
	check(EFFECTS.level_of(victim,"wither") == 7,"duplicate reliable packet does not raise Wither twice")
	actor.accept_visual({"revision":10,"time":10.0,"combo":-1.0})
	actor.accept_visual({"revision":9,"time":11.0,"combo":0.1})
	check(actor.combo_time < 0.0,"old visual packets cannot revive cancelled combo")
	check(actor.get_armor_test_effect_summary().contains("3"),"armor-test explanation supplied")
	# Real GPU frames and safe native audio playback, not only property assertions.
	await process_frame
	check(actor.voice.played.get("swing",0) == 2,"two original sweep audio events")
	actor.voice._previous = actor.global_position
	actor.voice._physics_process(0.4)
	check(actor.voice.played.get("step",0) == 0,"stationary unit never steps")
	actor.global_position.x += 2.0
	actor.voice._physics_process(0.4)
	check(actor.voice.played.get("step",0) == 1,"real displacement emits native footstep")
	actor.voice._physics_process(0.001)
	check(actor.voice.played.get("step",0) == 1,"same step stream never immediately overlaps")
	if DisplayServer.get_name() != "headless":
		var images:Array[Image] = []
		for t:float in [-1.0,0.22,0.49,0.86]:
			actor.combo_time = t
			actor.combo_heading = Vector2.RIGHT
			actor.visual_mob()
			await process_frame
			await RenderingServer.frame_post_draw
			var im:Image = root.get_texture().get_image()
			images.append(im)
			im.save_png("res://tests/wither_skeleton_swing_gpu_%s.png" % str(t).replace(".","_"))
		check(images[0].get_data() != images[1].get_data() and images[1].get_data() != images[2].get_data() and images[2].get_data() != images[3].get_data(),"GPU idle, both slashes and recover differ")
	actor.combo_time = -1.0
	actor.voice.request("death",actor.global_position)
	actor.voice.request("death",actor.global_position)
	check(actor.voice.played.get("death",0) == 1,"one native death cue only")
	fresh()
	victim.global_position = actor.global_position+Vector2(-500,-500)
	var ai_foe:Node2D = make_target("AIFoe",actor.global_position+Vector2(24,0))
	await physics_frame
	actor.direction = Vector2.UP
	actor.step_mob(0.02)
	check(actor.direction.is_equal_approx(Vector2.UP),"acquisition does not steer movement toward enemy")
	check(actor.combo_time >= 0.0 and actor.combo_heading.is_equal_approx(Vector2.RIGHT),"AI starts the two-slash combo when an enemy is in range")
	actor.cancel_combo()
	actor.cooldown_left = 0.0
	# Measure real public movement, not a multiplier-only assertion.
	var origin:Vector2 = actor.global_position
	actor.global_position = Vector2(600,500)
	actor.direction = Vector2.LEFT
	actor.Repel = Vector2.ZERO
	actor.move(actor.Speed,1.0/60.0)
	var normal_velocity:Vector2 = actor.velocity
	actor.begin_combo(Vector2.RIGHT)
	actor.move(actor.Speed,1.0/60.0)
	check(actor.velocity.is_equal_approx(normal_velocity*actor.ATTACK_MOVE_MULTIPLIER),"attack slows ordinary movement to 30 percent without turning")
	check(actor.direction.is_equal_approx(Vector2.LEFT),"aiming right preserves leftward movement")
	actor.direction = Vector2.UP # Public collision response remains free to redirect.
	actor.step_mob(0.01)
	check(actor.direction.is_equal_approx(Vector2.UP),"combo does not restore a cached pre-bounce direction")
	actor.advance_combo(actor.RECOVER_END)
	check(actor.combo_time < 0.0,"natural recovery completes before restoring speed")
	actor.move(actor.Speed,1.0/60.0)
	check(is_equal_approx(actor.velocity.length(),normal_velocity.length()),"completed recovery restores ordinary movement speed")
	actor.cooldown_left = 0.0
	actor.set_player_control_peer(1)
	actor.player_control_direction = Vector2.DOWN
	actor.begin_combo(Vector2.RIGHT)
	actor.move(actor.Speed,1.0/60.0)
	check(actor.velocity.y > 0.0 and absf(actor.velocity.x) < 0.001 and is_equal_approx(actor.velocity.length(),normal_velocity.length()*0.3),"manual attack slows WASD without replacing it with aim")
	actor.Repel = Vector2(12,0)
	actor.move(actor.Speed,1.0/60.0)
	check(is_equal_approx(actor.velocity.x,12.0),"attack slowdown does not scale external knockback")
	actor.Repel = Vector2.ZERO
	actor.set_player_control_peer(0)
	actor.cancel_combo()
	actor.global_position = origin
	actor.cooldown_left = 1.0
	actor.direction = Vector2.LEFT
	actor.step_mob(0.02)
	check(actor.direction.is_equal_approx(Vector2.LEFT),"cooldown and enemy nearby never steer locomotion")
	# Both facings: hand and sword go high -> low -> high, not two downward cuts.
	for facing:Vector2 in [Vector2.RIGHT,Vector2.LEFT]:
		fresh()
		actor.begin_combo(facing)
		actor.visual_mob()
		var high:Dictionary = actor.blade_segment(0.15)
		var low:Dictionary = actor.blade_segment(0.31)
		var up:Dictionary = actor.blade_segment(0.57)
		check(low.start.y-high.start.y > 10.0,"large real arm travel during downward cut")
		check(low.end.y-high.end.y > 25.0 and low.end.y-up.end.y > 25.0,"mirrored sword tip makes a broad downcut then upcut")
		check(actor.body_pose(0.86).clip == &"attack","body and hand share recovery clip")
		for t:float in [0.0,0.15,0.31,0.41,0.57,0.74,0.98]:
			actor.combo_time = t
			actor.visual_mob()
			check(actor._sword.global_position.is_equal_approx(actor.hand_position(t)),"visible grip equals damage grip")
		fresh()
	var wall:=StaticBody2D.new()
	var wall_shape:=RectangleShape2D.new()
	wall_shape.size = Vector2(8,240)
	var wall_col:=CollisionShape2D.new()
	wall_col.shape = wall_shape
	wall.add_child(wall_col)
	wall.position = actor.global_position+Vector2(20,0)
	arena.add_child(wall)
	await physics_frame
	fresh()
	actor.begin_combo(Vector2.RIGHT)
	actor.advance_combo(0.75)
	check(ai_foe.health == 10000,"a wall between attacker and target blocks both slashes")
	# Exercise an actual StaticBody2D contact during a slowed attack.
	fresh()
	actor.global_position = wall.global_position-Vector2(12,0)
	actor.direction = Vector2.RIGHT
	actor.begin_combo(Vector2.RIGHT)
	var bounced:bool = false
	for i:int in range(50):
		await physics_frame
		actor.move(actor.Speed,1.0/60.0)
		actor.step_mob(1.0/60.0)
		if actor.direction.x < -0.5:
			bounced = true
			break
	check(bounced,"real wall contact keeps ordinary reflection during slowed attack")
	var reflected:Vector2 = actor.direction
	actor.step_mob(0.02)
	check(actor.direction.is_equal_approx(reflected),"enemy aim cannot undo real wall reflection")
	wall.queue_free()
	await process_frame
	# Full-circle AIM, not a full-circle damage pulse. Body remains upright.
	actor.global_position = Vector2(400,350)
	ai_foe.global_position = Vector2(2000,2000)
	behind.global_position = Vector2(-2000,-2000)
	for i:int in range(8):
		var aim:Vector2 = Vector2.RIGHT.rotated(float(i)*TAU/8.0)
		fresh()
		reset_target(victim)
		victim.global_position = actor.global_position+aim*(14.0*actor.BODY_ENLARGEMENT)
		await physics_frame
		actor.direction = Vector2(0.6,0.8)
		actor.step_mob(0.01)
		check(actor.combo_time >= 0.0 and actor.combo_heading.is_equal_approx(aim),"AI acquires enemy in each of eight directions")
		check(actor.direction.is_equal_approx(Vector2(0.6,0.8)),"360 aiming never steers locomotion")
		check(is_equal_approx(actor.attack_hand_extension(0.23),4.5) and is_zero_approx(actor.attack_hand_extension(0.0)) and is_zero_approx(actor.attack_hand_extension(actor.RECOVER_END)),"reach eases out from idle and resets after recovery")
		actor.combo_time = 0.23
		actor.visual_mob()
		var pivot:Vector2 = actor.shoulder_position(0.23)
		var raw_hand:Vector2 = actor._hand_pixel(actor.POSES.HANDS["attack"][actor._attack_index(0.23)])
		var expected_hand:Vector2 = pivot+(raw_hand-pivot).rotated(actor.arm_aim_rotation(0.23))+aim*actor.ATTACK_HAND_REACH
		check(actor.hand_position(0.23).is_equal_approx(expected_hand),"real hand extends forward from original shoulder in every direction")
		var hand_pixel:Array = actor.POSES.HANDS["attack"][actor._body_frame]
		var local_hand:Vector2 = Vector2(float(hand_pixel[0])-80.0,float(hand_pixel[1])-112.0)+actor._arm.offset
		check((actor._arm.global_transform*local_hand).distance_to(actor._sword.global_position)<0.01,"rendered aimed arm ends at sword grip")
		check((actor._sword.global_transform*Vector2(10.5,-10.5)).distance_to(actor.blade_segment(0.23).end)<0.01,"visible extended sword tip equals real damage geometry")
		check(is_equal_approx(actor.blade_segment(0.23).radius,2.25),"widened threat and actual sweep share 2.25 radius (x0.9)")
		check(is_zero_approx(actor.image.rotation),"aim rotates arm not torso/legs")
		check(actor._arm.global_position.distance_to(pivot)<0.01,"extra reach leaves shoulder joined to body")
		var raw_vector:Vector2 = raw_hand-pivot
		var normal_world:Vector2 = raw_vector.normalized().orthogonal()
		var base:Transform2D = actor.image.global_transform
		if actor._face_right: base.x = -base.x
		# The enlarged sprite has a non-unit scale; use the full affine inverse, not the orthonormal-only shortcut.
		var pixel_width:Vector2 = base.affine_inverse().basis_xform(normal_world)
		check(is_equal_approx(actor._arm.global_transform.basis_xform(pixel_width).length(),1.0),"extension preserves arm thickness instead of scaling whole character")
		actor.combo_time = 0.0
		actor.advance_combo(0.74)
		check(victim.health == 9960,"actual two slashes hit enemy in each of eight directions")
		var side:float = 1.0 if actor._face_right else -1.0
		var previous_angle:float = actor.blade_angle(actor.COMBO_DURATION)
		var start_angle:float = previous_angle
		var same_direction:bool = true
		for sample:int in range(1,61):
			var angle:float = actor.blade_angle(lerpf(actor.COMBO_DURATION,actor.RECOVER_END,float(sample)/60.0))
			if (angle-previous_angle)*side > 0.00001: same_direction = false
			previous_angle = angle
		check(same_direction and (start_angle-previous_angle)*side >= TAU-0.001,"recovery turns at least one full revolution in upcut direction")
		var turns:Array[float] = []
		var angle_before:float = start_angle
		for quarter:int in range(1,5):
			var angle_now:float = actor.blade_angle(lerpf(actor.COMBO_DURATION,actor.RECOVER_END,float(quarter)/4.0))
			turns.append(absf(angle_now-angle_before))
			angle_before = angle_now
		check(turns[0]>turns[1] and turns[1]>turns[2] and turns[2]>turns[3] and turns[0]>4.0*turns[3],"spin starts fastest and continuously decelerates toward rest")
		check(absf(wrapf(previous_angle-actor.rest_angle(),-PI,PI))<0.001,"unwrapped full spin ends at resting blade angle")
		# Same sine easing/time. Diagonal rest still aligns after one full revolution;
		# <720deg total travel implies <43deg/tick at 60Hz/0.44s.
		var max_step:float = 0.0
		var before_angle:float = actor.blade_angle(actor.COMBO_DURATION)
		var before_hand:Vector2 = actor.hand_position(actor.COMBO_DURATION)
		var max_hand_step:float = 0.0
		var texture_index:int = actor._arm_source_index(actor.COMBO_DURATION)
		var one_texture:bool = true
		var anchors_match:bool = true
		for frame:int in range(1,55):
			var t:float = minf(actor.COMBO_DURATION+float(frame)/120.0,actor.RECOVER_END)
			var angle:float = actor.blade_angle(t)
			var hand:Vector2 = actor.hand_position(t)
			max_hand_step = maxf(max_hand_step,hand.distance_to(before_hand))
			before_hand = hand
			actor.combo_time = t
			actor.visual_mob()
			one_texture = one_texture and actor._arm_source_index(t) == texture_index
			var xy:Array = actor.POSES.HANDS["attack"][texture_index]
			var pixel:Vector2 = Vector2(float(xy[0])-80.0,float(xy[1])-112.0)+actor._arm.offset
			if t < actor.RECOVER_END:
				anchors_match = anchors_match and (actor._arm.global_transform*pixel).distance_to(actor._sword.global_position)<0.01
			if frame%2 == 0:
				max_step = maxf(max_step,absf(angle-before_angle))
				before_angle = angle
		var total_turn:float = absf(actor.blade_angle(actor.RECOVER_END)-start_angle)
		var peak_step:float = total_turn*PI*0.5/((actor.RECOVER_END-actor.COMBO_DURATION)*60.0)
		check(max_step <= peak_step+0.00001 and max_step < deg_to_rad(43.0),"diagonal recovery stays inside continuous sine angular-step bound at 60Hz")
		check(max_hand_step/actor.BODY_ENLARGEMENT < 1.0 and one_texture,"body-relative recovery wrist continuity preserved without swapping arm textures")
		print("WITHER_SKELETON_BODY_RECOVERY direction=%d max_degrees=%f hand_step=%f body_relative=%f" % [i,rad_to_deg(max_step),max_hand_step,max_hand_step/actor.BODY_ENLARGEMENT])
		check(anchors_match,"continuous recovery texture still joins the visible sword grip")
		check(actor.hand_position(actor.RECOVER_END).distance_to(actor._rest_hand())<0.001,"recovery reaches actual held hand without a final snap")
		actor.combo_time = actor.COMBO_DURATION
		var health_before_spin:int = victim.health
		actor.advance_combo((actor.RECOVER_END-actor.COMBO_DURATION)*0.5)
		check(actor.get_debug_attack_regions().is_empty() and actor.get_debug_detection_regions().is_empty(),"recovery spin is not a third damage or detection sweep")
		actor.advance_combo((actor.RECOVER_END-actor.COMBO_DURATION)*0.5+0.00001)
		check(victim.health == health_before_spin,"full recovery turn cannot deal extra damage")
		actor.visual_mob()
		check(not actor._arm.visible,"separate attack arm hides after recovery")
	# Compare legacy 14/3/2 weapon settings on the SAME current body: preserve the sword range buff.
	var original_hurt_shape:Shape2D = victim.get_node("hurtbox/CollisionShape2D").shape
	var narrow_shape:=CircleShape2D.new()
	narrow_shape.radius = 0.5
	victim.get_node("hurtbox/CollisionShape2D").shape = narrow_shape
	for i:int in range(8):
		var aim:Vector2 = Vector2.RIGHT.rotated(float(i)*TAU/8.0)
		fresh()
		reset_target(victim)
		actor.begin_combo(aim)
		var old_segments:Array[Dictionary] = []
		var farthest:Vector2 = actor.global_position
		var far_projection:float = -INF
		for window:Vector2 in actor.WINDOWS:
			for j:int in range(25):
				var sample:float = lerpf(window.x,window.y,float(j)/24.0)
				var segment:Dictionary = actor.blade_segment(sample)
				if segment.end.dot(aim)>far_projection:
					far_projection = segment.end.dot(aim)
					farthest = segment.end
				var sword_heading:Vector2 = (segment.end-segment.start).normalized()
				old_segments.append({"start":segment.start-aim*2.0,"end":segment.end-aim*2.0-sword_heading*6.0})
		victim.global_position = farthest+aim
		await physics_frame
		var old_hits:int = 0
		for segment:Dictionary in old_segments:
			for contact:Dictionary in actor.SWEEP.contacts(actor,segment.start,segment.end,2.0,{},actor.global_position):
				if contact.target == victim: old_hits += 1
		check(old_hits == 0,"extension target lies outside both old sword sweep envelopes")
		actor.advance_combo(0.74)
		check(victim.health < 10000,"extended physical sword actually damages newly reachable target")
	victim.get_node("hurtbox/CollisionShape2D").shape = original_hurt_shape
	# AI gate uses current real hurt shapes, not the much larger discovery circle.
	victim.global_position = Vector2(2000,-2000)
	ai_foe.global_position = Vector2(-2000,2000)
	var gate_foe:Node2D = make_target("RangeGate",actor.global_position+Vector2.RIGHT*50.0)
	await physics_frame
	for i:int in range(8):
		var aim:Vector2 = Vector2.RIGHT.rotated(float(i)*TAU/8.0)
		fresh()
		gate_foe.global_position = actor.global_position+aim*50.0
		await physics_frame
		actor.direction = Vector2(0.6,0.8)
		var old_heading:Vector2 = actor.combo_heading
		var old_face:bool = actor._face_right
		var old_revision:int = actor._revision
		var old_swings:int = actor.swings_started
		check(not actor.can_reach_target(gate_foe),"inside discovery circle but outside real two-slash reach is rejected")
		check(actor.combo_time < 0.0 and actor.cooldown_left == 0.0 and actor.combo_heading == old_heading and actor._face_right == old_face and actor._revision == old_revision and actor.swings_started == old_swings,"range preview has no pose/cooldown/audio/state side effects")
		actor.step_mob(0.01)
		check(actor.combo_time < 0.0 and actor.direction.is_equal_approx(Vector2(0.6,0.8)),"AI does not empty-swing or chase an unreachable enemy")
		actor.Attack()
		check(actor.combo_time < 0.0,"alternate AI Attack entry respects same range gate")
		gate_foe.global_position = actor.global_position+aim*24.0
		await physics_frame
		check(actor.can_reach_target(gate_foe),"reachable opponent accepted in each of eight directions")
		var preview:Dictionary = actor.blade_segment(0.23,aim)
		actor.step_mob(0.01)
		check(actor.combo_time >= 0.0 and actor.combo_heading.is_equal_approx(aim),"AI starts when enemy enters actual swept reach")
		var live:Dictionary = actor.blade_segment(0.23)
		check(preview.start.distance_to(live.start)<0.001 and preview.end.distance_to(live.end)<0.001,"candidate preview equals actual locked attack geometry")
		actor.advance_combo(0.74)
		check(gate_foe.health < 10000,"AI-admitted static target receives actual sword damage")
		reset_target(gate_foe)
	fresh()
	gate_foe.global_position = actor.global_position+Vector2.RIGHT*24.0
	var gate_wall:=StaticBody2D.new()
	var gate_wall_shape:=RectangleShape2D.new()
	gate_wall_shape.size = Vector2(4,100)
	var gate_wall_collision:=CollisionShape2D.new()
	gate_wall_collision.shape = gate_wall_shape
	gate_wall.add_child(gate_wall_collision)
	gate_wall.global_position = actor.global_position+Vector2.RIGHT*12.0
	arena.add_child(gate_wall)
	await physics_frame
	check(not actor.can_reach_target(gate_foe),"wall blocks reachable-target preview")
	actor.step_mob(0.01)
	check(actor.combo_time < 0.0,"AI does not start a sword combo through a wall")
	gate_wall.queue_free()
	await process_frame
	fresh()
	actor.set_player_control_peer(1)
	actor.set_player_control_aim_position(actor.global_position+Vector2.RIGHT*200.0)
	actor.player_control_action(0)
	check(actor.combo_time >= 0.0,"manual click still permits intentional empty swings")
	actor.set_player_control_peer(0)
	gate_foe.queue_free()
	await process_frame
	# Actual render-subframe clock advances only harmless recovery; physics stays fixed.
	fresh()
	actor.begin_combo(Vector2.RIGHT)
	check(is_equal_approx(actor.cooldown_left,1.2),"longer recovery does not extend original attack interval")
	actor.combo_time = 0.8
	actor._render_process = true
	var draw_a:float = actor._draw_combo_time(0.0)
	var draw_b:float = actor._draw_combo_time(0.5)
	var draw_c:float = actor._draw_combo_time(0.9)
	check(draw_a<draw_b and draw_b<draw_c and is_equal_approx(actor.combo_time,0.8),"high-refresh display advances between unchanged physics ticks")
	root.get_node("Game").now_stop_state = true
	check(is_equal_approx(actor._draw_combo_time(1.0),draw_c),"pause freezes the last displayed spin without rewinding")
	root.get_node("Game").now_stop_state = false
	actor.combo_time = 0.79
	check(actor._draw_combo_time(0.0)>=draw_c,"late visual snapshot cannot reverse the recovery spin")
	actor.combo_time = 0.23
	check(is_equal_approx(actor._draw_combo_time(0.9),0.23),"render interpolation never advances an active damaging slash")
	actor._render_process = false
	# Manual vertical aim follows the same real shoulder geometry.
	fresh()
	actor.set_player_control_peer(1)
	actor.set_player_control_aim_position(actor.global_position+Vector2.UP*100)
	actor.player_control_action(0)
	actor.combo_time = 0.23
	actor.visual_mob()
	check(actor.combo_heading.is_equal_approx(Vector2.UP) and absf(actor.arm_aim_rotation(0.23))>1.5,"manual overhead aim turns arm with sword")
	actor.set_player_control_peer(0)
	actor.queue_free()
	victim.queue_free()
	friend.queue_free()
	behind.queue_free()
	other.queue_free()
	ai_foe.queue_free()
	await process_frame
	await create_timer(1.5).timeout
	print("WITHER_SKELETON_RESULT checks=%d failures=%d renderer=%s" % [checks,failures,DisplayServer.get_name()])
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
