extends RefCounted
## Shared exact hurt-shape sweep extracted from diamond spear. No damage policy here.
const TOOLS = preload("res://scripts/characters/投稿角色工具.gd")

static func contacts(caster:ball,start:Vector2,finish:Vector2,radius:float,excluded:Dictionary,anchor:Vector2=Vector2.INF,terrain_occlusion:bool=true) -> Array[Dictionary]:
	var out:Array[Dictionary] = []
	if not is_instance_valid(caster) or not caster.is_inside_tree(): return out
	var shape := CapsuleShape2D.new()
	shape.radius = maxf(radius,0.2)
	shape.height = start.distance_to(finish)+shape.radius*2.0
	var pose := Transform2D((finish-start).angle()-PI*0.5,(start+finish)*0.5)
	var space:PhysicsDirectSpaceState2D = caster.get_world_2d().direct_space_state
	for raw:Node in TOOLS.targeting_candidates(caster):
		var target:ball = raw as ball
		if not is_instance_valid(target) or target.is_queued_for_deletion() or not TOOLS.is_enemy(caster,target): continue
		if target.has_method(&"multi_part_hurt_shapes"):
			# Multi-part bodies (grown cactus): every part the blade crosses is hit once per swing.
			_part_contacts(caster,target,shape,pose,start,finish,excluded,anchor,space,out,terrain_occlusion)
			continue
		if excluded.has(target.get_instance_id()): continue
		var area:Area2D = target.self_hurtbox
		if area == null: continue
		var touches:bool = false
		for child:Node in area.get_children():
			if child is CollisionShape2D and not child.disabled and child.shape!=null and shape.collide(pose,child.shape,child.global_transform):
				touches = true
				break
		if not touches: continue
		# Actual target position, never the controlled attacker's mouse aim.
		var point:Vector2 = Geometry2D.get_closest_point_to_segment(target.global_position,start,finish)
		if terrain_occlusion and anchor.is_finite() and not _clear(space,caster,anchor,point): continue
		if terrain_occlusion and (not _clear(space,caster,start,point) or not _clear(space,caster,point,target.global_position)): continue
		out.append({"target":target,"point":point})
	return out

static func _part_contacts(caster:ball,target:ball,shape:Shape2D,pose:Transform2D,start:Vector2,finish:Vector2,excluded:Dictionary,anchor:Vector2,space:PhysicsDirectSpaceState2D,out:Array[Dictionary],terrain_occlusion:bool) -> void:
	var parts:Array = target.call(&"multi_part_hurt_shapes")
	for i:int in range(parts.size()):
		var part:CollisionShape2D = parts[i] as CollisionShape2D
		var key:String = "%d:%d" % [target.get_instance_id(),i]
		if part == null or not is_instance_valid(part) or part.disabled or part.shape == null or excluded.has(key): continue
		if not shape.collide(pose,part.shape,part.global_transform): continue
		var center:Vector2 = part.global_position
		var point:Vector2 = Geometry2D.get_closest_point_to_segment(center,start,finish)
		if part.shape is RectangleShape2D:
			# Keep the reported impact inside the struck part (the blade line may pass beside it).
			var half:Vector2 = (part.shape as RectangleShape2D).size*0.5
			var local:Vector2 = part.global_transform.affine_inverse()*point
			point = part.global_transform*Vector2(clampf(local.x,-half.x,half.x),clampf(local.y,-half.y*0.98,half.y*0.98))
		if terrain_occlusion and anchor.is_finite() and not _clear(space,caster,anchor,point): continue
		if terrain_occlusion and (not _clear(space,caster,start,point) or not _clear(space,caster,point,center)): continue
		excluded[key] = true
		out.append({"target":target,"point":point,"part":i})

static func _clear(space:PhysicsDirectSpaceState2D,caster:ball,start:Vector2,finish:Vector2) -> bool:
	if start.distance_squared_to(finish)<0.000001: return true
	var ray := PhysicsRayQueryParameters2D.create(start,finish,1,[caster.get_rid()])
	return space.intersect_ray(ray).is_empty()
