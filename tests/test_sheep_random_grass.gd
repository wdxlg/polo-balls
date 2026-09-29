extends SceneTree
var checks:int = 0
var failures:int = 0
var arena:Node2D
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("REWORK_FAIL ",label)
func _initialize() -> void:
	call_deferred("run")
func spawn(path:String,point:Vector2,team:String):
	var packed:PackedScene = load(path)
	if packed == null:
		push_error("Scene unavailable: "+path)
		quit(2)
		return null
	var actor = packed.instantiate()
	actor.Team = team
	actor.position = point
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	for child:Node in actor.find_children("*","CollisionObject2D",true,false):
		(child as CollisionObject2D).disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	arena.add_child(actor,true)
	return actor
func wall_at(point:Vector2) -> StaticBody2D:
	var wall:StaticBody2D = StaticBody2D.new()
	var cs:CollisionShape2D = CollisionShape2D.new()
	var box:RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(5,200)
	cs.shape = box
	wall.add_child(cs)
	arena.add_child(wall)
	wall.global_position = point
	return wall
func effect_for(actor):
	for child in actor.get_children():
		if child.has_method("replace_with_hit") and child.is_active_effect(): return child
	return null
func run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	root.get_node("Game").now_stop_state = false
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var sheep = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2.ZERO,"A")
	sheep.health = 300
	sheep._observed_health = 300
	sheep._begin_grazing()
	sheep._graze(0.8)
	var first = get_nodes_in_group("SheepGrassBiteFX")[0]
	first.set_process(false)
	first._process(0.81)
	check(not first.is_queued_for_deletion(),"first bite debris survives next bite time")
	sheep._graze(0.8)
	var all = get_nodes_in_group("SheepGrassBiteFX")
	check(all.size() == 2 and not first.is_queued_for_deletion(),"two mouthfuls coexist independently")
	var second = all[1]
	second.set_process(false)
	check(first.parts[0].velocity != second.parts[0].velocity,"fresh random velocity each mouthful")
	var different_origins:bool = first.parts.size() != second.parts.size()
	for i:int in range(mini(first.parts.size(),second.parts.size())):
		if first.parts[i].origin != second.parts[i].origin: different_origins = true
	check(different_origins,"fresh random spawn locations across batch")
	check(first.parts[0].ground_wait != second.parts[0].ground_wait,"independent random ground lifetime")
	var part:Dictionary = first.parts[0]
	check(part.velocity.y < 0,"crumb starts upward before falling")
	var p0:Vector2 = first.particle_position(part,0)
	var p1:Vector2 = first.particle_position(part,0.1)
	var p2:Vector2 = first.particle_position(part,0.2)
	check(absf((p2.y-2*p1.y+p0.y)-first.GRAVITY*0.01)<0.001,"trajectory has constant downward gravity")
	check(absf(p2.x-2*p1.x+p0.x)<0.001,"horizontal motion remains ballistic")
	var tuft:Sprite2D = sheep._grass_patch.get_node("VanillaGrass0")
	var all_on_grass:bool = true
	var pixels:Image = tuft.texture.get_image()
	for fragment:Dictionary in first.parts:
		var pixel:Vector2 = tuft.to_local(first.global_position+fragment.origin)-tuft.offset
		var ix:int = int(floor(pixel.x))
		var iy:int = int(floor(pixel.y))
		if ix < 0 or ix >= 16 or iy < 0 or iy >= 16:
			all_on_grass = false
		elif pixels.get_pixel(ix,iy).a < 0.5:
			all_on_grass = false
	check(all_on_grass,"every fragment begins on actual opaque grass leaves")
	check(first.global_position == sheep._graze_ground_position() and first.floor_y == 0,"fragment ground matches grass root")
	var apex_time:float = -part.velocity.y/first.GRAVITY
	check(first.particle_position(part,apex_time).y < part.origin.y-5.0,"fragments rise clearly above their grass origin")
	var landed:float = first.landing_time(part)
	check(landed < 0.5,"stronger gravity lands debris within half second")
	var fall_early:float = first.particle_position(part,0.26).y-first.particle_position(part,0.24).y
	var fall_later:float = first.particle_position(part,0.30).y-first.particle_position(part,0.28).y
	check(fall_later > fall_early and fall_early > 0,"downward speed visibly increases over equal time steps")
	check(is_equal_approx(first.particle_position(part,landed+0.2).y,first.floor_y),"parabola lands exactly on ground")
	check(first.particle_alpha(part,landed+part.ground_wait*0.5)==1,"debris holds on ground before fade")
	check(first.particle_alpha(part,landed+part.ground_wait+0.2)<1,"debris fades on its own timer")
	first._process(4.0)
	check(first.is_queued_for_deletion() and not second.is_queued_for_deletion(),"one batch expires without deleting next batch")
	var no_rotation:bool = true
	for i:int in range(17):
		sheep._graze_elapsed = float(i)/16.0*sheep.graze_bite_interval
		sheep.visual_mob()
		if not is_zero_approx(sheep.image.rotation): no_rotation = false
	check(no_rotation,"whole bite animation never rotates sheep body")
	var shot = spawn("res://scenes/shooter/子弹.tscn",Vector2(120,0),"B")
	shot.direction = Vector2.LEFT
	shot.Speed = 5000
	shot.velocity = Vector2(-5000,0)
	sheep.wool = 3
	sheep._wool_phase = 0
	sheep._wool_cooldown = 0
	sheep._step_wool(0.01)
	check(sheep.wool==3 and not shot.has_meta("mc_wool_flight"),"fast but distant projectile is not pre-captured")
	check(not sheep.catch_wool_projectile(shot),"direct capture rejects distant projectile too")
	check(not sheep.WOOL_PROJECTILE.sweep(shot,Vector2(120,0),Vector2(80,0)),"flight not reaching sheep does not reflect")
	check(shot.global_position==Vector2(120,0),"rejected sweep does not move projectile")
	check(sheep.WOOL_PROJECTILE.sweep(shot,Vector2(120,0),Vector2(-80,0)),"crossing projectile intercepted")
	check(absf(shot.global_position.x-sheep.wool_projectile_radius)<0.05,"fast projectile advances to actual shell contact")
	check(shot.global_position.distance_to(sheep.global_position)<=22.05,"reflection only begins beside sheep")
	var controller = shot.get_meta("mc_wool_flight").get_ref()
	sheep.global_position += Vector2(40,0)
	controller._physics_process(0.02)
	check(shot.global_position.distance_to(sheep.global_position)<=22.05,"compression keeps shot near moving sheep")
	sheep._step_wool(0.15)
	check(controller.flying and shot.global_position.distance_to(sheep.global_position)<=22.05,"release starts at shell not distant old position")
	print("SHEEP_GRASS_RANDOM_CLOSE_REFLECT_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
