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
	check(label.get_theme_color("font_color") == Color.BLACK,"full-health digits start opaque pure black")
	check(label.get_theme_constant("outline_size") == 0 and label.get_theme_color("font_outline_color").a == 0.0,"normal health digits have no outline")
	check(label.get_theme_color("font_shadow_color").a == 0.0 and label.get_theme_constant("shadow_offset_x") == 0 and label.get_theme_constant("shadow_offset_y") == 0 and label.get_theme_constant("shadow_outline_size") == 0,"normal health digits have no shadow or halo")
	label.add_theme_constant_override("outline_size",120)
	label.add_theme_color_override("font_outline_color",Color.WHITE)
	label.add_theme_color_override("font_shadow_color",Color(0.0,0.0,0.0,0.58))
	hb._prepare_normal_health_label_style()
	check(label.get_theme_constant("outline_size") == 0 and label.get_theme_color("font_outline_color").a == 0.0 and label.get_theme_color("font_shadow_color").a == 0.0,"embedded legacy bar labels normalize back to no outline or shadow")
	var base:int = hb._label_base_font_size
	check(base == 900,"base font size recorded (%d)" % base)
	var font:Font = label.get_theme_font("font")
	var bar_width:float = hb.health_bar.size.x * hb.health_bar.scale.x
	for value:int in [7,100,1000,12345,999999]:
		hb._set_label_text(str(value))
		var fs:int = label.get_theme_font_size("font_size")
		var w:float = font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_CENTER,-1,fs).x
		check(w <= bar_width + 0.5,"'%d' fits inside the health bar without outline (w=%.0f/%.0f fs=%d)" % [value,w,bar_width,fs])
		check(fs <= base,"font never grows beyond base for %d" % value)
	hb._set_label_text("7")
	check(label.get_theme_font_size("font_size") == base,"short text restores base font size")
	hb.suppress_floating_text = true
	for sample:Array in [[100,51,100,Color.BLACK],[51,50,100,Color.WHITE],[50,49,100,Color.WHITE],[49,51,100,Color.BLACK],[51,50,101,Color.WHITE],[50,51,101,Color.BLACK]]:
		hb.health_changed.emit(sample[0],sample[1],sample[2],false)
		check(label.text == str(sample[1]) and label.get_theme_color("font_color") == sample[3],"%d/%d digits use exact 50%% threshold" % [sample[1],sample[2]])
	hb.health_changed.emit(100,40,100,true)
	var tween_ok:bool = true
	var started:int = Time.get_ticks_msec()
	while hb._bar_tweens.has(hb.health_bar) and hb._bar_tweens[hb.health_bar].is_running() and Time.get_ticks_msec()-started < 1300:
		await process_frame
		var shown:int = label.text.to_int()
		tween_ok = tween_ok and label.get_theme_color("font_color") == (Color.BLACK if shown > 50 else Color.WHITE)
	check(tween_ok and label.text == "40" and label.get_theme_color("font_color") == Color.WHITE,"animated health number crosses 50% without a color lag")
	unit.health = 40
	hb.health_changed.emit(40,40,100,false)
	hb.set_karma_preview("threshold-test",6.0)
	check(label.get_theme_color("font_color") == Color.WHITE,"KARMA overlay does not turn <=50% text black or purple")
	hb.clear_karma_preview("threshold-test")
	check(label.get_theme_color("font_color") == Color.WHITE,"clearing KARMA preserves the <=50% white text")
	hb.set_invincible_display(true,false)
	check(label.text == "INF" and label.get_theme_constant("outline_size") >= 220 and label.get_theme_color("font_color") != Color.WHITE,"INF keeps its separate gold outlined style")
	hb.set_invincible_display(false)
	check(label.get_theme_constant("outline_size") == 0 and label.get_theme_color("font_shadow_color").a == 0.0,"leaving INF restores no outline and no shadow")
	check(label.get_theme_color("font_color") == Color.WHITE,"leaving INF at <=50% immediately restores pure white digits")
	unit.health = 80
	hb.health_changed.emit(40,80,100,false)
	check(label.get_theme_color("font_color") == Color.BLACK,"healing above 50% restores pure black digits")
	print("HB_TEXT checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
