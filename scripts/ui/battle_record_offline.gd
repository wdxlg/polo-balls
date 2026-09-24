extends RefCounted
## Own only session-level clocks/UI. The World and every live node remain in place.
## Reuse an already-rendered recording frame for a small, wall-clock-throttled player preview.
const PREVIEW_SIZE:Vector2i = Vector2i(360, 640)
const PREVIEW_INTERVAL_USEC:int = 500000
var error:String = ""
var owner:Node
var _saved:Dictionary = {}
var _panels:Array = []
var _resumed:bool = false
var _preview_viewport:SubViewport
var _preview_image:TextureRect
var _preview_dim:ColorRect
var _preview_last_frame:int = -1
var _preview_last_wall_usec:int = 0
var _preview_updates:int = 0

func begin(recorder:Node) -> bool:
	owner = recorder
	if not Engine.get_write_movie_path().is_empty() or bool(AudioServer.call("is_offline_audio")) or int(Engine.call("get_recording_fixed_fps")) > 0:
		error = "已有引擎级影片/离线音频任务，不能同时启动另一个。"
		return false
	var tree:SceneTree = owner.get_tree()
	if tree.paused and not Game.now_stop_state:
		error = "请等待恢复倒计时结束，再从当前状态开始离线计算。"
		return false
	_saved = {"fixed":Engine.call("get_recording_fixed_fps"), "base_scale":Game.get_base_game_time_scale(), "max_fps":Engine.max_fps,
		"vsync":DisplayServer.window_get_vsync_mode(), "low_cpu":OS.low_processor_usage_mode,
		"mask":owner.get_viewport().canvas_cull_mask, "paused":tree.paused,
		"stopped":Game.now_stop_state, "stop_bg":Game.stop_background.visible,
		"stop_text":Game.stop_text.visible, "speed_text":Game.speed_text.visible,
		"speed_slider":Game.speed_slider.visible}
	# Freeze immediately, before encoder setup. No rematch/snapshot reconstruction.
	AudioServer.call("set_offline_audio", true)
	tree.paused = true
	# Export at normal base speed, retaining active skill-specific time overrides.
	if not is_equal_approx(Game.get_base_game_time_scale(),1.0): Game.set_speed(10.0,false)
	Engine.call("set_recording_fixed_fps", 60)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	OS.low_processor_usage_mode = false
	var control:Node = owner._world().control
	for path:String in ["Team", "Map", "Game_Setting", "MultiPlayer"]:
		var panel:CanvasItem = control.get_node_or_null(path)
		if panel != null:
			_panels.append({"node":panel, "visible":panel.visible})
	return true

func hide_preview() -> void:
	for entry:Dictionary in _panels: entry.node.hide()
	# Keep the expensive World out of the player viewport. The recording viewports
	# retain their own masks and render every video frame independently.
	owner.get_viewport().canvas_cull_mask = owner.CAPTURE_MASK_BIT
	_show_battle_preview()

func _show_battle_preview() -> void:
	var source:Viewport = owner._capture_viewport as Viewport
	var backdrop:ColorRect = owner._overlay_backdrop as ColorRect
	if not is_instance_valid(source) or not is_instance_valid(backdrop): return
	var progress:Label = owner._overlay_label as Label
	if is_instance_valid(progress):
		progress.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
		progress.add_theme_constant_override("outline_size", 8)
	# This viewport contains only a single textured quad, never a third World.
	# A cached 1/3-size GPU blit is much cheaper than re-rendering combat or
	# downloading/upscaling a full-resolution frame on the CPU every step.
	_preview_viewport = SubViewport.new()
	_preview_viewport.name = "BattleRecordPreviewCache"
	_preview_viewport.disable_3d = true
	_preview_viewport.gui_disable_input = true
	_preview_viewport.size = PREVIEW_SIZE
	_preview_viewport.world_2d = World2D.new()
	_preview_viewport.canvas_cull_mask = 1
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	owner.add_child(_preview_viewport)
	var source_image := TextureRect.new()
	source_image.name = "RecordedFrame"
	source_image.texture = source.get_texture() # Resolved sRGB frame, after vignette.
	source_image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	source_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	source_image.stretch_mode = TextureRect.STRETCH_SCALE
	source_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_viewport.add_child(source_image)
	source_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_preview_image = TextureRect.new()
	_preview_image.name = "BattleFrame"
	_preview_image.texture = _preview_viewport.get_texture()
	_preview_image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_preview_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_preview_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_image.visibility_layer = owner.CAPTURE_MASK_BIT
	backdrop.add_child(_preview_image)
	_preview_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.move_child(_preview_image, 0)
	_preview_dim = ColorRect.new()
	_preview_dim.name = "PreviewTextContrast"
	_preview_dim.color = Color(0.0, 0.0, 0.0, 0.26)
	_preview_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_dim.visibility_layer = owner.CAPTURE_MASK_BIT
	backdrop.add_child(_preview_dim)
	_preview_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.move_child(_preview_dim, 1) # Progress and abort button stay on top.
	_preview_last_frame = -1
	_preview_last_wall_usec = 0
	_preview_updates = 0
	RenderingServer.frame_post_draw.connect(_on_preview_frame)

