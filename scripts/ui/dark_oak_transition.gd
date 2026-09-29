extends CanvasLayer
## Root-owned true 3D hinged doors with native UI audio; no gameplay mutation.
## A root-owned service survives current_scene replacement. Only commit behind closed doors.
signal opening_half
signal covered
signal finished(completed:bool)
const TOP:Texture2D = preload("res://assets/ui/dark_oak_transition/dark_oak_door_top.png")
const BOTTOM:Texture2D = preload("res://assets/ui/dark_oak_transition/dark_oak_door_bottom.png")
const DOORS_3D = preload("res://scripts/ui/dark_oak_doors_3d.gd")
const OPEN_SOUND:AudioStream = preload("res://assets/ui/dark_oak_transition/open.ogg")
const CLOSE_SOUND:AudioStream = preload("res://assets/ui/dark_oak_transition/close.ogg")
const OVERLAY_LAYER:int = 4096 # Above game HUD, embedded windows (1024), draft UI (1500).
enum Phase { IDLE, CLOSING, COVERED, OPENING }
var phase:Phase = Phase.IDLE
var close_seconds:float = 0.275 # Motion only: doubled closing speed (2026-09-27).
var hold_seconds:float = 0.20
var open_seconds:float = 0.30  # Motion only: doubled opening speed (2026-09-27).
var progress:float = 0.0
var change_applied:bool = false
var _elapsed:float = 0.0
var _last_usec:int = 0
var _generation:int = 0
var _committed:bool = false
var _change:Callable
var _half_callback:Callable
var _half_sent:bool = false
const XP_BACKGROUND:Texture2D = preload("res://Images/UI/minecraft_xp/experience_bar_background.png")
const XP_PROGRESS:Texture2D = preload("res://Images/UI/minecraft_xp/experience_bar_progress.png")
var loading_progress:float = -1.0
var loading_slide:float = 0.0
var _loading_canvas:Control
var _focus:WeakRef
var shield:Control
var viewport_3d:SubViewport
var rig:Node3D
var picture:TextureRect
var open_audio:AudioStreamPlayer
var close_audio:AudioStreamPlayer
var audio_events:Array[String] = []

static func ensure(tree:SceneTree) -> CanvasLayer:
	var existing:Node = tree.root.get_node_or_null("DarkOakDoorTransition")
	if existing != null: return existing as CanvasLayer
	var script:Script = load("res://scripts/ui/dark_oak_transition.gd")
	var overlay:CanvasLayer = script.new()
	overlay.name = "DarkOakDoorTransition"
	tree.root.add_child(overlay)
	return overlay

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = OVERLAY_LAYER
	follow_viewport_enabled = false
	shield = Control.new()
	shield.name = "DoorInputShield"
	shield.mouse_filter = Control.MOUSE_FILTER_STOP
	shield.focus_mode = Control.FOCUS_ALL
	add_child(shield)
	viewport_3d=SubViewport.new()
	viewport_3d.name="DoorWorld3D"
	viewport_3d.own_world_3d=true
	viewport_3d.transparent_bg=true
	viewport_3d.handle_input_locally=false
	viewport_3d.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(viewport_3d)
	rig=DOORS_3D.new()
	viewport_3d.add_child(rig)
	picture=TextureRect.new()
	picture.name="PerspectiveDoors"
	picture.texture=viewport_3d.get_texture()
	picture.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
	shield.add_child(picture)
	_loading_canvas=Control.new()
	_loading_canvas.name="RoundLoadingExperience"
	_loading_canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_loading_canvas.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	_loading_canvas.draw.connect(_draw_loading)
	shield.add_child(_loading_canvas)
	# Existing Audios auto-routes UI players and compensates the shared audio clock.
	# Gameplay mc_native_audio.queue_stream intentionally suppresses paused audio;
	# it is not the correct service for a pause-menu transition.
	open_audio=_audio_player("OpenDoorSound",OPEN_SOUND)
	close_audio=_audio_player("CloseDoorSound",CLOSE_SOUND)
	visible = false
	set_process(false)
	set_process_input(false)
	get_viewport().size_changed.connect(_layout)
	_layout()

func is_busy() -> bool:
	return phase != Phase.IDLE

func play(change:Callable = Callable(),half_open:Callable = Callable()) -> bool:
	if not is_inside_tree() or is_busy(): return false
	_generation += 1
	_change = change
	_half_callback=half_open
	_half_sent=false
	loading_progress=-1.0
	loading_slide=0.0
	change_applied = false
	_committed = false
	_elapsed = 0.0
	_last_usec = Time.get_ticks_usec()
	progress = 0.0
	phase = Phase.CLOSING
	var focused:Control = get_viewport().gui_get_focus_owner()
	_focus = weakref(focused) if focused != null else null
	visible = true
	viewport_3d.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	open_audio.stop();close_audio.stop()
	audio_events.clear()
	_raise_input_order()
	shield.grab_focus()
	set_process(true)
	set_process_input(true)
	_layout()
	return true

func _input(_event:InputEvent) -> void:
	if is_busy(): get_viewport().set_input_as_handled()

