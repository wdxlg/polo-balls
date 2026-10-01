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
	model.phase_elapsed = model.swing_seconds*0.7
	model._update_pose()
	await RenderingServer.frame_post_draw
	var swung:Image = view.get_texture().get_image()
	check(raised.get_data()!=swung.get_data() and model.blade_center().distance_to(high)>10,"GPU swing follows actual axe hit geometry")
	swung.save_png("user://vindicator_swing.png")
	raised.save_png("user://vindicator_charge.png")
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
