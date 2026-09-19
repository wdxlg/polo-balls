extends SceneTree
## 盾狗刺网：纹理/可读 Image 跨实例共享，碎屑仍能采到不透明像素。
var checks:int = 0
var failures:int = 0
func check(cond:bool,label:String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: " + label)
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var wire_script:Script = load("res://scripts/effects/三角洲_铁丝网.gd")
	var a:Node2D = wire_script.new()
	var b:Node2D = wire_script.new()
	root.add_child(a)
	root.add_child(b)
	await process_frame
	await process_frame
	var ta:Texture2D = a.get("_wire_texture")
	var tb:Texture2D = b.get("_wire_texture")
	check(ta != null,"wire texture loaded")
	check(ta == tb,"texture shared across instances")
	var ia:Image = a.get("_wire_texture_image")
	var ib:Image = b.get("_wire_texture_image")
	check(ia != null and not ia.is_empty(),"readable image present")
	check(ia == ib,"image shared across instances")
	check(ia != null and not ia.is_compressed(),"image is decompressed/readable")
	var opaque:int = 0
	if ia != null:
		for y in range(0,ia.get_height(),16):
			for x in range(0,ia.get_width(),16):
				if ia.get_pixel(x,y).a > 0.5: opaque += 1
	check(opaque > 0,"image has opaque pixels (%d)" % opaque)
	var dog_script:Script = load("res://scripts/characters/三角洲/盾狗.gd")
	var t1:Texture2D = dog_script._load_shield_texture(dog_script.SHIELD_DOG_TEXTURE_PATH)
	var t2:Texture2D = dog_script._load_shield_texture(dog_script.SHIELD_DOG_TEXTURE_PATH)
	check(t1 != null and t1 == t2,"shield dog texture cached")
	print("WIRE_CACHE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures > 0 else 0)

