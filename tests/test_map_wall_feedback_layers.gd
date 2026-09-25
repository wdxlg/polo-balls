extends SceneTree
# Real World + actual damage/health scenes; GPU comparisons, including an old-layer negative control.
var checks:int = 0
var failures:int = 0
class HealthOwner:
	extends Node2D
	var Max_health:int = 1000
	var health:int = 1000
	var max_block:int = 100
	var max_energy:int = 100

func _initialize() -> void:
	_run.call_deferred()

func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("WALL_FEEDBACK FAIL: "+label)

func _frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw

func _changed(a:Image,b:Image,rect:Rect2) -> int:
	var ratio:Vector2 = Vector2(a.get_size())/root.get_visible_rect().size
	var canvas:Transform2D = root.get_canvas_transform()
	var from:Vector2i = Vector2i((canvas*rect.position)*ratio)
	var to:Vector2i = Vector2i((canvas*rect.end)*ratio)
	var changed:int = 0
	for y:int in range(maxi(from.y,0),mini(to.y,a.get_height())):
		for x:int in range(maxi(from.x,0),mini(to.x,a.get_width())):
			var c:Color = a.get_pixel(x,y)
			var d:Color = b.get_pixel(x,y)
			if absf(c.r-d.r)+absf(c.g-d.g)+absf(c.b-d.b)>0.045: changed += 1
	return changed

func _probe(parent:Node,point:Vector2,z:int,color:Color) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([Vector2(-2,-2),Vector2(2,-2),Vector2(2,2),Vector2(-2,2)])
	p.position = point
	p.z_as_relative = false
	p.z_index = z
	p.color = color
	parent.add_child(p)
	return p

