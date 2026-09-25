extends "res://tests/test_mc_bat_transform.gd"
func pixel_changes(node:CanvasItem) -> int:
	node.show()
	await RenderingServer.frame_post_draw
	var shown:Image = root.get_texture().get_image()
	node.hide()
	await RenderingServer.frame_post_draw
	var hidden:Image = root.get_texture().get_image()
	node.show()
	var count:int = 0
	for y:int in range(shown.get_height()):
		for x:int in range(shown.get_width()):
			var a:Color = shown.get_pixel(x,y)
			var b:Color = hidden.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>0.15: count += 1
	return count
func make_fang(caster:Node,origin:Vector2,hits:Dictionary) -> Node2D:
	var fang:Node2D = load("res://scripts/effects/我的世界/唤魔尖牙.gd").new()
	world.add_child(fang)
	fang.global_position = origin
	fang.setup(caster,0.25,10.0,hits)
	fang.set_physics_process(false)
	return fang
func run() -> void:
	var center:Vector2 = await setup_world()
	world.set_process(false)
	world.set_physics_process(false)
	root.size = Vector2i(540,540)
	var e:Node2D = spawn("res://scenes/characters/我的世界/唤魔者.tscn",center+Vector2(-70,0))
	e.state_machine.set_physics_process(false)
	await process_frame
	e.mc_native_animation.set_process(false)
	var camera:Camera2D = Camera2D.new()
	world.add_child(camera)
	camera.global_position = center
	camera.zoom = Vector2(7,7)
	camera.make_current()
	world.control.get_parent().hide()
	var fang:Node2D = make_fang(e,center,{})
	fang._physics_process(0.10)
	check(not fang._emerged and get_nodes_in_group("MCFangGround").is_empty(),"no debris before jaw begins emerging")
	fang._physics_process(0.02)
	check(fang._emerged and not fang._hit,"debris begins before unchanged bite time")
	var debris:Node2D = get_nodes_in_group("MCFangGround")[0]
	check(debris.get_script().resource_path.ends_with("重锤落地冲击.gd"),"reuses mace ground particles rather than copying simulation")
	if DisplayServer.get_name() == "headless":
		# Explicit synthetic sampler fixture for geometry checks only, never GPU evidence.
		var image:Image = Image.create(8,8,false,Image.FORMAT_RGBA8)
		image.fill(Color(0.3,0.5,0.2))
		debris._floor_snapshot = {"image":image,"rect":Rect2(center-Vector2(100,100),Vector2(200,200))}
		debris._build_block_particles()
	else:
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
	debris.set_process(false)
	check(debris._blocks.size()>=12 and debris._blocks.size()<=18,"small bounded 12 to 18 block burst")
	check(not debris.show_impact_ring and not debris.show_impact_streaks and debris._streaks.is_empty(),"no center ring or streak explosion")
	var low:bool = true
	var sides:Dictionary = {}
	for b:Dictionary in debris._blocks:
		low = low and b.start.length()>=7.0 and b.height>=2.0 and b.height<=4.0
		low = low and (b.landing-b.start).dot(b.start)>0.0
		sides[int(fposmod(b.start.angle(),TAU)/(PI/2.0))] = true
	check(low,"all fragments start outside center, travel outward and rise only 2 to 4 pixels")
	check(sides.size()>=3,"debris distributed around fang, not one central jet")
	var shared:Dictionary = {}
	var more:Array[Node2D] = []
	for i:int in range(6):
		var extra:Node2D = make_fang(e,center+Vector2(20+i*14,26),shared)
		extra._physics_process(0.12)
		more.append(extra)
	check(get_nodes_in_group("MCFangGround").size()==5,"one cast budgets four extra debris bursts, not one per jaw")
	for i:int in range(6):
		check(more[i]._hit or more[i]._emerged,"budgeted fangs still animate and bite on schedule")
	fang._physics_process(0.12)
	check(not fang._hit and world.get_node_or_null("CombatImpactLayer") == null,"no bite particles before closure")
	fang._physics_process(0.01)
	var layer:Node2D = world.get_node_or_null("CombatImpactLayer") as Node2D
	check(fang._hit and layer != null and layer._particles.size()==12,"jaw closure emits exactly twelve native CRIT even without victim")
	check(world.get_children().filter(func(c): return c.name == "CombatImpactLayer").size()==1,"bite burst reuses the single world batch layer")
	check(layer.CRITICAL_TEXTURE.resource_path.ends_with("Images/paricle/critical_hit.png"),"uses pixel-verified native CRIT texture")
	var neutral:bool = true
	for p:Dictionary in layer._particles:
		var tint:Color = p["color"]
		neutral = neutral and absf(tint.r-tint.g)<0.01 and absf(tint.g-tint.b)<0.01 and tint.r>=0.85
	check(neutral,"fang sparks stay neutral like the vanilla CRIT sprite, not the damage-crit brown")
	var sizing:bool = true
	for p:Dictionary in layer._particles:
		sizing = sizing and float(p["size"])>=5.6 and float(p["size"])<=7.55
	check(sizing,"fang CRIT keeps the shared size ramp instead of a bespoke sprite size")
	fang._physics_process(0.01)
	check(layer._particles.size()==12 and get_nodes_in_group("MCFangGround").size()==5,"both stages are one-shot")
	check(layer.critical_particle_count(50.0)==0 and layer.critical_particle_count(51.0)>0,"ordinary damage feedback thresholds unchanged")
	game.now_stop_state = true
	var age:float = fang._age
	fang._physics_process(0.2)
	check(fang._age==age,"pause cannot retrigger fang stages")
	game.now_stop_state = false
	if DisplayServer.get_name() != "headless":
		debris._elapsed=0.08
		debris.queue_redraw()
		layer.set_process(false)
		for p:Dictionary in layer._particles: p.born=Time.get_ticks_usec()+5000000
		layer.queue_redraw()
		var ground_pixels:int = await pixel_changes(debris)
		var bite_pixels:int = await pixel_changes(layer)
		print("FANG_GPU ground_pixels=",ground_pixels," bite_pixels=",bite_pixels)
		check(ground_pixels>30 and bite_pixels>30,"both emergence debris and bite particles draw on actual GPU")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://fang_particles_gpu.png")
	layer._prune(Time.get_ticks_usec()+10000000)
	check(layer._particles.is_empty(),"native particles clear after lifetime")
	debris._process(5.0)
	for extra:Node2D in more: extra._physics_process(1.0)
	fang._physics_process(1.0)
	check(debris.is_queued_for_deletion() and fang.is_queued_for_deletion(),"detached blocks and fang clean up independently")
	print("FANG_PARTICLES_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
