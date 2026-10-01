extends "res://tests/test_elytra_return_dash.gd"
func fixture_script(body:String) -> Script:
	var script:GDScript = GDScript.new()
	script.source_code = "extends \"res://classes/ball.gd\"\n"+body
	check(script.reload()==OK,"runtime damage fixture compiles after autoload initialization")
	return script
var unit:Node2D
var enemy:Node2D
var ball_type:Script

func tick(delta:float) -> void: unit.tick_physics(ball_type.State.Move,delta)
func reset_attack() -> void:
	unit.cancel_attack()
	unit.attack_wait = 0.0
	unit.rush_wait = 0.0
	unit.facing = Vector2.RIGHT
func strike(target:Node2D,ratio:float) -> float:
	unit.phase = unit.Phase.SWING
	unit.released_charge = ratio
	var before:float = target.health_loss_reading()
	unit.deal_axe_hit(target,target.global_position)
	return before-target.health_loss_reading()
func extra(scene:String,script:Script=null) -> Node2D:
	var target:Node2D = load(scene).instantiate()
	if script != null: target.set_script(script)
	target.Team = "Team1"
	target.Max_health = 10000
	target.Health_Restore = 0
	arena.add_child(target,true)
	target.global_position = Vector2(600,300)
	target.state_machine.set_physics_process(false)
	target.set_physics_process(false)
	return target

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Development_Mode = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	ball_type = load("res://classes/ball.gd")
	arena = FlightArena.new()
	root.add_child(arena)
	current_scene = arena
	arena.process_mode = Node.PROCESS_MODE_DISABLED
	create_timer(45.0,true,false,true).timeout.connect(func():push_error("VINDICATOR_TIMEOUT");quit(2))
	unit = actor("卫道士",Vector2.ZERO)
	enemy = victim(Vector2(180,0))
	enemy.max_block = 10000
	unit.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	enemy.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	for warm:int in 8: await process_frame
	check(unit.get_script().resource_path.ends_with("vindicator.gd"),"selectable scene loads production script")
	check(unit.get_preview_texture()!=null and unit.voice.events.size()==5,"native art and four sound families plus swing are connected")
	check(unit.player_control_action_ids()==[&"controlled_attack_action",&"controlled_skill_action"],"exactly two manual actions in left/right order")
	check(not unit.player_control_action_hold_repeat_allowed(0),"held attack is not repeatedly restarted")
	var locale:String = game.current_locale
	game.current_locale = "en"
	check(game.t("卫道士")=="Vindicator","official English name")
	game.current_locale = locale
	check(unit.damage_multiplier(0.0)<unit.damage_multiplier(0.5) and unit.damage_multiplier(0.5)<unit.damage_multiplier(1.0),"charge damage grows monotonically")

	for ratio:float in [0.0,0.4999,0.5,0.7499,0.75,1.0]:
		enemy.block = 10000
		enemy.Damage_reduction = 0.6
		var damage:float = unit.attack_damage(unit.damage_multiplier(ratio))
		var before_block:float = enemy.block
		var loss:float = strike(enemy,ratio)
		if ratio<0.5:
			check(is_zero_approx(loss) and enemy.block<before_block,"below 50% remains blockable: "+str(ratio))
		elif ratio<0.75:
			check(absf(loss-damage*0.4)<=1.0 and enemy.block==before_block,"50%-75% bypasses block but respects reduction: "+str(ratio))
		else:
			check(absf(loss-damage)<=1.0 and enemy.block==before_block,"75%+ true damage ignores block and reduction: "+str(ratio))
		check(not enemy.incoming_damage_bypasses_guard() and not enemy.incoming_damage_ignores_reduction(),"damage policy never leaks after a hit")
	enemy.block = 0
	var before:float = enemy.health
	enemy.receive_classified_positional_damage(20.0,enemy.global_position,&"ordinary",false,unit)
	check(absf(before-enemy.health-8.0)<1.1,"next ordinary attack retains normal reduction")
	var nested:Node2D = extra("res://scenes/ball.tscn",fixture_script("var triggered:bool = false\nfunc on_actual_health_damage_received(_amount:float,_before:float) -> void:\n\tif triggered: return\n\ttriggered = true\n\ttake_damage(10.0,true)\n"))
	var dodge:Node2D = extra("res://scenes/ball.tscn",fixture_script("var dodges:int = 0\nfunc receive_positional_damage(_damage:float,_point:Vector2,_ignore:bool=false,_source:Node=null) -> bool:\n\tdodges += 1\n\treturn false\n"))
	var immune:Node2D = extra("res://scenes/characters/默认/虚无盔甲架.tscn")
	var shell:Node2D = extra("res://scenes/characters/我的世界/潜影贝.tscn")
	var sword:Node2D = extra("res://scenes/characters/人物/剑客.tscn")
	var purple:Node2D = extra("res://scenes/characters/月计/堇紫泪滴.tscn")
	var red:Node2D = extra("res://scenes/characters/月计/殷红迷雾.tscn")
	var shield:Node2D = extra("res://scenes/characters/三角洲/盾狗.tscn")
	for warm:int in 8: await process_frame
	nested.Damage_reduction = 0.5
	var nested_loss:float = strike(nested,0.75)
	check(absf(nested_loss-(unit.attack_damage(unit.damage_multiplier(0.75))+5.0))<=1.0,"nested ordinary damage does not inherit true damage")
	check(is_zero_approx(strike(dodge,1.0)) and dodge.dodges>0,"full charge still respects virtual dodge")
	check(is_zero_approx(strike(immune,1.0)),"real invulnerable dummy remains invulnerable")
	shell.shell_open = false
	check(is_zero_approx(strike(shell,0.49)),"closed Shulker blocks a low-charge axe")
	check(strike(shell,0.5)>0.0,"50% axe pierces closed-shell block")
	sword._dodge_cooldown_left = 99.0
	sword._parry_active = true
	check(strike(sword,0.5)>0.0,"50% axe bypasses real swordsman parry")
	check(sword._parry_active,"bypass does not consume the defender's parry state")
	purple._stance = purple.Stance.DEFENSE
	var attacker_health:float = unit.health
	check(strike(purple,0.5)>0 and unit.health==attacker_health,"50% axe bypasses guard reflection without counter damage")
	purple._rewinding = true
	check(is_zero_approx(strike(purple,1.0)),"guard bypass does not bypass rewind invulnerability")
	red._guarding = true
	red.ego_active = true
	check(strike(red,0.5)>0,"50% bypasses EGO guard but not general resistance")
	red._movement_invulnerable = true
	check(is_zero_approx(strike(red,1.0)),"movement invulnerability remains effective")
	shield.front_damage_reduction = 1.0
	var full_expected:float = unit.attack_damage(unit.damage_multiplier(1.0))
	check(absf(strike(shield,1.0)-full_expected)<=1.0,"true damage ignores custom frontal armor reduction")
	for target:Node2D in [nested,dodge,immune,shell,sword,purple,red,shield]: target.free()
	await process_frame

	reset_attack()
	unit.set_player_control_peer(1)
	unit.attack_wait = 0.0
	unit.set_player_control_aim_position(Vector2(180,0))
	unit.player_control_action(0)
	check(unit.phase==unit.Phase.CHARGE,"press starts raising the axe")
	before = enemy.health
	tick(unit.full_charge_seconds*0.5)
	check(is_equal_approx(unit.charge_ratio(),0.5) and enemy.health==before,"holding advances charge without early damage")
	unit.player_control_action_released(0)
	check(unit.phase==unit.Phase.SWING and is_equal_approx(unit.released_charge,0.5),"release locks exact accumulated charge")
	var locked:Vector2 = unit.facing
	unit.set_player_control_aim_position(Vector2(0,-180))
	check(unit.facing==locked,"swing heading is committed, not redirected mid-hit")
	reset_attack()
	unit.player_control_action(0)
	tick(unit.full_charge_seconds+0.1)
	check(unit.phase==unit.Phase.SWING and is_equal_approx(unit.released_charge,1.0),"full charge auto-releases")
	reset_attack()
	unit.player_control_action(0)
	unit.player_control_action_cancelled(0)
	check(unit.phase==unit.Phase.IDLE and not unit._manual_held,"cancelled input does not accidentally swing")
	reset_attack()
	unit.player_control_action(0)
	unit.set_player_control_peer(0)
	check(unit.phase==unit.Phase.IDLE,"loss of control ownership cancels the held action")
	unit.set_player_control_peer(1)
	unit.set_player_control_aim_position(Vector2(500,0))
	reset_attack()
	unit.player_control_action(1)
	check(unit.phase==unit.Phase.DASH and unit.rush_wait>0.0,"right click starts one cooldown-gated rush")
	var old_position:Vector2 = unit.global_position
	tick(0.15)
	check(unit.global_position.distance_to(old_position)>0 and unit.charge_ratio()>0 and unit.charge_ratio()<1,"rush moves physically and charges over elapsed time")
	unit.set_player_control_aim_position(unit.global_position+Vector2(1,0))
	tick(0.01)
	check(unit.phase==unit.Phase.SWING and unit.released_charge<0.5,"early arrival swings with partial charge, not free full charge")
	reset_attack()
	unit.player_control_action(0)
	var stun:Node = unit.apply_stun(1.0,enemy)
	tick(0.1)
	check(unit.phase==unit.Phase.IDLE and unit.charge_elapsed==0,"stun interrupts charging")
	stun.free()
	reset_attack()
	unit.player_control_action(1)
	var cold:Node = load("res://scripts/characters/我的世界/snow_golem/cold.gd").ensure(unit)
	cold.add_cold(100.0,1.0,enemy)
	tick(0.1)
	check(unit.phase==unit.Phase.IDLE,"freeze interrupts rushing")
	unit.cleanse_negative_effects()
	await process_frame
	reset_attack()
	unit.player_control_action(0)
	unit.apply_damage_disable(2.0)
	tick(0.1)
	check(unit.phase==unit.Phase.IDLE,"damage disable cancels unfinished attack")
	unit._damage_output_disabled_until_msec = 0

	reset_attack()
	unit.global_position = Vector2.ZERO
	unit.facing = Vector2.RIGHT
	unit.phase = unit.Phase.SWING
	unit.released_charge = 1.0
	unit.phase_elapsed = unit.swing_seconds*0.5
	unit._update_pose()
	enemy.global_position = unit.blade_center()
	enemy.block = 0
	enemy.Damage_reduction = 0
	unit.phase_elapsed = 0.0
	unit._update_pose()
	before = enemy.health
	unit._advance_swing(unit.swing_seconds)
	check(absf(before-enemy.health-full_expected)<=1.0,"continuous visible axe sweep hits once even across a large delta")
	check(not unit.get_debug_attack_regions().is_empty(),"actual swept segments feed threat display")
	before = enemy.health
	tick(unit.recovery_seconds)
	check(enemy.health==before and unit.get_debug_attack_regions().is_empty(),"recovery cannot deal lingering axe damage")
	check(unit.phase==unit.Phase.IDLE,"recovery returns to idle")
	var pose_tip:Vector2 = unit.blade_center()
	unit._receive_visual(20,unit.Phase.CHARGE,unit.full_charge_seconds,0,0,Vector2.LEFT,0)
	check(unit.phase==unit.Phase.CHARGE and unit.blade_center()!=pose_tip,"remote presentation applies the authoritative raised pose")
	unit._receive_visual(19,unit.Phase.IDLE,0,0,0,Vector2.RIGHT,0)
	check(unit.phase==unit.Phase.CHARGE,"stale visual packet cannot rewind state")
	await extra_runtime_checks()
	await corrected_rig_and_movement_checks()
	await fixed_grip_charge_checks()
	await low_hand_grip_checks()
	await heavy_chop_checks()
	await fast_chop_contact_checks()
	await normal_wall_bounce_checks()
	if DisplayServer.get_name()!="headless": await gpu_checks()
	for warm:int in 6: await process_frame
	current_scene = null
	arena.queue_free()
	await process_frame
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	print("VINDICATOR_RESULT checks=",checks," failures=",failures," completed=true")
	quit(0 if failures==0 else 1)

