extends Node2D

# 菜月昴第 5 次死亡回归后的“死亡回归死档”。
# 这一阶段不加入 BattleTransient，因此不会被死亡回归时间轴倒回。
# 演出开始时暂停 SceneTree；本节点/音效使用 PROCESS_MODE_ALWAYS，
# 黑屏、莎缇拉之手与拖拽演出仍可在暂停状态下继续。

const DEAD_SAVE_SFX:AudioStream = preload("res://audio/characters/菜月昴/死亡回归死档.mp3")
const SATELLA_HAND_TEXTURE:Texture2D = preload("res://Images/characters/动漫/菜月昴/莎缇拉之手.png")
const DEAD_SAVE_CRT_SHADER:Shader = preload("res://shaders/ui/菜月昴死档CRT.gdshader")
const DEAD_SAVE_BG_LOVE_TEXT_SCRIPT = preload("res://scripts/effects/动漫/菜月昴背景爱字.gd")
const DEAD_SAVE_FOG_FRAMES:Array[SpriteFrames] = [
	preload("res://Images/characters/动漫/菜月昴/烟雾/透明序列/死档烟雾01.tres"),
	preload("res://Images/characters/动漫/菜月昴/烟雾/透明序列/死档烟雾02.tres"),
	preload("res://Images/characters/动漫/菜月昴/烟雾/透明序列/死档烟雾03.tres"),
]

# V395：地图本体和地图后方窗口底层统一恢复成深紫色。
const BACKGROUND_PURPLE:Color = Color(0.185,0.038,0.255,1.0)
const BEHIND_MAP_COLOR:Color = Color(0.115,0.012,0.17,1.0)
const FOG_DARK_PURPLE:Color = Color(0.18,0.025,0.24,0.88)
const FOG_BLACK:Color = Color(0.0,0.0,0.0,0.90)
const ARM_COLOR:Color = Color(0.0,0.0,0.0,0.98)

const BLACK_HOLD_SECONDS:float = 0.18
const DIM_FADE_SECONDS:float = 0.82
const FINAL_DIM_ALPHA:float = 0.18
const VIGNETTE_EXPAND_SECONDS:float = 3.20
const SFX_VOLUME_DB:float = 12.0

const GRAB_START_DELAY:float = 0.85
const HAND_EXTEND_SECONDS:float = 1.35
const HAND_WRAP_SECONDS:float = 0.65
const PULL_SECONDS:float = 4.00
const HAND_RETRACT_SECONDS:float = 0.60
const HANDS_PER_TARGET:int = 3
const ARM_WIDTH:float = 7.0
const ARM_CURVE_SAMPLES:int = 15

const LOVE_PHRASE:String = "愛してる"
const LOVE_TYPE_INTERVAL:float = 0.115
const LOVE_PHRASE_PAUSE:float = 0.22
const LOVE_BG_SPAWN_INTERVAL:float = 0.20
const LOVE_BG_MAX_COUNT:int = 60
const LOVE_BG_INITIAL_COUNT:int = 24

const DEAD_SAVE_FOG_COUNT:int = 7
const DEAD_SAVE_FOG_LAYER:int = 115
const DEAD_SAVE_FOG_GRAY:Color = Color(0.10,0.105,0.115,1.0)
const DEAD_SAVE_FOG_PURPLE:Color = Color(0.24,0.025,0.31,1.0)
const DEAD_SAVE_FOG_MIN_LIFE:float = 12.0
const DEAD_SAVE_FOG_MAX_LIFE:float = 22.0

var _world:Node = null
var _map_rect:Rect2 = Rect2()
var _refresh_elapsed:float = 999.0
var _elapsed:float = 0.0
var _grab_elapsed:float = 0.0
var _grab_started:bool = false
var _cinematic_finished:bool = false
var _owns_tree_pause:bool = false

var _love_type_elapsed:float = 0.0
var _love_phrase_pause_remaining:float = 0.0
var _love_char_index:int = 0
var _love_partial:String = ""
var _love_completed:Array[String] = []
var _love_bg_spawn_elapsed:float = 0.0

var _behind_map_root:Node2D = null
var _behind_map_parts:Array[Polygon2D] = []
var _map_background_fill:Polygon2D = null
var _fog_players:Array[Dictionary] = []
var _fog_layer:CanvasLayer = null
var _fog_rng := RandomNumberGenerator.new()
var _dim_layer:CanvasLayer = null
var _dim_rect:ColorRect = null
var _crt_layer:CanvasLayer = null
var _crt_back_buffer:BackBufferCopy = null
var _crt_rect:ColorRect = null
var _crt_material:ShaderMaterial = null
var _audio_player:AudioStreamPlayer = null

var _saved_grid_colors:bool = false
var _saved_grid_enabled:bool = false
var _saved_grid_z:bool = false
var _old_grid_z:int = -2
var _old_grid_enabled:bool = true
var _old_grid_normal:Color = Color.WHITE
var _old_grid_dark:Color = Color.WHITE
var _saved_world_background_visibility:bool = false
var _old_world_background_visible:bool = true
var _world_background_item:CanvasItem = null
var _grab_entries:Array[Dictionary] = []

func activate(_owner_node:Node) -> void:
	_world = get_tree().current_scene
	name = "菜月昴_死亡回归死档"
	process_mode = Node.PROCESS_MODE_ALWAYS
	# V188：进入死档状态的第一件事就是启动音频。播放器挂到 SceneTree 根节点并设为 ALWAYS，
	# 避免随后暂停整棵场景树时音频被一起暂停，也不会等到人物被吞噬死亡后才听见。
	_play_dead_save_sound()
	# V403：进入死档的第一帧立即清掉当前已经存在的伤害跳字，避免黑屏/暂停后旧伤害数字悬在画面上。
	_clear_existing_damage_texts()
	# V407：处决辅助视觉（黑色手臂/脚边局部雾）放到人物后方。
	# 真正允许挡住人物的只有莎缇拉手掌 Sprite；避免旧版高 Z 的遮挡矩形/雾团把人物整块盖住。
	z_index = -1
	_store_and_apply_world_background()
	_update_map_rect(true)
	# V404：先把 World 的逐帧相机逻辑切到“非跟随”分支，再立即刷新当前 Camera2D。
	# 仅改一次 Camera2D 位置会被 Game Autoload 下一帧的 world.process_always() 覆盖回受控角色。
	if _world != null and is_instance_valid(_world) and _world.has_method("set_dead_save_camera_follow_override"):
		_world.call("set_dead_save_camera_follow_override",true)
	_switch_to_non_follow_camera_view()
	_setup_fullscreen_dim()
	_setup_crt_postprocess()
	_apply_world_text_override()
	_reset_love_typewriter()
	_seed_background_love_text()
	_setup_random_fog()
	# V397：人物从进入死档的第一帧就进入颤抖状态；莎缇拉之手仍按原时间延迟出现。
	_begin_global_grab()
	_pause_tree_for_cinematic()
	# Godot 暂停 SceneTree 后再次显式解除播放器 stream_paused，保证死档音效不中断。
	_ensure_dead_save_sound_unpaused()
	set_process(true)

