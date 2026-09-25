extends Node2D
## Fired original Minecraft amethyst item texture: world-space straight trajectory.
const TEXTURE:Texture2D = preload("res://Images/characters/我的世界/sulfur_cube/source/amethyst_shard.png")
const SPEED:float = 270.0
const RADIUS:float = 3.0
const LIFETIME:float = 1.25
var source_ref:WeakRef
var direction:Vector2 = Vector2.RIGHT
var age:float = 0.0
var sprite:Sprite2D

func setup(source:ball,point:Vector2,heading:Vector2) -> void:
	source_ref = weakref(source)
	global_position = point
	direction = heading.normalized() if heading.length_squared() > 0.001 else Vector2.RIGHT
	sprite = Sprite2D.new()
	sprite.texture = TEXTURE
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.rotation = direction.angle()+PI*0.5
	sprite.scale = Vector2.ONE*0.7
	add_child(sprite)
	z_as_relative = false
	z_index = 105
	add_to_group("BattleTransient")
	add_to_group("AI_Hazard")

func _physics_process(delta:float) -> void:
	var owner:Variant = source_ref.get_ref() if source_ref != null else null
	if not is_instance_valid(owner) or owner.health <= 0:
		queue_free()
		return
	if not owner.is_combat_runtime_active(): return
	age += delta
	if age >= LIFETIME:
		queue_free()
		return
	var end:Vector2 = global_position+direction*SPEED*delta
	if owner.is_multiplayer_authority():
		var excludes:Array[RID] = [owner.get_rid()]
		for _i:int in range(12):
			var query := PhysicsRayQueryParameters2D.create(global_position,end,3,excludes)
			query.collide_with_areas = false
			var hit:Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
			if hit.is_empty(): break
			var collider:Variant = hit.get("collider",null)
			if collider is ball and owner.call("mc_enemy",collider):
				owner.call("_damage_with_impact",collider,owner.attack_damage(1.35),hit.get("position",end))
				queue_free()
				return
			if collider is CollisionObject2D and collider is ball:
				var rid:RID = (collider as CollisionObject2D).get_rid()
				if not excludes.has(rid): excludes.append(rid)
				continue
			queue_free() # Terrain/obstacle, not a projectile that passes through walls.
			return
	global_position = end

func get_ai_hazard_info() -> Dictionary:
	var owner:Variant = source_ref.get_ref() if source_ref != null else null
	if not is_instance_valid(owner) or owner.health <= 0 or is_queued_for_deletion(): return {}
	return {"shape":"circle","position":global_position,"radius":RADIUS,"damage":owner.attack_damage(1.35),"source":owner,"kind":"sulfur_amethyst_shard"}
