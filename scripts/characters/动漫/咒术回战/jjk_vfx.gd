extends RefCounted
## 咒术回战特效绘制库（纯视觉，静态）：柔光贴图、叠加混合材质、缓动曲线、闪电、锥形斩痕、
## 火焰轮廓、以及可复现（同种子各端一致）的轻量粒子系统。
## 只在 _draw 回调里使用；不结算任何伤害。

static var _glow:Texture2D
static var _glow_hard:Texture2D
static var _add_mat:CanvasItemMaterial

## 柔和的径向光斑（中心亮、边缘完全透明）。
static func glow_tex() -> Texture2D:
	if _glow == null:
		var g:Gradient = Gradient.new()
		g.offsets = PackedFloat32Array([0.0,0.18,0.45,0.75,1.0])
		g.colors = PackedColorArray([Color(1,1,1,1),Color(1,1,1,0.7),Color(1,1,1,0.25),Color(1,1,1,0.06),Color(1,1,1,0)])
		var t:GradientTexture2D = GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5,0.5)
		t.fill_to = Vector2(1.0,0.5)
		t.width = 128
		t.height = 128
		_glow = t
	return _glow

## 边缘较硬的光球（用于核心）。
static func core_tex() -> Texture2D:
	if _glow_hard == null:
		var g:Gradient = Gradient.new()
		g.offsets = PackedFloat32Array([0.0,0.55,0.8,1.0])
		g.colors = PackedColorArray([Color(1,1,1,1),Color(1,1,1,0.95),Color(1,1,1,0.35),Color(1,1,1,0)])
		var t:GradientTexture2D = GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5,0.5)
		t.fill_to = Vector2(1.0,0.5)
		t.width = 64
		t.height = 64
		_glow_hard = t
	return _glow_hard

static func add_material() -> CanvasItemMaterial:
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_mat

## 建立一个叠加混合的子画布，draw 回调接到 callback。
static func make_add_layer(parent:Node2D,callback:Callable,z:int = 0) -> Node2D:
	var n:Node2D = Node2D.new()
	n.name = "AddLayer"
	n.material = add_material()
	if z != 0:
		n.z_as_relative = true
		n.z_index = z
	parent.add_child(n)
	n.draw.connect(callback)
	return n

# ---------------------------------------------------------------- 缓动
static func out_cubic(x:float) -> float:
	x = clampf(x,0.0,1.0)
	return 1.0 - pow(1.0 - x,3.0)
static func out_expo(x:float) -> float:
	x = clampf(x,0.0,1.0)
	return 1.0 if x >= 1.0 else 1.0 - pow(2.0,-10.0 * x)
static func in_cubic(x:float) -> float:
	x = clampf(x,0.0,1.0)
	return x * x * x
static func in_out(x:float) -> float:
	x = clampf(x,0.0,1.0)
	return x * x * (3.0 - 2.0 * x)
static func out_back(x:float,s:float = 1.70158) -> float:
	x = clampf(x,0.0,1.0) - 1.0
	return x * x * ((s + 1.0) * x + s) + 1.0
## 0→1→0 的包络：前 a 段淡入，后 (1-b) 段淡出。
static func env(k:float,a:float = 0.1,b:float = 0.6) -> float:
	if k <= 0.0 or k >= 1.0: return 0.0
	if k < a: return k / a
	if k > b: return 1.0 - (k - b) / maxf(1.0 - b,0.0001)
	return 1.0
static func seg(k:float,a:float,b:float) -> float:
	return clampf((k - a) / maxf(b - a,0.0001),0.0,1.0)

# ---------------------------------------------------------------- 基本图元
static func glow(ci:CanvasItem,pos:Vector2,radius:float,color:Color) -> void:
	if radius <= 0.1 or color.a <= 0.003: return
	ci.draw_texture_rect(glow_tex(),Rect2(pos - Vector2(radius,radius),Vector2(radius,radius) * 2.0),false,color)

static func core(ci:CanvasItem,pos:Vector2,radius:float,color:Color) -> void:
	if radius <= 0.1 or color.a <= 0.003: return
	ci.draw_texture_rect(core_tex(),Rect2(pos - Vector2(radius,radius),Vector2(radius,radius) * 2.0),false,color)

## 沿线段拉长的柔光条。
static func streak(ci:CanvasItem,a:Vector2,b:Vector2,width:float,color:Color) -> void:
	var d:Vector2 = b - a
	var l:float = d.length()
	if l < 0.5 or width <= 0.1 or color.a <= 0.003: return
	ci.draw_set_transform((a + b) * 0.5,d.angle(),Vector2.ONE)
	ci.draw_texture_rect(glow_tex(),Rect2(Vector2(-l * 0.5 - width * 0.5,-width * 0.5),Vector2(l + width,width)),false,color)
	ci.draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

