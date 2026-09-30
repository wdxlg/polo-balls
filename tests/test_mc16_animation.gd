extends SceneTree
# Actual scene/skill regression. No ball type annotations before autoload bootstrap.
var game:Node
var world:Node
var saved:Dictionary
var saved_stop:bool
var checks:int = 0
var failures:int = 0
var finishing:bool = false
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+label)
func spawn(path:String,point:Vector2,team:String = "Team0") -> Node2D:
	var unit:Node2D = load(path).instantiate()
	unit.Team = team
	unit.Can_Attack = false
	unit.Can_Skill = false
	unit.Health_Restore = 0
	world.add_child(unit,true)
	unit.global_position = point
	unit.state_machine.set_physics_process(false)
	return unit
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(40.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.3).timeout
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var spider:Node2D = spawn("res://scenes/characters/我的世界/蜘蛛.tscn",center+Vector2(-140,0))
	var drowned:Node2D = spawn("res://scenes/characters/我的世界/溺尸.tscn",center+Vector2(140,0))
	var target:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(0,300),"Team1")
	target.health = 100000.0
	await process_frame
	await process_frame
	var units:Array = [spider,drowned]
	for unit:Node2D in units:
		var a:Node = unit.mc_native_animation
		check(is_instance_valid(a) and a.ready_visual,"scene attaches native animation: "+str(unit.name))
		if not is_instance_valid(a) or not a.ready_visual:
			finish(1)
			return
		a.set_process(false)
		check(unit.image is Sprite2D and unit.image.material != null,"original Sprite2D/material retained")
		check(unit.image.texture.get_size()==Vector2(160,224),"not a static portrait")
		var position_before:Vector2 = unit.image.position
		var scale_before:Vector2 = unit.image.scale
		var shape_before:Vector2 = unit.get_node("CollisionShape2D").shape.size
		var texture_before:Texture2D = unit.image.texture
		unit.global_position.x += 8.0
		a.advance(0.08)
		check(a.current_clip==&"walk","actual displacement selects walk")
		check(unit.image.texture!=texture_before,"walk changes bone frame")
		check(unit.image.position==position_before and unit.image.scale==scale_before,"no whole-image wobble or scaling")
		check(unit.get_node("CollisionShape2D").shape.size==shape_before,"collision shape unchanged")
		a.advance(0.5)
		check(a.current_clip==&"idle","stationary unit exits walking")
		# Every multi-frame action must contain real pixel changes, with no clipped limbs.
		var frames:SpriteFrames = a.frames
		for clip:StringName in frames.get_animation_names():
			var unique:Dictionary = {}
			for i:int in range(frames.get_frame_count(clip)):
				var tex:Texture2D = frames.get_frame_texture(clip,i)
				var im:Image = tex.get_image()
				var bounds:Rect2i = im.get_used_rect()
				check(tex.get_size()==Vector2(160,224),"constant canvas "+str(clip))
				check(bounds.has_area() and bounds.position.x>0 and bounds.position.y>0 and bounds.end.x<160 and bounds.end.y<224,"no clipped limbs "+str(clip))
				unique[hash(im.get_data())] = true
			if frames.get_frame_count(clip)>1: check(unique.size()>1,"real animated pixels "+str(clip))
	spider.silk_network.set_physics_process(false)
	drowned._trident.set_physics_process(false)
	world.get_node("MCTridentNetwork").set_physics_process(false)
	var sa:Node = spider.mc_native_animation
	var da:Node = drowned.mc_native_animation
	spider.silk_network.touch_wall(center+Vector2(-200,-100))
	sa.advance(0.03)
	check(sa.current_clip==&"cast","wall anchoring drives spider bone action")
	sa.advance(0.5)
	check(sa.current_clip==&"idle","anchor pose recovers")
	spider.hunt_web_target(target)
	sa.advance(0.04)
	check(sa.current_clip==&"lunge","web hunt drives spread legs")
	spider._lunge_left = 0.0
	sa.advance(0.04)
	check(sa.current_clip==&"idle","hunt end releases pose")
	drowned.throw_trident(target)
	da.advance(0.04)
	check(da.current_clip==&"throw_empty","launched spear removes duplicate hand model")
	var thrown:Texture2D = drowned.image.texture
	da.advance(0.13)
	check(drowned.image.texture!=thrown,"empty-handed throw retains native bone motion")
	da.advance(0.5)
	check(da.current_clip==&"idle_empty","no phantom spear while projectile is outside")
	check(drowned.image.texture!=drowned.get_preview_texture(),"static portrait never overwrites driver")
	var _empty_texture:Texture2D = drowned.image.texture
	drowned._trident.flight_state = 0
	drowned.dizziness = true
	drowned.catch_trident(drowned._trident)
	check(da.current_clip==&"idle","catch updates hand inventory even during stun")
	drowned.dizziness = false
	da.advance(0.04)
	drowned.hand_visual.sync_pose()
	check(da.current_clip==&"idle" and drowned.hand_visual.visible and not drowned.hand_visual.is_ghost,"caught spear reappears in independent hand layer")
	check(da.DROWNED_HANDS.TRACKS.has("walk_empty"),"actual rightItem bone attachment tracks loaded")
	check(drowned.trident_hand_position().distance_to(drowned.global_position)<100.0,"return endpoint follows model hand, not world origin")
	for unit:Node2D in units:
		var a:Node = unit.mc_native_animation
		var before:float = a.clip_time
		var tex:Texture2D = unit.image.texture
		game.now_stop_state = true
		a.advance(0.2)
		check(a.clip_time==before and unit.image.texture==tex,"pause freezes native animation")
		game.now_stop_state = false
		unit.dizziness = true
		a.advance(0.2)
		check(a.clip_time==before and unit.image.texture==tex,"stun freezes native action")
		unit.dizziness = false
		var hp:float = unit.health
		unit.health = 0
		a.advance(0.2)
		check(a.clip_time==before and unit.image.texture==tex,"death snapshot retains last frame")
		unit.health = hp
		unit.set_character_visual_flip_h(true)
		a.advance(0.04)
		check(unit._visual_facing_flipped_h,"facing survives frame switch")
		unit.set_multiplayer_authority(99)
		a._remote_pose = "walk"
		a.advance(0.1)
		check(a.current_clip==&"walk","non-authority presentation honors remote pose")
		before = a.clip_time
		a.advance(0.1)
		check(a.clip_time>before,"non-authority client continues animation")
		unit.set_multiplayer_authority(1)
		a._remote_pose = ""
	check(is_equal_approx(float(spider.Damage),26.0) and is_equal_approx(float(drowned.Damage),34.0),"damage unchanged")
	check(spider.get_node("CollisionShape2D").shape.size==Vector2(150,110),"spider collision unchanged")
	check(drowned.get_node("CollisionShape2D").shape.size==Vector2(70,125),"drowned collision unchanged")
	print("MC16_ANIMATION checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
func finish(code:int) -> void:
	if finishing: return
	finishing = true
	if not await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self): code = 1
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	if is_instance_valid(world): world.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	_stop_audio(root)
	await create_timer(0.12,true,false,true).timeout
	print("MC16_ANIMATION_EXIT=",code)
	quit(code)
func _stop_audio(node:Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		node.stop()
		if node.is_in_group("MCNativeSFX"): node.queue_free()
	for child:Node in node.get_children(): _stop_audio(child)
