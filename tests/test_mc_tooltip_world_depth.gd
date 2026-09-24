extends SceneTree
## Real D3D12 pixel regression: Minecraft potion/enchantment frames remain above
## clipped map ground but below an actor, a projectile and an obstacle.
var checks:int = 0
var failures:int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MC_TOOLTIP_DEPTH_FAIL: "+label)

func swatch(parent:Node,color:Color) -> ColorRect:
	var rect:=ColorRect.new()
	rect.color = color
	rect.position = Vector2(-7,-7)
	rect.size = Vector2(14,14)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect

func difference(a:Color,b:Color) -> float:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))

func run() -> void:
	create_timer(50.0,true,false,true).timeout.connect(func(): quit(2))
	if DisplayServer.get_name() == "headless":
		print("MC_TOOLTIP_DEPTH_SKIPPED headless requires a real GPU")
		quit()
		return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1000,700)
	var backdrop:=ColorRect.new()
	backdrop.color = Color("363437")
	backdrop.size = Vector2(1000,700)
	backdrop.z_index = -8
	root.add_child(backdrop)
	var map:=Control.new()
	map.name = "ClippedBattleMap"
	map.position = Vector2(110,95)
	map.size = Vector2(405,510)
	map.z_index = -2 # The real World root uses -2.
	map.clip_contents = true
	root.add_child(map)
	current_scene = map
	var floor:=ColorRect.new()
	floor.color = Color("29372f")
	floor.size = map.size
	floor.z_index = -2 # World map tile -2 relative to World(-2) = -4.
	map.add_child(floor)
	var potion:Node2D = (load("res://scenes/characters/默认/药水测试盔甲架.tscn") as PackedScene).instantiate()
	potion.position = Vector2(345,155)
	potion.process_mode = Node.PROCESS_MODE_DISABLED
	potion.set("Team","A")
	map.add_child(potion,true)
	var pool:Array = potion.get("potion_pool")
	var chosen:Array[MCPreviewPotionEffect] = [pool[0] as MCPreviewPotionEffect,pool[1] as MCPreviewPotionEffect]
	potion.call("set_displayed_potions",chosen)
	var enchant:Node2D = (load("res://scenes/characters/默认/附魔测试盔甲架.tscn") as PackedScene).instantiate()
	enchant.position = Vector2(345,355)
	enchant.process_mode = Node.PROCESS_MODE_DISABLED
	enchant.set("Team","A")
	map.add_child(enchant,true)
	var enchants:Array = enchant.get("enchantment_pool")
	var selected:Array[MCPreviewEnchantment] = [enchants[0] as MCPreviewEnchantment]
	enchant.call("set_displayed_enchantments","附魔书",selected)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var potion_ui:MCPreviewTooltip = potion.get_node("Minecraft信息框") as MCPreviewTooltip
	var enchant_ui:MCPreviewTooltip = enchant.get_node("Minecraft信息框") as MCPreviewTooltip
	var p:Control = potion_ui._panel
	var e:Control = enchant_ui._panel
	var potion_rect:=Rect2(p.position,p.size*p.scale)
	var enchant_rect:=Rect2(e.position,e.size*e.scale)
	var points:Array[Vector2i] = [Vector2i(510,int(p.position.y+40)),Vector2i(510,int(p.position.y+75)),Vector2i(510,int(e.position.y+45))]
	check(potion_ui.top_level and enchant_ui.top_level and potion_ui.z_index == -3 and enchant_ui.z_index == -3 and p.visible and e.visible,"both screen-aligned frames use world Z between ground and foreground")
	check(potion_rect.has_point(Vector2(points[0])) and potion_rect.has_point(Vector2(points[1])) and enchant_rect.has_point(Vector2(points[2])) and points[0].x < int(map.position.x+map.size.x),"three foreground probes land inside the two frames and the clipped map")
	var without_foreground:Image = root.get_texture().get_image()
	var actor:Node2D = (load("res://scenes/ball.tscn") as PackedScene).instantiate()
	actor.name = "CharacterAboveTooltip"
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.set("Team","A")
	actor.position = Vector2(points[0])-map.position
	map.add_child(actor,true)
	swatch(actor,Color.CYAN)
	var projectile:=Area2D.new()
	projectile.name = "ProjectileAboveTooltip"
	projectile.position = Vector2(points[1])-map.position
	map.add_child(projectile)
	swatch(projectile,Color.GREEN)
	var obstacle:=StaticBody2D.new()
	obstacle.name = "ObstacleAboveTooltip"
	obstacle.position = Vector2(points[2])-map.position
	map.add_child(obstacle)
	swatch(obstacle,Color.YELLOW)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var covered:Image = root.get_texture().get_image()
	var r:Color = covered.get_pixelv(points[0])
	var g:Color = covered.get_pixelv(points[1])
	var y:Color = covered.get_pixelv(points[2])
	check(r.g > r.r*2.5 and r.b > r.r*2.5 and difference(r,without_foreground.get_pixelv(points[0]))>0.25,"actual character's foreground canvas draws over the potion frame")
	check(g.g > g.r*2.5 and g.g > g.b*2.5 and difference(g,without_foreground.get_pixelv(points[1]))>0.25,"projectile canvas draws over the potion frame")
	check(y.r > y.b*2.5 and y.g > y.b*2.5 and difference(y,without_foreground.get_pixelv(points[2]))>0.25,"obstacle canvas draws over the enchantment frame")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://mc_tooltip_world_depth"))
	var saved:Error = covered.save_png("user://mc_tooltip_world_depth/foreground_above_frames.png")
	actor.hide()
	projectile.hide()
	obstacle.hide()
	potion_ui.set_process(false)
	enchant_ui.set_process(false)
	p.hide()
	e.hide()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var ground:Image = root.get_texture().get_image()
	for i:int in range(points.size()):
		check(difference(without_foreground.get_pixelv(points[i]),ground.get_pixelv(points[i]))>0.02,"frame %d was really visible above map ground before occlusion" % i)
	check(saved == OK,"GPU saved visible overlap frame outside the repository")
	potion_ui.set_process(true)
	enchant_ui.set_process(true)
	var camera:=Camera2D.new()
	camera.position = Vector2(500,350)
	camera.zoom = Vector2(1.3,1.3)
	root.add_child(camera)
	camera.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	check(potion_ui.transform.is_equal_approx(root.get_canvas_transform().affine_inverse()) and enchant_ui.transform.is_equal_approx(root.get_canvas_transform().affine_inverse()) and p.visible and e.visible and absf(p.position.x-potion_rect.position.x)>5.0,"both frames follow zoomed camera in screen space while retaining world Z")
	print("MC_TOOLTIP_DEPTH_RESULT checks=%d failures=%d points=%s foreground=%s,%s,%s" % [checks,failures,points,r,g,y])
	quit(1 if failures>0 else 0)
