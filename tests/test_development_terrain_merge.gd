extends SceneTree
## Merge regression: world-space moss/silk and TWO-LANE shared 24px managers.
## Run: Godot.4.7.2.offline.exe --headless --path . --script tests/test_development_terrain_merge.gd
var snow_script:Script
var rails_script:Script
var world:Node2D
var game:Node
var settings:Dictionary
var checks:int = 0
var failures:int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func close(a:Vector2,b:Vector2) -> bool:
	return a.distance_to(b) < 0.1

func entry(id:int,team:String,side:String,character:String,relative:Vector2) -> Dictionary:
	var point:Vector2 = world._development.base_rect.get_center()+relative
	return {"id":id,"char":character,"team":team,"scene_path":"res://scenes/characters/我的世界/%s.tscn" % character,
		"x":point.x,"y":point.y,"development_base_position":true,"development_lane_key":side+":0"}

func make_head(id:int,cell:Vector2i,owner:Node) -> Dictionary:
	var point:Vector2 = snow_script.point_at(cell)
	return {"id":id,"cell":cell,"point":point,"start":point+Vector2(0,-30),"landed":true,"blocks":1,
		"elapsed":0.32,"duration":0.32,"pending":false,"face_right":false,"visual_scale":1.0,
		"family":str(owner.Team),"team":owner.Team,"source":weakref(owner)}

