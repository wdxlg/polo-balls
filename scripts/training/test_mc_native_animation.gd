extends SceneTree
var game:Node
var world:Node
var saved:Dictionary
var saved_stop:bool
var checks:int = 0
var failures:int = 0
var finishing:bool = false
var native:Script
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)
func spawn(path:String,point:Vector2,master:Node = null) -> Node2D:
	var u:Node2D = load(path).instantiate()
	u.Team = "Team0"
	if master != null: u.Master = master
	world.add_child(u,true)
	u.global_position = point
	u.state_machine.set_physics_process(false)
	return u
func run() -> void:
	game = root.get_node("Game")
	native = load("res://scripts/effects/我的世界/mc_native_animation.gd")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(45.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var e:Node2D = spawn("res://scenes/characters/我的世界/末影人.tscn",center+Vector2(-180,0))
	var c:Node2D = spawn("res://scenes/characters/我的世界/唤魔者.tscn",center+Vector2(-60,0))
	var v:Node2D = spawn("res://scenes/creatures/唤魔恼鬼.tscn",center+Vector2(60,0),c)
	var s:Node2D = spawn("res://scenes/characters/我的世界/潜影贝.tscn",center+Vector2(180,0))
	var target:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(0,350))
	target.Team = "Team1"
	target.health = 100000
	await process_frame
	await process_frame
	var units:Array = [e,c,v,s]
	for u:Node2D in units:
		var a:Node = u.mc_native_animation
		check(is_instance_valid(a) and a.ready_visual,"actual scene driver initialized: "+str(u.name))
		if a == null or not a.ready_visual: finish(1); return
		a.set_process(false)
		check(u.image is Sprite2D,"original Sprite2D retained")
		check(u.image.texture.get_size() == Vector2(160,224),"full frame texture, not old static image")
		check(u.image.material != null,"existing tint/facing material retained")
	check(e.mc_live(),"fixture in actual active World")
	# Validate every sampled frame: loaded, nonempty, never clipped, fixed canvas;
	# each action that should move has genuinely different pixel data.
	var total_frames:int = 0
	for role:String in native.FRAMES:
		var f:SpriteFrames = native.FRAMES[role]
		for clip:StringName in f.get_animation_names():
			var unique:Dictionary = {}
			for i:int in range(f.get_frame_count(clip)):
				var texture:Texture2D = f.get_frame_texture(clip,i)
				check(texture != null and texture.get_size()==Vector2(160,224),role+" frame size "+str(clip))
				var im:Image = texture.get_image()
				var bounds:Rect2i = im.get_used_rect()
				check(bounds.has_area(),role+" nonempty "+str(clip))
				check(bounds.position.x>0 and bounds.position.y>0 and bounds.end.x<160 and bounds.end.y<224,role+" no cut-off limbs "+str(clip)+" / "+str(i))
				unique[hash(im.get_data())] = true
				total_frames += 1
			if f.get_frame_count(clip)>1: check(unique.size()>1,role+" real bone-motion pixels "+str(clip))
	var ea:Node = e.mc_native_animation
	var ca:Node = c.mc_native_animation
	var va:Node = v.mc_native_animation
	var sa:Node = s.mc_native_animation
	var collision_shapes:Array = []
	for u:Node2D in units: collision_shapes.append(u.get_node("CollisionShape2D").shape.size)
	var epos:Vector2 = e.image.position
	var escale:Vector2 = e.image.scale
	var tex:Texture2D = e.image.texture
	e.global_position.x += 8.0
	ea.advance(0.08)
	check(ea.current_clip == &"walk" and e.image.texture != tex,"enderman actual displacement starts walk")
	e.rage_remaining = 2.0
	ea.advance(0.02)
	check(str(ea.current_clip).begins_with("angry_"),"enderman rage selects scary face")
	ea._on_contact_attack(target.self_hurtbox)
	ea.advance(0.02)
	check(ea.current_clip == &"angry_attack","contact hit drives native attack overlay")
	check(e.image.position==epos and e.image.scale==escale,"enderman animation is not whole-image shaking")
	var attack_damage:float = c.Damage
	var fang_interval:float = c.fang_interval
	c.cast_fangs(target)
	ca.advance(0.02)
	check(ca.current_clip==&"cast","real fang entry triggers raised-arm casting")
	var casting_texture:Texture2D = c.image.texture
	ca.advance(0.12)
	check(c.image.texture!=casting_texture,"casting bone frames advance")
	check(c.Damage==attack_damage and c.fang_interval==fang_interval,"visual cast leaves combat numbers alone")
	ca.advance(1.0)
	check(ca.current_clip!=&"cast","cast returns to locomotion without a stuck pose")
	c.summon_vex()
	ca.advance(0.02)
	check(ca.current_clip==&"cast","real summon entry also triggers casting")
	for weak:WeakRef in c._vex:
		var summoned:Node = weak.get_ref()
		if is_instance_valid(summoned): summoned.state_machine.set_physics_process(false)
	await process_frame
	for weak:WeakRef in c._vex:
		var summoned:Node = weak.get_ref()
		check(is_instance_valid(summoned) and summoned.mc_native_animation.ready_visual,"runtime-spawned vex gets animation")
		if is_instance_valid(summoned): summoned.mc_native_animation.set_process(false)
	var vex_scale:Vector2 = v.image.scale
	v.begin_dash(target)
	va.advance(0.03)
	check(va.current_clip==&"charge","vex windup uses native charge skin and raised sword")
	v._launch_dash()
	va.advance(0.08)
	check(va.current_clip==&"charge","launched vex keeps charge animation")
	v._finish_dash()
	va.advance(0.03)
	check(va.current_clip==&"fly" and v.image.scale==vex_scale,"vex resumes flapping without scale snap")
	var fly_texture:Texture2D = v.image.texture
	va.advance(0.13)
	check(v.image.texture!=fly_texture,"idle flight has actual wing frames")
	var spos:Vector2 = s.image.position
	var sscale:Vector2 = s.image.scale
	s.shell_open = false
	sa.advance(1.0)
	check(sa.current_clip==&"closed","shell settles fully closed")
	s.shell_open = true
	s._update_shell_visual()
	sa.advance(0.2)
	check(sa.current_clip==&"open" and is_equal_approx(sa.shell_peek,0.4),"shell opening has intermediate peek frames")
	var intermediate:Texture2D = s.image.texture
	s.shell_open = false
	s._update_shell_visual()
	sa.advance(0.05)
	check(sa.current_clip==&"close" and is_equal_approx(sa.shell_peek,0.3),"opening reverses from current height, not endpoint")
	check(s.image.texture!=intermediate,"reverse closing changes actual shell frame")
	sa.advance(0.5)
	check(sa.current_clip==&"closed","closing reaches closed state")
	s.shell_open = true
	sa.advance(0.6)
	check(sa.current_clip==&"hold","opening reaches animated open hold")
	for gravity:Vector2 in [Vector2.DOWN,Vector2.LEFT,Vector2.UP,Vector2.RIGHT]:
		s.gravity_direction = gravity
		s.graphics.rotation = gravity.angle()-Vector2.DOWN.angle()
		sa.advance(0.07)
		check(s.image.position==spos and s.image.scale==sscale,"shell pivot/scale stable under rotated gravity")
	s.gravity_direction = Vector2.DOWN
	s.graphics.rotation = 0.0
	s.shell_open = false
	s._update_shell_visual()
	var hp:float = s.health
	s.receive_positional_damage(40,s.global_position,false,target)
	check(s.health==hp,"closed shell still blocks damage")
	check(s.health_bar.suppress_floating_text,"closed shell still suppresses floating combat text")
	s.shell_open = true
	s._update_shell_visual()
	check(not s.health_bar.suppress_floating_text,"open shell restores floating combat text")
	for i:int in range(units.size()):
		check(units[i].get_node("CollisionShape2D").shape.size==collision_shapes[i],"native frames do not resize combat hitboxes")
	for u:Node2D in units:
		var a:Node = u.mc_native_animation
		var before:float = a.clip_time
		var before_texture:Texture2D = u.image.texture
		game.now_stop_state = true
		a.advance(0.2)
		check(a.clip_time==before and u.image.texture==before_texture,"game pause freezes animation")
		game.now_stop_state = false
		var health_before:float = u.health
		u.health = 0
		a.advance(0.2)
		check(a.clip_time==before and u.image.texture==before_texture,"dead unit keeps last frame for death snapshot")
		u.health = health_before
	# Non-authority instances must still advance their presentation clock.
	v.set_multiplayer_authority(99)
	check(not v.mc_live(),"client fixture cannot execute authority-only combat")
	var client_before:float = va.clip_time
	va.advance(0.1)
	check(va.clip_time>client_before,"non-authority client still animates")
	v.set_multiplayer_authority(1)
	# Direction remains handled by the original shader, independent of frame switches.
	e.set_character_visual_flip_h(true)
	ea.advance(0.1)
	check(e._visual_facing_flipped_h,"frame switch retains shader-facing flip")
	e.set_character_visual_flip_h(false)
	c._victory_cheered = true
	ca.advance(0.1)
	check(ca.current_clip==&"celebrate","evoker victory selects original celebration")
	print("MC_NATIVE frames=",total_frames," checks=",checks," failures=",failures)
	if OS.get_cmdline_user_args().has("--capture"):
		# Actual battle instances and their original shaders, enlarged in an isolated
		# viewport so combat floating text cannot obscure the model inspection.
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1040,440)
		viewport.disable_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var stage := Node2D.new()
		viewport.add_child(stage)
		var background := ColorRect.new()
		background.color = Color("242b35")
		background.size = Vector2(1040,440)
		stage.add_child(background)
		for i:int in range(units.size()):
			var u:Node2D = units[i]
			u.reparent(stage)
			u.scale = Vector2.ONE
			u.global_position = Vector2(130.0+float(i)*260.0,250.0)
			u.health_bar.hide()
			u.set_character_visual_flip_h(false)
			u.hit_white_method(0.0)
			var label := Label.new()
			stage.add_child(label)
			label.text = ["Enderman", "Evoker", "Vex", "Shulker"][i]
			label.position = Vector2(80.0+float(i)*260.0,28.0)
			label.add_theme_font_size_override("font_size",20)
		c._victory_cheered = false
		ca.trigger_cast(10.0)
		v._charging = true
		s.shell_open = true
		sa.shell_peek = 0.0
		e.rage_remaining = 10.0
		ea._attack_left = 0.0
		ea._moving_left = 1.0
		for j:int in range(4):
			for u:Node2D in units: u.mc_native_animation.advance(0.16 if j>0 else 0.0)
			await process_frame
			await RenderingServer.frame_post_draw
			var screenshot:Image = viewport.get_texture().get_image()
			screenshot.save_png("res://scripts/training/mc_native_assets/actual_preview_"+str(j)+".png")
		print("MC_NATIVE_CAPTURE_SAVED=4")
		viewport.queue_free()
	finish(0 if failures==0 else 1)
func finish(code:int) -> void:
	if finishing: return
	finishing = true
	if is_instance_valid(game):
		game.Game_Settings = saved
		game.now_stop_state = saved_stop
	if is_instance_valid(world): world.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	quit(code)
