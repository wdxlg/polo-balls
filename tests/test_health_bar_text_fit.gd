extends SceneTree
var checks:int = 0
var failures:int = 0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func run() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	world.control.hide()
	var unit:Node2D = load("res://scenes/characters/我的世界/蠹虫.tscn").instantiate()
	unit.Team = "Team0"
	unit.Max_health = 100
	world.add_child(unit,true)
	await process_frame
	await process_frame
	var hb:Control = unit.health_bar
	var label:Label = hb.label
	check(label.get_theme_color("font_color") == Color.BLACK,"health digits have black fill")
	check(label.get_theme_color("font_outline_color") == Color.WHITE,"health digits have white outline")
	check(label.get_theme_constant("outline_size") == 120,"white outline is thinner (120): %d" % label.get_theme_constant("outline_size"))
	var base:int = hb._label_base_font_size
	check(base == 900,"base font size recorded (%d)" % base)
	var font:Font = label.get_theme_font("font")
	var bar_width:float = hb.health_bar.size.x * hb.health_bar.scale.x
	for value:int in [7,100,1000,12345,999999]:
		hb._set_label_text(str(value))
		var fs:int = label.get_theme_font_size("font_size")
		var w:float = font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_CENTER,-1,fs).x + label.get_theme_constant("outline_size") * 2.0
		check(w <= bar_width + 0.5,"'%d' fits inside the health bar incl. outline (w=%.0f/%.0f fs=%d)" % [value,w,bar_width,fs])
		check(fs <= base,"font never grows beyond base for %d" % value)
	hb._set_label_text("7")
	check(label.get_theme_font_size("font_size") == base,"short text restores base font size")
	hb.set_invincible_display(true,false)
	check(label.text == "INF" and label.get_theme_constant("outline_size") >= 220,"INF keeps its special thick outline")
	hb.set_invincible_display(false)
	check(label.get_theme_constant("outline_size") == hb._normal_label_outline_size,"leaving INF restores normal outline")
	check(label.get_theme_color("font_color") == Color.BLACK and label.get_theme_color("font_outline_color") == Color.WHITE,"leaving INF restores black text and white outline")
	print("HB_TEXT checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
