extends "res://tests/test_sulfur_cube_balance.gd"
## Task 9 (2026-09-28): copies are half size (body, collision, hit areas; health bar
## stays readable) and the spawn effect is "像素拼身": the copied character's own
## grayscale pixels assemble into the half-size copy, then flash and scatter.
## Needs a real renderer (gui) so textures can be read back.
var HAOCHEN:PackedScene
var REQUEST:PackedScene
var ASSEMBLE:Script

func collect(dir_path:String,out:Array[String]) -> void:
	var dir:=DirAccess.open(dir_path)
	if dir==null:return
	for sub:String in dir.get_directories():collect(dir_path.path_join(sub),out)
	for file:String in dir.get_files():
		if not file.ends_with(".tscn"):continue
		var path:String=dir_path.path_join(file)
		var head:String=FileAccess.get_file_as_string(path).substr(0,1200)
		if head.contains("res://scenes/ball.tscn"):out.append(path)

func hold(u:Node) -> void:
	u.state_machine.set_physics_process(false);u.set_physics_process(false)
	u.Has_Collision_Damage=false;u.Can_Attack=false;u.Can_Skill=false

func bbox(points:Array) -> Rect2:
	var r:=Rect2(points[0],Vector2.ZERO)
	for p:Vector2 in points:r=r.expand(p)
	return r

func shape_size(n:Node) -> Vector2:
	var cs:CollisionShape2D=n as CollisionShape2D
	if cs==null or cs.shape==null:return Vector2.ZERO
	return cs.shape.get_rect().size*cs.global_scale.abs()

var focus:Vector2
func shot(tag:String) -> void:
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	var k:float=float(image.get_width())/root.get_visible_rect().size.x
	var canvas:Vector2=world.get_viewport().get_canvas_transform()*focus
	var side:int=int(300.0*k)
	var rect:=Rect2i(Vector2i(canvas*k)-Vector2i(side/2,side/2),Vector2i(side,side)).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	image.get_region(rect).save_png("user://haochen_t9_%s.png"%tag)

