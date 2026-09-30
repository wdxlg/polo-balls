extends SceneTree
var game:Node
var world:Node
var saved:Dictionary
var saved_stop:bool
var checks:int = 0
var failures:int = 0
var finishing:bool = false
var native:Script
var fang_script:Script
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+label)
func spawn(name:String,point:Vector2,team:String = "Team0") -> Node2D:
	var path:String = "res://scenes/characters/我的世界/"+name+".tscn" if not name.is_empty() else "res://scenes/ball.tscn"
	var u:Node2D = load(path).instantiate()
	u.Team = team
	world.add_child(u,true)
	u.global_position = point
	u.state_machine.set_physics_process(false)
	return u
func texture_of(u:Node2D) -> Texture2D:
	if u.image is Sprite2D: return u.image.texture
	var a:AnimatedSprite2D = u.image
	return a.sprite_frames.get_frame_texture(a.animation,a.frame)
func run() -> void:
	game = root.get_node("Game")
	native = load("res://scripts/effects/我的世界/mc_native_batch2.gd")
	fang_script = load("res://scripts/effects/我的世界/唤魔尖牙.gd")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(50.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var units:Array[Node2D] = []
	for i:int in range(5): units.append(spawn(["女巫","烈焰人","苦力怕","蠹虫","骷髅"][i],center+Vector2(i*100.0-200,-100)))
	var target:Node2D = spawn("",center+Vector2(0,200),"Team1")
	target.health = 100000
	var caster:Node2D = spawn("唤魔者",center+Vector2(100,200))
	await process_frame
	await process_frame
	caster.mc_native_animation.set_process(false)
	for u:Node2D in units:
		var a:Node = u._native_mob_animation
		check(is_instance_valid(a) and a.ready_visual,"real scene driver ready: "+str(u.name))
		if a==null or not a.ready_visual: finish(1); return
		a.set_process(false)
		check(texture_of(u).get_size()==Vector2(160,224),"fixed native canvas")
		check(u.image.material!=null,"original hit/facing shader remains")
		check(u.image.visible,"animation is on the visible image, not a hidden fallback")
	var frames_total:int = 0
	var all_frames:Dictionary = native.FRAMES.duplicate()
	all_frames["fang"] = fang_script.NATIVE_FRAMES
	for role:String in all_frames:
		var f:SpriteFrames = all_frames[role]
		for clip:StringName in f.get_animation_names():
			var hashes:Dictionary = {}
			for i:int in range(f.get_frame_count(clip)):
				var t:Texture2D = f.get_frame_texture(clip,i)
				check(t!=null and t.get_size()==Vector2(160,224),role+" size "+str(clip))
				var im:Image = t.get_image()
				var bounds:Rect2i = im.get_used_rect()
				if role=="fang" and i==f.get_frame_count(clip)-1:
					check(not bounds.has_area(),"fang last frame fully retracted")
				else:
					check(bounds.has_area(),role+" visible "+str(clip))
					check(bounds.position.x>0 and bounds.position.y>0 and bounds.end.x<160 and bounds.end.y<224,role+" no clipped geometry "+str(clip)+"/"+str(i))
				hashes[hash(im.get_data())] = true
				frames_total += 1
			if f.get_frame_count(clip)>1: check(hashes.size()>1,role+" changes real model pixels "+str(clip))
	var witch:Node2D = units[0]
	var blaze:Node2D = units[1]
	var creeper:Node2D = units[2]
	var _silver:Node2D = units[3]
	var skeleton:Node2D = units[4]
	# State changes never touch collision resources, damage or movement speeds.
	for u:Node2D in units:
		var a:Node = u._native_mob_animation
		var shape:Shape2D = u.get_node("CollisionShape2D").shape
		var rect:Rect2 = shape.get_rect()
		var hp:float = u.health
		var damage:float = u.Damage
		var speed:float = u.Speed
		var scale_before:Vector2 = u.image.scale
		var position_before:Vector2 = u.image.position
		var previous:Texture2D = texture_of(u)
		u.global_position.x += 3.0
		a.advance(0.13)
		check(a.current_clip==&"walk" or a.role=="blaze","motion enters locomotion")
		check(texture_of(u)!=previous,"locomotion advances native frames")
		check(u.health==hp and u.Damage==damage and u.Speed==speed and shape.get_rect()==rect,"visual-only stats and collisions")
		check(u.image.scale==scale_before and u.image.position==position_before,"not whole-image shake/scale")
		var clock:float = a.clip_time
		game.now_stop_state = true
		a.advance(0.2)
		check(a.clip_time==clock,"game pause freezes native animation")
		game.now_stop_state = false
		u.health = 0
		a.advance(0.2)
		check(a.clip_time==clock,"death freezes frame for existing death sequence")
		u.health = hp
		u.set_multiplayer_authority(99)
		a.advance(0.1)
		check(a.clip_time!=clock,"non-authority presentation keeps advancing")
		u.set_multiplayer_authority(1)
	# Keep the exact existing brewing/drinking logic and bottle instance.
	var duration:float = witch.drink_animation_duration
	var bottle:Node = witch._brew_visual
	witch._begin_brew()
	witch._native_mob_animation.advance(0.02)
	check(witch._native_mob_animation.current_clip==&"hold" and witch._brewing,"real brew entry selects native holding pose")
	var effect:String = witch._pending_effect
	witch._finish_brew()
	witch._drink_potion(effect)
	witch._native_mob_animation.advance(0.1)
	check(witch._native_mob_animation.current_clip==&"drink","real drink entry selects native nose pose")
	check(witch._brew_visual==bottle and witch.drink_animation_duration==duration,"same bottle and same drinking duration")
	# Preserve AnimatedSprite2D and the two gameplay collision rods, not invisible substitutes.
	check(blaze.image is AnimatedSprite2D and blaze.image==blaze._body_anim and not blaze.get_node("Graphics/Image").visible,"blaze retains its actual AnimatedSprite2D")
	check(blaze.get_blaze_rod_rids().size()==2 and blaze._rod_a.visible and blaze._rod_b.visible,"both gameplay rods and their physics remain")
	var rods:Array = blaze.get_blaze_rod_rids()
	blaze._rpc_set_rod_attack_pose(true)
	blaze._update_rods(0.1)
	blaze._native_mob_animation.advance(0.1)
	check(blaze._rod_attack_pose and blaze._rod_attack_mix>0 and blaze.get_blaze_rod_rids()==rods,"native orbit coexists with unchanged attack rod expansion")
	var frame_before:int = blaze.image.frame
	blaze._native_mob_animation.advance(0.1)
	check(blaze.image.frame!=frame_before and not blaze.image.is_playing(),"blaze manual frames advance without uncontrolled autoplay")
	blaze._rpc_set_rod_attack_pose(false)
	# Creeper reverse progress and charged state are driven by gameplay values.
	var old_damage:float = creeper.explosion_damage
	var old_radius:float = creeper.explosion_radius
	creeper._rpc_begin_fuse(2.8,target.get_instance_id())
	creeper._fuse_elapsed = 2.0
	creeper._native_mob_animation.advance(0.2)
	var high:int = creeper._native_mob_animation.frame_index
	creeper._fuse_elapsed = 0.4
	creeper._native_mob_animation.advance(0.02)
	check(creeper._native_mob_animation.frame_index<high,"fuse reversal rewinds model swelling continuously")
	creeper._update_fuse_visual(0.0)
	check(creeper.graphics.scale==creeper._graphics_base_scale,"old whole-image growth does not double native swelling")
	creeper._rpc_set_charged(true)
	creeper._native_mob_animation.advance(0.02)
	check(str(creeper._native_mob_animation.current_clip).ends_with("_charged"),"charged state retains animated armor rather than static texture")
	creeper._rpc_cancel_fuse()
	creeper._native_mob_animation.advance(0.2)
	check(not str(creeper._native_mob_animation.current_clip).begins_with("fuse"),"fuse cancel restores locomotion")
	check(creeper.explosion_damage==old_damage and creeper.explosion_radius==old_radius,"unchanged explosion damage and radius")
	var spawned:Node2D = spawn("蠹虫",center+Vector2(300,-100))
	await process_frame
	check(spawned._native_mob_animation.ready_visual,"newly spawned silverfish gets the same animation")
	spawned._native_mob_animation.set_process(false)
	# Actual arrow entry, and the old static-image timer cannot overwrite frames.
	var before_children:int = world.get_child_count()
	skeleton.direction = Vector2.DOWN
	skeleton.Attack()
	skeleton._native_mob_animation.advance(0.03)
	check(world.get_child_count()>before_children and skeleton._native_mob_animation.current_clip==&"shoot","actual immediate arrow attack triggers native bow pose")
	var aim:Texture2D = texture_of(skeleton)
	skeleton._restore_idle_visual(skeleton._aim_visual_serial)
	check(texture_of(skeleton)==aim,"legacy aim timer cannot restore a static image")
	skeleton._native_mob_animation.advance(0.5)
	check(skeleton._native_mob_animation.current_clip!=&"shoot","shoot returns after original aim duration")
	# Fang opens BEFORE the same old hit moment; closes at that moment, not after.
	var shared:Dictionary = {}
	var fang:Node2D = fang_script.new()
	world.add_child(fang)
	fang.global_position = target.global_position
	fang.setup(caster,0.3,32.0,shared)
	fang.set_physics_process(false)
	var hp_target:float = target.health
	fang._physics_process(0.15)
	check(fang.native_frame_index()==-1 and target.health==hp_target,"fang hidden before telegraph start")
	fang._physics_process(0.05)
	check(fang.native_frame_index()>=0 and not fang._hit and target.health==hp_target,"fang visibly opens before damaging")
	fang._physics_process(0.099)
	check(not fang._hit and target.health==hp_target,"no early damage from visual telegraph")
	fang._physics_process(0.0011)
	check(fang._hit and target.health<hp_target and absf(fang.native_animation_progress()-0.5)<0.01,"same damage timestamp coincides with closed jaws")
	var after_hit:float = target.health
	fang._physics_process(0.1)
	check(target.health==after_hit,"animation does not cause repeated damage")
	var phase_before:float = fang._age
	game.now_stop_state = true
	fang._physics_process(0.1)
	check(fang._age==phase_before,"fang damage/animation clock both freeze during pause")
	game.now_stop_state = false
	var second:Node2D = fang_script.new()
	world.add_child(second)
	second.global_position = target.global_position
	second.setup(caster,0.0,32.0,shared)
	second.set_physics_process(false)
	second._physics_process(0.01)
	check(target.health==after_hit,"shared ring hit-dedup remains unchanged")
	fang._physics_process(0.3)
	check(fang.is_queued_for_deletion(),"fang still retires after original 0.34-second post-hit lifetime")
	print("MC_NATIVE_BATCH2 frames=",frames_total," checks=",checks," failures=",failures)
	if OS.get_cmdline_user_args().has("--capture"):
		await capture(units,caster)
	finish(0 if failures==0 else 1)
func capture(units:Array[Node2D],caster:Node2D) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1200,440)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node2D.new()
	viewport.add_child(stage)
	var background := ColorRect.new()
	background.color = Color("242b35")
	background.size = Vector2(1200,440)
	stage.add_child(background)
	for i:int in range(5):
		var u:Node2D = units[i]
		u.reparent(stage)
		u.scale = Vector2.ONE
		u.global_position = Vector2(100+i*200,240)
		u.health_bar.hide()
		u.set_character_visual_flip_h(false)
		u.hit_white_method(0.0)
		var label := Label.new()
		stage.add_child(label)
		label.text = ["Witch","Blaze","Creeper","Silverfish","Skeleton"][i]
		label.position = Vector2(50+i*200,20)
		label.z_index = 1000
		label.add_theme_font_size_override("font_size",18)
	units[1]._update_rods(0.0)
	units[2]._rpc_begin_fuse(2.8,0)
	var fang:Node2D = fang_script.new()
	stage.add_child(fang)
	fang.position = Vector2(1100,310)
	fang.scale = Vector2.ONE*7.0
	fang.setup(caster,0.2,0.0,{})
	fang.set_physics_process(false)
	var label := Label.new()
	stage.add_child(label)
	label.text = "Evoker fangs"
	label.position = Vector2(1040,20)
	label.add_theme_font_size_override("font_size",18)
	for i:int in range(8):
		units[2]._fuse_elapsed = float(i)/7.0*2.8
		if i==3: units[4]._native_mob_animation.trigger_shot(0.15)
		for u:Node2D in units: u._native_mob_animation.advance(0.06)
		if i in [0,3,7]:
			check(units[4]._native_mob_animation.current_clip==(&"shoot" if i==3 else &"idle"),"bow lowered before/after shooting, raised only during shooting")
		fang._age = 0.06+float(i)*0.06
		fang.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://scripts/training/mc_native_assets/batch2_preview_"+str(i)+".png")
	viewport.queue_free()
	print("MC_NATIVE_BATCH2_CAPTURE_SAVED=8 checks=",checks," failures=",failures)
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