func _process(delta:float) -> void:
	var dt:float = maxf(delta,0.0)
	_elapsed += dt
	_refresh_elapsed += dt
	_update_love_typewriter(dt)
	_update_background_love_text(dt)
	_update_random_fog(dt)
	_ensure_dead_save_sound_unpaused()

	if _refresh_elapsed >= 0.16:
		_refresh_elapsed = 0.0
		_update_map_rect(false)
		_apply_world_background()
		_apply_world_text_override()
		_resize_dim_to_viewport()
		_resize_crt_to_viewport()

	if _grab_started and not _cinematic_finished:
		_grab_elapsed += dt
		_update_global_grab()
		queue_redraw()
	elif _cinematic_finished:
		# V406：死档视觉本身会在第一次处决结束后继续存在。只要状态仍在，
		# 后续新放入场上的 Ball 也必须重新进入同一套莎缇拉处决流程。
		_try_restart_grab_for_new_balls()

func _exit_tree() -> void:
	_restore_tree_pause_if_owned()
	_restore_world_background()
	_cleanup_background_love_text()
	_cleanup_random_fog()
	if _world != null and is_instance_valid(_world):
		if _world.has_method("set_dead_save_camera_follow_override"):
			_world.call("set_dead_save_camera_follow_override",false)
		if _world.has_method("set_dead_save_ui_override"):
			_world.call("set_dead_save_ui_override",false)

# ========================================================
# 全局暂停 / UI / 背景
# ========================================================
func _pause_tree_for_cinematic() -> void:
	var tree:SceneTree = get_tree()
	if tree == null:
		return
	if not tree.paused:
		_owns_tree_pause = true
		tree.paused = true

func _restore_tree_pause_if_owned() -> void:
	if not _owns_tree_pause:
		return
	var tree:SceneTree = get_tree()
	if tree != null:
		tree.paused = false
	_owns_tree_pause = false

func _clear_existing_damage_texts() -> void:
	var tree:SceneTree = get_tree()
	if tree == null:
		return
	# health_bar.gd 会把伤害/回血跳字统一放进 __damage_text_runtime。这里只清负号开头的伤害数字，
	# 不误删当前可能存在的绿色回血“+N”提示。先隐藏确保本帧立刻不可见，再 queue_free 安全释放。
	for node:Node in tree.get_nodes_in_group("__damage_text_runtime"):
		if node == null or not is_instance_valid(node):
			continue
		if node is Label:
			var label:Label = node as Label
			if not label.text.begins_with("-"):
				continue
			label.visible = false
			label.queue_free()


func _apply_world_text_override() -> void:
	if _world == null or not is_instance_valid(_world):
		return
	if _world.has_method("set_dead_save_ui_override"):
		_world.call("set_dead_save_ui_override",true)


func _reset_love_typewriter() -> void:
	_love_type_elapsed = 0.0
	_love_phrase_pause_remaining = 0.0
	_love_char_index = 0
	_love_partial = ""
	_love_completed.clear()
	_push_love_text_to_world()


func _update_love_typewriter(delta:float) -> void:
	if _world == null or not is_instance_valid(_world):
		return
	var remaining:float = maxf(delta,0.0)
	if _love_phrase_pause_remaining > 0.0:
		_love_phrase_pause_remaining = maxf(_love_phrase_pause_remaining - remaining,0.0)
		if _love_phrase_pause_remaining > 0.0:
			return
	_love_type_elapsed += remaining
	while _love_type_elapsed >= LOVE_TYPE_INTERVAL:
		_love_type_elapsed -= LOVE_TYPE_INTERVAL
		if _love_char_index < LOVE_PHRASE.length():
			_love_partial += LOVE_PHRASE.substr(_love_char_index,1)
			_love_char_index += 1
			_push_love_text_to_world()
		if _love_char_index >= LOVE_PHRASE.length():
			_love_completed.append(LOVE_PHRASE)
			_love_partial = ""
			_love_char_index = 0
			_love_phrase_pause_remaining = LOVE_PHRASE_PAUSE
			_push_love_text_to_world()
			break


func _push_love_text_to_world() -> void:
	if _world == null or not is_instance_valid(_world):
		return
	if not _world.has_method("set_dead_save_love_text"):
		return
	# V187：和普通 VS 文字一样，一行允许排下多个“愛してる”，
	# 宽度不够时再由 RichTextLabel 自动换行并继续向地图上方延伸。
	var parts:Array[String] = []
	for phrase:String in _love_completed:
		parts.append(phrase)
	if not _love_partial.is_empty():
		parts.append(_love_partial)
	var display_text:String = "  ".join(parts)
	_world.call("set_dead_save_love_text",display_text)

func _seed_background_love_text() -> void:
	_love_bg_spawn_elapsed = 0.0
	for i:int in range(LOVE_BG_INITIAL_COUNT):
		_spawn_background_love_text(i)


func _update_background_love_text(delta:float) -> void:
	if _world == null or not is_instance_valid(_world):
		return
	_love_bg_spawn_elapsed += maxf(delta,0.0)
	while _love_bg_spawn_elapsed >= LOVE_BG_SPAWN_INTERVAL:
		_love_bg_spawn_elapsed -= LOVE_BG_SPAWN_INTERVAL
		_spawn_background_love_text(randi())


func _spawn_background_love_text(seed_value:int) -> void:
	if _world == null or not is_instance_valid(_world):
		return
	if _map_rect.size.x <= 40.0 or _map_rect.size.y <= 40.0:
		return
	var existing:int = 0
	for node:Node in get_tree().get_nodes_in_group("DeadSaveLoveBackgroundText"):
		if node != null and is_instance_valid(node) and not node.is_queued_for_deletion():
			existing += 1
	if existing >= LOVE_BG_MAX_COUNT:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else Game.battle_rng_seed_or("scripts/effects/动漫/菜月昴死档效果.gd:fallback_seed",int(Time.get_ticks_usec()))
	var point_info:Dictionary = _pick_visible_point_anywhere(rng)
	if not bool(point_info.get("ok",false)):
		return
	var point:Vector2 = point_info.get("point",Vector2.ZERO)
	var text_node:Node2D = DEAD_SAVE_BG_LOVE_TEXT_SCRIPT.new()
	text_node.process_mode = Node.PROCESS_MODE_ALWAYS
	# V402：固定顺序为 外部深紫(-5) < 视差网格(-4) < 愛してる(-3) < 地图深紫(-2) < BackBuffer(-1)。
	text_node.z_as_relative = true
	text_node.z_index = -3
	# 必须先挂进 World 再写 global_position；否则未入树时 global_position 会按局部坐标保存，
	# Camera/Canvas transform 下会把整批背景文字偏出当前窗口。
	_world.add_child(text_node)
	text_node.call("configure",point,rng.randi(),true)
	text_node.set("drift_velocity",Vector2.ZERO)