func _process(_delta:float) -> void:
	# Wall-clock UI time: settings may be paused or gameplay time_scale may be zero.
	_raise_input_order()
	var now:int = Time.get_ticks_usec()
	var ui_delta:float=minf(float(now-_last_usec)/1000000.0,0.1)
	_elapsed += ui_delta
	loading_slide=move_toward(loading_slide,1.0 if loading_progress>=0.0 else 0.0,ui_delta/0.25)
	_loading_canvas.queue_redraw()
	_last_usec = now
	if phase == Phase.CLOSING:
		progress = smoothstep(0.0,1.0,minf(_elapsed/maxf(close_seconds,0.001),1.0))
		if progress>=1.0:
			phase = Phase.COVERED
			close_audio.play()
			audio_events.append("close")
			_elapsed = 0.0
			_commit_when_drawn(_generation)
	elif phase == Phase.COVERED:
		if _committed and _elapsed>=hold_seconds:
			phase = Phase.OPENING
			open_audio.play()
			audio_events.append("open")
			_elapsed = 0.0
	elif phase == Phase.OPENING:
		progress = 1.0-smoothstep(0.0,1.0,minf(_elapsed/maxf(open_seconds,0.001),1.0))
		if progress<=0.5 and not _half_sent:
			_half_sent=true
			var generation:int=_generation
			opening_half.emit()
			if generation!=_generation or phase!=Phase.OPENING: return
			if _half_callback.is_valid(): _half_callback.call()
			if generation!=_generation or phase!=Phase.OPENING: return
		if progress<=0.0:
			_finish(true)
	_layout()

func _commit_when_drawn(generation:int) -> void:
	# Do not run a costly scene replacement before a fully opaque frame has appeared.
	if DisplayServer.get_name()=="headless": await get_tree().process_frame
	else: await RenderingServer.frame_post_draw
	if generation!=_generation or phase!=Phase.COVERED: return
	covered.emit()
	if generation!=_generation or phase!=Phase.COVERED: return
	var change:Callable = _change
	_change = Callable()
	if change.is_valid():
		await change.call()
		if generation!=_generation or phase!=Phase.COVERED: return
		change_applied = true
	# Allow deferred scene replacement and its first render to settle while still covered.
	await get_tree().process_frame
	if generation!=_generation or phase!=Phase.COVERED: return
	if DisplayServer.get_name()!="headless": await RenderingServer.frame_post_draw
	if generation!=_generation or phase!=Phase.COVERED: return
	_committed = true
	_elapsed = 0.0
	_last_usec = Time.get_ticks_usec()

func set_loading_progress(value:float) -> void:
	loading_progress=clampf(value,0.0,1.0) if value>=0.0 else -1.0
func loading_rect() -> Rect2:
	var screen:Vector2=get_viewport().get_visible_rect().size
	var factor:float=minf(screen.x/1080.0,screen.y/720.0)
	var bar_size:Vector2=Vector2(728.0,20.0)*factor
	var t:float=1.0-pow(1.0-loading_slide,4.0)
	return Rect2(Vector2((screen.x-bar_size.x)*0.5,lerpf(screen.y+bar_size.y,screen.y-80.0*factor,t)),bar_size)
func _draw_loading() -> void:
	if loading_slide<=0.0: return
	var rect:Rect2=loading_rect()
	_loading_canvas.draw_texture_rect(XP_BACKGROUND,rect,false)
	# Leaving the screen keeps the completed bar full; -1 only controls its slide.
	var amount:float=loading_progress if loading_progress>=0.0 else 1.0
	if amount>0.0:
		_loading_canvas.draw_texture_rect_region(XP_PROGRESS,Rect2(rect.position,rect.size*Vector2(amount,1.0)),Rect2(Vector2.ZERO,XP_PROGRESS.get_size()*Vector2(amount,1.0)))

func _audio_player(label:String,stream:AudioStream) -> AudioStreamPlayer:
	var player:=AudioStreamPlayer.new()
	player.name=label
	player.stream=stream
	player.bus=&"UI"
	player.volume_db=0.0
	player.process_mode=Node.PROCESS_MODE_ALWAYS
	add_child(player)
	return player

func _raise_input_order() -> void:
	var parent:Node=get_parent()
	if parent!=null and get_index()!=parent.get_child_count()-1: parent.move_child(self,parent.get_child_count()-1)

func _layout() -> void:
	if not is_instance_valid(shield): return
	var size:Vector2=get_viewport().get_visible_rect().size
	shield.position=Vector2.ZERO
	shield.size=size
	picture.position=Vector2.ZERO
	picture.size=size
	var pixels:=Vector2i(maxi(1,ceili(size.x)),maxi(1,ceili(size.y)))
	if viewport_3d.size!=pixels:viewport_3d.size=pixels
	rig.configure(size)
	rig.set_progress(progress)

func cancel() -> void:
	if not is_busy(): return
	_generation += 1
	_finish(false)

func _finish(completed:bool) -> void:
	phase = Phase.IDLE
	progress = 0.0
	_half_callback=Callable()
	loading_progress=-1.0
	loading_slide=0.0
	_change = Callable()
	visible = false
	viewport_3d.render_target_update_mode=SubViewport.UPDATE_DISABLED
	if not completed:
		open_audio.stop();close_audio.stop()
	set_process(false)
	set_process_input(false)
	shield.release_focus()
	var focused:Control = _focus.get_ref() as Control if _focus != null else null
	_focus = null
	if is_instance_valid(focused) and focused.is_inside_tree() and focused.is_visible_in_tree(): focused.call_deferred("grab_focus")
	finished.emit(completed)

func _exit_tree() -> void:
	_generation += 1
	_change = Callable()
	if is_busy(): finished.emit(false)
	phase = Phase.IDLE
