extends SceneTree
const SCENE_PATH:String = "res://scenes/characters/我的世界/火把.tscn"
const FIRE_PATH:String = "res://scripts/characters/我的世界/torch/torch_fire.gd"
const PAIRS_PATH:String = "res://classes/body_collision_exclusions.gd"
var world:Node
var game:Node
var saved:Dictionary
var saved_stop:bool
var checks:int = 0
var failures:int = 0
var done:bool = false

func _initialize() -> void: call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func spawn(path:String,point:Vector2,team:String = "Team0") -> Node2D:
	var unit:Node2D = load(path).instantiate() as Node2D
	unit.Team = team
	unit.Health_Restore = 0
	unit.position = point
	world.add_child(unit,true)
	return unit

func soul_look(unit:Node2D,burn:Node) -> bool:
	var tint:Color = unit.image.self_modulate
	var soul_tint:Color = burn.SOUL_BURN_TINT
	return burn.soul and burn._minecraft_burn_visual.sprite_frames == burn.SOUL_BURN_FRAMES and Vector3(tint.r,tint.g,tint.b).is_equal_approx(Vector3(soul_tint.r,soul_tint.g,soul_tint.b))

func dummy(point:Vector2,team:String = "Team1") -> Node2D:
	var target:Node2D = spawn("res://scenes/ball.tscn",point,team)
	target.Can_Attack = false
	target.Can_Skill = false
	target.Max_health = 10000
	target.default_properties["Max_health"] = 10000
	target.health = 10000
	target.Has_Collision_Damage = false
	target.state_machine.set_physics_process(false)
	return target

func has_knockback(unit:Node) -> bool:
	return unit.get_children().any(func(c:Node): return c.has_method("replace_with_hit"))

func sound_events() -> Array:
	return get_nodes_in_group("MCNativeSFX").map(func(n:Node): return str(n.get_meta("mc_sound_event","")))

func frames(n:int) -> void:
	for i:int in range(n): await physics_frame

## 按物理时间等待（无头运行时计时器的墙钟时间会快于物理时间），返回实际经过的物理时间。
func sim(seconds:float) -> float:
	var elapsed:float = 0.0
	await physics_frame
	while elapsed < seconds:
		await physics_frame
		elapsed += root.get_physics_process_delta_time()
	return elapsed

func clear_fires(torch:Node2D) -> void:
	for fire:Variant in torch.live_fires(): (fire as Node).queue_free()
	await process_frame
	torch._prune_fires()

func stop_sparks(torch:Node2D) -> void:
	torch.spark_interval = 999.0
	torch.soul_spark_interval = 999.0
	torch._spark_wait = 999.0

func settle_sparks() -> void:
	for i:int in range(120):
		if get_nodes_in_group("MCTorchSpark").is_empty(): return
		await physics_frame

## 触发一颗火星并等它落地，返回新生成的火（失败返回 null）。
func drop_spark(torch:Node2D) -> Variant:
	var before:Dictionary = {}
	for fire:Variant in torch.live_fires(): before[fire.get_instance_id()] = true
	torch.launch_spark()
	for i:int in range(90):
		await physics_frame
		for fire:Variant in torch.live_fires():
			if not before.has(fire.get_instance_id()): return fire
	return null

func finish(code:int) -> void:
	if done: return
	done = true
	print("TORCH RESULT: ",checks - failures,"/",checks," passed")
	if game != null:
		game.Game_Settings = saved
		game.now_stop_state = saved_stop
	if is_instance_valid(world):
		for node:Node in world.find_children("*","Node",true,false):
			if node.get_script() != null and node.get_script().resource_path.ends_with("mc_native_prewarm.gd"):
				node.set_process(false)
	var warm:Script = load("res://scripts/effects/我的世界/mc_native_prewarm.gd")
	for role:String in warm.CHARACTERS:
		var path:String = "res://scenes/characters/我的世界/" + role + ".tscn"
		var status:int = ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS or status == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(path)
	if is_instance_valid(world): world.queue_free()
	await process_frame
	quit(code)

