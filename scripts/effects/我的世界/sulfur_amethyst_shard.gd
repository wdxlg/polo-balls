extends Node2D
## The exact attached native cluster model, frozen at launch then translated.
const CRYSTAL = preload("res://scripts/effects/我的世界/sulfur_amethyst_crystal.gd")
const DAMAGE_MULT:float = 0.23625 # 2026-09-27: halve current flying-crystal damage again (0.4725 * 0.5).
const SPEED:float = 270.0
const RADIUS:float = 3.0
const LIFETIME:float = 1.25
var source_ref:WeakRef
var direction:Vector2 = Vector2.RIGHT
var age:float = 0.0
var sprite:Sprite2D
var model_viewport:SubViewport
var crystal:Node3D

func setup(source:ball,point:Vector2,heading:Vector2,appearance:Dictionary = {}) -> void:
	source_ref = weakref(source)
	global_position = point
	direction = heading.normalized() if heading.length_squared() > 0.001 else Vector2.RIGHT
	model_viewport = SubViewport.new()
	model_viewport.size = appearance.get("viewport_size",Vector2i(160,160))
	model_viewport.transparent_bg = true
	model_viewport.own_world_3d = true
	model_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(model_viewport)
	crystal = CRYSTAL.new()
	crystal.length = float(appearance.get("length",1.6))
	crystal.width = float(appearance.get("width",0.82))
	crystal.transform = appearance.get("transform",Transform3D.IDENTITY)
	model_viewport.add_child(crystal)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = float(appearance.get("camera_size",4.2))
	camera.transform = appearance.get("camera_transform",Transform3D(Basis.IDENTITY,Vector3(0,0,6)))
	model_viewport.add_child(camera)
	camera.make_current()
	sprite = Sprite2D.new()
	sprite.texture = model_viewport.get_texture()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	if appearance.has("canvas_transform"):
		# The projectile origin is its real tip. Preserve the whole launch-frame
		# projected shape behind it, including source squish, scale and camera.
		sprite.transform = appearance.canvas_transform
		sprite.position -= point
	else:
		sprite.scale = Vector2.ONE*0.2
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
				if owner.call("_damage_with_impact",collider,owner.attack_damage(DAMAGE_MULT),hit.get("position",end)):
					owner.call("_emit_sound",&"amethyst_break",hit.get("position",end))
				queue_free()
				return
			if collider is CollisionObject2D and collider is ball:
				var rid:RID = (collider as CollisionObject2D).get_rid()
				if not excludes.has(rid): excludes.append(rid)
				continue
			owner.call("_emit_sound",&"amethyst_break",hit.get("position",end))
			queue_free() # Terrain/obstacle, not a projectile that passes through walls.
			return
	global_position = end

func get_ai_hazard_info(_receiver:ball = null) -> Dictionary:
	var owner:Variant = source_ref.get_ref() if source_ref != null else null
	if not is_instance_valid(owner) or owner.health <= 0 or is_queued_for_deletion(): return {}
	return {"shape":"circle","position":global_position,"radius":RADIUS,"damage":owner.attack_damage(DAMAGE_MULT),"source":owner,"kind":"sulfur_amethyst_shard"}
