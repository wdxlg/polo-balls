extends RefCounted
## World 的随机布阵子系统：只存虚影席位，关工具栏后由 authority 抽取并创建真实人物。
const SHADOW = preload("res://scripts/ui/random_character_placeholder.gd")
const DRAW_UI = preload("res://scripts/ui/random_character_draw_overlay.gd")
const MAX_SLOTS:int = 1024
var _world:Node
var pending:Array[Dictionary] = []
var playing:bool = false
var animation_scale:float = 1.0
var _visuals:Dictionary = {}
var _next_id:int = 1
var _serial:int = 0
var _map:String = ""
var _sync_queued:bool = false
var _authority_finished:bool = false
var _previous_pause:bool = false
var _pause_owned:bool = false
var _layer:CanvasLayer
var overlay:Control
var rng := RandomNumberGenerator.new()
var _pool_key:int = -1
var _pool_cache:Array[Dictionary] = []

func _init(world:Node) -> void:
	_world = world
	rng.randomize()

func is_enabled() -> bool:
	return str(Game.Game_Settings.get("Character_Placement_Mode","custom")) == "random"

func blocks_combat() -> bool:
	return playing or not pending.is_empty()

func categories() -> PackedStringArray:
	_world._ensure_character_path_index()
	return _world._char_folder_names

func exclusion_key(category:String,character_name:String) -> String:
	return category+"/"+character_name

func picker_exclusion_key(character_name:String) -> String:
	# Match the picker's current-category-first cross-category search resolution.
	_world._ensure_character_path_index()
	var current:String = _world.return_now_char_type()
	if _world._character_paths_by_folder.get(current,{}).has(character_name):
		return exclusion_key(current,character_name)
	for category:String in categories():
		if _world._character_paths_by_folder.get(category,{}).has(character_name):
			return exclusion_key(category,character_name)
	return ""

func is_excluded(key:String) -> bool:
	var selected:Variant = Game.Game_Settings.get("Random_Character_Excluded",[])
	return (selected is Array or selected is PackedStringArray) and key in selected

func pool() -> Array[Dictionary]:
	var result:Array[Dictionary] = []
	var enabled:Variant = Game.Game_Settings.get("Random_Character_Categories",[])
	if not enabled is Array and not enabled is PackedStringArray: return result
	var excluded:Dictionary = {}
	var saved_exclusions:Variant = Game.Game_Settings.get("Random_Character_Excluded",[])
	if saved_exclusions is Array or saved_exclusions is PackedStringArray:
		for excluded_key:Variant in saved_exclusions:
			if excluded_key is String: excluded[str(excluded_key)] = true
	_world._ensure_character_path_index()
	var key:int = hash([enabled,excluded,_world._character_paths_by_folder,_world.PLACEABLE_OBSTACLE_SCENES])
	if key==_pool_key: return _pool_cache
	for category:String in categories():
		if category not in enabled: continue
		var indexed:Dictionary = _world._character_paths_by_folder.get(category,{})
		var names:Array = indexed.keys()
		names.sort()
		for character_name:Variant in names:
			if _world.is_placeable_obstacle(str(character_name),str(indexed[character_name])): continue
			if excluded.has(exclusion_key(category,str(character_name))): continue
			result.append({"char":str(character_name),"category":category,"scene_path":str(indexed[character_name])})
	_pool_key = key
	_pool_cache = result
	return result

func can_place() -> bool:
	return not playing and pending.size()<MAX_SLOTS and not pool().is_empty()

func place(team:String,position:Vector2) -> bool:
	if not _world.is_multiplayer_authority() or not can_place() or not position.is_finite(): return false
	if not _world.can_place_character_at(position): return false
	on_map_changed()
	if Game.is_rotation_training_mode() or Game.is_boss_training_mode():
		if str(_world._special_two_team_side(team,position)).is_empty(): return false
	if team == "random": team = _world.control.return_random_team()
	_map = str(_world.now_choose_map)
	var slot:Dictionary = {"id":_next_id,"team":team,"x":position.x,"y":position.y}
	_next_id += 1
	pending.append(slot)
	_add_visual(slot)
	_world._freeze_existing_special_prestart_nodes()
	_queue_sync()
	return true

