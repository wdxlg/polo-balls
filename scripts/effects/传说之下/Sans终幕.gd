extends Node2D

# 一条战斗时钟负责攻击、地图和倒计时；不使用独立 Timer/Tween 协程推进阶段。
# 地图只加入本局运行时 map_group，不写设置、不替换原 TileMap、不删除原场景。
const WALL_SLOTS = preload("res://scripts/effects/传说之下/sans_wall_slots.gd")
const BONE = preload("res://scripts/effects/传说之下/Sans终幕骨列.gd")
const SPIKE = preload("res://scripts/effects/传说之下/Sans骨头攻击.gd")
const TEMP_NAME:String = "SansFinal10x10"
const OPEN_END:float = 1.20
const SCROLL_START:float = 8.0
const CORRIDOR_START:float = 13.0
const CORRIDOR_END:float = 25.0
const RETURN_START:float = 29.0
const WIND_START:float = 30.0
var source:Node2D
var world:Node2D
var elapsed:float = 0.0
var death_return_started:int = -1
var death_return_time:float = 0.0
const GROUP_START:float = 21.5
var total_duration:float = 0.0
var wind_end:float = 0.0
var wind_steps:int = 90
var wind_interval:float = 0.072
var wind_slots:int = 30
var wind_emitted:int = 0
var arena_rect:Rect2
var base_rect:Rect2
var original_rect:Rect2
var original_map:String
var temp_map:TileMapLayer
var in_temp:bool = false
var finished:bool = false
var events:Array[Dictionary] = []
var event_cursor:int = 0
var participants:Array[Dictionary] = []
var hazards:Array[Node2D] = []
var slams:Array[Dictionary] = []
var impact_sides:Dictionary = {}
var known_participants:Dictionary = {}
var roster_refresh:float = 0.0
var corridor_height:float = 0.0
var corridor_gap:float = 0.0
var walls:Array[StaticBody2D] = []
var snapshot:Dictionary = {}
var anchor:Vector2
var overlay:CanvasLayer
var black:ColorRect
var blackout_root:Node2D
var timer_label:Label
var background:Polygon2D
var border:Line2D
var old_safety:Node
var original_positions_restored:bool = false
var gesture_left:float=0.0
var bone_token:String=""
var pending_corridor:bool=false
var hidden_surrounding_hud:Dictionary={}
const SURROUNDING_HUD:Array[String]=["versus_label","interaction_label","_center_watermark_root","_dead_save_watermark_name","character_dialogue_root","rotation_versus_root","timed_training_label"]
func _suppress_surrounding_hud() -> void:
	for property:String in SURROUNDING_HUD:
		var item:Variant=world.get(property)
		if not is_instance_valid(item) or not item is CanvasItem: continue
		var id:int=item.get_instance_id()
		if not hidden_surrounding_hud.has(id): hidden_surrounding_hud[id]={"ref":weakref(item),"visible":item.visible}
		item.hide()
func _restore_surrounding_hud() -> void:
	for record:Dictionary in hidden_surrounding_hud.values():
		var item:Variant=record.ref.get_ref()
		if is_instance_valid(item): item.visible=bool(record.visible)
	hidden_surrounding_hud.clear()

