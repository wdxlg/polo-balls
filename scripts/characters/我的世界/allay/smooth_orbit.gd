extends "res://scripts/characters/我的世界/allay/orbit.gd"
## Critically damped world-space followers: velocity is continuous through turns.
var velocities:Array[Vector2] = []
const RESPONSE:float = 14.0
func resize(count:int,origin:Vector2) -> void:
	super.resize(count,origin)
	velocities.resize(count)
func advance(count:int,origin:Vector2,time:float,delta:float,radius:float,rate:float,squash:float=0.72,lift:float=5.0,bob:float=2.0,constrain:Callable=Callable()) -> void:
	resize(count,origin)
	if delta<=0.0: return
	var decay:float=exp(-RESPONSE*delta)
	for i:int in range(count):
		var angle:float=phases[i]+time*rate
		var target:Vector2=origin+Vector2(cos(angle)*radius,sin(angle)*radius*squash-lift+sin(time*2.0+phases[i])*bob)
		if constrain.is_valid(): target=constrain.call(target)
		var offset:Vector2=positions[i]-target
		var change:Vector2=(velocities[i]+offset*RESPONSE)*delta
		positions[i]=target+(offset+change)*decay
		velocities[i]=(velocities[i]-change*RESPONSE)*decay
func take_first(fallback:Vector2) -> Vector2:
	return take_at(0,fallback)
func take_at(index:int,fallback:Vector2) -> Vector2:
	if index>=0 and index<positions.size(): velocities.remove_at(index)
	return super.take_at(index,fallback)
func clear() -> void:
	super.clear()
	velocities.clear()
