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
	sheep.visual_mob()
	var fixed:Sprite2D = sheep._wool_fixed_visual
	var body:Sprite2D = sheep._wool_visual
	var transform:Transform2D = fixed.global_transform
	var root_scale:Vector2 = sheep.image.scale
	check(body.material == null,"inflatable body no longer color-selects head pixels")
	check((body.texture as AtlasTexture).atlas.resource_path.ends_with("sheep_wool_body.png"),"body uses torso-only native bake")
	check((fixed.texture as AtlasTexture).atlas.resource_path.ends_with("sheep_wool_fixed.png"),"head uses independent native bake")
	check(fixed.get_parent() == sheep.image and not body.is_ancestor_of(fixed),"head is not parented under expanding wool")
	var head_texture:Texture2D = fixed.texture
	for phase:int in [1,2]:
		for time:float in [0.0,0.035,0.07,0.13,0.20]:
			sheep._wool_phase = phase
			sheep._wool_elapsed = time
			sheep.visual_mob()
			check(fixed.global_transform.is_equal_approx(transform),"head transform fixed through pulse "+str(phase)+" "+str(time))
			check(fixed.texture == head_texture,"head native frame unchanged by pulse")
	sheep._wool_phase = 1
	sheep._wool_elapsed = 0.0
	sheep.visual_mob()
	check(body.scale.x > 1.3,"body wool expands immediately")
	sheep._wool_phase = 2
	sheep._wool_elapsed = 0.0
	sheep.visual_mob()
	check(body.scale.x > 1.3 and fixed.scale == Vector2.ONE,"only body wool expands")
	check(sheep.image.scale == root_scale,"defence leaves whole-body scale unchanged")
	sheep._wall_squash_age = 0.065
	sheep._wall_squash_axis = Vector2.RIGHT
	sheep._wall_squash_strength = 1
	sheep.visual_mob()
	check(not fixed.global_transform.is_equal_approx(transform),"separate wall crash animation still deforms whole sheep")
	print("SHEEP_FIXED_HEAD_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