func _pick_visible_point_anywhere(rng:RandomNumberGenerator) -> Dictionary:
	# V400：随机点覆盖整个当前窗口，不再把 map_rect 排除。
	# 遮挡由绘制层级负责：地图内随机到的字照常生成，但会被 z=-2 的地图深紫填充遮住。
	var viewport:Viewport = get_viewport()
	if viewport == null:
		return {"ok":false}
	var viewport_size:Vector2 = get_viewport_rect().size
	if viewport_size.x <= 8.0 or viewport_size.y <= 8.0:
		return {"ok":false}
	var inv_canvas:Transform2D = viewport.get_canvas_transform().affine_inverse()
	var screen_point := Vector2(
		rng.randf_range(8.0,maxf(viewport_size.x - 8.0,8.0)),
		rng.randf_range(8.0,maxf(viewport_size.y - 8.0,8.0))
	)
	return {"ok":true,"point":inv_canvas * screen_point}


func _cleanup_background_love_text() -> void:
	if get_tree() != null:
		for node:Node in get_tree().get_nodes_in_group("DeadSaveLoveBackgroundText"):
			if node != null and is_instance_valid(node):
				node.queue_free()
	_cleanup_behind_map_background()


func _store_and_apply_world_background() -> void:
	if _world == null or not is_instance_valid(_world):
		return
	if not _saved_grid_colors:
		var normal_value:Variant = _world.get("map_outside_grid_normal_color")
		var dark_value:Variant = _world.get("map_outside_grid_dark_color")
		if normal_value is Color and dark_value is Color:
			_old_grid_normal = normal_value
			_old_grid_dark = dark_value
			_saved_grid_colors = true
	if not _saved_grid_enabled:
		var enabled_value:Variant = _world.get("map_outside_grid_enabled")
		if enabled_value is bool:
			_old_grid_enabled = bool(enabled_value)
			_saved_grid_enabled = true
	# V401：world.tscn 的 Background 是蓝色 Gradient Sprite2D，z=-3。
	# V400 的深紫 Polygon 在它后面，因此仍会露出蓝底，并把棋盘深格混成蓝色。
	# 死档期间直接隐藏原蓝底，退出时恢复；真正底色由死档深紫 Polygon 提供。
	if _world_background_item == null or not is_instance_valid(_world_background_item):
		var background_node:Node = _world.get_node_or_null("Background")
		if background_node is CanvasItem:
			_world_background_item = background_node as CanvasItem
			_old_world_background_visible = _world_background_item.visible
			_saved_world_background_visibility = true
	_apply_world_background()


func _apply_world_background() -> void:
	if _world == null or not is_instance_valid(_world):
		return
	if _world_background_item != null and is_instance_valid(_world_background_item):
		_world_background_item.visible = false
	# 深紫浅格 + 接近纯黑的深格。深格完全不再依赖原蓝 Background 的透明混色。
	_world.set("map_outside_grid_enabled",true)
	_world.set("map_outside_grid_normal_color",Color(0.205,0.030,0.285,0.96))
	_world.set("map_outside_grid_dark_color",Color(0.006,0.003,0.010,1.0))
	var grid_root:Variant = _world.get("map_outside_grid_root")
	if grid_root is CanvasItem and is_instance_valid(grid_root):
		var grid_item:CanvasItem = grid_root as CanvasItem
		if not _saved_grid_z:
			_old_grid_z = grid_item.z_index
			_saved_grid_z = true
		# V402：把实色视差网格放到背景爱字后面，避免棋盘直接盖掉文字。
		grid_item.z_index = -4
		grid_item.visible = true
	if _world.has_method("_update_map_outside_grid_parallax"):
		_world.call("_update_map_outside_grid_parallax")
	_update_behind_map_background()


func _restore_world_background() -> void:
	if _world == null or not is_instance_valid(_world):
		return
	if _saved_grid_colors:
		_world.set("map_outside_grid_normal_color",_old_grid_normal)
		_world.set("map_outside_grid_dark_color",_old_grid_dark)
	if _saved_grid_enabled:
		_world.set("map_outside_grid_enabled",_old_grid_enabled)
	if _saved_world_background_visibility and _world_background_item != null and is_instance_valid(_world_background_item):
		_world_background_item.visible = _old_world_background_visible
	var grid_root:Variant = _world.get("map_outside_grid_root")
	if _saved_grid_z and grid_root is CanvasItem and is_instance_valid(grid_root):
		(grid_root as CanvasItem).z_index = _old_grid_z
	if _world.has_method("_update_map_outside_grid_parallax"):
		_world.call("_update_map_outside_grid_parallax")
	_cleanup_behind_map_background()


func _switch_to_non_follow_camera_view() -> void:
	if _world == null or not is_instance_valid(_world):
		return
	var camera_node:Node = _world.get_node_or_null("Camera2D")
	if not camera_node is Camera2D:
		return
	var camera:Camera2D = camera_node as Camera2D
	var desired_center:Vector2 = camera.global_position
	if _map_rect.size.x > 1.0 and _map_rect.size.y > 1.0:
		desired_center = _map_rect.get_center()

	# V405：这里要复刻的是设置里的“镜头跟随 / Camera_Move”关闭后的视角，
	# 不是只关闭 Follow_Controlled_Character。只有一名角色时 battle_center 就等于角色位置，
	# V404 因此会一直看着活着的角色，等角色被莎缇拉处决后才突然回到地图中心。
	# 现在黑屏出现前直接使用地图中心，并保留玩家已有的中键平移。
	var mouse_offset_value:Variant = _world.get("mouse_offset")
	if mouse_offset_value is Vector2:
		desired_center += mouse_offset_value

	# 清掉上一帧 World Camera shake 的 offset；整屏微颤改由最终 CRT 后处理统一执行，
	# 这样地图、UI、烟雾和文字会一起抖，而不是只有世界画布抖。
	camera.offset = Vector2.ZERO
	camera.global_position = desired_center
	camera.reset_smoothing()
	camera.force_update_scroll()


func _ensure_behind_map_background() -> void:
	if _behind_map_root != null and is_instance_valid(_behind_map_root):
		return
	if _world == null or not is_instance_valid(_world):
		return
	_behind_map_root = Node2D.new()
	_behind_map_root.name = "菜月昴_地图后死档背景"
	# V400：拆开“外部底色 / 爱字 / 地图内部填充”的层级。
	# root=-4 的四块外部深紫底位于最下；爱字独立放 z=-3；地图内部填充子节点 z=2，
	# 实际 world z=-2，与地图外视差网格同级且位于爱字之上，从而遮住地图内随机生成的字。
	_behind_map_root.z_index = -5
	_behind_map_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_world.add_child(_behind_map_root)

	# 地图内部专用深紫底。World 的 TileMap 运行时本来就隐藏，所以这里就是玩家看到的地图底色。
	_map_background_fill = Polygon2D.new()
	_map_background_fill.name = "MapDeepPurpleFill"
	_map_background_fill.color = BACKGROUND_PURPLE
	_map_background_fill.z_index = 3
	_behind_map_root.add_child(_map_background_fill)

	_behind_map_parts.clear()
	for i:int in range(4):
		var poly := Polygon2D.new()
		poly.name = "BehindMap_%d" % i
		poly.color = BEHIND_MAP_COLOR
		poly.z_index = 0
		_behind_map_root.add_child(poly)
		_behind_map_parts.append(poly)

