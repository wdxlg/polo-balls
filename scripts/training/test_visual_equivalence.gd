extends SceneTree
var failures:int = 0
var pixel_checks:int = 0
var random_checks:int = 0
var property_checks:int = 0
var unit:Node
var reference:RefCounted
var fixtures:Array[Node] = []
var gpu_equal:bool = false

func _initialize() -> void:
	call_deferred("_run")

func _fail(message:String) -> void:
	failures += 1
	if failures <= 8:
		push_error("VISUAL_MISMATCH " + message)

func _check_pixels(seed_value:int) -> void:
	var sampler:RefCounted = unit._make_visual_pixel_sampler()
	var rect:Rect2 = unit._hit_effect_visual_rect()
	var rng:RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	for i:int in range(200):
		var point:Vector2 = rect.position + rect.size * Vector2(rng.randf_range(-0.1,1.1),rng.randf_range(-0.1,1.1))
		var expected:Color = unit._sample_current_visual_pixel(point)
		var actual:Color = sampler.sample(point)
		pixel_checks += 1
		if expected != actual:
			_fail("pixel " + str(point) + " " + str(expected) + " != " + str(actual))
	for i:int in range(10):
		var a:RandomNumberGenerator = RandomNumberGenerator.new()
		var b:RandomNumberGenerator = RandomNumberGenerator.new()
		a.seed = seed_value + i
		b.seed = seed_value + i
		var outward:Vector2 = Vector2.RIGHT.rotated(float(i) * 0.63)
		var expected:Dictionary = reference.sample(unit,a,i % 2 == 0,outward,10.0,float(i) / 10.0)
		var actual:Dictionary = unit._random_hit_effect_visual_sample(b,i % 2 == 0,outward,10.0,float(i) / 10.0)
		random_checks += 1
		if expected != actual or a.state != b.state:
			_fail("streak sample or RNG state")

func _check_snapshot(source:Sprite2D) -> void:
	var expected:Sprite2D = source.duplicate()
	var actual:Sprite2D = unit._make_plain_sprite_snapshot(source)
	if actual == null:
		_fail("plain snapshot unexpectedly used fallback")
		expected.free()
		return
	for info:Dictionary in expected.get_property_list():
		var property_name:String = str(info["name"])
		if (int(info["usage"]) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		if property_name == "material" or property_name.begins_with("instance_shader_parameters/"):
			continue
		property_checks += 1
		if expected.get(property_name) != actual.get(property_name):
			_fail("snapshot property " + property_name)
	expected.free()
	actual.free()

func _run() -> void:
	reference = load("res://scripts/training/original_visual_reference.gd").new()
	unit = load("res://scenes/shooter/knife.tscn").instantiate()
	root.add_child(unit)
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	unit.image_color = Color(0.23,0.67,0.91,1.0)
	unit.image_color_mix = 0.37
	unit.modulate = Color(0.91,0.87,0.63,0.83)
	unit.self_modulate = Color(0.77,0.63,0.89,0.91)
	var image:Image = Image.create(48,32,false,Image.FORMAT_RGBA8)
	var rng:RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 9514
	for y:int in range(32):
		for x:int in range(48):
			image.set_pixel(x,y,Color(rng.randf(),rng.randf(),rng.randf(),float((x + y) % 5) * 0.25))
	var texture:ImageTexture = ImageTexture.create_from_image(image)
	var sprite:Sprite2D = Sprite2D.new()
	sprite.name = "ReferenceSprite"
	sprite.texture = texture
	sprite.offset = Vector2(-1.5,2.75)
	sprite.modulate = Color(0.9,0.8,0.7,0.8)
	sprite.self_modulate = Color(0.7,0.6,0.5,0.7)
	unit.get_node("Graphics").add_child(sprite)
	fixtures.append(sprite)
	unit.image = sprite
	for mode:int in range(3):
		sprite.region_enabled = mode == 2
		sprite.hframes = 3 if mode == 1 else 1
		sprite.vframes = 2 if mode == 1 else 1
		sprite.frame = 4 if mode == 1 else 0
		sprite.region_rect = Rect2(5,3,21,15)
		for flip:int in range(4):
			sprite.flip_h = (flip & 1) != 0
			sprite.flip_v = (flip & 2) != 0
			_check_pixels(100 + mode * 4 + flip)
			_check_snapshot(sprite)
	var animated:AnimatedSprite2D = AnimatedSprite2D.new()
	animated.sprite_frames = SpriteFrames.new()
	animated.sprite_frames.add_frame("default",texture)
	animated.sprite_frames.add_frame("default",texture)
	animated.offset = Vector2(3.25,-2.5)
	unit.get_node("Graphics").add_child(animated)
	fixtures.append(animated)
	unit.image = animated
	for flip:int in range(4):
		animated.flip_h = (flip & 1) != 0
		animated.flip_v = (flip & 2) != 0
		animated.centered = flip < 2
		animated.frame = flip % 2
		_check_pixels(200 + flip)
	unit.image = sprite
	sprite.flip_h = false
	sprite.flip_v = false
	var first:Sprite2D = sprite.duplicate()
	var second:Sprite2D = unit._make_plain_sprite_snapshot(sprite)
	var views:Array[SubViewport] = []
	for node:Sprite2D in [first,second]:
		var view:SubViewport = SubViewport.new()
		view.size = Vector2i(128,128)
		view.transparent_bg = true
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		view.add_child(node)
		node.material = load("res://shaders/after_image_material.tres")
		node.position = Vector2(64,64)
		node.scale = Vector2(3,3)
		node.set_instance_shader_parameter("progress",0.3)
		node.set_instance_shader_parameter("source_flip_h",1.0)
		node.set_instance_shader_parameter("trail_direction",Vector2(0.9,0.1))
		views.append(view)
	await RenderingServer.frame_post_draw
	var pixels_a:PackedByteArray = views[0].get_texture().get_image().get_data()
	var pixels_b:PackedByteArray = views[1].get_texture().get_image().get_data()
	gpu_equal = pixels_a == pixels_b and not pixels_a.is_empty()
	if not gpu_equal:
		_fail("GPU snapshot images differ")
	var result:Dictionary = {"pixel_checks":pixel_checks,"streak_and_rng_checks":random_checks,"snapshot_property_checks":property_checks,"gpu_snapshot_equal":gpu_equal,"failures":failures}
	var file:FileAccess = FileAccess.open("res://scripts/training/benchmark_visual_equivalence.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("VISUAL_RESULT ",JSON.stringify(result))
	for view:SubViewport in views:
		view.queue_free()
	unit.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
