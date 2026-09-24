extends RefCounted
## Independent world-space followers, never a leader/follower train.
var positions:Array[Vector2] = []
var phases:Array[float] = []
var serial:int = 0
var next_spawn:Vector2 = Vector2.ZERO
var has_spawn:bool = false
func resize(count:int,origin:Vector2) -> void:
	while positions.size()<count:
		positions.append(next_spawn if has_spawn else origin)
		has_spawn = false
		phases.append(float(serial)*TAU*0.61803398875)
		serial += 1
	positions.resize(count)
	phases.resize(count)
func advance(count:int,origin:Vector2,time:float,delta:float,radius:float,rate:float,squash:float = 0.72,lift:float = 5.0,bob:float = 2.0,constrain:Callable = Callable()) -> void:
	resize(count,origin)
	var blend:float = 1.0-exp(-5.5*maxf(delta,0.0))
	for i:int in range(count):
		var angle:float = phases[i]+time*rate
		var offset:=Vector2(cos(angle)*radius,sin(angle)*radius*squash-lift+sin(time*2.0+phases[i])*bob)
		var target:Vector2 = origin+offset
		if constrain.is_valid(): target = constrain.call(target)
		positions[i] = positions[i].lerp(target,blend)
func take_first(fallback:Vector2) -> Vector2:
	if positions.is_empty(): return fallback
	phases.pop_front()
	return positions.pop_front()
func take_at(index:int,fallback:Vector2) -> Vector2:
	if index<0 or index>=positions.size(): return fallback
	phases.pop_at(index)
	return positions.pop_at(index)
func clear() -> void:
	positions.clear()
	phases.clear()
