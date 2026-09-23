extends RefCounted
## Own only session-level clocks/UI. The World and every live node remain in place.
var error:String = ""
var owner:Node
var _saved:Dictionary = {}
var _panels:Array = []
var _resumed:bool = false

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
	# One cheap opaque progress panel in the player window, not a third battlefield.
	# The recorder's offscreen viewports have independent masks and stay visible.
	owner.get_viewport().canvas_cull_mask = owner.CAPTURE_MASK_BIT

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
