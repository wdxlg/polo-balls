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
	check(actor.Max_health == 420 and actor.Damage == 24 and actor.Speed == 88.0,"baseline attributes")
	check(actor.player_control_action_ids() == [&"controlled_attack_action"],"exactly one left mouse action")
	check(not actor.Has_Collision_Damage and not actor.Can_Skill,"no hidden collision or extra skill")
	check(actor.FRAMES.get_frame_count(&"attack") == 16,"native attack animation")
	check(is_equal_approx(actor.image.scale.x,actor.BODY_SCALE) and is_equal_approx(actor.image.position.y,actor.BODY_OFFSET_Y),"body keeps the shared humanoid footprint")
	var body_shape:RectangleShape2D = actor.get_node("CollisionShape2D").shape
	check(is_equal_approx(body_shape.size.x,40.0) and is_equal_approx(body_shape.size.y,126.0),"collider matches the slimmer visual")
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
	check(victim.health == 9976,"first actual swept slash inflicts exactly 24")
	check(EFFECTS.level_of(victim,"wither") == 1,"first hit adds Wither I")
	check(friend.health == 10000 and behind.health == 10000,"no friend or rear phantom hit")
	check(not actor.get_debug_attack_regions().is_empty(),"actual sampled blade geometry exposed")
	var status:Node = EFFECTS.current(victim,"wither")
	if status != null: status.set_physics_process(false)
	actor.advance_combo(0.01)
	check(victim.health == 9976,"one target at most once within one slash")
	# Place at second slash's actual swept hand+blade, never mouse location.
	geometry = actor.blade_segment(0.49)
	victim.global_position = geometry.start.lerp(geometry.end,0.55)
	await physics_frame
	actor.advance_combo(0.25)
	check(victim.health == 9952,"second slash inflicts a separate 24")
	check(EFFECTS.level_of(victim,"wither") == 2,"two hits from zero produce Wither II")
	status = EFFECTS.current(victim,"wither")
	check(status != null and is_equal_approx(status.remaining,3.0),"second hit refreshes duration to 3 seconds")
	actor.advance_combo(0.25)
	check(actor.combo_time >= 0.0 and actor.swings_started == 2,"two swings landed, recover transition still playing")
	check(absf(wrapf(actor.blade_angle(0.97)-actor.rest_angle(),-PI,PI)) < 0.06,"blade eases back toward the rest angle")
	actor.advance_combo(0.25)
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
	actor.Damage = 24
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
			im.save_png("res://tests/wither_skeleton_gpu_%s.png" % str(t).replace(".","_"))
		check(images[0].get_data() != images[1].get_data() and images[1].get_data() != images[2].get_data() and images[2].get_data() != images[3].get_data(),"GPU idle, both slashes and recover differ")
	actor.combo_time = -1.0
	actor.voice.request("death",actor.global_position)
	actor.voice.request("death",actor.global_position)
	check(actor.voice.played.get("death",0) == 1,"one native death cue only")
	fresh()
	victim.global_position = actor.global_position+Vector2(-500,-500)
	var ai_foe:Node2D = make_target("AIFoe",actor.global_position+Vector2(40,0))
	await physics_frame
	actor.step_mob(0.02)
	check(actor.combo_time >= 0.0 and actor.combo_heading.is_equal_approx(Vector2.RIGHT),"AI starts the two-slash combo when an enemy is in range")
	actor.cancel_combo()
	actor.cooldown_left = 0.0
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
	wall.queue_free()
	await process_frame
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
