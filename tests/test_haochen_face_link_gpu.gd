extends "res://tests/test_sulfur_cube_balance.gd"
## Real GPU pixels: head-front faces (normal/laugh) and the source->Haochen particle link.
func frozen(unit:Node) -> void:
	unit.state_machine.set_physics_process(false)
	unit.set_physics_process(false)
	unit.Has_Collision_Damage=false
	if unit.health_bar!=null:unit.health_bar.hide()

func count(image:Image,rect:Rect2i,test:Callable) -> int:
	var n:int=0
	for y:int in range(maxi(rect.position.y,0),mini(rect.end.y,image.get_height())):
		for x:int in range(maxi(rect.position.x,0),mini(rect.end.x,image.get_width())):
			var c:Color=image.get_pixel(x,y)
			if c.a>=0.4 and test.call(c):n+=1
	return n

func red(c:Color) -> bool: return c.r>0.55 and c.g<0.3 and c.b<0.3
func opaque(c:Color) -> bool: return true
func violet(c:Color) -> bool: return c.b>0.45 and c.b>c.g+0.12 and c.r>c.g

func run() -> void:
	create_timer(60.0,true,false,true).timeout.connect(func():print("HAOCHEN_FACE_TIMEOUT");quit(2))
	game=root.get_node("Game")
	var saved:Dictionary=game.Game_Settings.duplicate(true)
	var stopped:bool=game.now_stop_state
	game.now_stop_state=false
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	AudioServer.set_bus_mute(0,true)
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.free()
	world.set_process(false);world.set_physics_process(false)
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(320,180);viewport.transparent_bg=false;viewport.world_2d=World2D.new()
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	world.add_child(viewport)
	var bg:=ColorRect.new();bg.color=Color(0.16,0.17,0.2);bg.size=Vector2(320,180);viewport.add_child(bg)
	var layer:=Node2D.new();viewport.add_child(layer)
	var hero:Node2D=load("res://scenes/characters/我的世界/皓宸.tscn").instantiate()
	# Base ball root scale is 0.2 (in-battle head is 32px); x2 here for readable pixels.
	hero.name="FaceHaochen";hero.Team="Team0";hero.position=Vector2(240,86);hero.scale=Vector2.ONE*0.4
	layer.add_child(hero);frozen(hero);hero.set_process(false)
	var donor:Node2D=load("res://scenes/characters/我的世界/苦力怕.tscn").instantiate()
	donor.name="FaceDonor";donor.Team="Team1";donor.position=Vector2(56,86);donor.scale=Vector2.ONE*0.45
	layer.add_child(donor);frozen(donor)
	var head:=Rect2i(208,54,64,64)
	for i:int in range(6):await process_frame
	await RenderingServer.frame_post_draw
	var normal:Image=viewport.get_texture().get_image()
	normal.save_png("user://haochen_face_normal_gpu.png")
	var head_px:int=count(normal,head,opaque)
	var normal_red:int=count(normal,head,red)
	hero.charge_phase=hero.Phase.CHARGING
	await process_frame;await RenderingServer.frame_post_draw
	var laugh:Image=viewport.get_texture().get_image()
	laugh.save_png("user://haochen_face_laugh_gpu.png")
	var laugh_red:int=count(laugh,head,red)
	print("HAOCHEN_FACE head_px=",head_px," normal_red=",normal_red," laugh_red=",laugh_red)
	check(head_px>=3600,"head front renders as a full 64px square portrait at 2x battle scale")
	check(normal_red==0 and laugh_red>60,"charging swaps to the laughing face with its open red mouth")
	hero.charge_phase=hero.Phase.COPYING
	var request:Node2D=load("res://scenes/effects/我的世界/角色复制请求.tscn").instantiate()
	request.position=hero.position+Vector2(-30,0);request.remaining=10.0;request.cast_duration=10.0
	request.link_from=donor.global_position;request.link_to=hero.global_position;request.link_visible=true
	layer.add_child(request);request.set_physics_process(false)
	await process_frame
	for i:int in range(4):
		request._emit_link_particles(12,false)
		await create_timer(0.05,true,false,true).timeout
	await create_timer(0.12,true,false,true).timeout
	await RenderingServer.frame_post_draw
	var linked:Image=viewport.get_texture().get_image()
	linked.save_png("user://haochen_copy_link_gpu.png")
	var middle:int=count(linked,Rect2i(95,60,90,52),violet)
	print("HAOCHEN_LINK middle_violet=",middle)
	check(middle>20,"native portal particles are visible between the copied character and Haochen")
	print("HAOCHEN_FACE_DIR ",ProjectSettings.globalize_path("user://"))
	world.queue_free()
	await process_frame
	await create_timer(0.3,true,false,true).timeout
	game.Game_Settings=saved;game.now_stop_state=stopped
	print("HAOCHEN_FACE_LINK checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