## 实心带状光束（中间亮）：多层叠加。
static func beam(ci:CanvasItem,a:Vector2,b:Vector2,width:float,color:Color,core_color:Color = Color(1,1,1)) -> void:
	streak(ci,a,b,width * 2.2,Color(color,color.a * 0.35))
	streak(ci,a,b,width * 1.1,Color(color,color.a * 0.7))
	ci.draw_line(a,b,Color(color,color.a * 0.85),width * 0.55,true)
	ci.draw_line(a,b,Color(core_color,color.a),maxf(1.0,width * 0.22),true)

## 锥形新月斩痕：两端尖、中间粗，可弯曲。reveal/erase 控制出现与消失的区段。
static func crescent(ci:CanvasItem,a:Vector2,b:Vector2,width:float,bulge:float,color:Color,reveal:float = 1.0,erase:float = 0.0,steps:int = 18) -> void:
	if reveal <= erase + 0.01 or color.a <= 0.003 or width < 0.6: return
	if a.distance_to(b) * (reveal - erase) < 3.0: return
	var n:Vector2 = (b - a).orthogonal().normalized()
	var top:PackedVector2Array = []
	var bottom:PackedVector2Array = []
	for i:int in steps + 1:
		var u:float = lerpf(erase,reveal,float(i) / steps)
		var mid:Vector2 = a.lerp(b,u) + n * bulge * 4.0 * u * (1.0 - u)
		var local:float = (u - erase) / maxf(reveal - erase,0.0001)
		var w:float = width * sin(PI * local) * 0.5
		top.append(mid + n * w)
		bottom.append(mid - n * w * 0.35)
	var poly:PackedVector2Array = []
	poly.append(top[0])
	for i2:int in range(1,steps): poly.append(top[i2])
	poly.append(top[steps])
	for i3:int in range(steps - 1,0,-1): poly.append(bottom[i3])
	if poly.size() >= 3 and width > 0.3:
		ci.draw_colored_polygon(poly,color)

## 折线闪电（中点位移），返回点列。
static func bolt(rng:RandomNumberGenerator,a:Vector2,b:Vector2,jag:float,depth:int = 5) -> PackedVector2Array:
	var pts:PackedVector2Array = [a,b]
	var offset:float = jag
	for _d:int in depth:
		var next:PackedVector2Array = []
		for i:int in pts.size() - 1:
			var p:Vector2 = pts[i]
			var q:Vector2 = pts[i + 1]
			next.append(p)
			var n:Vector2 = (q - p).orthogonal().normalized()
			next.append((p + q) * 0.5 + n * rng.randf_range(-offset,offset))
		next.append(pts[pts.size() - 1])
		pts = next
		offset *= 0.55
	return pts

static func draw_bolt(ci:CanvasItem,pts:PackedVector2Array,width:float,glow_color:Color,core_color:Color) -> void:
	if pts.size() < 2: return
	ci.draw_polyline(pts,Color(glow_color,glow_color.a * 0.35),width * 3.0,true)
	ci.draw_polyline(pts,glow_color,width * 1.4,true)
	ci.draw_polyline(pts,core_color,maxf(1.0,width * 0.5),true)

## 四角星闪光。
static func sparkle(ci:CanvasItem,pos:Vector2,size:float,color:Color,rot:float = 0.0) -> void:
	if size <= 0.3 or color.a <= 0.003: return
	var pts:PackedVector2Array = []
	for i:int in 8:
		var r:float = size if i % 2 == 0 else size * 0.18
		pts.append(pos + Vector2.from_angle(rot + TAU * i / 8.0) * r)
	ci.draw_colored_polygon(pts,color)

## 火焰/能量轮廓：半径随角度和时间起伏的星形多边形。
static func flame_blob(ci:CanvasItem,center:Vector2,radius:float,wobble:float,time:float,color:Color,seed_value:float = 0.0,up_bias:float = 0.0,segments:int = 40) -> void:
	if radius <= 0.5 or color.a <= 0.003: return
	var pts:PackedVector2Array = []
	for i:int in segments:
		var a:float = TAU * i / segments
		var n:float = sin(a * 3.0 + time * 7.0 + seed_value) * 0.5 + sin(a * 5.0 - time * 11.0 + seed_value * 2.0) * 0.3 + sin(a * 9.0 + time * 17.0) * 0.2
		var up:float = maxf(0.0,-sin(a)) * up_bias
		pts.append(center + Vector2.from_angle(a) * radius * (1.0 + n * wobble + up))
	ci.draw_colored_polygon(pts,color)

