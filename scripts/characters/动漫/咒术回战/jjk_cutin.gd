extends CanvasLayer
## 大招过场特写（纯视觉，不暂停战斗）：上下黑边、斜向色带、速度线、角色脸部大特写、招式名。
var life:float = 1.25
var t:float = 0.0
var face:Texture2D
var title:String = ""
var subtitle:String = ""
var color:Color = Color(0.4,0.6,1.0)
var from_right:bool = false
var _draw_node:Node2D
var _seed:int = 0

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
	var appear:float = _oc(t / 0.16)
	var leave:float = clampf((t - (life - 0.22)) / 0.22,0.0,1.0)
	var open:float = appear * (1.0 - leave * leave)
	# 上下黑边
	var bar:float = h * 0.11 * open
	ci.draw_rect(Rect2(0,0,w,bar),Color(0,0,0,0.92))
	ci.draw_rect(Rect2(0,h - bar,w,bar),Color(0,0,0,0.92))
	# 斜向色带
	var bh:float = h * 0.30 * open
	if bh < 1.0: return
	var center:Vector2 = Vector2(w * 0.5,h * 0.5)
	var ang:float = -0.12 if not from_right else 0.12
	ci.draw_set_transform(center,ang,Vector2.ONE)
	var reveal:float = _oc(t / 0.22)
	var x0:float = -w
	var x1:float = lerpf(-w,w,reveal)
	if from_right:
		x0 = lerpf(w,-w,reveal)
		x1 = w
	var dark:Color = Color(color.darkened(0.75),0.94)
	var mid:Color = Color(color.darkened(0.25),0.94)
	ci.draw_polygon(PackedVector2Array([Vector2(x0,-bh * 0.5),Vector2(x1,-bh * 0.5),Vector2(x1,0),Vector2(x0,0)]),PackedColorArray([dark,dark,mid,mid]))
	ci.draw_polygon(PackedVector2Array([Vector2(x0,0),Vector2(x1,0),Vector2(x1,bh * 0.5),Vector2(x0,bh * 0.5)]),PackedColorArray([mid,mid,dark,dark]))
	ci.draw_line(Vector2(x0,-bh * 0.5),Vector2(x1,-bh * 0.5),Color(1,1,1,0.9),3.0)
	ci.draw_line(Vector2(x0,bh * 0.5),Vector2(x1,bh * 0.5),Color(1,1,1,0.9),3.0)
	# 速度线
	var rng:RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed
	for i:int in 42:
		var speed:float = rng.randf_range(1.6,3.2) * w
		var ln:float = rng.randf_range(0.08,0.3) * w
		var y:float = rng.randf_range(-0.48,0.48) * bh
		var x:float = fposmod(rng.randf() * 2.0 * w - t * speed * (1.0 if not from_right else -1.0),2.0 * w) - w
		var a:float = rng.randf_range(0.15,0.55)
		ci.draw_line(Vector2(x,y),Vector2(x + ln,y),Color(1,1,1,a),rng.randf_range(1.0,3.0))
	# 脸部特写
	if face != null:
		var fs:float = bh * 1.18
		var drift:float = lerpf(0.0,-0.05,t / life) * w * (1.0 if not from_right else -1.0)
		var fx:float = (-w * 0.26 if not from_right else w * 0.26) + drift
		var slide:float = (1.0 - _oc(t / 0.28)) * w * 0.4 * (-1.0 if not from_right else 1.0)
		var r:Rect2 = Rect2(Vector2(fx + slide - fs * 0.5,-fs * 0.5),Vector2(fs,fs))
		ci.draw_rect(r.grow(6.0),Color(1,1,1,0.95))
		ci.draw_rect(r.grow(10.0),Color(0,0,0,0.9),false,4.0)
		ci.draw_texture_rect(face,r,false)
	# 招式名
	var font:Font = ThemeDB.fallback_font
	var fsize:int = int(clampf(h * 0.075,18,72))
	var tw:float = font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,fsize).x
	# 长招式名（如“八握剑异戒神将 魔虚罗”）自动缩小，保证完整显示在横幅内。
	var max_w:float = w * 0.4
	if tw > max_w and tw > 0.0:
		fsize = maxi(12,int(fsize * max_w / tw))
		tw = font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,fsize).x
	var tx:float = (w * 0.08 if not from_right else -w * 0.08 - tw)
	var tslide:float = (1.0 - _oc((t - 0.08) / 0.3)) * w * 0.5 * (1.0 if not from_right else -1.0)
	var tpos:Vector2 = Vector2(tx + tslide - (0.0 if not from_right else 0.0),fsize * 0.15)
	ci.draw_string_outline(font,tpos,title,HORIZONTAL_ALIGNMENT_LEFT,-1,fsize,10,Color(0,0,0,0.95))
	ci.draw_string(font,tpos,title,HORIZONTAL_ALIGNMENT_LEFT,-1,fsize,Color(1,1,1))
	if not subtitle.is_empty():
		var ss:int = int(fsize * 0.45)
		var stw:float = font.get_string_size(subtitle,HORIZONTAL_ALIGNMENT_LEFT,-1,ss).x
		var sx:float = tpos.x if not from_right else tpos.x + tw - stw
		ci.draw_string_outline(font,Vector2(sx,tpos.y + ss * 1.5),subtitle,HORIZONTAL_ALIGNMENT_LEFT,-1,ss,6,Color(0,0,0,0.9))
		ci.draw_string(font,Vector2(sx,tpos.y + ss * 1.5),subtitle,HORIZONTAL_ALIGNMENT_LEFT,-1,ss,color.lightened(0.5))
	ci.draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
	# 开场/收尾闪光
	var fl:float = maxf(1.0 - t / 0.1,0.0) * 0.7 + (leave * (1.0 - leave) * 4.0) * 0.25
	if fl > 0.0: ci.draw_rect(Rect2(Vector2.ZERO,size),Color(1,1,1,fl))