func _add_visual(slot:Dictionary) -> void:
	var visual:Node2D = SHADOW.new()
	visual.name = "RandomCharacterSlot_%d" % int(slot.id)
	visual.slot_number = int(slot.id)
	visual.position = Vector2(float(slot.x),float(slot.y))
	# 固定轮廓与颜色，不加载或泄露尚未抽取的人物。
	_world.add_child(visual)
	_visuals[int(slot.id)] = visual

func create_cursor() -> Node2D:
	var visual:Node2D = SHADOW.new()
	visual.name = "RandomCharacterCursor"
	visual.modulate.a = 0.55
	_world.add_child(visual)
	return visual

func remove_at(position:Vector2) -> bool:
	if playing or pending.is_empty(): return false
	var nearest:int = -1
	var distance:float = 17.0*17.0
	for index:int in range(pending.size()):
		var slot:Dictionary = pending[index]
		var squared:float = Vector2(float(slot.x),float(slot.y)).distance_squared_to(position)
		if squared <= distance:
			distance = squared
			nearest = index
	if nearest < 0: return false
	_remove_visual(int(pending[nearest].id))
	pending.remove_at(nearest)
	if pending.is_empty() and Game.get_training_mode_type()=="manual": _world._restore_special_prestart_nodes()
	_queue_sync()
	return true

func _remove_visual(id:int) -> void:
	var visual:Node = _visuals.get(id)
	if is_instance_valid(visual): visual.queue_free()
	_visuals.erase(id)

func _queue_sync() -> void:
	if _sync_queued: return
	_sync_queued = true
	call_deferred("_flush_sync")

func _flush_sync() -> void:
	_sync_queued = false
	if not is_instance_valid(_world) or not _world.is_inside_tree(): return
	if _world.multiplayer.has_multiplayer_peer() and _world.is_multiplayer_authority():
		Game.random_character_state.rpc("slots",pending,_serial)

func receive_slots(slots:Array) -> void:
	if playing: return
	for id:Variant in _visuals.keys(): _remove_visual(int(id))
	pending.clear()
	_map = str(_world.now_choose_map)
	for raw:Variant in slots:
		if raw is Dictionary:
			var slot:Dictionary = raw.duplicate(true)
			pending.append(slot)
			_add_visual(slot)
	if not pending.is_empty(): _world._freeze_existing_special_prestart_nodes()
	elif Game.get_training_mode_type()=="manual": _world._restore_special_prestart_nodes()

func on_map_changed() -> void:
	if not _map.is_empty() and _map != str(_world.now_choose_map): cancel(true)
	_map = str(_world.now_choose_map)

func start() -> bool:
	if playing or pending.is_empty() or not _world.is_multiplayer_authority(): return false
	var available:Array[Dictionary] = pool()
	if available.is_empty(): return false
	var results:Array = []
	for slot:Dictionary in pending:
		var record:Dictionary = slot.duplicate(true)
		record.merge(available[rng.randi_range(0,available.size()-1)])
		results.append(record)
	_serial += 1
	if _world.multiplayer.has_multiplayer_peer(): Game.random_character_state.rpc("draw",results,_serial)
	play(results,_serial)
	return true

