extends Node
## 录像封面：开场镜头拉开、全员同框的那一刻（开战铃已响且开场拉远镜头结束；录制开始得更晚就取第一帧，
## 一直没开战就在收尾时取），用与录像同一相机抓一张纯战场画面——共享 World2D 的离屏视口，
## 剔除中/英文文字副本与被隐藏的原文，不含工具栏、HUD、VS 字和暗角——再按中/英文各合成
## 9:16（1080×1920）与 16:9（1920×1080）两张 JPG。标题是 mc_title_text 的我的世界 3D 立体字，
## 内容与配色和对局 VS 标题一致（battle_record_locale 翻译后的 VS BBCode → versus_title_3d 解析）。
## 只在离屏视口里各渲染一次，读回放在后续帧、合成与写盘在后台线程，不打断录制计时。
const TITLE_SCRIPT:GDScript = preload("res://scripts/ui/mc_title_text.gd")
const VERSUS:GDScript = preload("res://scripts/ui/versus_title_3d.gd")
const LocaleScript = preload("res://scripts/ui/battle_record_locale.gd")
const NamingScript = preload("res://scripts/ui/battle_record_naming.gd")
const PORTRAIT:Vector2i = Vector2i(1080,1920)
const LANDSCAPE:Vector2i = Vector2i(1920,1080)
const JPG_QUALITY:float = 0.92
## 16:9 里地图宽高比不超过这个值就左图右字，否则上字下图。
const SIDE_LAYOUT_MAX_ASPECT:float = 1.3
enum State {WAITING, RENDERING, TITLES, COMPOSING, DONE, FAILED}

var state:int = State.WAITING
var folder:String = ""
## "zh_9x16" 等 → 已写出的封面绝对路径。
var outputs:Dictionary = {}
var error:String = ""
var _viewport:SubViewport = null
var _render_frame:int = -1
var _render_attempts:int = 0
var _frame:Image = null
var _map_px:Rect2 = Rect2()
var _sides:Dictionary = {}
var _fallback_titles:Dictionary = {}
var _layouts:Dictionary = {}
var _titles:Array = []
var _task_id:int = -1
var _job:Dictionary = {}


func _ready() -> void:
	name = "BattleRecordCover"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _notification(what:int) -> void:
	if what == NOTIFICATION_PREDELETE and _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


func is_active() -> bool:
	return state in [State.RENDERING, State.TITLES, State.COMPOSING]


## 每个录像抓帧调用：现在是不是封面时刻。
func should_capture(world:Node) -> bool:
	if state != State.WAITING: return false
	if world == null or world.get("_intro_camera_state") == null or world.get("_battle_start_bell_played") == null: return true
	return bool(world.get("_battle_start_bell_played")) and int(world.get("_intro_camera_state")) == 0


## 用录像当前帧的画布变换抓纯战场画面；sides/titles 为 locale → VS 段 / 文件名标题（VS 解析不出来时用）。
func capture(main:Viewport, canvas_transform:Transform2D, size:Vector2i, map_rect:Rect2, sides:Dictionary, titles:Dictionary) -> void:
	if state != State.WAITING: return
	_sides = sides.duplicate(true)
	_fallback_titles = titles.duplicate()
	var sub := SubViewport.new()
	sub.name = "CoverFrame"
	sub.disable_3d = true
	sub.transparent_bg = false
	sub.gui_disable_input = true
	sub.size = size
	sub.use_hdr_2d = false
	sub.canvas_item_default_texture_filter = main.canvas_item_default_texture_filter
	sub.msaa_2d = main.msaa_2d
	sub.snap_2d_transforms_to_pixel = main.snap_2d_transforms_to_pixel
	sub.snap_2d_vertices_to_pixel = main.snap_2d_vertices_to_pixel
	sub.world_2d = main.world_2d
	# 纯战场：去掉中/英文文字副本和录制期间被藏起来的原文。
	sub.canvas_cull_mask = ((1 << 20) - 1) & ~(LocaleScript.ZH_BIT | LocaleScript.EN_BIT | LocaleScript.HIDDEN_BIT)
	sub.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(sub)
	sub.canvas_transform = canvas_transform # 画布要在进入场景树后才存在。
	_viewport = sub
	_map_px = canvas_transform * map_rect if map_rect.has_area() else Rect2(Vector2(size) * Vector2(0.06,0.25),Vector2(size) * Vector2(0.88,0.5))
	_render_frame = Engine.get_frames_drawn()
	state = State.RENDERING


