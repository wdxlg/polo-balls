extends "res://tests/test_sulfur_cube_balance.gd"
## Screenshot only: original creeper vs Haochen copy (UI shrinks with the half body).
func run() -> void:
	game=root.get_node("Game")
	game.now_stop_state=false
	game.Game_Settings.Training_Mode=true
	game.Game_Settings.Training_Mode_Type="manual"
	AudioServer.set_bus_mute(0,true)
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	for i:int in range(20):await process_frame
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.queue_free()
	var center:Vector2=world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()
	var TOOLS:Script=load("res://scripts/characters/投稿角色工具.gd")
	var hero:Node2D=load("res://scenes/characters/我的世界/皓宸.tscn").instantiate();hero.name="ShotHaochen";hero.Team="Team0";hero.position=center+Vector2(0,-45)
	world.add_child(hero,true)
	var donor:Node2D=load("res://scenes/characters/我的世界/苦力怕.tscn").instantiate();donor.name="ShotCreeper";donor.Team="Team1";donor.position=center+Vector2(-28,0)
	world.add_child(donor,true)
	await process_frame
	for u:Node in [hero,donor]:
		u.state_machine.set_physics_process(false);u.set_physics_process(false);u.Can_Attack=false;u.Can_Skill=false;u.Has_Collision_Damage=false
	var stats:Dictionary={}
	for key:String in TOOLS.COPY_STAT_KEYS:stats[key]=donor.get(key)
	var snap:Dictionary={"scene":"res://scenes/characters/我的世界/苦力怕.tscn","label":"苦力怕","stats":stats,"health":1,"block":0,"energy":0}
	print("SHOT snap ",snap.size())
	var copy:Node2D=null
	if not snap.is_empty():
		copy=TOOLS.spawn_character_copy(hero,snap,center+Vector2(28,0),0.5,{"owner":hero,"parent":world,"full_vitals":true,"monochrome":true,"metadata":{"haochen_copy":true},"body_scale":0.5,"friendly_guard":true,"prepare_instance":func(u:Node2D):u.scale*=0.5})
	await process_frame
	if is_instance_valid(copy):
		copy.state_machine.set_physics_process(false);copy.set_physics_process(false);copy.global_position=center+Vector2(28,0)
		print("SHOT bars donor ",(donor.get_node("Health_Bar") as Control).get_global_transform().get_scale()," copy ",(copy.get_node("Health_Bar") as Control).get_global_transform().get_scale())
	var cam:Camera2D=root.get_viewport().get_camera_2d()
	if cam!=null:cam.global_position=center+Vector2(0,-10)
	for i:int in range(30):await process_frame
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	var k:float=float(image.get_width())/root.get_visible_rect().size.x
	var canvas:Vector2=world.get_viewport().get_canvas_transform()*(center+Vector2(0,-10))
	var side:Vector2i=Vector2i(int(560.0*k),int(380.0*k))
	var rect:=Rect2i(Vector2i(canvas*k)-side/2,side).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	image.get_region(rect).save_png("user://haochen_t10_ui.png")
	print("SHOT saved ",rect)
	quit(0)