func play(results:Array,serial:int) -> void:
	if playing or results.is_empty(): return
	_serial = serial
	playing = true
	_authority_finished = false
	_previous_pause = _world.get_tree().paused
	_pause_owned = true
	_world.get_tree().paused = true
	Game._placement._cancel_placement_press()
	if is_instance_valid(Game._placement.ghost_ball):
		Game._placement.ghost_ball.queue_free()
		Game._placement.ghost_ball = null
	_world.control.hide()
	_world.control.team.hide()
	_world._freeze_existing_special_prestart_nodes()
	_layer = CanvasLayer.new()
	_layer.name = "RandomCharacterDraw"
	_layer.layer = 1500
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_world.add_child(_layer)
	overlay = DRAW_UI.new()
	_layer.add_child(overlay)
	# Build every anonymous seat before the first reveal. Resolve special-mode sides
	# with the same placement rule as combat, without mutating network/battle records.
	var roster:Array = []
	var mode:String = Game.get_training_mode_type()
	for record:Dictionary in results:
		var display_team:String = str(record.get("team",""))
		if mode in ["rotation","boss"]:
			var side:String = _world._special_two_team_side(display_team,Vector2(float(record.x),float(record.y)))
			display_team = "Team0" if side=="left" else "Team1"
		roster.append({"id":record.id,"display_team":display_team})
	var boss_team:String = "Team0" if str(Game.Game_Settings.get("Training_Boss_Side","right"))=="left" else "Team1"
	overlay.configure_roster(roster,mode,boss_team,_world.team_text_colors)
	overlay.configure_roulette(pool(),Callable(_world,"create_character_preview"))
	var candidate_names:Array[String] = []
	var duration:float = clampf(9.0/float(results.size()),0.14,1.25)*animation_scale
	for index:int in range(results.size()):
		if not _valid(serial): return
		var record:Dictionary = results[index]
		overlay.begin_ticket(index,results.size(),record,candidate_names,duration*0.55)
		await _wait(duration*0.55,serial)
		if not _valid(serial): return
		var preview:Node2D = _world.create_character_preview(str(record.char),str(record.scene_path),false)
		overlay.reveal_ticket(record,preview)
		await _wait(duration*0.45,serial)
		if not _valid(serial): return
		if _world.is_multiplayer_authority():
			# create_char 的冷资源加载可能异步；必须等它完成，不能提前开放战斗闸门。
			await _world.create_char(str(record.team),str(record.char),Vector2(float(record.x),float(record.y)),str(record.scene_path))
			if not _valid(serial): return
		_remove_visual(int(record.id))
	pending.clear()
	overlay.show_finishing()
	if _world.is_multiplayer_authority():
		await _wait(0.22*animation_scale,serial)
		if not _valid(serial): return
		_authority_finished = true
		if _world.multiplayer.has_multiplayer_peer(): Game.random_character_state.rpc("finish",[],serial)
	while _valid(serial) and not _authority_finished:
		await _world.get_tree().process_frame
	if not _valid(serial): return
	overlay.show_complete()
	# Let the original level-up cue finish before releasing combat. Zero animation
	# scale remains a fast deterministic test path, not a user-facing skip button.
	var complete_hold:float = 0.48*animation_scale
	if animation_scale>0.0: complete_hold = maxf(complete_hold,overlay.completion_sound_seconds())
	await _wait(complete_hold,serial)
	if not _valid(serial): return
	# Keep combat/input locked until the last fully transparent frame has rendered.
	overlay.begin_exit(overlay.EXIT_SECONDS if animation_scale>0.0 else 0.0)
	while _valid(serial) and is_instance_valid(overlay) and not overlay.is_exit_finished():
		await _world.get_tree().process_frame
	if not _valid(serial): return
	playing = false
	_release_pause()
	if is_instance_valid(_layer): _layer.queue_free()
	overlay = null
	if Game.get_training_mode_type()=="manual": _world._restore_special_prestart_nodes()
	_world.notify_primary_battle_character_alive_changed()

func _valid(serial:int) -> bool:
	return serial == _serial and playing and is_instance_valid(_world) and _world.is_inside_tree()

func _wait(seconds:float,serial:int) -> void:
	var until:int = Time.get_ticks_msec()+int(maxf(seconds,0.0)*1000)
	if _valid(serial): await _world.get_tree().process_frame
	while _valid(serial) and Time.get_ticks_msec()<until:
		await _world.get_tree().process_frame

func finish_from_authority(serial:int) -> void:
	if serial == _serial: _authority_finished = true

func _release_pause() -> void:
	if _pause_owned and is_instance_valid(_world) and _world.get_tree()!=null:
		_world.get_tree().paused = _previous_pause or Game.now_stop_state
	_pause_owned = false

func cancel(broadcast:bool = true) -> void:
	_serial += 1
	playing = false
	pending.clear()
	for id:Variant in _visuals.keys(): _remove_visual(int(id))
	if is_instance_valid(_layer): _layer.queue_free()
	overlay = null
	_release_pause()
	if is_instance_valid(_world) and _world.is_inside_tree():
		if Game.get_training_mode_type()=="manual": _world._restore_special_prestart_nodes()
		if broadcast and _world.is_multiplayer_authority() and _world.multiplayer.has_multiplayer_peer():
			Game.random_character_state.rpc("cancel",[],_serial)