func gpu_checks() -> void:
	var view:SubViewport = SubViewport.new()
	view.size = Vector2i(640,480)
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var stage:Node2D = FlightArena.new()
	view.add_child(stage)
	stage.process_mode = Node.PROCESS_MODE_DISABLED
	var backdrop:CanvasLayer = CanvasLayer.new()
	backdrop.layer = -10
	view.add_child(backdrop)
	var color:ColorRect = ColorRect.new()
	color.color = Color(0.13,0.15,0.18)
	color.size = Vector2(640,480)
	backdrop.add_child(color)
	var previous_arena:Node2D = arena
	arena = stage
	var model:Node2D = actor("卫道士",Vector2.ZERO)
	arena = previous_arena
	model.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	model.stun_shake_enabled = false
	model.hurt_shake_enabled = false
	for warm:int in 8: await process_frame
	var camera:Camera2D = Camera2D.new()
	stage.add_child(camera)
	camera.zoom = Vector2(5.0,5.0)
	camera.make_current()
	camera.force_update_scroll()
	model._arm.hide()
	await RenderingServer.frame_post_draw
	var body:Image = view.get_texture().get_image()
	var visible_body:int = 0
	var background:Color = body.get_pixel(0,0)
	for y:int in range(100,380):
		for x:int in range(200,440):
			var pixel:Color = body.get_pixel(x,y)
			if absf(pixel.r-background.r)+absf(pixel.g-background.g)+absf(pixel.b-background.b)>0.16: visible_body+=1
	check(visible_body>1000 and not model.image.flip_h,"GPU renders the complete body with shader-safe facing")
	model._arm.show()
	var icon_bounds:Rect2i = model.get_preview_texture().get_image().get_used_rect()
	var torso_bounds:Rect2i = model.FRAMES.get_frame_texture(&"idle",0).get_image().get_used_rect()
	check(icon_bounds.position.y<torso_bounds.position.y-5,"imported selection preview includes the raised enlarged axe")
	model.phase = model.Phase.CHARGE
	model.facing = Vector2.RIGHT
	model.charge_elapsed = 0.0
	model._update_pose()
	for frame:int in 3: await RenderingServer.frame_post_draw
	var before:Image = view.get_texture().get_image()
	var low:Vector2 = model.blade_center()
	model.charge_elapsed = model.full_charge_seconds*0.8
	model._update_pose()
	await RenderingServer.frame_post_draw
	var raised:Image = view.get_texture().get_image()
	var high:Vector2 = model.blade_center()
	check(high.y<low.y-5,"GPU pose raises the real axe above its resting hand")
	check(before.get_data()!=raised.get_data(),"GPU charge visibly changes original-model arm and axe")
	check(raised.get_size()==Vector2i(640,480),"GPU capture uses the isolated unscaled viewport")
	model.phase = model.Phase.SWING
	model.released_charge = 0.8
	model.phase_elapsed = model.swing_seconds*0.7
	model._update_pose()
	await RenderingServer.frame_post_draw
	var swung:Image = view.get_texture().get_image()
	check(raised.get_data()!=swung.get_data() and model.blade_center().distance_to(high)>10,"GPU swing follows actual axe hit geometry")
	swung.save_png("user://vindicator_swing.png")
	raised.save_png("user://vindicator_charge.png")
	for heading:Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,-1).normalized(),Vector2(-1,-1).normalized(),Vector2(1,1).normalized(),Vector2(-1,1).normalized()]:
		for pose:int in [model.Phase.CHARGE,model.Phase.SWING]:
			model.facing = heading
			model.phase = pose
			model.charge_elapsed = model.full_charge_seconds*0.8
			model.released_charge = 0.8
			model.phase_elapsed = model.swing_seconds*0.7 if pose==model.Phase.SWING else 0.0
			model._update_pose()
			await RenderingServer.frame_post_draw
			view.get_texture().get_image().save_png("user://vindicator_grip_%d_%d.png"%[pose,int(round(rad_to_deg(heading.angle())))])
	for side:int in [-1,1]:
		var previous:Image
		for percentage:int in [0,25,50,75,100]:
			model.phase = model.Phase.CHARGE
			model.facing = Vector2(side,0)
			model.charge_elapsed = model.full_charge_seconds*float(percentage)/100.0
			model._update_pose()
			await RenderingServer.frame_post_draw
			var frame:Image = view.get_texture().get_image()
			if previous!=null: check(frame.get_data()!=previous.get_data(),"GPU charge keeps changing through %d%% facing %d"%[percentage,side])
			frame.save_png("user://vindicator_upright_%d_%d.png"%[side,percentage])
			previous = frame
	for side:int in [-1,1]:
		for stage_index:int in 5:
			model.facing = Vector2(side,0)
			model.phase = model.Phase.RECOVER if stage_index in [2,3] else model.Phase.CHARGE if stage_index==1 else model.Phase.IDLE
			model.charge_elapsed = model.full_charge_seconds*0.02
			model.released_charge = 0.4
			model.phase_elapsed = model.recovery_seconds*(0.75 if stage_index==2 else 1.0)
			model.velocity = Vector2(85,0) if stage_index==4 else Vector2.ZERO
			model._update_pose()
			await RenderingServer.frame_post_draw
			var frame:Image = view.get_texture().get_image()
			var shaft:Vector2 = model._axe.get_global_transform_with_canvas()*(model.AXE_GRIP+Vector2(3,-3)+model._axe.offset)
			var brown:bool = false
			for y:int in range(-1,2):
				for x:int in range(-1,2):
					var pixel:Color = frame.get_pixelv(Vector2i(shaft.round())+Vector2i(x,y))
					brown = brown or (pixel.r>0.2 and pixel.r>pixel.g*1.1 and pixel.b<pixel.r*0.6)
			check(brown,"GPU lowered axe has visible wooden shaft on the blade side of the fist, not hidden by sleeve: side="+str(side)+" stage="+str(stage_index))
			frame.save_png("user://vindicator_low_grip_%d_%d.png"%[side,stage_index])
	model.set_player_control_peer(1)
	for rush:bool in [false,true]:
		model.global_position = Vector2.ZERO
		model.set_player_control_aim_position(Vector2(400,0))
		model.cancel_attack()
		model.attack_wait = 0.0
		model.rush_wait = 0.0
		for frame:int in 90:
			if frame==12: model.player_control_action(1 if rush else 0)
			if frame==48:
				if rush: model.set_player_control_aim_position(model.global_position+Vector2(8,0))
				else: model.player_control_action_released(0)
			model.tick_physics(ball_type.State.Move,1.0/60.0)
			if rush and frame==47: check(model.global_position.x>30 and model.phase==model.Phase.DASH,"GPU rush sequence uses actual moving physics, not a stationary pose")
			camera.position = model.global_position
			camera.force_update_scroll()
			await RenderingServer.frame_post_draw
			view.get_texture().get_image().save_png("user://vindicator_motion_%d_%03d.png"%[int(rush),frame])
		check(model.phase==model.Phase.IDLE,"GPU full input-driven action finishes in lowered idle, rush="+str(rush))
	view.queue_free()
	await process_frame