func _process(_delta:float) -> void:
	match state:
		State.RENDERING:
			if Engine.get_frames_drawn() <= _render_frame + 1: return
			_frame = _viewport.get_texture().get_image() if is_instance_valid(_viewport) else null
			# 新建的离屏视口偶尔第一次还没真正画出来（读回全黑）：再画一次。
			if is_instance_valid(_viewport) and (_frame == null or _is_blank(_frame)) and _render_attempts < 6:
				_render_attempts += 1
				_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
				_render_frame = Engine.get_frames_drawn()
				return
			if is_instance_valid(_viewport): _viewport.queue_free()
			_viewport = null
			if _frame == null or _frame.is_empty():
				_fail("封面画面读取失败。")
				return
			_frame.convert(Image.FORMAT_RGBA8)
			_start_titles()
		State.TITLES:
			for entry:Dictionary in _titles:
				if int(entry.built_frame) < 0 or Engine.get_frames_drawn() <= int(entry.built_frame) + 1: return
			_start_compose()
		State.COMPOSING:
			if _task_id < 0 or not WorkerThreadPool.is_task_completed(_task_id): return
			WorkerThreadPool.wait_for_task_completion(_task_id)
			_task_id = -1
			outputs = _job.get("written",{}).duplicate()
			error = str(_job.get("error",""))
			state = State.DONE if error.is_empty() else State.FAILED
			_job = {}


func _fail(message:String) -> void:
	error = message
	state = State.FAILED
	for entry:Dictionary in _titles:
		if is_instance_valid(entry.node): entry.node.queue_free()
	_titles.clear()


## 每种画幅一个标题区域（像素），按区域挑折行，再各渲染一张立体字。
func _start_titles() -> void:
	_layouts = {"9x16":_portrait_layout(), "16x9":_landscape_layout()}
	for locale:String in ["zh","en"]:
		for kind:String in _layouts:
			var area:Rect2 = _layouts[kind].title
			var sides:Array = _sides.get(locale,[])
			var lines:Array = _title_lines(sides,area.size) if not sides.is_empty() else [{"segments":[{"text":str(_fallback_titles.get(locale,"")),"style":"stone"}]}]
			var title:Control = TITLE_SCRIPT.new()
			title.name = "CoverTitle_%s_%s" % [locale,kind]
			title.visible = false # 只要它离屏视口里的画面，不画到玩家屏幕上。
			title.setup(lines,{"render_width":clampi(int(area.size.x * 1.15),1024,2048)})
			var entry:Dictionary = {"locale":locale,"kind":kind,"node":title,"built_frame":-1}
			title.built.connect(func() -> void: entry.built_frame = Engine.get_frames_drawn())
			_titles.append(entry)
			add_child(title)
	state = State.TITLES


func _start_compose() -> void:
	var titles:Dictionary = {}
	for entry:Dictionary in _titles:
		var image:Image = entry.node.texture().get_image() if entry.node.texture() != null else null
		entry.node.queue_free()
		if image == null or image.is_empty():
			_fail("封面标题渲染失败。")
			return
		image.convert(Image.FORMAT_RGBA8)
		var used:Rect2i = image.get_used_rect()
		titles["%s_%s" % [entry.locale,entry.kind]] = image.get_region(used) if used.has_area() else image
	_titles.clear()
	_job = {"frame":_frame,"map":_map_px,"layouts":_layouts.duplicate(true),"titles":titles,"folder":folder,"written":{},"error":""}
	_frame = null
	_task_id = WorkerThreadPool.add_task(_compose_all.bind(_job),false,"battle_record_cover")
	state = State.COMPOSING


static func _is_blank(image:Image) -> bool:
	var probe:Image = image.duplicate()
	probe.resize(8,8,Image.INTERPOLATE_BILINEAR)
	for y:int in range(8):
		for x:int in range(8):
			var color:Color = probe.get_pixel(x,y)
			if maxf(color.r,maxf(color.g,color.b)) > 0.01: return false
	return true


## 封面标题折行：和 VS 立体字同内容同配色，但队伍内也能在「+」处折行，挑在区域里字最大的方案。
static func _title_lines(sides:Array, area:Vector2) -> Array:
	var tokens:Array = []
	for side_index:int in range(sides.size()):
		var side:Dictionary = sides[side_index]
		var members:PackedStringArray = String(side.text).split(" + ",false)
		for member_index:int in range(members.size()):
			var separator:String = "" if side_index == 0 and member_index == 0 else ("VS" if member_index == 0 else "+")
			tokens.append({"text":members[member_index].strip_edges(),"style":side.style,"separator":separator})
	var widest_token:float = 0.0
	var total:float = 0.0
	for token:Dictionary in tokens:
		var width:float = VERSUS.estimate_width(token.text)
		widest_token = maxf(widest_token,width)
		total += width + _separator_width(token.separator)
	var best:Array = []
	var best_scale:float = -1.0
	var wrap:float = widest_token
	while true:
		var lines:Array = _pack_tokens(tokens,wrap)
		var widest:float = 0.0
		for line:Dictionary in lines: widest = maxf(widest,float(line.width))
		var per_em:float = minf(area.x / (widest + 0.6),area.y / (float(lines.size()) * 1.3 + 0.2))
		if per_em > best_scale * 1.03:
			best_scale = per_em
			best = lines
		if wrap >= total: break
		wrap = minf(wrap + 0.5,total)
	var result:Array = []
	for line:Dictionary in best: result.append({"segments":line.segments})
	return result


