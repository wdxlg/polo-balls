extends "res://scripts/training/test_mc_new5.gd"
func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(45).timeout.connect(func(): finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.5).timeout
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	u=load("res://scripts/characters/我的世界/new5/utils.gd")
	await clear_units()
	for role:String in ["","守卫者","恶魂","粘性活塞","史莱姆"]:
		var actor:Node2D=spawn(role,Vector2.ZERO,"Team0")
		actor.begin_stun_visual()
		var fx:Node2D=actor._stun_visual_instance
		check(fx!=null and fx.strands.size()==6,"six irregular lines for "+role)
		check(fx.front_layer.glyphs.size()+fx.back_layer.glyphs.size()==4,"four swirl particles")
		check(fx.global_scale.x>=0.54,"compact stun scale retains visibility")
		check(fx.follow_offset==Vector2(0,-20),"exercise actual inherited scene offset")
		check(fx.global_position.y<actor.image.global_position.y,"orbit stays above body origin, not down at feet")
		var z:int=fx.effective_z(actor.image)
		check(fx.back_layer.z_index<z and fx.front_layer.z_index>z,"orbit layers straddle body art including absolute z")
		check(fx.back_layer.pixels.size()>0 and fx.front_layer.pixels.size()>0,"both halves of orbit are populated")
		var initial:Vector2=fx.global_position
		actor.image.position+=Vector2(0,-10)
		fx._follow_target()
		check(fx.global_position.y<initial.y,"head orbit follows body bob/jump")
		var before:float=fx.age
		game.now_stop_state=true
		fx._process(0.2)
		check(fx.age==before,"orbit freezes when battle stops")
		game.now_stop_state=false
		fx._process(0.2)
		check(fx.age>before,"orbit resumes smoothly")
		actor.begin_stun_visual()
		check(actor._stun_visual_instance==fx,"stacked stun reuses visual")
		actor.end_stun_visual()
		check(not fx.is_queued_for_deletion(),"one remaining stun retains visual")
		actor.end_stun_visual()
		check(fx.fading_out and not fx.is_queued_for_deletion(),"last stun begins fade instead of disappearing")
		game.now_stop_state=true
		fx._process(0.06)
		check(fx.modulate.a>0 and fx.modulate.a<1,"stun fades quickly even at end of combat")
		fx._process(0.07)
		check(fx.is_queued_for_deletion(),"fade cleans both layers in 120 ms")
		game.now_stop_state=false
		await clear_units()
	# A single long strand crossing the character plane must split at per-pixel depth.
	var actor:Node2D=spawn("",Vector2.ZERO,"Team0")
	actor.begin_stun_visual()
	var fx:Node2D=actor._stun_visual_instance
	fx.strands.clear()
	fx.strands.append({"angle":0.0,"speed":2.0,"radius":20.0,"height":5.0,"offset":0.0,"short":1.0,"long":1.0,"rate":1.0,"phase":0.0})
	fx.age=0.0
	fx._rebuild_orbit()
	check(fx.back_layer.pixels.size()>0 and fx.front_layer.pixels.size()>0,"one crossing line split between front and rear")
	for point:Vector2 in fx.back_layer.pixels: check(point.y<=0.0,"back pixels belong to rear arc")
	for point:Vector2 in fx.front_layer.pixels: check(point.y>=0.0,"front pixels belong to front arc")
	actor.health=0
	game.now_stop_state=true
	fx._process(0.01)
	check(fx.is_queued_for_deletion() and not fx.visible,"death clears orbit while paused")
	game.now_stop_state=false
	await clear_units()
	# GPU readback: back pixels must be covered by opaque body; front pixels must show.
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(400,400)
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var dummy:=StunDummy.new()
	dummy.position=Vector2(200,200)
	var graphics:=Node2D.new()
	graphics.name="Graphics"
	dummy.add_child(graphics)
	var sprite:=Sprite2D.new()
	sprite.name="Image"
	var red:=Image.create(64,64,false,Image.FORMAT_RGBA8)
	red.fill(Color(0.6,0.05,0.05,1))
	sprite.texture=ImageTexture.create_from_image(red)
	graphics.add_child(sprite)
	viewport.add_child(dummy)
	var orbit:Node2D=load("res://scenes/effects/stun_visual.tscn").instantiate()
	orbit.setup(dummy)
	dummy.add_child(orbit)
	orbit.set_process(false)
	orbit.strands.clear()
	orbit.strands.append({"angle":0.0,"speed":2.0,"radius":20.0,"height":5.0,"offset":0.0,"short":1.4,"long":1.4,"rate":1.0,"phase":0.0})
	orbit.age=0.0
	orbit._rebuild_orbit()
	orbit.front_layer.glyphs.clear()
	orbit.back_layer.glyphs.clear()
	await RenderingServer.frame_post_draw
	var rendered:Image=viewport.get_texture().get_image()
	var tested_front:int=0
	var tested_back:int=0
	for point:Vector2 in orbit.back_layer.pixels:
		if point.y>=-1: continue
		var pixel:Vector2i=Vector2i(orbit.to_global(point+Vector2(0.5,0.5)))
		var color:Color=rendered.get_pixelv(pixel)
		check(color.g<0.08 and color.r>0.5,"GPU body occludes rear line pixels")
		tested_back+=1
	for point:Vector2 in orbit.front_layer.pixels:
		if point.y<=1: continue
		var pixel:Vector2i=Vector2i(orbit.to_global(point+Vector2(0.5,0.5)))
		var color:Color=rendered.get_pixelv(pixel)
		check(color.g>0.15,"GPU front line pixels overlay body")
		tested_front+=1
	check(tested_front>0 and tested_back>0,"GPU tested both depth halves")
	viewport.queue_free()
	await create_timer(2).timeout
	finish(0 if failures==0 else 1)
class StunDummy extends Node2D:
	var health:float=100.0
	func is_combat_runtime_active() -> bool: return true