func extra_runtime_checks() -> void:
	check(unit.player_control_action_hold_repeat_allowed(1),"skill hold-repeat retains normal cooldown retry semantics")
	reset_attack()
	unit.player_control_action(0)
	tick(0.3)
	var charge:float = unit.charge_elapsed
	var cooldown:float = unit.rush_wait
	game.now_stop_state = true
	tick(0.5)
	check(unit.phase==unit.Phase.CHARGE and unit.charge_elapsed==charge and unit.rush_wait==cooldown,"pause preserves charging and cooldown progress")
	game.now_stop_state = false
	tick(0.1)
	check(unit.charge_elapsed>charge,"resume continues the same charge")
	var damage:int = unit.Damage
	unit.Damage = damage*2
	var loss:float = strike(enemy,0.75)
	check(absf(loss-unit.attack_damage(unit.damage_multiplier(0.75)))<=1.0,"axe samples current attack stats at impact")
	unit.Damage = damage
	var guarded:Node2D = extra("res://scenes/ball.tscn",fixture_script("var scopes:Array[bool] = []\nfunc on_actual_health_damage_received(_amount:float,_before:float) -> void:\n\tscopes.append(current_health_damage_bypasses_guard())\n\tif scopes.size()==1: health -= 10\n"))
	strike(guarded,0.75)
	check(guarded.scopes==[true,false] and not guarded.current_health_damage_bypasses_guard(),"direct nested health write has its own guard scope")
	guarded.free()
	reset_attack()
	unit.global_position = Vector2.ZERO
	enemy.global_position = Vector2(1000,0)
	unit.set_player_control_aim_position(Vector2(500,0))
	var wall:StaticBody2D = StaticBody2D.new()
	wall.collision_layer = 1
	wall.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	var shape:CollisionShape2D = CollisionShape2D.new()
	var rectangle:RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(20,240)
	shape.shape = rectangle
	wall.add_child(shape)
	arena.add_child(wall)
	wall.global_position = Vector2(60,0)
	await physics_frame
	var old_cooldown:float = unit.Skill_Cooling
	unit.Skill_Cooling = 3.5
	unit.player_control_action(1)
	check(is_equal_approx(unit.rush_wait,3.5),"rush cooldown uses current skill cooldown attribute")
	unit.Skill_Cooling = old_cooldown
	tick(0.6)
	check(unit.global_position.x<50 and unit.phase==unit.Phase.SWING and unit.released_charge<1.0,"real wall collision stops rush and releases only accumulated charge")
	wall.free()
	reset_attack()