func begin(actor:Node2D) -> bool:
	source = actor
	world = get_tree().current_scene as Node2D
	if world == null or not world.has_method("return_map_world_rect") or world.has_meta(&"sans_final_phase"):
		return false
	var maps:Dictionary = world.get("map_group")
	if not maps.has("Map10x10") or not maps.has(world.get("now_choose_map")):
		return false
	original_map = str(world.get("now_choose_map"))
	original_rect = world.call("return_map_world_rect",maps[original_map])
	base_rect = world.call("return_map_world_rect",maps["Map10x10"])
	if base_rect.size.x <= 1.0 or base_rect.size.y <= 1.0:
		return false
	# 独立空间，10×10 的真实单格尺度；不是把原地图缩放成小方框。
	base_rect.position = Vector2(20000.0,20000.0)
	arena_rect = base_rect
	world.set_meta(&"sans_final_phase",self)
	process_priority = 100
	wind_slots = maxi(int(source.get("windmill_blaster_count_per_round")),12)
	wind_steps = wind_slots * 3
	wind_interval = maxf(float(source.get("windmill_spawn_interval")),0.01)
	wind_end = WIND_START + (wind_steps-1)*wind_interval + float(source.get("windmill_appearance_duration")) + float(source.get("windmill_prefire_delay")) + float(source.get("windmill_attack_duration")) + 0.8
	total_duration = wind_end + 7.2
	snapshot = {
		"source_layer": source.collision_layer, "source_mask": source.collision_mask,
		"source_z": source.z_index, "source_z_relative": source.z_as_relative,
		"graphics_z":source.graphics.z_index,"graphics_relative":source.graphics.z_as_relative,
		"escape": source.get_meta(&"submission_allow_map_escape") if source.has_meta(&"submission_allow_map_escape") else null,
		"safety_name": world.get("_map_safety_frame_map_name"),
		"camera_position": world.get("camera_2d").global_position,
		"camera_zoom": world.get("camera_2d").zoom,
		"camera_smoothing": world.get("camera_2d").position_smoothing_enabled,
		"health_bar_visible": source.health_bar.visible if is_instance_valid(source.health_bar) else false,
		"versus_visible": world.get("versus_label").visible,
		"interaction_visible": world.get("interaction_label").visible,
		"watermark_visible": world.get("_center_watermark_root").visible,
		"mask_enabled": world.get("map_outside_mask_enabled"),
		"mask_materials": [],
	}
	_suppress_surrounding_hud()
	for polygon:Polygon2D in world.get("map_outside_mask_parts"):
		snapshot.mask_materials.append(polygon.material)
	world.get("camera_2d").position_smoothing_enabled = false
	if is_instance_valid(source.health_bar):
		source.health_bar.hide()
	old_safety = world.get("_map_safety_frame")
	if is_instance_valid(old_safety):
		snapshot["safety_process"] = old_safety.process_mode
		snapshot["safety_visible"] = old_safety.visible
	# 取消旧技能序列与本 Sans 重力；不动其他角色/其他 Sans 的来源登记。
	source.call("_cancel_windmill")
	source.call("_cancel_rolling_bones")
	source.set("_boss_gravity_wall_sequence_serial",int(source.get("_boss_gravity_wall_sequence_serial"))+1)
	source.call("_cleanup_all_sans_gravity_states")
	for unit:Node in get_tree().get_nodes_in_group("Ball"):
		if unit is CharacterBody2D and unit.is_inside_tree() and unit.get("Type") == 0:
			_register_participant(unit)
	# 通道必须容得下本局人物的真实碰撞体，不能把大体型角色塞进必中的窄缝。
	var largest:float = 0.0
	for entry:Dictionary in participants:
		var unit:Node2D = entry.ref.get_ref()
		if is_instance_valid(unit) and unit != source:
			largest = maxf(largest,unit.get_crowd_separation_radius_world()*2.0)
	corridor_height = minf(base_rect.size.y*0.92,maxf(base_rect.size.y*0.72,largest*1.50))
	corridor_gap = minf(corridor_height-20.0,maxf(corridor_height*0.46,largest+8.0))
	source.collision_layer = 0
	source.collision_mask = 0
	source.z_as_relative = false
	source.z_index = 110
	source.graphics.z_as_relative = false
	source.graphics.z_index = maxi(110,int(world.get("versus_label").z_index)+1)
	source.set_meta(&"submission_allow_map_escape",true)
	source.call("_reset_dodge_stretch")
	source.call("_set_visual_mode_local",0)
	_build_overlay()
	_build_timeline()
	# 第一张黑屏出现的同一帧转场，而不是等黑屏结束才切地图。
	_enter_arena(maps["Map10x10"])
	_hold_source()
	_update_hud()
	return true

func _register_participant(unit:Node2D) -> void:
	if known_participants.has(unit.get_instance_id()):
		return
	known_participants[unit.get_instance_id()] = true
	participants.append({"ref":weakref(unit),"position":unit.global_position,
		"rotation":unit.global_rotation,"up":unit.up_direction,
		"terminal":unit.external_directional_gravity_terminal_speed,
		"locomotion":unit.get("_external_directional_gravity_locomotion_enabled"),
		"axis_ratio":unit.get("_external_directional_gravity_axis_speed_ratio_max"),
		"hop":unit.get("_external_directional_gravity_hop_enabled"),
		"hop_min":unit.get("_external_directional_gravity_hop_min_interval"),
		"hop_max":unit.get("_external_directional_gravity_hop_max_interval"),
		"hop_ratio_min":unit.get("_external_directional_gravity_hop_min_ratio"),
		"hop_ratio_max":unit.get("_external_directional_gravity_hop_max_ratio"),
		"tinted":false})

func _build_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.layer = 128
	add_child(overlay)
	black = ColorRect.new()
	black.color = Color.BLACK
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	# Backdrop lives in the world canvas below actors; only the timer is HUD.
	black.z_as_relative=false
	black.z_index=-1
	blackout_root=Node2D.new()
	add_child(blackout_root)
	blackout_root.add_child(black)
	timer_label = Label.new()
	timer_label.size = Vector2(180,54)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size",32)
	timer_label.add_theme_color_override("font_color",Color.WHITE)
	timer_label.add_theme_color_override("font_outline_color",Color.BLACK)
	timer_label.add_theme_constant_override("outline_size",5)
	timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(timer_label)
	background = Polygon2D.new()
	background.color = Color.BLACK
	background.z_as_relative = false
	background.z_index = -2 # 高于 Background(-3)，先于 BackBufferCopy(-1)，遮罩采样同一黑底。
	add_child(background)
	border = Line2D.new()
	border.z_as_relative = false
	border.z_index = 101
	border.default_color = Color.WHITE
	border.width = 2.0
	border.closed = true
	add_child(border)

