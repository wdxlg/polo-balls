extends Node
## 录像封面：从开场镜头结束到最后决出胜负之前（场上不足两方即结束），每 0.5 秒取样一次，
## 用蓄水池抽样等概率随机挑一帧；所有主战角色完整在画面内的帧优先，都不满足时退回部分出画的帧，
## 再不行才用收尾时的画面。只有被抽中的帧才渲染：共享 World2D 的离屏视口、与录像同一相机，
## 剔除中/英文文字副本与被隐藏的原文，不含工具栏、HUD、VS 字和暗角。
## 中/英文各合成 9:16（1080×1920）与 16:9（1920×1080）两张 JPG；标题是 mc_title_text 的我的世界 3D 立体字，
## 文字同文件夹对阵名，配色同 VS 立体字。标题位置随画面变化：竖版随机挑不挡角色的空处，
## 横版随机左右/上下与高低。随机数用独立生成器，不影响离线录制的确定性；合成与写盘在后台线程。
const TITLE_SCRIPT:GDScript = preload("res://scripts/ui/mc_title_text.gd")
const VERSUS:GDScript = preload("res://scripts/ui/versus_title_3d.gd")
const LocaleScript = preload("res://scripts/ui/battle_record_locale.gd")
const NamingScript = preload("res://scripts/ui/battle_record_naming.gd")
const PORTRAIT:Vector2i = Vector2i(1080,1920)
const LANDSCAPE:Vector2i = Vector2i(1920,1080)
const JPG_QUALITY:float = 0.92
const SAMPLE_INTERVAL_FRAMES:int = 30
## 角色贴图离画面边缘至少这么多像素才算“完整在画面内”。
const EDGE_MARGIN:float = 8.0
## 16:9 里地图宽高比不超过这个值就左右排，否则上下排。
const SIDE_LAYOUT_MAX_ASPECT:float = 1.3
const PORTRAIT_TITLE_BOX:Vector2 = Vector2(980.0,340.0)
enum State {SAMPLING, TITLES, COMPOSING, DONE, FAILED}
## 取样档次：0 收尾兜底，1 有角色部分出画，2 全员完整在画面内。
enum Tier {FALLBACK, PARTIAL, FULL}

var state:int = State.SAMPLING
var folder:String = ""
## "zh_9x16" 等 → 已写出的封面绝对路径。
var outputs:Dictionary = {}
var error:String = ""
var _rng := RandomNumberGenerator.new()
var _countdown:int = SAMPLE_INTERVAL_FRAMES
var _seen:int = 0
var _finishing:bool = false
var _viewport:SubViewport = null
## 正在渲染、等读回的候选帧。
var _pending:Dictionary = {}
## 当前抽中的帧：image / tier / map / rects / sides / titles。
var _chosen:Dictionary = {}
var _layouts:Dictionary = {}
var _titles:Array = []
var _task_id:int = -1
var _job:Dictionary = {}


func _init() -> void:
	_rng.randomize()


func _ready() -> void:
	name = "BattleRecordCover"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _notification(what:int) -> void:
	if what == NOTIFICATION_PREDELETE and _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


## 收尾后还在出图（等候选帧读回、渲染标题、合成写盘）。
func is_active() -> bool:
	return _finishing and state not in [State.DONE, State.FAILED]


func has_frame() -> bool:
	return not _chosen.is_empty() or not _pending.is_empty()


## 每个录像帧调用：到了取样时刻才返回 true（随后由录像器调用 offer）。
func wants_sample() -> bool:
	if state != State.SAMPLING or _finishing or not _pending.is_empty(): return false
	_countdown -= 1
	if _countdown > 0: return false
	_countdown = SAMPLE_INTERVAL_FRAMES
	return true


## 取样：判断这一帧能不能当封面，按蓄水池抽样决定要不要渲染它。labels 返回 {sides, titles}。
func offer(world:Node, main:Viewport, canvas_transform:Transform2D, size:Vector2i, map_rect:Rect2, labels:Callable) -> void:
	if not battle_running(world): return
	var rects:Array = character_rects(world,canvas_transform)
	if rects.is_empty(): return
	var tier:int = Tier.FULL if all_inside(rects,size) else Tier.PARTIAL
	var held:int = int(_chosen.get("tier",-1))
	if tier < held: return
	if tier > held: _seen = 0 # 更好的一档从头开始抽，之前的低档帧作废。
	_seen += 1
	if _rng.randf() * float(_seen) >= 1.0: return
	_render(main,canvas_transform,size,map_rect,rects,tier,labels)


