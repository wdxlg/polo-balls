extends Control
## 我的世界标题立体字，按 honghemc / cube-3d-text 的生成方式：
## 像素字体按像素格挤出成真正的 3D 网格，透视相机正对着拍——正面上亮下暗的阶梯渐变带颗粒质感与边缘倒角，
## 上/左/右侧面深色，底面由前往后变暗，背后一圈放大的描边体。面直接上色不打光，不受场景环境影响。
## 含中文的行用 Fusion Pixel 12px，纯英文/数字行用 Mojangles（方块感更强），按同一字高对齐。
## 不注册 class_name，用 load() 取脚本：
##   var title = load(PATH).new()
##   title.setup([{"text":"烈焰人","style":Color.RED},{"text":"VS","style":"gold","scale":0.62}])
##   一行多色：{"segments":[{"text":"烈焰人","style":Color.RED},{"text":"VS","style":"gold","scale":0.7},{"text":"骷髅","style":Color.BLUE}]}
##   parent.add_child(title)   # 在自己的 size 里按比例居中绘制
## 行 style："stone"（原版标题灰石）/ "gold"（JAVA EDITION 金）/ Color（按颜色生成整套配色）。
## 选项：render_width（渲染宽度，默认 1280）。

const CJK_FONT:String = "res://fonts/fusion-pixel-12px-proportional-zh_hans.otf.woff2"
const LATIN_FONT:String = "res://fonts/Mojangles.ttf"
const CJK_SIZE:int = 12
const LATIN_SIZE:int = 8
## 世界单位：一个字高（em）= 12。
const EM:float = 12.0
const DEPTH_EM:float = 0.5
## 描边半格粗（在 2 倍细分的格子上外扩 1 格）。
const OUTLINE_CELLS:float = 0.5
const LINE_GAP_EM:float = 0.2
## 同一行几段之间的间距。
const SEGMENT_GAP_EM:float = 0.3
## 相机距离 / 画面宽度：越小透视越强（cube-3d-text 默认约 0.8）。
const CAMERA_DISTANCE_RATIO:float = 0.7
## 每行绕自己的水平中线往后仰的角度：每一行都露出底面，像原版标题从下往上看。
const TILT_DEGREES:float = 16.0
## 正面质感：每个字体像素细分的小格数、颗粒明暗幅度、侧面颗粒、边缘倒角、斜向光带（单位：小格）。
const TEXELS:int = 2
const FRONT_GRAIN:float = 0.11
const SIDE_GRAIN:float = 0.12
const BEVEL_TOP:float = 0.42
const BEVEL_LEFT:float = 0.16
const BEVEL_BOTTOM:float = 0.24
const BEVEL_RIGHT:float = 0.1
const SHINE_PERIOD:int = 26
const SHINE_WIDTH:int = 5
const SHINE_AMOUNT:float = 0.1

const GOLD:Dictionary = {"front_top":Color("ffd07b"),"front_bottom":Color("ffaa00"),"side":Color("553800"),"down_front":Color("a56c00"),"down_back":Color("553800"),"outline":Color("291a00")}
const STONE:Dictionary = {"front_top":Color("ffffff"),"front_bottom":Color("a8a8a8"),"side":Color("3c3c3c"),"down_front":Color("727272"),"down_back":Color("3c3c3c"),"outline":Color("161616")}

## 新画面组装好、换上之后发出。
signal built

## 段网格缓存（文字 + 缩放 + 配色 → 正文/描边网格），本体与录像副本共用；字形栅格同样缓存。
const MESH_CACHE_LIMIT:int = 96
static var _mesh_cache:Dictionary = {}
static var _mask_cache:Dictionary = {}
static var _materials:Array = []

var viewport:SubViewport
var _task_id:int = -1
var _job:Dictionary = {}
var _lines:Array = []
var _options:Dictionary = {}
var _aspect:float = 4.0
## 竖直对齐：0 顶、0.5 居中、1 贴底。
var valign:float = 0.5

static func style_colors(style:Variant) -> Dictionary:
	if style is Color:
		var c:Color = style
		return {"front_top":c.lerp(Color.WHITE,0.6),"front_bottom":c.lightened(0.08),"side":c.darkened(0.74),"down_front":c.darkened(0.5),"down_back":c.darkened(0.78),"outline":c.darkened(0.88)}
	return GOLD if str(style) == "gold" else STONE

