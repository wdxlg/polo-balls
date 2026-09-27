extends Node2D
## 咒术回战一次性视觉特效（纯视觉，不结算伤害）。坐标全部为世界坐标。
## 由角色 RPC 在各端本地生成，随机种子随包下发，各端动画一致。
## 两层绘制：本节点（普通混合：暗部、烟、实体）+ AddLayer（叠加混合：光、火、电、粒子）。
const V = preload("res://scripts/characters/动漫/咒术回战/jjk_vfx.gd")
const JJK_FONT_OUTLINE:int = 8

var kind:String = ""
var data:Dictionary = {}
var life:float = 0.5
var t:float = 0.0
var _seed:int = 0
var _rng:RandomNumberGenerator = RandomNumberGenerator.new()
var _drng:RandomNumberGenerator = RandomNumberGenerator.new()
var _parts:V.Parts = V.Parts.new()
var _add:Node2D
var _emit_acc:float = 0.0
var _cache:Array = []

static func spawn(parent:Node,fx_kind:String,fx_data:Dictionary,duration:float) -> Node2D:
	if not is_instance_valid(parent) or not parent.is_inside_tree(): return null
	var fx:Node2D = (load("res://scripts/characters/动漫/咒术回战/jjk_fx.gd") as GDScript).new()
	fx.name = "JJKFx_" + fx_kind
	fx.set("kind",fx_kind)
	fx.set("data",fx_data)
	fx.set("life",maxf(duration,0.05))
	fx.set("_seed",int(fx_data.get("seed",randi())))
	fx.top_level = true
	fx.z_as_relative = false
	fx.z_index = int(fx_data.get("z",88))
	# 世界级特效（世界斩、领域文字）挂到当前场景，其余挂在角色下。
	if bool(fx_data.get("world",false)) and parent.get_tree().current_scene != null:
		parent.get_tree().current_scene.add_child(fx)
		fx.add_to_group("JJKWorldFx")
	else:
		parent.add_child(fx)
	fx.global_position = Vector2.ZERO
	fx.global_rotation = 0.0
	fx.global_scale = Vector2.ONE
	return fx

## 纯视觉的最短演出时长（不影响任何判定）。
const MIN_LIFE:Dictionary = {"red_burst":0.7,"cleave":0.55,"web":0.85,"fuga_burst":1.2,"world_slash":1.3,"black_flash":0.65,"thunder":0.65,"ripple":0.4,"teleport":0.45,"wheel_turn":0.9,"purple_beam":0.9}

func _ready() -> void:
	life = maxf(life,float(MIN_LIFE.get(kind,0.0)))
	_rng.seed = _seed
	_add = V.make_add_layer(self,_draw_add)
	if kind == "cutin":
		var face_path:String = str(data.get("face",""))
		V.cutin(self,load(face_path) if ResourceLoader.exists(face_path) else null,str(data.get("title","")),str(data.get("sub","")),_c("color",Color(0.5,0.7,1.0)),bool(data.get("right",false)),life)
		life = 0.05
		return
	_init_kind()
	_juice()

func _process(delta:float) -> void:
	if Game.now_stop_state: return
	t += delta
	if t >= life + _linger():
		queue_free()
		return
	_tick_kind(delta)
	_parts.step(delta)
	queue_redraw()
	_add.queue_redraw()

## 效果结束后让粒子自然消散的额外时间。
func _linger() -> float:
	return 0.35 if _parts.alive > 0 else 0.0

func _v(key:String,fallback:Vector2 = Vector2.ZERO) -> Vector2:
	var value:Variant = data.get(key,fallback)
	return value if value is Vector2 else fallback

func _f(key:String,fallback:float) -> float:
	return float(data.get(key,fallback))

func _c(key:String,fallback:Color) -> Color:
	var value:Variant = data.get(key,fallback)
	return value if value is Color else fallback

func _k() -> float:
	return clampf(t / life,0.0,1.0)

func _burst(pos:Vector2,count:int,speed_min:float,speed_max:float,lifetime:float,size:float,color:Color,k:int = 0,drag:float = 3.0,gravity:float = 0.0,spread:float = TAU,dir:float = 0.0) -> void:
	for i:int in count:
		var a:float = dir + _rng.randf_range(-spread * 0.5,spread * 0.5)
		_parts.emit(pos,Vector2.from_angle(a) * _rng.randf_range(speed_min,speed_max),lifetime * _rng.randf_range(0.6,1.2),size * _rng.randf_range(0.6,1.3),color,k,drag,gravity)

# ================================================================= 初始化
func _init_kind() -> void:
	match kind:
		"ripple":
			_burst(_v("pos"),8,90.0,170.0,0.4,3.0,Color(0.6,0.95,1.0),2,9.0)
		"red_burst":
			var p:Vector2 = _v("pos")
			var r:float = _f("radius",80.0)
			_burst(p,34,r * 2.0,r * 5.5,0.55,4.0,Color(1.0,0.35,0.15),2,4.0)
			_burst(p,14,r * 0.8,r * 2.2,0.7,r * 0.18,Color(1.0,0.55,0.25,0.9),0,3.0)
			_burst(p,10,r * 0.4,r * 1.2,1.1,r * 0.2,Color(0.12,0.04,0.04,0.55),1,2.0,-20.0)
		"purple_beam":
			var a:Vector2 = _v("a")
			var b:Vector2 = _v("b")
			for i:int in 12:
				_cache.append(_rng.randf())
			_burst(a,24,120.0,420.0,0.6,5.0,Color(0.8,0.5,1.0),2,3.0)
		"slash":
			var a2:Vector2 = _v("a")
			var b2:Vector2 = _v("b")
			_cache = [_rng.randf_range(-1.0,1.0) * a2.distance_to(b2) * 0.08]
			var mid:Vector2 = a2.lerp(b2,0.5)
			var n:Vector2 = (b2 - a2).orthogonal().normalized()
			for i2:int in 6:
				_parts.emit(mid + (b2 - a2) * _rng.randf_range(-0.3,0.3),n * _rng.randf_range(-160,160) + (b2 - a2).normalized() * _rng.randf_range(60,220),0.35,2.5,_c("color",Color.WHITE),2,5.0)
		"cleave":
			var p3:Vector2 = _v("pos")
			var r3:float = _f("radius",34.0)
			for i3:int in 6:
				_cache.append([_rng.randf() * PI,_rng.randf_range(0.8,1.3),i3 * 0.035 + _rng.randf() * 0.02,_rng.randf_range(-6,6)])
			_burst(p3,22,120.0,380.0,0.45,3.0,Color(1.0,0.3,0.35),2,5.0)
			_burst(p3,10,40.0,140.0,0.7,r3 * 0.12,Color(0.5,0.0,0.05,0.7),1,3.0,120.0)
		"web":
			var p4:Vector2 = _v("pos")
			var r4:float = _f("radius",150.0)
			var spokes:int = 14
			for i4:int in spokes:
				var ang:float = TAU * i4 / spokes + _rng.randf_range(-0.12,0.12)
				var pts:PackedVector2Array = V.bolt(_rng,p4,p4 + Vector2.from_angle(ang) * r4 * _rng.randf_range(0.85,1.1),r4 * 0.06,4)
				_cache.append(pts)
			_burst(p4,30,60.0,r4 * 2.2,0.8,5.0,Color(0.35,0.3,0.28,0.8),1,3.0,160.0)
			_burst(p4,24,r4 * 1.5,r4 * 3.5,0.45,2.5,Color(1,0.95,0.95),2,5.0)
		"fuga_burst":
			var p5:Vector2 = _v("pos")
			var r5:float = _f("radius",160.0)
			_burst(p5,50,r5 * 0.8,r5 * 3.2,1.0,r5 * 0.09,Color(1.0,0.5,0.1,0.9),0,2.5,-120.0)
			_burst(p5,40,r5 * 1.5,r5 * 4.0,0.8,3.0,Color(1.0,0.8,0.3),2,2.0,-60.0)
			for i5:int in 7:
				_cache.append([_rng.randf_range(-r5 * 0.7,r5 * 0.7),_rng.randf_range(0.6,1.3),_rng.randf_range(0.0,0.25)])
		"world_slash":
			var a6:Vector2 = _v("a")
			var b6:Vector2 = _v("b")
			var n6:Vector2 = (b6 - a6).orthogonal().normalized()
			for i6:int in 60:
				var at:Vector2 = a6.lerp(b6,_rng.randf())
				var side:float = 1.0 if _rng.randf() < 0.5 else -1.0
				_parts.emit(at,n6 * side * _rng.randf_range(80,420) + (b6 - a6).normalized() * _rng.randf_range(-60,60),0.7,_rng.randf_range(2.0,4.0),Color(1,0.95,0.95),2,3.0)
			for i7:int in 26:
				_cache.append([_rng.randf(),_rng.randf_range(-1.0,1.0),_rng.randf_range(8,26),_rng.randf() * TAU])
		"black_flash":
			var p8:Vector2 = _v("pos")
			var r8:float = _f("radius",70.0)
			_burst(p8,20,r8 * 2.0,r8 * 6.0,0.45,3.0,Color(1.0,0.1,0.15),2,5.0)
			_burst(p8,16,r8 * 1.5,r8 * 4.0,0.5,r8 * 0.07,Color(0.02,0.0,0.0,0.9),1,5.0)
		"heal":
			pass
		"thunder":
			var p9:Vector2 = _v("pos")
			var r9:float = _f("radius",70.0)
			_burst(p9,26,r9 * 1.5,r9 * 5.0,0.5,2.5,Color(0.75,0.9,1.0),2,4.0,200.0)
		"teleport":
			var a10:Vector2 = _v("a")
			var b10:Vector2 = _v("b")
			for i10:int in 16:
				_parts.emit(a10.lerp(b10,_rng.randf()),Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(10,50),0.45,3.0,Color(0.6,0.95,1.0),0,2.0)
			_burst(b10,14,120.0,260.0,0.35,2.5,Color(0.7,0.95,1.0),2,6.0)
		"wheel_turn":
			var p11:Vector2 = _v("pos")
			_burst(p11,18,60.0,200.0,0.8,3.0,Color(1.0,0.85,0.4),3,3.0)
		"shockwave":
			var p12:Vector2 = _v("pos")
			var r12:float = _f("radius",200.0)
			var c12:Color = _c("color",Color(0.6,0.9,1.0))
			_burst(p12,int(clampf(r12 / 6.0,8,40)),r12 * 1.2,r12 * 2.4,life * 0.9,3.0,c12.lightened(0.3),2,3.0)
		"text":
			pass

