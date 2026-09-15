extends Node2D
## One draw node per event. No gameplay, global time scaling, screen flash or RNG.
var kind:int
var delta_point:Vector2
var tint:Color
var radius:float
var lifetime:float
var elapsed:float = 0.0
func configure(value:int,start:Vector2,finish:Vector2,color:Color,size:float,duration:float) -> void:
	kind = value
	global_position = start
	delta_point = finish - start
	tint = color
	radius = size
	lifetime = maxf(duration,0.05)
	z_as_relative = false
	z_index = 7
func _process(delta:float) -> void:
	# Keep telegraph and action clocks aligned during manual time stop.
	if Game.now_stop_state:
		return
	elapsed += delta
	if elapsed >= lifetime:
		queue_free()
	else:
		queue_redraw()
func _draw() -> void:
	if lifetime <= 0.0:
		return
	var t:float = clampf(elapsed/lifetime,0.0,1.0)
	var color:Color = tint
	color.a = 1.0-t
	if kind == 0:
		color.a = 0.28 + 0.4*t
		if radius > 0.0:
			draw_arc(delta_point,radius,-PI/2,TAU*t-PI/2,40,color,1.4,true)
			draw_circle(delta_point,3.0,color)
		else:
			for i:int in range(12):
				draw_line(delta_point*(float(i)/12),delta_point*((float(i)+0.55)/12),color,1.2,true)
	elif kind == 2:
		draw_line(Vector2.ZERO,delta_point,Color(tint,0.18*(1.0-t)),maxf(radius*4.0,6.0),true)
		draw_line(Vector2.ZERO,delta_point,color,maxf(radius,1.2),true)
		draw_line(Vector2.ZERO,delta_point,Color(1.0,0.96,0.84,(1.0-t)*0.85),1.0,true)
	elif kind == 4:
		draw_arc(Vector2.ZERO,radius,-PI,PI,40,Color(tint,0.15),7.0,true)
		for i:int in range(6):
			var a:float = float(i)*TAU/6.0
			draw_arc(Vector2.ZERO,radius,a,a+0.7,8,Color(tint,0.85),2.5,true)
	else:
		var r:float = radius*(0.25+0.75*sin(t*PI*0.5))
		draw_arc(Vector2.ZERO,r,0,TAU,40,color,2.0,true)
		for i:int in range(8):
			var direction:Vector2 = Vector2.from_angle(float(i)*TAU/8.0+(t*0.4 if kind==3 else 0.0))
			draw_line(direction*r*0.72,direction*r*(1.18 if kind==1 else 0.9),color,2.0,true)
