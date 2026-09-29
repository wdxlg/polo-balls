extends Control
## Cosmetic reel only. The authority's chosen result is the exact landing card.
signal cell_passed
var _last_cell:int = 0
const STEP:float = 100.0
const LANDING:int = 18
var landed:bool = true
var confirmed_name:String = ""
var _cards:Array[Dictionary] = []
var _start_tick:int = 0
var _duration:float = 0.6
var _distance:float = 0.0
var _target:Dictionary = {}
var _chrome:Control
var _confirm_age:float = 1.0
var _tick:int = 0
var _clock:float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	for index:int in range(-3,LANDING+4):
		var card := Control.new()
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.size = Vector2(90,116)
		var portrait := TextureRect.new()
		portrait.position = Vector2(9,8)
		portrait.size = Vector2(72,78)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(portrait)
		var unknown := Label.new()
		unknown.position = Vector2(0,8)
		unknown.size = Vector2(90,78)
		unknown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		unknown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		unknown.add_theme_font_size_override("font_size",36)
		unknown.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(unknown)
		var title := Label.new()
		title.position = Vector2(0,88)
		title.size = Vector2(90,24)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.add_theme_font_size_override("font_size",14)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(title)
		add_child(card)
		_cards.append({"index":index,"card":card,"portrait":portrait,"unknown":unknown,"title":title})
	_chrome = Control.new()
	_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.draw.connect(_draw_chrome)
	add_child(_chrome)
	_tick = Time.get_ticks_msec()
	visible = false

func start_roll(candidates:Array[Dictionary],target:Dictionary,seconds:float,sequence:int) -> void:
	visible = true
	_target = target
	_duration = maxf(0.001,seconds)
	confirmed_name = ""
	_last_cell = 0
	_confirm_age = 1.0
	landed = false
	for cell:Dictionary in _cards:
		var index:int = cell.index
		var item:Dictionary = target
		if not candidates.is_empty(): item = candidates[posmod(index+sequence*3,candidates.size())]
		if index==LANDING: item = target
		_set_card(cell,item)
	_start_tick = Time.get_ticks_msec()
	_advance(0.0)

func _set_card(cell:Dictionary,item:Dictionary) -> void:
	var texture:Texture2D = item.get("texture")
	cell.portrait.texture = texture
	cell.unknown.visible = texture==null
	cell.unknown.text = str(item.get("name","?")).left(1)
	cell.title.text = str(item.get("name","?"))

func _advance(fraction:float) -> void:
	var progress:float = clampf(fraction,0.0,1.0)
	# Fast continuous scroll, then decelerate to the center marker without rerolling.
	_distance = LANDING*STEP*(1.0-pow(1.0-progress,3.0))
	for cell:Dictionary in _cards:
		var relative:float = int(cell.index)*STEP-_distance
		cell.card.position = Vector2(size.x*0.5-45+relative,8)
		cell.card.modulate.a = clampf(1.0-absf(relative)/360.0,0.18,1.0)
	landed = progress>=1.0
	var current_cell:int = int(floorf((_distance+STEP*0.5)/STEP))
	if current_cell!=_last_cell and not landed: cell_passed.emit()
	_last_cell = current_cell
	_update_card_depth()
	_chrome.queue_redraw()
	queue_redraw()

func confirm_result(display_name:String,texture:Texture2D) -> void:
	_confirm_age = 0.0
	confirmed_name = display_name
	_target = {"name":display_name,"texture":texture}
	for cell:Dictionary in _cards:
		if int(cell.index)==LANDING: _set_card(cell,_target)
	_advance(1.0)

func _update_card_depth() -> void:
	for cell:Dictionary in _cards:
		var relative:float = int(cell.index)*STEP-_distance
		var proximity:float = clampf(1.0-absf(relative)/240.0,0,1)
		var pop:float = 0.0
		if int(cell.index)==LANDING and not confirmed_name.is_empty():
			pop = sin(clampf(_confirm_age/0.30,0,1)*PI)*0.09
		cell.card.pivot_offset = Vector2(45,58)
		cell.card.scale = Vector2.ONE*(0.82+proximity*0.18+pop)
		cell.card.position.y = 8+(1-proximity)*8
		cell.card.modulate.a = 0.25+proximity*0.75

func _process(_delta:float) -> void:
	var tick:int = Time.get_ticks_msec()
	var elapsed:float = clampf(float(tick-_tick)/1000.0,0,0.1)
	_tick = tick
	_clock += elapsed
	_confirm_age = minf(1.0,_confirm_age+elapsed)
	if not visible: return
	if not landed: _advance(float(tick-_start_tick)/1000.0/_duration)
	else: _update_card_depth()
	queue_redraw()
	_chrome.queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("0b1011"))
	draw_rect(Rect2(Vector2.ZERO,size),Color("586451"),false,2)
	var center_x:float = size.x*0.5
	draw_rect(Rect2(center_x-48,5,96,size.y-10),Color("24332c"))
	if not landed:
		for index:int in range(12):
			var x:float = fposmod(index*53-_distance*0.35,size.x)
			draw_line(Vector2(x,size.y-4),Vector2(minf(x+16,size.x),size.y-4),Color(0.55,0.74,0.64,0.2),1)

func _draw_chrome() -> void:
	var center_x:float = size.x*0.5
	var selected:bool = not confirmed_name.is_empty()
	var color := Color("e5d39b") if selected else Color("9bb9ac")
	var pulse:float = 0.4+0.12*sin(_clock*4)
	var flash:float = maxf(0.0,1.0-_confirm_age/0.42) if selected else 0.0
	var frame := Rect2(center_x-48,5,96,size.y-10)
	for index:int in range(3,0,-1):
		_chrome.draw_rect(frame.grow(index*2),Color(color,(pulse+flash)*0.075),false,2)
	_chrome.draw_rect(frame,color,false,2)
	# Corner brackets and a tiny floating center pointer remain above the portraits.
	for corner:Vector2 in [frame.position,Vector2(frame.end.x,frame.position.y),frame.end,Vector2(frame.position.x,frame.end.y)]:
		var direction:Vector2 = (frame.get_center()-corner).sign()
		_chrome.draw_line(corner,corner+Vector2(direction.x*10,0),color,3)
		_chrome.draw_line(corner,corner+Vector2(0,direction.y*10),color,3)
	var pointer_y:float = 1.0 if selected else 1.0+sin(_clock*5)*1.5
	_chrome.draw_colored_polygon(PackedVector2Array([Vector2(center_x-5,pointer_y),Vector2(center_x+5,pointer_y),Vector2(center_x,pointer_y+6)]),color)
	if flash>0:
		_chrome.draw_rect(frame,Color(color,flash*0.10))
		var shine_x:float = frame.position.x+clampf(_confirm_age/0.38,0,1)*frame.size.x
		_chrome.draw_rect(Rect2(shine_x,frame.position.y+3,2,frame.size.y-6),Color(1,1,0.8,flash*0.65))
	# Soft stepped edge masks emphasize motion without obscuring the selected character.
	for index:int in range(4):
		var alpha:float = (4-index)*0.12
		_chrome.draw_rect(Rect2(index*8,2,8,size.y-4),Color(0.04,0.06,0.06,alpha))
		_chrome.draw_rect(Rect2(size.x-(index+1)*8,2,8,size.y-4),Color(0.04,0.06,0.06,alpha))
