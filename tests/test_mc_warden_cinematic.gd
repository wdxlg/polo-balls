extends "res://tests/test_mc_warden_sound.gd"
func run() -> void:
	var o:Vector2=await setup_world()
	create_timer(90).timeout.connect(func():finish(2))
	var w:Node2D=actor("监守者",o)
	var enemy:Node2D=dummy(o+Vector2(170,0))
	await process_frame
	world.get_node("MCBattleNoise").set_physics_process(false)
	w.form=w.Form.AWAKE; w._form_stats(true)
	w.hear_noise(enemy,enemy.global_position,"attack",120)
	check(w.begin_sonic(),"real sonic charge starts")
	var screen:Node=world.get_node("MCWardenScreenFX")
	screen.set_process(false)
	var before:Vector2=w.global_position
	screen._process(0.575)
	check(screen.zoom_amount>0.02 and screen.zoom_amount<0.05,"charge subtly zooms toward caster halfway through windup")
	check(w.global_position==before,"presentation zoom never displaces gameplay body")
	screen._process(0.575)
	check(is_equal_approx(screen.zoom_amount,0.07),"full charge zoom is bounded at seven percent")
	check(screen.shader_material.get_shader_parameter("focus")==screen.focus,"screen sampling focus follows caster's screen position")
	game.now_stop_state=true; var zoom:float=screen.zoom_amount; screen._process(1)
	check(screen.zoom_amount==zoom and not screen.rect.visible,"pause freezes cinematic timing and hides temporary compositor")
	game.now_stop_state=false
	w.sonic_left=0; w.release_sonic(); halt_waves(w)
	check(screen.release_left==0.6 and screen.inversion_left>0,"firing starts elastic return and preserves brief inversion")
	screen._process(0.15)
	check(screen.zoom_amount<0,"return slightly overshoots original size for elastic recoil")
	screen._process(0.46)
	check(screen.zoom_amount==0 and not screen.rect.visible,"recoil restores exact original framing with no residual scaling")
	# Known flat background beneath compositor to verify actual darkening on GPU.
	var layer:=CanvasLayer.new(); layer.layer=119; world.add_child(layer)
	var bg:=ColorRect.new(); layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); bg.color=Color(0.4,0.5,0.6)
	await process_frame; await RenderingServer.frame_post_draw
	var base:Color=root.get_texture().get_image().get_pixel(20,20)
	w._cancel_attacks(true); w.form=w.Form.DORMANT; w.signals_received=5
	check(w.begin_emergence(),"actual summon starts darkness and expanding blue ring")
	screen._process(0.07)
	var radius:float=screen.shader_material.get_shader_parameter("ring_radius")
	check(radius>0 and float(screen.shader_material.get_shader_parameter("ring_alpha"))>0,"blue circle starts from summoner and expands immediately")
	var projected:Vector2=(w.get_canvas_transform()*w.global_position)/root.get_visible_rect().size
	check(Vector2(screen.shader_material.get_shader_parameter("ring_center")).is_equal_approx(projected),"blue ring originates at the summoner's projected position")
	screen._process(0.07)
	check(is_equal_approx(float(screen.shader_material.get_shader_parameter("darkness")),0.55),"screen quickly darkens first before later pulses")
	await process_frame; await RenderingServer.frame_post_draw
	var dark:Color=root.get_texture().get_image().get_pixel(20,20)
	check(dark.r<base.r*0.6 and dark.g<base.g*0.6 and dark.b<base.b*0.6,"GPU output darkens instead of flashing white")
	screen._process(0.26)
	check(float(screen.shader_material.get_shader_parameter("ring_radius"))>root.get_visible_rect().size.length(),"blue circle rapidly expands beyond the entire screen")
	var low:float=1; var high:float=0
	for i:int in range(16):
		screen._process(0.05)
		var darkness:float=screen.shader_material.get_shader_parameter("darkness")
		low=minf(low,darkness); high=maxf(high,darkness)
	check(high-low>0.08 and low>=0.17 and high<=0.31,"after initial darkening the screen gently pulses darker, never white")
	screen._process(w.emerge_duration)
	check(screen.summon_left==0 and not screen.rect.visible,"summon cinematic finishes cleanly")
	layer.queue_free()
	print("WARDEN CINEMATIC: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