func _update_behind_map_background() -> void:
	if _map_rect.size.x <= 0.0 or _map_rect.size.y <= 0.0:
		return
	_ensure_behind_map_background()
	if _behind_map_root == null or not is_instance_valid(_behind_map_root):
		return
	var extent:float = 1000000.0
	var l:float = _map_rect.position.x
	var r:float = _map_rect.end.x
	var t:float = _map_rect.position.y
	var b:float = _map_rect.end.y
	if _map_background_fill != null and is_instance_valid(_map_background_fill):
		_map_background_fill.color = BACKGROUND_PURPLE
		_map_background_fill.polygon = PackedVector2Array([
			_map_rect.position,
			Vector2(r,t),
			_map_rect.end,
			Vector2(l,b),
		])
	var rects:Array[Rect2] = [
		Rect2(Vector2(-extent,-extent),Vector2(extent * 2.0,t + extent)),
		Rect2(Vector2(-extent,b),Vector2(extent * 2.0,extent - b)),
		Rect2(Vector2(-extent,t),Vector2(l + extent,maxf(b - t,0.0))),
		Rect2(Vector2(r,t),Vector2(extent - r,maxf(b - t,0.0))),
	]
	for i:int in range(mini(_behind_map_parts.size(),rects.size())):
		var rr:Rect2 = rects[i]
		var poly:Polygon2D = _behind_map_parts[i]
		poly.color = BEHIND_MAP_COLOR
		poly.polygon = PackedVector2Array([
			rr.position,
			Vector2(rr.end.x,rr.position.y),
			rr.end,
			Vector2(rr.position.x,rr.end.y),
		])

func _cleanup_behind_map_background() -> void:
	if _behind_map_root != null and is_instance_valid(_behind_map_root):
		_behind_map_root.queue_free()
	_behind_map_root = null
	_map_background_fill = null
	_behind_map_parts.clear()

func _update_map_rect(force_redraw:bool) -> void:
	var next_rect:Rect2 = _read_current_map_rect()
	if force_redraw or next_rect != _map_rect:
		_map_rect = next_rect
		_update_map_background_polygon()

func _read_current_map_rect() -> Rect2:
	if _world == null or not is_instance_valid(_world):
		return Rect2()
	if not _world.has_method("return_map_world_rect"):
		return Rect2()
	var map_group_value:Variant = _world.get("map_group")
	if not map_group_value is Dictionary:
		return Rect2()
	var groups:Dictionary = map_group_value
	var map_name:String = str(_world.get("now_choose_map"))
	if not groups.has(map_name):
		return Rect2()
	var map_node:Variant = groups[map_name]
	if not map_node is TileMapLayer:
		return Rect2()
	var rect_value:Variant = _world.call("return_map_world_rect",map_node)
	return rect_value if rect_value is Rect2 else Rect2()

func _update_map_background_polygon() -> void:
	# V400：地图内/外仍统一深紫；爱字生成点覆盖全窗口，但地图内部分由地图填充遮挡。
	_update_behind_map_background()



# ========================================================
# V402：屏幕随机烟雾（离线去黑透明序列 + AnimatedSprite2D）
# ========================================================
func _setup_random_fog() -> void:
	if _world == null or not is_instance_valid(_world) or DEAD_SAVE_FOG_FRAMES.is_empty():
		return
	_cleanup_random_fog()
	_fog_rng.seed = Game.battle_rng_seed_or("scripts/effects/动漫/菜月昴死档效果.gd:_fog_rng.seed",int(Time.get_ticks_usec()) ^ int(get_instance_id()))

	# V401 的 VideoStreamPlayer/get_video_texture 路径在实机上仍没有稳定显示。
	# V402 直接使用预先从原 MP4 去黑得到的透明 WebP 帧，完全绕开运行时视频纹理。
	_fog_layer = CanvasLayer.new()
	_fog_layer.name = "菜月昴死档_屏幕随机烟雾"
	_fog_layer.layer = DEAD_SAVE_FOG_LAYER
	_fog_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_fog_layer)

	for i:int in range(DEAD_SAVE_FOG_COUNT):
		var sprite := AnimatedSprite2D.new()
		sprite.name = "菜月昴死档烟雾_%02d" % (i + 1)
		sprite.process_mode = Node.PROCESS_MODE_ALWAYS
		sprite.centered = true
		sprite.z_index = i
		_fog_layer.add_child(sprite)
		_fog_players.append({
			"sprite": sprite,
			"remaining": 0.0,
			"angle": 0.0,
			"angular_velocity": 0.0,
			"edge_margin": 0.0,
			"edge_slide": 0.0,
			"edge_slide_velocity": 0.0,
			"display_width": 1.0,
		})
		_randomize_fog_entry(i,true)


func _randomize_fog_entry(index:int,_first_time:bool = false) -> void:
	if index < 0 or index >= _fog_players.size():
		return
	var entry:Dictionary = _fog_players[index]
	var sprite:AnimatedSprite2D = entry.get("sprite") as AnimatedSprite2D
	if sprite == null or not is_instance_valid(sprite):
		return
	var view_size:Vector2 = get_viewport_rect().size
	if view_size.x <= 1.0 or view_size.y <= 1.0:
		return

	var frames:SpriteFrames = DEAD_SAVE_FOG_FRAMES[_fog_rng.randi_range(0,DEAD_SAVE_FOG_FRAMES.size() - 1)]
	sprite.sprite_frames = frames
	sprite.animation = &"default"
	var frame_count:int = maxi(frames.get_frame_count(&"default"),1)
	sprite.frame = _fog_rng.randi_range(0,frame_count - 1)
	sprite.speed_scale = _fog_rng.randf_range(0.70,1.18)
	sprite.play(&"default")

	var first_texture:Texture2D = frames.get_frame_texture(&"default",0)
	var source_width:float = 960.0
	if first_texture != null:
		source_width = maxf(first_texture.get_size().x,1.0)
	# 超大雾：整团宽度为窗口 8~12 倍；视觉强度只靠低 alpha，不再被去黑 Shader 二次乘没。
	var display_width:float = view_size.x * _fog_rng.randf_range(8.0,12.0)
	var uniform_scale:float = display_width / source_width
	sprite.scale = Vector2(uniform_scale,uniform_scale)
	entry["display_width"] = display_width

	entry["angle"] = _fog_rng.randf_range(-PI,PI)
	entry["angular_velocity"] = _fog_rng.randf_range(-0.032,0.032)
	if absf(float(entry["angular_velocity"])) < 0.008:
		entry["angular_velocity"] = 0.008 * (-1.0 if _fog_rng.randf() < 0.5 else 1.0)
	entry["edge_margin"] = _fog_rng.randf_range(24.0,110.0)
	var view_diag:float = view_size.length()
	entry["edge_slide"] = _fog_rng.randf_range(-view_diag * 0.16,view_diag * 0.16)
	entry["edge_slide_velocity"] = _fog_rng.randf_range(-8.0,8.0)

	var purple_mix:float = pow(_fog_rng.randf(),0.82)
	var tint:Color = DEAD_SAVE_FOG_GRAY.lerp(DEAD_SAVE_FOG_PURPLE,purple_mix)
	if _fog_rng.randf() < 0.30:
		tint = Color(_fog_rng.randf_range(0.12,0.22),_fog_rng.randf_range(0.11,0.18),_fog_rng.randf_range(0.14,0.24),1.0)
	tint.a = _fog_rng.randf_range(0.055,0.095)
	sprite.modulate = tint

	entry["remaining"] = _fog_rng.randf_range(DEAD_SAVE_FOG_MIN_LIFE,DEAD_SAVE_FOG_MAX_LIFE)
	_fog_players[index] = entry
	_apply_fog_outside_edge_constraint(index)