# ================================================================= 持续发射
func _tick_kind(delta:float) -> void:
	var k:float = _k()
	_emit_acc += delta
	match kind:
		"purple_beam":
			if k < 0.75 and _emit_acc > 0.016:
				_emit_acc = 0.0
				var a:Vector2 = _v("a")
				var b:Vector2 = _v("b")
				var head:Vector2 = a.lerp(b,V.out_cubic(k / 0.35))
				var n:Vector2 = (b - a).orthogonal().normalized()
				var w:float = _f("width",90.0)
				for i:int in 4:
					var at:Vector2 = a.lerp(head,_rng.randf())
					_parts.emit(at + n * _rng.randf_range(-w,w) * 0.4,n * _rng.randf_range(-1,1) * 160.0,0.5,_rng.randf_range(2,5),Color(0.75,0.45,1.0),2,2.0)
				_parts.emit(head,Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(80,260),0.4,w * 0.12,Color(0.9,0.7,1.0,0.8),0,3.0)
		"fuga_burst":
			if k < 0.7 and _emit_acc > 0.02:
				_emit_acc = 0.0
				var p:Vector2 = _v("pos")
				var r:float = _f("radius",160.0)
				for i2:int in 3:
					var off:Vector2 = Vector2(_rng.randf_range(-r,r) * 0.8,_rng.randf_range(-r,r) * 0.3)
					_parts.emit(p + off,Vector2(_rng.randf_range(-20,20),-_rng.randf_range(90,260)),0.8,r * _rng.randf_range(0.06,0.12),Color(1.0,_rng.randf_range(0.35,0.7),0.1,0.9),0,1.0,-80.0)
				if k > 0.35: _parts.emit(p + Vector2(_rng.randf_range(-r,r) * 0.6,-_rng.randf_range(0,r) * 0.5),Vector2(_rng.randf_range(-15,15),-_rng.randf_range(30,80)),1.4,r * 0.14,Color(0.1,0.07,0.06,0.45),1,0.5,-10.0)
		"heal":
			if k < 0.8 and _emit_acc > 0.03:
				_emit_acc = 0.0
				var p3:Vector2 = _v("pos")
				var r3:float = _f("radius",30.0)
				var a3:float = _rng.randf() * TAU
				_parts.emit(p3 + Vector2.from_angle(a3) * r3 * _rng.randf_range(0.3,1.2),Vector2(cos(a3) * 20.0,-_rng.randf_range(50,110)),0.9,_rng.randf_range(2.0,4.0),Color(0.5,1.0,0.6),3 if _rng.randf() < 0.4 else 0,1.0)
		"thunder":
			if k < 0.5 and _emit_acc > 0.05:
				_emit_acc = 0.0
				_burst(_v("pos"),4,80.0,260.0,0.3,2.0,Color(0.8,0.95,1.0),2,4.0,300.0)
		"wheel_turn":
			if k < 0.6 and _emit_acc > 0.04:
				_emit_acc = 0.0
				var p4:Vector2 = _v("pos")
				var r4:float = _f("radius",22.0) * 2.4
				var a4:float = _rng.randf() * TAU
				_parts.emit(p4 + Vector2.from_angle(a4) * r4,Vector2.from_angle(a4 + PI * 0.5) * 60.0,0.6,2.5,Color(1.0,0.9,0.5),3,2.0)