func corrected_rig_and_movement_checks() -> void:
	reset_attack()
	unit.global_position = Vector2.ZERO
	enemy.global_position = Vector2(1000,0)
	unit.set_player_control_peer(0)
	unit.Repel = Vector2.ZERO
	unit.direction = Vector2(-0.6,-0.8)
	unit.phase = unit.Phase.IDLE
	tick(0.01)
	check(unit.facing.is_equal_approx(unit.direction),"idle facing follows normal travel rather than a distant enemy")
	var expected:Vector2 = unit.direction*unit.Speed*ball_type.CHARACTER_BASE_MOVE_SPEED_MULTIPLIER
	for state:int in [unit.Phase.IDLE,unit.Phase.CHARGE,unit.Phase.SWING,unit.Phase.RECOVER]:
		unit.phase = state
		unit.move(unit.Speed,1.0/60.0)
		check(unit.direction.is_equal_approx(Vector2(-0.6,-0.8)) and unit.velocity.is_equal_approx(expected),"normal movement preserves direction and speed in phase "+str(state))
	unit.set_player_control_peer(1)
	unit.player_control_direction = Vector2.UP
	unit.set_player_control_aim_position(Vector2(1000,0))
	unit.phase = unit.Phase.SWING
	unit.move(unit.Speed,1.0/60.0)
	check(unit.velocity.is_equal_approx(Vector2.UP*unit.Speed*ball_type.CHARACTER_BASE_MOVE_SPEED_MULTIPLIER),"WASD movement remains independent of attack aim while swinging")
	unit.Repel = Vector2(20,0)
	unit.stand(1.0/60.0)
	check(unit.velocity.is_equal_approx(unit.Repel),"normal stand preserves common knockback during a swing")
	unit.Repel = Vector2.ZERO
	unit.velocity = Vector2.ZERO
	check(unit._arm.show_behind_parent,"resting far arm renders behind torso and head")
	check(unit._axe.get_parent()==unit._wrist and unit._hand_sprite.get_parent()==unit._wrist and unit._axe.get_index()<unit._hand_sprite.get_index(),"hand occludes the axe handle instead of the handle covering the hand")
	var skin:Color = unit.ARM.get_image().get_pixelv(unit.HAND.floor())
	check(skin.a>0.9 and absf(skin.r-skin.g)<0.08 and skin.r>0.25,"grip anchor lies inside the native gray hand, not at the sleeve or fingertips")
	for heading:Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,-1).normalized(),Vector2(-1,-1).normalized(),Vector2(1,1).normalized(),Vector2(-1,1).normalized()]:
		unit.facing = heading
		unit.phase = unit.Phase.CHARGE
		unit.charge_elapsed = unit.full_charge_seconds*0.8
		unit._update_pose()
		var hand:Vector2 = unit.hand_center()
		check(unit._axe.to_global(unit.AXE_GRIP+unit._axe.offset).distance_to(hand)<0.001,"axe grip follows palm for heading "+str(heading))
		check(hand.y<unit._arm.global_position.y-5,"charge raises hand above shoulder for heading "+str(heading))
		if is_zero_approx(heading.y):
			var neck:Vector2 = unit._axe.to_global(Vector2(11.5,5.5)+unit._axe.offset)
			check((unit.blade_center()-neck).dot(heading)>0,"cutting edge faces the attack, not backward: "+str(heading))
	for pose:int in [unit.Phase.CHARGE,unit.Phase.SWING,unit.Phase.RECOVER]:
		unit.phase = pose
		unit.released_charge = 0.8
		unit.phase_elapsed = unit.swing_seconds*0.65
		unit.facing = Vector2.RIGHT
		unit._update_pose()
		var axis:Vector2 = unit.image.to_global(unit.image.offset)
		var right:Vector2 = unit.blade_center()-axis
		unit.facing = Vector2.LEFT
		unit._update_pose()
		var left:Vector2 = unit.blade_center()-axis
		check(left.distance_to(Vector2(-right.x,right.y))<0.001,"entire arm and axe geometry mirrors in phase "+str(pose))
	reset_attack()