## 收尾时还没有任何候选帧：用当前画面兜底。
func offer_fallback(world:Node, main:Viewport, canvas_transform:Transform2D, size:Vector2i, map_rect:Rect2, labels:Callable) -> void:
	if has_frame() or state != State.SAMPLING: return
	_render(main,canvas_transform,size,map_rect,character_rects(world,canvas_transform),Tier.FALLBACK,labels)


## 录制结束：不再取样，候选帧读回后开始出图。
func finish() -> void:
	_finishing = true


## 开场镜头已结束、仍在正式对战（至少两方存活、不在轮换转场里）。
static func battle_running(world:Node) -> bool:
	if world == null: return true
	if world.get("_intro_camera_state") != null and int(world.get("_intro_camera_state")) != 0: return false
	if world.has_method("is_rotation_scene_transition_active") and world.is_rotation_scene_transition_active(): return false
	if world.has_method("is_combat_runtime_active") and not world.is_combat_runtime_active(): return false
	if world.has_method("_collect_alive_victory_sides") and world._collect_alive_victory_sides().size() < 2: return false
	return true


## 存活主战角色的贴图在录像画面里的像素范围。
static func character_rects(world:Node, canvas_transform:Transform2D) -> Array:
	var rects:Array = []
	var units:Variant = world.get("_battle_units_cache") if world != null else null
	if not units is Array: return rects
	for raw:Variant in units:
		if not raw is ball or not is_instance_valid(raw): continue
		var actor:ball = raw
		if actor.is_queued_for_deletion() or actor.health <= 0 or not actor.is_visible_in_tree(): continue
		if world.has_method("_is_primary_battle_character") and not world._is_primary_battle_character(actor): continue
		var image:Node2D = actor.image as Node2D if is_instance_valid(actor.image) else null
		var xform:Transform2D = image.get_global_transform() if image != null else actor.get_global_transform()
		rects.append(canvas_transform * (xform * actor._get_source_visual_rect()))
	return rects


static func all_inside(rects:Array, size:Vector2i) -> bool:
	var frame := Rect2(Vector2.ZERO,Vector2(size)).grow(-EDGE_MARGIN)
	for rect:Rect2 in rects:
		if not frame.encloses(rect): return false
	return true


func _render(main:Viewport, canvas_transform:Transform2D, size:Vector2i, map_rect:Rect2, rects:Array, tier:int, labels:Callable) -> void:
	if not is_instance_valid(_viewport):
		var sub := SubViewport.new()
		sub.name = "CoverFrame"
		sub.disable_3d = true
		sub.transparent_bg = false
		sub.gui_disable_input = true
		sub.use_hdr_2d = false
		sub.canvas_item_default_texture_filter = main.canvas_item_default_texture_filter
		sub.msaa_2d = main.msaa_2d
		sub.snap_2d_transforms_to_pixel = main.snap_2d_transforms_to_pixel
		sub.snap_2d_vertices_to_pixel = main.snap_2d_vertices_to_pixel
		sub.world_2d = main.world_2d
		# 纯战场：去掉中/英文文字副本和录制期间被藏起来的原文。
		sub.canvas_cull_mask = ((1 << 20) - 1) & ~(LocaleScript.ZH_BIT | LocaleScript.EN_BIT | LocaleScript.HIDDEN_BIT)
		sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(sub)
		_viewport = sub
	_viewport.size = size
	_viewport.canvas_transform = canvas_transform
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var text:Dictionary = labels.call() if labels.is_valid() else {}
	var map_px:Rect2 = canvas_transform * map_rect if map_rect.has_area() else Rect2(Vector2(size) * Vector2(0.06,0.25),Vector2(size) * Vector2(0.88,0.5))
	_pending = {"tier":tier, "frame":Engine.get_frames_drawn(), "attempts":0, "map":map_px, "rects":rects,
		"sides":text.get("sides",{}), "titles":text.get("titles",{})}


func _process(_delta:float) -> void:
	match state:
		State.SAMPLING:
			if not _pending.is_empty(): _read_pending()
			if _finishing and _pending.is_empty():
				if _chosen.is_empty(): _fail("没有可用的封面画面。")
				else: _start_titles()
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


func _read_pending() -> void:
	if Engine.get_frames_drawn() <= int(_pending.frame) + 1: return
	var image:Image = _viewport.get_texture().get_image() if is_instance_valid(_viewport) else null
	# 离屏视口偶尔第一次还没真正画出来（读回全黑）：再画一次。
	if is_instance_valid(_viewport) and (image == null or _is_blank(image)) and int(_pending.attempts) < 6:
		_pending.attempts = int(_pending.attempts) + 1
		_pending.frame = Engine.get_frames_drawn()
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		return
	if image != null and not image.is_empty():
		image.convert(Image.FORMAT_RGBA8)
		_chosen = _pending.duplicate()
		_chosen.image = image
	_pending = {}


