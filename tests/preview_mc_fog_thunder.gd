extends "res://tests/preview_mc_fog_clouds.gd"
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(45).timeout.connect(func(): finish(2))
	world.control.hide()
	world.set_process(false)
	world.set_physics_process(false)
	world.camera_2d.enabled = false
	camera = Camera2D.new()
	world.add_child(camera)
	camera.position = center
	camera.zoom = Vector2.ONE
	camera.make_current()
	var man:Node2D = actor("雾中人",center)
	fog = man.fog
	fog.set_process(false)
	fog.fog_alpha = 0.985
	fog._process(0.1)
	var backdrop := Polygon2D.new()
	backdrop.polygon = PackedVector2Array([center+Vector2(-2000,-2000),center+Vector2(2000,-2000),center+Vector2(2000,2000),center+Vector2(-2000,2000)])
	backdrop.z_index = 89
	world.add_child(backdrop)
	man.rage_origin = center
	man.rage_left = 4.0
	man.lightning_wait = true
	man.set_phase(man.Phase.RAGE)
	man.emit_event("thunder_warning",center)
	check(man.lightning_visual.scene_file_path=="res://scenes/effects/我的世界/雷电.tscn","uses exact creeper lightning scene")
	check(man.lightning_wait and fog.storms.is_empty() and not man.lightning_visual._impact_started,"warning thunder occurs before bolt and clearing")
	man.lightning_visual._process(0.69)
	check(not man.lightning_wait and man.lightning_visual._impact_started,"shared effect impact starts explosion and clearing together")
	center = man.rage_origin
	check(man.lightning_visual.is_visible_in_tree(),"shared lightning stays visible when actor turns to mist")
	man.charge_fx.hide() # Isolate terrain fog from the replacement mist body too.
	# Isolate fog transmittance from the shared bolt's bright impact ring/streaks.
	man.lightning_visual.hide()
	for child:Node in man.charge_fx.get_children():
		if child is CanvasItem and str(child.name).begins_with("CreeperLightningWhiteLines"): child.hide()
	check(fog.storms.size()==1 and fog.cloud_material.get_shader_parameter("storm_count")==1,"thunder publishes clearing immediately without a field tick")
	check(man.clear_radius==180.0,"clearing radius reduced to 180")
	man.apply_phase_flags()
	check(fog.storms.size()==1,"repeated snapshots do not restart thunder")
	backdrop.color = Color.BLACK
	var black:Image = await capture()
	backdrop.color = Color.WHITE
	var white:Image = await capture()
	var transmission:float = difference(black,white,center+Vector2(60,0))
	print("THUNDER INSTANT TRANSMISSION=",transmission)
	var feathered:int = 0
	for x:int in range(100,240,5):
		var t:float = difference(black,white,center+Vector2(x,0))
		if t>0.02 and t<0.98: feathered += 1
	print("FEATHER SAMPLES=",feathered)
	check(feathered>=5,"wide cloud rim has graded transparency rather than hard clipping")
	check(transmission>0.98,"thunder completely removes fog immediately over a broad region")
	var low:float = INF
	var high:float = 0.0
	for i:int in range(64):
		var edge:float = fog.storm_edge(center,180.0,TAU*i/64.0)
		low = minf(low,edge)
		high = maxf(high,edge)
	check(high-low>35.0,"thunder rim is genuinely irregular rather than circular")
	var anchor:Vector2 = center+Vector2(100,0)
	var outward:float = fog.storm_push(anchor).length()
	fog._process(0.4)
	check(outward>40.0,"cloud centers are pushed into outer rim")
	man.set_phase(man.Phase.STALK)
	fog.advance_storms(1.6)
	check(fog.storm_push(anchor).length()<outward,"return flow moves cloud targets from exterior toward interior")
	backdrop.color = Color.BLACK
	black = await capture()
	backdrop.color = Color.WHITE
	white = await capture()
	var outer:float = difference(black,white,center+Vector2(190,0))
	var inner:float = difference(black,white,center+Vector2.ZERO)
	print("THUNDER RETURN outer=",outer," inner=",inner)
	check(outer<0.2 and inner>0.98,"outside fills first while center remains open")
	fog.advance_storms(1.7)
	check(fog.storms.is_empty(),"inward front eventually closes completely")
	backdrop.queue_free()
	man.health_bar._spawn_amount_text(10.0,&"damage")
	check(man.disappear(),"discovery still triggers normal disappearance")
	check(not man.is_visible_in_tree() and not man.health_bar.is_visible_in_tree(),"vanished actor and entire health HUD are hidden")
	check(not man.eye_fx.is_visible_in_tree() and not man.effects.is_visible_in_tree(),"eyes trails and attached effects cannot reveal vanished location")
	var popup_visible:bool = false
	for popup:Node in get_nodes_in_group("__damage_text_runtime"):
		var ref:Variant = popup.get_meta("combat_visual_owner",null)
		if ref is WeakRef and ref.get_ref()==man and popup.is_visible_in_tree(): popup_visible = true
	check(not popup_visible and man.health_bar.suppress_floating_text,"existing popups hidden and self-cost popup suppressed")
	check(man.try_reappear() and man.visible and not man.health_bar.suppress_floating_text,"reappearance restores root and normal HUD feedback")
	finish(0 if failures==0 else 1)