func _build_timeline() -> void:
	for i:int in range(3):
		events.append({"t":1.5+i*2.0,"kind":"slam","dir":[Vector2.DOWN,Vector2.UP,Vector2.DOWN][i]})
	for i:int in range(8):
		events.append({"t":SCROLL_START+i*0.55,"kind":"scroll","i":i})
	events.append({"t":CORRIDOR_START,"kind":"corridor"})
	events.append({"t":GROUP_START,"kind":"groups"})
	events.append({"t":26.0,"kind":"slam","dir":Vector2.RIGHT})
	events.append({"t":RETURN_START,"kind":"return"})
	for i:int in range(5):
		events.append({"t":wind_end+0.4+i*1.15,"kind":"slam","dir":[Vector2.DOWN,Vector2.LEFT,Vector2.UP,Vector2.RIGHT,Vector2.DOWN][i]})
	events.append({"t":wind_end+6.0,"kind":"final_black"})
	events.sort_custom(func(a:Dictionary,b:Dictionary): return a.t < b.t)

func _enter_arena(reference:TileMapLayer) -> void:
	temp_map = TileMapLayer.new()
	temp_map.name = TEMP_NAME
	temp_map.tile_set = reference.tile_set
	temp_map.set_meta(&"sans_final_rect",arena_rect)
	world.add_child(temp_map)
	world.get("map_group")[TEMP_NAME] = temp_map
	world.set("now_choose_map",TEMP_NAME)
	world.set("_presentation_map_name",TEMP_NAME)
	world.set("_map_safety_frame_map_name",TEMP_NAME)
	if is_instance_valid(old_safety):
		old_safety.process_mode = Node.PROCESS_MODE_DISABLED
		old_safety.hide()
	world.call("_sync_selected_map_visibility")
	# 临时地图外沿也使用纯黑；不依赖屏幕拷贝中棋盘背景的绘制排序。
	var mask_shader:=Shader.new()
	mask_shader.code = "shader_type canvas_item; render_mode unshaded; void fragment(){ COLOR=vec4(0.0,0.0,0.0,1.0); }"
	var mask_material:=ShaderMaterial.new()
	mask_material.shader = mask_shader
	world.set("map_outside_mask_enabled",true)
	for polygon:Polygon2D in world.get("map_outside_mask_parts"):
		polygon.material = mask_material
	in_temp = true
	for i:int in range(4):
		var wall:=StaticBody2D.new()
		wall.collision_layer = 1
		wall.collision_mask = 0
		var shape:=CollisionShape2D.new()
		shape.shape = RectangleShape2D.new()
		wall.add_child(shape)
		add_child(wall)
		walls.append(wall)
	for entry:Dictionary in participants:
		var unit:Node2D = entry.ref.get_ref()
		if not is_instance_valid(unit):
			continue
		var uv:Vector2 = (entry.position-original_rect.position)/original_rect.size
		uv = uv.clamp(Vector2(0.18,0.18),Vector2(0.82,0.82))
		unit.global_position = base_rect.position + uv*base_rect.size
		unit.velocity = Vector2.ZERO
		unit.Repel = Vector2.ZERO
		unit.clear_external_directional_gravity_velocity()
	anchor = Vector2(base_rect.get_center().x,base_rect.position.y-maxf(30.0,base_rect.size.y*0.10))
	_update_arena_geometry()

func _update_arena_geometry() -> void:
	if not in_temp:
		return
	temp_map.set_meta(&"sans_final_rect",arena_rect)
	background.polygon = PackedVector2Array([Vector2(-100000,-100000),Vector2(100000,-100000),Vector2(100000,100000),Vector2(-100000,100000)])
	border.points = PackedVector2Array([arena_rect.position,Vector2(arena_rect.end.x,arena_rect.position.y),arena_rect.end,Vector2(arena_rect.position.x,arena_rect.end.y)])
	var bounds:Array[Rect2] = [
		Rect2(arena_rect.position-Vector2(16,16),Vector2(arena_rect.size.x+32,16)),
		Rect2(Vector2(arena_rect.end.x,arena_rect.position.y-16),Vector2(16,arena_rect.size.y+32)),
		Rect2(Vector2(arena_rect.position.x-16,arena_rect.end.y),Vector2(arena_rect.size.x+32,16)),
		Rect2(arena_rect.position-Vector2(16,16),Vector2(16,arena_rect.size.y+32))]
	for i:int in range(4):
		walls[i].global_position = bounds[i].get_center()
		(walls[i].get_child(0).shape as RectangleShape2D).size = bounds[i].size
	world.call("_refresh_map_outside_grid",arena_rect)
	world.call("_refresh_map_outside_mask",arena_rect)

