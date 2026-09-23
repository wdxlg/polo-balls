extends Node2D
## Bounded, world-space snapshots of the original sword. Pure presentation, no hitboxes.
const LIMIT:int = 10
const INTERVAL:float = 0.012
const OPACITY:float = 0.30
const COPY_PARAMETERS:Array[StringName] = [&"power",&"hit_white_color",&"defualt_color_mix",&"default_color",&"snow_cold",&"snow_freeze_offset"]
var unit:Node2D
var samples:Array[Dictionary] = []
var _free:Array[Sprite2D] = []
var _created:int = 0

func _ready() -> void:
	set_as_top_level(true)
	global_transform = Transform2D.IDENTITY
	z_as_relative = false
	z_index = unit.image.z_index-1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false
	add_to_group("MCCopperSwingTrail")

func _source_visible() -> bool:
	return is_instance_valid(unit) and unit.health>0 and is_instance_valid(unit.image) and unit.is_visible_in_tree() and unit.image.visible

func clear() -> void:
	for sample:Dictionary in samples:
		var sprite:Sprite2D = sample.sprite
		sprite.hide()
		_free.append(sprite)
	samples.clear()
	visible = false

func advance(delta:float) -> void:
	if not _source_visible():
		clear()
		return
	if not unit.is_combat_runtime_active() or get_tree().paused: return
	var dt:float = maxf(delta,0.0)
	var lifetime:float = maxf(unit.trail_lifetime,0.01)
	for i:int in range(samples.size()-1,-1,-1):
		samples[i].age += dt
		if samples[i].age>=lifetime:
			var sprite:Sprite2D = samples[i].sprite
			sprite.hide()
			_free.append(sprite)
			samples.remove_at(i)
		else: _fade(samples[i])
	visible = not samples.is_empty()

func _fade(sample:Dictionary) -> void:
	var tint:Color = sample.tint
	tint.a *= OPACITY*pow(1.0-clampf(float(sample.age)/maxf(unit.trail_lifetime,0.01),0.0,1.0),1.5)
	sample.sprite.modulate = tint

func _take_sprite() -> Sprite2D:
	if not _free.is_empty(): return _free.pop_back()
	if _created<LIMIT:
		var sprite := Sprite2D.new()
		sprite.name = "SwordEcho%d" % _created
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)
		_created += 1
		return sprite
	var oldest:Dictionary = samples.pop_front()
	return oldest.sprite

func record_segment(from_phase:float,to_phase:float) -> void:
	if not _source_visible() or not unit.is_combat_runtime_active() or get_tree().paused: return
	if not unit._swing_active or unit._windup_left>0.0 or unit.dizziness or not unit.Can_Attack or unit.is_damage_output_disabled(): return
	if to_phase<=from_phase: return
	var duration:float = maxf(unit._swing_duration,0.001)
	var first:int = int(floor(from_phase*duration/INTERVAL))+1
	var last:int = int(floor(to_phase*duration/INTERVAL))
	# Sub-frame samples follow the real accelerating arc, not a linear smear between
	# endpoints. This also stays bounded on low-FPS / coarse simulation frames.
	for index:int in range(maxi(first,last-LIMIT+1),last+1):
		var phase:float = float(index)*INTERVAL/duration
		if phase<unit.HIT_BEGIN or phase>1.0: continue
		var angular_speed:float = 2.0*unit.SWING_HALF_ARC*unit.SWING_EASE_POWER*pow(phase,unit.SWING_EASE_POWER-1.0)/duration
		if angular_speed<unit.trail_min_angular_speed: continue
		var age:float = (to_phase-phase)*duration
		if age>=unit.trail_lifetime: continue
		var sprite:Sprite2D = _take_sprite()
		sprite.texture = unit.image.texture
		sprite.material = unit.image.material
		sprite.centered = unit.image.centered
		sprite.offset = unit.image.offset
		sprite.flip_h = unit.image.flip_h
		sprite.flip_v = unit.image.flip_v
		sprite.global_transform = unit.weapon_transform(phase)
		# Each echo keeps its own rust/mirror/flash state, rather than changing later
		# when the live sword turns, oxidizes or is cleansed by lightning.
		sprite.set_instance_shader_parameter("rust_level",unit.rust)
		sprite.set_instance_shader_parameter("sprite_flip_h",0.0 if unit._face_right else 1.0)
		for parameter:StringName in COPY_PARAMETERS:
			var value:Variant = unit.image.get_instance_shader_parameter(parameter)
			if value!=null: sprite.set_instance_shader_parameter(parameter,value)
		var sample:Dictionary = {"sprite":sprite,"age":age,"pose":sprite.global_transform,"phase":phase,"angular_speed":angular_speed,"tint":unit.image.modulate*unit.image.self_modulate*unit.graphics.modulate}
		samples.append(sample)
		_fade(sample)
		sprite.show()
	visible = not samples.is_empty()
