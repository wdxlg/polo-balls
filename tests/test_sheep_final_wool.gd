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
	root.get_node("Game").now_stop_state = false
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var sheep = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2.ZERO,"A")
	for use:int in range(3):
		sheep._wool_cooldown = 0
		check(sheep._begin_wool(),"wool activation "+str(use))
		sheep.visual_mob()
		check(is_equal_approx(sheep._wool_visual.scale.x,1.35),"smaller 1.35 peak")
		check(sheep._wool_fixed_visual.scale==Vector2.ONE,"head and legs not inflated")
		if use < 2:
			sheep._step_wool(0.15)
			sheep.visual_mob()
			check(sheep._wool_visual.scale.x < 1,"first two layers retain elastic shrink")
			sheep._step_wool(0.31)
			sheep.visual_mob()
			check(sheep._wool_visual.visible and sheep._wool_visual.scale==Vector2.ONE,"remaining wool returns to normal")
			check(get_nodes_in_group("SheepWoolBreakFX").is_empty(),"no fragments before final layer")
		else:
			sheep._step_wool(0.08)
			sheep.visual_mob()
			check(is_equal_approx(sheep._wool_visual.scale.x,1.35),"last wool does not shrink")
			sheep._step_wool(0.03)
			sheep.visual_mob()
			check(sheep.wool==0 and sheep._wool_phase==0 and not sheep._wool_visual.visible,"last enlarged layer disappears directly")
			check(not sheep._wool_fixed_visual.visible and sheep.image.visible,"native sheared sheep remains")
			var debris:Array[Node] = get_nodes_in_group("SheepWoolBreakFX")
			check(debris.size()==1,"one debris burst on final use")
			var fx = debris[0]
			check(fx.parts.size()>=18 and not fx.leaf_samples.is_empty(),"debris sampled from actual wool pixels")
			var part:Dictionary = fx.parts[0]
			var landing:float = fx.landing_time(part)
			check(is_equal_approx(fx.particle_position(part,landing).y,fx.floor_y) or absf(fx.particle_position(part,landing).y-fx.floor_y)<0.001,"wool fragments land on ground")
			check(fx.particle_alpha(part,landing+0.5)>0 and fx.particle_alpha(part,landing+3)==0,"fragments linger then fade")
			sheep._receive_wool_break(sheep._wool_break_serial)
			check(get_nodes_in_group("SheepWoolBreakFX").size()==1,"duplicate visual event emits no extra debris")
	check(not sheep._begin_wool(),"no defence without wool")
	print("SHEEP_FINAL_WOOL_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