func _physics_process(delta:float) -> void:
	if finished:
		return
	if not is_instance_valid(source) or not is_instance_valid(world) or source.health <= 0 or get_tree().current_scene != world:
		finish(false)
		return
	if str(world.get("now_choose_map")) != (TEMP_NAME if in_temp else original_map):
		finish(false)
		return
	var has_opponent:bool = false
	for entry:Dictionary in participants:
		var unit:Node2D = entry.ref.get_ref()
		if is_instance_valid(unit) and unit != source and unit.health > 0 and str(unit.Team) != str(source.Team):
			has_opponent = true
			break
	if death_return_started >= 0:
		return
	if not has_opponent:
		_start_death_return()
		return
	if Game.now_stop_state:
		return
	roster_refresh -= delta
	if roster_refresh <= 0.0:
		roster_refresh = 0.25
		for raw:Node in get_tree().get_nodes_in_group("Ball"):
			if raw is CharacterBody2D and raw.get("Type") == 0 and not known_participants.has(raw.get_instance_id()):
				_register_participant(raw)
				if in_temp:
					var uv:Vector2 = (raw.global_position-arena_rect.position)/arena_rect.size
					participants.back()["position"] = original_rect.position+uv.clamp(Vector2(0.15,0.15),Vector2(0.85,0.85))*original_rect.size
	if gesture_left>0.0:
		gesture_left=maxf(gesture_left-maxf(delta,0.0),0.0)
		if gesture_left<=0.0: source.call("_set_visual_mode_local",0)
	elapsed = minf(elapsed+maxf(delta,0.0),total_duration)
	while event_cursor < events.size() and float(events[event_cursor].t) <= elapsed:
		_dispatch(events[event_cursor])
		event_cursor += 1
	if in_temp and elapsed >= CORRIDOR_START and elapsed <= CORRIDOR_END:
		var t:float = elapsed-CORRIDOR_START
		arena_rect.size.x = base_rect.size.x*(1.0+t*0.95)
		arena_rect.size.y = base_rect.size.y*lerpf(1.0,corridor_height/base_rect.size.y,minf(t/2.0,1.0))
		arena_rect.position.y = base_rect.get_center().y-arena_rect.size.y*0.5
		_update_arena_geometry()
	if pending_corridor and not _moving_bones_alive():
		pending_corridor=false
		_start_corridor()
	_sync_wall_bones()
	_update_slams(delta)
	if elapsed >= WIND_START and elapsed < wind_end:
		while wind_emitted < wind_steps and WIND_START+wind_emitted*wind_interval <= elapsed:
			if wind_emitted==0: _gesture(2)
			if source.is_multiplayer_authority():
				source.call("_spawn_windmill_gaster",original_rect,-TAU*float(wind_emitted)/float(wind_slots))
			wind_emitted += 1
	_hold_source()
	if elapsed >= total_duration:
		finish(true)

func _gesture(side:int) -> void:
	# Same battle clock as the countdown, so pause cannot consume the gesture timer.
	source.set("_gesture_serial",int(source.get("_gesture_serial"))+1)
	var mode:int=source.call("_visual_mode_for_wall_side",side)
	source.call("_set_visual_mode_local",mode)
	gesture_left=source.call("_gesture_duration_for_mode",mode)
func _moving_bones_alive() -> bool:
	for effect:Node2D in hazards:
		if is_instance_valid(effect) and not effect.is_queued_for_deletion() and effect.get_script()==BONE and effect.travel_speed>0.0: return true
	return false
func _start_corridor() -> void:
	_clear_hazards()
	_set_gravity(Vector2.RIGHT,base_rect.size.x*0.8,base_rect.size.x*3.0)
	_build_stationary_corridor()
func _dispatch(event:Dictionary) -> void:
	match str(event.kind):
		"slam": _start_slam(event.dir)
		"scroll": _spawn_scroll(int(event.i))
		"corridor":
			if _moving_bones_alive(): pending_corridor=true
			else: _start_corridor()
		"groups":
			_clear_hazards() # 弧线完整结束，才进入分组骨头；绝不同时预生成两套。
			_build_group_corridor()
		"return":
			_clear_hazards()
			_release_gravity()
			_restore_map()
		"final_black":
			_clear_hazards()
			_release_gravity()
			anchor = original_rect.get_center()

