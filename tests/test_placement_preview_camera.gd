extends "res://tests/test_rotation_timed_flow.gd"
# Placement preview must sit exactly where the character lands (the release input event point) at every zoom.
# Game samples the mouse world position BEFORE World.process_always(): process_always rewrites the Camera2D
# zoom immediately, and a later camera owner (the battle recorder composition) restores the displayed camera in
# the same frame. Sampling in between used a transform the player never saw, so the preview drifted from the
# real drop point, more when the view was larger.
var late_owner:Node=null
var owner_factor:float=0.0
var owner_shift:Vector2=Vector2.ZERO
func owner_step() -> void:
	if owner_factor<=0.0 or not is_instance_valid(world):return
	var cam:Camera2D=world.camera_2d
	cam.zoom=Vector2.ONE*world.get_effective_camera_zoom()*owner_factor
	cam.global_position=world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()+owner_shift
	cam.force_update_scroll()
func push_mouse(p:Vector2) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=p;motion.global_position=p
	Input.parse_input_event(motion)
func sample_matches(tag:String,window_point:Vector2) -> void:
	push_mouse(window_point)
	for f in 4:await process_frame
	var seen:Transform2D=world.get_canvas_transform()
	var expected:Vector2=seen.affine_inverse()*root.get_mouse_position()
	await process_frame
	var got:Vector2=game._placement.mouse_poi
	check(got.distance_to(expected)<0.05,"%s: preview position = world point under the cursor in the displayed view (got %s expected %s)"%[tag,got,expected])
func run() -> void:
	create_timer(60,true,false,true).timeout.connect(func():print("PLACEMENT_PREVIEW_TIMEOUT");quit(2))
	game=root.get_node("Game");saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false;game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Development_Mode=false;game.Game_Settings.Map_Background="blue"
	game.now_stop_state=false;AudioServer.set_bus_mute(0,true)
	Input.use_accumulated_input=false
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT);root.add_child(world)
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.free()
	world._mc_prewarmer=null
	await process_frame
	world.now_choose_map="Map10x10";world.refresh_map_presentation()
	# A node processed after everything else owns the displayed camera, like the recorder composition.
	var owner_script:=GDScript.new()
	owner_script.source_code="extends Node\nvar step:Callable\nfunc _process(_delta:float) -> void:\n\tif step.is_valid(): step.call()\n"
	owner_script.reload()
	late_owner=Node.new();late_owner.name="LateCameraOwner";late_owner.process_priority=100000
	late_owner.set_script(owner_script);late_owner.set("step",owner_step);root.add_child(late_owner)
	var window_point:Vector2=Vector2(root.size)*Vector2(0.22,0.3)
	for z in [1.0,0.35,2.5]:
		world.toolbar_zoom_multiplier=z;world.mouse_offset=Vector2.ZERO
		owner_factor=1.45;owner_shift=Vector2(18,-11)
		for f in 3:await process_frame
		# The scenario is real: right after process_always the canvas transform is not the displayed one.
		push_mouse(window_point)
		for f in 3:await process_frame
		var shown:Vector2=world.get_canvas_transform().affine_inverse()*root.get_mouse_position()
		world.process_always(0.0)
		var mid_frame:Vector2=world.get_global_mouse_position()
		check(mid_frame.distance_to(shown)>1.0,"zoom x%.2f: sampling after process_always would be off by %.1f world units"%[z,mid_frame.distance_to(shown)])
		await sample_matches("zoom x%.2f with late camera owner"%z,window_point)
		owner_factor=0.0
		await sample_matches("zoom x%.2f plain world camera"%z,window_point+Vector2(37,23))
	print("PLACEMENT_PREVIEW_RESULT checks=%d failures=%d"%[checks,failures])
	late_owner.queue_free()
	game.Game_Settings=saved;game.now_stop_state=false
	if is_instance_valid(world):world.queue_free()
	current_scene=null
	await process_frame;await process_frame
	quit(0 if failures==0 else 1)