func normal_wall_bounce_checks() -> void:
	reset_attack()
	unit.set_player_control_peer(0)
	unit.Repel = Vector2.ZERO
	enemy.global_position = Vector2(1000,0)
	var wall:StaticBody2D = StaticBody2D.new()
	wall.collision_layer = 1
	wall.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	var shape:CollisionShape2D = CollisionShape2D.new()
	var rectangle:RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(20,240)
	shape.shape = rectangle
	wall.add_child(shape)
	arena.add_child(wall)
	wall.global_position = Vector2(60,0)
	await physics_frame
	for state:int in [unit.Phase.IDLE,unit.Phase.CHARGE]:
		unit.global_position = Vector2.ZERO
		unit.phase = state
		unit.direction = Vector2.RIGHT
		for frame:int in 120:
			await physics_frame
			unit.move(unit.Speed,1.0/60.0)
			if unit.direction.x<0: break
		check(unit.direction.x<0,"normal physical wall collision reflects direction in phase "+str(state))
		var point:Vector2 = unit.global_position
		await physics_frame
		unit.move(unit.Speed,1.0/60.0)
		check(unit.global_position.x<point.x and unit.direction.x<0,"enemy aiming cannot overwrite wall bounce in phase "+str(state))
	wall.free()
	reset_attack()

