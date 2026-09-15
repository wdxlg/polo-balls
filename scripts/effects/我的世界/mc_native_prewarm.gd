extends Node
## Resources only: no character instantiation, _ready(), combat or random draws.
const CHARACTERS:Array[String] = ["骷髅","女巫","烈焰人","苦力怕","蠹虫","末影人","唤魔者","潜影贝"]
var scenes:Dictionary = {}
var finished:Dictionary = {}
var failed:Dictionary = {}
var _paths:Dictionary = {}
var _seen:Dictionary = {}
var _jobs:Array = []
var _view:SubViewport
var _polygon:Polygon2D
var _sprite:Sprite2D
var _active:String = ""
var _wait_frames:int = 0
var _visual:CanvasItem
var _status:Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_view = SubViewport.new()
	_view.size = Vector2i(64,64)
	_view.disable_3d = true
	# Pipeline variants must match the real HDR/MSAA render target.
	_view.use_hdr_2d = get_viewport().use_hdr_2d
	_view.msaa_2d = get_viewport().msaa_2d
	_view.canvas_item_default_texture_filter = get_viewport().canvas_item_default_texture_filter
	_view.transparent_bg = true
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_view)
	_sprite = Sprite2D.new()
	_sprite.position = Vector2(32,32)
	_sprite.scale = Vector2.ONE*0.15
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.add_child(_sprite)
	_polygon = Polygon2D.new()
	_polygon.polygon = PackedVector2Array([Vector2(24,24),Vector2(40,24),Vector2(40,40),Vector2(24,40)])
	_polygon.antialiased = true
	_view.add_child(_polygon)
	var layer := CanvasLayer.new()
	layer.layer = 110
	add_child(layer)
	_status = Label.new()
	_status.position = Vector2(16,76)
	_status.add_theme_color_override("font_color",Color(0.95,0.86,0.58))
	_status.add_theme_color_override("font_shadow_color",Color.BLACK)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.hide()
	layer.add_child(_status)
	call_deferred("_begin")

func _begin() -> void:
	for character:String in CHARACTERS:
		var path:String = "res://scenes/characters/我的世界/"+character+".tscn"
		_paths[character] = path
		var error:Error = ResourceLoader.load_threaded_request(path,"PackedScene")
		if error != OK:
			failed[character] = true
			push_warning("Minecraft background preparation failed: "+character)

func handles(character:String) -> bool: return character in CHARACTERS
func is_ready(character:String) -> bool: return finished.has(character)
func has_failed(character:String) -> bool: return failed.has(character)

func _collect(value:Variant) -> void:
	if value is Resource:
		var id:int = value.get_instance_id()
		if _seen.has(id): return
		_seen[id] = true
	if value is Texture2D:
		_jobs.append(value)
	elif value is Material:
		_jobs.append(value)
	elif value is SpriteFrames:
		for clip:StringName in value.get_animation_names():
			if value.get_frame_count(clip)>0: _collect(value.get_frame_texture(clip,0))
	elif value is PackedScene:
		var state:SceneState = value.get_state()
		for i:int in range(state.get_node_count()):
			_collect(state.get_node_instance(i))
			# Only built-in drawing nodes, with no scripts or gameplay initialization.
			var type:String = state.get_node_type(i)
			if type in ["Sprite2D","AnimatedSprite2D","Label","TextureRect","TextureProgressBar","ProgressBar","Polygon2D","Line2D"]:
				var visual:CanvasItem = ClassDB.instantiate(type)
				for j:int in range(state.get_node_property_count(i)):
					var property:String = state.get_node_property_name(i,j)
					if property in ["script","owner","process_mode"]: continue
					visual.set(property,state.get_node_property_value(i,j))
				visual.process_mode = Node.PROCESS_MODE_DISABLED
				visual.position = Vector2(24,24)
				visual.scale = Vector2.ONE*0.15
				visual.visible = true
				if visual is Label:
					Health_bar.prepare_minecraft_number_label(visual)
					visual.text = "0123456789/INF+-"
				_jobs.append(visual)
			for j:int in range(state.get_node_property_count(i)):
				_collect(state.get_node_property_value(i,j))
	elif value is Script:
		# Native animation constants contain frame resources, not gameplay actors.
		for key:Variant in value.get_script_constant_map():
			var item:Variant = value.get_script_constant_map()[key]
			if item is Texture2D or item is SpriteFrames or item is Material: _collect(item)
			elif item is Script and "mc_native" in item.resource_path: _collect(item)
			elif str(key) == "FRAMES" and item is Dictionary:
				for frames:Variant in item.values(): _collect(frames)

func _process(_delta:float) -> void:
	var selected:String = str(get_parent().get("now_choose_char")) if get_parent().get("now_choose_char") != null else ""
	_status.visible = handles(selected) and not is_ready(selected) and not has_failed(selected)
	_status.text = "正在准备 "+selected+" 动画…"
	if _wait_frames>0:
		_wait_frames -= 1
		return
	if is_instance_valid(_visual):
		_visual.queue_free()
		_visual = null
	if not _jobs.is_empty():
		# One small image per frame. Never instantiate a real mob to warm rendering.
		var job:Variant = _jobs.pop_front()
		if job is Texture2D:
			ball.prewarm_after_image_texture(job)
			_sprite.texture = job
		elif job is Material:
			_sprite.material = job
			_polygon.material = job
		elif job is CanvasItem:
			_visual = job
			_view.add_child(_visual)
		_view.render_target_update_mode = SubViewport.UPDATE_ONCE
		_wait_frames = 1
		return
	if not _active.is_empty():
		finished[_active] = true
		_active = ""
	if not _paths.is_empty() and finished.size()+failed.size() == _paths.size():
		_status.hide()
		_sprite.texture = null
		set_process(false)
		return
	for character:Variant in _paths:
		if finished.has(character) or failed.has(character): continue
		var status:int = ResourceLoader.load_threaded_get_status(_paths[character])
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			failed[character] = true
			push_warning("Minecraft background preparation failed: "+str(character))
		elif status == ResourceLoader.THREAD_LOAD_LOADED:
			# get() is nonblocking ONLY after LOADED; keep strong refs for later placements.
			var packed:PackedScene = ResourceLoader.load_threaded_get(_paths[character]) as PackedScene
			scenes[character] = packed
			_active = character
			var base:PackedScene = load("res://scenes/ball.tscn")
			_collect(base)
			_collect(packed)
			return

func _exit_tree() -> void:
	# Undrawn stand-ins have not entered the tree yet, so free them explicitly.
	for job:Variant in _jobs:
		if job is Node and is_instance_valid(job): job.free()
	_jobs.clear()