func _apply_fog_outside_edge_constraint(index:int) -> void:
	if index < 0 or index >= _fog_players.size():
		return
	var entry:Dictionary = _fog_players[index]
	var sprite:AnimatedSprite2D = entry.get("sprite") as AnimatedSprite2D
	if sprite == null or not is_instance_valid(sprite):
		return
	var view_size:Vector2 = get_viewport_rect().size
	if view_size.x <= 1.0 or view_size.y <= 1.0:
		return

	var angle:float = float(entry.get("angle",0.0))
	var forward := Vector2(cos(angle),sin(angle))
	var original_left_normal := -forward
	var left_edge_tangent := Vector2(-sin(angle),cos(angle))
	var view_center:Vector2 = view_size * 0.5
	var support:float = absf(original_left_normal.x) * view_size.x * 0.5 + absf(original_left_normal.y) * view_size.y * 0.5
	var margin:float = maxf(float(entry.get("edge_margin",36.0)),8.0)
	var slide:float = float(entry.get("edge_slide",0.0))
	var left_edge_center:Vector2 = view_center + original_left_normal * (support + margin) + left_edge_tangent * slide
	var display_width:float = maxf(float(entry.get("display_width",view_size.x * 8.0)),1.0)
	var sprite_center:Vector2 = left_edge_center - original_left_normal * (display_width * 0.5)
	sprite.rotation = angle
	sprite.position = sprite_center


func _update_random_fog(delta:float) -> void:
	if _fog_players.is_empty():
		return
	var dt:float = maxf(delta,0.0)
	var view_diag:float = get_viewport_rect().size.length()
	for i:int in range(_fog_players.size()):
		var entry:Dictionary = _fog_players[i]
		var sprite:AnimatedSprite2D = entry.get("sprite") as AnimatedSprite2D
		if sprite == null or not is_instance_valid(sprite):
			continue
		if not sprite.is_playing():
			sprite.play(&"default")

		entry["angle"] = wrapf(float(entry.get("angle",0.0)) + float(entry.get("angular_velocity",0.0)) * dt,-PI,PI)
		var slide:float = float(entry.get("edge_slide",0.0)) + float(entry.get("edge_slide_velocity",0.0)) * dt
		var slide_limit:float = maxf(view_diag * 0.28,60.0)
		if slide > slide_limit:
			slide = slide_limit
			entry["edge_slide_velocity"] = -absf(float(entry.get("edge_slide_velocity",0.0)))
		elif slide < -slide_limit:
			slide = -slide_limit
			entry["edge_slide_velocity"] = absf(float(entry.get("edge_slide_velocity",0.0)))
		entry["edge_slide"] = slide
		entry["remaining"] = float(entry.get("remaining",0.0)) - dt
		_fog_players[i] = entry
		_apply_fog_outside_edge_constraint(i)
		if float(entry["remaining"]) <= 0.0:
			_randomize_fog_entry(i,false)


func _cleanup_random_fog() -> void:
	for entry:Dictionary in _fog_players:
		var sprite:AnimatedSprite2D = entry.get("sprite") as AnimatedSprite2D
		if sprite != null and is_instance_valid(sprite):
			sprite.stop()
			sprite.queue_free()
	_fog_players.clear()
	if _fog_layer != null and is_instance_valid(_fog_layer):
		_fog_layer.queue_free()
	_fog_layer = null


