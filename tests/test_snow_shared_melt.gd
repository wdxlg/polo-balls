extends "res://tests/test_mc_snow_golem.gd"
## Real snow field/grid and production environment settings, not mock visual timers.
var conditions:Node2D
var metrics:Array = []
var evidence:String

func rectangle(record:Dictionary,cell:Vector2i) -> Rect2:
	return record.get("tile",Rect2(FIELD.point_at(cell)-Vector2.ONE*FIELD.CELL*0.5,Vector2.ONE*FIELD.CELL))
func opacity(field:Node2D,record:Dictionary) -> float:
	return field.snow_alpha(record) if field.has_method("snow_alpha") else 1.0
func step_setting(value:String) -> void:
	game._apply_runtime_game_setting_local("Environment",value,false)
func finish(code:int) -> void:
	if done: return
	if not evidence.is_empty():
		var file:=FileAccess.open(evidence.path_join("metrics.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"metrics":metrics},"\t"));file.close()
	print("SNOW_SHARED_MELT checks=",checks," failures=",failures)
	await super.finish(code)

func run() -> void:
	game = root.get_node("Game")
	var original:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Environment = "none"
	var center:Vector2 = await setup_world()
	saved = original
	evidence = OS.get_environment("SNOW_MELT_EVIDENCE_DIR")
	if evidence.is_empty(): evidence = "user://snow_shared_melt"
	DirAccess.make_dir_recursive_absolute(evidence)
	create_timer(100,true,false,true).timeout.connect(func():finish(2))
	conditions = world.battle_conditions
	conditions.set_physics_process(false)
	var unit:Node2D = spawn(GOLEM_PATH,center)
	unit.Can_Attack = false
	var field:Node2D = unit._field
	field.set_physics_process(false)
	await physics_frame
	await process_frame
	field.patches.clear()
	unit._trail_started = false
	unit.lay_trail()
	check(field.patches.size()==1,"standing first deposits exactly one snow tile")
	var cell:Vector2i = field.patches.keys()[0]
	var patch:Dictionary = field.patches[cell]
	var tile:Rect2 = rectangle(patch,cell)
	var size:Vector2 = world.map_visual_cell_size(world._current_map_node())
	var origin:Vector2 = world.map_island_rects(world._current_map_node())[0].position
	check(tile.size.is_equal_approx(size),"golem trail is exactly the same actual block size as environment snow")
	var local:Vector2 = (tile.position-origin)/size
	check(local.is_equal_approx(local.round()),"golem trail follows the actual environment block origin")
	var position_before:Vector2 = tile.position
	field.advance(8.15)
	patch = field.patches.get(cell,{})
	check(not patch.is_empty() and int(patch.get("level",2))==2,"melt never turns a full tile into a half-size stage")
	var alpha:float = opacity(field,patch)
	check(alpha>0.0 and alpha<1.0,"after eight dry combat seconds snow quickly fades instead of shrinking")
	check(patch.is_empty() or rectangle(patch,cell).position==position_before,"fade keeps its original block footprint fixed")
	field.advance(0.16)
	check(not field.patches.has(cell),"dry snow disappears after the short fade, not a four-second half-snow stage")
	step_setting("snow")
	await physics_frame
	await process_frame
	field = conditions.field
	field.set_physics_process(false)
	field.patches.clear()
	field.clear_environment()
	var record:Dictionary = {"cell":Vector2i(30,30),"tile":Rect2(center-Vector2(8,8),Vector2(16,16)),"rects":[Rect2(center-Vector2(8,8),Vector2(16,16))],"decorative":false}
	field.add_environment_patch(conditions,record)
	field.advance(8.1)
	check(field.environment_patches.has(record.cell) and opacity(field,field.environment_patches[record.cell])==1.0,"Snow weather runs environmental melting at half speed, not ordinary speed")
	step_setting("none")
	check(field.environment_patches.has(record.cell),"turning off Snow stops generation but preserves existing accumulation to melt naturally")
	if field.environment_patches.has(record.cell):
		field.advance(4.10)
		var current:Dictionary = field.environment_patches.get(record.cell,{})
		alpha = opacity(field,current)
		check(not current.is_empty() and alpha>0.0 and alpha<1.0,"existing environmental age survives setting changes and returns to normal fade speed")
		field.advance(0.16)
		check(field.environment_patches.is_empty(),"environment ground snow actually expires instead of remaining permanent")
	else:
		check(false,"existing environmental age survives setting changes and returns to normal fade speed")
		check(false,"environment ground snow actually expires instead of remaining permanent")
	await check_uniform_lifecycle(field,unit,center)
	await check_merge_age(field,unit,center)
	await check_map_grid(field,unit,center)
	check_recycling(field,unit)
	await finish(0 if failures==0 else 1)

func empty(field:Node2D) -> void:
	field._field_state([],[],true)
	field.clear_environment()
	field._positions.clear()
	field._damage_until.clear()
	field.full_snow_lifetime = 8.0
	field.snow_fade_duration = 0.30

func check_uniform_lifecycle(field:Node2D,unit:Node2D,center:Vector2) -> void:
	step_setting("none")
	empty(field)
	var cell:Vector2i = field.snow_cell_at(center)
	var tile:Rect2 = field.snow_tile_at(cell)
	check(field.SNOW==field.wall_view.NATIVE_SNOW,"ground trails and environment use the identical original snow texture")
	check(field.deposit(unit,cell,false),"real golem deposits a map-sized full tile")
	var target:Node2D = dummy(tile.get_center())
	target.set_physics_process(false)
	await physics_frame
	park_contact(field,target,tile.get_center())
	var hp:int = target.health
	field.check_ground()
	check(target.health==hp-3,"full snow retains original cold damage before fading")
	park_contact(field,target,Vector2(tile.end.x+0.1,tile.get_center().y))
	hp = target.health
	field.check_ground()
	check(target.health==hp,"new trail has no hidden damage outside its actual one-block rectangle")
	var info:Dictionary = field.get_debug_hazard_info()
	check(info.parts.size()==1 and (info.parts[0].half_extents as Vector2).is_equal_approx(tile.size*0.5),"trail threat uses the same real block footprint")
	field.advance(8.0)
	park_contact(field,target,tile.get_center())
	hp = target.health
	field.check_ground()
	check(target.health==hp and field.get_debug_hazard_info().is_empty(),"short visual fade is harmless and removes damage threat immediately")
	var footprint:Rect2 = field.patches[cell].tile
	field.advance(0.15)
	check(is_equal_approx(field.snow_alpha(field.patches[cell]),0.5) and field.patches[cell].tile==footprint,"mid-fade is half opacity at the SAME size, never half a block")
	check(field.deposit(unit,cell,false) and field.snow_alpha(field.patches[cell])==1.0,"a genuine revisit refreshes the same whole tile during fade")
	var expiry:float = field.patches[cell].expires_at
	unit.global_position = tile.get_center()
	unit._trail_started = false
	unit.lay_trail()
	expiry = field.patches[cell].expires_at
	for i:int in range(25): unit.lay_trail()
	check(field.patches[cell].expires_at==expiry,"standing still cannot keep replenishing a tile's lifetime")
	game.now_stop_state = true
	var melt_clock:float = field._melt_clock
	var damage_clock:float = field._clock
	field.advance(100)
	check(field._melt_clock==melt_clock and field._clock==damage_clock,"pause freezes both clocks without deleting snow")
	game.now_stop_state = false
	Engine.time_scale = 0
	field.advance(100)
	check(field._melt_clock==melt_clock,"zero game speed also freezes melt age")
	Engine.time_scale = 1
	field.advance(-1)
	check(field._melt_clock==melt_clock,"invalid delta cannot reverse snow age")
	empty(field)
	step_setting("snow")
	field.set_physics_process(false)
	field.full_snow_lifetime = 1.0
	field.snow_fade_duration = 0.4
	field.deposit(unit,cell,false)
	var env_tile:Rect2 = Rect2(tile.position+Vector2(32,0),tile.size)
	var ground:Dictionary = {"cell":Vector2i(900,0),"tile":env_tile,"rects":[env_tile],"decorative":false}
	var wall:Dictionary = {"cell":Vector2i(901,0),"tile":Rect2(env_tile.position+Vector2(32,0),tile.size),"rects":[Rect2(env_tile.position+Vector2(32,0),tile.size)],"decorative":true}
	field.add_environment_patch(conditions,ground)
	field.add_environment_patch(conditions,wall)
	park_contact(field,target,tile.get_center())
	hp = target.health
	field.check_ground()
	field.advance(0.5)
	check(target.health==hp-6,"Snow weather slows melting, not the original half-second damage cadence")
	field.advance(1.5)
	check(field.patches.has(cell) and field.environment_patches.size()==2,"both trail and floor/wall environment snow remain until twice the normal solid duration")
	field.advance(0.4)
	check(is_equal_approx(field.snow_alpha(field.patches[cell]),0.5) and is_equal_approx(field.snow_alpha(field.environment_patches[ground.cell]),0.5) and is_equal_approx(field.snow_alpha(field.environment_patches[wall.cell]),0.5),"all three snow surfaces share a half-speed fade under Snow weather")
	field.advance(0.41)
	check(field.patches.is_empty() and field.environment_patches.is_empty(),"all surfaces expire after the doubled solid-plus-fade duration")
	empty(field)
	field.full_snow_lifetime = 2.0
	field.snow_fade_duration = 0.4
	field.deposit(unit,cell,false)
	field.advance(1.0) # Half-rate: only 0.5 melt seconds consumed.
	var remaining:float = field.patches[cell].expires_at-field._melt_clock
	step_setting("none")
	field.advance(0.5)
	step_setting("snow")
	check(is_equal_approx(field.patches[cell].expires_at-field._melt_clock,remaining-0.5),"weather off/on never resets, resurrects or restamps an existing trail")
	field.advance(2.0)
	check(field.snow_alpha(field.patches[cell])==1.0 and field.get_debug_hazard_info().is_empty(),"after rate switches the original solid deadline still starts a harmless fade")
	# Remaining time is signed, so a late snapshot can arrive midway through fade.
	field.advance(0.2)
	var payload:Array = field._cell_snapshot([cell])
	check(is_equal_approx(payload[0].remaining,-0.1),"snapshot carries signed remaining melt time rather than restarting the fade")
	var replica:Node2D = load("res://scenes/effects/我的世界/雪傀儡雪地.tscn").instantiate()
	replica.name = "SharedMeltReplica"
	world.add_child(replica,true)
	replica.set_multiplayer_authority(2)
	replica.set_physics_process(false)
	replica._melt_clock = 400
	replica._melt_rate_state(0.5)
	replica._field_state(payload,[],true)
	check(is_equal_approx(replica.snow_alpha(replica.patches[cell]),0.75),"different local clock preserves a late-join partial fade")
	var remote_hp:int = target.health
	replica.advance(0.61)
	check(replica.patches.is_empty() and target.health==remote_hp,"replica predicts disappearance without doing authoritative damage")
	replica.queue_free()
	clear_cold(target)
	target.queue_free()
	var retained:Dictionary = {"cell":Vector2i(1200,0),"tile":tile,"rects":[tile],"decorative":false}
	field.add_environment_patch(conditions,retained)
	var client_snapshot:Dictionary = field.environment_patches.duplicate(true)
	conditions.set_multiplayer_authority(2)
	field.set_multiplayer_authority(2)
	conditions._map_key = "" # A guest never ran the authority's generation setup.
	step_setting("none")
	check(field.environment_patches==client_snapshot,"fresh client controller cannot clear authoritative snow when weather is turned off")
	conditions.set_multiplayer_authority(1)
	field.set_multiplayer_authority(1)
	field._refresh_melt_rate()
	empty(field)
	await process_frame

func check_map_grid(field:Node2D,unit:Node2D,center:Vector2) -> void:
	var map:Node2D = world._current_map_node()
	var transform:Transform2D = map.transform
	map.scale = Vector2(1.5,2.0)
	map.position += Vector2(7,11)
	world.refresh_map_presentation()
	field.refresh_grid(true)
	await physics_frame
	var middle:Vector2 = world.return_map_world_rect(map).get_center()
	unit.global_position = middle
	unit._trail_started = false
	unit.lay_trail()
	var actual:Rect2 = field.patches.values()[0].tile
	check(actual.size.is_equal_approx(Vector2(24,32)),"golem snow follows real nonuniform map-block scale, not hard-coded 16")
	var offset:Vector2 = (actual.position-field.grid_origin)/field.grid_size
	check(offset.is_equal_approx(offset.round()),"translated/nonuniform map keeps the same origin alignment as environment snow")
	var first:Vector2i = field.snow_cell_at(unit.global_position)
	unit.global_position += Vector2(field.grid_size.x*3.1,0)
	unit.lay_trail()
	check(field.patches.has(first+Vector2i.RIGHT) and field.patches.has(first+Vector2i(2,0)),"movement fills intermediate real-sized blocks without 24-unit gaps")
	map.transform = transform
	world.refresh_map_presentation()
	field.refresh_grid(true)
	empty(field)
	unit.global_position = center
	unit._trail_started = false
	await physics_frame

func check_recycling(field:Node2D,unit:Node2D) -> void:
	world.now_choose_map = "Map10x10"
	world.refresh_map_presentation()
	unit.global_position = world.return_map_world_rect(world._current_map_node()).get_center()
	step_setting("snow")
	conditions.refresh_layout(true)
	field.set_physics_process(false)
	field.full_snow_lifetime = 0.2
	field.snow_fade_duration = 0.1
	var candidate_count:int = conditions._ground_candidates.size()+conditions._wall_candidates.size()
	var born:int = 0
	for i:int in range(1500):
		var previous:Dictionary = field.environment_patches.duplicate(true)
		conditions.advance(0.1)
		for key:Vector2i in field.environment_patches:
			if not previous.has(key) or field.environment_patches[key].expires_at!=previous[key].expires_at: born+=1
		field.advance(0.1)
	check(born>candidate_count and born>200,"long-running weather replenishes melted candidate positions rather than stopping after one fill")
	check(field.environment_patches.size()<10,"short-lived environment snow stays bounded during sustained snowfall")
	var retained:int = field.environment_patches.size()
	step_setting("none")
	conditions.advance(20)
	check(field.environment_patches.size()==retained and not field.wall_view.weather_enabled,"weather-off produces no new snow while leaving existing patches to the field timer")
	field.advance(1)
	check(field.environment_patches.is_empty(),"all remaining short-lived environment snow clears naturally after weather-off")
	metrics.append({"phase":"recycling","candidates":candidate_count,"spawned":born})

func check_merge_age(field:Node2D,unit:Node2D,center:Vector2) -> void:
	empty(field)
	var base:Vector2i = field.snow_cell_at(center)
	var left:Vector2i = base+Vector2i(-2,0)
	var right:Vector2i = base+Vector2i(2,0)
	field.deposit(unit,left,false)
	field.add_environment_patch(conditions,{"cell":left,"tile":field.snow_tile_at(left),"rects":[field.snow_tile_at(left)],"decorative":false})
	field.advance(1.0)
	field.deposit(unit,right,false)
	field.add_environment_patch(conditions,{"cell":right,"tile":field.snow_tile_at(right),"rects":[field.snow_tile_at(right)],"decorative":false})
	var retained_deadline:float = field.patches[right].expires_at
	var span:float = field.grid_size.x*2.0
	field.development_begin_merge(func(point:Vector2):return "left" if point.x<center.x else "right",{"left":Vector2(-span,0),"right":Vector2(span,0)})
	field.development_preview_merge({}, {"left":{"offset":Vector2.ZERO},"right":{"offset":Vector2.ZERO}})
	field.development_finish_merge()
	check(field.patches.size()==1 and field.environment_patches.size()==1,"merging lanes coalesces each ownership layer into one actual map block")
	check(field.patches.has(base) and field.patches[base].tile==field.snow_tile_at(base),"merged golem trail translates its real footprint, not an obsolete 24-unit point")
	check(is_equal_approx(field.patches[base].expires_at,retained_deadline) and is_equal_approx(field.environment_patches[base].expires_at,retained_deadline),"merge keeps the newer remaining lifetime without resetting age or shortening the winning tile")
	check(is_equal_approx(field._cell_snapshot([base])[0].remaining,8.0),"post-merge network snapshot retains the winning relative melt time")
	empty(field)
	await process_frame