# ================================================================= 普通层（暗部/实体）
func _draw() -> void:
	var k:float = _k()
	_sprites_normal(k)
	_parts.draw_normal(self)
	match kind:
		"purple_beam":
			# 被抹消后的地面：紫黑色灼痕，慢慢淡去。
			var a:Vector2 = _v("a")
			var b:Vector2 = _v("b")
			var w:float = _f("width",90.0)
			var head:Vector2 = a.lerp(b,V.out_cubic(k / 0.35))
			var scar:float = V.seg(k,0.1,0.3) * (1.0 - V.seg(k,0.6,1.0))
			if scar > 0.0:
				draw_line(a,head,Color(0.08,0.0,0.12,0.45 * scar),w * 0.9,true)
		"world_slash":
			var a2:Vector2 = _v("a")
			var b2:Vector2 = _v("b")
			var w2:float = _f("width",70.0)
			var open:float = V.out_expo(k / 0.12) * (1.0 - V.in_cubic(V.seg(k,0.25,0.7)))
			if open > 0.0:
				# 空间裂缝：黑色虚空带，边缘带红/青色差。
				var n:Vector2 = (b2 - a2).orthogonal().normalized()
				var gap:float = w2 * 0.35 * open
				draw_line(a2 + n * 3.0,b2 + n * 3.0,Color(1.0,0.1,0.2,0.5 * open),gap + 4.0,true)
				draw_line(a2 - n * 3.0,b2 - n * 3.0,Color(0.1,0.9,1.0,0.35 * open),gap + 4.0,true)
				draw_line(a2,b2,Color(0,0,0,0.95 * open),gap,true)
			for sh:Variant in _cache:
				var u:float = float(sh[0])
				var side:float = float(sh[1])
				var size:float = float(sh[2])
				var rot:float = float(sh[3]) + t * 4.0 * side
				var n2:Vector2 = (b2 - a2).orthogonal().normalized()
				var fly:float = V.out_cubic(V.seg(k,0.05,0.8)) * 120.0 * side
				var c:Vector2 = a2.lerp(b2,u) + n2 * fly
				var fa:float = 1.0 - V.seg(k,0.4,1.0)
				if fa <= 0.0: continue
				var pts:PackedVector2Array = [c + Vector2.from_angle(rot) * size,c + Vector2.from_angle(rot + 2.2) * size * 0.4,c + Vector2.from_angle(rot + PI) * size * 0.8,c + Vector2.from_angle(rot + 4.0) * size * 0.3]
				draw_colored_polygon(pts,Color(0.0,0.0,0.02,0.75 * fa))
				draw_polyline(pts + PackedVector2Array([pts[0]]),Color(1,1,1,0.6 * fa),1.0,true)
		"black_flash":
			var p3:Vector2 = _v("pos")
			var r3:float = _f("radius",70.0)
			var hit:float = 1.0 - V.seg(k,0.0,0.35)
			if hit > 0.0:
				draw_circle(p3,r3 * 0.5 * V.out_expo(k / 0.1),Color(0,0,0,0.85 * hit))
			_drng.seed = _seed + int(t / 0.045) * 7
			var alpha:float = 1.0 - V.seg(k,0.35,1.0)
			for i3:int in 7:
				var ang:float = TAU * i3 / 7.0 + _drng.randf_range(-0.4,0.4)
				var pts3:PackedVector2Array = V.bolt(_drng,p3,p3 + Vector2.from_angle(ang) * r3 * _drng.randf_range(0.8,1.6) * V.out_cubic(k / 0.15),r3 * 0.18,4)
				draw_polyline(pts3,Color(0.0,0.0,0.0,alpha),5.0,true)
		"web":
			var p4:Vector2 = _v("pos")
			var r4:float = _f("radius",150.0)
			var grow:float = V.out_cubic(k / 0.25)
			var fade4:float = 1.0 - V.seg(k,0.55,1.0)
			for pts4:Variant in _cache:
				var poly:PackedVector2Array = pts4
				var n4:int = maxi(2,int(poly.size() * grow))
				draw_polyline(poly.slice(0,n4),Color(0.1,0.07,0.06,0.8 * fade4),3.0,true)
			for ringi:int in 3:
				var rr:float = r4 * (ringi + 1) / 3.5 * grow
				var pts5:PackedVector2Array = []
				for pts6:Variant in _cache:
					var q:PackedVector2Array = pts6
					var idx:int = mini(q.size() - 1,int(q.size() * (ringi + 1) / 3.5))
					pts5.append(p4 + (q[idx] - p4).limit_length(rr))
				if pts5.size() > 2:
					pts5.append(pts5[0])
					draw_polyline(pts5,Color(0.12,0.08,0.07,0.6 * fade4),2.0,true)
		"red_burst":
			var p7:Vector2 = _v("pos")
			var r7:float = _f("radius",80.0)
			var scorch:float = V.seg(k,0.05,0.2) * (1.0 - V.seg(k,0.5,1.0))
			if scorch > 0.0: draw_circle(p7,r7 * 0.55,Color(0.08,0.02,0.02,0.35 * scorch))
		"fuga_burst":
			var p8:Vector2 = _v("pos")
			var r8:float = _f("radius",160.0)
			var sc:float = V.seg(k,0.1,0.3) * (1.0 - V.seg(k,0.6,1.0))
			if sc > 0.0: draw_circle(p8,r8 * 0.7,Color(0.1,0.03,0.0,0.4 * sc))
		"shockwave":
			var cw:Color = _c("color",Color(0.6,0.9,1.0))
			if cw.get_luminance() < 0.3:
				var pw:Vector2 = _v("pos")
				var rw:float = _f("radius",200.0)
				var ew:float = V.out_expo(k)
				draw_circle(pw,rw * 0.9 * ew,Color(cw,0.35 * (1.0 - k)))
				V.shock(self,pw,rw * ew,maxf(6.0,rw * 0.3) * (1.0 - k),Color(cw,0.9 * (1.0 - k)))
				V.shock(self,pw,rw * 0.6 * V.out_cubic(k),maxf(4.0,rw * 0.2) * (1.0 - k),Color(0.4,0.1,0.6,0.7 * (1.0 - k)))
		"text":
			_draw_text(self,false)