func axe_shaft_direction(model:Node2D) -> Vector2:
	return (model._axe.to_global(model.AXE_GRIP+Vector2(6,-6)+model._axe.offset)-model._axe.to_global(model.AXE_GRIP+model._axe.offset)).normalized()

func fixed_grip_charge_checks() -> void:
	reset_attack()
	unit.set_player_control_peer(1)
	unit.velocity = Vector2.ZERO
	for heading:Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,-1).normalized(),Vector2(-1,-1).normalized(),Vector2(1,1).normalized(),Vector2(-1,1).normalized()]:
		unit.facing = heading
		unit.phase = unit.Phase.IDLE
		unit._update_pose()
		check(unit.hand_center().y>unit._arm.global_position.y+5,"idle hand hangs below shoulder, not an attacking stance: "+str(heading))
		var hand_direction:Vector2 = (unit.hand_center()-unit._wrist.global_position).normalized()
		check(absf(axe_shaft_direction(unit).dot(hand_direction))<0.1 and is_zero_approx(unit._wrist.rotation),"lowered axe stays perpendicular to hand, not upright on screen: "+str(heading))
		check(is_equal_approx(unit._axe.scale.x,5.0) and is_equal_approx(unit.blade_radius(),unit._axe.global_scale.abs().x*4.5),"larger axe and actual blade radius share scale: "+str(heading))
		for pose:int in [unit.Phase.CHARGE,unit.Phase.DASH]:
			unit.phase = pose
			var fixed_grip:bool = true
			var attached:bool = true
			var rises:bool = true
			var previous:float = INF
			var first_axis:Vector2
			for step:int in 101:
				unit.charge_elapsed = unit.full_charge_seconds*float(step)/100.0
				unit._update_pose()
				if step==0: first_axis = axe_shaft_direction(unit)
				fixed_grip = fixed_grip and is_equal_approx(unit._axe.rotation,unit.AXE_HOLD_ANGLE)
				attached = attached and unit._axe.to_global(unit.AXE_GRIP+unit._axe.offset).distance_to(unit.hand_center())<0.001
				rises = rises and unit.blade_center().y<previous-0.0001
				previous = unit.blade_center().y
			check(fixed_grip and attached,"fixed hand-and-axe grip at every charge percentage: "+str(heading)+" phase "+str(pose))
			check(absf(first_axis.angle_to(axe_shaft_direction(unit)))>0.8,"axe actually rotates with the raising forearm: "+str(heading)+" phase "+str(pose))
			check(rises,"axe rises throughout 0-100%, including the final quarter: "+str(heading)+" phase "+str(pose))
		unit.phase = unit.Phase.SWING
		unit.released_charge = 1.0
		unit.phase_elapsed = 0.0
		unit._update_pose()
		var swing_axis:Vector2 = axe_shaft_direction(unit)
		unit.phase_elapsed = unit.swing_seconds*0.75
		unit._update_pose()
		check(unit._arm.show_behind_parent==(heading.y< -0.15),"swing depth follows front/back direction "+str(heading))
		check(absf(swing_axis.angle_to(axe_shaft_direction(unit)))>0.2 and is_equal_approx(unit._axe.rotation,unit.AXE_HOLD_ANGLE),"swing rotates arm and axe together in direction "+str(heading))
		for ratio:float in [0.0,0.1,0.25,0.5,0.75,1.0]:
			unit.phase = unit.Phase.CHARGE
			unit.charge_elapsed = unit.full_charge_seconds*ratio
			unit._update_pose()
			var before:Vector2 = unit.blade_center()
			var shaft:Vector2 = axe_shaft_direction(unit)
			unit._release_swing()
			check(unit.blade_center().distance_to(before)<0.001 and axe_shaft_direction(unit).distance_to(shaft)<0.001,"release starts from actual held height and hand-relative grip: "+str(heading)+" charge "+str(ratio))
	reset_attack()

