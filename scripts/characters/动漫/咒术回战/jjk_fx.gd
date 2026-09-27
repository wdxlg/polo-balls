extends Node2D
## 咒术回战一次性视觉特效（纯视觉，不结算伤害）。坐标全部为世界坐标。
## 由角色 RPC 在各端本地生成；挂在角色下、top_level，角色释放时随之清理。
var kind:String = ""
var data:Dictionary = {}
var life:float = 0.5
var t:float = 0.0
var _seed:int = 0

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

func _process(delta:float) -> void:
	if Game.now_stop_state: return
	t += delta
	if t >= life:
		queue_free()
		return
	queue_redraw()

func _v(key:String,fallback:Vector2 = Vector2.ZERO) -> Vector2:
	var value:Variant = data.get(key,fallback)
	return value if value is Vector2 else fallback

func _draw() -> void:
	var k:float = clampf(t / life,0.0,1.0)
	var fade:float = 1.0 - k
	var rng:RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed
	match kind:
		"ripple":
			var p:Vector2 = _v("pos")
			var r:float = float(data.get("radius",26.0))
			for i:int in 3:
				var rr:float = r * (0.7 + k * 0.6 + i * 0.18)
				draw_arc(p,rr,0.0,TAU,40,Color(0.55,0.9,1.0,0.55 * fade),2.0 - i * 0.5,true)
		"red_burst":
			var p2:Vector2 = _v("pos")
			var r2:float = float(data.get("radius",80.0))
			draw_circle(p2,r2 * (0.35 + 0.65 * k),Color(1.0,0.15,0.1,0.35 * fade))
			draw_arc(p2,r2 * (0.4 + 0.7 * k),0.0,TAU,48,Color(1.0,0.5,0.4,0.9 * fade),4.0,true)
			for i2:int in 10:
				var a:float = TAU * i2 / 10.0 + rng.randf() * 0.3
				draw_line(p2 + Vector2.from_angle(a) * r2 * 0.3 * k,p2 + Vector2.from_angle(a) * r2 * (0.6 + 0.6 * k),Color(1.0,0.3,0.2,fade),2.0,true)
		"purple_beam":
			var a3:Vector2 = _v("a")
			var b3:Vector2 = _v("b")
			var w:float = float(data.get("width",90.0))
			var grow:float = minf(1.0,t / 0.12)
			draw_line(a3,b3,Color(0.45,0.1,0.8,0.45 * fade),w * grow,true)
			draw_line(a3,b3,Color(0.75,0.4,1.0,0.8 * fade),w * 0.55 * grow,true)
			draw_line(a3,b3,Color(1.0,0.95,1.0,0.95 * fade),w * 0.18 * grow,true)
			draw_circle(b3,w * 0.7 * (1.0 + k),Color(0.7,0.3,1.0,0.3 * fade))
		"slash":
			var a4:Vector2 = _v("a")
			var b4:Vector2 = _v("b")
			var col:Color = data.get("color",Color(1,1,1)) as Color
			var width4:float = float(data.get("width",3.0))
			var head:float = minf(1.0,t / maxf(life * 0.25,0.01))
			var tail:float = clampf((t - life * 0.35) / maxf(life * 0.65,0.01),0.0,1.0)
			draw_line(a4.lerp(b4,tail),a4.lerp(b4,head),Color(col,fade),width4,true)
			draw_line(a4.lerp(b4,tail),a4.lerp(b4,head),Color(1,1,1,fade),maxf(1.0,width4 * 0.35),true)
		"cleave":
			var p5:Vector2 = _v("pos")
			var s5:float = float(data.get("size",36.0))
			for d:Vector2 in [Vector2(1,1),Vector2(1,-1),Vector2(1,0.2),Vector2(-0.3,1)]:
				var n:Vector2 = d.normalized() * s5 * (0.5 + 0.5 * minf(1.0,t * 8.0))
				draw_line(p5 - n,p5 + n,Color(1.0,0.2,0.25,fade),3.0,true)
				draw_line(p5 - n,p5 + n,Color(1,1,1,fade),1.0,true)
		"web":
			var p6:Vector2 = _v("pos")
			var r6:float = float(data.get("radius",180.0))
			for i6:int in 16:
				var a6:float = TAU * i6 / 16.0 + rng.randf_range(-0.1,0.1)
				draw_line(p6,p6 + Vector2.from_angle(a6) * r6 * minf(1.0,t * 6.0),Color(1,1,1,fade),2.0,true)
			for ring:int in 3:
				draw_arc(p6,r6 * (ring + 1) / 3.0,0.0,TAU,32,Color(1,0.85,0.85,0.7 * fade),1.5,true)
		"fuga_burst":
			var p7:Vector2 = _v("pos")
			var r7:float = float(data.get("radius",160.0))
			draw_circle(p7,r7 * (0.3 + 0.7 * k),Color(1.0,0.45,0.05,0.45 * fade))
			draw_circle(p7,r7 * (0.2 + 0.4 * k),Color(1.0,0.85,0.3,0.55 * fade))
			for i7:int in 18:
				var a7:float = TAU * i7 / 18.0 + rng.randf() * 0.4
				var l7:float = r7 * rng.randf_range(0.6,1.2) * (0.3 + 0.7 * k)
				draw_line(p7,p7 + Vector2.from_angle(a7) * l7,Color(1.0,0.5,0.1,fade),3.0,true)
		"world_slash":
			var a8:Vector2 = _v("a")
			var b8:Vector2 = _v("b")
			var w8:float = float(data.get("width",30.0))
			var open:float = minf(1.0,t / 0.08)
			draw_line(a8,b8,Color(0,0,0,0.9 * fade),w8 * open,true)
			draw_line(a8,b8,Color(1,1,1,fade),maxf(2.0,w8 * 0.12),true)
			var n8:Vector2 = (b8 - a8).orthogonal().normalized() * w8 * 0.6
			draw_line(a8 + n8,b8 + n8,Color(0.8,0.1,0.15,0.6 * fade),2.0,true)
			draw_line(a8 - n8,b8 - n8,Color(0.8,0.1,0.15,0.6 * fade),2.0,true)
		"black_flash":
			var p9:Vector2 = _v("pos")
			var r9:float = float(data.get("radius",60.0))
			draw_circle(p9,r9 * 0.35 * fade,Color(0,0,0,0.8 * fade))
			for i9:int in 7:
				var a9:float = rng.randf() * TAU
				var pts:PackedVector2Array = [p9]
				var cur:Vector2 = p9
				for j9:int in 5:
					cur += Vector2.from_angle(a9 + rng.randf_range(-0.8,0.8)) * r9 * 0.25
					pts.append(cur)
				draw_polyline(pts,Color(0.05,0,0,fade),5.0,true)
				draw_polyline(pts,Color(1.0,0.1,0.15,fade),2.0,true)
		"heal":
			var p10:Vector2 = _v("pos")
			var r10:float = float(data.get("radius",40.0))
			draw_arc(p10,r10 * (0.4 + 0.8 * k),0.0,TAU,40,Color(0.4,1.0,0.55,0.8 * fade),3.0,true)
			for i10:int in 6:
				var q10:Vector2 = p10 + Vector2(rng.randf_range(-r10,r10) * 0.6,-k * r10 + rng.randf_range(-6,6))
				draw_line(q10 - Vector2(0,5),q10 + Vector2(0,5),Color(0.5,1,0.6,fade),2.0)
				draw_line(q10 - Vector2(5,0),q10 + Vector2(5,0),Color(0.5,1,0.6,fade),2.0)
		"thunder":
			var p11:Vector2 = _v("pos")
			var r11:float = float(data.get("radius",110.0))
			draw_circle(p11,r11,Color(1.0,0.95,0.3,0.12 * fade))
			for i11:int in 9:
				var a11:float = rng.randf() * TAU
				var pts11:PackedVector2Array = [p11]
				var cur11:Vector2 = p11
				for j11:int in 6:
					cur11 += Vector2.from_angle(a11 + rng.randf_range(-0.9,0.9)) * r11 / 6.0
					pts11.append(cur11)
				draw_polyline(pts11,Color(1.0,1.0,0.6,fade),2.5,true)
		"teleport":
			var a12:Vector2 = _v("a")
			var b12:Vector2 = _v("b")
			draw_arc(a12,20.0 + k * 20.0,0.0,TAU,24,Color(0.6,0.95,1.0,fade),2.0,true)
			draw_arc(b12,40.0 - k * 20.0,0.0,TAU,24,Color(0.6,0.95,1.0,fade),2.0,true)
			draw_dashed_line(a12,b12,Color(0.6,0.95,1.0,0.5 * fade),1.5,6.0)
		"wheel_turn":
			var p13:Vector2 = _v("pos")
			draw_arc(p13,24.0 + k * 30.0,0.0,TAU,32,Color(1.0,0.9,0.5,fade),3.0,true)
		"shockwave":
			var p14:Vector2 = _v("pos")
			var r14:float = float(data.get("radius",200.0))
			var c14:Color = data.get("color",Color(0.6,0.9,1.0)) as Color
			draw_arc(p14,r14 * k,0.0,TAU,64,Color(c14,fade),6.0 * fade + 1.0,true)
		"text":
			var p15:Vector2 = _v("pos")
			var text:String = str(data.get("text",""))
			var size:int = int(data.get("size",34))
			var c15:Color = data.get("color",Color.WHITE) as Color
			var font:Font = ThemeDB.fallback_font
			var alpha:float = minf(1.0,t * 6.0) * minf(1.0,(life - t) * 3.0)
			var width15:float = font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
			var at:Vector2 = p15 + Vector2(-width15 * 0.5,-k * 10.0)
			draw_string_outline(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,6,Color(0,0,0,0.85 * alpha))
			draw_string(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color(c15,alpha))
