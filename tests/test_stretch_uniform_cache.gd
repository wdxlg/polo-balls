extends SceneTree
var failures:int = 0
var checks:int = 0
var unit:Node
func _initialize() -> void:
	call_deferred("run")
func check_uniforms() -> void:
	var expected:Dictionary = {
		"source_flip_h":1.0 if unit._visual_facing_flipped_h else 0.0,
		"head_color":unit.AfterImage_Stretch_Head_Color,
		"tail_color":unit.AfterImage_Stretch_Tail_Color,
		"stretch_params":Vector4(unit.AfterImage_Stretch_Length,unit.AfterImage_Stretch_Head_Width,unit.AfterImage_Stretch_Tail_Width,unit.AfterImage_Stretch_Distortion_Pixels),
		"alpha_value":unit.AfterImage_Stretch_Alpha,
		"style_mode":int(unit.AfterImage_Style),
		"sample_count":clampi(unit.AfterImage_Stretch_Sample_Count,1,8),
		"region_params":unit._get_after_image_region_params()
	}
	for key:String in expected:
		checks += 1
		if unit._after_image_stretch_sprite.get_instance_shader_parameter(key) != expected[key]:
			failures += 1
			push_error("STRETCH_UNIFORM_MISMATCH " + key)
func run() -> void:
	unit = load("res://scenes/shooter/knife.tscn").instantiate()
	root.add_child(unit)
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	var world:Node2D = Node2D.new()
	root.add_child(world)
	current_scene = world
	for i:int in range(32):
		unit.AfterImage_Stretch_Head_Color = Color(0.5,float(i)/32.0,0.9,0.8)
		unit.AfterImage_Stretch_Tail_Color = Color(0.1,0.5,float(i)/32.0,0.2)
		unit.AfterImage_Stretch_Length = 16.0 + float(i)
		unit.AfterImage_Stretch_Head_Width = 0.2 + float(i)*0.02
		unit.AfterImage_Stretch_Tail_Width = 0.1 + float(i)*0.01
		unit.AfterImage_Stretch_Distortion_Pixels = float(i)*0.1
		unit.AfterImage_Stretch_Alpha = float(i)/32.0
		unit.AfterImage_Stretch_Sample_Count = i % 10
		unit.AfterImage_Style = i % 6
		unit._visual_facing_flipped_h = (i % 2) == 1
		unit.image.region_enabled = (i % 3) == 1
		unit.image.region_rect = Rect2(i,i,50,40)
		for repeat:int in range(2):
			unit._update_after_image_stretch(1.0/60.0,unit.image.global_transform,500.0,Vector2.RIGHT,true)
			check_uniforms()
	var prior:Transform2D = unit._after_image_stretch_sprite.global_transform
	unit._update_after_image_stretch(1.0/60.0,Transform2D.IDENTITY,0.0,Vector2.ZERO,false)
	checks += 1
	if unit._after_image_stretch_sprite.global_transform != prior:
		failures += 1
	unit._after_image_stretch_sprite.free()
	unit._update_after_image_stretch(1.0/60.0,unit.image.global_transform,500.0,Vector2.UP,true)
	check_uniforms()
	print("STRETCH_UNIFORM_TEST ",JSON.stringify({"checks":checks,"failures":failures}))
	current_scene = null
	unit.free()
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
