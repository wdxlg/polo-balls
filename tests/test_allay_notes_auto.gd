extends "res://tests/test_allay_extended.gd"
func run() -> void:
	game=root.get_node("Game"); saved=game.Game_Settings.duplicate(true); saved_stop=game.now_stop_state
	game.Game_Settings.Map_Background="blue"
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(40.0).timeout.connect(func(): finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"; world.refresh_map_presentation(); world.control.hide()
	await create_timer(0.3).timeout
	var center:Vector2=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var allay:Node=spawn("res://scenes/characters/我的世界/悦灵.tscn",center,"Team0")
	var enemy:Node=spawn("res://scenes/ball.tscn",center+Vector2(125,0),"Team1")
	allay.process_mode=Node.PROCESS_MODE_DISABLED; enemy.process_mode=Node.PROCESS_MODE_DISABLED
	allay.player_control_peer_id=1; allay.Can_Attack=false
	allay.notes=2; allay._generate_left=100.0
	allay._note_cloud.resize(2,center)
	allay._note_cloud.positions[0]=center+Vector2(-30,0)
	allay._note_cloud.positions[1]=center+Vector2(30,0)
	allay.step_mob(0.01)
	check(allay.notes==1,"player-controlled allay auto fires without attack input")
	check(allay._note_cloud.positions[0]==center+Vector2(-30,0),"nearest eligible orbit note fires rather than first stored note")
	var shots:Array[Node]=get_nodes_in_group("AllayFlyingNote")
	check(shots.size()==1,"one automatic launch respects firing cadence")
	var shot:Node=shots[0]
	check(shot.target_ref.get_ref()==enemy,"automatic target is the nearby enemy")
	check(shot.global_position==center+Vector2(30,0),"automatic launch begins at its own note position")
	check(shot.z_index>100 and not shot.z_as_relative and shot.get_meta("submission_allow_map_escape",false),"flying note bypasses map mask and out-of-bounds cleanup")
	check(allay._note_visual.z_index>100 and not allay._note_visual.z_as_relative,"orbit note has its own unclipped visual layer")
	check(allay.z_index<90,"allay body is not lifted above the map mask")
	shot._create_trail()
	check(shot._trail.z_index>100 and not shot._trail.z_as_relative,"note trail is also drawn above the map mask")
	shot.queue_free()
	allay._note_left=0.0
	allay.step_mob(0.01)
	check(allay.notes==1,"note outside its own trigger radius waits")
	enemy.global_position=center+Vector2(30,0)
	allay.dizziness=true; allay.step_mob(0.01)
	check(allay.notes==1,"stun still prevents automatic firing")
	allay.dizziness=false
	game.now_stop_state=true; allay.step_mob(0.5)
	check(allay.notes==1,"pause prevents automatic firing")
	game.now_stop_state=false
	allay.step_mob(0.01)
	check(allay.notes==0,"automatic firing resumes when able to act")
	var smooth:Script=load("res://scripts/characters/我的世界/allay/smooth_orbit.gd")
	var cloud:RefCounted=smooth.new()
	cloud.resize(2,Vector2.ZERO)
	cloud.advance(2,Vector2(100,0),0.0,0.016,0.0,0.0,1.0,0.0,0.0)
	check(cloud.positions[0].x>0.0 and cloud.positions[0].x<10.0,"follow starts gradually rather than snapping")
	var before:Vector2=cloud.positions[0]
	var velocity:Vector2=cloud.velocities[0]
	cloud.advance(2,Vector2(-100,0),0.0,0.0,0.0,0.0,1.0,0.0,0.0)
	check(cloud.positions[0]==before and cloud.velocities[0]==velocity,"paused spring preserves both position and velocity")
	cloud.take_at(0,Vector2.ZERO)
	check(cloud.positions.size()==1 and cloud.velocities.size()==1 and cloud.velocities[0]==velocity,"consumption keeps remaining follower state aligned")
	var endpoints:Array[Vector2]=[]
	for fps:int in [30,60,120]:
		var follower:RefCounted=smooth.new(); follower.resize(1,Vector2.ZERO)
		for i:int in fps: follower.advance(1,Vector2(100,0),0.0,1.0/fps,0.0,0.0,1.0,0.0,0.0)
		endpoints.append(follower.positions[0])
	check(endpoints[0].distance_to(endpoints[2])<0.001,"spring response is frame-rate independent for a fixed goal")
	cloud.clear()
	check(cloud.positions.is_empty() and cloud.velocities.is_empty(),"spring cleanup resets all follower state")
	allay.queue_free(); enemy.queue_free()
	await create_timer(3.0).timeout
	print("ALLAY_NOTES_AUTO_TEST checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