func _fail(message:String) -> void:
	error = message
	state = State.FAILED
	for entry:Dictionary in _titles:
		if is_instance_valid(entry.node): entry.node.queue_free()
	_titles.clear()


func _start_titles() -> void:
	if is_instance_valid(_viewport): _viewport.queue_free()
	_viewport = null
	_layouts = {"9x16":{"title":Rect2(Vector2(50.0,0.0),PORTRAIT_TITLE_BOX)}, "16x9":_landscape_layout()}
	for locale:String in ["zh","en"]:
		var sides:Array = _chosen.sides.get(locale,[]) if _chosen.sides is Dictionary else []
		for kind:String in _layouts:
			var area:Rect2 = _layouts[kind].title
			var lines:Array = _title_lines(sides,area.size) if not sides.is_empty() else [{"segments":[{"text":str(_chosen.titles.get(locale,"")),"style":"stone"}]}]
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
	_layouts["9x16"].map = _chosen.map
	_layouts["9x16"].avoid = _avoid_rects(_chosen.rects)
	_job = {"frame":_chosen.image,"layouts":_layouts.duplicate(true),"titles":titles,"folder":folder,"seed":_rng.randi(),"written":{},"error":""}
	_chosen = {}
	_task_id = WorkerThreadPool.add_task(_compose_all.bind(_job),false,"battle_record_cover")
	state = State.COMPOSING


## 标题不能挡住的区域：角色贴图四周留一点，头顶多留出血量数字的位置。
static func _avoid_rects(rects:Array) -> Array:
	var result:Array = []
	for rect:Rect2 in rects:
		var pad:float = 14.0 + maxf(rect.size.x,rect.size.y) * 0.12
		result.append(rect.grow_individual(pad,pad + rect.size.y * 0.45,pad,pad))
	return result


## 横版：地图接近方形就左右排（地图随机在左或右），否则上下排（标题随机在上或下）；标题高低也随机。
func _landscape_layout() -> Dictionary:
	var size := Vector2(LANDSCAPE)
	var crop:Rect2 = _map_crop()
	var aspect:float = crop.size.x / maxf(crop.size.y,1.0)
	var anchor:float = [0.12,0.5,0.88][_rng.randi_range(0,2)]
	if aspect <= SIDE_LAYOUT_MAX_ASPECT:
		var map_h:float = size.y - 96.0
		var map_w:float = minf(map_h * aspect,size.x * 0.58)
		map_h = map_w / aspect
		var map_left:bool = _rng.randf() < 0.5
		var map_rect := Rect2(64.0 if map_left else size.x - 64.0 - map_w,(size.y - map_h) * 0.5,map_w,map_h)
		var column_left:float = map_rect.end.x + 56.0 if map_left else 64.0
		var column_right:float = size.x - 64.0 if map_left else map_rect.position.x - 56.0
		return {"title":Rect2(column_left,90.0,column_right - column_left,size.y - 180.0),"map":map_rect,"crop":crop,"anchor":anchor,"vertical":true}
	var title_top:bool = _rng.randf() < 0.5
	var band := 300.0
	var title := Rect2(80.0,36.0 if title_top else size.y - 36.0 - band,size.x - 160.0,band)
	var room := Rect2(60.0,(title.end.y + 24.0) if title_top else 40.0,size.x - 120.0,size.y - band - 36.0 - 24.0 - 40.0)
	var scale_amount:float = minf(room.size.x / crop.size.x,room.size.y / crop.size.y)
	var fitted:Vector2 = crop.size * scale_amount
	return {"title":title,"map":Rect2(room.position + (room.size - fitted) * 0.5,fitted),"crop":crop,"anchor":anchor,"vertical":false}


## 横版里清晰显示的范围：地图四周多留一点（3D 墙与地影），并包住所有角色，限制在画面内。
func _map_crop() -> Rect2:
	var map_px:Rect2 = _chosen.map
	var crop:Rect2 = map_px.grow(maxf(map_px.size.x,map_px.size.y) * 0.05)
	for rect:Rect2 in _chosen.rects: crop = crop.merge(rect.grow(12.0))
	var frame_rect := Rect2(Vector2.ZERO,Vector2(_chosen.image.get_size()))
	crop = crop.intersection(frame_rect)
	return crop if crop.size.x >= 32.0 and crop.size.y >= 32.0 else frame_rect


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


