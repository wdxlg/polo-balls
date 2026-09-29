extends Control
const FRAME:Texture2D = preload("res://Images/UI/rotation_frames/item_frame.png")
const CROSS:Texture2D = preload("res://Images/UI/rotation_frames/cross.png")
const CHECK:Texture2D = preload("res://Images/UI/rotation_frames/check.png")
var world:Node
var portraits:RefCounted
var side:String = "left"
var roster:Array = []
var results:Dictionary = {}
var active_id:int = -1
var cell:float = 16.0
var bar_height:float = 1.6
var first_visible:int = 0
var scroll_pixels:float = 0.0
var scroll_tween:Tween
var _signature:String = ""
var _textures:Dictionary = {}

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func reset_scroll() -> void:
	if scroll_tween != null and scroll_tween.is_valid(): scroll_tween.kill()
	first_visible = 0
	scroll_pixels = 0.0
	_signature = ""
	queue_redraw()

func configure(records:Array,statuses:Dictionary,current:int,block:float,bar:float) -> void:
	roster = records
	results = statuses
	active_id = current
	cell = block
	bar_height = bar
	var capacity:int = maxi(1,floori(size.x / cell))
	var active_index:int = -1
	for i:int in range(roster.size()):
		if int(roster[i].get("id",-1)) == active_id:
			active_index = i
			break
	# Keep the first page until its last fighter ends. Subsequent fighters move
	# into that same rightmost slot; do not center/follow every active fighter.
	var wanted:int = first_visible
	if roster.size() * cell <= size.x: wanted = 0
	elif active_index >= 0: wanted = maxi(0,active_index - capacity + 1)
	wanted = clampi(wanted,0,maxi(0,roster.size()-capacity))
	if wanted != first_visible:
		first_visible = wanted
		if scroll_tween != null and scroll_tween.is_valid(): scroll_tween.kill()
		scroll_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		scroll_tween.tween_property(self,"scroll_pixels",float(wanted)*cell,0.24)
	elif scroll_tween == null or not scroll_tween.is_running():
		scroll_pixels = float(wanted)*cell
	var signature:String = str([records,statuses,current,block,size])
	if signature != _signature:
		_signature = signature
		queue_redraw()

func _process(_delta:float) -> void:
	# Only two rows redraw, and only visible slots are painted / loaded.
	if is_visible_in_tree() and (active_id >= 0 or (scroll_tween != null and scroll_tween.is_running())):
		queue_redraw()

func content_start() -> float:
	return maxf(0.0,(size.x - float(roster.size())*cell)*0.5) - scroll_pixels

func frame_rect(index:int) -> Rect2:
	var y:float = 0.0 if side == "left" else bar_height
	return Rect2(Vector2(content_start()+float(index)*cell+cell*0.05,y+cell*0.05),Vector2.ONE*cell*0.9)

func _draw() -> void:
	var blue:bool = side == "left"
	var color:Color = Color("418cff") if blue else Color("ef4f50")
	var bar_y:float = cell if blue else 0.0
	draw_rect(Rect2(0,bar_y,size.x,bar_height),color.darkened(0.35))
	draw_rect(Rect2(0,bar_y,size.x,maxf(bar_height*0.55,0.5)),color)
	var first:int = maxi(0,floori(-content_start()/cell))
	var last:int = mini(roster.size(),first+ceili(size.x/cell)+2)
	for i:int in range(first,last):
		var record:Dictionary = roster[i]
		var id:int = int(record.get("id",-1))
		var box:Rect2 = frame_rect(i)
		var state:String = str(results.get(id,"waiting"))
		var tint:Color = Color(0.38,0.38,0.38,1.0) if state == "dead" else Color.WHITE
		if state == "retired": tint = Color(0.72,0.72,0.72,1.0)
		draw_texture_rect(FRAME,box,false,tint)
		var key:String = str(record.get("scene_path",""))+":"+str(record.get("char",""))
		if not _textures.has(key):
			var picture:Texture2D = portraits.resolve(world,record)
			if picture != null: _textures[key] = picture
		var texture:Texture2D = _textures.get(key)
		if texture != null:
			var area:Rect2 = box.grow(-box.size.x*0.15)
			var ts:Vector2 = texture.get_size()
			var fitted:Vector2 = ts * minf(area.size.x/maxf(ts.x,1.0),area.size.y/maxf(ts.y,1.0))
			draw_texture_rect(texture,Rect2(area.get_center()-fitted*0.5,fitted),false,tint)
		if id == active_id and state not in ["dead","won"]:
			var pulse:float = 0.7 + 0.3*sin(float(Time.get_ticks_msec())*0.004)
			draw_rect(box.grow(cell*0.025),Color(1.0,0.78,0.08,0.26*pulse),false,maxf(cell*0.05,0.6))
			draw_rect(box,Color(1.0,0.9,0.24,1.0),false,maxf(cell*0.035,0.5))
		if state in ["dead","won"]:
			var mark:Texture2D = CROSS if state == "dead" else CHECK
			var extent:float = box.size.x*0.60
			var mark_size:Vector2 = mark.get_size()
			mark_size *= extent/maxf(mark_size.x,mark_size.y)
			var mark_rect:Rect2 = Rect2(box.get_center()-mark_size*0.5,mark_size)
			draw_texture_rect(mark,Rect2(mark_rect.position+Vector2.ONE*cell*0.025,mark_rect.size),false,Color(0,0,0,0.85))
			draw_texture_rect(mark,mark_rect,false)

func _get_tooltip(at_position:Vector2) -> String:
	var index:int = floori((at_position.x-content_start())/cell)
	if index < 0 or index >= roster.size(): return ""
	var record:Dictionary = roster[index]
	return str(index+1)+". "+Game.t(str(record.get("char",""))).replace("_"," ")

func _gui_input(event:InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT: return
	if not world.is_multiplayer_authority() or world._rotation_transitioning: return
	var index:int = floori((event.position.x-content_start())/cell)
	if index < 0 or index >= roster.size(): return
	var id:int = int(roster[index].get("id",-1))
	if str(results.get(id,"waiting")) in ["dead","retired","won"]: return
	if world.delete_rotation_queue_setup_id(id,side): accept_event()