# ================================================================= 叠加层（光）
func _draw_add() -> void:
	var ci:CanvasItem = _add
	var k:float = _k()
	_sprites_add(ci,k)
	match kind:
		"ripple":
			# 无下限：空间在接触点凝固，几圈涟漪从外向内收缩。
			var p:Vector2 = _v("pos")
			var r:float = _f("radius",24.0)
			var c:Color = _c("color",Color(0.55,0.9,1.0))
			V.glow(ci,p,r * 1.6 * (1.0 - k * 0.5),Color(c,0.5 * (1.0 - k)))
			for i:int in 4:
				var kk:float = V.seg(k,i * 0.12,i * 0.12 + 0.6)
				if kk <= 0.0 or kk >= 1.0: continue
				var rr:float = r * lerpf(1.6,0.35,V.out_cubic(kk))
				ci.draw_arc(p,rr,0.0,TAU,40,Color(c,0.8 * (1.0 - kk)),1.6,true)
			for j:int in 6:
				var ang:float = TAU * j / 6.0 + t * 1.5
				V.sparkle(ci,p + Vector2.from_angle(ang) * r * 0.9 * (1.0 - k),3.0 * (1.0 - k),Color(0.9,1,1,0.9 * (1.0 - k)),ang)
		"red_burst":
			var p2:Vector2 = _v("pos")
			var r2:float = _f("radius",80.0)
			var flash:float = 1.0 - V.seg(k,0.0,0.18)
			V.core(ci,p2,r2 * 0.5 * (0.6 + flash),Color(1.0,0.95,0.9,flash))
			V.glow(ci,p2,r2 * lerpf(0.5,1.5,V.out_cubic(k)),Color(1.0,0.2,0.1,0.9 * (1.0 - k)))
			V.flame_blob(ci,p2,r2 * lerpf(0.3,0.95,V.out_expo(k / 0.4)),0.18,t,Color(1.0,0.25,0.08,0.45 * (1.0 - V.seg(k,0.2,0.8))),float(_seed % 100))
			V.shock(ci,p2,r2 * lerpf(0.4,1.5,V.out_expo(k / 0.5)),r2 * 0.35 * (1.0 - k),Color(1.0,0.55,0.4,0.9 * (1.0 - k)))
			_drng.seed = _seed
			for i2:int in 14:
				var a2:float = TAU * i2 / 14.0 + _drng.randf() * 0.4
				var l0:float = r2 * lerpf(0.2,0.9,V.out_expo(k / 0.3))
				var l1:float = r2 * lerpf(0.5,1.9,V.out_expo(k / 0.3)) * _drng.randf_range(0.6,1.1)
				ci.draw_line(p2 + Vector2.from_angle(a2) * l0,p2 + Vector2.from_angle(a2) * l1,Color(1.0,0.45,0.3,0.9 * (1.0 - V.seg(k,0.1,0.6))),2.0,true)
		"purple_beam":
			_draw_purple(ci,k)
		"slash":
			var a4:Vector2 = _v("a")
			var b4:Vector2 = _v("b")
			var col:Color = _c("color",Color(1,1,1))
			var w4:float = _f("width",3.0) * 5.0 + 6.0
			var bulge:float = float(_cache[0]) if not _cache.is_empty() else 0.0
			var reveal:float = V.out_expo(k / 0.3)
			var erase:float = V.in_cubic(V.seg(k,0.35,1.0))
			V.crescent(ci,a4,b4,w4 * 2.2,bulge,Color(col,0.25),reveal,erase)
			V.crescent(ci,a4,b4,w4,bulge,Color(col,0.85),reveal,erase)
			V.crescent(ci,a4,b4,w4 * 0.35,bulge,Color(1,1,1,1),reveal,erase)
			var tip:Vector2 = a4.lerp(b4,reveal)
			if k < 0.4: V.sparkle(ci,tip,w4 * 1.2 * (1.0 - k / 0.4),Color(1,1,1,1.0 - k / 0.4),t * 10.0)
		"cleave":
			var p5:Vector2 = _v("pos")
			var r5:float = _f("radius",34.0) * 1.6
			for cut:Variant in _cache:
				var ang:float = float(cut[0])
				var scale5:float = float(cut[1])
				var delay:float = float(cut[2])
				var off:float = float(cut[3])
				var kk5:float = V.seg(t,delay,delay + 0.3)
				if kk5 <= 0.0 or kk5 >= 1.0: continue
				var dir:Vector2 = Vector2.from_angle(ang) * r5 * scale5
				var shift:Vector2 = dir.orthogonal().normalized() * off
				var rev:float = V.out_expo(kk5 / 0.35)
				var era:float = V.in_cubic(V.seg(kk5,0.4,1.0))
				V.crescent(ci,p5 - dir + shift,p5 + dir + shift,14.0,6.0,Color(1.0,0.15,0.25,0.5),rev,era)
				V.crescent(ci,p5 - dir + shift,p5 + dir + shift,5.0,6.0,Color(1,1,1,1),rev,era)
			V.glow(ci,p5,r5 * 1.3,Color(1.0,0.1,0.2,0.5 * (1.0 - k)))
			if k < 0.25: V.sparkle(ci,p5,r5 * (1.0 - k * 4.0),Color(1,0.9,0.9,1.0 - k * 4.0),0.4)
		"web":
			var p6:Vector2 = _v("pos")
			var r6:float = _f("radius",150.0)
			var grow6:float = V.out_cubic(k / 0.25)
			var fade6:float = 1.0 - V.seg(k,0.4,1.0)
			V.glow(ci,p6,r6 * 0.6,Color(1,0.6,0.6,0.35 * fade6))
			for pts6:Variant in _cache:
				var poly6:PackedVector2Array = pts6
				var n6:int = maxi(2,int(poly6.size() * grow6))
				ci.draw_polyline(poly6.slice(0,n6),Color(1,0.85,0.85,0.8 * fade6),1.4,true)
				# 沿辐条奔跑的斩击光点
				var run:float = fmod(t * 3.0 + float(poly6.size() % 7) * 0.13,1.0)
				var idx6:int = int(run * (n6 - 1))
				V.glow(ci,poly6[idx6],8.0,Color(1,1,1,fade6))
			V.shock(ci,p6,r6 * V.out_expo(k / 0.3),14.0 * (1.0 - k),Color(1,0.9,0.9,0.6 * fade6))
		"fuga_burst":
			_draw_fuga(ci,k)
		"world_slash":
			var a7:Vector2 = _v("a")
			var b7:Vector2 = _v("b")
			var w7:float = _f("width",70.0)
			var flash7:float = 1.0 - V.seg(k,0.0,0.15)
			if flash7 > 0.0:
				var rect:Rect2 = V.screen_rect(self)
				ci.draw_rect(rect,Color(1,0.95,0.95,0.35 * flash7))
			var line_a:float = 1.0 - V.seg(k,0.3,1.0)
			V.beam(ci,a7,b7,w7 * 0.25 * (0.4 + flash7),Color(1.0,0.85,0.9,line_a),Color(1,1,1))
			V.streak(ci,a7,b7,w7 * 1.8,Color(1.0,0.2,0.3,0.25 * line_a))
		"black_flash":
			var p8:Vector2 = _v("pos")
			var r8:float = _f("radius",70.0)
			var alpha8:float = 1.0 - V.seg(k,0.35,1.0)
			var flash8:float = 1.0 - V.seg(k,0.0,0.12)
			if flash8 > 0.0:
				ci.draw_rect(V.screen_rect(self),Color(0.5,0.0,0.05,0.25 * flash8))
			V.glow(ci,p8,r8 * 2.0,Color(1.0,0.05,0.1,0.8 * alpha8))
			_drng.seed = _seed + int(t / 0.045) * 7
			for i8:int in 7:
				var ang8:float = TAU * i8 / 7.0 + _drng.randf_range(-0.4,0.4)
				var pts8:PackedVector2Array = V.bolt(_drng,p8,p8 + Vector2.from_angle(ang8) * r8 * _drng.randf_range(0.8,1.6) * V.out_cubic(k / 0.15),r8 * 0.18,4)
				ci.draw_polyline(pts8,Color(1.0,0.05,0.12,alpha8),9.0,true)
			V.shock(ci,p8,r8 * 2.2 * V.out_expo(k / 0.4),18.0 * (1.0 - k),Color(1.0,0.2,0.25,alpha8))
		"heal":
			var p9:Vector2 = _v("pos")
			var r9:float = _f("radius",30.0)
			V.glow(ci,p9,r9 * 2.2 * V.out_cubic(k / 0.3),Color(0.4,1.0,0.55,0.55 * (1.0 - k)))
			V.shock(ci,p9,r9 * lerpf(0.5,1.8,V.out_cubic(k)),10.0 * (1.0 - k),Color(0.5,1.0,0.6,0.8 * (1.0 - k)))
			for i9:int in 3:
				var kk9:float = V.seg(k,i9 * 0.15,i9 * 0.15 + 0.6)
				if kk9 > 0.0 and kk9 < 1.0:
					var yy:float = -r9 * 1.5 * V.out_cubic(kk9)
					var pc:Vector2 = p9 + Vector2((i9 - 1) * r9 * 0.6,yy)
					var s9:float = 7.0 * (1.0 - kk9 * 0.5)
					ci.draw_line(pc - Vector2(s9,0),pc + Vector2(s9,0),Color(0.6,1,0.7,1.0 - kk9),3.0,true)
					ci.draw_line(pc - Vector2(0,s9),pc + Vector2(0,s9),Color(0.6,1,0.7,1.0 - kk9),3.0,true)
		"thunder":
			var p10:Vector2 = _v("pos")
			var r10:float = _f("radius",70.0)
			var strikes:Array[float] = [0.0,0.18,0.34]
			for si:int in strikes.size():
				var kk10:float = V.seg(k,strikes[si],strikes[si] + 0.22)
				if kk10 <= 0.0 or kk10 >= 1.0: continue
				_drng.seed = _seed + si * 31 + int(t / 0.04)
				var top:Vector2 = p10 + Vector2(_drng.randf_range(-60,60),-520)
				var pts10:PackedVector2Array = V.bolt(_drng,top,p10 + Vector2(_drng.randf_range(-r10,r10) * 0.3,0),60.0,6)
				V.draw_bolt(ci,pts10,3.0 * (1.0 - kk10) + 1.0,Color(0.55,0.75,1.0,1.0 - kk10),Color(1,1,1,1.0 - kk10))
				for bi:int in 3:
					var from_i:int = _drng.randi_range(4,pts10.size() - 8)
					var br:PackedVector2Array = V.bolt(_drng,pts10[from_i],pts10[from_i] + Vector2(_drng.randf_range(-90,90),_drng.randf_range(20,120)),20.0,4)
					V.draw_bolt(ci,br,1.2,Color(0.55,0.75,1.0,0.7 * (1.0 - kk10)),Color(1,1,1,0.8 * (1.0 - kk10)))
				V.glow(ci,p10,r10 * 2.0,Color(0.6,0.8,1.0,0.9 * (1.0 - kk10)))
				if kk10 < 0.3: ci.draw_rect(V.screen_rect(self),Color(0.7,0.85,1.0,0.12 * (1.0 - kk10 / 0.3)))
			V.shock(ci,p10,r10 * 1.4 * V.out_expo(k / 0.5),12.0 * (1.0 - k),Color(0.7,0.9,1.0,0.8 * (1.0 - k)))
		"teleport":
			var a11:Vector2 = _v("a")
			var b11:Vector2 = _v("b")
			var c11:Color = Color(0.6,0.95,1.0)
			# 出发点：空间向内塌缩；落点：向外展开。
			V.shock(ci,a11,lerpf(46.0,4.0,V.out_cubic(k)),8.0,Color(c11,0.9 * (1.0 - k)))
			V.glow(ci,a11,30.0 * (1.0 - k),Color(c11,0.6 * (1.0 - k)))
			V.shock(ci,b11,lerpf(6.0,56.0,V.out_expo(k)),10.0 * (1.0 - k),Color(c11,0.9 * (1.0 - k)))
			V.core(ci,b11,22.0 * (1.0 - V.seg(k,0.0,0.3)),Color(1,1,1,1.0 - V.seg(k,0.0,0.3)))
			V.streak(ci,a11,b11,16.0 * (1.0 - k),Color(c11,0.5 * (1.0 - k)))
		"wheel_turn":
			_draw_wheel(ci,k)
		"shockwave":
			var p13:Vector2 = _v("pos")
			var r13:float = _f("radius",200.0)
			var c13:Color = _c("color",Color(0.6,0.9,1.0))
			if c13.get_luminance() < 0.3: c13 = Color(0.55,0.3,0.9,0.5)
			var e13:float = V.out_expo(k)
			V.glow(ci,p13,r13 * 0.8 * e13,Color(c13,0.35 * (1.0 - k)))
			V.shock(ci,p13,r13 * e13,maxf(4.0,r13 * 0.18) * (1.0 - k),Color(c13,0.95 * (1.0 - k)))
			V.shock(ci,p13,r13 * 0.7 * V.out_cubic(k),maxf(3.0,r13 * 0.08) * (1.0 - k),Color(c13.lightened(0.4),0.6 * (1.0 - k)))
		"text":
			_draw_text(ci,true)
	_parts.draw_add(ci)