## 后台线程：只做 Image 运算与写盘。
static func _compose_all(job:Dictionary) -> void:
	var frame:Image = job.frame
	var rng := RandomNumberGenerator.new()
	rng.seed = int(job.seed)
	# 竖版/横版的标题位置各自随机，中英文共用同一位置，两种语言的封面构图一致。
	var portrait_spot:Rect2 = _pick_portrait_spot(job.layouts["9x16"],[job.titles["zh_9x16"],job.titles["en_9x16"]],rng)
	for locale:String in ["zh","en"]:
		for kind:String in ["9x16","16x9"]:
			var key:String = "%s_%s" % [locale,kind]
			var canvas:Image = _compose_portrait(frame,portrait_spot,job.titles[key]) if kind == "9x16" else _compose_landscape(frame,job.layouts[kind],job.titles[key])
			canvas.convert(Image.FORMAT_RGB8)
			var path:String = String(job.folder).path_join(NamingScript.COVERS[key])
			var result:Error = canvas.save_jpg(path,JPG_QUALITY)
			if result != OK:
				job.error = "封面写入失败（%s）：%s" % [error_string(result),path]
				return
			job.written[key] = path


## 竖版标题位置：在整幅画面里随机挑一个不挡角色的地方；地图外的空处比压在场地上更常被选中，
## 压在地图边线上的最少。实在没有空处就挑挡得最少的。
static func _pick_portrait_spot(layout:Dictionary, titles:Array, rng:RandomNumberGenerator) -> Rect2:
	var box:Vector2 = layout.title.size
	var size := Vector2.ZERO # 能同时放下中、英文标题的范围
	for title:Image in titles:
		var scale_amount:float = minf(box.x / title.get_width(),box.y / title.get_height())
		size = size.max(Vector2(title.get_size()) * scale_amount)
	var map_px:Rect2 = layout.map
	var xs:Array = [(PORTRAIT.x - size.x) * 0.5]
	if size.x < box.x * 0.85: xs.append_array([50.0,PORTRAIT.x - 50.0 - size.x])
	var clear:Array = []
	var weights:Array = []
	var fallback := Rect2()
	var least:float = INF
	var y:float = 90.0
	while y <= PORTRAIT.y - 90.0 - size.y:
		for x:float in xs:
			var spot := Rect2(x,y,size.x,size.y)
			var covered:float = 0.0
			for avoid:Rect2 in layout.avoid: covered += spot.intersection(avoid).get_area()
			if covered <= 0.0:
				clear.append(spot)
				weights.append(1.0 if not spot.intersects(map_px) else (0.6 if map_px.encloses(spot) else 0.25))
			elif covered < least:
				least = covered
				fallback = spot
		y += 24.0
	if clear.is_empty(): return fallback if fallback.has_area() else Rect2(Vector2((PORTRAIT.x - size.x) * 0.5,140.0),size)
	return clear[rng.rand_weighted(PackedFloat32Array(weights))]


static func _compose_portrait(frame:Image, spot:Rect2, title:Image) -> Image:
	var canvas:Image = frame.duplicate()
	if canvas.get_size() != PORTRAIT: canvas.resize(PORTRAIT.x,PORTRAIT.y,Image.INTERPOLATE_BILINEAR)
	# 标题背后一道上下渐隐的暗带，立体字更醒目。
	_shade_band(canvas,int(spot.position.y - 90.0),int(spot.end.y + 90.0),0.5)
	_place_title(canvas,title,spot)
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
	# 标题在留给它的一栏/一条里等比放大，沿长边方向按随机锚点放（高/中/低 或 左/中/右）。
	var area:Rect2 = layout.title
	var scale_amount:float = minf(area.size.x / title.get_width(),area.size.y / title.get_height())
	var size := Vector2(title.get_size()) * scale_amount
	var anchor:float = float(layout.anchor)
	var spot := Rect2(area.position + (area.size - size) * (Vector2(0.5,anchor) if layout.vertical else Vector2(anchor,0.5)),size)
	_place_title(canvas,title,spot)
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


## 水平暗带：中间最暗，向上下两边平滑淡出。
static func _shade_band(canvas:Image, top:int, bottom:int, strength:float) -> void:
	var height:int = bottom - top
	if height <= 1: return
	var ramp := Image.create(1,height,false,Image.FORMAT_RGBA8)
	for y:int in range(height):
		var amount:float = 1.0 - absf(float(y) / float(height - 1) * 2.0 - 1.0)
		ramp.set_pixel(0,y,Color(0,0,0,strength * amount * amount * (3.0 - 2.0 * amount)))
	ramp.resize(canvas.get_width(),height,Image.INTERPOLATE_BILINEAR)
	canvas.blend_rect(ramp,Rect2i(0,0,canvas.get_width(),height),Vector2i(0,top))
