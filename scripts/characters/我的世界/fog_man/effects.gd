extends Node2D
var actor:Node2D
var bursts:Array[Dictionary] = []
func _ready() -> void:
	top_level = true
	global_transform = Transform2D.IDENTITY
	z_as_relative = false
	z_index = 97
func burst(kind:String,point:Vector2) -> void:
	if bursts.size()>=8: bursts.pop_front()
	bursts.append({"kind":kind,"point":point,"age":0.0})
	queue_redraw()
func _process(delta:float) -> void:
	if not is_instance_valid(actor): queue_free(); return
	if not actor.is_combat_runtime_active(): return
	for i:int in range(bursts.size()-1,-1,-1):
		bursts[i].age += delta
		if bursts[i].age>=0.65: bursts.remove_at(i)
	queue_redraw()
func _draw() -> void:
	for b:Dictionary in bursts:
		var fade:float = 1.0-b.age/0.65
		if b.kind=="thunder":
			if b.age>0.30: continue
			var points := PackedVector2Array()
			for i:int in range(9): points.append(b.point+Vector2(sin(float(i)*6.7)*9.0*(1.0-float(i)/8.0),-110.0+float(i)*13.75))
			draw_polyline(points,Color(0.55,0.78,1,fade*0.22),9.0,true)
			draw_polyline(points,Color(0.87,0.95,1,fade),2.0,true)
		else:
			for i:int in range(14):
				var offset:Vector2 = Vector2.RIGHT.rotated(float(i)*2.4)*(4.0+b.age*25.0)
				offset.y -= b.age*20.0
				draw_circle(b.point+offset,3.0+float(i%3),Color(0.58,0.64,0.68,fade*0.3))