# ================================================================= 虚式·茈
func _draw_purple(ci:CanvasItem,k:float) -> void:
	var a:Vector2 = _v("a")
	var b:Vector2 = _v("b")
	var w:float = _f("width",90.0)
	var dir:Vector2 = (b - a).normalized()
	var n:Vector2 = dir.orthogonal()
	# 茈是一颗前进的球体：光束跟在球后面展开。
	var travel:float = V.out_cubic(k / 0.35)
	var head:Vector2 = a.lerp(b,travel)
	var alive:float = 1.0 - V.in_cubic(V.seg(k,0.55,1.0))
	var thin:float = lerpf(1.0,0.15,V.seg(k,0.55,1.0))
	var flash:float = 1.0 - V.seg(k,0.0,0.12)
	if flash > 0.0: ci.draw_rect(V.screen_rect(self),Color(0.6,0.3,1.0,0.22 * flash))
	# 外层紫光、内层白芯
	V.streak(ci,a,head,w * 2.6 * thin,Color(0.45,0.1,0.9,0.35 * alive))
	V.streak(ci,a,head,w * 1.4 * thin,Color(0.65,0.3,1.0,0.7 * alive))
	ci.draw_line(a,head,Color(0.85,0.6,1.0,0.8 * alive),w * 0.55 * thin,true)
	ci.draw_line(a,head,Color(1,1,1,alive),maxf(2.0,w * 0.2 * thin),true)
	# 两侧的能量电弧（每 0.04 秒重新生成）
	_drng.seed = _seed + int(t / 0.04) * 13
	for side:int in 2:
		var s:float = 1.0 if side == 0 else -1.0
		var off:Vector2 = n * s * w * 0.42 * thin
		var pts:PackedVector2Array = V.bolt(_drng,a + off,head + off,w * 0.12,5)
		ci.draw_polyline(pts,Color(0.8,0.55,1.0,0.8 * alive),2.0,true)
	# 红蓝残影在出发点旋转合一
	var merge:float = 1.0 - V.seg(k,0.0,0.2)
	if merge > 0.0:
		var rot:float = t * 30.0
		V.glow(ci,a + Vector2.from_angle(rot) * w * 0.5 * merge,w * 0.5,Color(0.2,0.4,1.0,merge))
		V.glow(ci,a - Vector2.from_angle(rot) * w * 0.5 * merge,w * 0.5,Color(1.0,0.15,0.1,merge))
	# 前进的球体
	var orb:float = 1.0 - V.seg(k,0.35,0.5)
	if orb > 0.0:
		V.glow(ci,head,w * 1.8,Color(0.6,0.25,1.0,0.8 * orb))
		V.flame_blob(ci,head,w * 0.62,0.12,t * 2.0,Color(0.7,0.4,1.0,0.8 * orb),3.0)
		V.core(ci,head,w * 0.42,Color(1,0.95,1,orb))
		for i:int in 6:
			var ang:float = t * 12.0 + TAU * i / 6.0
			ci.draw_arc(head,w * (0.7 + 0.08 * i),ang,ang + 1.4,16,Color(0.85,0.6,1.0,0.7 * orb),2.0,true)
	# 起点冲击波
	V.shock(ci,a,w * 2.5 * V.out_expo(k / 0.4),w * 0.4 * (1.0 - k),Color(0.8,0.5,1.0,0.8 * (1.0 - k)))

# ================================================================= 开·竈
func _draw_fuga(ci:CanvasItem,k:float) -> void:
	var p:Vector2 = _v("pos")
	var r:float = _f("radius",160.0)
	var flash:float = 1.0 - V.seg(k,0.0,0.12)
	if flash > 0.0:
		V.core(ci,p,r * 0.8,Color(1,0.95,0.8,flash))
		ci.draw_rect(V.screen_rect(self),Color(1.0,0.5,0.1,0.16 * flash))
	var body:float = V.out_expo(k / 0.25)
	var fade:float = 1.0 - V.seg(k,0.45,1.0)
	V.glow(ci,p,r * 1.8 * body,Color(1.0,0.35,0.05,0.7 * fade))
	V.flame_blob(ci,p,r * 0.85 * body,0.2,t,Color(1.0,0.3,0.05,0.55 * fade),1.0,0.55)
	V.flame_blob(ci,p,r * 0.6 * body,0.25,t * 1.3,Color(1.0,0.6,0.15,0.6 * fade),2.0,0.7)
	V.flame_blob(ci,p,r * 0.32 * body,0.3,t * 1.7,Color(1.0,0.9,0.5,0.8 * fade),3.0,0.8)
	# 火柱
	for pillar:Variant in _cache:
		var x:float = float(pillar[0])
		var hscale:float = float(pillar[1])
		var delay:float = float(pillar[2])
		var kk:float = V.seg(k,delay,delay + 0.5)
		if kk <= 0.0 or kk >= 1.0: continue
		var h:float = r * 1.6 * hscale * V.out_cubic(kk / 0.4)
		var base:Vector2 = p + Vector2(x,r * 0.2)
		var pf:float = 1.0 - V.seg(kk,0.5,1.0)
		V.streak(ci,base,base + Vector2(sin(t * 9.0 + x) * 8.0,-h),r * 0.28,Color(1.0,0.45,0.08,0.8 * pf))
		V.streak(ci,base,base + Vector2(0,-h * 0.7),r * 0.12,Color(1.0,0.85,0.4,0.9 * pf))
	V.shock(ci,p,r * 1.5 * V.out_expo(k / 0.4),r * 0.25 * (1.0 - k),Color(1.0,0.6,0.2,0.8 * (1.0 - k)))

# ================================================================= 魔虚罗法阵
func _draw_wheel(ci:CanvasItem,k:float) -> void:
	var p:Vector2 = _v("pos")
	var r:float = _f("radius",22.0) * 2.4
	var appear:float = V.out_back(k / 0.25)
	var fade:float = 1.0 - V.seg(k,0.6,1.0)
	var rot:float = V.out_back(V.seg(k,0.1,0.55),2.2) * TAU / 8.0
	var gold:Color = Color(1.0,0.82,0.35,fade)
	V.glow(ci,p,r * 2.2 * appear,Color(1.0,0.75,0.3,0.45 * fade))
	# 放射光束
	for i:int in 16:
		var a:float = TAU * i / 16.0 + t * 0.4
		V.streak(ci,p,p + Vector2.from_angle(a) * r * 2.4 * appear,6.0,Color(1.0,0.85,0.45,0.25 * fade))
	ci.draw_arc(p,r * appear,0.0,TAU,48,gold,3.0,true)
	ci.draw_arc(p,r * 0.55 * appear,0.0,TAU,32,gold,2.0,true)
	for i2:int in 8:
		var a2:float = rot + TAU * i2 / 8.0
		var d:Vector2 = Vector2.from_angle(a2)
		ci.draw_line(p + d * r * 0.2 * appear,p + d * r * 1.25 * appear,gold,3.0,true)
		V.core(ci,p + d * r * 1.32 * appear,5.0 * appear,gold)
	V.core(ci,p,r * 0.22 * appear,Color(1,0.95,0.7,fade))
	V.shock(ci,p,r * 3.0 * V.out_expo(V.seg(k,0.45,1.0)),10.0,Color(1.0,0.85,0.45,0.8 * V.env(V.seg(k,0.45,1.0),0.05,0.3)))