static func _separator_width(separator:String) -> float:
	if separator == "VS": return VERSUS.VS_WIDTH_EM
	return 0.0 if separator.is_empty() else VERSUS.estimate_width(" + ")


static func _pack_tokens(tokens:Array, wrap_em:float) -> Array:
	var lines:Array = []
	var segments:Array = []
	var width:float = 0.0
	for token:Dictionary in tokens:
		var token_width:float = VERSUS.estimate_width(token.text)
		var separator_width:float = _separator_width(token.separator)
		if not segments.is_empty() and width + separator_width + token_width > wrap_em:
			lines.append({"segments":segments,"width":width})
			segments = []
			width = 0.0
		if token.separator == "VS":
			segments.append({"text":"VS","style":"gold","scale":VERSUS.VS_INLINE_SCALE})
		elif token.separator == "+":
			segments.append({"text":" + " if not segments.is_empty() else "+ ","style":token.style})
		width += separator_width
		segments.append({"text":token.text,"style":token.style})
		width += token_width
	if not segments.is_empty(): lines.append({"segments":segments,"width":width})
	return lines


## 竖版：录像同一画面，标题放在地图上方（地图太高就放下方，取空间大的一侧），背后一道渐暗。
func _portrait_layout() -> Dictionary:
	var size := Vector2(PORTRAIT)
	var top_space:float = _map_px.position.y - 140.0 - 24.0
	var bottom_space:float = size.y - 140.0 - (_map_px.end.y + 24.0)
	var height:float = clampf(maxf(top_space,bottom_space),260.0,520.0)
	var on_top:bool = top_space >= bottom_space or bottom_space < 260.0
	var y:float = (_map_px.position.y - 24.0 - height) if on_top else (_map_px.end.y + 24.0)
	y = clampf(y,110.0,size.y - 110.0 - height)
	return {"title":Rect2(50.0,y,size.x - 100.0,height),"top":on_top}


## 横版：地图接近方形就左图右字，否则上字下图；背景是同一画面放大模糊压暗。
func _landscape_layout() -> Dictionary:
	var size := Vector2(LANDSCAPE)
	var crop:Rect2 = _map_crop()
	var aspect:float = crop.size.x / maxf(crop.size.y,1.0)
	if aspect <= SIDE_LAYOUT_MAX_ASPECT:
		var map_h:float = size.y - 96.0
		var map_w:float = minf(map_h * aspect,size.x * 0.58)
		map_h = map_w / aspect
		var map_rect := Rect2(64.0,(size.y - map_h) * 0.5,map_w,map_h)
		var left:float = map_rect.end.x + 56.0
		return {"title":Rect2(left,90.0,size.x - 64.0 - left,size.y - 180.0),"map":map_rect,"crop":crop}
	var title := Rect2(80.0,36.0,size.x - 160.0,300.0)
	var room := Rect2(60.0,title.end.y + 24.0,size.x - 120.0,size.y - title.end.y - 24.0 - 40.0)
	var scale_amount:float = minf(room.size.x / crop.size.x,room.size.y / crop.size.y)
	var fitted:Vector2 = crop.size * scale_amount
	return {"title":title,"map":Rect2(room.position + (room.size - fitted) * 0.5,fitted),"crop":crop}


## 地图在抓帧里的区域，四周多留一点（3D 墙与地影），限制在画面内。
func _map_crop() -> Rect2:
	var margin:float = maxf(_map_px.size.x,_map_px.size.y) * 0.05
	var frame_rect := Rect2(Vector2.ZERO,Vector2(PORTRAIT))
	var crop:Rect2 = _map_px.grow(margin).intersection(frame_rect)
	return crop if crop.size.x >= 32.0 and crop.size.y >= 32.0 else frame_rect


## 后台线程：只做 Image 运算与写盘。
static func _compose_all(job:Dictionary) -> void:
	var frame:Image = job.frame
	for locale:String in ["zh","en"]:
		for kind:String in ["9x16","16x9"]:
			var key:String = "%s_%s" % [locale,kind]
			var canvas:Image = _compose_portrait(frame,job.layouts[kind],job.titles[key]) if kind == "9x16" else _compose_landscape(frame,job.layouts[kind],job.titles[key])
			canvas.convert(Image.FORMAT_RGB8)
			var path:String = String(job.folder).path_join(NamingScript.COVERS[key])
			var result:Error = canvas.save_jpg(path,JPG_QUALITY)
			if result != OK:
				job.error = "封面写入失败（%s）：%s" % [error_string(result),path]
				return
			job.written[key] = path


