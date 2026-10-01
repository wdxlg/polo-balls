extends Control
## 轮换切换的胜利卡片：门完全关上后从屏幕上方滑下（原版成就框放大），显示胜利的人物或队伍和提示文字；
## 开门时随门一起滑回上方。只读取 duel_top_hud 的回合结果快照，不改任何对局状态。
const FONT:Font = preload("res://fonts/Mojangles.ttf")
const TOAST:Texture2D = preload("res://Images/UI/minecraft_hud/toast_advancement.png")
const ITEM_FRAME:Texture2D = preload("res://Images/UI/rotation_frames/item_frame.png")
const SLIDE_SECONDS:float = 0.45
const TITLE_COLOR:Color = Color("ff88ff")
const BODY_COLOR:Color = Color("ffffff")
const HINT_COLOR:Color = Color("e0e0e0")
const TEXT:Dictionary = {
	"zh":{"title":"挑战已完成！","none":"本局结束","hint":"下一场即将开始"},
	"en":{"title":"Challenge Complete!","none":"Round Complete","hint":"Next round starting soon"},
}
var hud:Control
var door:CanvasLayer
## 0 = 完全在屏幕上方，1 = 到位。
var slide:float = 0.0
var _last_usec:int = 0
var _wool_cache:Dictionary = {}
## 门关着时下一场会加载并重置顶部 HUD，所以胜者在关门前就固定下来。
var _locale:String = "zh"
var _winner:Dictionary = {}
var _body:String = ""
## 开门时改用缓入曲线，门一动卡片就往上收，而不是停到最后一刻。
var _leaving:bool = false

func setup(result_hud:Control,transition:CanvasLayer) -> void:
	hud = result_hud
	door = transition
	if not is_instance_valid(hud): return
	if hud.has_method("_toast_locale"): _locale = str(hud.call("_toast_locale"))
	var index:int = int(hud.get("winner_index"))
	var sides:Array = hud.get("sides")
	if index >= 0 and index < sides.size(): _winner = (sides[index] as Dictionary).duplicate()
	_body = str(hud.call("victory_body_text"))

func _ready() -> void:
	name = "RotationResultCard"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_last_usec = Time.get_ticks_usec()

func _process(_delta:float) -> void:
	# 真实时间：轮换切换时游戏可能暂停或倍速。
	var now:int = Time.get_ticks_usec()
	var ui_delta:float = minf(float(now - _last_usec) / 1000000.0,0.1)
	_last_usec = now
	if is_instance_valid(door):
		var phase:int = int(door.phase)
		if phase == int(door.Phase.COVERED): slide = move_toward(slide,1.0,ui_delta / SLIDE_SECONDS)
		elif phase == int(door.Phase.OPENING):
			_leaving = true
			slide = minf(slide,float(door.progress))
		else: slide = 0.0
	queue_redraw()

func pixel() -> float:
	var screen:Vector2 = get_viewport_rect().size
	return 5.5 * minf(screen.x / 1080.0,screen.y / 720.0)

func card_rect() -> Rect2:
	var p:float = pixel()
	var screen:Vector2 = get_viewport_rect().size
	var card:Vector2 = Vector2(160.0,32.0) * p
	var s:float = clampf(slide,0.0,1.0)
	var t:float = s * s if _leaving else 1.0 - pow(1.0 - s,4.0)
	var hidden_y:float = -card.y - 24.0 * p
	return Rect2(Vector2((screen.x - card.x) * 0.5,lerpf(hidden_y,screen.y * 0.16,t)),card)

func locale() -> String:
	return _locale

func winner_side() -> Dictionary:
	return _winner

func title_text() -> String:
	var strings:Dictionary = TEXT[locale()] if TEXT.has(locale()) else TEXT.zh
	return str(strings.title) if not winner_side().is_empty() else str(strings.none)

func body_text() -> String:
	return _body

func hint_text() -> String:
	return str((TEXT[locale()] if TEXT.has(locale()) else TEXT.zh).hint)

func _wool(name:String) -> Texture2D:
	if not _wool_cache.has(name): _wool_cache[name] = load("res://Images/UI/team_victory/" + name + "_wool.png")
	return _wool_cache[name]

func _draw_wool_cube(texture:Texture2D,rect:Rect2) -> void:
	var uv:=PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)])
	var faces:Array = [[Vector2(0.5,0),Vector2(1,0.25),Vector2(0.5,0.5),Vector2(0,0.25)],
		[Vector2(0,0.25),Vector2(0.5,0.5),Vector2(0.5,1),Vector2(0,0.75)],
		[Vector2(0.5,0.5),Vector2(1,0.25),Vector2(1,0.75),Vector2(0.5,1)]]
	for i:int in range(3):
		var points:=PackedVector2Array()
		for point:Vector2 in faces[i]: points.append(rect.position + point * rect.size)
		var shade:float = [1.0,0.8,0.6][i]
		draw_polygon(points,PackedColorArray([Color(shade,shade,shade)]),uv,texture)

func _fit(text:String,width:float,size:int) -> int:
	var font_size:int = size
	while font_size > 8 and FONT.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x > width: font_size -= 1
	return font_size

func _draw() -> void:
	if slide <= 0.0: return
	var p:float = pixel()
	var rect:Rect2 = card_rect()
	draw_texture_rect(TOAST,rect,false)
	var side:Dictionary = winner_side()
	if not side.is_empty():
		var slot:Rect2 = Rect2(rect.position + Vector2(8.0,8.0) * p,Vector2(16.0,16.0) * p)
		var wool:String = str(side.get("team_wool",""))
		if not wool.is_empty():
			draw_texture_rect(ITEM_FRAME,slot,false)
			_draw_wool_cube(_wool(wool),slot.grow(-slot.size.x * 0.18))
		elif side.get("texture") is Texture2D:
			var texture:Texture2D = side.texture
			var fitted:Vector2 = texture.get_size() * minf(slot.size.x / maxf(texture.get_width(),1.0),slot.size.y / maxf(texture.get_height(),1.0))
			draw_texture_rect(texture,Rect2(slot.get_center() - fitted * 0.5,fitted),false)
	var text_x:float = rect.position.x + 30.0 * p
	var text_width:float = rect.size.x - 38.0 * p
	var title:String = title_text()
	draw_string(FONT,Vector2(text_x,rect.position.y + 15.0 * p),title,HORIZONTAL_ALIGNMENT_LEFT,text_width,_fit(title,text_width,int(7.0 * p)),TITLE_COLOR)
	var body:String = body_text()
	draw_string(FONT,Vector2(text_x,rect.position.y + 26.0 * p),body,HORIZONTAL_ALIGNMENT_LEFT,text_width,_fit(body,text_width,int(7.0 * p)),BODY_COLOR)
	var hint:String = hint_text()
	var hint_size:int = int(6.0 * p)
	var baseline:Vector2 = Vector2(rect.position.x,rect.end.y + 12.0 * p)
	draw_string_outline(FONT,baseline,hint,HORIZONTAL_ALIGNMENT_CENTER,rect.size.x,hint_size,maxi(2,int(p)),Color(0,0,0,0.85))
	draw_string(FONT,baseline,hint,HORIZONTAL_ALIGNMENT_CENTER,rect.size.x,hint_size,HINT_COLOR)

