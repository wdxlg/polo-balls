extends CanvasLayer
## 大招过场特写（纯视觉，不暂停战斗）：动画标题卡风格——黑边、白底斜带墨色速度线、粗黑框脸部特写、逐字盖章的招式名。
## 所有运动按 12fps 抽帧，保持作画感。
var life:float = 1.25
var t:float = 0.0
var face:Texture2D
var title:String = ""
var subtitle:String = ""
var color:Color = Color(0.4,0.6,1.0)
var from_right:bool = false
var _draw_node:Node2D
var _seed:int = 0

const INK:Color = Color(0.04,0.03,0.05)
const PAPER:Color = Color(0.97,0.96,0.94)

func _ready() -> void:
	layer = 95
	_seed = randi()
	_draw_node = Node2D.new()
	_draw_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_draw_node)
	_draw_node.draw.connect(_on_draw)

func _process(delta:float) -> void:
	t += delta
	if t >= life:
		queue_free()
		return
	_draw_node.queue_redraw()

static func _oc(x:float) -> float:
	x = clampf(x,0.0,1.0)
	return 1.0 - pow(1.0 - x,3.0)

func _on_draw() -> void:
	var ci:Node2D = _draw_node
	var vp:Viewport = get_viewport()
	var size:Vector2 = vp.get_visible_rect().size if vp != null else Vector2(800,600)
	var w:float = size.x
	var h:float = size.y
	var ts:float = floor(t * 12.0) / 12.0
	var dirx:float = 1.0 if not from_right else -1.0
	# 开场两帧：全屏白闪 → 墨色反相
	if t < 1.0 / 24.0:
		ci.draw_rect(Rect2(Vector2.ZERO,size),PAPER)
		return
	var appear:float = _oc(ts / 0.17)
	var leave:float = clampf((ts - (life - 0.25)) / 0.25,0.0,1.0)
	var open:float = appear * (1.0 - leave * leave)
	var bar:float = h * 0.12 * open
	ci.draw_rect(Rect2(0,0,w,bar),INK)
	ci.draw_rect(Rect2(0,h - bar,w,bar),INK)
	var bh:float = h * 0.32 * open
	if bh < 2.0: return
	var shake:Vector2 = Vector2.ZERO
	if ts < 0.2:
		var sr:RandomNumberGenerator = RandomNumberGenerator.new()
		sr.seed = _seed + int(ts * 12.0)
		shake = Vector2(sr.randf_range(-1,1),sr.randf_range(-1,1)) * h * 0.012 * (1.0 - ts / 0.2)
	var center:Vector2 = Vector2(w * 0.5,h * 0.5) + shake
	var ang:float = -0.12 * dirx
	ci.draw_set_transform(center,ang,Vector2.ONE)
	var reveal:float = _oc(ts / 0.2)
	var x0:float = -w
	var x1:float = lerpf(-w,w,reveal)
	if from_right:
		x0 = lerpf(w,-w,reveal)
		x1 = w
	var top:float = -bh * 0.5
	var bot:float = bh * 0.5
	# 墨线外框 + 角色色边条 + 白纸底
	ci.draw_rect(Rect2(x0,top - 9.0,x1 - x0,bh + 18.0),INK)
	ci.draw_rect(Rect2(x0,top - 5.0,x1 - x0,5.0),color)
	ci.draw_rect(Rect2(x0,bot,x1 - x0,5.0),color)
	ci.draw_rect(Rect2(x0,top,x1 - x0,bh),PAPER)
	# 墨色速度线（两头尖的楔形，按帧重掷）
	var rng:RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed + int(ts * 12.0) * 7919
	for i:int in 36:
		var y:float = rng.randf_range(top + 4.0,bot - 4.0)
		var ln:float = rng.randf_range(0.12,0.45) * w
		var x:float = rng.randf_range(x0,x1 - ln * 0.3)
		var th:float = rng.randf_range(1.0,4.5)
		var xe:float = minf(x + ln,x1)
		if xe - x < 8.0: continue
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x,y),Vector2(lerpf(x,xe,0.7),y - th),Vector2(xe,y),Vector2(lerpf(x,xe,0.7),y + th)]),INK)
	# 脸部特写：粗墨框 + 色块投影
	if face != null:
		var fs:float = bh * 1.22
		var drift:float = lerpf(0.0,-0.04,ts / life) * w * dirx
		var fx:float = -w * 0.26 * dirx + drift
		var slide:float = (1.0 - _oc(ts / 0.25)) * w * 0.45 * -dirx
		var r:Rect2 = Rect2(Vector2(fx + slide - fs * 0.5,-fs * 0.5),Vector2(fs,fs))
		ci.draw_rect(Rect2(r.position + Vector2(10.0 * dirx,10.0),r.size).grow(8.0),color.darkened(0.35))
		ci.draw_rect(r.grow(8.0),INK)
		ci.draw_rect(r.grow(4.0),PAPER)
		ci.draw_texture_rect(face,r,false)
	# 招式名：逐字盖章（每字先放大 1.6 倍再落定），黑字白描边 + 色块硬投影
	var font:Font = ThemeDB.fallback_font
	var fsize:int = int(clampf(h * 0.08,18,76))
	var tw:float = font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,fsize).x
	var max_w:float = w * 0.4
	if tw > max_w and tw > 0.0:
		fsize = maxi(12,int(fsize * max_w / tw))
		tw = font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,fsize).x
	var tx:float = w * 0.06 if not from_right else -w * 0.06 - tw
	var base:Vector2 = Vector2(tx,fsize * 0.3)
	var cx:float = 0.0
	for i:int in title.length():
		var ch:String = title[i]
		var cw:float = font.get_string_size(ch,HORIZONTAL_ALIGNMENT_LEFT,-1,fsize).x
		var ct:float = ts - 0.1 - i * 0.045
		if ct >= 0.0:
			var pop:float = 1.0 + 0.6 * maxf(0.0,1.0 - ct / 0.09)
			var cs:int = int(fsize * pop)
			var cp:Vector2 = base + Vector2(cx + cw * 0.5 - cw * 0.5 * pop,(pop - 1.0) * fsize * 0.35)
			ci.draw_string(font,cp + Vector2(5,5),ch,HORIZONTAL_ALIGNMENT_LEFT,-1,cs,color.darkened(0.2))
			ci.draw_string_outline(font,cp,ch,HORIZONTAL_ALIGNMENT_LEFT,-1,cs,12,PAPER)
			ci.draw_string_outline(font,cp,ch,HORIZONTAL_ALIGNMENT_LEFT,-1,cs,4,INK)
			ci.draw_string(font,cp,ch,HORIZONTAL_ALIGNMENT_LEFT,-1,cs,INK)
		cx += cw
	if not subtitle.is_empty() and ts > 0.2:
		var ss:int = int(fsize * 0.42)
		var stw:float = font.get_string_size(subtitle,HORIZONTAL_ALIGNMENT_LEFT,-1,ss).x
		var sx:float = base.x if not from_right else base.x + tw - stw
		var sp:Vector2 = Vector2(sx,base.y + ss * 1.6)
		ci.draw_rect(Rect2(sp + Vector2(-6,-ss * 0.95),Vector2(stw + 12,ss * 1.25)),INK)
		ci.draw_string(font,sp,subtitle,HORIZONTAL_ALIGNMENT_LEFT,-1,ss,color.lightened(0.35))
	ci.draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
	# 收尾一帧白闪
	if leave > 0.0 and leave < 0.2:
		ci.draw_rect(Rect2(Vector2.ZERO,size),Color(PAPER,0.8))
