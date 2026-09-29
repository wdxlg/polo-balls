extends Control
## Bounded, deterministic UI-only effects. Advanced by the overlay's real-time clock.
signal portrait_arrived
const MAX_FLIGHTS:int = 4
const MAX_BURSTS:int = 8
var _flights:Array[Dictionary] = []
var _bursts:Array[Dictionary] = []
var _rings:Array[Dictionary] = []
var _gains:Array[Dictionary] = []
var _time:float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func launch_result(texture:Texture2D,start:Vector2,end:Vector2,color:Color,extent:float) -> void:
	if _flights.size()>=MAX_FLIGHTS: _flights.pop_front()
	_flights.append({"texture":texture,"start":start,"end":end,"color":color,"extent":clampf(extent,32,76),"age":0.0,"duration":0.38})
	burst(start,color,8)

func burst(at:Vector2,color:Color,count:int = 12) -> void:
	if _bursts.size()>=MAX_BURSTS: _bursts.pop_front()
	_bursts.append({"at":at,"color":color,"age":0.0,"count":count,"seed":_time})

func ripple(rect:Rect2,color:Color) -> void:
	if _rings.size()>=6: _rings.pop_front()
	_rings.append({"rect":rect,"color":color,"age":0.0})

func experience_gain(at:Vector2) -> void:
	if _gains.size()>=4: _gains.pop_front()
	_gains.append({"at":at,"age":0.0})

func finish() -> void:
	_flights.clear()
	queue_redraw()

func advance(delta:float) -> void:
	_time += delta
	for index:int in range(_flights.size()-1,-1,-1):
		var flight:Dictionary = _flights[index]
		flight.age += delta
		if float(flight.age)>=float(flight.duration):
			burst(flight.end,flight.color,14)
			portrait_arrived.emit()
			_flights.remove_at(index)
	for effects:Array in [_bursts,_rings,_gains]:
		for index:int in range(effects.size()-1,-1,-1):
			effects[index].age += delta
			if float(effects[index].age)>0.7: effects.remove_at(index)
	queue_redraw()

func _flight_position(flight:Dictionary,fraction:float) -> Vector2:
	var start:Vector2 = flight.start
	var end:Vector2 = flight.end
	var bend := Vector2((end.x-start.x)*0.16,-90.0)
	var control:Vector2 = (start+end)*0.5+bend
	var t:float = clampf(fraction,0.0,1.0)
	return start*(1-t)*(1-t)+control*2*(1-t)*t+end*t*t

func _draw() -> void:
	for flight:Dictionary in _flights:
		var t:float = clampf(float(flight.age)/float(flight.duration),0.0,1.0)
		var eased:float = 1.0-pow(1.0-t,2.0)
		var at:Vector2 = _flight_position(flight,eased)
		var color:Color = flight.color
		# A short pixel comet rather than a screen-filling trail.
		for tail:int in range(6,0,-1):
			var trail_at:Vector2 = _flight_position(flight,maxf(0.0,eased-tail*0.032))
			var side:float = 2.0+(6-tail)*0.7
			draw_rect(Rect2(trail_at-Vector2.ONE*side*0.5,Vector2.ONE*side),Color(color,(1.0-float(tail)/7.0)*0.7))
		var side:float = float(flight.extent)*lerpf(0.8,1.0,eased)
		var rect := Rect2(at-Vector2.ONE*side*0.5,Vector2.ONE*side)
		draw_rect(rect.grow(4),Color("111a1a"))
		draw_rect(rect.grow(4),Color(color,0.85),false,2)
		var texture:Texture2D = flight.texture
		if texture!=null:
			var fit:float = minf(side/maxf(texture.get_width(),1),side/maxf(texture.get_height(),1))
			var extent:Vector2 = texture.get_size()*fit
			draw_texture_rect(texture,Rect2(at-extent*0.5,extent),false)
		else:
			draw_rect(Rect2(at-Vector2(3,3),Vector2(6,6)),color)
	for burst:Dictionary in _bursts:
		var age:float = burst.age
		var fade:float = pow(maxf(0.0,1.0-age/0.7),2.0)
		for index:int in range(int(burst.count)):
			var angle:float = float(index)*TAU/float(burst.count)+float(burst.seed)*0.7
			var speed:float = 28.0+float(index%4)*18.0
			var offset:Vector2 = Vector2.from_angle(angle)*speed*age+Vector2(0,35*age*age)
			var at:Vector2 = Vector2(burst.at)+offset
			var side:float = 2.0+float(index%3)
			var color:Color = Color.WHITE if index%4==0 else Color(burst.color)
			draw_rect(Rect2(at.round(),Vector2.ONE*side),Color(color,fade))
	for ring:Dictionary in _rings:
		var age:float = ring.age
		var progress:float = clampf(age/0.55,0,1)
		var rect:Rect2 = ring.rect
		draw_rect(rect.grow(3+progress*13),Color(ring.color,(1-progress)*0.65),false,2)
		if age<0.22: draw_rect(rect,Color(ring.color,(1-age/0.22)*0.14))
	for gain:Dictionary in _gains:
		var age:float = gain.age
		var fade:float = clampf(1.0-age/0.7,0,1)
		var at:Vector2 = gain.at
		for index:int in range(6):
			var offset := Vector2((index-2.5)*5*age,-(20+index%3*12)*age)
			draw_rect(Rect2((at+offset).round(),Vector2(2,2)),Color(0.65,1.0,0.27,fade))
		var font:Font = get_theme_font("font","Label")
		var text_at:Vector2 = at+Vector2(8,-10-age*25)
		draw_string_outline(font,text_at,"+1",HORIZONTAL_ALIGNMENT_LEFT,-1,16,2,Color(0,0,0,fade))
		draw_string(font,text_at,"+1",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color(0.65,1.0,0.27,fade))
