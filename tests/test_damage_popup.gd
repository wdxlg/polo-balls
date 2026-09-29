extends SceneTree
var checks:int = 0
var failures:int = 0
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("POPUP_FAIL "+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var script:Script = load("res://scripts/damage_text.gd")
	var packed:PackedScene = load("res://scenes/damage_text.tscn")
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	root.size = Vector2i(1100,650)
	root.content_scale_size = Vector2i(1100,650)
	var bg := ColorRect.new()
	bg.size = Vector2(1100,650)
	bg.color = Color("202b38")
	world.add_child(bg)
	for kind:StringName in [&"damage",&"block",&"heal"]:
		var a:Color = script.amount_color(1,kind)
		var b:Color = script.amount_color(500,kind)
		check(a != b,"different endpoints "+str(kind))
		check(script.amount_color(1e9,kind).is_equal_approx(b),"high clamp "+str(kind))
		check(script.amount_color(INF,kind).is_equal_approx(b),"INF endpoint "+str(kind))
		var previous:Color = a
		for amount:int in [1,10,30,100,250,500]:
			var color:Color = script.amount_color(amount,kind)
			check(color.g<=previous.g+0.0001 if kind!=&"heal" else color.g>=previous.g-0.0001,"monotonic "+str(kind))
			previous=color
	var unit:Node2D = load("res://scenes/ball.tscn").instantiate()
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	unit.position = Vector2(400,300)
	world.add_child(unit)
	unit.hide()
	var hb:Node = unit.health_bar
	var min_x:float=INF
	var max_x:float=-INF
	var min_y:float=INF
	var max_y:float=-INF
	for i:int in range(100):
		var p:Vector2 = hb._floating_text_point()
		var local:Vector2 = unit.image.to_local(p)
		check(unit.image.get_rect().has_point(local),"spawn on visual bounds")
		min_x=minf(min_x,p.x);max_x=maxf(max_x,p.x)
		min_y=minf(min_y,p.y);max_y=maxf(max_y,p.y)
	check(max_x-min_x>5 and max_y-min_y>5,"random points spread across both axes")
	hb._spawn_damage_text(30,hb.health_bar)
	hb._spawn_damage_text(100,hb.block_bar)
	hb._spawn_heal_text(250)
	check(get_node_count_in_group("__damage_text_runtime")==3,"all existing HealthBar routes")
	await process_frame
	await process_frame
	for popup:Node in get_nodes_in_group("__damage_text_runtime"):
		check(popup.get_theme_color("font_color").is_equal_approx(script.amount_color(float(popup.text),popup._kind)),"route colour "+popup.text)
		popup._flight.kill()
		var apex:float = -popup._flight_velocity.y/popup._gravity
		popup._sample_flight(0.0)
		var start:Vector2 = popup.global_position
		popup._sample_flight(apex)
		var top:Vector2 = popup.global_position
		check(top.y<start.y-15,"rises to apex")
		check(is_equal_approx(popup.modulate.a,1.0),"readable before descent")
		popup._sample_flight(popup._lifetime*0.8)
		check(popup.global_position.y>top.y and popup.modulate.a<1 and popup.modulate.a>0,"falls while fading")
		popup._sample_flight(popup._lifetime)
		check(is_zero_approx(popup.modulate.a),"ends transparent")
		popup.queue_free()
	await process_frame
	# A live popup must clean itself up without manual intervention.
	hb._spawn_heal_text(20)
	await create_timer(1.5).timeout
	check(get_node_count_in_group("__damage_text_runtime")==0,"automatic cleanup")
	# Actual rendered palette and parabola samples, using the production script.
	var amounts:Array[int] = [1,10,30,100,250,500]
	for row:int in range(3):
		var kind:StringName = [&"damage",&"block",&"heal"][row]
		var label:=Label.new()
		label.text = ["伤害：黄色 → 红色","防御受损：浅灰 → 深灰","治疗：深绿 → 浅绿"][row]
		label.position = Vector2(45,25+row*125)
		label.add_theme_font_size_override("font_size",24)
		world.add_child(label)
		for col:int in range(6):
			var popup:Label = packed.instantiate()
			popup.set_multiplayer_authority(99)
			popup.configure_amount(amounts[col],kind)
			popup.add_theme_font_size_override("font_size",32)
			popup.position = Vector2(70+col*165,70+row*125)
			world.add_child(popup)
	var title:=Label.new()
	title.text="轨迹采样：起点 → 上升 → 最高点 → 下落渐隐"
	title.position=Vector2(45,410)
	title.add_theme_font_size_override("font_size",24)
	world.add_child(title)
	for i:int in range(6):
		var popup:Label=packed.instantiate()
		popup.set_multiplayer_authority(99)
		popup.configure_amount(100,&"damage")
		popup.add_theme_font_size_override("font_size",32)
		world.add_child(popup)
		popup._lifetime=1.0
		popup._flight_origin=Vector2(75,555)
		popup._flight_velocity=Vector2(860,-230)
		popup._gravity=550.0
		popup._sample_flight(0.05+i*0.175)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/damage_popup_preview.png")
	print("DAMAGE_POPUP checks=",checks," failures=",failures)
	world.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures==0 else 1)