func _hold_source() -> void:
	if is_instance_valid(source):
		source.global_position = anchor
		source.velocity = Vector2.ZERO
		source.Repel = Vector2.ZERO

func _set_gravity(direction:Vector2,terminal:float,strength:float) -> void:
	_clear_slams()
	if not source.is_multiplayer_authority():
		return
	for entry:Dictionary in participants:
		var unit:Node2D = entry.ref.get_ref()
		if not is_instance_valid(unit) or unit == source or unit.health <= 0:
			continue
		unit.cancel_external_directional_gravity_release()
		unit.clear_external_directional_gravity_velocity()
		unit.external_directional_gravity_terminal_speed = terminal
		unit.up_direction = -direction
		unit.configure_external_directional_gravity_locomotion(true,0.8)
		unit.configure_external_directional_gravity_hop(false)
		world.call("register_directional_gravity",self,str(unit.get_instance_id()),direction,strength,false,unit)
		source.call("_set_target_gravity_rotation_networked",str(unit.name),float(entry.rotation)+direction.angle()-Vector2.DOWN.angle())
		if not entry.tinted:
			source.call("_set_gravity_tint_networked",str(unit.name),true)
			entry.tinted = true

func _start_slam(direction:Vector2) -> void:
	_gesture(source.call("_wall_side_for_gravity_direction",direction))
	_clear_slams()
	impact_sides.clear()
	var rect:Rect2 = arena_rect if in_temp else original_rect
	_set_gravity(direction,maxf(rect.size.length()*3.0,900.0),maxf(rect.size.length()*20.0,8000.0))
	if source.is_multiplayer_authority():
		for entry:Dictionary in participants:
			var unit:Node2D = entry.ref.get_ref()
			if is_instance_valid(unit) and unit != source and unit.health > 0:
				source.call("_begin_slam_target_phasing",unit)
				slams.append({"ref":weakref(unit),"direction":direction,"time":0.0,"rect":rect})

func _update_slams(delta:float) -> void:
	for i:int in range(slams.size()-1,-1,-1):
		var item:Dictionary = slams[i]
		var unit:Node2D = item.ref.get_ref()
		if not is_instance_valid(unit) or unit.health <= 0:
			if is_instance_valid(unit):
				source.call("_end_slam_target_phasing",unit)
			slams.remove_at(i)
			continue
		item.time += delta
		var distance:float = source.call("_distance_to_map_wall",unit,item.direction,item.rect)
		if distance <= 3.0 and float(item.time) >= 0.06:
			var side:int = source.call("_wall_side_for_gravity_direction",item.direction)
			# 同一波全员砸墙只生成一面骨墙，不随人数堆出几十面重叠伤害。
			if not impact_sides.has(side):
				impact_sides[side] = true
				source.call("_trigger_gravity_slam_screen_shake_networked",item.direction)
				source.call("_play_slam_sfx_networked",unit.global_position)
				# 真实撞墙才刺出；每次骨刺仅维持 0.14 秒，不改普通骨墙默认寿命。
				_spawn_spike(item.rect,side)
			source.call("_end_slam_target_phasing",unit)
			_enable_slam_hop(unit,item.direction)
			if str(unit.Team) != str(source.Team):
				unit.receive_positional_damage(1.0,unit.global_position,true,source)
			slams.remove_at(i)
		elif float(item.time) > 1.6:
			# 受特殊位移/障碍阻挡时不能凭定时器伪造撞墙。
			source.call("_end_slam_target_phasing",unit)
			_enable_slam_hop(unit,item.direction)
			slams.remove_at(i)

func _enable_slam_hop(unit:Node2D,direction:Vector2) -> void:
	# 强砸只占飞行段。落地后降回正常重力，允许在两次砸击间反重力起跳。
	world.call("register_directional_gravity",self,str(unit.get_instance_id()),direction,720.0,false,unit)
	unit.external_directional_gravity_terminal_speed = 420.0
	unit.configure_external_directional_gravity_hop(true,0.18,0.40,0,2.0,4.0)

func _spawn_spike(rect:Rect2,side:int) -> void:
	var attack:Rect2 = source.call("_make_full_wall_bone_rect",rect,side)
	if multiplayer.has_multiplayer_peer():
		_rpc_spike.rpc(attack,side)
	else:
		_rpc_spike(attack,side)

@rpc("authority","call_local","reliable")
func _rpc_spike(rect:Rect2,side:int) -> void:
	if not WALL_SLOTS.available(self,side): return
	var effect:Node2D = SPIKE.new()
	WALL_SLOTS.register(effect,self,side,str(effect.get_instance_id()))
	add_child(effect)
	effect.add_to_group("BattleTransient")
	effect.call("configure",source,rect,side,0.05,0.06,0.14,5.0,1.0)
	hazards.append(effect)