func run() -> void:
	create_timer(85.0,true,false,true).timeout.connect(func(): print("TIMEOUT"); quit(2))
	game = root.get_node("Game")
	snow_script = load("res://scripts/characters/我的世界/snow_golem/snow_field.gd")
	rails_script = load("res://scripts/characters/我的世界/minecart/powered_rails.gd")
	settings = game.Game_Settings.duplicate(true)
	game.Game_Settings.Development_Mode = true
	game.Game_Settings.Development_Duration = 120.0
	game.Game_Settings.Development_Speed = 1.0
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Map_Background = "blue"
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	await process_frame
	await process_frame
	world.control.team.show()
	var dev:Variant = world._development
	check(dev.phase == dev.SETUP,"development starts with two separate arenas")
	var chosen_map:String = world.now_choose_map
	for map_name:String in ["Map10x10","Map30x30","Map50x50","Map_Portal"]:
		dev.cleanup(false)
		world.now_choose_map = map_name
		dev.prepare()
		var a:Vector2 = dev._offset("left:0")
		var b:Vector2 = dev._offset("right:0")
		check(is_equal_approx(fmod(absf(a.x),48.0),0.0) and is_equal_approx(fmod(absf(b.x),48.0),0.0) and b.x-a.x > dev.base_rect.size.x,
			map_name+": two complete maps stay separate and both grid phases survive their individual offsets")
	dev.cleanup(false)
	world.now_choose_map = chosen_map
	dev.prepare()
	var left:Vector2 = dev._offset("left:0")
	var right:Vector2 = dev._offset("right:0")
	check(is_equal_approx(fmod(absf(left.x),48.0),0.0) and is_equal_approx(fmod(absf(right.x),48.0),0.0),"each map's offset preserves both the 16px and 24px grid phase")
	var moss_left:Node = world._spawn_character_from_setup(entry(801,"Team0","left","苔藓",Vector2(-32,0)))
	var moss_right:Node = world._spawn_character_from_setup(entry(802,"Team1","right","苔藓",Vector2(32,0)))
	var spider_left:Node = world._spawn_character_from_setup(entry(803,"Team0","left","蜘蛛",Vector2(0,-48)))
	var spider_right:Node = world._spawn_character_from_setup(entry(804,"Team1","right","蜘蛛",Vector2(0,48)))
	check(is_instance_valid(moss_left) and is_instance_valid(moss_right) and is_instance_valid(spider_left) and is_instance_valid(spider_right),"actual moss and spider units spawn on both lanes")
	if not is_instance_valid(moss_left) or not is_instance_valid(spider_left) or not is_instance_valid(moss_right) or not is_instance_valid(spider_right):
		quit(2)
		return
	for actor:Node in [moss_left,moss_right,spider_left,spider_right]:
		actor.Can_Attack = false
		actor.Can_Skill = false
		actor.Speed = 0.0
		actor.Health_Restore = 0.0
	await process_frame
	var silk_left:Node2D = spider_left.get_node("SpiderSilk")
	var silk_right:Node2D = spider_right.get_node("SpiderSilk")
	check(silk_left.global_position == Vector2.ZERO and silk_right.global_position == Vector2.ZERO,"both silk services draw in world coordinates")
	var base_moss_point:Vector2 = moss_left.point_for_cell(moss_left.cell_at(dev.base_rect.get_center()+Vector2(-32,0)))
	for data:Array in [[moss_left,left],[moss_right,right]]:
		var actor:Node = data[0]
		var offset:Vector2 = data[1]
		actor.patches.append({"point":base_moss_point+offset,"layers":2,"serial":1})
		actor._growth_pending.append({"point":base_moss_point+offset+Vector2(16,0),"layer":0})
		actor.burrowing = true
		actor.burrow_origin = actor.global_position
		actor.burrow_destination = base_moss_point+offset
	var wall:Node2D = Node2D.new()
	wall.name = "DevelopmentSilkWall"
	world.add_child(wall)
	wall.global_position = spider_left.global_position+Vector2(-36,0)
	wall.add_to_group("BattleTransient")
	for data:Array in [[spider_left,silk_left,left],[spider_right,silk_right,right]]:
		var spider:Node = data[0]
		var silk:Node2D = data[1]
		var offset:Vector2 = data[2]
		var a:Dictionary = silk._make_anchor(spider.global_position+Vector2(-36,0),wall if spider == spider_left else null)
		var b:Dictionary = silk._make_anchor(spider.global_position+Vector2(36,0),null)
		silk.segments.append({"id":1,"start":a,"end":b})
		silk.anchor = b
		silk.live_id = 2
		silk.webs["web"] = {"point":dev.base_rect.get_center()+Vector2(0,-48 if offset==left else 48)+offset,"hunters":[],"cooldowns":{}}
		silk._previous[123] = a.point
		silk._previous_lines[1] = [a.point,b.point]
	var old_silk_left:Vector2 = silk_left.segments[0].start.point
	var old_silk_right:Vector2 = silk_right.segments[0].start.point
	var old_web_left:Vector2 = silk_left.webs["web"].point
	var old_web_right:Vector2 = silk_right.webs["web"].point
	var snow:Node2D = snow_script.ensure(world)
	var rails:Node2D = rails_script.new()
	rails.name = "MinecartRails"
	world.add_child(rails)
	rails.add_to_group("BattleTransient")
	var base_cell:Vector2i = snow_script.cell_at(dev.base_rect.get_center())
	var snow_left_cell:Vector2i = base_cell+Vector2i(roundi(left.x/24.0),roundi(left.y/24.0))
	var snow_right_cell:Vector2i = base_cell+Vector2i(roundi(right.x/24.0),roundi(right.y/24.0))
	snow.patches[snow_left_cell] = {"level":2,"family":"L","team":"Team0","source":weakref(moss_left),"expires_at":11.0,"half_lifetime":4.0}
	snow.patches[snow_right_cell] = {"level":1,"family":"R","team":"Team1","source":weakref(moss_right),"expires_at":18.0,"half_lifetime":4.0}
	snow.heads[1] = make_head(1,snow_left_cell,moss_left)
	snow.heads[2] = make_head(2,snow_right_cell,moss_right)
	snow._positions[spider_left.get_instance_id()] = snow_script.point_at(snow_left_cell)
	var ice_script:Script = load("res://scripts/effects/我的世界/sulfur_ice_trail.gd")
	var ice:Node2D = ice_script.new()
	world.add_child(ice)
	ice.setup(moss_left,Rect2(snow_script.point_at(snow_left_cell)-Vector2.ONE*12.0,Vector2.ONE*24.0))
	var ice_before:Rect2 = ice.cell_rect
	for offset:Vector2 in [left,right]:
		var rail_cell:Vector2i = rails.world_to_cell(snow_script.point_at(base_cell)+offset)
		var a:int = rails._node(rail_cell,offset == left,true)
		var b:int = rails._node(rail_cell+Vector2i.RIGHT,false,true)
		rails._connect(a,b)
	rails._publish()
	check(rails.nodes.size() == 4 and snow.patches.size() == 2,"both teams own data in the two shared terrain managers")
	# Adding a reserve re-centers the active fighter's development map. Its
	# already-placed ground cannot be left behind before the merge even starts.
	game.Game_Settings.Training_Mode_Type = "rotation"
	world._rotation_rosters["left"] = [{"id":801},{"id":805}]
	world._rotation_rosters["right"] = [{"id":802}]
	dev._sync_lanes(false)
	var rearranged:Vector2 = dev._offset("left:0")-left
	var moved_snow:Vector2i = snow_left_cell+Vector2i(roundi(rearranged.x/24.0),roundi(rearranged.y/24.0))
	check(not rearranged.is_zero_approx() and close(moss_left.patches[0].point,base_moss_point+left+rearranged) and close(spider_left.global_position,dev.base_rect.get_center()+Vector2(0,-48)+left+rearranged),"roster re-centering carries character and moss together")
	check(close(silk_left.segments[0].start.point,old_silk_left+rearranged) and close(wall.global_position,old_silk_left+rearranged),"silk anchor and attached obstacle move together when adding a reserve")
	check(snow.patches.has(moved_snow) and snow.heads[1].cell == moved_snow and not snow.patches.has(snow_left_cell),"snow manager rekeys its old lane when reserve count changes")
	check(not rails.cell_at(snow_script.point_at(moved_snow)).is_empty() and rails.nodes.size() == 4,"rail graph rekeys without losing lanes before combat")
	check(close(ice.cell_rect.get_center(),ice_before.get_center()+rearranged) and close(ice.cell_rect.get_center(),ice.global_position),"ice hitbox follows its node during roster re-centering")
	game.Game_Settings.Training_Mode_Type = "manual"
	dev._sync_lanes(false)
	check(close(moss_left.patches[0].point,base_moss_point+left) and close(silk_left.segments[0].start.point,old_silk_left) and snow.patches.has(snow_left_cell) and rails.nodes.size() == 4 and close(ice.cell_rect.get_center(),ice_before.get_center()),"return to manual lanes restores every terrain coordinate before merging")
	world.control.team.hide()
	dev.update(0.1)
	check(dev.phase == dev.RUNNING,"terrain is committed before the growth-to-battle transition")
	dev._begin_merge()
	check(dev.phase == dev.MERGING and snow.process_mode == Node.PROCESS_MODE_DISABLED,"merge freezes persistent terrain updates")
	dev._merge_frame(0.5)
	var half_left:Vector2 = left*0.75
	var half_right:Vector2 = right*0.75
	check(close(moss_left.patches[0].point,base_moss_point+half_left) and close(moss_right.patches[0].point,base_moss_point+half_right),"both moss fields and sprites translate together during merge")
	check(close(moss_left._growth_pending[0].point,base_moss_point+Vector2(16,0)+half_left) and close(moss_left.burrow_destination,base_moss_point+half_left),"pending moss growth and burrow destination follow the field")
	check(close(silk_left.segments[0].start.point,old_silk_left-left*0.25) and close(silk_right.segments[0].start.point,old_silk_right-right*0.25),"both silk strands follow their owner without moving the world-origin node")
	check(silk_left.segments[0].start.ref == null and close(wall.global_position,old_silk_left-left*0.25),"attached silk stays on the moving wall, not its obsolete pre-merge attachment")
	check(close(silk_left.webs["web"].point,old_web_left-left*0.25) and close(silk_right.webs["web"].point,old_web_right-right*0.25),"silk web draw/damage points move on both sides")
	check(silk_left.global_position == Vector2.ZERO and silk_left._previous.is_empty() and silk_left._previous_lines.is_empty(),"silk origin stays fixed and outdated sweep caches are cleared")
	check(snow.global_position == Vector2.ZERO and close(snow._development_draw_offsets[snow_left_cell],-left*0.25) and close(snow.heads[1].point,snow_script.point_at(snow_left_cell)-left*0.25),"snow tiles and pumpkins visually tween while the shared manager stays fixed")
	check(rails.global_position == Vector2.ZERO and close(rails._development_draw_offsets[rails.world_to_cell(snow_script.point_at(base_cell)+left)],-left*0.25),"rail drawing follows the left map without moving the shared graph node")
	check(close(ice.global_position,ice_before.get_center()-left*0.25) and close(ice.cell_rect.get_center(),ice.global_position),"temporary ice tile's image and world-space speed hitbox follow together")
	dev._complete_merge()
	check(dev.phase == dev.BATTLE,"merge completes into battle")
	check(close(moss_left.patches[0].point,base_moss_point) and close(moss_right.patches[0].point,base_moss_point),"both moss fields now overlap the intended original floor tile")
	check(moss_left.cell_at(moss_left.patches[0].point) == moss_left.cell_at(base_moss_point) and moss_left.moss_floor_contains_tile(moss_left.patches[0].point),"moss interaction cell agrees with original floor after merge")
	check(close(silk_left.segments[0].start.point,old_silk_left-left) and close(silk_right.segments[0].start.point,old_silk_right-right),"silk collision anchors and render coordinates agree after merge")
	check(close(silk_left.webs["web"].point,old_web_left-left) and close(silk_right.webs["web"].point,old_web_right-right),"both spider webs remain at their corresponding destination")
	check(close(ice.cell_rect.get_center(),ice_before.get_center()-left) and ice.cell_rect.has_point(ice.global_position),"ice boost still applies at the visible tile after merging")
	check(snow.patches.size() == 1 and snow.patches.has(base_cell) and int(snow.patches[base_cell].level) == 2,"overlapping 24px snow cells coalesce without losing the stronger effect")
	check(snow.heads[1].cell == base_cell and snow.heads[2].cell == base_cell and close(snow.heads[1].point,snow_script.point_at(base_cell)) and snow._positions.is_empty(),"pumpkin locations and snow collision history are rebased")
	check(rails.nodes.size() == 2 and rails.rails.size() == 1 and rails._cell_ids.size() == 2,"overlapping rail cells and edges retain one usable graph")
	var end_cell:Vector2i = rails.world_to_cell(snow_script.point_at(base_cell))+Vector2i.RIGHT
	var rail_at:Dictionary = rails.cell_at(snow_script.point_at(base_cell))
	check(not rail_at.is_empty() and rail_at.cell == rails.world_to_cell(snow_script.point_at(base_cell)) and bool(rail_at.powered) and rails._cell_ids.has(end_cell),"rail occupancy, power and lookup agree at the destination")
	check(rails.neighbors(int(rail_at.id)).size() == 1 and rails.edge(int(rails.neighbors(int(rail_at.id))[0])).size() > 0 and rails.render_cells().size() == 2,"the merged rail is traversable and draws once per final cell")
	check(snow.global_position == Vector2.ZERO and rails.global_position == Vector2.ZERO and silk_right.global_position == Vector2.ZERO,"world-origin shared managers do not inherit a guessed lane offset")
	# Leaving development half-way through a transition must also undo its
	# world-space caches; simply restoring Ball positions is not enough.
	world.reset()
	await process_frame
	dev = world._development
	world.control.team.show()
	check(dev.phase == dev.SETUP,"reset prepares a fresh two-lane cancellation fixture")
	var center:Vector2 = dev.base_rect.get_center()
	var preview_left:Dictionary = {"id":901,"char":"Test","scene_path":"res://scenes/ball.tscn","team":"Team0","x":center.x,"y":center.y,"development_base_position":true,"development_lane_key":"left:0"}
	var preview_right:Dictionary = preview_left.duplicate()
	preview_right.id = 902
	preview_right.team = "Team1"
	preview_right.development_lane_key = "right:0"
	var active_left:Node = world._spawn_character_from_setup(preview_left)
	world._spawn_character_from_setup(preview_right)
	var cancel_offset:Vector2 = dev._offset("left:0")
	var cancel_cell:Vector2i = snow_script.cell_at(center)
	var placed_cell:Vector2i = cancel_cell+Vector2i(roundi(cancel_offset.x/24.0),roundi(cancel_offset.y/24.0))
	var cancel_snow:Node2D = snow_script.ensure(world)
	cancel_snow.patches[placed_cell] = {"level":2,"family":"C","team":"Team0","source":weakref(active_left),"expires_at":90.0,"half_lifetime":4.0}
	var cancel_rails:Node2D = rails_script.new()
	cancel_rails.name = "MinecartRails"
	world.add_child(cancel_rails)
	cancel_rails.add_to_group("BattleTransient")
	var first:int = cancel_rails._node(placed_cell,false,true)
	var second:int = cancel_rails._node(placed_cell+Vector2i.RIGHT,true,true)
	cancel_rails._connect(first,second)
	cancel_rails._publish()
	world.control.team.hide()
	dev.update(0.1)
	dev._begin_merge()
	dev._merge_frame(0.5)
	dev.cleanup(false)
	check(dev.phase == dev.OFF and close(active_left.global_position,center),"cancelled merge restores the actor's original coordinate")
	check(cancel_snow.patches.has(cancel_cell) and not cancel_snow.patches.has(placed_cell) and cancel_snow.global_position == Vector2.ZERO,"cancelled merge restores both snow rendering and snow hitbox cells")
	check(cancel_rails.nodes.size() == 2 and not cancel_rails.cell_at(snow_script.point_at(cancel_cell)).is_empty() and cancel_rails.global_position == Vector2.ZERO,"cancelled merge restores the rail graph, not just its manager node")
	world.reset()
	await process_frame
	game.set_runtime_game_setting("Development_Mode",false,false)
	await process_frame
	world.queue_free()
	await process_frame
	game.Game_Settings = settings
	game.set_development_time_multiplier(1.0)
	print("Development terrain merge checks: ",checks,"; failures: ",failures)
	var result:int = 1 if failures > 0 else 0
	snow_script = null
	rails_script = null
	world = null
	game = null
	call_deferred("quit",result)