func heavy_chop_checks() -> void:
	reset_attack()
	unit.set_player_control_peer(1)
	unit.set_player_control_aim_position(Vector2(900,0))
	unit._update_pose()
	var resting_hand:Vector2 = unit.hand_center()
	check(unit.swing_seconds<=0.14,"complete chop takes at most 140 milliseconds")
	for rush:bool in [false,true]:
		reset_attack()
		unit._update_pose()
		var before:Vector2 = unit.blade_center()
		check(unit._begin_charge(rush) and unit.blade_center().distance_to(before)<0.001,"attack draws continuously from lowered idle, rush="+str(rush))
		if rush:
			for frame:int in 7: tick(1.0/60.0)
			var hand:Vector2 = unit.hand_center()
			check(unit.phase==unit.Phase.DASH and hand.y<unit._arm.global_position.y-4 and hand.y<resting_hand.y-10,"rush visibly raises hand within seven real physics steps")
			check(unit.charge_ratio()<0.1 and unit.velocity.length()>unit.Speed,"early high rush pose is not free full charge and movement continues")
			var before_release:Vector2 = unit.blade_center()
			unit._release_swing()
			check(unit.released_rush and unit.blade_center().distance_to(before_release)<0.001,"rush release preserves its distinct raised pose without snapping")
		else:
			tick(0.7)
			unit._release_swing()
		var at_release:Vector2 = unit.blade_center()
		unit.phase_elapsed = unit.swing_seconds
		unit._update_pose()
		var at_end:Vector2 = unit.blade_center()
		check(at_end.y>at_release.y+10,"side chop follows through visibly downward, rush="+str(rush))
		unit.phase = unit.Phase.RECOVER
		unit.phase_elapsed = 0.0
		unit._update_pose()
		check(unit.blade_center().distance_to(at_end)<0.001,"follow-through joins recovery without a position jump")
		unit.phase_elapsed = unit.recovery_seconds*0.15
		unit._update_pose()
		check(unit.blade_center().distance_to(at_end)<0.001,"brief low follow-through holds only the arm, not the world")
		unit.phase_elapsed = unit.recovery_seconds
		unit._update_pose()
		var recovered:Vector2 = unit.blade_center()
		unit.phase = unit.Phase.IDLE
		unit._update_pose()
		check(unit.blade_center().distance_to(recovered)<0.001,"recovery returns continuously to lowered idle")
	for aim:Vector2 in [Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(-1,-1).normalized(),Vector2(-1,1).normalized()]:
		unit.released_charge = 1.0
		unit.released_rush = false
		var start:Vector2 = unit._swing_pose(aim,0.0)
		var early:Vector2 = unit._swing_pose(aim,0.2)
		var middle:Vector2 = unit._swing_pose(aim,0.4)
		var end:Vector2 = unit._swing_pose(aim,1.0)
		check(absf(end.x-start.x)>=2.09,"large committed chop arc, not a small wrist wag: "+str(aim))
		check(absf(middle.x-early.x)>absf(early.x-start.x)*1.4,"downstroke visibly accelerates rather than moving at constant speed: "+str(aim))
	reset_attack()