## 渐变圆环（用顶点色）：内圈 inner_color，外圈 outer_color。
static func ring(ci:CanvasItem,center:Vector2,r_in:float,r_out:float,inner_color:Color,outer_color:Color,segments:int = 48) -> void:
	if r_out <= r_in or r_out <= 0.5: return
	var pts:PackedVector2Array = []
	var cols:PackedColorArray = []
	var idx:PackedInt32Array = []
	for i:int in segments + 1:
		var d:Vector2 = Vector2.from_angle(TAU * i / segments)
		pts.append(center + d * maxf(r_in,0.0)); cols.append(inner_color)
		pts.append(center + d * r_out); cols.append(outer_color)
	for i2:int in segments:
		var b:int = i2 * 2
		idx.append_array([b,b + 1,b + 3,b,b + 3,b + 2])
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(),idx,pts,cols)

## 冲击波：逐渐变细的亮环 + 柔光。
static func shock(ci:CanvasItem,center:Vector2,radius:float,thickness:float,color:Color) -> void:
	if radius <= 1.0 or color.a <= 0.003: return
	ring(ci,center,maxf(0.0,radius - thickness),radius,Color(color,0.0),Color(color,color.a),56)
	ring(ci,center,radius,radius + thickness * 0.35,Color(color,color.a),Color(color,0.0),56)

## 地图矩形（全屏闪光用）。
static func screen_rect(node:Node2D) -> Rect2:
	var vp:Viewport = node.get_viewport()
	if vp == null: return Rect2(-2000,-2000,4000,4000)
	var inv:Transform2D = vp.get_canvas_transform().affine_inverse()
	var size:Vector2 = vp.get_visible_rect().size
	var p0:Vector2 = inv * Vector2.ZERO
	var p1:Vector2 = inv * size
	return Rect2(p0,p1 - p0).abs().grow(40.0)

# ---------------------------------------------------------------- 粒子
## 轻量粒子：kind 0=叠加光点 1=普通（烟/碎片） 2=叠加拖尾线 3=叠加四角星。
class Parts extends RefCounted:
	var p:PackedVector2Array = []
	var v:PackedVector2Array = []
	var age:PackedFloat32Array = []
	var life:PackedFloat32Array = []
	var size:PackedFloat32Array = []
	var drag:PackedFloat32Array = []
	var grav:PackedFloat32Array = []
	var col:PackedColorArray = []
	var kind:PackedByteArray = []
	var alive:int = 0

	func emit(pos:Vector2,vel:Vector2,lifetime:float,sz:float,color:Color,k:int = 0,drag_value:float = 0.0,gravity:float = 0.0) -> void:
		# 复用已死亡的槽位，数组不无限增长。
		for i:int in p.size():
			if age[i] >= life[i]:
				p[i] = pos; v[i] = vel; age[i] = 0.0; life[i] = lifetime; size[i] = sz; col[i] = color; kind[i] = k; drag[i] = drag_value; grav[i] = gravity
				return
		p.append(pos); v.append(vel); age.append(0.0); life.append(lifetime); size.append(sz); col.append(color); kind.append(k); drag.append(drag_value); grav.append(gravity)

	func step(dt:float) -> void:
		alive = 0
		for i:int in p.size():
			if age[i] >= life[i]: continue
			age[i] += dt
			var vel:Vector2 = v[i]
			if drag[i] > 0.0: vel *= exp(-drag[i] * dt)
			vel.y += grav[i] * dt
			v[i] = vel
			p[i] += vel * dt
			alive += 1

	func draw_add(ci:CanvasItem) -> void:
		var lib:Script = load("res://scripts/characters/动漫/咒术回战/jjk_vfx.gd")
		var tex:Texture2D = lib.call("glow_tex")
		for i:int in p.size():
			if age[i] >= life[i] or kind[i] == 1: continue
			var k:float = age[i] / life[i]
			var fade:float = (1.0 - k) * minf(1.0,k * 12.0 + 0.2)
			var c:Color = Color(col[i],col[i].a * fade)
			var s:float = size[i] * (1.0 - k * 0.5)
			match kind[i]:
				0: ci.draw_texture_rect(tex,Rect2(p[i] - Vector2(s,s),Vector2(s,s) * 2.0),false,c)
				2:
					var tail:Vector2 = v[i] * 0.045
					ci.draw_line(p[i] - tail,p[i],c,maxf(1.0,s * 0.5),true)
					ci.draw_texture_rect(tex,Rect2(p[i] - Vector2(s,s),Vector2(s,s) * 2.0),false,Color(c,c.a * 0.6))
				3: lib.call("sparkle",ci,p[i],s * 1.6,c,age[i] * 6.0)

	func draw_normal(ci:CanvasItem) -> void:
		for i:int in p.size():
			if age[i] >= life[i] or kind[i] != 1: continue
			var k:float = age[i] / life[i]
			var c:Color = Color(col[i],col[i].a * (1.0 - k))
			ci.draw_circle(p[i],size[i] * (0.6 + k * 0.9),c)