func setup(lines:Array,options:Dictionary = {}) -> void:
	_lines = lines.duplicate(true)
	_options = options.duplicate()
	if is_inside_tree(): _build()

func texture() -> Texture2D:
	return viewport.get_texture() if viewport != null else null

func _ready() -> void:
	set_process(_task_id >= 0)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	resized.connect(queue_redraw)
	if viewport == null: _build()

func _draw() -> void:
	var tex:Texture2D = texture()
	if tex == null or size.x <= 0.0 or size.y <= 0.0: return
	draw_texture_rect(tex,content_rect(),false)

## 实际画出字块的矩形（本地坐标，按比例适配 size，横向居中、竖直按 valign）。
func content_rect() -> Rect2:
	var fit:Vector2 = Vector2(size.x,size.x / _aspect)
	if fit.y > size.y: fit = Vector2(size.y * _aspect,size.y)
	return Rect2(Vector2((size.x - fit.x) * 0.5,(size.y - fit.y) * valign),fit)

static func _has_cjk(text:String) -> bool:
	for i:int in range(text.length()):
		if text.unicode_at(i) >= 0x2E80: return true
	return false

## 把字形轮廓（含二次/三次曲线控制点）展开成折线。
static func _flatten(points:PackedVector3Array,from:int,to:int,offset:Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n:int = to - from + 1
	if n < 2: return out
	var start:int = 0
	while start < n and int(points[from + start].z) != 1: start += 1
	if start >= n: start = 0
	var p0 := Vector2(points[from + start].x,points[from + start].y)
	out.append(p0 + offset)
	var cur:Vector2 = p0
	var i:int = 1
	while i <= n:
		var p:Vector3 = points[from + (start + i) % n]
		var pv := Vector2(p.x,p.y)
		if int(p.z) == 1:
			out.append(pv + offset); cur = pv; i += 1
		elif int(p.z) == 0:
			var nxt:Vector3 = points[from + (start + i + 1) % n]
			var end := Vector2(nxt.x,nxt.y)
			if int(nxt.z) == 1: i += 2
			else:
				end = (pv + end) * 0.5; i += 1
			for k:int in range(1,5):
				var t:float = k / 4.0
				out.append(cur.lerp(pv,t).lerp(pv.lerp(end,t),t) + offset)
			cur = end
		else:
			var c2:Vector3 = points[from + (start + i + 1) % n]
			var e3:Vector3 = points[from + (start + i + 2) % n]
			var end3 := Vector2(e3.x,e3.y)
			for k:int in range(1,7):
				out.append(cur.bezier_interpolate(pv,Vector2(c2.x,c2.y),end3,k / 6.0) + offset)
			cur = end3; i += 3
	return out

## 文字 → 像素格：{w, h, cells(行优先，1=有字), unit(每格世界单位)}。
static func rasterize(text:String) -> Dictionary:
	var cjk:bool = _has_cjk(text)
	var font:Font = load(CJK_FONT if cjk else LATIN_FONT)
	var font_size:int = CJK_SIZE if cjk else LATIN_SIZE
	var ts:TextServer = TextServerManager.get_primary_interface()
	var shaped:RID = ts.create_shaped_text()
	ts.shaped_text_add_string(shaped,text,font.get_rids(),font_size)
	var glyphs:Array = ts.shaped_text_get_glyphs(shaped)
	var ascent:int = int(round(font.get_ascent(font_size)))
	var height:int = ascent + int(round(font.get_descent(font_size)))
	var polys:Array = []
	var pen:float = 0.0
	for g:Dictionary in glyphs:
		var offset:Vector2 = g.get("offset",Vector2.ZERO)
		var rid:RID = g.get("font_rid",RID())
		if rid.is_valid():
			var data:Dictionary = ts.font_get_glyph_contours(rid,font_size,int(g.get("index",0)))
			var points:PackedVector3Array = data.get("points",PackedVector3Array())
			var from:int = 0
			var glyph:Array = []
			for end:int in data.get("contours",PackedInt32Array()):
				glyph.append(_flatten(points,from,end,Vector2(pen,0.0) + offset))
				from = end + 1
			if not glyph.is_empty(): polys.append(glyph)
		pen += float(g.get("advance",0.0)) * maxi(int(g.get("repeat",1)),1)
	ts.free_rid(shaped)
	var width:int = maxi(int(ceil(pen)),1)
	var cells := PackedByteArray()
	cells.resize(width * height)
	for glyph:Array in polys:
		var lo:float = INF
		var hi:float = -INF
		for poly:PackedVector2Array in glyph:
			for v:Vector2 in poly:
				lo = minf(lo,v.x); hi = maxf(hi,v.x)
		for row:int in range(height):
			var yc:float = row + 0.5 - ascent
			var hits:Array[Vector2] = []
			for poly:PackedVector2Array in glyph:
				var count:int = poly.size()
				for k:int in range(count):
					var a:Vector2 = poly[k]
					var b:Vector2 = poly[(k + 1) % count]
					if (a.y <= yc and b.y > yc) or (b.y <= yc and a.y > yc):
						hits.append(Vector2(a.x + (yc - a.y) * (b.x - a.x) / (b.y - a.y),1.0 if b.y > a.y else -1.0))
			if hits.is_empty(): continue
			hits.sort_custom(func(p:Vector2,q:Vector2) -> bool: return p.x < q.x)
			var winding:float = 0.0
			var h:int = 0
			for col:int in range(maxi(int(floor(lo)),0),mini(int(ceil(hi)) + 1,width)):
				var xc:float = col + 0.5
				while h < hits.size() and hits[h].x < xc:
					winding += hits[h].y; h += 1
				if winding != 0.0: cells[row * width + col] = 1
	return {"w":width,"h":height,"cells":cells,"unit":EM / float(font_size)}

## 描边体：格子 2 倍细分后向外扩 1 个细格（= 半格），四周各多出 1 个细格。
static func _outline_mask(mask:Dictionary) -> Dictionary:
	var sw:int = int(mask.w)
	var w:int = sw * 2 + 2
	var h:int = int(mask.h) * 2 + 2
	var src:PackedByteArray = mask.cells
	var cells := PackedByteArray()
	cells.resize(w * h)
	for y:int in range(int(mask.h)):
		for x:int in range(sw):
			if src[y * sw + x] == 0: continue
			for dy:int in range(4):
				for dx:int in range(4):
					cells[(y * 2 + dy) * w + x * 2 + dx] = 1
	return {"w":w,"h":h,"cells":cells,"unit":float(mask.unit) * 0.5}

static func _filled(mask:Dictionary,x:int,y:int) -> bool:
	return x >= 0 and y >= 0 and x < int(mask.w) and y < int(mask.h) and (mask.cells as PackedByteArray)[y * int(mask.w) + x] != 0

static func _quad(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3,d:Vector3,ca:Color,cb:Color,cc:Color,cd:Color) -> void:
	for pair:Array in [[a,ca],[b,cb],[c,cc],[a,ca],[c,cc],[d,cd]]:
		st.set_color(pair[1]); st.add_vertex(pair[0])

## 一块像素格挤出：正面 + 四周侧面（相机在正前方，看不到背面，不生成）。
## origin 是格子左上角的世界坐标，cell 每格边长，depth 挤出厚度。
static func _extrude(st:SurfaceTool,mask:Dictionary,origin:Vector2,cell:float,depth:float,colors:Dictionary,ink_top:float,ink_bottom:float,flat:Color = Color(0,0,0,0)) -> void:
	var w:int = int(mask.w)
	var h:int = int(mask.h)
	var single:bool = flat.a > 0.0
	var pos := func(x:float,y:float,z:float) -> Vector3: return Vector3(origin.x + x * cell,origin.y - y * cell,z)
	var grad := func(y:float) -> Color:
		if single: return flat
		return (colors.front_top as Color).lerp(colors.front_bottom,clampf((y - ink_top) / maxf(ink_bottom - ink_top,0.001),0.0,1.0))
	var side:Color = flat if single else colors.side
	var down_front:Color = flat if single else colors.down_front
	var down_back:Color = flat if single else colors.down_back
	if not single:
		_textured_front(st,mask,pos,grad)
	else:
		for y:int in range(h):
			var x:int = 0
			while x < w:
				if not _filled(mask,x,y):
					x += 1; continue
				var x1:int = x
				while x1 < w and _filled(mask,x1,y): x1 += 1
				_quad(st,pos.call(x,y,0.0),pos.call(x1,y,0.0),pos.call(x1,y + 1,0.0),pos.call(x,y + 1,0.0),flat,flat,flat,flat)
				x = x1
	for y:int in range(h):
		for edge:int in [-1,1]:
			var x:int = 0
			while x < w:
				if not (_filled(mask,x,y) and not _filled(mask,x,y + edge)):
					x += 1; continue
				var x1:int = x + 1
				if single:
					while x1 < w and _filled(mask,x1,y) and not _filled(mask,x1,y + edge): x1 += 1
				var yy:float = float(y) if edge < 0 else float(y + 1)
				var front_color:Color = side if edge < 0 else down_front
				var back_color:Color = side if edge < 0 else down_back
				if not single:
					var grain:float = _hash(x * 7 + edge,y * 5) * SIDE_GRAIN
					front_color = _shade(front_color,grain)
					back_color = _shade(back_color,grain)
				_quad(st,pos.call(x,yy,0.0),pos.call(x1,yy,0.0),pos.call(x1,yy,-depth),pos.call(x,yy,-depth),front_color,front_color,back_color,back_color)
				x = x1
	for x:int in range(w):
		for edge:int in [-1,1]:
			var y:int = 0
			while y < h:
				if not (_filled(mask,x,y) and not _filled(mask,x + edge,y)):
					y += 1; continue
				var y1:int = y + 1
				if single:
					while y1 < h and _filled(mask,x,y1) and not _filled(mask,x + edge,y1): y1 += 1
				var xx:float = float(x) if edge < 0 else float(x + 1)
				var wall:Color = side if single else _shade(side,_hash(x * 5 + edge,y * 7 + 3) * SIDE_GRAIN)
				_quad(st,pos.call(xx,y,0.0),pos.call(xx,y1,0.0),pos.call(xx,y1,-depth),pos.call(xx,y,-depth),wall,wall,wall,wall)
				y = y1

## 正面质感（参照原版标题与 cube-3d-text 的纹理/高光叠加）：每个字体像素再分 TEXELS×TEXELS 个小格，
## 每格单色——阶梯渐变 + 固定哈希的颗粒明暗 + 上亮下暗的边缘倒角 + 斜向光带。哈希固定，同一文字每次一样。
static func _textured_front(st:SurfaceTool,mask:Dictionary,pos:Callable,grad:Callable) -> void:
	var step:float = 1.0 / float(TEXELS)
	for y:int in range(int(mask.h)):
		for x:int in range(int(mask.w)):
			if not _filled(mask,x,y): continue
			var open_up:bool = not _filled(mask,x,y - 1)
			var open_down:bool = not _filled(mask,x,y + 1)
			var open_left:bool = not _filled(mask,x - 1,y)
			var open_right:bool = not _filled(mask,x + 1,y)
			var cell_grain:float = _hash(x,y)
			for sy:int in range(TEXELS):
				for sx:int in range(TEXELS):
					var gx:int = x * TEXELS + sx
					var gy:int = y * TEXELS + sy
					var c:Color = grad.call(float(y) + (float(sy) + 0.5) * step)
					c = _shade(c,(_hash(gx + 101,gy + 57) * 0.65 + cell_grain * 0.35) * FRONT_GRAIN)
					if posmod(gx + gy,SHINE_PERIOD) < SHINE_WIDTH: c = c.lerp(Color.WHITE,SHINE_AMOUNT)
					if sy == 0 and open_up: c = c.lerp(Color.WHITE,BEVEL_TOP)
					elif sx == 0 and open_left: c = c.lerp(Color.WHITE,BEVEL_LEFT)
					# 一格细的笔画只留高光，不再压暗另一边，免得汉字细笔画变成明暗条纹。
					if sy == TEXELS - 1 and open_down and not open_up: c = c.darkened(BEVEL_BOTTOM)
					elif sx == TEXELS - 1 and open_right and not open_left: c = c.darkened(BEVEL_RIGHT)
					var x0:float = float(x) + float(sx) * step
					var y0:float = float(y) + float(sy) * step
					_quad(st,pos.call(x0,y0,0.0),pos.call(x0 + step,y0,0.0),pos.call(x0 + step,y0 + step,0.0),pos.call(x0,y0 + step,0.0),c,c,c,c)

## 固定整数哈希 → [-1, 1]。
static func _hash(x:int,y:int) -> float:
	var h:int = (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 32767.5 - 1.0

## amount > 0 提亮，< 0 压暗。
static func _shade(c:Color,amount:float) -> Color:
	return c.lightened(amount) if amount > 0.0 else c.darkened(-amount)

static func _ink_rows(mask:Dictionary) -> Vector2:
	var top:int = -1
	var bottom:int = -1
	for y:int in range(int(mask.h)):
		for x:int in range(int(mask.w)):
			if _filled(mask,x,y):
				if top < 0: top = y
				bottom = y + 1
				break
	return Vector2(maxi(top,0),maxi(bottom,1))

static func _make_material(priority:int,depth_test:bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 描边先画、不写深度也不做深度测试；正文后画、自己做深度——正文永远盖在描边上（同 three.js 的做法）。
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = priority
	mat.no_depth_test = not depth_test
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS if depth_test else BaseMaterial3D.DEPTH_DRAW_DISABLED
	return mat

## 先在主线程排版（字形栅格有缓存），缺的段网格交给后台线程生成，期间继续显示旧画面；
## 全部就绪后在主线程组装新视口再换上，主线程只做很轻的组装。
func _build() -> void:
	if _task_id >= 0: return # 后台任务完成后会按最新的行重新排版。
	var plan:Dictionary = _plan()
	if plan.parts.is_empty(): return
	var missing:Array = []
	var queued:Dictionary = {}
	for part:Dictionary in plan.parts:
		if _mesh_cache.has(part.key) or queued.has(part.key): continue
		queued[part.key] = true
		missing.append(part.duplicate())
	if missing.is_empty():
		_assemble(plan)
		return
	_job = {"parts":missing}
	_task_id = WorkerThreadPool.add_task(_run_job.bind(_job),false,"mc_title_mesh")
	set_process(true)

func is_busy() -> bool:
	return _task_id >= 0

func _process(_delta:float) -> void:
	if _task_id < 0 or not WorkerThreadPool.is_task_completed(_task_id): return
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	set_process(false)
	_store(_job)
	_job = {}
	_build()

func _notification(what:int) -> void:
	if what == NOTIFICATION_PREDELETE and _task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1

## 后台线程：只做纯计算（挤出网格数组），不碰场景树。
static func _run_job(job:Dictionary) -> void:
	for part:Dictionary in job.parts:
		var mask:Dictionary = part.mask
		var cell:float = part.cell
		var ink:Vector2 = part.ink
		var origin := Vector2(0.0,ink.x * cell + (ink.y - ink.x) * cell * 0.5)
		var main := SurfaceTool.new()
		main.begin(Mesh.PRIMITIVE_TRIANGLES)
		_extrude(main,mask,origin,cell,part.depth,part.colors,ink.x,ink.y)
		part["main_arrays"] = main.commit_to_arrays()
		var rim := SurfaceTool.new()
		rim.begin(Mesh.PRIMITIVE_TRIANGLES)
		_extrude(rim,_outline_mask(mask),origin + Vector2(-OUTLINE_CELLS * cell,OUTLINE_CELLS * cell),cell * 0.5,part.depth,part.colors,0.0,1.0,part.colors.outline)
		part["rim_arrays"] = rim.commit_to_arrays()

static func _store(job:Dictionary) -> void:
	if _mesh_cache.size() + (job.parts as Array).size() > MESH_CACHE_LIMIT: _mesh_cache.clear()
	for part:Dictionary in job.parts:
		if not part.has("main_arrays"): continue
		var entry:Dictionary = {}
		for kind:String in ["main","rim"]:
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,part[kind + "_arrays"])
			entry[kind] = mesh
		_mesh_cache[part.key] = entry

static func _cached_mask(text:String) -> Dictionary:
	if not _mask_cache.has(text):
		if _mask_cache.size() > 256: _mask_cache.clear()
		_mask_cache[text] = rasterize(text)
	return _mask_cache[text]

static func _shared_material(rim:bool) -> StandardMaterial3D:
	if _materials.is_empty():
		_materials = [_make_material(0,false),_make_material(1,true)]
	return _materials[0] if rim else _materials[1]

## 排版：每段的网格键、栅格、位置，以及整块的范围。
func _plan() -> Dictionary:
	var parts_out:Array = []
	var y:float = 0.0
	var half_width:float = 0.0
	var top_y:float = -INF
	var bottom_y:float = INF
	for line:Dictionary in _lines:
		var line_scale:float = float(line.get("scale",1.0))
		var parts:Array = []
		var line_width:float = 0.0
		var line_height:float = 0.0
		var line_cell:float = 0.0
		var pieces:Array = line.get("segments",[line])
		for piece:Dictionary in pieces:
			var text:String = str(piece.get("text","")).strip_edges()
			if text.is_empty(): continue
			var scale_amount:float = line_scale * (float(piece.get("scale",1.0)) if line.has("segments") else 1.0)
			var mask:Dictionary = _cached_mask(text)
			var cell:float = float(mask.unit) * scale_amount
			var ink:Vector2 = _ink_rows(mask)
			var colors:Dictionary = style_colors(piece.get("style","stone"))
			if not parts.is_empty(): line_width += SEGMENT_GAP_EM * EM * line_scale
			parts.append({"key":"%s|%s|%s" % [text,scale_amount,str(colors)],"mask":mask,"cell":cell,"ink":ink,"x":line_width,"depth":DEPTH_EM * EM * scale_amount,"colors":colors})
			line_width += int(mask.w) * cell
			line_height = maxf(line_height,(ink.y - ink.x) * cell)
			line_cell = maxf(line_cell,cell)
		if parts.is_empty(): continue
		# 行距按实际有字的行算，字体上下留白不占地方。每段在自己的局部坐标里建（墨迹中线为 y=0），
		# 同一行的几段共用行中线、一起后仰。
		for part:Dictionary in parts:
			part["position"] = Vector3(-line_width * 0.5 + float(part.x),y - line_height * 0.5,0.0)
			parts_out.append(part)
		half_width = maxf(half_width,line_width * 0.5 + OUTLINE_CELLS * line_cell)
		top_y = maxf(top_y,y + OUTLINE_CELLS * line_cell)
		bottom_y = minf(bottom_y,y - line_height - OUTLINE_CELLS * line_cell)
		y -= line_height + LINE_GAP_EM * EM * line_scale
	return {"parts":parts_out,"half_width":half_width,"top_y":top_y,"bottom_y":bottom_y}

func _assemble(plan:Dictionary) -> void:
	var next := SubViewport.new()
	next.own_world_3d = true
	next.transparent_bg = true
	next.msaa_3d = Viewport.MSAA_4X
	next.render_target_update_mode = SubViewport.UPDATE_ONCE
	for part:Dictionary in plan.parts:
		var entry:Dictionary = _mesh_cache[part.key]
		for kind:String in ["rim","main"]:
			var mesh := MeshInstance3D.new()
			mesh.mesh = entry[kind]
			mesh.material_override = _shared_material(kind == "rim")
			mesh.position = part.position
			mesh.rotation.x = -deg_to_rad(TILT_DEGREES)
			next.add_child(mesh)
	# 画面：字块四周留一点边（后仰后行底会往前凸一点）。相机正对字块中心，透视但不裁切。
	var margin:float = EM * 0.45
	var top_y:float = plan.top_y
	var bottom_y:float = plan.bottom_y
	var view_w:float = float(plan.half_width) * 2.0 + margin * 2.0
	var view_h:float = (top_y - bottom_y) + margin * 2.0
	var center_y:float = (top_y + bottom_y) * 0.5
	var camera_y:float = center_y
	# 多行时字块高：按高度也拉远一些，免得最上/最下一行透视夸张到看不清字。
	var distance:float = maxf(view_w * CAMERA_DISTANCE_RATIO,view_h * 1.35)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0,camera_y,distance)
	var near:float = distance * 0.1
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.set_frustum(view_h * near / distance,Vector2(0.0,(center_y - camera_y) * near / distance),near,distance * 4.0)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	camera.environment = env
	next.add_child(camera)
	var aspect:float = view_w / view_h
	var render_width:int = int(_options.get("render_width",1280))
	next.size = Vector2i(render_width,maxi(int(render_width / aspect),8))
	add_child(next)
	if viewport != null: viewport.queue_free()
	viewport = next
	_aspect = aspect
	queue_redraw()
	built.emit()

