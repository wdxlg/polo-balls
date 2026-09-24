extends Node2D
# Presentation only: never a projectile, network endpoint, or enchantable item.
const LAYERS = preload("res://Images/characters/我的世界/native_frames/hand_pounce/drowned_hand_layers.gd")
const FLASH = preload("res://scripts/effects/我的世界/trident_refill_flash.gdshader")
const HELD_SCALE:float = 3.0
const HAND_LIFT:Vector2=Vector2(0,-4)
var unit:Node2D
var weapon:Sprite2D
var flash_material:ShaderMaterial
var record:Dictionary = {}
var opacity:float = 0.0
var is_ghost:bool = false
func _ready() -> void:
	set_as_top_level(true)
	z_as_relative = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	weapon = Sprite2D.new()
	weapon.name = "RightHandTrident"
	flash_material = ShaderMaterial.new()
	flash_material.shader = FLASH
	weapon.material = flash_material
	add_child(weapon)
	visible = false
func _process(delta:float) -> void:
	# Between snapshots, replicas interpolate only the ghost; they never refill.
	if is_instance_valid(unit) and not unit.is_multiplayer_authority() and unit._refill_left>=0.0:
		if unit.health>0 and unit.is_combat_runtime_active() and not Game.now_stop_state and not get_tree().paused:
			unit._refill_left = maxf(unit._refill_left-maxf(delta,0.0),0.0)
	sync_pose()
func desired_world_axis() -> Vector2:
	# Idle grip points up; only the actual throw preparation turns it sideways.
	if unit._catch_left>0.0:
		var p:float=1.0-unit._catch_left/maxf(unit.trident_catch_duration,0.01)
		var side:float=1.0 if unit._visual_facing_flipped_h else -1.0
		return Vector2.UP.rotated(side*0.95*(1.0-smoothstep(0.0,1.0,p)))
	if unit._throw_left<0.0: return Vector2.UP
	var target:Variant=unit._throw_target.get_ref() if unit._throw_target!=null else null
	var right:bool=unit._visual_facing_flipped_h
	if is_instance_valid(target): right=target.global_position.x>=unit.global_position.x
	var progress:float=clampf((1.0-unit._throw_left/maxf(unit.trident_throw_windup,0.01))*1.5,0.0,1.0)
	return Vector2.from_angle(lerp_angle(-PI*0.5,0.0 if right else PI,smoothstep(0.0,1.0,progress)))
func sync_pose() -> void:
	visible = false
	opacity = 0.0
	is_ghost = false
	if not is_instance_valid(unit) or unit.health<=0 or unit.is_queued_for_deletion(): return
	var driver:Node = unit.mc_native_animation
	if not is_instance_valid(driver) or not driver.ready_visual: return
	var held:bool = unit.has_trident and is_instance_valid(unit._trident) and unit._trident.flight_state==0
	is_ghost = not held and not is_instance_valid(unit._trident) and unit._refill_left>=0.0
	if not held and not is_ghost: return
	record = driver.hand_frame_record()
	if record.is_empty(): return
	opacity = 1.0 if held else clampf(1.0-unit._refill_left/maxf(unit.trident_refill_delay,0.1),0.0,1.0)
	var facing := Transform2D.IDENTITY
	if unit._visual_facing_flipped_h: facing.x.x = -1.0
	global_transform = driver.sprite.global_transform*facing
	global_position+=HAND_LIFT
	var depth:int = 0
	var canvas:CanvasItem = driver.sprite
	while canvas!=null:
		depth += canvas.z_index
		if not canvas.z_as_relative: break
		var ancestor:Node = canvas.get_parent()
		while ancestor!=null and not ancestor is CanvasItem and not ancestor is CanvasLayer and not ancestor is Viewport:
			ancestor = ancestor.get_parent()
		canvas = ancestor as CanvasItem
	z_index = clampi(depth+1,-4096,4096)
	weapon.texture = record.item
	weapon.modulate = Color(1.0,1.0,1.0,opacity)
	var size:float = HELD_SCALE*(unit._trident.refill_scale() if held else 1.0)
	weapon.scale = Vector2.ONE*size
	var path:PackedVector2Array=PackedVector2Array(record.path)
	var shaft:Vector2=path[path.size()-1]-path[0] if path.size()>1 else Vector2(-1,1)
	var local_axis:Vector2=global_transform.basis_xform_inv(desired_world_axis()).normalized()
	weapon.rotation=local_axis.angle()-shaft.angle()
	# Rotate/scale around the hand, never the center of the full-frame item texture.
	var grip:Vector2=Vector2(record.grip)
	weapon.position=grip-grip.rotated(weapon.rotation)*size
	flash_material.set_shader_parameter("refill_flash",unit._trident.refill_flash() if held else 0.0)
	visible = true