func run() -> void:
	game=root.get_node("Game")
	HAOCHEN=load("res://scenes/characters/我的世界/皓宸.tscn")
	REQUEST=load("res://scenes/effects/我的世界/角色复制请求.tscn")
	ASSEMBLE=load("res://scripts/effects/我的世界/像素拼身粒子.gd")
	var saved:Dictionary=game.Game_Settings.duplicate(true)
	game.now_stop_state=false
	game.Game_Settings.Training_Mode=true
	game.Game_Settings.Training_Mode_Type="manual"
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	for i:int in range(20):await process_frame
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.queue_free()
	var center:Vector2=world.return_map_world_rect(world.map_group[world.now_choose_map]).get_center()

	# --- A. Real Haochen charge -> copy of a real creeper -----------------------------
	var hero:Node2D=HAOCHEN.instantiate();hero.name="T9Haochen";hero.Team="Team0";hero.position=center
	world.add_child(hero,true)
	var donor:Node2D=load("res://scenes/characters/我的世界/苦力怕.tscn").instantiate();donor.name="T9Creeper";donor.Team="Team1";donor.position=center+Vector2(60,0)
	world.add_child(donor,true)
	await process_frame
	hold(hero);hold(donor)
	for i:int in range(120):
		hero._scan_left=0.0;hero._step_energy(0.1)
		if hero.charge_phase==hero.Phase.COPYING:break
	check(hero.charge_phase==hero.Phase.COPYING,"a full meter starts the real copy cast")
	var request:Node2D=hero._copy_request.get_ref() if hero._copy_request!=null else null
	check(is_instance_valid(request) and request.source_name=="T9Creeper" and is_equal_approx(request.body_scale,0.5),"the cast knows the copied character (replicated by name) and the half body scale")
	# Screenshot geometry only: the random spawn side can put the figure behind Haochen's
	# own health label; move the cast to its left before the (deferred) effect starts.
	if is_instance_valid(request):request.global_position=center+Vector2(-75,15)
	focus=request.global_position if is_instance_valid(request) else center
	await process_frame;await process_frame
	var fxs:Array[Node]=get_nodes_in_group("MCHaochenAssembleParticle")
	check(fxs.size()==1,"the cast starts one pixel-assembly effect (not the old soul gathering)")
	var fx:Node2D=fxs[0] if not fxs.is_empty() else null
	if fx==null:
		print("HAOCHEN_TASK9 checks=",checks," failures=",failures);quit(1);return
	var gray:bool=true
	for c:Dictionary in fx.cells:gray=gray and is_equal_approx(c.color.r,c.color.g) and is_equal_approx(c.color.g,c.color.b)
	check(fx.cells.size()>=20 and gray,"the creeper's own frame becomes %d grayscale pixel cells" % fx.cells.size())
	var full:Dictionary=ASSEMBLE.sample(donor,1.0)
	var full_box:Rect2=bbox((full.cells as Array).map(func(c):return c.p))
	var targets:Array=fx.cells.map(func(c):return c.target)
	var tbox:Rect2=bbox(targets)
	print("HAOCHEN_T9 donor figure ",full_box.size," assembled target figure ",tbox.size," cell ",fx.cell_size)
	check(absf(tbox.size.y-0.5*full_box.size.y)<=0.15*full_box.size.y+2.0,"the pixels assemble into a HALF-size figure of the copied character")
	await create_timer(0.12,true,false,true).timeout
	var spread:float=0.0
	for c:Dictionary in fx.cells:spread+=(c.pos as Vector2).distance_to(c.target)
	spread/=float(fx.cells.size())
	check(spread>=0.8*fx._extent,"early in the cast the pixels are still flying in from around (mean %.1f px away, figure radius %.1f)" % [spread,fx._extent])
	await shot("1_gathering")
	var t:float=0.0
	while not fx.is_assembled() and t<1.0:
		await process_frame;t+=1.0/60.0
	check(fx.is_assembled() and not request.completed,"the figure is fully assembled before the copy appears")
	await shot("2_assembled")
	t=0.0
	while hero.completed_copies<1 and t<2.0:
		await physics_frame;t+=1.0/60.0
	check(hero.completed_copies==1,"the cast completes the copy")
	check(is_instance_valid(fx) and fx.stage==fx.Stage.SCATTER and fx.flashed,"when the copy appears the pixels flash white and scatter")
	var copy:Node2D=null
	for n:Node in world.get_children():
		if n!=donor and n.get_meta("haochen_copy",false):copy=n
	check(is_instance_valid(copy),"the half-size copy exists")
	if is_instance_valid(copy):
		hold(copy)
		check(copy.scale.is_equal_approx(donor.scale*0.5),"copy root scale is half of the original (%s vs %s)" % [copy.scale,donor.scale])
		var cb:Vector2=shape_size(copy.collision_shape_2d);var db:Vector2=shape_size(donor.collision_shape_2d)
		check(cb.is_equal_approx(db*0.5),"copy collision body is half size (%s vs %s)" % [cb,db])
		var ch:Vector2=shape_size(copy.self_hurtbox.get_node_or_null("CollisionShape2D"));var dh:Vector2=shape_size(donor.self_hurtbox.get_node_or_null("CollisionShape2D"))
		check(ch.is_equal_approx(dh*0.5),"copy hurt area is half size")
		var cimg:Vector2=(copy.image as Node2D).global_scale.abs();var dimg:Vector2=(donor.image as Node2D).global_scale.abs()
		check(cimg.is_equal_approx(dimg*0.5),"copy image is drawn at half size")
		var cbar:Vector2=(copy.get_node("Health_Bar") as Control).get_global_transform().get_scale().abs();var dbar:Vector2=(donor.get_node("Health_Bar") as Control).get_global_transform().get_scale().abs()
		check(cbar.is_equal_approx(dbar),"copy health bar keeps the normal, readable size (%s vs %s, local %s vs %s)" % [cbar,dbar,copy.get_node("Health_Bar").scale,donor.get_node("Health_Bar").scale])
		check(is_equal_approx(float(copy.character_copy_profile.get("body_scale",0.0)),0.5),"the replicated copy profile carries body_scale 0.5")
		var real:Dictionary=ASSEMBLE.sample(copy,1.0)
		var rbox:Rect2=bbox((real.cells as Array).map(func(c):return c.p+copy.global_position))
		print("HAOCHEN_T9 copy figure ",rbox," assembled ",tbox)
		check(absf(rbox.size.y-tbox.size.y)<=0.12*rbox.size.y+2.0 and rbox.get_center().distance_to(tbox.get_center())<=8.0,"the assembled figure matches the real copy's size and place")
	await create_timer(0.06,true,false,true).timeout
	await shot("3_scatter")
	await create_timer(0.25,true,false,true).timeout
	await shot("4_scatter_late")
	await create_timer(0.6,true,false,true).timeout
	check(not is_instance_valid(fx) and get_nodes_in_group("MCHaochenAssembleParticle").is_empty(),"the shards free themselves after the burst")
	check(get_nodes_in_group("MCHaochenSpawnRiseParticle").is_empty(),"the old soul-rise spawn effect is gone")

	# --- B. Fallback: no readable source -> old soul gathering -------------------------
	var r2:Node2D=REQUEST.instantiate();r2.position=center+Vector2(-150,0);r2.remaining=99.0;r2.source_name="Nobody"
	world.add_child(r2)
	await process_frame;await process_frame
	check(r2._soul_gather and get_nodes_in_group("MCHaochenAssembleParticle").is_empty(),"without a source the cast falls back to soul gathering")
	r2.queue_free()

	# --- C. Cancelled cast: shards scatter without the white flash ---------------------
	var r3:Node2D=REQUEST.instantiate();r3.position=center+Vector2(-150,60);r3.remaining=99.0;r3.source_name="T9Creeper"
	world.add_child(r3)
	await process_frame;await process_frame
	var fx3:Node2D=r3._assemble.get_ref() if r3._assemble!=null else null
	r3.queue_free()
	await process_frame
	check(is_instance_valid(fx3) and fx3.stage==fx3.Stage.SCATTER and not fx3.flashed,"a cancelled cast scatters its pixels (no flash, no copy)")

	# --- D. Roster coverage: which characters can be assembled from pixels -------------
	var scenes:Array[String]=[]
	collect("res://scenes/characters",scenes)
	scenes.sort()
	var ok:int=0;var bad:Array[String]=[]
	for path:String in scenes:
		var before:Dictionary={}
		for c:Node in world.get_children():before[c.get_instance_id()]=true
		var u:Node=load(path).instantiate()
		if not (u is Node2D) or not u.has_method("_refresh_character_copy_visuals"):
			u.free();continue
		u.name="T9Roster";u.Team="Team5";u.position=center+Vector2(0,-200)
		world.add_child(u,true)
		await process_frame
		if is_instance_valid(u):
			var d:Dictionary=ASSEMBLE.sample(u,0.5)
			if not d.is_empty() and (d.cells as Array).size()>=12:ok+=1
			else:bad.append(path.get_file())
		for c:Node in world.get_children():
			if not before.has(c.get_instance_id()) and not c.is_queued_for_deletion():c.queue_free()
		for n:Node in get_nodes_in_group("BattleTransient"):
			if is_instance_valid(n) and not n.is_queued_for_deletion():n.queue_free()
		await process_frame
	print("HAOCHEN_T9_ROSTER assembled=",ok," of ",ok+bad.size()," fallback=",bad)
	check(ok>=int(0.85*float(ok+bad.size())),"most roster characters assemble from their own pixels (%d/%d)" % [ok,ok+bad.size()])

	world.queue_free()
	await process_frame
	await create_timer(0.3,true,false,true).timeout
	game.Game_Settings=saved
	print("HAOCHEN_TASK9 checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