func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(120.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	var map:Node = world.map_group["Map50x50"]
	var center:Vector2 = world.return_map_world_rect(map).get_center()
	var FIRE:Script = load(FIRE_PATH)
	var PAIRS:Script = load(PAIRS_PATH)
	var classifier:Script = load("res://classes/combat_classification.gd")

	# --- 场景与登记 ---
	var torch:Node2D = spawn(SCENE_PATH,center)
	stop_sparks(torch)
	torch.Speed = 0.0
	torch.default_properties["Speed"] = 0.0
	await physics_frame
	await process_frame
	await process_frame
	check(torch.Max_health == 700 and is_equal_approx(torch.Damage,10.0),"火把 stats 700 HP / 10 damage")
	var parked:Vector2 = torch.global_position
	check(world.return_all_character_names().has("火把"),"火把 appears in the Minecraft roster")
	check(torch.Unique_Death_Audio == torch.AUDIO.EVENTS["entity.item.break"][0].stream,"death uses native item break")
	check(str(classifier.profile_of(torch).get("entity_kind","")) == "character","torch classified as character")
	check(not torch.get_armor_test_effect_summary().is_empty(),"armor-stand introduction resolves")
	check(torch.call("is_combat_runtime_active"),"real World combat is active")
	var body:Rect2 = torch.body_rect()
	var tip:Vector2 = torch.tip_world_position()
	check(absf(tip.x - body.get_center().x) < 1.0 and tip.y < body.get_center().y - body.size.y * 0.3,"flame tip sits at the top of the torch body")
	check(torch.get_node_or_null("Graphics/Image/TipFlame") is Sprite2D,"head flame sprite rides on the torch image")

	# --- 灵魂沙：地图外一圈 + 随机向内蔓延 ---
	var field:Node2D = world.get_node_or_null("MCSoulSandField")
	check(field != null and torch.soul_sand_field() == field,"soul sand field singleton is created under World")
	if field == null:
		finish(1)
		return
	field.full_cover_seconds = 1.0e9
	field._grid_key = ""
	field._rebuild_grid()
	var visual:Rect2 = world.return_map_visual_rect(map)
	var floor_rect:Rect2 = world.return_map_world_rect(map)
	var walled:bool = visual.size.x > floor_rect.size.x + 0.5
	var g:float = field.grid_size.x
	var tuck:float = g * field.RING_INSET_CELLS if walled else 0.0
	check(field.ring_rects.size() >= 200 and field.ring_rects.all(func(r:Rect2): return not visual.grow(-tuck - 0.5).intersects(r) and not floor_rect.intersects(r)),"outer soul sand ring surrounds the map, at most half a block tucked under the wall")
	var outside_part:float = 0.0
	for r:Rect2 in field.ring_rects:
		if r.position.y + r.size.y <= visual.position.y + tuck + 0.01 and r.position.x > visual.position.x and r.end.x < visual.end.x: outside_part = maxf(outside_part,visual.position.y - r.position.y)
	check(walled and is_equal_approx(outside_part,g - tuck),"only half a block of the ring shows outside the wall (%.2f of %.2f)" % [outside_part,g])
	var ring_view:Node2D = field.get_node("OuterRing")
	check(not ring_view.z_as_relative and ring_view.z_index == -4,"outer ring shares the 3D wall layer (z -4) so the top-level walls and clouds order around it")
	check(not field.z_as_relative and field.z_index == -3,"soul sand inside the map is ground level under characters")
	check(field.floor_cells.size() == 2500,"every floor cell of the 50x50 map can turn into soul sand")
	check(field.cells.is_empty() and field.frontier_size() == 196,"spreading starts from the cells along the map edge")
	field._rng.seed = 20261002
	field._grid_key = ""
	field._rebuild_grid()
	field.full_cover_seconds = 20.0
	await sim(1.2)
	var lo := Vector2i(1 << 30,1 << 30)
	var hi := Vector2i(-(1 << 30),-(1 << 30))
	for cell:Vector2i in field.floor_cells:
		lo = Vector2i(mini(lo.x,cell.x),mini(lo.y,cell.y))
		hi = Vector2i(maxi(hi.x,cell.x),maxi(hi.y,cell.y))
	var depth_of := func(cell:Vector2i) -> int: return mini(mini(cell.x - lo.x,hi.x - cell.x),mini(cell.y - lo.y,hi.y - cell.y))
	var edge_count:int = 0
	var max_depth:int = 0
	var connected:bool = true
	for cell:Vector2i in field.cells:
		var depth:int = depth_of.call(cell)
		max_depth = maxi(max_depth,depth)
		if depth == 0: edge_count += 1
		elif not [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN].any(func(d:Vector2i): return field.cells.has(cell + d)): connected = false
	check(field.cells.size() >= 100,"soul sand keeps spreading during combat (%d cells)" % field.cells.size())
	check(max_depth >= 2 and edge_count < 196,"spread is random, not ring by ring (edge %d/196, deepest %d)" % [edge_count,max_depth])
	check(connected,"every new soul sand cell grows next to existing soul sand")
	# 像素随机蔓延：新格从已有灵魂沙的边缘按像素随机长，并溢到相邻格；整格长满才是正式灵魂沙。
	var fresh:Vector2i = Vector2i(-999,-999)
	for c:Vector2i in field.floor_cells:
		if field.cells.has(c) or not [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN].any(func(d:Vector2i): return field.cells.has(c + d)): continue
		# 至少两个相邻的空地面格，才有地方溢出。
		if [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN].filter(func(d:Vector2i): return field.floor_cells.has(c + d) and not field.cells.has(c + d)).size() >= 2:
			fresh = c
			break
	field.full_cover_seconds = 1.0e9
	field._add_cell(fresh,field._clock)
	check(field._growing.has(fresh) and not field.has_sand_at(field.cell_center(fresh)) and field.cell_pixel_count(fresh) < field.pixels_per_cell(),"a new soul sand cell starts growing and is not formal soul sand yet")
	await sim(field.GROW_SECONDS * 0.5)
	var total_px:int = field.pixels_per_cell()
	var half_px:int = field.cell_pixel_count(fresh)
	check(half_px > total_px / 4 and half_px < total_px and not field.has_full_sand_at(field.cell_center(fresh)),"half way through it is partly covered pixel by pixel and still not formal (%d/%d)" % [half_px,total_px])
	await sim(field.GROW_SECONDS * 0.6)
	check(field.has_full_sand_at(field.cell_center(fresh)) and field.cell_pixel_count(fresh) == total_px and not field._growing.has(fresh),"after %.1f s every pixel is covered and the cell becomes formal soul sand" % field.GROW_SECONDS)
	var spilled:int = 0
	var spill_formal:bool = false
	for d:Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		var n:Vector2i = fresh + d
		if field.floor_cells.has(n) and not field.cells.has(n):
			spilled += field.cell_pixel_count(n)
			spill_formal = spill_formal or field.has_sand_at(field.cell_center(n))
	check(spilled > 0 and not spill_formal,"pixels also creep into neighbouring cells, which do not become soul sand from that (%d px)" % spilled)
	# 只有长满的灵魂沙减速 20%；灵魂疾行 1 级抵消，之后每级 +20%。
	var enchants:Script = load("res://scripts/effects/我的世界/mc_enchantments.gd")
	# 测减速用地图中部的格子：贴边的格子会被墙把假人推出去。
	var full_cell:Vector2i = field.cell_of(center + Vector2(96.0,0.0))
	field.force_full(full_cell)
	var dummy_on_sand:Node2D = dummy(field.cell_center(full_cell))
	await sim(0.25)
	check(field.cell_of(dummy_on_sand.global_position) == full_cell and is_equal_approx(dummy_on_sand.motion_speed_factor(),0.8),"anyone on full soul sand moves 20%% slower (%.2f)" % dummy_on_sand.motion_speed_factor())
	var growing_cell:Vector2i = field.cell_of(center + Vector2(-96.0,0.0))
	field.cells.erase(growing_cell)
	field._add_cell(growing_cell,field._clock)
	var dummy_on_growing:Node2D = dummy(field.cell_center(growing_cell))
	await sim(0.25)
	check(is_equal_approx(dummy_on_growing.motion_speed_factor(),1.0),"sand that is still growing does not slow")
	dummy_on_growing.queue_free()
	enchants.apply(dummy_on_sand,"soul_speed",1)
	await sim(0.25)
	var source:int = dummy_on_sand.get_instance_id()
	var buffs:Dictionary = dummy_on_sand.Buff_Dic.get(source,{})
	check(is_equal_approx(dummy_on_sand.motion_speed_factor(),1.0) and not buffs.has("MC附魔灵魂疾行"),"Soul Speed I ignores the soul sand slowdown")
	enchants.apply(dummy_on_sand,"soul_speed",3)
	await sim(0.25)
	buffs = dummy_on_sand.Buff_Dic.get(source,{})
	check(is_equal_approx(dummy_on_sand.motion_speed_factor(),1.0) and buffs.has("MC附魔灵魂疾行") and is_equal_approx(float(buffs["MC附魔灵魂疾行"].amount),1.4),"Soul Speed III: +20% per level above I on soul sand (x1.4)")
	dummy_on_sand.global_position = field.cell_center(growing_cell)
	await sim(0.25)
	buffs = dummy_on_sand.Buff_Dic.get(source,{})
	check(not buffs.has("MC附魔灵魂疾行"),"the Soul Speed bonus ends off full soul sand")
	enchants.remove(dummy_on_sand,"soul_speed")
	dummy_on_sand.queue_free()
	field.full_cover_seconds = 0.5
	await sim(1.0)
	check(is_equal_approx(field.coverage(),1.0),"soul sand eventually covers the whole map")
	field.full_cover_seconds = 1.0e9
	field.clear_sand()
	torch.soul_charge = 0.0

	# --- 火星落地成火 ---
	check(torch.global_position.distance_to(parked) < 0.5,"test torch stays parked (no movement drift)")
	var origin:Vector2 = torch.global_position
	torch.launch_spark()
	await process_frame
	var sparks:Array = get_nodes_in_group("MCTorchSpark")
	check(sparks.size() == 1 and (sparks[0] as Node2D).global_position.distance_to(torch.tip_world_position()) < 3.0,"a spark leaves from the flame tip")
	if sparks.size() == 1:
		var flying:Node2D = sparks[0]
		var apex:Vector2 = flying.point_at(0.5)
		check(apex.y < minf(flying._from.y,flying._to.y) - 4.0 and flying._arc >= torch.spark_arc,"the spark flies up first and then falls to the ground (apex %.1f, from %.1f, to %.1f)" % [apex.y,flying._from.y,flying._to.y])
	check(sound_events().has("block.lava.pop"),"a native lava pop plays when the spark flies out")
	var fire:Variant = null
	for i:int in range(90):
		await physics_frame
		if not torch.live_fires().is_empty():
			fire = torch.live_fires()[0]
			break
	check(fire != null and get_nodes_in_group("MCTorchSpark").is_empty(),"the spark lands and becomes fire")
	if fire == null:
		finish(1)
		return
	var land:Vector2 = fire.damage_center()
	var fx:Node = world.get_node_or_null("MCTorchParticles")
	check(fx != null and fx.count(fx.KIND_SMOKE) > 3 and fx.count(fx.KIND_FLAME) > 3,"the torch tip keeps giving off native flame and smoke particles")
	await sim(0.8)
	var fire_smoke:int = 0
	if fx != null:
		for p:Dictionary in fx.particles:
			# 火冒的是原版大烟（尺寸 >= 6.5），火把尖端的烟更小。
			if int(p.kind) == fx.KIND_SMOKE and float(p.size) >= 6.5 and absf((p.pos as Vector2).x - land.x) < 20.0: fire_smoke += 1
	check(fire_smoke >= 2,"the ground fire gives off smoke (%d puffs)" % fire_smoke)
	check(sound_events().has("block.fire.ambient"),"the ground fire crackles with the native fire ambient sound")
	var cell:float = 16.0
	check(land.distance_to(origin) <= torch.spark_max_cells * cell + cell and land.distance_to(field.cell_center(field.cell_of(land))) < 0.01,"fire lands near the torch on a map cell centre")
	check(not fire.soul and is_equal_approx(fire.damage_radius(),cell * 0.5) and is_equal_approx(fire.tick_damage(),5.0),"normal fire: one-cell circle, Damage x 0.5 per tick")
	var info:Dictionary = fire.get_ai_hazard_info(null)
	check(fire.is_in_group("AI_Hazard") and info.get("shape") == "circle" and info.get("position") == land and is_equal_approx(float(info.get("radius",0.0)),fire.damage_radius()) and info.get("source") == torch,"fire threat circle equals its real damage circle")
	check(str(classifier.profile_of(fire).get("entity_kind","")) == "hazard","torch fire classified as hazard")
	check(not fire.z_as_relative and fire.z_index == 92,"fire draws above the map-outside mask like Blaze fire")
	var enemy:Node2D = dummy(land)
	var before:float = enemy.health
	await sim(0.7)
	var burn:Node = enemy.get_node_or_null("MinecraftBlazeBurn")
	check(enemy.health < before,"an enemy standing in the fire takes damage")
	check(burn != null and burn.source == torch and is_equal_approx(float(burn.tick_damage),3.0),"fire sets the enemy burning (Damage x 0.3 per burn tick)")
	check(burn != null and not burn.soul and burn._minecraft_burn_visual.sprite_frames == burn.MINECRAFT_BURN_FRAMES,"normal fire burns with the normal native fire look")
	var ally:Node2D = dummy(land,"Team0")
	var ally_before:float = ally.health
	await sim(0.6)
	check(is_equal_approx(ally.health,ally_before),"fire never hurts the torch's own team")
	ally.queue_free()
	enemy.queue_free()
	await clear_fires(torch)

	# --- 灵魂沙充能与灵魂火把 ---
	for c:Vector2i in field.floor_cells:
		if field.cell_rect(c).intersects(torch.body_rect()): field.force_full(c)
	var charged_time:float = await sim(1.0)
	var expected_charge:float = charged_time / torch.soul_charge_seconds
	check(absf(torch.soul_charge - expected_charge) < 0.03,"standing on soul sand fills the bar (%.3f after %.2f s, expected %.3f)" % [torch.soul_charge,charged_time,expected_charge])
	field.clear_sand()
	var held:float = torch.soul_charge
	await sim(0.4)
	check(is_equal_approx(torch.soul_charge,held),"the bar holds while off soul sand")
	for c:Vector2i in field.floor_cells: field.force_full(c)
	torch.soul_charge = 0.995
	await sim(0.5)
	check(torch.soul_form and torch.image.texture.resource_path.ends_with("soul_torch.png"),"a full bar turns it into a soul torch")
	check(torch.get_node("Graphics/Image/TipFlame").texture.resource_path.ends_with("soul_fire_flame.png"),"soul torch head burns with soul flame")
	check(sound_events().has("particle.soul_escape"),"native soul escape sound plays on the change")
	torch.soul_spark_interval = 0.3
	torch._spark_wait = 0.0
	await frames(2)
	check(torch._spark_wait > 0.2 and torch._spark_wait <= 0.3,"soul torch drops sparks faster")
	stop_sparks(torch)
	await settle_sparks()
	await clear_fires(torch)
	var soul_fire:Variant = await drop_spark(torch)
	check(soul_fire != null and soul_fire.soul and soul_fire._fire_block.soul and soul_fire._fire_block.textures() == soul_fire._fire_block.SOUL_FIRE_TEXTURES,"sparks landing on soul sand become soul fire")
	if soul_fire != null:
		check(is_equal_approx(soul_fire.tick_damage(),10.0) and is_equal_approx(soul_fire.burn_tick_damage(),6.0),"soul fire doubles ground damage and burn")
		check(soul_fire.get_ai_hazard_info(null).get("kind") == "torch_soul_fire","soul fire threat is labelled")
		var scorched:Node2D = dummy(soul_fire.damage_center())
		await physics_frame
		await physics_frame
		soul_fire._damage_inside(torch)
		var scorched_burn:Node = scorched.get_node_or_null("MinecraftBlazeBurn")
		check(scorched_burn != null and soul_look(scorched,scorched_burn),"standing in soul fire burns with the native soul fire look and soul tint")
		scorched.queue_free()
	var marked:Node2D = dummy(center + Vector2(-200,-200))
	FIRE.apply_burn(torch,marked,3.0,6.0,true)
	var marked_burn:Node = marked.get_node("MinecraftBlazeBurn")
	FIRE.apply_burn(torch,marked,3.0,3.0)
	check(is_equal_approx(float(marked_burn.tick_damage),6.0),"normal fire does not downgrade the same torch's soul burn")
	check(soul_look(marked,marked_burn),"the kept soul burn keeps its soul fire look")
	FIRE.SHARED_BURN.apply_amount(torch,marked,3.0,2.0)
	var tint:Color = marked.image.self_modulate
	check(not marked_burn.soul and marked_burn._minecraft_burn_visual.sprite_frames == marked_burn.MINECRAFT_BURN_FRAMES and Vector3(tint.r,tint.g,tint.b).is_equal_approx(Vector3(marked_burn.BURN_TINT.r,marked_burn.BURN_TINT.g,marked_burn.BURN_TINT.b)),"a plain fire refresh turns it back into the normal burning look")
	marked.queue_free()
	await clear_fires(torch)

	# --- 灵魂火连冲 ---
	var t:Vector2 = torch.global_position
	var b:Vector2 = torch.snap_to_cell(t + Vector2(64,0))
	var c2:Vector2 = torch.snap_to_cell(t + Vector2(64,64))
	torch._dash_cooldown_left = 0.0
	torch.spark_landed(9001,b,true,false)
	torch.spark_landed(9002,c2,true,false)
	var victim:Node2D = dummy(t.lerp(b,0.5))
	await physics_frame
	var victim_before:float = victim.health
	torch.spark_landed(9000,torch.snap_to_cell(t),true,false)
	var started:bool = false
	var knocked:bool = false
	var form_seen:bool = false
	var segment_ok:bool = false
	var body_peak:int = 0
	var hurt_sound:bool = false
	var trail_peak:int = 0
	var fx2:Node = null
	for i:int in range(180):
		await physics_frame
		if torch.dashing:
			started = true
			fx2 = world.get_node_or_null("MCTorchParticles")
			if fx2 != null:
				trail_peak = maxi(trail_peak,fx2.count(fx2.KIND_FLAME))
				var near:int = 0
				for p:Dictionary in fx2.particles:
					if int(p.kind) == fx2.KIND_FLAME and bool(p.soul) and (p.pos as Vector2).distance_to(torch.global_position) < 14.0: near += 1
				body_peak = maxi(body_peak,near)
			form_seen = form_seen or (not torch.image.visible and body_peak >= 25 and torch.get_node_or_null("Graphics/FlameForm") == null)
			hurt_sound = hurt_sound or sound_events().has("entity.player.hurt_on_fire")
			for region:Dictionary in torch.get_debug_attack_regions():
				if region.get("kind") == "torch_flame_dash" and region.get("shape") == "segment" and is_equal_approx(float(region.get("radius",0.0)),8.0): segment_ok = true
		knocked = knocked or has_knockback(victim)
		if started and not torch.dashing: break
	var drop:float = victim_before - victim.health
	check(started,"touching its own soul fire turns the torch into a dashing flame")
	check(form_seen,"while dashing the torch becomes a dense cluster of soul flame particles (%d near it)" % body_peak)
	check(trail_peak >= 40,"the dash leaves a dense trail of soul flame particles (%d)" % trail_peak)
	check(is_equal_approx(torch.attack_damage(torch.dash_damage_multiplier),30.0) and drop >= 29.0,"a dash hit deals 30 damage (%.1f)" % drop)
	check(hurt_sound,"burning an enemy with the dash plays the native hurt-on-fire sound")
	check(segment_ok,"the dash path is shown as a real threat segment")
	check(drop > 0.0 and torch._dash_hit.size() == 1 and torch._dash_hit.has(victim.get_instance_id()),"each enemy on the path is hit once per chain (%.1f damage)" % drop)
	var victim_burn:Node = victim.get_node_or_null("MinecraftBlazeBurn")
	check(victim_burn != null and is_equal_approx(float(victim_burn.tick_damage),6.0) and soul_look(victim,victim_burn),"dash hits apply soul-strength burn with the soul fire look")
	check(not knocked,"the dash passes straight through enemies without knockback")
	check(torch.dash_hops == 2 and torch.global_position.distance_to(c2) < 1.0,"the flame visits every reachable soul fire once and stops at the last")
	check(not torch.dashing and torch.image.visible and torch._dash_cooldown_left > 2.5,"it turns back into a torch with about 3 s cooldown")
	check(torch.soul_fires().size() == 3,"soul fires are not consumed")
	check(not PAIRS.are_excluded(torch,victim),"pass-through leases are released after the dash")
	check(sound_events().has("block.fire.extinguish") or sound_events().has("item.firecharge.use"),"native fire charge / extinguish sounds accompany the dash")
	await sim(0.5)
	check(not torch.dashing,"no new chain while cooling down even on a soul fire")
	victim.queue_free()
	await clear_fires(torch)

	# --- 被墙挡住的灵魂火跳过 ---
	t = torch.global_position
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var wall_shape := CollisionShape2D.new()
	var wall_rect := RectangleShape2D.new()
	wall_rect.size = Vector2(124,8)
	wall_shape.shape = wall_rect
	wall.add_child(wall_shape)
	wall.position = t + Vector2(38,-32)
	world.add_child(wall)
	await frames(3)
	var wall_blocks:bool = not torch.U.line_clear(torch,t,torch.snap_to_cell(t + Vector2(0,-64)))
	var open_fire:Vector2 = torch.snap_to_cell(t + Vector2(64,0))
	var hidden_fire:Vector2 = torch.snap_to_cell(t + Vector2(0,-64))
	torch._dash_cooldown_left = 0.0
	torch.spark_landed(9101,open_fire,true,false)
	torch.spark_landed(9102,hidden_fire,true,false)
	torch.spark_landed(9100,torch.snap_to_cell(t),true,false)
	started = false
	for i:int in range(180):
		await physics_frame
		if torch.dashing: started = true
		if started and not torch.dashing: break
	check(started and torch.dash_hops == 1 and torch.global_position.distance_to(open_fire) < 1.0,"soul fires behind walls are skipped (started %s, hops %d, at %s, open %s, hidden %s, wall blocks %s)" % [started,torch.dash_hops,torch.global_position,open_fire,hidden_fire,wall_blocks])
	wall.queue_free()
	await clear_fires(torch)

	# --- 死亡：火熄灭，灵魂沙消散 ---
	stop_sparks(torch)
	torch.spark_landed(9200,torch.snap_to_cell(torch.global_position + Vector2(48,0)),true,false)
	await physics_frame
	torch.health = 0
	await sim(2.5)
	check(get_nodes_in_group("MCTorchFire").is_empty(),"its fires go out after the torch dies")
	var left:Node = world.get_node_or_null("MCSoulSandField")
	check(left == null or bool(left.get("_retiring")),"soul sand fades once no torch is alive")
	finish(0 if failures == 0 else 1)
