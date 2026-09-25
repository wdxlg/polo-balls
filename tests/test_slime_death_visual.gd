extends SceneTree
## Actual GPU readback of the genuine slime landing ring/chips at death.

var checks:int=0
var failures:int=0

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("SLIME_DEATH_GPU_FAIL "+label)

func pixels_from_effect(fx:Node2D) -> Dictionary:
	await RenderingServer.frame_post_draw
	var showing:Image=root.get_texture().get_image()
	fx.hide()
	await RenderingServer.frame_post_draw
	var hidden:Image=root.get_texture().get_image()
	fx.show()
	var origin:Vector2=(root.get_final_transform()*fx.get_global_transform_with_canvas())*Vector2.ZERO
	var radius:int=maxi(28,ceili(fx.reach*2.2))
	var left:int=clampi(int(origin.x)-radius,0,showing.get_width()-1)
	var right:int=clampi(int(origin.x)+radius,0,showing.get_width()-1)
	var top:int=clampi(int(origin.y)-radius,0,showing.get_height()-1)
	var bottom:int=clampi(int(origin.y)+radius,0,showing.get_height()-1)
	var changed:int=0
	var green:int=0
	for y:int in range(top,bottom+1):
		for x:int in range(left,right+1):
			var drawn:Color=showing.get_pixel(x,y)
			var blank:Color=hidden.get_pixel(x,y)
			if absf(drawn.r-blank.r)+absf(drawn.g-blank.g)+absf(drawn.b-blank.b)<0.10: continue
			changed+=1
			if drawn.g>0.19 and drawn.g>drawn.r*1.22 and drawn.g>drawn.b*1.22: green+=1
	return {"changed":changed,"green":green,"origin":origin,"radius":radius}

func run() -> void:
	create_timer(45,true,false,true).timeout.connect(func(): push_error("SLIME_DEATH_GPU_TIMEOUT"); quit(2))
	var game:Node=root.get_node("Game")
	var original:Dictionary=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Camera_Move=false
	game.Game_Settings.Shaking_Camera=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	root.size=Vector2i(540,960)
	var world:Node2D=(load("res://scenes/world.tscn") as PackedScene).instantiate() as Node2D
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	# Keep the scene cache alive for split_scene(), but the pixel-only fixture
	# does not need its asynchronous 23-character render warm-up loop.
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.set_process(false)
	world.control.get_parent().hide()
	world.now_choose_map="Map10x10"
	world.refresh_map_presentation()
	var center:Vector2=world.return_map_world_rect(world.map_group["Map10x10"]).get_center()
	world.camera_2d.global_position=center
	world.camera_2d.force_update_scroll()
	var slime:Node2D=(load("res://scenes/characters/我的世界/史莱姆.tscn") as PackedScene).instantiate() as Node2D
	slime.Team="Team0"
	slime.position=center
	world.add_child(slime,true)
	slime.state_machine.set_physics_process(false)
	# A direct Die call also represents death; it must emit the same detached FX.
	slime.Die()
	var bursts:Array[Node]=[]
	for node:Node in get_nodes_in_group("MCSlimeJumpFX"):
		if node.linger_after_death: bursts.append(node)
	check(bursts.size()==1,"large slime death creates exactly one landing FX")
	var fx:Node2D=bursts[0] as Node2D if bursts.size()==1 else null
	if fx!=null:
		check(fx.landing and fx.ring!=null and fx.particles.size()>=12,"real landing ring and original slimeball particles reused")
	slime.free()
	game.now_stop_state=true
	# Freeze unrelated camera/children/death pose so the GPU difference on the
	# actual battlefield comes from the impact FX, not moving green descendants.
	world.set_process(false)
	world.set_physics_process(false)
	world.camera_2d.set_process(false)
	world.camera_2d.set_physics_process(false)
	for actor:Node in get_nodes_in_group("Ball"):
		actor.set_process(false)
		actor.set_physics_process(false)
		actor.state_machine.process_mode=Node.PROCESS_MODE_DISABLED
	for node:Node in get_nodes_in_group("MCDeathPose"):
		node.hide()
	for node:Node in get_nodes_in_group("MCDeathSmoke"):
		node.hide()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if fx!=null:
		var live_pixels:Dictionary=await pixels_from_effect(fx)
		print("SLIME_DEATH_LIVE_GPU_METRIC ",live_pixels)
		check(live_pixels.green>3,"death burst is actually visible on the battlefield, not just in isolation")
	var overlay:CanvasLayer=CanvasLayer.new()
	overlay.layer=200
	root.add_child(overlay)
	var backdrop:ColorRect=ColorRect.new()
	backdrop.color=Color(0.07,0.07,0.07,1.0)
	backdrop.z_index=-4096
	backdrop.size=root.get_visible_rect().size
	overlay.add_child(backdrop)
	if fx!=null:
		fx.reparent(overlay,false)
		fx.position=root.get_visible_rect().size*0.5
		await process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var pixels:Dictionary=await pixels_from_effect(fx)
		print("SLIME_DEATH_GPU_METRIC ",pixels)
		check(pixels.changed>16,"genuine death effect changes visible GPU pixels")
		check(pixels.green>10,"death animation renders bright green landing chips/ring")
		for frame:int in range(120):
			if not is_instance_valid(fx): break
			await process_frame
		check(not is_instance_valid(fx),"death FX fades even after owner removal and match stop")
	if is_instance_valid(world._mc_prewarmer):
		for path:Variant in world._mc_prewarmer._paths.values():
			var status:int=ResourceLoader.load_threaded_get_status(str(path))
			if status in [ResourceLoader.THREAD_LOAD_IN_PROGRESS,ResourceLoader.THREAD_LOAD_LOADED]:
				ResourceLoader.load_threaded_get(str(path))
	world.queue_free()
	overlay.queue_free()
	await process_frame
	game.Game_Settings=original
	print("SLIME_DEATH_GPU_RESULT checks=",checks," failures=",failures)
	quit(1 if failures>0 else 0)
