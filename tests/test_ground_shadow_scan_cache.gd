extends SceneTree
## 角色地面阴影像素扫描缓存：缓存命中结果必须与重新扫描完全一致（含左右翻转、不同位置）。
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
	var game:Node = root.get_node("Game")
	game.Game_Settings["Training_Mode"] = false
	game.Game_Settings["Training_Mode_Type"] = "manual"
	game.now_stop_state = false
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func() -> void: current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	await create_timer(0.8).timeout
	world._battle_random_seed = game.begin_battle_random(20260914)
	var border:Dictionary = world.return_now_map_border()
	var origin:Vector2 = border["start"] + Vector2(200,200)
	var names:Array = ["剑客","盾狗","战争女神","菊花茶"]
	for character_name in names:
		var before:Array = get_nodes_in_group("Ball")
		world.create_char("Team0",character_name,origin)
		world.create_char("Team1",character_name,origin + Vector2(137,-61))
		await process_frame
		var spawned:Array = []
		for node in get_nodes_in_group("Ball"):
			if not before.has(node) and node.get("Type") == 0: spawned.append(node)
		if spawned.size() < 2:
			check(false,"spawn %s" % character_name); continue
		var a = spawned[0]
		var b = spawned[1]
		await process_frame
		await process_frame
		if b.has_method("set_character_visual_flip_h"): b.set_character_visual_flip_h(true)
		var rect_a:Rect2 = a._hit_effect_visual_rect()
		var sampler_a:RefCounted = a._make_visual_pixel_sampler()
		var fresh:Dictionary = a._character_ground_shadow_scan(rect_a,sampler_a)
		var cached:Dictionary = a._character_ground_shadow_scan_cached(rect_a,sampler_a)
		check(fresh == cached,"%s: cached scan == fresh scan" % character_name)
		var again:Dictionary = a._character_ground_shadow_scan_cached(rect_a,sampler_a)
		check(again == fresh,"%s: second hit identical" % character_name)
		var metrics_a:Dictionary = a._character_ground_shadow_body_metrics()
		var metrics_b:Dictionary = b._character_ground_shadow_body_metrics()
		if not metrics_a.is_empty() and not metrics_b.is_empty():
			check(absf(float(metrics_a["body_width"]) - float(metrics_b["body_width"])) < 0.01,"%s: width equal across instances" % character_name)
			var fp_a:Vector2 = metrics_a["foot_point"]
			var fp_b:Vector2 = metrics_b["foot_point"]
			check(absf(fp_a.y - fp_b.y) < 0.01,"%s: foot y equal (local)" % character_name)
			# 镜像实例的脚点 X 应是镜像值（或对称图相同）
			check(absf(absf(fp_a.x) - absf(fp_b.x)) < 0.6,"%s: foot |x| symmetric under flip (%.2f vs %.2f)" % [character_name,fp_a.x,fp_b.x])
		# 翻转后的 sampler 必须走不同 key，且结果与该状态下的重新扫描一致
		var rect_b:Rect2 = b._hit_effect_visual_rect()
		var sampler_b:RefCounted = b._make_visual_pixel_sampler()
		check(b._character_ground_shadow_scan(rect_b,sampler_b) == b._character_ground_shadow_scan_cached(rect_b,sampler_b),"%s: flipped cached == fresh" % character_name)
		a.queue_free(); b.queue_free()
		await process_frame
	print("GROUND_SHADOW_CACHE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures > 0 else 0)

