extends SceneTree
var world:Node
var game:Node
var saved:Dictionary
var checks:int = 0
var failures:int = 0
func _initialize() -> void:
	call_deferred("run")
func check(ok:bool,message:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FINAL_FAIL ",message)
func spawn(path:String,team:String,p:Vector2) -> Node2D:
	var unit:Node2D = load(path).instantiate()
	unit.Team = team
	unit.position = p
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(unit,true)
	return unit
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	create_timer(60.0).timeout.connect(func(): finish(2))
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.now_stop_state = false
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	var old_mask:Material = world.map_outside_mask_parts[0].material
	var rect:Rect2 = world.return_map_world_rect(world.map_group["Map50x50"])
	var sans:Node2D = spawn("res://scenes/characters/传说之下/Sans.tscn","Team1",rect.get_center())
	var a:Node2D = spawn("res://scenes/ball.tscn","Team0",rect.get_center()+Vector2(80,80))
	var ally:Node2D = spawn("res://scenes/ball.tscn","Team1",rect.get_center()-Vector2(80,80))
	var old_a:Vector2 = a.global_position
	var old_ally:Vector2 = ally.global_position
	sans._dodge_count = 2
	sans._dodge_grace_remaining = 0.0
	sans._try_dodge_incoming()
	check(not sans._last_trial_active,"normal Sans cannot trigger final")
	sans.prepare_training_boss_specialization(1.0)
	sans.activate_training_boss_specialization(1.0)
	sans._dodge_count = 2
	sans._dodge_grace_remaining = 0.0
	sans._try_dodge_incoming()
	check(sans._last_trial_active,"last dodge locks immunity immediately")
	sans.take_damage(999)
	check(sans.health == 1 and sans._dodge_count == 1,"same-frame incoming damage cannot consume last dodge")
	check(not sans.receive_positional_damage(999.0,sans.global_position,true,a),"positional damage blocked during final")
	check(not sans.receive_spatial_damage(999.0,rect,true,true),"raw spatial damage blocked during final")
	await process_frame
	await process_frame
	var phase:Node = sans._last_trial_controller
	check(is_instance_valid(phase),"controller created")
	if not is_instance_valid(phase):
		finish(1)
		return
	check(world.now_choose_map == "SansFinal10x10","first blackout immediately transfers map")
	check(world.map_outside_mask_parts[0].material != old_mask,"temporary black outside material installed")
	check(phase.base_rect.size == world.return_map_world_rect(world.map_group["Map10x10"]).size,"exact native 10x10 dimensions")
	check(phase.base_rect.has_point(a.global_position) and phase.base_rect.has_point(ally.global_position),"all teams transferred")
	check(a.Team == "Team0" and ally.Team == "Team1","teams unchanged")
	phase._process(0.0)
	check(phase.timer_label.text.contains(":"),"seconds:hundredths HUD")
	var time:float = phase.elapsed
	game.now_stop_state = true
	phase._physics_process(5.0)
	check(phase.elapsed == time,"shared timeline pauses")
	game.now_stop_state = false
	phase._start_slam(Vector2.DOWN)
	check(not a.get_collision_layer_value(2),"slam passes through other combatant bodies")
	a.global_position = Vector2(phase.base_rect.get_center().x,phase.base_rect.end.y-a.get_crowd_separation_radius_world())
	ally.global_position = a.global_position
	phase._update_slams(0.10)
	check(phase.impact_sides.size() == 1 and phase.hazards.size() == 1,"one impact spike per wall, not per combatant")
	check(a.get_collision_layer_value(2),"wall impact restores body collision")
	check(a._external_directional_gravity_hop_enabled,"opening slam permits jumping after landing")
	check(a.get_external_directional_gravity().length() < 1000.0,"slam force drops back to jumpable gravity")
	check(sans.graphics.z_index > world.versus_label.z_index,"Sans graphics really render above VS")
	phase._update_hud()
	check(world.versus_label.visible,"VS is retained, not hidden as a layering workaround")
	check(is_equal_approx(phase.hazards[0].active_duration,0.14),"short per-instance spike lifetime")
	check(phase.background.z_index == -2,"black backdrop precedes outside-mask capture")
	phase._physics_process(13.1)
	check(phase.arena_rect.size.x > phase.base_rect.size.x,"right boundary extends")
	check(phase.hazards.size() == 40,"sparse arc only; grouped bones not spawned yet")
	var stationary:Node2D = phase.hazards[0]
	var origin:Vector2 = stationary.global_position
	stationary._physics_process(0.1)
	check(stationary.global_position == origin,"arc bones stationary in world coordinates")
	check(a.get_external_directional_gravity().x > 0.0,"characters receive real rightward gravity")
	var old_wall_y:float = stationary.global_position.y
	phase._physics_process(0.5)
	check(not is_equal_approx(stationary.global_position.y,old_wall_y),"bones follow narrowing wall movement")
	check(is_equal_approx(stationary.global_position.y,phase.arena_rect.position.y),"upper bone root flush with current wall")
	phase._physics_process(11.5)
	check(phase.hazards.size() == 18,"arc clears before six separate triple groups")
	check(stationary.is_queued_for_deletion(),"previous arc removed at group transition")
	phase._physics_process(4.0)
	check(world.now_choose_map == "Map50x50","second blackout restores original map")
	check(a.global_position == old_a and ally.global_position == old_ally,"all participant positions restored")
	check(not world.map_group.has("SansFinal10x10"),"temporary map removed")
	check(world.map_outside_mask_parts[0].material == old_mask,"original clipping material restored")
	phase._physics_process(1.0)
	check(phase.wind_emitted > 0,"windmill only after return")
	phase._physics_process(6.4)
	check(phase.wind_emitted == phase.wind_steps,"exactly three rounds emitted")
	check(phase.wind_steps == phase.wind_slots*3,"three-round shared timeline")
	phase._physics_process(20.0)
	check(not sans._last_trial_active,"invulnerability ends with final blackout")
	check(sans.global_position == rect.get_center(),"Sans returns to original map center")
	check(not world.has_meta("sans_final_phase"),"world ownership restored")
	check(not a.get_external_directional_gravity().length_squared() > 0.0,"trial gravity removed")
	sans._start_windmill()
	check(not sans._windmill_active,"independent windmill entry disabled")
	sans._dodge_grace_remaining = 0.0
	sans._try_dodge_incoming()
	check(not sans._last_trial_active,"final cannot trigger twice")
	# 中断恢复测试：新的 Boss 被主动停止/释放时不得遗留地图、水印、重力。
	var second:Node2D = spawn("res://scenes/characters/传说之下/Sans.tscn","Team1",rect.get_center())
	second.prepare_training_boss_specialization(1.0)
	second.activate_training_boss_specialization(1.0)
	second._dodge_count = 2
	second._dodge_grace_remaining = 0.0
	second._try_dodge_incoming()
	await process_frame
	await process_frame
	var interrupted:Node = second._last_trial_controller
	check(is_instance_valid(interrupted),"subsequent encounter can own map")
	interrupted._physics_process(14.0)
	interrupted.finish(false)
	check(world.now_choose_map == "Map50x50" and not world.has_meta("sans_final_phase"),"interruption restores map ownership")
	check(not second._last_trial_active,"interruption clears immunity")
	check(a.get_collision_layer_value(2),"interruption restores collision phasing")
	check(world.versus_label.visible,"interruption restores versus HUD")
	check(second.health_bar.visible,"interruption restores Sans health bar")
	# 敌人死亡也必须先黑屏，再恢复原图；胜利暂停不能阻止收尾。
	second._last_trial_used = false
	second._dodge_count = 2
	second._dodge_grace_remaining = 0.0
	second._try_dodge_incoming()
	await process_frame
	await process_frame
	var death_phase:Node = second._last_trial_controller
	a.health = 0
	death_phase._physics_process(0.1)
	check(death_phase.death_return_started >= 0 and death_phase.in_temp,"enemy death starts blackout without immediate map swap")
	game.now_stop_state = true
	death_phase.death_return_started -= 300
	death_phase._process(0.0)
	check(not death_phase.in_temp and death_phase.black.color.a > 0.99,"return occurs while fully black")
	death_phase.death_return_started -= 800
	death_phase._process(0.0)
	check(death_phase.finished and not second._last_trial_active,"death blackout completes even with victory pause")
	check(world.now_choose_map == "Map50x50","death return restores original map")
	game.now_stop_state = false
	a.health = 1000
	# 刀光必须匹配世界变换；普通/EGO 使用真实纹理遮罩。
	var mist:Node2D = spawn("res://scenes/characters/月计/殷红迷雾.tscn","Team0",rect.get_center())
	mist.scale = Vector2.ONE*0.5
	var area:Area2D = mist._create_local_rect_attack_volume(Vector2.RIGHT,Vector2(200,100),1.0,50.0)
	mist._spawn_blade_light_on_area(0,area,Vector2(200,100),false)
	var effect:Node2D = world.get_child(world.get_child_count()-1)
	check(effect.global_position.is_equal_approx(area.global_position),"mist center matches attack volume")
	check(effect._effect_size.is_equal_approx(Vector2(100,50)),"mist carries parent scale into world dimensions")
	check(effect._sprite.position == Vector2.ZERO,"no duplicate forward offset")
	check(effect.z_index > 90 and effect.z_index < 100,"mist above outside mask, below border")
	game.now_stop_state = true
	time = effect._elapsed
	effect._process(2.0)
	check(effect._elapsed == time,"mist visual pauses with battle")
	game.now_stop_state = false
	finish(0 if failures == 0 else 1)
func finish(code:int) -> void:
	if game != null:
		game.Game_Settings = saved
	print("FINAL_TEST_RESULT checks=",checks," failures=",failures)
	quit(code)
