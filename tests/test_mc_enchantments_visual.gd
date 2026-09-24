extends SceneTree
## Real rendering-display regression: an enchanted sprite must produce visible animated pixels.
## Run WITHOUT --headless. Saves samples to user://mc_enchantments_visual/.
const ENCHANT = preload("res://scripts/effects/我的世界/mc_enchantments.gd")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("MC_ENCHANT_VISUAL requires a GPU rendering display, not --headless")
		quit(2)
		return
	var view := SubViewport.new()
	view.size = Vector2i(128,128)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var image := Image.create(64,64,false,Image.FORMAT_RGBA8)
	image.fill(Color(0.40,0.40,0.40,1.0))
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.position = Vector2(64,64)
	view.add_child(sprite)
	await RenderingServer.frame_post_draw
	var base:Image = view.get_texture().get_image()
	if not ENCHANT.apply(sprite,"thorns",17):
		quit(1)
		return
	await RenderingServer.frame_post_draw
	var first:Image = view.get_texture().get_image()
	ENCHANT.ensure(sprite)._process(9.0)
	await RenderingServer.frame_post_draw
	var second:Image = view.get_texture().get_image()
	var visible:int = 0
	var animated:int = 0
	for y:int in range(32,96):
		for x:int in range(32,96):
			var a:Color = base.get_pixel(x,y)
			var b:Color = first.get_pixel(x,y)
			var c:Color = second.get_pixel(x,y)
			if absf(b.r-a.r)+absf(b.g-a.g)+absf(b.b-a.b) > 0.02: visible += 1
			if absf(c.r-b.r)+absf(c.g-b.g)+absf(c.b-b.b) > 0.02: animated += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://mc_enchantments_visual"))
	var output:Error = second.save_png("user://mc_enchantments_visual/enchanted.png")
	print("MC_ENCHANT_VISUAL visible_pixels=",visible," animated_pixels=",animated," png_error=",output)
	view.queue_free()
	quit(0 if visible>100 and animated>100 and output==OK else 1)
