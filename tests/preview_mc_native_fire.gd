extends "res://tests/test_mc_frontier.gd"
func run() -> void:
	root.size=Vector2i(1080,720)
	root.content_scale_size=Vector2i(1080,720)
	var o:Vector2=await setup_world()
	var camera:=Camera2D.new(); world.add_child(camera)
	camera.global_position=o+Vector2(0,-35); camera.zoom=Vector2.ONE*1.6; camera.make_current()
	var source:Node2D=actor("烈焰人",o+Vector2(-300,0)); source.hide()
	var victim:Node2D=dummy(o+Vector2(0,50))
	var patch:Node2D=load("res://scripts/effects/我的世界/烈焰火场.gd").new()
	world.add_child(patch); patch.setup(source,"Team0",o+Vector2(-200,50),34,4.5,0.5,0.11,2.2,0.05); patch.set_physics_process(false)
	var burn:Node2D=load("res://scripts/status/战争女神_灼烧.gd").new()
	victim.add_child(burn); burn.setup(victim,source,10,1,0); burn.set_physics_process(false)
	var owner:Node2D=spawn("res://scenes/characters/乐队/薇欧拉.tscn",o+Vector2(300,0),"Team0"); owner.state_machine.set_physics_process(false); owner.set_process(false); owner.hide()
	var big:Node2D=load("res://scripts/effects/薇欧拉_火场.gd").new()
	world.add_child(big); big.setup(owner,o+Vector2(200,0)); big.set_physics_process(false); big.elapsed=0.5; big._update_main_fire_visual()
	await create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg("res://tests/mc_native_fire_preview.jpg",0.90)
	print("MC FIRE GPU: Blaze ground / burning target / Viola large fire")
	finish(0)