func _bone(root:Vector2,inward:Vector2,move:Vector2,speed:float,length:float,life:float) -> void:
	var side:int=WALL_SLOTS.side_from_inward(inward)
	if not WALL_SLOTS.available(self,side,bone_token): return
	var bone:Node2D = BONE.new()
	WALL_SLOTS.register(bone,self,side,bone_token)
	add_child(bone)
	bone.add_to_group("BattleTransient")
	bone.call("configure_final",source,root,inward,move,speed,maxf(length,8.0),life)
	bone.set_meta(&"trial_wall_side",0 if inward.y > 0.0 else 2)
	bone.set_meta(&"trial_wall_left",arena_rect.position.x)
	hazards.append(bone)
	_sync_wall_bones()

func _sync_wall_bones() -> void:
	if not in_temp:
		return
	for bone:Node2D in hazards:
		if not is_instance_valid(bone) or bone.is_queued_for_deletion() or not bone.has_meta(&"trial_wall_side"):
			continue
		# 沿墙的 X 位置由骨列/滚动控制；根部 Y 永远等于当前墙面，包含收窄过程。
		bone.global_position.x += arena_rect.position.x-float(bone.get_meta(&"trial_wall_left",arena_rect.position.x))
		bone.set_meta(&"trial_wall_left",arena_rect.position.x)
		bone.global_position.y = arena_rect.position.y if int(bone.get_meta(&"trial_wall_side")) == 0 else arena_rect.end.y

func _spawn_scroll(index:int) -> void:
	if index == 0:
		_set_gravity(Vector2.DOWN,420.0,720.0)
		for entry:Dictionary in participants:
			var unit:Node2D = entry.ref.get_ref()
			if is_instance_valid(unit) and unit != source:
				unit.configure_external_directional_gravity_hop(true,0.25,0.65,0,2.0,4.0)
	var top:bool = index%2 == 0
	if not WALL_SLOTS.available(self,0 if top else 2): return
	bone_token=str(get_path())+":scroll:"+str(index)
	_gesture(0 if top else 2)
	var height:float = base_rect.size.y
	var y:float = base_rect.position.y+4.0 if top else base_rect.end.y-4.0
	var inward:Vector2 = Vector2.DOWN if top else Vector2.UP
	for j:int in range(3):
		_bone(Vector2(base_rect.end.x+8+j*20,y),inward,Vector2.LEFT,base_rect.size.x*0.65,height*0.32,3.0)

func _build_stationary_corridor() -> void:
	bone_token=str(get_path())+":corridor"
	_gesture(3)
	var h:float = corridor_height
	var cy:float = base_rect.get_center().y
	var start:float = base_rect.position.x+base_rect.size.x*0.85
	var span:float = base_rect.size.x*5.5
	# 20 对取代 38 对；长段整体为一个弧形，而非密集重复的小波浪。
	for i:int in range(20):
		var u:float = float(i)/19.0
		var x:float = start+span*u
		var amplitude:float = maxf((h-corridor_gap)*0.5-10.0,0.0)
		var gap_y:float = cy+cos(u*TAU)*minf(h*0.22,amplitude)
		_bone(Vector2(x,arena_rect.position.y),Vector2.DOWN,Vector2.ZERO,0.0,gap_y-corridor_gap*0.5-(cy-h*0.5),16.0)
		_bone(Vector2(x,arena_rect.end.y),Vector2.UP,Vector2.ZERO,0.0,(cy+h*0.5)-(gap_y+corridor_gap*0.5),16.0)

func _build_group_corridor() -> void:
	bone_token=str(get_path())+":groups"
	_gesture(3)
	var h:float = corridor_height
	# 与先前弧形段末端衔接；六组、每组三根，组内 20px，组间 112px。
	var start:float = base_rect.position.x+base_rect.size.x*7.85
	for i:int in range(6):
		var top:bool = i%2 == 0
		for j:int in range(3):
			var x:float = start+i*base_rect.size.x*0.70+j*20.0
			_bone(Vector2(x,arena_rect.position.y if top else arena_rect.end.y),Vector2.DOWN if top else Vector2.UP,Vector2.ZERO,0.0,minf(h*0.46,h-corridor_gap),8.0)

func _clear_slams() -> void:
	for item:Dictionary in slams:
		var unit:Node2D = item.ref.get_ref()
		if is_instance_valid(unit) and is_instance_valid(source):
			source.call("_end_slam_target_phasing",unit)
	slams.clear()

