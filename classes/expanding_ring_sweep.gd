extends RefCounted
## Shared swept annulus geometry; callers own damage, authority and hit bookkeeping.
const SWEEP = preload("res://classes/weapon_tip_sweep.gd")

static func segments(center:Vector2,previous:float,current:float,half_width:float=3.5,sides:int=48) -> Array[Dictionary]:
	var result:Array[Dictionary] = []
	var middle:float = (previous+current)*0.5
	var width:float = half_width+absf(current-previous)*0.5
	for i:int in range(sides):
		result.append({"a":center+Vector2.from_angle(TAU*float(i)/sides)*middle,"b":center+Vector2.from_angle(TAU*float(i+1)/sides)*middle,"r":width})
	return result

static func contacts(caster:ball,center:Vector2,previous:float,current:float,half_width:float,excluded:Dictionary,sides:int=48) -> Array[Dictionary]:
	var result:Array[Dictionary] = []
	var seen:Dictionary = excluded.duplicate()
	var candidates:Array[Dictionary] = SWEEP.contacts(caster,center,center,maxf(previous,current)+half_width,seen,center)
	if candidates.is_empty(): return result
	var bands:Array[Dictionary] = segments(center,previous,current,half_width,sides)
	for band:Dictionary in bands:
		var capsule:=CapsuleShape2D.new()
		capsule.radius = band.r
		capsule.height = Vector2(band.a).distance_to(band.b)+capsule.radius*2.0
		band.shape = capsule
		band.pose = Transform2D((Vector2(band.b)-Vector2(band.a)).angle()-PI*0.5,(Vector2(band.a)+Vector2(band.b))*0.5)
	for hit:Dictionary in candidates:
		var target:ball = hit.target
		if not is_instance_valid(target) or target.is_queued_for_deletion() or target.get_world_2d()!=caster.get_world_2d() or seen.has(target.get_instance_id()): continue
		var shapes:Array = target.call("multi_part_hurt_shapes") if target.has_method("multi_part_hurt_shapes") else target.self_hurtbox.get_children()
		var touches:bool = false
		for band:Dictionary in bands:
			for child:Node in shapes:
				if child is CollisionShape2D and not child.disabled and child.shape!=null and (band.shape as Shape2D).collide(band.pose,child.shape,child.global_transform):
					var point:Vector2 = Geometry2D.get_closest_point_to_segment(child.global_position,band.a,band.b)
					seen[target.get_instance_id()] = true
					result.append({"target":target,"point":point})
					touches = true
					break
			if touches: break
	return result