func _on_preview_frame() -> void:
	if _saved.is_empty() or not is_instance_valid(owner) or not is_instance_valid(_preview_viewport): return
	if not owner.is_recording() or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED: return
	var frame:int = owner._frame_index
	if frame <= 0 or frame == _preview_last_frame: return
	var now:int = int(Time.call("get_wall_ticks_usec"))
	if _preview_last_wall_usec > 0 and now - _preview_last_wall_usec < PREVIEW_INTERVAL_USEC: return
	# UPDATE_ONCE freezes the last battle frame between refreshes. This never
	# enters either encoder path and does not cause an additional video readback.
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_preview_last_wall_usec = now
	_preview_last_frame = frame
	_preview_updates += 1

func _clear_battle_preview() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_preview_frame):
		RenderingServer.frame_post_draw.disconnect(_on_preview_frame)
	if is_instance_valid(_preview_image):
		_preview_image.hide()
		_preview_image.texture = null
		_preview_image.queue_free()
	if is_instance_valid(_preview_dim):
		_preview_dim.hide()
		_preview_dim.queue_free()
	if is_instance_valid(_preview_viewport): _preview_viewport.queue_free()
	_preview_image = null
	_preview_dim = null
	_preview_viewport = null

func resume_current_world() -> void:
	_resumed = true
	# No three/two/one countdown and no skill/status/timer restart.
	if Game.Stop_Override_Tween: Game.Stop_Override_Tween.kill()
	Game.now_stop_state = false
	Game.stop_background.hide()
	Game.stop_text.hide()
	Game.speed_text.hide()
	Game.speed_slider.hide()
	owner.get_tree().paused = false
	Audios.set_gameplay_paused(false)

func finish(keep_result:bool = true) -> void:
	if _saved.is_empty(): return
	_clear_battle_preview() # Before the recording source viewport is released.
	if _resumed and keep_result: Game.stop_game(false)
	Engine.call("set_recording_fixed_fps", _saved.fixed)
	if not is_equal_approx(Game.get_base_game_time_scale(),float(_saved.base_scale)):
		Game.set_speed(float(_saved.base_scale)+9.0 if float(_saved.base_scale)>1.0 else float(_saved.base_scale)*10.0,false)
	Engine.max_fps = _saved.max_fps
	DisplayServer.window_set_vsync_mode(_saved.vsync)
	OS.low_processor_usage_mode = _saved.low_cpu
	owner.get_viewport().canvas_cull_mask = _saved.mask
	# Keep the calculated current state frozen while encoding finishes. Never reset/replay.
	# The user may continue from here with Esc; do not spend CPU running an unrecorded battle.
	if not (_resumed and keep_result):
		owner.get_tree().paused = _saved.paused
		Game.now_stop_state = _saved.stopped
		Game.stop_background.visible = _saved.stop_bg
		Game.stop_text.visible = _saved.stop_text
		Game.speed_text.visible = _saved.speed_text
		Game.speed_slider.visible = _saved.speed_slider
		Audios.set_gameplay_paused(_saved.paused or _saved.stopped)
	# Do not reopen setup/map panels; remain at the calculated battle state.
	AudioServer.call("set_offline_audio", false)
	_saved.clear()
	_panels.clear()