# ========================================================
# 黑屏 / 全局暗幕 / 音效
# ========================================================
func _setup_fullscreen_dim() -> void:
	if _dim_layer != null and is_instance_valid(_dim_layer):
		return
	_dim_layer = CanvasLayer.new()
	_dim_layer.name = "死亡回归死档_全屏暗幕"
	_dim_layer.layer = 120
	_dim_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_dim_layer)

	_dim_rect = ColorRect.new()
	_dim_rect.name = "黑屏与持续暗幕"
	_dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim_rect.color = Color(0.0,0.0,0.0,1.0)
	_dim_rect.process_mode = Node.PROCESS_MODE_ALWAYS
	_dim_layer.add_child(_dim_rect)
	_resize_dim_to_viewport()

	var tween:Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_interval(BLACK_HOLD_SECONDS)
	tween.tween_method(_set_dim_alpha,1.0,FINAL_DIM_ALPHA,DIM_FADE_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _resize_dim_to_viewport() -> void:
	if _dim_rect == null or not is_instance_valid(_dim_rect):
		return
	_dim_rect.position = Vector2.ZERO
	_dim_rect.size = get_viewport_rect().size

func _set_dim_alpha(value:float) -> void:
	if _dim_rect == null or not is_instance_valid(_dim_rect):
		return
	var c:Color = _dim_rect.color
	c.a = clampf(value,0.0,1.0)
	_dim_rect.color = c


func _setup_crt_postprocess() -> void:
	if _crt_layer != null and is_instance_valid(_crt_layer):
		return
	_crt_layer = CanvasLayer.new()
	_crt_layer.name = "死亡回归死档_CRT失真"
	# 高于全局暗幕与普通 HUD，让 CRT/色差/扫描线作用到整个窗口最终画面。
	_crt_layer.layer = 220
	_crt_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_crt_layer)

	# World 自己已有更早的 BackBufferCopy 用于地图外裁剪。Godot 2D 的 screen_texture
	# 会优先读取最近一次 back buffer；因此这里必须在最终后处理层重新复制整个窗口，
	# 再让 CRT ColorRect 读取，确保拿到人物、UI 与暗幕都已经绘制后的当前画面。
	_crt_back_buffer = BackBufferCopy.new()
	_crt_back_buffer.name = "CRT最终窗口拷贝"
	_crt_back_buffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_crt_back_buffer.process_mode = Node.PROCESS_MODE_ALWAYS
	_crt_back_buffer.z_index = 0
	_crt_layer.add_child(_crt_back_buffer)

	_crt_rect = ColorRect.new()
	_crt_rect.name = "CRT老电视后处理"
	_crt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crt_rect.process_mode = Node.PROCESS_MODE_ALWAYS
	_crt_rect.z_index = 1
	# 透明作为 Shader 编译/资源异常时的安全后备，避免材质失效时整屏退化成白色 ColorRect。
	_crt_rect.color = Color(1.0,1.0,1.0,0.0)
	_crt_material = ShaderMaterial.new()
	_crt_material.shader = DEAD_SAVE_CRT_SHADER
	# V400：CRT 仍从黑屏第一帧启用；保留色差/扫描线/颗粒/同步抖动/撕裂等层次，
	# 斜向持续纹理继续很弱，并彻底移除从上到下滚动的扫光亮带。
	_crt_material.set_shader_parameter("effect_strength",0.94)
	_crt_material.set_shader_parameter("vignette_progress",0.0)
	_crt_rect.material = _crt_material
	_crt_layer.add_child(_crt_rect)
	_resize_crt_to_viewport()

	# CRT 从黑屏开始即生效；暗角仍严格遵守上一轮要求，在黑屏 hold + 淡出完全结束后才开始扩大。
	var vignette_tween:Tween = create_tween()
	vignette_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	vignette_tween.tween_interval(BLACK_HOLD_SECONDS + DIM_FADE_SECONDS)
	vignette_tween.tween_method(_set_crt_vignette_progress,0.0,1.0,VIGNETTE_EXPAND_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _resize_crt_to_viewport() -> void:
	if _crt_rect == null or not is_instance_valid(_crt_rect):
		return
	_crt_rect.position = Vector2.ZERO
	_crt_rect.size = get_viewport_rect().size


func _set_crt_strength(value:float) -> void:
	if _crt_material == null or not is_instance_valid(_crt_material):
		return
	_crt_material.set_shader_parameter("effect_strength",clampf(value,0.0,1.0))

func _set_crt_vignette_progress(value:float) -> void:
	if _crt_material == null or not is_instance_valid(_crt_material):
		return
	_crt_material.set_shader_parameter("vignette_progress",clampf(value,0.0,1.0))

func _play_dead_save_sound() -> void:
	if DEAD_SAVE_SFX == null or get_tree() == null or get_tree().root == null:
		return
	if _audio_player != null and is_instance_valid(_audio_player):
		_audio_player.stop()
		_audio_player.queue_free()
	_audio_player = AudioStreamPlayer.new()
	_audio_player.name = "死亡回归死档"
	_audio_player.stream = DEAD_SAVE_SFX
	_audio_player.volume_db = SFX_VOLUME_DB
	_audio_player.process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(&"GameplayRecord") >= 0:
		_audio_player.bus = &"GameplayRecord"
	else:
		_audio_player.bus = &"Master"
	# 挂到 SceneTree 根节点：死档节点随后暂停 current_scene 时，这个播放器仍立即开始并持续播放。
	get_tree().root.add_child(_audio_player)
	_audio_player.finished.connect(_audio_player.queue_free,CONNECT_ONE_SHOT)
	_audio_player.play()
	_audio_player.stream_paused = false

func _ensure_dead_save_sound_unpaused() -> void:
	if _audio_player == null or not is_instance_valid(_audio_player):
		return
	_audio_player.process_mode = Node.PROCESS_MODE_ALWAYS
	if _audio_player.stream_paused:
		_audio_player.stream_paused = false

# ========================================================
# 莎缇拉之手：所有 Ball 同时被缠住、颤抖、拖入雾中
# ========================================================
func _begin_global_grab() -> void:
	if _grab_started:
		return
	_grab_started = true
	_grab_elapsed = 0.0
	_grab_entries.clear()

	for raw:Node in get_tree().get_nodes_in_group("Ball"):
		if raw == null or not is_instance_valid(raw) or raw.is_queued_for_deletion():
			continue
		# 非 authority 客户端上，被死档处决的角色可能会短暂保留到网络 despawn 到达。
		# 已经标记过的目标不能被下一轮再次抓取。
		if bool(raw.get_meta(&"satella_dead_save_forced_death",false)):
			continue
		if not raw is Node2D:
			continue
		var target:Node2D = raw as Node2D
		var bounds:Rect2 = _estimate_target_bounds_global(target)
		var width:float = clampf(maxf(bounds.size.x,40.0),40.0,230.0)
		var height:float = clampf(maxf(bounds.size.y,56.0),56.0,280.0)
		var fog_center_x:float = bounds.get_center().x
		var fog_y:float = bounds.end.y - minf(height * 0.04,4.0)
		var pull_depth:float = height + 52.0
		var mask_width:float = maxf(width * 1.28,72.0)
		var root_base:Vector2 = target.global_position

		var grip_points:Array[Vector2] = [
			Vector2(bounds.position.x + width * 0.23,bounds.position.y + height * 0.38),
			Vector2(bounds.position.x + width * 0.50,bounds.position.y + height * 0.54),
			Vector2(bounds.position.x + width * 0.77,bounds.position.y + height * 0.40),
		]
		var start_points:Array[Vector2] = [
			Vector2(fog_center_x - width * 0.30,fog_y + 4.0),
			Vector2(fog_center_x,fog_y + 7.0),
			Vector2(fog_center_x + width * 0.30,fog_y + 4.0),
		]

		var hand_nodes:Array[Sprite2D] = []
		for i:int in range(HANDS_PER_TARGET):
			var hand := Sprite2D.new()
			hand.name = "莎缇拉之手_%d" % i
			hand.texture = SATELLA_HAND_TEXTURE
			hand.centered = true
			hand.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			hand.scale = Vector2.ONE * (0.18 + 0.018 * float(i))
			hand.modulate = Color(0.86,0.80,0.94,0.0)
			# V407：手掌独立使用绝对 Z，确保只由手掌本身压在人物前面；
			# 父节点上的手臂/局部雾仍保持在人物后方。
			hand.z_as_relative = false
			hand.z_index = 97
			add_child(hand)
			hand.global_position = start_points[i]
			hand_nodes.append(hand)

		_prepare_target_for_grab(target)
		_grab_entries.append({
			"ref": weakref(target),
			"base_root": root_base,
			"bounds": bounds,
			"width": width,
			"height": height,
			"fog_center_x": fog_center_x,
			"fog_y": fog_y,
			"pull_depth": pull_depth,
			"mask_width": mask_width,
			"grips": grip_points,
			"starts": start_points,
			"hands": hand_nodes,
			"phase": randf_range(0.0,TAU),
			"killed": false,
		})

	queue_redraw()


func _try_restart_grab_for_new_balls() -> void:
	# 第一次处决演出完成后 SceneTree 会恢复，但死档节点不会消失。
	# 因此持续检查 Ball 组；一旦玩家在死档期间又放入角色，就重新开始同一套
	# “立即颤抖 -> 手伸出缠绕 -> 雾中沉没 -> 强制死亡”的完整流程。
	var tree:SceneTree = get_tree()
	if tree == null:
		return
	var has_new_target:bool = false
	for raw:Node in tree.get_nodes_in_group("Ball"):
		if raw == null or not is_instance_valid(raw) or raw.is_queued_for_deletion():
			continue
		if bool(raw.get_meta(&"satella_dead_save_forced_death",false)):
			continue
		if raw is Node2D:
			has_new_target = true
			break
	if not has_new_target:
		return

	# 重新使用现有全局处决流程，保证新角色不是直接瞬删，而是和第一次一样被莎缇拉之手杀死。
	_grab_started = false
	_cinematic_finished = false
	_begin_global_grab()
	_pause_tree_for_cinematic()
	_ensure_dead_save_sound_unpaused()

func _prepare_target_for_grab(target:Node2D) -> void:
	# SceneTree 已暂停；这里再关掉目标自己的物理/碰撞，确保任何 ALWAYS 节点也不会在演出中改位置。
	target.set_physics_process(false)
	if target is CollisionObject2D:
		var collision_object:CollisionObject2D = target as CollisionObject2D
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
	var health_bar_value:Variant = target.get("health_bar")
	if health_bar_value is CanvasItem:
		(health_bar_value as CanvasItem).visible = false
	var status_value:Variant = target.get("status_image")
	if status_value is CanvasItem:
		(status_value as CanvasItem).visible = false
	var side_status_value:Variant = target.get("side_status_ui")
	if side_status_value is CanvasItem:
		(side_status_value as CanvasItem).visible = false

func _update_global_grab() -> void:
	# V397：角色颤抖从 _grab_elapsed=0 开始；只有手的伸出阶段保留原来的 0.85 秒延迟。
	var extend_end:float = GRAB_START_DELAY + HAND_EXTEND_SECONDS
	var wrap_end:float = extend_end + HAND_WRAP_SECONDS
	var pull_end:float = wrap_end + PULL_SECONDS
	var retract_end:float = pull_end + HAND_RETRACT_SECONDS

	for index:int in range(_grab_entries.size()):
		var entry:Dictionary = _grab_entries[index]
		var target:Node2D = null
		var wr:Variant = entry.get("ref")
		if wr is WeakRef:
			var obj:Variant = (wr as WeakRef).get_ref()
			if obj is Node2D and is_instance_valid(obj):
				target = obj as Node2D

		# V407：角色本体不再真的向屏幕下方移动，只在原位置持续颤抖。
		# 旧版从脚底向上推进的紫色遮挡矩形已删除，避免长色块伸出屏幕并盖住人物。
		var displacement:Vector2 = Vector2.ZERO
		var phase:float = float(entry.get("phase",0.0))
		if _grab_elapsed >= wrap_end:
			var pull_t:float = clampf((_grab_elapsed - wrap_end) / maxf(PULL_SECONDS,0.001),0.0,1.0)
			var shake_amp:float = lerpf(1.55,4.8,pull_t)
			var shake_x:float = sin(_grab_elapsed * 52.0 + phase) * shake_amp
			var shake_y:float = sin(_grab_elapsed * 67.0 + phase * 1.7) * shake_amp * 0.28
			displacement = Vector2(shake_x,shake_y)
		else:
			# 一进入死档就轻微颤抖；手尚未出现时也可见。随后在缠绕阶段自然接到更强的抖动。
			var pre_strength:float = 1.10 if _grab_elapsed < extend_end else 1.40
			displacement = Vector2(
				sin(_grab_elapsed * 45.0 + phase) * pre_strength,
				sin(_grab_elapsed * 61.0 + phase * 1.7) * pre_strength * 0.30
			)
		if target != null:
			var base_root:Vector2 = entry.get("base_root",target.global_position)
			target.global_position = base_root + displacement

		_update_entry_hands(entry,displacement,extend_end,pull_end,retract_end)

		if _grab_elapsed >= pull_end and not bool(entry.get("killed",false)):
			entry["killed"] = true
			if target != null:
				_force_target_death(target)

		_grab_entries[index] = entry

	if _grab_elapsed >= retract_end:
		_finish_global_grab()

func _update_entry_hands(entry:Dictionary,displacement:Vector2,extend_end:float,pull_end:float,_retract_end:float) -> void:
	var starts:Array = entry.get("starts",[])
	var grips:Array = entry.get("grips",[])
	var hands:Array = entry.get("hands",[])
	if starts.size() < HANDS_PER_TARGET or grips.size() < HANDS_PER_TARGET:
		return

	var extend_t:float = clampf((_grab_elapsed - GRAB_START_DELAY) / maxf(HAND_EXTEND_SECONDS,0.001),0.0,1.0)
	var extend_ease:float = _ease_out_cubic(extend_t)
	var retract_t:float = 0.0
	if _grab_elapsed > pull_end:
		retract_t = clampf((_grab_elapsed - pull_end) / maxf(HAND_RETRACT_SECONDS,0.001),0.0,1.0)

	for i:int in range(mini(hands.size(),HANDS_PER_TARGET)):
		var hand:Variant = hands[i]
		if not hand is Sprite2D or not is_instance_valid(hand):
			continue
		var sprite:Sprite2D = hand as Sprite2D
		var start:Vector2 = starts[i]
		var grip:Vector2 = grips[i] + displacement
		# 角色不下移，但缠住后的手会略微向雾面方向牵拉，配合逐渐上升的遮挡线模拟 3D 下沉。
		if _grab_elapsed > extend_end + HAND_WRAP_SECONDS:
			var pull_t:float = clampf((_grab_elapsed - extend_end - HAND_WRAP_SECONDS) / maxf(PULL_SECONDS,0.001),0.0,1.0)
			var tug:float = minf(float(entry.get("height",80.0)) * 0.20,18.0) * _ease_in_cubic(pull_t)
			grip.y += tug
		var current:Vector2 = start.lerp(grip,extend_ease)
		if _grab_elapsed >= extend_end:
			current = grip
		if retract_t > 0.0:
			current = grip.lerp(start,_ease_in_cubic(retract_t))
		sprite.global_position = current
		sprite.modulate.a = clampf(minf(extend_t * 1.8,1.0) * (1.0 - retract_t),0.0,1.0)
		var tangent:Vector2 = current - start
		if tangent.length_squared() > 0.0001:
			sprite.rotation = tangent.angle() + PI * 0.5

func _force_target_death(target:Node2D) -> void:
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		return
	# 这是死档处决，不走 health=0 setter；否则菜月昴会再次触发死亡回归、猫等角色也可能复活。
	# 仍调用公共死亡报告，保留击杀/录像/统计侧的“死亡”语义，然后在完全沉入雾后释放节点。
	target.set_meta(&"satella_dead_save_forced_death",true)
	# 所有客户端在完全沉没时先把视觉隐藏；真正释放只由该角色 authority 执行。
	# MultiplayerSpawner 会把 authority 的 despawn 同步给其它端。
	if target is CanvasItem:
		(target as CanvasItem).visible = false
	var can_free_here:bool = true
	if multiplayer.has_multiplayer_peer() and target.has_method("is_multiplayer_authority"):
		can_free_here = bool(target.call("is_multiplayer_authority"))
	if not can_free_here:
		return
	if target.has_method("_report_combat_death_once"):
		target.call("_report_combat_death_once")
	target.queue_free()

func _finish_global_grab() -> void:
	if _cinematic_finished:
		return
	_cinematic_finished = true
	for entry:Dictionary in _grab_entries:
		var hands:Array = entry.get("hands",[])
		for hand:Variant in hands:
			if hand is Node and is_instance_valid(hand):
				(hand as Node).queue_free()
	_grab_entries.clear()
	queue_redraw()
	# 死档视觉与 UI 继续保持，但时间只在处决演出期间冻结；演出结束后恢复此前的暂停状态。
	_restore_tree_pause_if_owned()

# ========================================================
# 手臂 / 脚边雾（人物后方绘制）
# ========================================================
func _draw() -> void:
	if not _grab_started or _grab_entries.is_empty():
		return

	# V407：处决绘制严格分层。这个 Node2D 自身 z=-1，所以这里的黑色手臂和脚边局部雾
	# 全部在人物后面；真正压在人物前面的只有 z_as_relative=false / z=97 的手掌 Sprite2D。
	# 旧版用于“下沉遮挡”的超长 BACKGROUND_PURPLE draw_rect 已完全删除，
	# 它就是人物下方会一路伸出屏幕的长矩形色块，也是把人物大面积盖住的主要来源。
	var extend_t:float = clampf((_grab_elapsed - GRAB_START_DELAY) / maxf(HAND_EXTEND_SECONDS,0.001),0.0,1.0)
	var extend_end:float = GRAB_START_DELAY + HAND_EXTEND_SECONDS
	var pull_start:float = extend_end + HAND_WRAP_SECONDS
	var pull_t:float = clampf((_grab_elapsed - pull_start) / maxf(PULL_SECONDS,0.001),0.0,1.0)
	var retract_start:float = pull_start + PULL_SECONDS
	var retract_t:float = clampf((_grab_elapsed - retract_start) / maxf(HAND_RETRACT_SECONDS,0.001),0.0,1.0)

	for entry:Dictionary in _grab_entries:
		var fog_x:float = float(entry.get("fog_center_x",0.0))
		var fog_y:float = float(entry.get("fog_y",0.0))
		var mask_width:float = float(entry.get("mask_width",80.0))
		var phase:float = float(entry.get("phase",0.0))

		# 脚边雾只作为人物后方的环境提示，不再承担遮挡/吞没人物的职责。
		for j:int in range(7):
			var ratio:float = float(j) / 6.0
			var wobble:float = sin(_grab_elapsed * (1.5 + ratio * 0.7) + phase + float(j) * 0.92)
			var wx:float = fog_x + lerpf(-mask_width * 0.42,mask_width * 0.42,ratio) + wobble * 4.0
			var wy:float = fog_y + 5.0 + sin(_grab_elapsed * 1.2 + phase * 0.7 + float(j)) * 2.4
			var radius:float = lerpf(14.0,22.0,0.5 + 0.5 * sin(phase + float(j) * 1.27))
			var fog_color:Color = FOG_BLACK.lerp(FOG_DARK_PURPLE,ratio)
			fog_color.a *= clampf(0.30 + extend_t * 0.22,0.0,0.52)
			draw_circle(to_local(Vector2(wx,wy)),radius,fog_color)

		# 曲线手臂仍保留，但因为父节点 z=-1，它们从人物后方接到前景手掌，不会盖住人物身体。
		var starts:Array = entry.get("starts",[])
		var grips:Array = entry.get("grips",[])
		if starts.size() < HANDS_PER_TARGET or grips.size() < HANDS_PER_TARGET:
			continue
		var displacement:Vector2 = Vector2.ZERO
		if _grab_elapsed >= pull_start:
			var eased_pull:float = _ease_in_cubic(pull_t)
			displacement.y = minf(float(entry.get("height",80.0)) * 0.20,18.0) * eased_pull
		var arm_alpha:float = clampf(extend_t * 1.55,0.0,1.0) * (1.0 - retract_t)
		for i:int in range(HANDS_PER_TARGET):
			var start:Vector2 = starts[i]
			var end:Vector2 = grips[i] + displacement
			var visible_end:Vector2 = start.lerp(end,_ease_out_cubic(extend_t)) if _grab_elapsed < extend_end else end
			if retract_t > 0.0:
				visible_end = end.lerp(start,_ease_in_cubic(retract_t))
			var side:float = -1.0 if i == 0 else (1.0 if i == 2 else 0.35)
			var p1:Vector2 = start + Vector2(side * 24.0,-42.0 - 9.0 * float(i))
			var p2:Vector2 = visible_end + Vector2(-side * 22.0,30.0 + 7.0 * float(i))
			var world_path:PackedVector2Array = _sample_cubic(start,p1,p2,visible_end,ARM_CURVE_SAMPLES)
			var local_path := PackedVector2Array()
			for point:Vector2 in world_path:
				local_path.append(to_local(point))
			if local_path.size() >= 2:
				var arm_color:Color = ARM_COLOR
				arm_color.a *= arm_alpha
				draw_polyline(local_path,arm_color,ARM_WIDTH + float(i) * 1.2,true)

func _sample_cubic(p0:Vector2,p1:Vector2,p2:Vector2,p3:Vector2,samples:int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count:int = maxi(samples,4)
	for i:int in range(count + 1):
		var t:float = float(i) / float(count)
		var inv:float = 1.0 - t
		points.append(
			p0 * (inv * inv * inv)
			+ p1 * (3.0 * inv * inv * t)
			+ p2 * (3.0 * inv * t * t)
			+ p3 * (t * t * t)
		)
	return points

func _estimate_target_bounds_global(target:Node2D) -> Rect2:
	var image_value:Variant = target.get("image")
	if image_value is Node2D and (image_value as Node2D).has_method("get_rect"):
		var visual:Node2D = image_value as Node2D
		var rect_value:Variant = visual.call("get_rect")
		if rect_value is Rect2:
			var rect:Rect2 = rect_value
			var corners:Array[Vector2] = [
				visual.to_global(rect.position),
				visual.to_global(Vector2(rect.end.x,rect.position.y)),
				visual.to_global(rect.end),
				visual.to_global(Vector2(rect.position.x,rect.end.y)),
			]
			var min_x:float = INF
			var max_x:float = -INF
			var min_y:float = INF
			var max_y:float = -INF
			for p:Vector2 in corners:
				min_x = minf(min_x,p.x)
				max_x = maxf(max_x,p.x)
				min_y = minf(min_y,p.y)
				max_y = maxf(max_y,p.y)
			if min_x < INF and max_x > min_x and max_y > min_y:
				return Rect2(Vector2(min_x,min_y),Vector2(max_x - min_x,max_y - min_y))

	var collision_value:Variant = target.get("collision_shape_2d")
	if collision_value is CollisionShape2D:
		var shape_node:CollisionShape2D = collision_value as CollisionShape2D
		var shape:Shape2D = shape_node.shape
		if shape is RectangleShape2D:
			var size:Vector2 = (shape as RectangleShape2D).size * shape_node.global_scale.abs()
			return Rect2(target.global_position - size * 0.5,size)
		if shape is CircleShape2D:
			var diameter:float = (shape as CircleShape2D).radius * 2.0 * maxf(absf(shape_node.global_scale.x),absf(shape_node.global_scale.y))
			var size:Vector2 = Vector2.ONE * diameter
			return Rect2(target.global_position - size * 0.5,size)

	return Rect2(target.global_position - Vector2(34.0,48.0),Vector2(68.0,96.0))

func _ease_out_cubic(t:float) -> float:
	var x:float = clampf(t,0.0,1.0)
	return 1.0 - pow(1.0 - x,3.0)

func _ease_in_cubic(t:float) -> float:
	var x:float = clampf(t,0.0,1.0)
	return x * x * x
