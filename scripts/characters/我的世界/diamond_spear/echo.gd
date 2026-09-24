extends Node2D
## A volley owns a fixed world origin and aim. Upgraded spears travel through once; neither mode homes.
## A top-level child retains world coordinates but is destroyed with its caster.
var caster:Node2D
var anchor:Vector2
var axis:Vector2 = Vector2.RIGHT
var visual_scale:Vector2 = Vector2.ONE
var lifetime:float = 0.44
var stroke_duration:float = 0.38
var stroke_distance:float = 42.0
var _wall_stroke_limit:float = 42.0
var _floor_stroke_limit:float = 42.0
var elapsed:float = 0.0
var previous_elapsed:float = 0.0
var attack_echo:bool = false
var piercing:bool = false
var accent:bool = false
var requires_skill:bool = false
var multiplier:float = 0.0
var hit_ids:Dictionary = {}
var sprite:Sprite2D
var previous_tip:Vector2
var tip_distance:float = 14.4
var tint:Color = Color(0.35,0.95,1.0,0.55)
var _trail_sprites:Array[Sprite2D] = []

func _ready() -> void:
	top_level = true
	global_position = anchor
	global_rotation = axis.angle()
	global_scale = Vector2.ONE
	add_to_group("DiamondSpearVisual")
	if piercing:
		# Three reused silhouettes per echo, not a new node every frame.
		for i:int in range(3):
			var trail := Sprite2D.new()
			trail.texture = caster.image.texture
			trail.rotation = caster.NATIVE_ROTATION_OFFSET
			trail.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			trail.scale = visual_scale
			trail.z_as_relative = false
			trail.z_index = 1
			trail.visible = false
			add_child(trail)
			_trail_sprites.append(trail)
	sprite = Sprite2D.new()
	sprite.texture = caster.image.texture
	sprite.rotation = caster.NATIVE_ROTATION_OFFSET
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = visual_scale
	sprite.modulate = tint
	sprite.z_as_relative = false
	sprite.z_index = 2
	add_child(sprite)
	previous_tip = anchor + axis * tip_distance
	_floor_stroke_limit = stroke_distance
	if piercing:
		var regions:Array = caster._floor_regions()
		if not regions.is_empty():
			var steps:int = maxi(1,int(ceil(stroke_distance/4.0)))
			for i:int in range(steps+1):
				var distance:float = stroke_distance*float(i)/steps
				if not caster._on_floor(anchor+axis*distance,axis,regions):
					_floor_stroke_limit = stroke_distance*float(maxi(i-1,0))/steps
					break
	_refresh_wall_limit()

func _refresh_wall_limit() -> void:
	_wall_stroke_limit = minf(stroke_distance,_floor_stroke_limit)
	if not attack_echo: return
	var query := PhysicsRayQueryParameters2D.create(anchor,anchor+axis*(tip_distance+stroke_distance+2.2),1,[caster.get_rid()])
	var hit:Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_wall_stroke_limit = minf(_wall_stroke_limit,clampf(anchor.distance_to(hit.position)-tip_distance-2.2,0.0,stroke_distance))

func _stroke_offset_at(time:float) -> float:
	if piercing:
		# Monotonic one-way passage: no retracting through the enemy for another hit.
		return minf(stroke_distance*smoothstep(0.0,1.0,clampf(time/maxf(stroke_duration,0.001),0.0,1.0)),_wall_stroke_limit)
	return minf(caster.thrust_offset_at(time,stroke_duration,stroke_distance),_wall_stroke_limit)

func _physics_process(delta:float) -> void:
	if not is_instance_valid(caster) or caster.is_queued_for_deletion() or caster.health <= 0:
		queue_free()
		return
	if not caster.is_combat_runtime_active(): return
	var allowed:bool = caster.Can_Skill if requires_skill else caster.Can_Attack
	if attack_echo and (caster.dizziness or caster.is_damage_output_disabled() or not allowed):
		queue_free()
		return
	previous_elapsed = elapsed
	elapsed += delta
	_refresh_wall_limit()
	_render_at(elapsed)
	var damage_end:float = stroke_duration if piercing else stroke_duration*0.70
	if attack_echo and caster.is_multiplayer_authority() and previous_elapsed<damage_end:
		var end_time:float = minf(elapsed,damage_end)
		var peak_time:float = stroke_duration*0.22
		# Ordinary elastic strokes must still visit their peak when a coarse frame skips it.
		if not piercing and previous_elapsed<peak_time and end_time>=peak_time:
			var peak_tip:Vector2 = anchor+axis*(tip_distance+_stroke_offset_at(peak_time))
			caster.damage_segment(previous_tip,peak_tip,2.2,multiplier,hit_ids,0.0,anchor,accent)
			previous_tip = peak_tip
		var tip:Vector2 = anchor+axis*(tip_distance+_stroke_offset_at(end_time))
		caster.damage_segment(previous_tip,tip,2.2,multiplier,hit_ids,0.0,anchor,accent)
		previous_tip = tip
	if elapsed>=lifetime: queue_free()

func _process(_delta:float) -> void:
	if not is_instance_valid(caster) or caster.health<=0 or not caster.is_combat_runtime_active(): return
	_render_at(lerpf(previous_elapsed,elapsed,Engine.get_physics_interpolation_fraction()))

func _render_at(time:float) -> void:
	var visual_time:float = clampf(time,0.0,lifetime)
	sprite.position.x = _stroke_offset_at(visual_time) if attack_echo else 0.0
	var fade_start:float = stroke_duration if piercing else stroke_duration*0.65
	var alpha:float = 1.0-smoothstep(fade_start,lifetime,visual_time)
	sprite.modulate.a = tint.a*alpha if attack_echo else tint.a*pow(1.0-visual_time/lifetime,1.25)
	for i:int in range(_trail_sprites.size()):
		var trail:Sprite2D = _trail_sprites[i]
		var delay:float = 0.012*float(i+1)
		trail.visible = visual_time>delay
		trail.position.x = _stroke_offset_at(maxf(visual_time-delay,0.0))
		trail.modulate = Color(tint.r,tint.g,tint.b,alpha*(0.24-float(i)*0.06))