# ================================================================= 文字
func _draw_text(ci:CanvasItem,additive:bool) -> void:
	var p:Vector2 = _v("pos")
	var text:String = str(data.get("text",""))
	var size:int = int(data.get("size",34))
	var c:Color = _c("color",Color.WHITE)
	var font:Font = ThemeDB.fallback_font
	var k:float = _k()
	var big:bool = size >= 30
	var alpha:float = clampf(minf(1.0,t * 8.0) * minf(1.0,(life - t) * 3.0),0.0,1.0)
	var width:float = font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	var pop:float = V.out_back(minf(1.0,t / 0.22),2.5)
	var rise:float = 0.0 if big else -14.0 * V.out_cubic(k)
	var origin:Vector2 = p + Vector2(0,rise)
	if big:
		# 领域名：毛笔墨带自左向右刷开，文字逐字浮现，外发光。
		var brush:float = V.out_cubic(t / 0.35)
		var band_w:float = (width + size * 2.0) * brush
		var left:Vector2 = origin + Vector2(-(width + size * 2.0) * 0.5,0.0)
		if not additive:
			var pts:PackedVector2Array = []
			var steps:int = 24
			for i:int in steps + 1:
				var u:float = float(i) / steps
				pts.append(left + Vector2(band_w * u,-size * 0.62 * (0.85 + 0.15 * sin(u * 17.0 + _seed))))
			for i2:int in range(steps,-1,-1):
				var u2:float = float(i2) / steps
				pts.append(left + Vector2(band_w * u2,size * 0.62 * (0.85 + 0.15 * cos(u2 * 13.0 + _seed))))
			if band_w > 2.0: ci.draw_colored_polygon(pts,Color(0.02,0.0,0.02,0.78 * alpha))
			var shown:int = int(ceil(text.length() * V.seg(t,0.12,0.12 + 0.05 * text.length())))
			var x:float = -width * 0.5
			for ch:int in text.length():
				var cs:String = text.substr(ch,1)
				var cw:float = font.get_string_size(cs,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
				if ch < shown:
					var ct:float = clampf((t - 0.12 - 0.05 * ch) / 0.18,0.0,1.0)
					var scl:float = lerpf(1.6,1.0,V.out_cubic(ct))
					var at:Vector2 = origin + Vector2(x,size * 0.35)
					ci.draw_set_transform(at + Vector2(cw * 0.5,-size * 0.35),0.0,Vector2(scl,scl))
					ci.draw_string_outline(font,Vector2(-cw * 0.5,size * 0.35),cs,HORIZONTAL_ALIGNMENT_LEFT,-1,size,JJK_FONT_OUTLINE,Color(0,0,0,0.9 * alpha * ct))
					ci.draw_string(font,Vector2(-cw * 0.5,size * 0.35),cs,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color(c,alpha * ct))
					ci.draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
				x += cw
		else:
			V.streak(ci,origin + Vector2(-width * 0.6,0),origin + Vector2(width * 0.6,0),size * 2.2,Color(c,0.35 * alpha))
			var sweep:float = V.seg(t,0.2,0.9)
			if sweep > 0.0 and sweep < 1.0:
				var sx:float = lerpf(-width * 0.6,width * 0.6,sweep)
				V.streak(ci,origin + Vector2(sx - 30,-size * 0.4),origin + Vector2(sx + 30,size * 0.4),size * 0.6,Color(1,1,1,0.6 * alpha))
		return
	if additive:
		V.glow(ci,origin,width * 0.7 + size,Color(c,0.25 * alpha))
		return
	ci.draw_set_transform(origin,0.0,Vector2(pop,pop))
	var at2:Vector2 = Vector2(-width * 0.5,size * 0.35)
	ci.draw_string_outline(font,at2 + Vector2(2,2),text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,6,Color(0,0,0,0.5 * alpha))
	ci.draw_string_outline(font,at2,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,5,Color(0,0,0,0.9 * alpha))
	ci.draw_string(font,at2,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color(c,alpha))
	ci.draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

# ================================================================= 演出：扭曲 / 后处理 / 震屏 / 顿帧 / 推镜
func _juice() -> void:
	match kind:
		"red_burst":
			var r:float = _f("radius",80.0)
			V.distort(self,0,_v("pos"),Vector2.ONE * r * 5.0,0.45,30.0,{"aberration":1.5})
			V.shake(self,7.0)
			V.zoom_punch(self,_v("pos"),0.35)
		"purple_beam":
			var a:Vector2 = _v("a")
			var b:Vector2 = _v("b")
			var w:float = _f("width",90.0)
			var big:float = clampf(w / 90.0,0.6,2.0)
			V.screen(self,a,life,{"blur":0.055 * big,"aberration":0.01 * big,"flash":Color(0.8,0.6,1.0,0.55),"flash_time":0.14,"vignette":0.35,"tint":Color(0.7,0.5,1.0,0.25)},Vector3(0.05,0.35,1.0))
			V.distort(self,0,a,Vector2.ONE * w * 7.0,0.6,40.0 * big,{"aberration":2.0})
			V.distort(self,2,a.lerp(b,0.5),Vector2(a.distance_to(b),w * 2.4),life,7.0 * big,{"rot_angle":(b - a).angle(),"aberration":1.5})
			V.shake(self,12.0 * big,(b - a))
			V.hitstop(self,1.0,a)
			V.zoom_punch(self,a,0.8)
		"cleave":
			V.distort(self,0,_v("pos"),Vector2.ONE * _f("radius",34.0) * 5.0,0.35,14.0)
			V.shake(self,3.0)
		"web":
			V.distort(self,0,_v("pos"),Vector2.ONE * _f("radius",150.0) * 2.6,0.5,16.0)
			V.shake(self,5.0)
		"fuga_burst":
			var r5:float = _f("radius",160.0)
			V.distort(self,0,_v("pos"),Vector2.ONE * r5 * 5.0,0.6,42.0,{"aberration":2.0})
			V.screen(self,_v("pos"),0.7,{"blur":0.035,"aberration":0.007,"tint":Color(1.0,0.55,0.25,0.3),"flash":Color(1.0,0.75,0.4,0.5),"flash_time":0.1,"vignette":0.3})
			V.shake(self,12.0)
			V.hitstop(self,0.8,_v("pos"))
			V.zoom_punch(self,_v("pos"),0.7)
		"world_slash":
			var a6:Vector2 = _v("a")
			var b6:Vector2 = _v("b")
			var mid:Vector2 = a6.lerp(b6,0.5)
			V.screen(self,mid,0.9,{"invert":1.0,"invert_time":0.14,"aberration":0.016,"blur":0.025,"flash":Color(1,1,1,0.8),"flash_time":0.08,"desat":0.5},Vector3(0.02,0.25,1.0))
			V.distort(self,2,mid,Vector2(a6.distance_to(b6),_f("width",70.0) * 4.0),life,26.0,{"rot_angle":(b6 - a6).angle(),"aberration":3.0})
			V.shake(self,18.0,(b6 - a6).orthogonal())
			V.hitstop(self,1.0,mid)
			V.zoom_punch(self,mid,0.6)
		"black_flash":
			var p8:Vector2 = _v("pos")
			V.screen(self,p8,0.4,{"invert":1.0,"invert_time":0.12,"aberration":0.014,"blur":0.03,"tint":Color(1.0,0.3,0.3,0.4)},Vector3(0.02,0.2,1.0))
			V.distort(self,0,p8,Vector2.ONE * _f("radius",70.0) * 4.5,0.4,32.0,{"aberration":3.0})
			V.shake(self,9.0)
			V.hitstop(self,1.0,p8)
			V.zoom_punch(self,p8,0.9)
		"thunder":
			var p10:Vector2 = _v("pos")
			V.distort(self,0,p10,Vector2.ONE * _f("radius",70.0) * 4.0,0.4,20.0)
			V.screen(self,p10,0.3,{"flash":Color(0.8,0.9,1.0,0.35),"flash_time":0.08,"aberration":0.006})
			V.shake(self,6.0)
		"teleport":
			V.distort(self,0,_v("b"),Vector2.ONE * 160.0,0.35,18.0)
		"shockwave":
			var r13:float = _f("radius",200.0)
			if r13 >= 60.0: V.distort(self,0,_v("pos"),Vector2.ONE * r13 * 2.3,life,16.0 + r13 * 0.04)
		"wheel_turn":
			V.distort(self,0,_v("pos"),Vector2.ONE * 160.0,0.5,12.0)

# ================================================================= 贴图层：普通混合（烟、碎石、黑色部分）
func _sprites_normal(k:float) -> void:
	match kind:
		"red_burst":
			var r:float = _f("radius",80.0)
			V.anim(self,"a_smoke_black",_v("pos") + Vector2(0,-r * 0.2 * k),r * 3.0,V.seg(k,0.12,1.0),Color(0.2,0.12,0.12,0.8))
		"fuga_burst":
			var r2:float = _f("radius",160.0)
			V.anim(self,"a_smoke_black",_v("pos") + Vector2(0,-r2 * 0.4 * k),r2 * 3.2,V.seg(k,0.25,1.0),Color(0.15,0.1,0.08,0.75))
		"web":
			var r3:float = _f("radius",150.0)
			var fade3:float = 1.0 - V.seg(k,0.5,1.0)
			V.sprite(self,"k_dirt02",_v("pos"),r3 * 1.4 * V.out_cubic(k / 0.2),Color(0.18,0.13,0.1,0.8 * fade3),float(_seed % 7))
			V.anim(self,"a_smoke_white",_v("pos"),r3 * 1.6,V.seg(k,0.05,1.0),Color(0.45,0.4,0.38,0.55))
		"black_flash":
			var r4:float = _f("radius",70.0)
			var a4:float = 1.0 - V.seg(k,0.2,1.0)
			V.sprite(self,"k_scorch02",_v("pos"),r4 * 2.6 * V.out_expo(k / 0.1),Color(0,0,0,0.9 * a4),t * 2.0)
			# 黑色闪电：伸出红光之外才看得见
			_drng.seed = _seed * 7 + int(t / 0.06)
			for bi:int in 5:
				var ba:float = _drng.randf() * TAU
				var bp:Vector2 = _v("pos") + Vector2.from_angle(ba) * r4 * 1.35
				V.sprite(self,"k_spark06" if bi % 2 == 0 else "k_spark05",bp,r4 * 2.0,Color(0,0,0,0.95 * a4),ba + PI * 0.5,Vector2(0.7,1.0))
		"shockwave":
			var cw:Color = _c("color",Color(0.6,0.9,1.0))
			if cw.get_luminance() < 0.3:
				var r5:float = _f("radius",200.0)
				V.sprite(self,"k_smoke10",_v("pos"),r5 * 2.4 * V.out_expo(k),Color(0.05,0.03,0.08,0.7 * (1.0 - k)),t)
		"world_slash":
			var a6:Vector2 = _v("a")
			var b6:Vector2 = _v("b")
			var open:float = V.out_expo(k / 0.12) * (1.0 - V.in_cubic(V.seg(k,0.25,0.7)))
			V.sprite_line(self,"k_trace07",a6,b6,_f("width",70.0) * 0.6 * open,Color(0,0,0,0.9 * open),true)

# ================================================================= 贴图层：叠加（光、火、电）
func _sprites_add(ci:CanvasItem,k:float) -> void:
	match kind:
		"ripple":
			var p:Vector2 = _v("pos")
			var r:float = _f("radius",24.0)
			var c:Color = _c("color",Color(0.55,0.9,1.0))
			V.anim(ci,"a_bluering",p,r * 4.0,k,Color(c,0.9))
			V.sprite(ci,"k_circle02",p,r * lerpf(3.0,1.0,V.out_cubic(k)),Color(c,0.7 * (1.0 - k)))
			V.sprite(ci,"k_star06",p,r * 2.5 * (1.0 - k),Color(1,1,1,1.0 - k),t * 3.0)
		"red_burst":
			var p2:Vector2 = _v("pos")
			var r2:float = _f("radius",80.0)
			var fl:float = 1.0 - V.seg(k,0.0,0.2)
			V.sprite(ci,"k_light01",p2,r2 * 3.2 * (0.6 + 0.4 * fl),Color(1.0,0.3,0.15,fl))
			V.sprite(ci,"k_scorch02",p2,r2 * 3.0 * V.out_expo(k / 0.25),Color(1.0,0.35,0.2,0.9 * (1.0 - V.seg(k,0.1,0.5))),float(_seed % 11))
			V.anim(ci,"a_expl_fire",p2,r2 * 3.8,V.seg(k,0.0,0.85),Color(1,0.85,0.8,1.0))
			V.anim(ci,"a_smoke_expl",p2,r2 * 2.4,V.seg(k,0.02,0.6),Color(1.0,0.4,0.3,0.7))
		"purple_beam":
			var a:Vector2 = _v("a")
			var b:Vector2 = _v("b")
			var w:float = _f("width",90.0)
			var head:Vector2 = a.lerp(b,V.out_cubic(k / 0.35))
			var alive:float = 1.0 - V.in_cubic(V.seg(k,0.55,1.0))
			var thin:float = lerpf(1.0,0.15,V.seg(k,0.55,1.0))
			# 光束主体：竖直 trace 贴图沿光束铺开 + 两条电弧
			V.sprite_line(ci,"k_trace06",a,head,w * 2.2 * thin,Color(0.6,0.25,1.0,0.8 * alive),true)
			V.sprite_line(ci,"k_trace07",a,head,w * 0.9 * thin,Color(0.95,0.85,1.0,alive),true)
			V.sprite_line(ci,"k_spark07",a,head,w * 1.1 * thin,Color(0.75,0.45,1.0,0.8 * alive * (0.6 + 0.4 * sin(t * 40.0))))
			V.anim(ci,"a_lightning",a.lerp(head,0.5),a.distance_to(head),t * 3.0,Color(0.8,0.55,1.0,0.8 * alive),(head - a).angle(),true,Vector2(1.0,w / 90.0))
			# 前进的球
			var orb:float = 1.0 - V.seg(k,0.35,0.55)
			if orb > 0.0:
				V.sprite(ci,"k_flare01",head,w * 7.0,Color(0.8,0.6,1.0,orb),0.0,Vector2(1.0,0.35))
				V.anim(ci,"a_pfx_purple",head,w * 3.2,t * 1.4,Color(1,1,1,orb),0.0,true)
				V.sprite(ci,"k_twirl02",head,w * 2.6,Color(0.7,0.4,1.0,orb),-t * 14.0)
				V.sprite(ci,"k_twirl03",head,w * 1.8,Color(1.0,0.9,1.0,orb),t * 18.0)
			# 起点：红蓝合一的爆闪
			var st:float = 1.0 - V.seg(k,0.0,0.3)
			V.sprite(ci,"k_light03",a,w * 4.0 * (1.0 + (1.0 - st)),Color(0.7,0.4,1.0,st))
			V.anim(ci,"a_expl_ring",a,w * 3.5,V.seg(k,0.0,0.6),Color(0.8,0.6,1.0,0.9))
			# 终点冲击
			var hit:float = V.seg(k,0.3,0.9)
			V.anim(ci,"a_pfx_purple",b,w * 4.0,hit,Color(1,1,1,1.0 - hit * 0.5))
		"slash":
			var a3:Vector2 = _v("a")
			var b3:Vector2 = _v("b")
			var col:Color = _c("color",Color(1,1,1))
			var rev:float = V.out_expo(k / 0.3)
			var fade3:float = 1.0 - V.in_cubic(V.seg(k,0.3,1.0))
			var l3:float = a3.distance_to(b3)
			var mid3:Vector2 = a3.lerp(b3,0.5)
			V.sprite(ci,"k_slash04",mid3,l3 * 1.15 * (0.7 + 0.3 * rev),Color(col,0.9 * fade3),(b3 - a3).angle(),Vector2(1.0,0.55))
			V.sprite(ci,"k_star08",a3.lerp(b3,rev),l3 * 0.35 * fade3,Color(1,1,1,fade3),t * 8.0)
		"cleave":
			var p4:Vector2 = _v("pos")
			var r4:float = _f("radius",34.0) * 1.6
			for cut:Variant in _cache:
				var ang:float = float(cut[0])
				var delay:float = float(cut[2])
				var kk:float = V.seg(t,delay,delay + 0.3)
				if kk <= 0.0 or kk >= 1.0: continue
				V.sprite(ci,"k_slash04",p4,r4 * 2.6 * float(cut[1]),Color(1.0,0.35,0.4,1.0 - kk),ang,Vector2(1.0,0.4))
			V.sprite(ci,"k_scratch01",p4,r4 * 2.4 * V.out_expo(k / 0.2),Color(1.0,0.5,0.55,1.0 - k),float(_seed % 3))
		"web":
			var p5:Vector2 = _v("pos")
			var r5:float = _f("radius",150.0)
			V.sprite(ci,"k_scratch01",p5,r5 * 1.6 * V.out_expo(k / 0.2),Color(1,0.9,0.9,0.8 * (1.0 - k)),float(_seed % 5))
			V.sprite(ci,"k_scratch01",p5,r5 * 1.3 * V.out_expo(k / 0.2),Color(1,0.9,0.9,0.6 * (1.0 - k)),float(_seed % 5) + 1.9)
		"fuga_burst":
			var p6:Vector2 = _v("pos")
			var r6:float = _f("radius",160.0)
			var fl6:float = 1.0 - V.seg(k,0.0,0.2)
			V.sprite(ci,"k_light01",p6,r6 * 3.4,Color(1.0,0.55,0.2,fl6))
			V.anim(ci,"a_expl_flare",p6,r6 * 3.4,V.seg(k,0.0,0.7),Color(1,1,1,1))
			V.anim(ci,"a_pfx_fireburst",p6 + Vector2(0,-r6 * 0.35),r6 * 2.6,V.seg(k,0.05,0.9),Color(1,0.9,0.8,0.95))
			V.anim(ci,"a_pfx_firering",p6,r6 * 3.0,V.seg(k,0.0,0.8),Color(1,1,1,0.9))
			for pillar:Variant in _cache:
				var kk6:float = V.seg(k,float(pillar[2]),float(pillar[2]) + 0.55)
				if kk6 <= 0.0 or kk6 >= 1.0: continue
				var hs:float = float(pillar[1]) * V.out_cubic(kk6 / 0.3) * (1.0 - V.seg(kk6,0.6,1.0))
				V.anim(ci,"a_fire",p6 + Vector2(float(pillar[0]),-r6 * 0.5 * hs),r6 * 0.7,t * 1.5 + float(pillar[0]),Color(1,1,1,0.95),0.0,true,Vector2(1.0,hs * 1.6))
		"world_slash":
			var a7:Vector2 = _v("a")
			var b7:Vector2 = _v("b")
			var w7:float = _f("width",70.0)
			var line_a:float = 1.0 - V.seg(k,0.3,1.0)
			V.sprite_line(ci,"k_trace06",a7,b7,w7 * 4.0 * (0.6 + 0.4 * V.out_expo(k / 0.15)),Color(0.9,0.05,0.12,0.45 * line_a),true)
			V.sprite_line(ci,"k_trace06",a7,b7,w7 * 1.6,Color(1.0,0.3,0.4,0.7 * line_a),true)
			V.sprite(ci,"k_flare01",a7.lerp(b7,0.5),a7.distance_to(b7) * 0.9,Color(1.0,0.4,0.45,0.8 * (1.0 - V.seg(k,0.0,0.3))),(b7 - a7).angle(),Vector2(1.0,0.12))
			V.sprite_line(ci,"k_trace07",a7,b7,w7 * 0.5,Color(1,1,1,line_a),true)
			V.anim(ci,"a_lightning",a7.lerp(b7,0.5),a7.distance_to(b7),t * 4.0,Color(1,0.9,0.95,0.7 * line_a),(b7 - a7).angle(),true,Vector2(1.0,0.6))
		"black_flash":
			var p8:Vector2 = _v("pos")
			var r8:float = _f("radius",70.0)
			var a8:float = 1.0 - V.seg(k,0.25,1.0)
			V.sprite(ci,"k_scorch03",p8,r8 * 3.4 * V.out_expo(k / 0.12),Color(0.9,0.08,0.12,0.8 * a8),-t * 3.0)
			V.sprite(ci,"k_light01",p8,r8 * 3.0,Color(0.8,0.02,0.08,0.45 * a8))
			V.sprite(ci,"k_star08",p8,r8 * 2.2 * (1.0 - k),Color(1.0,0.85,0.85,1.0 - k),t * 4.0)
			V.sprite(ci,"k_light02",p8,r8 * 0.9,Color(1,0.9,0.9,a8))
			_drng.seed = _seed + int(t / 0.05)
			for i8:int in 4:
				var ang8:float = _drng.randf() * TAU
				V.sprite(ci,"k_spark06",p8 + Vector2.from_angle(ang8) * r8 * 0.7,r8 * 1.6,Color(1.0,0.15,0.2,a8),ang8 + PI * 0.5,Vector2(0.6,1.0))
		"heal":
			var p9:Vector2 = _v("pos")
			var r9:float = _f("radius",30.0)
			var e9:float = V.out_back(k / 0.3)
			var f9:float = 1.0 - V.seg(k,0.5,1.0)
			V.sprite(ci,"k_magic02",p9,r9 * 3.4 * e9,Color(0.45,1.0,0.6,0.85 * f9),t * 1.5)
			V.sprite(ci,"k_light03",p9,r9 * 3.0,Color(0.4,1.0,0.55,0.4 * f9))
		"thunder":
			var p10:Vector2 = _v("pos")
			var r10:float = _f("radius",70.0)
			var strikes:Array[float] = [0.0,0.18,0.34]
			for si:int in strikes.size():
				var kk10:float = V.seg(k,strikes[si],strikes[si] + 0.22)
				if kk10 <= 0.0 or kk10 >= 1.0: continue
				var top:Vector2 = p10 + Vector2((si - 1) * 30.0,-560)
				V.sprite_line(ci,"k_spark06" if si % 2 == 0 else "k_spark05",top,p10,r10 * 1.3,Color(0.7,0.85,1.0,1.0 - kk10),true)
				V.sprite(ci,"k_flare01",p10,r10 * 5.0,Color(0.7,0.85,1.0,1.0 - kk10),0.0,Vector2(1.0,0.3))
			V.sprite(ci,"k_scorch01",p10,r10 * 2.4 * V.out_expo(k / 0.2),Color(0.6,0.8,1.0,0.8 * (1.0 - k)))
		"teleport":
			var a11:Vector2 = _v("a")
			var b11:Vector2 = _v("b")
			V.anim(ci,"a_bluering",a11,90.0,1.0 - k,Color(0.6,0.95,1.0,0.9))
			V.anim(ci,"a_bluering",b11,110.0,k,Color(0.6,0.95,1.0,0.9))
			V.sprite(ci,"k_twirl01",a11,80.0 * (1.0 - k),Color(0.6,0.95,1.0,1.0 - k),-t * 20.0)
			V.sprite_line(ci,"k_trace07",a11,b11,24.0 * (1.0 - k),Color(0.7,0.95,1.0,0.8 * (1.0 - k)),true)
		"wheel_turn":
			var p12:Vector2 = _v("pos")
			var r12:float = _f("radius",22.0)
			var f12:float = 1.0 - V.seg(k,0.6,1.0)
			V.anim(ci,"a_pfx_goldring",p12,r12 * 5.0,V.seg(k,0.0,0.9),Color(1,1,1,1))
			V.sprite(ci,"k_magic02",p12,r12 * 4.0 * V.out_back(k / 0.3),Color(1.0,0.85,0.4,0.8 * f12),V.out_back(V.seg(k,0.1,0.55),2.2) * TAU / 8.0)
			V.sprite(ci,"k_flare01",p12,r12 * 7.0,Color(1.0,0.85,0.45,0.8 * f12),0.0,Vector2(1.0,0.25))
		"shockwave":
			var p13:Vector2 = _v("pos")
			var r13:float = _f("radius",200.0)
			var c13:Color = _c("color",Color(0.6,0.9,1.0))
			if c13.get_luminance() < 0.3: c13 = Color(0.55,0.3,0.9)
			V.sprite(ci,"k_circle02",p13,r13 * 2.1 * V.out_expo(k),Color(c13,0.8 * (1.0 - k)))
			V.sprite(ci,"k_circle04",p13,r13 * 1.5 * V.out_cubic(k),Color(c13,0.5 * (1.0 - k)))
