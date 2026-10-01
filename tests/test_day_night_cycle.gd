extends SceneTree
const CYCLE = preload("res://scripts/day_night_cycle.gd")
var checks:int = 0
var failures:int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("DAY_NIGHT FAIL: "+label)
	else: print("PASS: ",label)

func _run() -> void:
	create_timer(90.0,true,false,true).timeout.connect(func():quit(2))
	var game:Node = root.get_node("Game")
	var old:Dictionary = game.Game_Settings.duplicate(true)
	var old_stop:bool = game.now_stop_state
	var old_scale:float = Engine.time_scale
	game.Game_Settings.Map_Background = "blue"
	game.Game_Settings.Day_Night_Cycle = true
	game.Game_Settings.Training_Mode = false
	game.now_stop_state = false
	paused = false
	Engine.time_scale = 1.0
	AudioServer.set_bus_mute(0,true)
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.set_physics_process(false)
	var cycle:Node2D = world.day_night_cycle
	check(cycle.time_text()=="12:00" and is_equal_approx(cycle.minutes,720.0),"new world starts at 12:00")
	check(cycle.daylight==1.0 and not cycle.tint.visible,"noon leaves original colors untouched")
	check(cycle.clock_label.text=="12:00" and cycle.clock_label.mouse_filter==Control.MOUSE_FILTER_IGNORE,"readable HH:MM clock never captures controls")
	for i:int in range(60): cycle.advance(1.0/60.0)
	check(cycle.time_text()=="12:01" and absf(cycle.minutes-721.0)<0.00001,"sixty 1/60-second physical steps advance exactly one minute")
	cycle.advance(59.0)
	check(cycle.time_text()=="13:00","sixty seconds advance one hour")
	cycle.set_minutes(1439.5)
	cycle.advance(0.5)
	check(cycle.time_text()=="00:00" and cycle.minutes<0.000001,"midnight wraps without a 24:00 frame")
	cycle.reset_to_noon()
	cycle.advance(1440.0)
	check(cycle.time_text()=="12:00","1440 seconds form one complete repeating day")
	cycle.advance(1440.0*3.0+65.0)
	check(cycle.time_text()=="13:05","large delta and multiple cycles retain remainder")
	cycle.set_minutes(-1.0)
	check(cycle.time_text()=="23:59","negative manual time is normalized")
	cycle.reset_to_noon()
	cycle.advance(-2.0)
	cycle.set_minutes(NAN)
	cycle.advance(INF)
	check(cycle.time_text()=="12:00","invalid/negative advances cannot corrupt time")
	for hour:int in [12,18,0,6]:
		cycle.set_minutes(hour*60.0)
		var expected:Vector2 = {12:Vector2(1,-1),18:Vector2(1,1),0:Vector2(-1,1),6:Vector2(-1,-1)}[hour]
		check(world.map_wall_light_direction.is_equal_approx(expected.normalized()),"%02d:00 sun has clockwise quadrant" % hour)
	var clockwise:bool = true
	for minute:int in range(1440):
		if CYCLE.sun_direction_at(float(minute)).cross(CYCLE.sun_direction_at(float(minute+1)))<=0.0: clockwise=false
	check(clockwise,"sun moves smoothly clockwise through all 1440 minute boundaries")
	check(CYCLE.sun_direction_at(1439.999).distance_to(CYCLE.sun_direction_at(0.0))<0.00001,"sun direction is continuous at midnight")
	var smooth_dusk:bool = true
	var previous:float = 1.0
	for minute:int in range(960,1201):
		var value:float = CYCLE.daylight_at(float(minute))
		if value>previous+0.000001 or previous-value>0.007: smooth_dusk=false
		previous=value
	check(smooth_dusk and previous==0.0,"16:00-20:00 smoothly dims without an abrupt switch")
	var smooth_dawn:bool = true
	previous=0.0
	for minute:int in range(300,481):
		var value:float = CYCLE.daylight_at(float(minute))
		if value<previous-0.000001 or value-previous>0.009: smooth_dawn=false
		previous=value
	check(smooth_dawn and previous==1.0,"05:00-08:00 smoothly returns to full daylight")
	cycle.set_minutes(0.0)
	check(cycle.tint.visible and cycle.tint.color==CYCLE.NIGHT_TINT and cycle.tint.color.b>cycle.tint.color.r and cycle.tint.color.r>0.2,"night remains visible with cool ambient tint")
	cycle.reset_to_noon()
	game.now_stop_state=true
	cycle.advance(10.0)
	check(cycle.time_text()=="12:00","Game pause freezes time")
	game.now_stop_state=false
	paused=true
	cycle.advance(10.0)
	check(cycle.time_text()=="12:00","SceneTree pause freezes time")
	paused=false
	Engine.time_scale=0.0
	cycle.advance(10.0)
	check(cycle.time_text()=="12:00","zero game speed freezes time")
	Engine.time_scale=1.0
	cycle.advance(1.0)
	check(cycle.time_text()=="12:01","resume continues without wall-clock catch-up")
	# 真实物理调度：以本帧经过的 physics frame 数比较，避免边界帧差误判。
	world.set_physics_process(true)
	await physics_frame
	var start_frames:int = Engine.get_physics_frames()
	var start_minutes:float = cycle.minutes
	for i:int in range(60): await physics_frame
	var elapsed_frames:int = Engine.get_physics_frames()-start_frames
	var elapsed_minutes:float = cycle.minutes-start_minutes
	world.set_physics_process(false)
	check(absf(elapsed_minutes-float(elapsed_frames)/Engine.physics_ticks_per_second)<0.025,"real World physics drives 1 minute per game second")
	Engine.time_scale=2.0
	world.set_physics_process(true)
	await physics_frame
	start_frames=Engine.get_physics_frames()
	start_minutes=cycle.minutes
	for i:int in range(30): await physics_frame
	elapsed_frames=Engine.get_physics_frames()-start_frames
	elapsed_minutes=cycle.minutes-start_minutes
	world.set_physics_process(false)
	Engine.time_scale=1.0
	check(absf(elapsed_minutes-2.0*float(elapsed_frames)/Engine.physics_ticks_per_second)<0.05,"2x speed advances the clock once, not twice-scaled")
	cycle.advancing=false
	var frozen:float=cycle.minutes
	for i:int in range(5): await process_frame
	check(cycle.minutes==frozen,"render frames alone never advance the clock")
	cycle.advancing=true
	cycle.set_minutes(1125.0)
	game.set_runtime_game_setting("Map_Background","grass",false)
	world.refresh_map_presentation()
	check(cycle.time_text()=="18:45" and world.map_wall_volume.visible,"theme switch preserves current time")
	var volume:Node2D = world.map_wall_volume
	var mesh_id:int = volume.mesh_node.mesh.get_instance_id()
	var initial_count:int = volume.block_count
	cycle.advance(10.0)
	check(volume.mesh_node.mesh.get_instance_id()==mesh_id and volume.block_count==initial_count,"sun/time updates never rebuild wall geometry")
	check(is_equal_approx(volume.shadow_picture.modulate.a,0.62*cycle.daylight),"sun shadows fade as night approaches")
	cycle.set_minutes(0)
	check(volume.shadow_picture.modulate.a==0.0,"no bright daytime solar shadow remains at midnight")
	game.set_runtime_game_setting("Map_Background","blue",false)
	world.refresh_map_presentation()
	check(not volume.visible and volume.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED and cycle.tint.visible,"blue stays flat and still participates in day/night")
	cycle.set_minutes(1100)
	world.rematch_last_battle()
	check(cycle.time_text()=="18:20","empty rematch leaves current time alone")
	world.reset()
	check(cycle.time_text()=="12:00" and not cycle.tint.visible,"clear/reset restores noon without leftover darkness")
	# 时间开关：关闭后隐藏右上角时间、固定正午、不推进；重新打开恢复。
	cycle.set_minutes(1100)
	game.set_runtime_game_setting("Day_Night_Cycle",false,false)
	check(not cycle.clock_layer.visible and cycle.time_text()=="12:00" and not cycle.tint.visible,"time off hides the clock and holds noon lighting")
	cycle.advance(120.0)
	cycle.set_minutes(0)
	check(cycle.time_text()=="12:00" and cycle.daylight==1.0 and not cycle.tint.visible,"time off: no advancing and no night")
	world.reset()
	check(not cycle.clock_layer.visible and cycle.time_text()=="12:00","time stays off across reset")
	game.set_runtime_game_setting("Day_Night_Cycle",true,false)
	check(cycle.clock_layer.visible,"time on shows the clock again")
	cycle.advance(60.0)
	check(cycle.time_text()=="13:00","time on resumes advancing")
	game.Game_Settings=old
	game.now_stop_state=old_stop
	Engine.time_scale=old_scale
	world.queue_free()
	await process_frame
	print("DAY_NIGHT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