func _release_gravity() -> void:
	_clear_slams()
	if not is_instance_valid(world):
		return
	world.call("clear_directional_gravity",self,"")
	for entry:Dictionary in participants:
		var unit:Node2D = entry.ref.get_ref()
		if not is_instance_valid(unit) or unit == source:
			continue
		unit.clear_external_directional_gravity_velocity()
		unit.external_directional_gravity_terminal_speed = float(entry.terminal)
		unit.up_direction = entry.up
		unit.global_rotation = float(entry.rotation)
		if is_instance_valid(source) and source.is_multiplayer_authority():
			source.call("_set_target_gravity_rotation_networked",str(unit.name),float(entry.rotation))
		unit.configure_external_directional_gravity_locomotion(bool(entry.locomotion),float(entry.axis_ratio))
		unit.configure_external_directional_gravity_hop(bool(entry.hop),float(entry.hop_min),float(entry.hop_max),0,float(entry.hop_ratio_min),float(entry.hop_ratio_max))
		if entry.tinted and is_instance_valid(source) and source.is_multiplayer_authority():
			source.call("_set_gravity_tint_networked",str(unit.name),false)
			entry.tinted = false

func _restore_map() -> void:
	if not in_temp or not is_instance_valid(world):
		return
	in_temp = false
	world.set("now_choose_map",original_map)
	world.set("_presentation_map_name",original_map)
	world.set("_map_safety_frame_map_name",snapshot.safety_name)
	if is_instance_valid(old_safety):
		old_safety.process_mode = int(snapshot.safety_process)
		old_safety.visible = bool(snapshot.safety_visible)
	world.set("map_outside_mask_enabled",bool(snapshot.mask_enabled))
	var mask_parts:Array = world.get("map_outside_mask_parts")
	for i:int in range(mini(mask_parts.size(),snapshot.mask_materials.size())):
		mask_parts[i].material = snapshot.mask_materials[i]
	world.get("map_group").erase(TEMP_NAME)
	if is_instance_valid(temp_map):
		temp_map.queue_free()
	for wall:StaticBody2D in walls:
		if is_instance_valid(wall):
			wall.collision_layer = 0
			wall.queue_free()
	walls.clear()
	background.hide()
	border.hide()
	for entry:Dictionary in participants:
		var unit:Node2D = entry.ref.get_ref()
		if is_instance_valid(unit):
			unit.global_position = entry.position
			unit.velocity = Vector2.ZERO
			unit.Repel = Vector2.ZERO
	original_positions_restored = true
	anchor = Vector2(original_rect.get_center().x,original_rect.position.y-maxf(30.0,original_rect.size.y*0.10))
	world.call("refresh_map_presentation")

func _process(_delta:float) -> void:
	if death_return_started >= 0 and not finished:
		_update_death_return()
	if finished or not is_instance_valid(world):
		return
	var camera:Camera2D = world.get("camera_2d")
	if is_instance_valid(camera):
		var view:Rect2 = base_rect if in_temp else original_rect
		if in_temp and elapsed >= CORRIDOR_START:
			var follow_x:float = base_rect.get_center().x
			var count:int = 0
			var sum_x:float = 0.0
			for entry:Dictionary in participants:
				var unit:Node2D = entry.ref.get_ref()
				if is_instance_valid(unit) and unit != source and unit.health > 0:
					sum_x += unit.global_position.x
					count += 1
			if count > 0:
				follow_x = sum_x/float(count)
			view = Rect2(Vector2(follow_x-base_rect.size.x*0.65,arena_rect.position.y),Vector2(base_rect.size.x*1.3,base_rect.size.y))
		var viewport:Vector2 = get_viewport_rect().size
		var zoom:float = minf(viewport.x/(view.size.x*1.30),viewport.y/(view.size.y*1.50))
		camera.zoom = Vector2.ONE*zoom
		camera.global_position = view.get_center()-Vector2(0,view.size.y*0.07)
		camera.force_update_scroll()
	_update_hud()