static func _compose_portrait(frame:Image, layout:Dictionary, title:Image) -> Image:
	var canvas:Image = frame.duplicate()
	if canvas.get_size() != PORTRAIT: canvas.resize(PORTRAIT.x,PORTRAIT.y,Image.INTERPOLATE_BILINEAR)
	var area:Rect2 = layout.title
	# 标题那一侧从画面边缘渐暗到标题区外，立体字更醒目。
	var band_top:int = 0 if layout.top else int(area.position.y - 90.0)
	var band_bottom:int = int(area.end.y + 90.0) if layout.top else PORTRAIT.y
	_shade_band(canvas,band_top,band_bottom,layout.top,0.5)
	_place_title(canvas,title,area)
	return canvas


static func _compose_landscape(frame:Image, layout:Dictionary, title:Image) -> Image:
	var canvas:Image = frame.duplicate()
	# 背景：整幅画面放大铺满、模糊、压暗。
	var cover_scale:float = maxf(float(LANDSCAPE.x) / canvas.get_width(),float(LANDSCAPE.y) / canvas.get_height())
	var tiny := Vector2i(maxi(int(canvas.get_width() * cover_scale / 24.0),2),maxi(int(canvas.get_height() * cover_scale / 24.0),2))
	canvas.resize(tiny.x,tiny.y,Image.INTERPOLATE_BILINEAR)
	canvas.resize(int(frame.get_width() * cover_scale),int(frame.get_height() * cover_scale),Image.INTERPOLATE_BILINEAR)
	var crop:Rect2 = layout.crop
	var center_y:float = (crop.get_center().y * cover_scale) - LANDSCAPE.y * 0.5
	var offset := Vector2i(int((canvas.get_width() - LANDSCAPE.x) * 0.5),clampi(int(center_y),0,canvas.get_height() - LANDSCAPE.y))
	canvas = canvas.get_region(Rect2i(offset,LANDSCAPE))
	canvas.adjust_bcs(0.6,1.0,0.85)
	# 前景：清晰的地图区域，带一点投影。
	var map_rect:Rect2 = layout.map
	var map_image:Image = frame.get_region(Rect2i(crop))
	map_image.resize(maxi(int(map_rect.size.x),1),maxi(int(map_rect.size.y),1),Image.INTERPOLATE_LANCZOS)
	var shadow := Image.create(map_image.get_width(),map_image.get_height(),false,Image.FORMAT_RGBA8)
	shadow.fill(Color(0,0,0,0.45))
	canvas.blend_rect(shadow,Rect2i(Vector2i.ZERO,shadow.get_size()),Vector2i(map_rect.position) + Vector2i(14,14))
	canvas.blit_rect(map_image,Rect2i(Vector2i.ZERO,map_image.get_size()),Vector2i(map_rect.position))
	_place_title(canvas,title,layout.title)
	return canvas


## 立体字等比缩放进区域并居中。
static func _place_title(canvas:Image, title:Image, area:Rect2) -> void:
	if title == null or title.is_empty(): return
	var scale_amount:float = minf(area.size.x / title.get_width(),area.size.y / title.get_height())
	var size := Vector2i(maxi(int(title.get_width() * scale_amount),1),maxi(int(title.get_height() * scale_amount),1))
	var scaled:Image = title.duplicate()
	scaled.resize(size.x,size.y,Image.INTERPOLATE_LANCZOS)
	var at := Vector2i(area.position + (area.size - Vector2(size)) * 0.5)
	canvas.blend_rect(scaled,Rect2i(Vector2i.ZERO,size),at)


## 竖直渐暗带：from_edge 为 true 时上沿最暗、往下变透明，否则下沿最暗。
static func _shade_band(canvas:Image, top:int, bottom:int, from_edge:bool, strength:float) -> void:
	top = clampi(top,0,canvas.get_height())
	bottom = clampi(bottom,0,canvas.get_height())
	var height:int = bottom - top
	if height <= 1: return
	var ramp := Image.create(1,height,false,Image.FORMAT_RGBA8)
	for y:int in range(height):
		var t:float = float(y) / float(height - 1)
		var amount:float = (1.0 - t) if from_edge else t
		ramp.set_pixel(0,y,Color(0,0,0,strength * amount * amount * (3.0 - 2.0 * amount)))
	ramp.resize(canvas.get_width(),height,Image.INTERPOLATE_BILINEAR)
	canvas.blend_rect(ramp,Rect2i(0,0,canvas.get_width(),height),Vector2i(0,top))
