extends SceneTree
# 选地图列表：像素滚动条样式 + 中键按住拖动滚动。
var checks:int = 0
var failures:int = 0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error(label)
func run() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	for i in range(4): await process_frame
	var control:Control = world.control
	var scroll:ScrollContainer = control.map_scroll
	var box:VBoxContainer = control.map_box
	control.map.visible = true
	check(box.get_child_count() >= 8,"map list contains all maps (%d)" % box.get_child_count())
	# 保证内容超出可视区域以便测试滚动。
	for i in range(30):
		var b := Button.new(); b.text = "pad%d" % i; b.custom_minimum_size.y = 20; box.add_child(b)
	control._configure_map_middle_drag()
	await process_frame
	await process_frame
	var bar:VScrollBar = scroll.get_v_scroll_bar()
	check(bar.max_value - bar.page > 50.0,"map list overflows so the scrollbar is active")
	check(bar.has_theme_stylebox_override("grabber") and bar.has_theme_icon_override("increment"),"map scrollbar uses the pixel style shared with the character list")
	check(scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_ALWAYS,"vertical scroll mode matches the character list")
	print("DBG scroll=",scroll.size," box=",box.size," bar max=",bar.max_value," page=",bar.page)
	# 模拟在某个地图按钮上按下中键并向上拖动。
	var target:Button = box.get_child(1) as Button
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE; press.pressed = true
	target.gui_input.emit(press)
	check(control._map_middle_dragging,"middle press on a map button starts drag")
	var before:int = scroll.scroll_vertical
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(0,-40)
	control._input(motion)
	await process_frame
	check(scroll.scroll_vertical == before+40,"dragging upward scrolls the list down by the same distance (%d -> %d)" % [before,scroll.scroll_vertical])
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_MIDDLE; release.pressed = false
	control._input(release)
	check(not control._map_middle_dragging,"middle release anywhere ends drag")
	var after:int = scroll.scroll_vertical
	control._input(motion)
	await process_frame
	check(scroll.scroll_vertical == after,"motion without middle button held no longer scrolls")
	print("MAP_SCROLL checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