func _update_hud() -> void:
	if not is_instance_valid(timer_label):
		return
	var hundredths:int = maxi(int(ceil((total_duration-elapsed)*100.0)),0)
	timer_label.text = "%02d:%02d" % [hundredths/100,hundredths%100]
	var view:Vector2 = get_viewport_rect().size
	# 根视口可能以 1080×1920 缩放到手机/竖窗；字号随逻辑高度取值，避免倒计时缩成十几个像素。
	timer_label.add_theme_font_size_override("font_size",maxi(32,int(view.y*0.04)))
	_suppress_surrounding_hud()
	if is_instance_valid(source.health_bar):
		source.health_bar.hide()
	black.size = view
	blackout_root.global_transform=get_viewport().get_canvas_transform().affine_inverse()
	var blackout:float = 0.0
	if elapsed < OPEN_END:
		blackout = 1.0-smoothstep(0.8,OPEN_END,elapsed)
	elif elapsed >= RETURN_START and elapsed < WIND_START:
		blackout = 1.0-smoothstep(RETURN_START+0.7,WIND_START,elapsed)
	elif elapsed >= wind_end+6.0:
		blackout = 1.0-smoothstep(total_duration-0.3,total_duration,elapsed)
	if death_return_started >= 0:
		blackout = smoothstep(0.0,0.20,death_return_time)*(1.0-smoothstep(0.65,1.0,death_return_time))
		hundredths = maxi(int(ceil((1.0-death_return_time)*100.0)),0)
		timer_label.text = "%02d:%02d" % [hundredths/100,hundredths%100]
	black.color.a = blackout
	var rect:Rect2 = arena_rect if in_temp else original_rect
	var marker:Control = world.get("_center_watermark_root")
	if is_instance_valid(marker):
		marker.hide()
	var bottom:Vector2 = Vector2(rect.get_center().x,rect.end.y+float(world.get("center_watermark_bottom_gap"))+16.0)
	if in_temp and elapsed >= CORRIDOR_START:
		bottom.x = world.get("camera_2d").global_position.x
	var target:Vector2 = get_viewport().get_canvas_transform()*bottom
	var center:Vector2 = view*0.5
	var point:Vector2 = center.lerp(target,smoothstep(0.72,OPEN_END,elapsed)) if elapsed < OPEN_END else target
	if blackout > 0.5 and elapsed >= RETURN_START:
		point = center
	timer_label.position = point-timer_label.size*0.5

func _clear_hazards() -> void:
	for effect:Node2D in hazards:
		if is_instance_valid(effect):
			effect.queue_free()
	hazards.clear()

func finish(completed:bool) -> void:
	if finished:
		return
	finished = true
	gesture_left=0.0
	if is_instance_valid(source): source.call("_set_visual_mode_local",0)
	_clear_hazards()
	_release_gravity()
	_restore_map()
	if is_instance_valid(source):
		source.collision_layer = int(snapshot.get("source_layer",2))
		source.collision_mask = int(snapshot.get("source_mask",1))
		source.z_index = int(snapshot.get("source_z",0))
		source.z_as_relative = bool(snapshot.get("source_z_relative",true))
		source.graphics.z_index = int(snapshot.get("graphics_z",0))
		source.graphics.z_as_relative = bool(snapshot.get("graphics_relative",true))
		if snapshot.get("escape") == null:
			source.remove_meta(&"submission_allow_map_escape")
		else:
			source.set_meta(&"submission_allow_map_escape",snapshot.escape)
		source.global_position = original_rect.get_center()
		source.set("_last_trial_active",false)
		source.set("_last_trial_controller",null)
		source.set("_dodge_grace_remaining",0.15)
		source.call("_update_face_visual")
		if is_instance_valid(source.health_bar):
			source.health_bar.visible = bool(snapshot.get("health_bar_visible",true))
	if is_instance_valid(world):
		if world.get_meta(&"sans_final_phase",null) == self:
			world.remove_meta(&"sans_final_phase")
		world.call("_refresh_center_watermark_layout")
		world.get("_center_watermark_root").visible = bool(snapshot.get("watermark_visible",true))
		world.get("versus_label").visible = bool(snapshot.get("versus_visible",true))
		world.get("interaction_label").visible = bool(snapshot.get("interaction_visible",true))
		var camera:Camera2D = world.get("camera_2d")
		if is_instance_valid(camera):
			camera.global_position = snapshot.get("camera_position",original_rect.get_center())
			camera.zoom = snapshot.get("camera_zoom",Vector2.ONE)
			camera.position_smoothing_enabled = bool(snapshot.get("camera_smoothing",false))
	_restore_surrounding_hud()
	set_meta(&"completed",completed)
	queue_free()

func _exit_tree() -> void:
	if not finished and not snapshot.is_empty():
		# 整个 World 正在销毁时不再重建水印/边框或向离树角色发送 RPC。
		if not is_instance_valid(world) or world.is_queued_for_deletion() or not world.is_inside_tree():
			finished = true
			return
		finish(false)

func _start_death_return() -> void:
	if death_return_started >= 0:
		return
	death_return_started = Time.get_ticks_msec()
	death_return_time = 0.0
	_clear_hazards()
	_release_gravity()
	# 胜利可能暂停战斗时钟；收尾黑屏仍须完整结束，不能卡在临时地图。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_update_hud()

func _update_death_return() -> void:
	death_return_time = float(Time.get_ticks_msec()-death_return_started)/1000.0
	if death_return_time >= 0.25 and in_temp:
		_restore_map() # 已全黑，才切回原图。
		anchor = original_rect.get_center()
	_hold_source()
	if death_return_time >= 1.0:
		finish(false)