func _run() -> void:
	create_timer(115.0,true,false,true).timeout.connect(func():quit(2))
	var folder:String = "user://wall_feedback_layers"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	AudioServer.set_bus_mute(0,true)
	var game:Node = root.get_node("Game")
	var old:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Map_Background = "blue"
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.day_night_cycle.advancing = false
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	world.control.hide()
	var physical:Rect2 = world.map_island_rects(world.map_group["Map10x10"])[0]
	var cell:Vector2 = world.map_visual_cell_size(world.map_group["Map10x10"])
	var center:Vector2 = Vector2(physical.get_center().x,physical.position.y-cell.y*0.5)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	camera.zoom = Vector2.ONE*4.0
	camera.global_position = center
	camera.force_update_scroll()
	# Enter these BEFORE the wall is created, so equal-Z draw-order regressions are exposed.
	var actor := HealthOwner.new()
	var health:Control = load("res://scenes/health_bar.tscn").instantiate()
	actor.add_child(health)
	health.owner = actor
	health.scale = Vector2.ONE*0.01
	health.z_as_relative = false
	health.z_index = 99
	actor.position = center+Vector2(-52,0)
	world.add_child(actor)
	var damage:Label = load("res://scenes/damage_text.tscn").instantiate()
	# Freeze just the flight in this ordering fixture; use the real scene/font/amount styling.
	damage.set_multiplayer_authority(2)
	damage.configure_amount(150)
	world.add_child(damage)
	damage.scale = Vector2.ONE*0.65
	await _frame()
	damage.position = center+Vector2(-14,0)-damage.size*0.325
	var probes:Array[Polygon2D] = []
	for z:int in range(91,100):
		probes.append(_probe(world,center+Vector2(20+(z-91)*6,0),z,Color(1,0.2,0.8)))
	var shadow_point:Vector2 = Vector2(physical.get_center().x-cell.x*2,physical.position.y+cell.y*0.3)
	var ground_actor:Polygon2D = _probe(world,shadow_point,1,Color(0.95,0.95,0.95))
	var outside:Polygon2D = _probe(world,center+Vector2(0,-cell.y*2),1,Color.MAGENTA)
	var health_rect := Rect2(actor.position-Vector2(12,12),Vector2(24,24))
	var damage_rect := Rect2(center+Vector2(-34,-14),Vector2(40,28))
	var shadow_rect := Rect2(shadow_point-Vector2(2,2),Vector2(4,4))
	var wall_rect := Rect2(center+Vector2(-75,-7),Vector2(150,14))
	for style:String in ["grass","sand","stone","nether","end"]:
		game.set_runtime_game_setting("Map_Background",style,false)
		world.refresh_map_presentation()
		await _frame()
		var volume:Node2D = world.map_wall_volume
		var actual:Image = root.get_texture().get_image()
		var old_z:int = volume.z_index
		var old_shadow_z:int = volume.shadow_picture.z_index
		var old_relative:bool = volume.shadow_picture.z_as_relative
		var old_index:int = volume.get_index()
		# Wall and ground shadow precede the background snapshot and ALL feedback,
		# including the low-Z potion/enchantment frames tested in test_map_wall_tooltips.
		volume.z_index = -4
		volume.shadow_picture.z_as_relative = false
		volume.shadow_picture.z_index = -4
		await _frame()
		var expected:Image = root.get_texture().get_image()
		# Negative control exactly recreates the reported wall99 / shadow98 ordering.
		volume.z_index = 99
		volume.shadow_picture.z_as_relative = true
		volume.shadow_picture.z_index = -1
		world.move_child(volume,world.get_child_count()-1)
		await _frame()
		var legacy:Image = root.get_texture().get_image()
		print("WALL_FEEDBACK_PIXELS ",style," current_damage=",_changed(actual,expected,damage_rect)," current_health=",_changed(actual,expected,health_rect)," legacy_damage=",_changed(legacy,expected,damage_rect)," legacy_health=",_changed(legacy,expected,health_rect))
		check(_changed(actual,expected,damage_rect)<=2 and _changed(legacy,expected,damage_rect)>10,style+": real damage digits visible over wall; legacy layering demonstrably hides them")
		check(_changed(actual,expected,health_rect)<=2 and _changed(legacy,expected,health_rect)>10,style+": actual health scene visible even when created before wall")
		for i:int in range(probes.size()):
			var r := Rect2(probes[i].position-Vector2(2,2),Vector2(4,4))
			check(_changed(actual,expected,r)<=2 and _changed(legacy,expected,r)>4,"%s: z%d feedback remains above wall" % [style,91+i])
		check(_changed(actual,expected,shadow_rect)<=2 and _changed(legacy,expected,shadow_rect)>4,style+": ground shadow does not tint world actor")
		if style=="grass":
			actual.save_png(folder+"/current.png")
			expected.save_png(folder+"/expected.png")
			legacy.save_png(folder+"/legacy.png")
		volume.z_index = old_z
		volume.shadow_picture.z_as_relative = old_relative
		volume.shadow_picture.z_index = old_shadow_z
		world.move_child(volume,old_index)
		outside.hide()
		await _frame()
		check(_changed(actual,root.get_texture().get_image(),Rect2(outside.position-Vector2(3,3),Vector2(6,6)))==0,style+": outside mask still removes out-of-bounds foreground")
		outside.show()
		volume.picture.hide()
		await _frame()
		check(_changed(actual,root.get_texture().get_image(),wall_rect)>50,style+": outside-facing wall survives map mask at lower layer")
		volume.picture.show()
		check(volume.z_index==-4 and volume.shadow_picture.z_index==-4 and not volume.shadow_picture.z_as_relative,style+": background-layer contract survives theme refresh")
		world.refresh_map_presentation()
		await _frame()
		check(volume.z_index<world.map_clip_backbuffer.z_index+world.z_index and _changed(actual,root.get_texture().get_image(),wall_rect)<=2,style+": refresh keeps wall in background snapshot without losing visible wall")
	ground_actor.queue_free()
	game.Game_Settings = old
	world.queue_free()
	await process_frame
	print("WALL_FEEDBACK checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