func fast_chop_contact_checks() -> void:
	unit.global_position = Vector2.ZERO
	enemy.block = 0
	enemy.Damage_reduction = 0
	for rush:bool in [false,true]:
		for heading:Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,-1).normalized(),Vector2(-1,-1).normalized(),Vector2(1,1).normalized(),Vector2(-1,1).normalized()]:
			reset_attack()
			unit.facing = heading
			unit.phase = unit.Phase.DASH if rush else unit.Phase.CHARGE
			unit.charge_elapsed = unit.full_charge_seconds*(0.1 if rush else 1.0)
			enemy.global_position = heading*26.0
			await physics_frame
			unit._release_swing()
			var before:float = enemy.health_loss_reading()
			var expected:float = unit.attack_damage(unit.damage_multiplier(unit.released_charge))
			unit._advance_swing(unit.swing_seconds)
			var loss:float = before-enemy.health_loss_reading()
			check(absf(loss-expected)<=1.0,"one real blade hit through a whole fast-chop tick: "+str(heading)+" rush="+str(rush)+" actual="+str(loss)+" expected="+str(expected))
			check(unit._regions.size()>=90,"fast coarse tick retains dense true-blade threat segments")
	enemy.global_position = Vector2(180,0)
	reset_attack()

func low_hand_grip_checks() -> void:
	reset_attack()
	var original:Image = unit.ARM.get_image()
	var skin:Image = unit.HAND_TEXTURE.get_image()
	var sleeve:Image = unit.FOREARM.get_image()
	var preserved:bool = true
	for y:int in original.get_height():
		for x:int in original.get_width():
			var base:Color = original.get_pixel(x,y)
			var hand:Color = skin.get_pixel(x,y)
			var cloth:Color = sleeve.get_pixel(x,y)
			preserved = preserved and is_equal_approx(base.a,hand.a+cloth.a)
			if base.a>0.5:
				var part:Color = hand if hand.a>0.5 else cloth
				preserved = preserved and part.is_equal_approx(base)
	check(preserved,"split hand and sleeve preserve every original opaque texel without painting new art")
	for heading:Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,-1).normalized(),Vector2(-1,-1).normalized(),Vector2(1,1).normalized(),Vector2(-1,1).normalized()]:
		unit.facing = heading
		for pose:int in [unit.Phase.IDLE,unit.Phase.CHARGE,unit.Phase.DASH,unit.Phase.RECOVER]:
			var fixed:bool = true
			var attached:bool = true
			unit.phase = pose
			unit.released_charge = 0.4
			for step:int in 101:
				unit.charge_elapsed = unit.full_charge_seconds*float(step)/100.0
				unit.phase_elapsed = unit.recovery_seconds*float(step)/100.0
				unit._update_pose()
				var palm:Vector2 = unit.hand_center()
				var hand_axis:Vector2 = (unit._hand_sprite.to_global(unit.HAND+Vector2(10,0)+unit._hand_sprite.offset)-palm).normalized()
				var expected:float = absf(unit.AXE_HOLD_ANGLE-PI/4.0)
				fixed = fixed and is_zero_approx(unit._wrist.rotation) and absf(absf(hand_axis.angle_to(axe_shaft_direction(unit)))-expected)<0.001
				attached = attached and palm.distance_to(unit._axe.to_global(unit.AXE_GRIP+unit._axe.offset))<0.001
			check(fixed and attached,"axe stays clenched in the unchanged attack grip throughout lowering/drawing, without wrist compensation: "+str(heading)+" phase="+str(pose))
	reset_attack()
